extends Node2D
class_name PlanetRoom
## 行星地表/内部的可进入场景基类。
##
## 星图（`scenes/map/map.tscn`）是空的航道枢纽；玩家走进某颗行星时载入对应的
## PlanetRoom 场景，因此每颗星球可以有自己的地形、建筑与谜题，互不干扰。
##
## 本基类提供所有星球共用的东西：玩家移动与碰撞、视野经济与扫描、摩斯电码输入台、
## 建筑显隐与点亮、知识地图/结局覆盖层、反馈文本与顶部 HUD。
## 子类只需要实现 `_build_room()` 摆放自己的地形与建筑，并按需覆写 `_observe_text()`。

signal feedback(text: String)
signal location_changed(room_id: StringName, layer: StringName)
## 玩家走到出口时发出，由星图接住并返回航道
signal exit_requested
## 请求切换层级（-1 上一层，+1 下一层），由星图决定是否允许
signal layer_change_requested(step: int)
## 摩斯发送判定完成，携带 SunLanguage.verify() 的结果
signal morse_sent(outcome: Dictionary)

const KNOWLEDGE_MAP := preload("res://scenes/ui/knowledge/knowledge_map.tscn")
const ENDING_PANEL := preload("res://scenes/ui/ending/ending_panel.tscn")
const BUILDING_SCRIPT := preload("res://scripts/map/map_building.gd")
const OBSTACLE_SCRIPT := preload("res://scripts/map/map_obstacle.gd")

## 本房间在 WorldState 里使用的场景标识（用于太阳语判定）
@export var room_id: StringName = &"mercury_1"
## 顶部显示的行星名与层，例如「水星 · 2 层」
@export var display_name: String = "未知行星"
@export var layer_name: String = "地表"
## 房间可行走范围（矩形，超出即视为出口边界）
@export var room_size: Vector2 = Vector2(2400.0, 1600.0)
## 视野与扫描
@export var base_vision_radius: float = 420.0
@export var scan_vision_radius: float = 1100.0
@export_range(0.2, 10.0, 0.1) var scan_duration: float = 1.6
@export_range(0.0, 20.0, 0.5) var scan_cooldown: float = 1.4
## 与塔/特殊对象的交互半径
@export var interaction_radius: float = 420.0
## 摩斯电码相关的按钮（电码键 / 等待键 / 发送）是否默认显示。
## 设计稿要求它们只在「有东西可发送」的地方出现：赤阳之塔内、太阳外层的发送台。
## 行星地表默认隐藏，靠近发送对象时由 `set_morse_available()` 打开。
@export var morse_enabled: bool = false
## 是否允许摩斯发送（太阳外层、塔附近等）
@export var morse_send_allowed: bool = true
## 出口位置（走到附近并按 E 返回航道）
@export var exit_position: Vector2 = Vector2(120.0, 120.0)

@onready var _player: CharacterBody2D = $Player
@onready var _camera: Camera2D = $Player/Camera2D
@onready var _buildings: Node2D = $Buildings
@onready var _obstacles: Node2D = $Obstacles

var vision := MapVision.new()
var morse := MorseInput.new()
var _scan_cooldown_left: float = 0.0
var _lit_buildings: Array[MapBuilding] = []
var _room_built: bool = false

var _layer_label: Label
var _clock_label: Label
var _status_label: Label
var _morse_label: Label
var _feedback_label: RichTextLabel
var _scan_button: Button
var _morse_button: Button
var _wait_button: Button
var _send_button: Button
var _layer_up_button: Button
var _layer_down_button: Button
var _hud: CanvasLayer
var _knowledge_map: Control
var _ending_panel: Control


func _ready() -> void:
	vision.set_base_radius(base_vision_radius)
	vision.set_scan_radius(scan_vision_radius)
	_build_hud()
	_wire_input()
	_build_boundaries()
	_build_room()
	# 子类在 _build_room() 里才会写 display_name / layer_name / morse_enabled，
	# 因此 HUD 建好之后要再同步一次，否则顶部会一直显示占位名、按钮可见性也不对。
	_sync_hud_identity()
	set_morse_available(morse_enabled)
	_room_built = true
	_collect_buildings()
	_refresh_visibility()
	_refresh_hud()


## 子类在这里摆放地形与建筑；基类已经在 _ready 里调好视野与 HUD
func _build_room() -> void:
	pass


func _process(delta: float) -> void:
	vision.tick(delta)
	if _scan_cooldown_left > 0.0:
		_scan_cooldown_left = maxf(0.0, _scan_cooldown_left - delta)
	morse.tick(delta)
	_refresh_visibility()
	_refresh_hud()


## ---------- 世界查询（供子类与测试） ----------

func player() -> CharacterBody2D:
	return _player


func is_ready_for_input() -> bool:
	return _room_built and not get_tree().paused


func current_planet() -> StringName:
	return room_id


func current_layer() -> StringName:
	return StringName(layer_name)


func room_rect() -> Rect2:
	return Rect2(Vector2.ZERO, room_size)


## ---------- 建筑 ----------

## 在房间局部坐标放一个建筑；layer 留空表示跟随本房间
func add_building(
		building_id: String,
		kind: StringName,
		position: Vector2,
		layer: StringName = &"",
		visible_in_base_vision: bool = true,
		has_generator: bool = true,
		lit_radius: float = 320.0) -> MapBuilding:
	var building := BUILDING_SCRIPT.new() as MapBuilding
	building.name = building_id
	building.building_id = StringName(building_id)
	building.kind = kind
	building.position = position
	building.layer = layer if layer != &"" else current_layer()
	building.visible_in_base_vision = visible_in_base_vision
	building.has_generator = has_generator
	building.lit_vision_radius = lit_radius
	# 碰撞形状：Area2D 需要形状才能被点击
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 56.0
	shape.shape = circle
	building.add_child(shape)
	var label := Label.new()
	label.name = "Label"
	label.position = Vector2(0.0, 40.0)
	label.add_theme_font_size_override(&"font_size", 26)
	label.text = building.display_name()
	building.add_child(label)
	_buildings.add_child(building)
	return building


## 放一个按层显隐的障碍（火星迷宫等）
func add_obstacle(obstacle_id: String, rect: Rect2, layer: StringName = &"") -> StaticBody2D:
	var body := OBSTACLE_SCRIPT.new() as StaticBody2D
	body.name = obstacle_id
	body.layer = layer if layer != &"" else current_layer()
	body.position = rect.position + rect.size * 0.5
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	body.add_child(shape)
	_obstacles.add_child(body)
	return body


## 房间四周的墙：防止玩家走出地图，属于本层常驻障碍
func _build_boundaries() -> void:
	var thickness := 80.0
	var size := room_size
	add_obstacle("bound_top", Rect2(0.0, -thickness, size.x, thickness))
	add_obstacle("bound_bottom", Rect2(0.0, size.y, size.x, thickness))
	add_obstacle("bound_left", Rect2(-thickness, 0.0, thickness, size.y))
	add_obstacle("bound_right", Rect2(size.x, 0.0, thickness, size.y))


func collect_buildings() -> void:
	_collect_buildings()


func _collect_buildings() -> void:
	_lit_buildings.clear()
	for node in get_tree().get_nodes_in_group(&"map_building"):
		var building := node as MapBuilding
		if building == null or not is_ancestor_of(building):
			continue
		if building.lit:
			_lit_buildings.append(building)
		if not building.clicked.is_connected(_on_building_clicked):
			building.clicked.connect(_on_building_clicked)
		if not building.generator_activated.is_connected(_on_building_activated):
			building.generator_activated.connect(_on_building_activated)


func _refresh_visibility() -> void:
	if not is_inside_tree():
		return
	var player_position := _player.global_position
	for node in get_tree().get_nodes_in_group(&"map_building"):
		var building := node as MapBuilding
		if building == null or not is_ancestor_of(building):
			continue
		var reachable := vision.is_reachable(player_position, building.global_position, _lit_buildings)
		if vision.is_scanning() and reachable:
			building.reveal_by_scan()
		building.visible = building.is_visible_to(reachable)


## ---------- 扫描 ----------

func scan() -> bool:
	if _scan_cooldown_left > 0.0:
		feedback.emit("扫描尚未就绪。")
		return false
	vision.begin_scan(scan_duration)
	_scan_cooldown_left = scan_duration + scan_cooldown
	_refresh_visibility()
	feedback.emit("扫描：视野扩大到 %.0f，持续 %.1f 秒。" % [scan_vision_radius, scan_duration])
	return true


## ---------- 建筑交互 ----------

func _on_building_clicked(building: MapBuilding) -> void:
	if not vision.is_reachable(_player.global_position, building.global_position, _lit_buildings):
		feedback.emit("你还没有观察到那里。")
		return
	if _handle_building_interaction(building):
		return
	if building.has_generator and not building.lit:
		if building.light_up():
			_lit_buildings.append(building)
			WorldState.apply_changes({&"lit_" + String(building.building_id): true})
			WorldState.record_knowledge(&"lit_" + String(building.building_id))
			feedback.emit("%s 的发电机启动，建筑被点亮。" % [building.display_name()])
			_refresh_visibility()
			return
	feedback.emit(_observe_text(building))


func _on_building_activated(building: MapBuilding) -> void:
	if not _lit_buildings.has(building):
		_lit_buildings.append(building)


## 子类覆写：返回 true 表示已经处理，基类不再走点亮/观察流程
func _handle_building_interaction(_building: MapBuilding) -> bool:
	return false


## 子类覆写：本房间的观察文本
func _observe_text(building: MapBuilding) -> String:
	return "你观察到%s，但这里暂时没有新的线索。" % [building.display_name()]


func lit_buildings() -> Array[MapBuilding]:
	# 以建筑自身的 lit 状态为准重新收集：玩家是在运行中逐个点亮发电机的，
	# 只依赖初始化时的缓存会漏掉后来的灯（地球的灯谜就依赖这份实时列表）。
	var result: Array[MapBuilding] = []
	for node in get_tree().get_nodes_in_group(&"map_building"):
		var building := node as MapBuilding
		if building != null and is_ancestor_of(building) and building.lit:
			result.append(building)
	_lit_buildings = result
	return result


## ---------- 摩斯电码 ----------

func press_morse() -> void:
	morse.press()
	_refresh_morse()


func release_morse() -> void:
	morse.release()
	_refresh_morse()


func separator_morse() -> void:
	if morse.separator():
		_refresh_morse()


func clear_morse() -> void:
	morse.clear()
	_refresh_morse()
	feedback.emit("已清空输入。")


## 知识的键名 → 是否已获得，供 SunLanguage.verify 判定
func knowledge_snapshot() -> Dictionary:
	var result := {}
	for word in SunLanguage.WORDS:
		var key := SunLanguage.word_knowledge_key(word)
		if key.is_empty():
			continue
		result[key] = WorldState.knows(key)
	return result


## 发送当前输入并立刻判定（供 UI 与测试共用）
func send_morse() -> Dictionary:
	var outcome := _verify_current()
	if morse.is_empty():
		feedback.emit("还没有输入任何电码。")
	if outcome.is_empty():
		return {}
	morse_sent.emit(outcome)
	morse.clear()
	return outcome


func _verify_current() -> Dictionary:
	var tokens := morse.effective_tokens()
	if tokens.is_empty():
		return {}
	if not morse_enabled:
		feedback.emit("这里发不出电码。")
		return {}
	return SunLanguage.verify(tokens, room_id, knowledge_snapshot())


## 把判定结果转成一句话，子类可以直接用或改写
func describe_outcome(outcome: Dictionary) -> String:
	if outcome.is_empty():
		return ""
	match int(outcome["result"]):
		SunLanguage.Result.UNKNOWN:
			return "错误的电码。太阳返回一段回应：疑惑。"
		SunLanguage.Result.LOCKED:
			return "电码是对的，但你还读不懂它。（%s）" % [SunLanguage.word_hint(outcome["word"])]
		SunLanguage.Result.WRONG_CONTEXT:
			return "这串太阳语不属于这里。"
		SunLanguage.Result.SUCCESS:
			return "你送出了「%s」。" % [SunLanguage.word_text(StringName(outcome["word"]))]
	return ""


## ---------- 覆盖层 ----------

## 打开知识地图；由本房间自己持有实例，任何行星里都能查
func toggle_knowledge_map() -> void:
	if _knowledge_map.visible:
		_knowledge_map.close()
		return
	_knowledge_map.open()


func show_ending() -> void:
	if _ending_panel.visible:
		return
	_ending_panel.open(knowledge_snapshot())


## ---------- 输入 ----------

func _wire_input() -> void:
	_scan_button.pressed.connect(func() -> void: scan())
	_morse_button.button_down.connect(press_morse)
	_morse_button.button_up.connect(release_morse)
	_wait_button.pressed.connect(separator_morse)
	_send_button.pressed.connect(func() -> void: send_morse())
	feedback.connect(func(text: String) -> void: _feedback_label.text = text)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_K:
			toggle_knowledge_map()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"ui_accept"):
		interact()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# 覆盖层打开时吞掉全部输入，避免玩家在查看知识树时还在移动
	if _knowledge_map != null and _knowledge_map.visible:
		get_viewport().set_input_as_handled()
		return
	if _ending_panel != null and _ending_panel.visible:
		if event.is_action_pressed(&"pause_game") or event.is_action_pressed(&"ui_accept"):
			_ending_panel.close()
		get_viewport().set_input_as_handled()


## 与最近的建筑/出口交互
func interact() -> void:
	if _player.global_position.distance_to(exit_position) <= 120.0:
		request_exit()
		return
	var target := nearest_building()
	if target == null:
		feedback.emit("附近没有可以交互的东西。")
		return
	target.clicked.emit(target)


func nearest_building() -> MapBuilding:
	var best: MapBuilding = null
	var best_distance := interaction_radius
	for node in get_tree().get_nodes_in_group(&"map_building"):
		var building := node as MapBuilding
		if building == null or not is_ancestor_of(building) or not building.visible:
			continue
		var distance := _player.global_position.distance_to(building.global_position)
		if distance < best_distance:
			best_distance = distance
			best = building
	return best


## 请求离开本行星，回到航道枢纽
func request_exit() -> void:
	exit_requested.emit()


## 请求切换层级；-1 上一层，+1 下一层。星图负责判定并重新载入房间。
func request_layer_step(step: int) -> void:
	if step == 0:
		return
	layer_change_requested.emit(step)


## 给房间追加一个 HUD 按钮（子类用来放自己特有的操作，例如进入赤阳之塔）
func add_hud_button(text: String, on_pressed: Callable) -> Button:
	var button := _make_button(text)
	button.pressed.connect(on_pressed)
	var bar := _hud.get_node_or_null("ActionBar")
	if bar == null:
		# 按钮栏是 HUD 下第一个 HBoxContainer
		for child in _hud.get_children():
			if child is HBoxContainer:
				bar = child
				break
	if bar != null:
		bar.add_child(button)
	return button


## 打开/关闭摩斯系列按钮（电码键 / 等待键 / 发送）。
## 设计稿要求它们只在能发送的地方出现，因此默认隐藏，由子类或交互打开。
func set_morse_available(available: bool) -> void:
	morse_enabled = available
	if _morse_button != null:
		_morse_button.visible = available
	if _wait_button != null:
		_wait_button.visible = available
	if _send_button != null:
		_send_button.visible = available and morse_send_allowed
	if not available and morse != null:
		morse.clear()
		_refresh_morse()


func morse_available() -> bool:
	return morse_enabled


## 星图告诉本房间「能不能换层」，用于禁用按钮
func set_layer_availability(up_allowed: bool, down_allowed: bool) -> void:
	if _layer_up_button != null:
		_layer_up_button.disabled = not up_allowed
	if _layer_down_button != null:
		_layer_down_button.disabled = not down_allowed


## 只有一层的行星（地球、太阳）不该看到上下层按钮，直接整组隐藏
func set_layer_buttons_visible(shown: bool) -> void:
	if _layer_up_button != null:
		_layer_up_button.visible = shown
	if _layer_down_button != null:
		_layer_down_button.visible = shown


func layer_buttons_visible() -> bool:
	return _layer_up_button != null and _layer_up_button.visible


## ---------- HUD ----------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "HUD"
	add_child(_hud)
	var header := PanelContainer.new()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 24.0
	header.offset_top = 18.0
	header.offset_right = -24.0
	header.offset_bottom = 90.0
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(header)
	var content := Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(content)
	var name_label := _make_label("%s · %s" % [display_name, layer_name], 26)
	name_label.name = "PlanetNameLabel"
	name_label.position = Vector2(12.0, 8.0)
	_clock_label = _make_label("第 1 轮 · 00:00", 26)
	_clock_label.position = Vector2(420.0, 8.0)
	_layer_label = _make_label("", 24)
	_layer_label.position = Vector2(900.0, 8.0)
	content.add_child(name_label)
	content.add_child(_clock_label)
	content.add_child(_layer_label)

	_status_label = _make_label("", 24)
	_status_label.position = Vector2(32.0, 100.0)
	_hud.add_child(_status_label)
	_morse_label = _make_label("", 30)
	_morse_label.position = Vector2(32.0, 140.0)
	_hud.add_child(_morse_label)
	# 反馈区用可滚动富文本：AI 对话与观察文本可能很长，Label 会被截断
	_feedback_label = RichTextLabel.new()
	_feedback_label.name = "FeedbackLabel"
	_feedback_label.bbcode_enabled = false
	_feedback_label.scroll_active = true
	_feedback_label.scroll_following = true
	_feedback_label.fit_content = false
	_feedback_label.add_theme_font_size_override(&"normal_font_size", 26)
	_feedback_label.position = Vector2(32.0, 760.0)
	_feedback_label.size = Vector2(1400.0, 180.0)
	_feedback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_feedback_label)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 24.0
	bar.offset_top = -92.0
	bar.offset_right = -24.0
	bar.offset_bottom = -24.0
	bar.add_theme_constant_override(&"separation", 16)
	bar.name = "ActionBar"
	_hud.add_child(bar)
	_scan_button = _make_button("扫描（Tab）")
	_morse_button = _make_button("电码键：短按=点 长按=划")
	_wait_button = _make_button("等待键：分段")
	_send_button = _make_button("发送")
	# 层级导航：上层 / 下层，能否走由星图判定（水星 3→4 需要核心露出）
	_layer_up_button = _make_button("上一层")
	_layer_up_button.pressed.connect(func() -> void: request_layer_step(-1))
	_layer_down_button = _make_button("下一层")
	_layer_down_button.pressed.connect(func() -> void: request_layer_step(1))
	var back_button := _make_button("返回宇宙地图")
	back_button.pressed.connect(request_exit)
	var knowledge_button := _make_button("知识地图（K）")
	knowledge_button.pressed.connect(toggle_knowledge_map)
	for button in [_layer_up_button, _layer_down_button, back_button, _scan_button,
			_morse_button, _wait_button, _send_button, knowledge_button]:
		bar.add_child(button)
	# 摩斯系列按钮默认隐藏，只在可以发送的地方出现（子类用 set_morse_available 打开）
	set_morse_available(morse_enabled)

	_knowledge_map = KNOWLEDGE_MAP.instantiate() as Control
	_knowledge_map.visible = false
	_hud.add_child(_knowledge_map)
	_ending_panel = ENDING_PANEL.instantiate() as Control
	_ending_panel.visible = false
	_hud.add_child(_ending_panel)


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## 顶部左上角显示「行星 · 层」；子类在 _build_room() 里写的名字在这里生效
func _sync_hud_identity() -> void:
	if _hud == null:
		return
	var label := _hud.find_child("PlanetNameLabel", true, false) as Label
	if label != null:
		label.text = "%s · %s" % [display_name, layer_name]


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 56.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_to_group(&"cursor_frame_target")
	return button


func _refresh_hud() -> void:
	if _clock_label == null:
		return
	_sync_hud_identity()
	_clock_label.text = "第 %d 轮 · %02d:%02d" % [
		WorldTime.loop_index, int(WorldTime.elapsed_seconds) / 60, int(WorldTime.elapsed_seconds) % 60]
	_status_label.text = "%s · %s" % [TerrainState.sun_stage_label(WorldState.get_flags()), vision.label()]
	_scan_button.disabled = _scan_cooldown_left > 0.0
	_scan_button.text = "扫描（Tab）" if _scan_cooldown_left <= 0.0 else "扫描冷却 %.1fs" % [_scan_cooldown_left]
	_morse_button.disabled = not morse_enabled
	_send_button.disabled = not morse_enabled
	_refresh_morse()


func _refresh_morse() -> void:
	if _morse_label == null:
		return
	if not morse_enabled:
		_morse_label.text = ""
		return
	_morse_label.text = "输入：" + (morse.display() if not morse.is_empty() else "—")
