extends Node2D
## 星图（航道枢纽）：移动、扫描、进入行星。
##
## 玩家在星图上只是「在轨道间移动」；走进某颗行星时载入对应的 PlanetRoom 场景
## （`scenes/planets/*.tscn`），因此每颗星球有自己的地形、建筑与谜题。
## 时间与进度仍全部走常驻服务（WorldTime / WorldState / WorldJourney），星图不另建时钟。

signal location_changed(planet_id: StringName, layer: StringName)
signal feedback(text: String)
signal room_entered(room: Node)

const VIRTUAL_TIMELINE := preload("res://resources/time/timeline.tres")
const REAL_TIMELINE := preload("res://resources/time/real_timeline.tres")
const KNOWLEDGE_MAP := preload("res://scenes/ui/knowledge/knowledge_map.tscn")
const ENDING_PANEL := preload("res://scenes/ui/ending/ending_panel.tscn")

## 星图的世界范围与中心：相机固定在这里，保证整张图一屏可见
const WORLD_SIZE := Vector2(2100.0, 1260.0)
const WORLD_CENTER := Vector2(960.0, 560.0)

## 行星 → 该行星的入口场景（水星按层给不同场景）
const PLANET_ROOMS: Dictionary = {
	&"earth": ["res://scenes/planets/planet_earth.tscn"],
	&"mercury": [
		"res://scenes/planets/planet_mercury.tscn",
		"res://scenes/planets/planet_mercury2.tscn",
		"res://scenes/planets/planet_mercury3.tscn",
		"res://scenes/planets/planet_mercury4.tscn",
	],
	&"mars": [
		"res://scenes/planets/planet_mars.tscn",
		"res://scenes/planets/planet_mars2.tscn",
	],
	&"sun": ["res://scenes/planets/planet_sun.tscn"],
}

## 星图上的视野与扫描（决定能看清哪些行星）
@export var base_vision_radius: float = 700.0
@export var scan_vision_radius: float = 2000.0
@export_range(0.2, 10.0, 0.1) var scan_duration: float = 1.6
@export_range(0.0, 20.0, 0.5) var scan_cooldown: float = 1.3
@export var space_zoom: float = 1.0

@onready var _player: CharacterBody2D = $player
@onready var _camera: Camera2D = $player/Camera2D
@onready var _planets: Node2D = $planets
@onready var _ui_layer: CanvasLayer = $UI
@onready var _scan_button: Button = $UI/ActionBar/Buttons/ScanButton
@onready var _knowledge_button: Button = $UI/ActionBar/Buttons/KnowledgeButton
@onready var _planet_label: Label = $UI/Header/Content/PlanetLabel
@onready var _clock_label: Label = $UI/Header/Content/ClockLabel
@onready var _layer_label: Label = $UI/Header/Content/LayerLabel
@onready var _status_label: Label = $UI/StatusLabel
@onready var _feedback_label: Label = $UI/FeedbackLabel
@onready var _result_label: Label = $UI/ScanResult
@onready var _enter_button: Button = $UI/ActionBar/Buttons/EnterButton
@onready var _prev_button: Button = $UI/ActionBar/Buttons/PrevButton
@onready var _next_button: Button = $UI/ActionBar/Buttons/NextButton
## 选中行星的高亮圈
var _selector: Line2D
## 扫描波形：从中心向外扩张的圆环
var _wave: Line2D
var _wave_progress: float = 1.0
## 一次扫描的波前已经扫过哪些行星，用于逐个「浮现」
var _wave_hits: Array[StringName] = []

## 当前选中的行星（枢纽用「选中 — 进入」的方式导航，不要求玩家精准走到星球上）
var _selected: StringName = &""
## 行星选择顺序，决定左右切换的次序
const PLANET_ORDER: Array[StringName] = [&"earth", &"mercury", &"mars", &"sun"]

var vision := MapVision.new()
var _scan_cooldown_left: float = 0.0
var _current_planet: StringName = &""
## 每颗行星各自记住自己所在层：否则从水星 3 层出来会污染火星的层级判定
var _planet_layers: Dictionary = {}
## 当前载入的行星房间（在轨道上时为 null）
var _room: Node = null
var _knowledge_map: Control
var _ending_panel: Control


func _ready() -> void:
	vision.set_base_radius(base_vision_radius)
	vision.set_scan_radius(scan_vision_radius)
	_ensure_journey()
	_wire_ui()
	_build_selector()
	_build_wave()
	_focus_space()
	_fit_camera()
	_select(&"earth")
	_refresh_hud()


## 枢纽不需要人移动：相机固定在星图中心，缩放让整张图一屏放得下
func _fit_camera() -> void:
	if _player != null:
		_player.hide()
	_camera.global_position = WORLD_CENTER
	var viewport := get_viewport_rect().size
	var fit := minf(viewport.x / WORLD_SIZE.x, viewport.y / WORLD_SIZE.y) * 0.88
	_camera.zoom = Vector2.ONE * maxf(fit, 0.05)


## 扫描波形：从星图中心向外扩张的圆环
func _build_wave() -> void:
	_wave = Line2D.new()
	_wave.name = "ScanWave"
	_wave.width = 6.0
	_wave.default_color = Color(0.55, 0.95, 1.0, 0.75)
	_wave.closed = true
	var points := PackedVector2Array()
	for index in 64:
		var angle := TAU * float(index) / 64.0
		points.append(Vector2(cos(angle), sin(angle)))
	_wave.points = points
	_wave.visible = false
	_planets.add_child(_wave)


## 选中行星的高亮圈：让玩家一眼看出「现在会进入哪颗」
func _build_selector() -> void:
	_selector = Line2D.new()
	_selector.name = "Selector"
	_selector.width = 4.0
	_selector.default_color = Color(0.6, 0.95, 1.0, 0.95)
	_selector.closed = true
	var points := PackedVector2Array()
	for index in 48:
		var angle := TAU * float(index) / 48.0
		points.append(Vector2(cos(angle), sin(angle)) * 200.0)
	_selector.points = points
	_selector.visible = false
	add_child(_selector)


## 选中某颗行星（切换目标）
func _select(planet_id: StringName) -> void:
	var planet := planet_node(planet_id)
	if planet == null:
		return
	_selected = planet_id
	if _selector != null:
		_selector.visible = true
		_selector.global_position = planet.global_position
	feedback.emit("目标：%s · 按 R 或「进入」前往" % [_planet_display_name(planet_id)])


func selected_planet() -> StringName:
	return _selected


## 切换目标（左右方向）
func cycle_selection(step: int) -> void:
	if PLANET_ORDER.is_empty():
		return
	var index := PLANET_ORDER.find(_selected)
	if index < 0:
		index = 0
	index = wrapi(index + step, 0, PLANET_ORDER.size())
	_select(PLANET_ORDER[index])


## 进入当前选中的行星；这就是枢纽的主要操作
func enter_selected() -> bool:
	if _room != null:
		return false
	if _selected == &"":
		feedback.emit("还没有选中任何行星。")
		return false
	# 水星默认进 1 层；如果已经解锁了更深层，进入时沿用上次所在层
	var layer := 1
	if _selected == &"mercury":
		var remembered := int(_planet_layers.get(&"mercury", 1))
		if _remembered_layer_allowed(remembered):
			layer = remembered
		else:
			_planet_layers[&"mercury"] = 1
	return enter_planet(_selected, layer)


func _remembered_layer_allowed(layer_index: int) -> bool:
	if layer_index <= 1:
		return true
	return _layer_allowed(&"mercury", layer_index)


## 星图是正式入口：首次进入时安装时间表并开始第一轮，之后只读取全局状态。
func _ensure_journey() -> void:
	if not WorldJourney.is_started() and WorldTime.phase == WorldTime.Phase.READY:
		if not WorldJourney.start(VIRTUAL_TIMELINE, REAL_TIMELINE):
			push_error("星图入口需要有效的虚拟世界与现实世界时间表。")


func _wire_ui() -> void:
	_scan_button.pressed.connect(func() -> void: scan())
	_knowledge_button.pressed.connect(toggle_knowledge_map)
	_enter_button.pressed.connect(enter_selected)
	_prev_button.pressed.connect(func() -> void: cycle_selection(-1))
	_next_button.pressed.connect(func() -> void: cycle_selection(1))
	feedback.connect(func(text: String) -> void: _feedback_label.text = text)
	_knowledge_map = KNOWLEDGE_MAP.instantiate() as Control
	_knowledge_map.visible = false
	_ui_layer.add_child(_knowledge_map)
	_ending_panel = ENDING_PANEL.instantiate() as Control
	_ending_panel.visible = false
	_ui_layer.add_child(_ending_panel)


func _process(delta: float) -> void:
	vision.tick(delta)
	if _scan_cooldown_left > 0.0:
		_scan_cooldown_left = maxf(0.0, _scan_cooldown_left - delta)
	_advance_wave(delta)
	_refresh_hud()


## 波形推进：半径按时间扩张，波前经过的行星逐个「浮现」并写进结果
func _advance_wave(delta: float) -> void:
	if _wave == null or _wave_progress >= 1.0:
		return
	_wave_progress = minf(1.0, _wave_progress + delta / maxf(scan_duration, 0.05))
	var radius := _wave_progress * scan_vision_radius
	_wave.scale = Vector2.ONE * radius
	_wave.position = WORLD_CENTER - WORLD_CENTER * 0.0
	_wave.global_position = WORLD_CENTER
	# 波前扫到的行星依次浮现
	for planet_id in PLANET_ORDER:
		if _wave_hits.has(planet_id):
			continue
		var planet := planet_node(planet_id)
		if planet == null:
			continue
		if WORLD_CENTER.distance_to(planet.global_position) <= radius:
			_wave_hits.append(planet_id)
			_flash_planet(planet)
	if _wave_progress >= 1.0:
		_wave.visible = false


## 被波前扫到：短暂放大并亮一下
func _flash_planet(planet: Node2D) -> void:
	var visual := planet.get_node_or_null("visual") as Polygon2D
	if visual == null:
		return
	var tween := create_tween()
	tween.tween_property(visual, "modulate", Color(1.6, 1.6, 1.6, 1.0), 0.12)
	tween.tween_property(visual, "modulate", Color.WHITE, 0.5)


## 扫描：发出波形，并把这一片的观测结果列出来
func scan() -> bool:
	if _scan_cooldown_left > 0.0:
		feedback.emit("扫描尚未就绪。")
		return false
	vision.begin_scan(scan_duration)
	_scan_cooldown_left = scan_duration + scan_cooldown
	_wave_progress = 0.0
	_wave_hits.clear()
	if _wave != null:
		_wave.visible = true
		_wave.scale = Vector2.ZERO
		_wave.global_position = WORLD_CENTER
	_result_label.text = _format_scan_result()
	feedback.emit("扫描波形发出。")
	return true


## 扫描结果文本：每颗行星一行，带距离与已经拿到的知识线索
func _format_scan_result() -> String:
	var lines: PackedStringArray = []
	for planet_id in PLANET_ORDER:
		var planet := planet_node(planet_id)
		if planet == null:
			continue
		var distance := WORLD_CENTER.distance_to(planet.global_position)
		var info: Array = PLANET_ROOMS[planet_id] as Array
		lines.append("· %s　相距 %.0f　可进入 %d 层　%s" % [
			_planet_display_name(planet_id), distance, info.size(), _planet_knowledge_hint(planet_id)])
	return "扫描结果\n" + "\n".join(lines)


## 该行星已经查明的线索
func _planet_knowledge_hint(planet_id: StringName) -> String:
	var got: PackedStringArray = []
	match planet_id:
		&"earth":
			if WorldState.knows(&"tower_location"):
				got.append("赤阳之塔的位置")
			if WorldState.knows(&"tower_lit"):
				got.append("塔已被灯框住")
			if WorldState.knows(&"met_earth_ai"):
				got.append("地球 AI")
		&"mercury":
			if WorldState.knows(&"water_flow_south"):
				got.append("水流方向")
			if WorldState.knows(&"met_mercury_ai"):
				got.append("水星核心")
			if TerrainState.mercury_core_exposed(WorldState.get_flags()):
				got.append("核心已露出")
		&"mars":
			if WorldState.knows(&"met_mars_ai"):
				got.append("Mars")
			if WorldState.knows(&"human_plan_ai"):
				got.append("人类计划")
		&"sun":
			if WorldState.knows(&"know_ultimate"):
				got.append("终极太阳语")
			if bool(WorldState.get_flag(&"ultimate_sent", false)):
				got.append("已送出")
	if got.is_empty():
		return "无已知线索"
	return "、".join(got)


## ---------- 行星 ----------

func current_planet() -> StringName:
	return _current_planet


func current_layer() -> StringName:
	var stored: Variant = _planet_layers.get(_current_planet, &"")
	if stored is StringName:
		return stored
	if stored is int:
		return StringName("%d" % [stored])
	return StringName(str(stored))


func current_room() -> Node:
	return _room


func planet_node(planet_id: StringName) -> Node2D:
	for node in _planets.get_children():
		if StringName(node.name.to_lower()) == planet_id:
			return node as Node2D
	return null


## 枢纽不需要人移动，因此行星恒定可进入（扫描只影响可见性）
func planet_in_reach(_planet_id: StringName) -> bool:
	return true


## 进入行星：载入该行星的房间场景
func enter_planet(planet_id: StringName, layer_index: int = 1) -> bool:
	if _room != null:
		return false
	if not PLANET_ROOMS.has(planet_id):
		feedback.emit("这里没有可以进入的行星。")
		return false
	var paths: Array = PLANET_ROOMS[planet_id]
	if layer_index < 1 or layer_index > paths.size():
		feedback.emit(_layer_refusal(planet_id, layer_index))
		return false
	if not _layer_allowed(planet_id, layer_index):
		feedback.emit(_layer_refusal(planet_id, layer_index))
		return false
	var scene := load(String(paths[layer_index - 1])) as PackedScene
	if scene == null:
		feedback.emit("这颗行星的地表还没有做出来。")
		return false
	_room = scene.instantiate()
	if _room == null:
		return false
	_current_planet = planet_id
	_planet_layers[planet_id] = layer_index
	# 行星房间是独立场景，星图留在树上但隐藏，返回时原样恢复
	add_child(_room)
	_room.exit_requested.connect(_on_room_exit)
	if _room.has_signal(&"layer_change_requested"):
		_room.layer_change_requested.connect(_on_layer_step)
	if _room.has_signal(&"feedback"):
		_room.feedback.connect(func(text: String) -> void: feedback.emit(text))
	_apply_room_layer_buttons(layer_index)
	_planets.hide()
	_player.hide()
	if _selector != null:
		_selector.visible = false
	_ui_layer.get_node("Header").hide()
	_ui_layer.get_node("ActionBar").hide()
	_ui_layer.get_node("StatusLabel").hide()
	_ui_layer.get_node("FeedbackLabel").hide()
	WorldState.apply_changes({
		&"in_space": false,
		&"planet_name": _planet_display_name(planet_id),
		&"planet_layer": _layer_display_name(layer_index),
	})
	location_changed.emit(_current_planet, current_layer())
	room_entered.emit(_room)
	return true


## 房间请求切换层级
func _on_layer_step(step: int) -> void:
	if _room == null:
		return
	var current := int(_planet_layers.get(_current_planet, 1))
	var target := current + step
	var info: Array = PLANET_ROOMS[_current_planet] as Array
	if target < 1 or target > info.size():
		feedback.emit("这里已经没有%s了。" % ["上一层" if step < 0 else "下一层"])
		return
	if not _layer_allowed(_current_planet, target):
		feedback.emit(_layer_refusal(_current_planet, target))
		return
	switch_layer(target)


## 让房间的「上一层 / 下一层」按钮反映当前是否可走；
## 只有一层的行星（地球、太阳）整组隐藏，不显示无意义的按钮。
func _apply_room_layer_buttons(layer_index: int) -> void:
	if _room == null or not _room.has_method(&"set_layer_availability"):
		return
	var info: Array = PLANET_ROOMS.get(_current_planet, []) as Array
	if info.size() <= 1:
		_room.set_layer_buttons_visible(false)
		return
	if _room.has_method(&"set_layer_buttons_visible"):
		_room.set_layer_buttons_visible(true)
	var up_allowed := layer_index > 1
	var down_allowed := layer_index < info.size() \
		and _layer_allowed(_current_planet, layer_index + 1)
	_room.set_layer_availability(up_allowed, down_allowed)


## 房间请求返回航道
func _on_room_exit() -> void:
	if _room == null:
		return
	if _room.has_method(&"current_layer"):
		_planet_layers[_current_planet] = _layer_number(_room.current_layer())
	_room.queue_free()
	_room = null
	_planets.show()
	_player.show()
	_ui_layer.get_node("Header").show()
	_ui_layer.get_node("ActionBar").show()
	_ui_layer.get_node("StatusLabel").show()
	_ui_layer.get_node("FeedbackLabel").show()
	if _selector != null:
		_selector.visible = true
	# 回到该行星旁边的轨道位置
	var planet := planet_node(_current_planet)
	if planet != null:
		_player.global_position = planet.global_position + Vector2(0.0, 260.0)
	_focus_space()
	_select(_current_planet if _current_planet != &"" else &"earth")
	feedback.emit("你回到了航道。")


## 切换行星层级：先在原位释放当前房间，再载入目标层
func switch_layer(layer_index: int) -> bool:
	if _current_planet == &"":
		feedback.emit("需要先进入一颗行星。")
		return false
	var planet := _current_planet
	if _room != null:
		_room.queue_free()
		_room = null
	return enter_planet(planet, layer_index)


func _focus_space() -> void:
	_current_planet = &""
	WorldState.apply_changes({&"in_space": true, &"planet_name": "太空", &"planet_layer": ""})
	_camera.global_position = Vector2.ZERO
	_camera.zoom = Vector2.ONE * space_zoom
	location_changed.emit(&"", &"")


## 水星 1→2→3 自由；3→4 需要核心露出或已接触 Mercury。火星只能走地图上的洞口。
func _layer_allowed(planet_id: StringName, layer_index: int) -> bool:
	if planet_id == &"mercury":
		if layer_index < 1 or layer_index > 4:
			return false
		if layer_index >= 4:
			var known := {}
			for word in SunLanguage.WORDS:
				var key := SunLanguage.word_knowledge_key(word)
				if not key.is_empty():
					known[key] = WorldState.knows(key)
			known[&"met_mercury_ai"] = WorldState.knows(&"met_mercury_ai")
			return TerrainState.can_enter_mercury_core(WorldState.get_flags(), known)
		return true
	if planet_id == &"mars":
		if layer_index < 1 or layer_index > 2:
			return false
		var current := int(_planet_layers.get(planet_id, 0))
		if current == 0 or layer_index == current:
			return true
		# 火星换层必须走地图上分布的口：洞口只在 1 层，因此只有「在 1 层的洞口附近」
		# 才允许 1 ↔ 2。设计稿明确要求火星不能像水星那样自由换层。
		return _near_mars_hole()
	return true


func _layer_refusal(planet_id: StringName, layer_index: int) -> String:
	if planet_id == &"mercury" and layer_index >= 4:
		return "水星 3 层之下被高温水汽封闭，需要先让核心露出来。"
	if planet_id == &"mars":
		return "火星的层级之间无法直接切换；需要先走到 1 层的洞口。"
	return "现在无法进入这一层。"


## 火星洞口：玩家必须真的站在 1 层的洞口建筑旁边
func _near_mars_hole() -> bool:
	if _room == null:
		return false
	var hole := _room.get_node_or_null("Buildings/mars_hole_down") as Node2D
	if hole == null:
		return false
	var player := _room.get_node_or_null("Player") as Node2D
	if player == null:
		return false
	return player.global_position.distance_to(hole.global_position) <= 200.0


## 重载行星房间脚本里的层级数字（例如 "2 层 · 洞穴" → 2）
func _layer_number(layer_text: StringName) -> int:
	var text := String(layer_text)
	var digits := ""
	for index in text.length():
		var character := text[index]
		if character >= "0" and character <= "9":
			digits += character
		elif not digits.is_empty():
			break
	return int(digits) if not digits.is_empty() else 1


func _planet_display_name(planet_id: StringName) -> String:
	match planet_id:
		&"mercury":
			return "水星"
		&"mars":
			return "火星"
		&"earth":
			return "地球"
		&"sun":
			return "太阳"
	return String(planet_id)


func _layer_display_name(layer_index: int) -> String:
	return "第 %d 层" % [layer_index]


## ---------- 覆盖层 ----------

## 知识地图由星图持有，因此任何行星里、以及航道里都能查
func toggle_knowledge_map() -> void:
	if _knowledge_map.visible:
		_knowledge_map.close()
		return
	_knowledge_map.open()


func show_ending() -> void:
	if _ending_panel.visible:
		return
	_ending_panel.open(_knowledge_snapshot())


func _knowledge_snapshot() -> Dictionary:
	var result := {}
	for word in SunLanguage.WORDS:
		var key := SunLanguage.word_knowledge_key(word)
		if not key.is_empty():
			result[key] = WorldState.knows(key)
	for extra in [&"met_mercury_ai", &"met_mars_ai", &"met_earth_ai", &"ultimate_sent"]:
		result[extra] = WorldState.knows(extra) or bool(WorldState.get_flag(extra, false))
	return result


## ---------- 输入 ----------

func _unhandled_input(event: InputEvent) -> void:
	if _room != null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		match key.keycode:
			KEY_K:
				toggle_knowledge_map()
				get_viewport().set_input_as_handled()
				return
			KEY_R:
				enter_selected()
				get_viewport().set_input_as_handled()
				return
			KEY_LEFT:
				cycle_selection(-1)
				get_viewport().set_input_as_handled()
				return
			KEY_RIGHT:
				cycle_selection(1)
				get_viewport().set_input_as_handled()
				return
	# 靠近某颗行星时按 E 直接进入它（走近仍然可用）
	if event.is_action_pressed(&"ui_accept"):
		for planet_id in PLANET_ORDER:
			if planet_in_reach(planet_id):
				enter_planet(planet_id, 1)
				get_viewport().set_input_as_handled()
				return
		enter_selected()
		get_viewport().set_input_as_handled()


## ---------- HUD ----------

func _refresh_hud() -> void:
	_clock_label.text = "第 %d 轮 · %02d:%02d" % [
		WorldTime.loop_index, int(WorldTime.elapsed_seconds) / 60, int(WorldTime.elapsed_seconds) % 60]
	_scan_button.disabled = _scan_cooldown_left > 0.0
	_scan_button.text = "扫描（Tab）" if _scan_cooldown_left <= 0.0 else "扫描冷却 %.1fs" % [_scan_cooldown_left]
	if _room != null:
		return
	_status_label.text = "%s · 目标：%s · R 进入 / ←→ 换目标" % [
		TerrainState.sun_stage_label(WorldState.get_flags()), _planet_display_name(_selected)]
	_planet_label.text = "太空"
	_layer_label.text = ""
	_enter_button.text = "进入 %s（R）" % [_planet_display_name(_selected)]


func _nearest_planet_hint() -> String:
	var best := ""
	var best_distance := 240.0
	for planet_id in PLANET_ROOMS:
		var planet := planet_node(planet_id)
		if planet == null:
			continue
		var distance := _player.global_position.distance_to(planet.global_position)
		if distance < best_distance:
			best_distance = distance
			best = _planet_display_name(planet_id)
	if best.is_empty():
		return vision.label()
	return "靠近%s · 按 E 进入" % [best]
