extends Control
## 知识地图：把已获得的知识画成一张带连线的知识树。
##
## 设计稿对应第三张图：每条知识挂在对应分支下，并由「谁解锁了谁」的连线串起来，
## 是《Outer Wilds》式「线索本身即进度」的可视化。未解锁节点只显示占位与线索提示，
## 不泄露正文，避免提前剧透。
##
## 节点由 `KnowledgeNode` 的子节点呈现，连线由本脚本的 `_draw()` 绘制，
## 因此增减知识只需要改 NODES 表，不用动场景。

signal closed

const PAGE_NAME := "知识地图"

## 知识树骨架。`requires` 指向解锁它的前置节点，用于画连线与判断层次。
const NODES: Array[Dictionary] = [
	# 地球
	{"key": &"met_earth_ai", "branch": "地球", "title": "与地球 AI 接触", "hint": "居民楼的电脑", "requires": []},
	{"key": &"earth_is_one_grid", "branch": "地球", "title": "地球电网连成一体", "hint": "需要电力", "requires": [&"met_earth_ai"]},
	{"key": &"earth_needs_power", "branch": "地球", "title": "点亮全部发电机", "hint": "中央区域的电脑", "requires": [&"earth_is_one_grid"]},
	{"key": &"lit_earth_generator", "branch": "地球", "title": "地球发电机已启动", "hint": "发电机", "requires": []},
	# 水星
	{"key": &"water_flow_south", "branch": "水星", "title": "水流方向（东南）", "hint": "外层水流", "requires": []},
	{"key": &"know_awaken", "branch": "水星", "title": "太阳语：苏醒", "hint": "观测记录", "requires": [&"water_flow_south"]},
	{"key": &"met_mercury_ai", "branch": "水星", "title": "与水星 AI Mercury 接触", "hint": "水星 4 层", "requires": [&"mercury_core_open"]},
	{"key": &"mercury_core_open", "branch": "水星", "title": "水星核心已露出", "hint": "11 分钟后", "requires": []},
	{"key": &"mercury_is_simulation", "branch": "水星", "title": "这个世界是模拟", "hint": "Mercury 的话", "requires": [&"met_mercury_ai"]},
	{"key": &"simulation_error_time", "branch": "水星", "title": "时间上的渲染错误", "hint": "Mercury 的话", "requires": [&"mercury_is_simulation"]},
	# 火星
	{"key": &"met_mars_ai", "branch": "火星", "title": "与火星 AI Mars 接触", "hint": "算力中心", "requires": []},
	{"key": &"human_plan_ai", "branch": "火星", "title": "人类全力发展 AI 躲避太阳", "hint": "Mars 的话", "requires": [&"met_mars_ai"]},
	{"key": &"plan_may_terminate", "branch": "火星", "title": "错误地点的观察会让计划终止", "hint": "警告", "requires": [&"human_plan_ai"]},
	# 太阳与电码
	{"key": &"know_death_clear", "branch": "太阳", "title": "太阳语：清除", "hint": "死亡时触发", "requires": []},
	{"key": &"know_doubt", "branch": "太阳", "title": "太阳语：疑惑", "hint": "错误电码的回应", "requires": []},
	{"key": &"know_ultimate", "branch": "太阳", "title": "终极太阳语", "hint": "集齐三段语料", "requires": [&"know_awaken", &"know_doubt", &"know_death_clear"]},
	{"key": &"tower_location", "branch": "太阳", "title": "太阳观测塔的位置", "hint": "赤阳之塔内", "requires": [&"know_ultimate"]},
	{"key": &"tower_build_reason", "branch": "太阳", "title": "太阳观测塔的建造原因", "hint": "赤阳之塔内", "requires": [&"tower_location"]},
	{"key": &"ultimate_sent", "branch": "太阳", "title": "已向太阳送出终极太阳语", "hint": "结局", "requires": [&"tower_build_reason"]},
]

## 每列在画布上的 x 起点与宽度（画布是 4 倍窗口尺寸的大平面）
const COLUMN_WIDTH := 460.0
const COLUMN_GAP := 60.0
const ROW_HEIGHT := 96.0
const ROW_GAP := 18.0
const TOP_MARGIN := 120.0

@onready var _title: Label = %KnowledgeTitle
@onready var _progress: Label = %KnowledgeProgress
@onready var _canvas: Control = %KnowledgeCanvas
@onready var _scroll: ScrollContainer = %KnowledgeScroll
@onready var _back_button: Button = %KnowledgeBack

var _node_controls: Dictionary = {}
var _positions: Dictionary = {}


func _ready() -> void:
	hide()
	_back_button.pressed.connect(close)


## 用 _input 而不是 _unhandled_input：本页是覆盖全屏的模态界面，
## 里面的 ScrollContainer 会先吃掉 GUI 事件，等不到 _unhandled_input。
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not event.is_pressed() or event.is_echo():
		return
	var is_close := false
	if event is InputEventKey:
		var key := event as InputEventKey
		is_close = key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE \
			or key.keycode == KEY_K
	elif event is InputEventMouseButton:
		# 点击遮罩也能退出，避免玩家找不到关闭方式
		is_close = (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT
	if is_close:
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	_refresh()
	show()


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


## 已解锁条目数 / 总条目数
static func unlocked_count(known: Dictionary) -> int:
	var count := 0
	for entry in NODES:
		if bool(known.get(entry["key"], false)):
			count += 1
	return count


## 分支顺序（按 NODES 首次出现的顺序，保证布局稳定）
static func branches() -> Array[String]:
	var result: Array[String] = []
	for entry in NODES:
		var branch := String(entry["branch"])
		if not result.has(branch):
			result.append(branch)
	return result


func _refresh() -> void:
	var known := _knows()
	_title.text = PAGE_NAME
	_progress.text = "已获得 %d / %d 条知识" % [unlocked_count(known), NODES.size()]
	_layout(known)
	queue_redraw()


func _knows() -> Dictionary:
	var result := {}
	for entry in NODES:
		result[entry["key"]] = WorldState.knows(entry["key"])
	# 世界标记也能作为「已获得」的证据
	for flag_key in [&"ultimate_sent", &"mercury_core_open"]:
		if bool(WorldState.get_flag(flag_key, false)):
			result[flag_key] = true
	return result


## 每个分支一列，节点按在 NODES 中的顺序自上而下排列
func _layout(known: Dictionary) -> void:
	for child in _canvas.get_children():
		child.queue_free()
	_node_controls.clear()
	_positions.clear()
	var columns := branches()
	var max_rows := 0
	for column_index in columns.size():
		var branch := columns[column_index]
		var row := 0
		for entry in NODES:
			if String(entry["branch"]) != branch:
				continue
			var key := StringName(entry["key"])
			var position := Vector2(
				column_index * (COLUMN_WIDTH + COLUMN_GAP),
				TOP_MARGIN + row * (ROW_HEIGHT + ROW_GAP))
			_positions[key] = position
			var node := _build_node(entry, known, position)
			_canvas.add_child(node)
			_node_controls[key] = node
			row += 1
		max_rows = maxi(max_rows, row)
	# 画布尺寸决定滚动范围
	var height := TOP_MARGIN * 2.0 + max_rows * (ROW_HEIGHT + ROW_GAP)
	var width := columns.size() * (COLUMN_WIDTH + COLUMN_GAP)
	_canvas.custom_minimum_size = Vector2(width, height)
	_canvas.size = _canvas.custom_minimum_size
	# 分支标题
	for column_index in columns.size():
		var header := Label.new()
		header.text = columns[column_index]
		header.add_theme_font_size_override(&"font_size", 32)
		header.position = Vector2(column_index * (COLUMN_WIDTH + COLUMN_GAP), 40.0)
		header.size = Vector2(COLUMN_WIDTH, 48.0)
		_canvas.add_child(header)


func _build_node(entry: Dictionary, known: Dictionary, position: Vector2) -> PanelContainer:
	var key := StringName(entry["key"])
	var unlocked := bool(known.get(key, false))
	var panel := PanelContainer.new()
	panel.position = position
	panel.size = Vector2(COLUMN_WIDTH, ROW_HEIGHT)
	panel.custom_minimum_size = panel.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 20)
	if unlocked:
		label.text = "• " + String(entry["title"])
		label.modulate = Color.WHITE
	else:
		label.text = "？？？　线索：%s" % [String(entry["hint"])]
		label.modulate = Color(1, 1, 1, 0.42)
	panel.add_child(label)
	return panel


## 画连线：从前置节点指向当前节点，未解锁的连线画成暗色
func _draw() -> void:
	if _positions.is_empty():
		return
	var known := _knows()
	for entry in NODES:
		var key := StringName(entry["key"])
		if not _positions.has(key):
			continue
		var to: Vector2 = _positions[key]
		var from_rect := Rect2(to, Vector2(COLUMN_WIDTH, ROW_HEIGHT))
		var start_point := from_rect.position + Vector2(0.0, ROW_HEIGHT * 0.5)
		for parent in entry.get("requires", []):
			var parent_key := StringName(parent)
			if not _positions.has(parent_key):
				continue
			var parent_pos: Vector2 = _positions[parent_key]
			var end_point := parent_pos + Vector2(COLUMN_WIDTH, ROW_HEIGHT * 0.5)
			var unlocked := bool(known.get(key, false)) and bool(known.get(parent_key, false))
			var color := Color(0.45, 0.85, 1.0, 0.85) if unlocked else Color(1, 1, 1, 0.18)
			# 先水平再垂直的正交折线，避免斜线穿过节点文字
			var mid_x := (end_point.x + start_point.x) * 0.5
			draw_polyline(PackedVector2Array([
				end_point,
				Vector2(mid_x, end_point.y),
				Vector2(mid_x, start_point.y),
				start_point,
			]), color, 2.0, true)
			draw_circle(end_point, 4.0, color, true, -1.0, true)
			draw_circle(start_point, 4.0, color, true, -1.0, true)
