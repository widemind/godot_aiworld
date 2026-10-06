extends Node
## 星图枢纽 + 行星房间的场景测试。
## headless 运行：Godot --headless --path . res://test/tests/star_map_scene_test.tscn

const MAP_SCENE := "res://scenes/map/map.tscn"
const ROOMS := {
	&"earth": "res://scenes/planets/planet_earth.tscn",
	&"mercury1": "res://scenes/planets/planet_mercury.tscn",
	&"mercury2": "res://scenes/planets/planet_mercury2.tscn",
	&"mercury3": "res://scenes/planets/planet_mercury3.tscn",
	&"mercury4": "res://scenes/planets/planet_mercury4.tscn",
	&"mars1": "res://scenes/planets/planet_mars.tscn",
	&"mars2": "res://scenes/planets/planet_mars2.tscn",
	&"sun": "res://scenes/planets/planet_sun.tscn",
}

var _passed: int = 0
var _failed: int = 0
var _map: Node2D


func _ready() -> void:
	await get_tree().process_frame
	var scene := load(MAP_SCENE)
	_check(scene != null, "星图场景可以加载")
	if scene == null:
		_finish()
		return
	_map = (scene as PackedScene).instantiate()
	add_child(_map)
	await get_tree().process_frame
	await get_tree().process_frame
	_test_hub()
	_test_hub_view()
	_test_knowledge_map()
	await _test_scan_wave()
	await _test_point_and_enter()
	await _test_rooms()
	await _test_layer_navigation()
	_test_ending_panel()
	_finish()


func _finish() -> void:
	print("STAR_MAP_SCENE_TESTS passed=%d failed=%d" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("STAR_MAP_SCENE_TEST FAILED: " + message)


func _test_hub() -> void:
	_check(_map.get_node_or_null("planets/earth") != null, "枢纽里有地球")
	_check(_map.get_node_or_null("planets/mercury") != null, "枢纽里有水星")
	_check(_map.get_node_or_null("planets/mars") != null, "枢纽里有火星")
	_check(_map.get_node_or_null("planets/sun") != null, "枢纽里有太阳")
	_check(_map.get_node_or_null("UI/ActionBar/Buttons/ScanButton") != null, "枢纽里有扫描按钮")
	_check(bool(WorldState.get_flag(&"in_space", false)), "开局位于航道")
	_check(_map.current_planet() == &"", "开局不在任何行星上")
	# 枢纽的主要操作：选中 → 进入，不要求玩家走到星球上
	_check(_map.selected_planet() != &"", "开局已经选中一颗行星")
	var first: StringName = _map.selected_planet()
	_map.cycle_selection(1)
	_check(_map.selected_planet() != first, "可以切换选中的行星")
	_map.cycle_selection(-1)
	_check(_map.selected_planet() == first, "切回来还是原来那颗")
	_check(_map.get_node_or_null("UI/ActionBar/Buttons/EnterButton") != null, "枢纽里有「进入」按钮")
	_check(_map.get_node_or_null("Selector") != null, "枢纽里有选中高亮圈")
	# 扫描
	_check(_map.scan(), "枢纽里可以扫描")
	_check(_map.vision.is_scanning(), "扫描进入扫描态")
	_check(not _map.scan(), "冷却期间不能重复扫描")
	_check(not _map.enter_planet(&"venus", 1), "不存在的行星进不去")


## 「选中 → 进入」这条主路径必须走得通
func _test_point_and_enter() -> void:
	_check(_map.current_room() == null, "此时在航道上")
	for planet_id in [&"earth", &"mercury", &"mars", &"sun"]:
		# 轮流切换直到选中目标（最多绕一圈）
		var guard := 0
		while _map.selected_planet() != planet_id and guard < 8:
			guard += 1
			_map.cycle_selection(1)
		_check(_map.selected_planet() == planet_id, "能选中%s" % [planet_id])
		_check(_map.enter_selected(), "选中%s后可以进入" % [planet_id])
		var room: Node = _map.current_room()
		_check(room != null, "%s 已经载入" % [planet_id])
		if room != null:
			room.request_exit()
			await get_tree().process_frame
		if _map.current_room() != null:
			_map.current_room().request_exit()
			await get_tree().process_frame


func _test_knowledge_map() -> void:
	var knowledge: Control = _map.get_node_or_null("UI/KnowledgeMap")
	_check(knowledge != null, "枢纽里存在知识地图")
	if knowledge == null:
		return
	_check(not knowledge.visible, "知识地图默认隐藏")
	_map.toggle_knowledge_map()
	_check(knowledge.visible, "可以打开知识地图")
	var canvas: Control = knowledge.get_node_or_null("%KnowledgeCanvas")
	_check(canvas != null and canvas.get_child_count() > 10, "知识树画布生成了节点与分支")
	_map.toggle_knowledge_map()
	_check(not knowledge.visible, "可以关闭知识地图")
	# 打开后必须能被自己关掉（曾出现关不掉的问题）
	knowledge.open()
	_check(knowledge.visible, "可以再次打开")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	knowledge._input(escape)
	_check(not knowledge.visible, "Esc 能关闭知识地图")


## 扫描：波形从中心扩张，波前扫过的行星逐个浮现，并给出结果
func _test_scan_wave() -> void:
	var wave: Line2D = _map.get_node_or_null("planets/ScanWave") as Line2D
	_check(wave != null, "星图里有扫描波形节点")
	_check(_map.get_node_or_null("UI/ScanResult") != null, "星图里有扫描结果面板")
	# 等冷却走完再扫一次
	await get_tree().create_timer(_map.scan_duration + _map.scan_cooldown + 0.2).timeout
	_check(_map.scan(), "冷却结束后可以扫描")
	if wave != null:
		_check(wave.visible, "扫描时波形可见")
	await get_tree().create_timer(_map.scan_duration + 0.3).timeout
	if wave != null:
		_check(not wave.visible, "波形结束后自动隐藏")
		_check(wave.scale.x > 100.0, "波形扩张到覆盖整张星图（scale=%.0f）" % [wave.scale.x])
	# 结果文本应当列出每一颗行星
	var result: Label = _map.get_node("UI/ScanResult")
	var text := result.text
	_check(text.contains("扫描结果"), "结果面板有标题")
	for name in ["地球", "水星", "火星", "太阳"]:
		_check(text.contains(name), "结果列出%s" % [name])
	_check(text.contains("相距"), "结果包含距离")


## 枢纽不需要人移动：玩家隐藏、相机固定并缩放成一屏
func _test_hub_view() -> void:
	var player: Node2D = _map.get_node("player")
	_check(not player.visible, "枢纽里玩家不显示（不需要移动）")
	var camera: Camera2D = _map.get_node("player/Camera2D")
	_check(camera != null, "存在固定相机")
	var viewport := _map.get_viewport_rect().size
	for planet_id in [&"earth", &"mercury", &"mars", &"sun"]:
		var planet: Node2D = _map.planet_node(planet_id)
		if planet == null:
			continue
		var screen := (planet.global_position - camera.global_position) * camera.zoom + viewport * 0.5
		_check(screen.x > 0.0 and screen.x < viewport.x and screen.y > 0.0 and screen.y < viewport.y,
			"%s 在屏幕内（%.0f, %.0f）" % [planet_id, screen.x, screen.y])


func _test_rooms() -> void:
	var player: Node2D = _map.get_node("player")
	for planet_id in [&"earth", &"mercury", &"mars", &"sun"]:
		var planet: Node2D = _map.planet_node(planet_id)
		_check(planet != null, "枢纽里能找到%s" % [planet_id])
		if planet == null:
			continue
		# 走到行星旁边才能进入
		player.global_position = planet.global_position + Vector2(0.0, 150.0)
		_check(_map.planet_in_reach(planet_id), "%s 在交互范围内" % [planet_id])
		_check(_map.enter_planet(planet_id, 1), "可以进入%s" % [planet_id])
		var room: Node = _map.current_room()
		_check(room != null, "%s 房间已载入" % [planet_id])
		if room == null:
			continue
		await get_tree().process_frame
		# 房间自己的结构
		_check(room.get_node_or_null("Player") != null, "%s 房间里有玩家" % [planet_id])
		_check(room.get_node_or_null("Buildings") != null, "%s 房间里有建筑容器" % [planet_id])
		_check(room.get_node_or_null("Obstacles") != null, "%s 房间里有障碍容器" % [planet_id])
		_check(room.get_node_or_null("HUD") != null, "%s 房间里有自己的 HUD" % [planet_id])
		# 「返回宇宙地图」按钮必须存在，并且真的能回到航道
		var back := _find_button(room.get_node("HUD"), "返回宇宙地图")
		_check(back != null, "%s 房间里有返回宇宙地图按钮" % [planet_id])
		# 摩斯系列按钮只在能发送的地方出现
		var morse_btn := _find_button(room.get_node("HUD"), "电码键")
		var should_show_morse: bool = planet_id == &"sun"
		_check(morse_btn != null and morse_btn.visible == should_show_morse,
			"%s 的电码键可见性=%s（应为 %s）" % [planet_id, morse_btn != null and morse_btn.visible, should_show_morse])
		# 只有一层的行星（地球、太阳）不该看到上下层按钮
		var wants_layers: bool = planet_id == &"mercury" or planet_id == &"mars"
		var up_btn := _find_button(room.get_node("HUD"), "上一层")
		_check(up_btn != null and up_btn.visible == wants_layers,
			"%s 的上下层按钮可见性=%s（应为 %s）" % [planet_id, up_btn != null and up_btn.visible, wants_layers])
		if not wants_layers:
			_check(not room.layer_buttons_visible(), "%s 不显示上下层按钮" % [planet_id])
		# 顶部显示真实行星名，不是「未知行星」
		var name_label := _find_label_starting_with(room.get_node("HUD"), "地球")
		if planet_id == &"earth":
			_check(name_label != null, "地球房间顶部显示地球而不是未知行星")
		_check(room.display_name != "未知行星", "%s 房间设置了行星名（%s）" % [planet_id, room.display_name])
		var buildings := room.get_node("Buildings").get_child_count()
		_check(buildings >= 1, "%s 房间里放了建筑（%d 个）" % [planet_id, buildings])
		# 房间可以扫描与返回
		_check(room.scan(), "%s 房间可以扫描" % [planet_id])
		room.request_exit()
		await get_tree().process_frame
		_check(_map.current_room() == null, "离开%s后回到航道" % [planet_id])
		_check(bool(WorldState.get_flag(&"in_space", false)), "回到航道后标记为太空")


## 行星内的「上一层 / 下一层」按钮：能走就走，不能走就禁掉并给出原因
func _test_layer_navigation() -> void:
	# 水星 1 层：可以下一层，不能上一层
	_check(_map.enter_planet(&"mercury", 1), "进入水星 1 层")
	var room: Node = _map.current_room()
	_check(room != null, "水星 1 层已载入")
	if room == null:
		return
	var hud: CanvasLayer = room.get_node("HUD")
	var up := _find_button(hud, "上一层")
	var down := _find_button(hud, "下一层")
	_check(up != null and down != null, "水星 1 层有上层/下层按钮")
	if up == null or down == null:
		return
	_check(up.disabled, "1 层不能再上一层")
	_check(not down.disabled, "1 层可以下到 2 层")
	# 走下一层
	room.request_layer_step(1)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_map.current_room() != null, "切层后仍有房间")
	_check(int(_map.current_layer()) == 2, "已经在水星 2 层（%s）" % [_map.current_layer()])
	var room2: Node = _map.current_room()
	var up2 := _find_button(room2.get_node("HUD"), "上一层")
	_check(up2 != null and not up2.disabled, "2 层可以回上一层")
	# 回上一层
	room2.request_layer_step(-1)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(int(_map.current_layer()) == 1, "回到了水星 1 层")
	# 3 → 4 需要核心露出，未满足时下一层按钮应当是禁用的
	var room3: Node = _map.current_room()
	room3.request_layer_step(1)
	await get_tree().process_frame
	await get_tree().process_frame
	var room_2: Node = _map.current_room()
	room_2.request_layer_step(1)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(int(_map.current_layer()) == 3, "已经在水星 3 层")
	var room3b: Node = _map.current_room()
	var down3 := _find_button(room3b.get_node("HUD"), "下一层")
	_check(down3 != null and down3.disabled, "核心未露出时 3 层的下一层被禁用")
	room3b.request_layer_step(1)
	await get_tree().process_frame
	_check(int(_map.current_layer()) == 3, "被拒绝后仍停在 3 层")
	# 核心露出后可以下到 4 层
	WorldState.apply_changes({&"mercury_core_open": true, &"mercury_boiling": true})
	_map.switch_layer(3)
	await get_tree().process_frame
	var room3c: Node = _map.current_room()
	_map._apply_room_layer_buttons(3)
	await get_tree().process_frame
	var down3c := _find_button(room3c.get_node("HUD"), "下一层")
	_check(down3c != null and not down3c.disabled, "核心露出后 3 层可以下到 4 层")
	room3c.request_layer_step(1)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(int(_map.current_layer()) == 4, "进入了水星 4 层（核心）")
	# 火星：1 → 2 必须走地图上的洞口，按钮应当禁用
	var room4: Node = _map.current_room()
	room4.request_exit()
	await get_tree().process_frame
	_check(_map.enter_planet(&"mars", 1), "进入火星 1 层")
	var mars_room: Node = _map.current_room()
	var mars_down := _find_button(mars_room.get_node("HUD"), "下一层")
	_check(mars_down != null and mars_down.disabled,
		"火星 1 层不能直接下到 2 层（要走洞口）[mars_layer=%d allowed=%s]" % [
			int(_map.current_layer()), _map._layer_allowed(&"mars", 2)])
	mars_room.request_layer_step(1)
	await get_tree().process_frame
	_check(int(_map.current_layer()) == 1, "火星被拒绝后仍停在 1 层")
	if _map.current_room() != null:
		_map.current_room().request_exit()
		await get_tree().process_frame


## 在房间 HUD 的按钮栏里按文字找按钮
func _find_button(hud: Node, text: String) -> Button:
	for node in hud.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and button.text.contains(text):
			return button
	return null


## 找以某段文字开头的 Label（顶部行星名用）
func _find_label_starting_with(hud: Node, prefix: String) -> Label:
	for node in hud.find_children("*", "Label", true, false):
		var label := node as Label
		if label != null and label.text.begins_with(prefix):
			return label
	return null


func _test_ending_panel() -> void:
	var ending: Control = _map.get_node_or_null("UI/EndingPanel")
	_check(ending != null, "枢纽里有结局界面")
	if ending == null:
		return
	_check(not ending.visible, "结局默认隐藏")
	var known: Dictionary = ending.ending_text({&"mercury_is_simulation": true})
	var unknown: Dictionary = ending.ending_text({})
	_check(known["body"] != unknown["body"], "已知模拟与否给出不同结局文本")
	_map.show_ending()
	_check(ending.visible, "可以弹出结局")
	ending.close()
	_check(not ending.visible, "结局可以关闭")
	# 每颗行星房间也要能弹出结局（太阳外层是真正触发点）
	var room_scene := load(ROOMS[&"sun"]) as PackedScene
	_check(room_scene != null, "太阳房间场景可以加载")
	if room_scene == null:
		return
	var room: Node = room_scene.instantiate()
	add_child(room)
	await get_tree().process_frame
	_check(room.ultimate_sent() == false, "太阳房间开局没有送出终极太阳语")
	room.show_ending()
	var room_ending: Control = room.get_node_or_null("HUD/EndingPanel")
	_check(room_ending != null and room_ending.visible, "太阳房间内也能弹出结局")
	room.queue_free()
