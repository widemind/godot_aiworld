@tool
class_name FloatingLinkButton
extends Control
## 根节点保存摆放位置，只有内部 Button 漂浮；虚线使用视口坐标转换跟随目标。

signal pressed
signal button_down
signal button_up

@export_group("Button")
@export var text: String = "关联按钮":
	set(value):
		text = value
		_content_dirty = true
@export var disabled: bool = false:
	set(value):
		disabled = value
		_content_dirty = true
@export var button_tint: Color = Color(0.45, 0.85, 1.0):
	set(value):
		button_tint = value
		_style_dirty = true
@export var background_color: Color = Color(0.025, 0.055, 0.09, 0.95):
	set(value):
		background_color = value
		_style_dirty = true
@export_range(0.0, 40.0, 1.0) var horizontal_padding: float = 10.0:
	set(value):
		horizontal_padding = value
		_style_dirty = true
@export_range(0.5, 4.0, 0.25) var border_dot_radius: float = 1.25
@export_range(3.0, 20.0, 0.5) var border_dot_spacing: float = 7.0

@export_group("Float")
@export var float_enabled: bool = true
@export var float_amplitude: Vector2 = Vector2(6.0, 4.0)
@export_range(0.0, 10.0, 0.05) var float_speed: float = 1.2
@export_range(0.0, 6.283185, 0.01) var float_phase: float = 0.0
@export var preview_float_in_editor: bool = false

@export_group("Connection")
## 可拖入 Node2D / Sprite2D / Marker2D / Control 等 CanvasItem。
@export var target: CanvasItem
@export var target_offset: Vector2 = Vector2.ZERO
@export var connection_enabled: bool = true
@export var line_color: Color = Color(0.45, 0.85, 1.0, 0.75)
@export_range(0.5, 10.0, 0.5) var line_width: float = 2.0
@export_range(1.0, 40.0, 0.5) var dash_length: float = 9.0
@export_range(0.0, 100.0, 1.0) var button_gap: float = 8.0
@export_range(0.0, 200.0, 1.0) var target_gap: float = 18.0

var _elapsed: float = 0.0
var _style_dirty: bool = true
var _content_dirty: bool = true
@onready var _button: Button = get_node_or_null("Button") as Button


func _ready() -> void:
	if _button == null:
		return
	_button.add_to_group(&"cursor_frame_target")
	_button.pressed.connect(func() -> void: pressed.emit())
	_button.button_down.connect(func() -> void: button_down.emit())
	_button.button_up.connect(func() -> void: button_up.emit())
	_button.minimum_size_changed.connect(update_minimum_size)
	_button.draw.connect(_draw_button_border)
	_refresh_button()
	update_minimum_size()
	queue_redraw()


func _get_minimum_size() -> Vector2:
	return _button.get_combined_minimum_size() if is_instance_valid(_button) else Vector2(0.0, 64.0)


func _process(delta: float) -> void:
	if _button == null:
		return
	_refresh_button()
	if float_enabled and (not Engine.is_editor_hint() or preview_float_in_editor):
		_elapsed += delta
		var phase := _elapsed * float_speed
		_button.position = Vector2(sin(phase + float_phase), sin(phase * 0.73 + float_phase)) * float_amplitude.abs()
	else:
		_button.position = Vector2.ZERO
	# 目标、相机、CanvasLayer 与布局均可移动，不缓存上一帧的连接坐标。
	queue_redraw()
	_button.queue_redraw()


func _draw() -> void:
	var points := get_connection_points()
	if points.size() == 2:
		draw_dashed_line(points[0], points[1], line_color, maxf(line_width, 0.5), maxf(dash_length, 1.0), true, true)


func _draw_button_border() -> void:
	# 在原生 Button 的绘制回调中叠加圆点，矩形路径不使用圆角。
	var tint := button_tint
	if _button.disabled:
		tint = Color(tint, tint.a * 0.4)
	elif _button.is_hovered() or _button.has_focus():
		tint = tint.lerp(Color.WHITE, 0.3)
	var radius := maxf(border_dot_radius, 0.5)
	var span := _button.size - Vector2.ONE * radius * 2.0
	if span.x <= 0.0 or span.y <= 0.0:
		return
	var spacing := maxf(border_dot_spacing, radius * 2.0 + 1.0)
	var columns := maxi(1, roundi(span.x / spacing))
	var rows := maxi(1, roundi(span.y / spacing))
	for column in range(columns + 1):
		var x := radius + span.x * float(column) / float(columns)
		_button.draw_circle(Vector2(x, radius), radius, tint, true, -1.0, true)
		_button.draw_circle(Vector2(x, radius + span.y), radius, tint, true, -1.0, true)
	# 顶部/底部已绘制四个角点，侧边只绘制内部点以避免角点重叠。
	for row in range(1, rows):
		var y := radius + span.y * float(row) / float(rows)
		_button.draw_circle(Vector2(radius, y), radius, tint, true, -1.0, true)
		_button.draw_circle(Vector2(radius + span.x, y), radius, tint, true, -1.0, true)


## 连接到不同目标，null 解除绑定；目标移动不改变按钮的摆放位置。
func bind_target(value: CanvasItem) -> void:
	target = value
	queue_redraw()


func get_button() -> Button:
	return _button


## 返回此控件局部坐标下的线段端点；目标无效、隐藏、重叠时返回空数组。
func get_connection_points() -> PackedVector2Array:
	if not connection_enabled or not is_instance_valid(_button) or not is_instance_valid(target):
		return PackedVector2Array()
	if not target.is_inside_tree() or not target.is_visible_in_tree() or target.get_viewport() != get_viewport():
		return PackedVector2Array()
	var root_transform := get_global_transform_with_canvas()
	var button_transform := _button.get_transform()
	if is_zero_approx(root_transform.determinant()) or is_zero_approx(button_transform.determinant()):
		return PackedVector2Array()
	var anchor := target_offset
	if target is Control:
		anchor += (target as Control).size * 0.5
	var target_point := root_transform.affine_inverse() * target.get_global_transform_with_canvas() * anchor
	var half_size := _button.size * 0.5
	if half_size.x <= 0.0 or half_size.y <= 0.0:
		return PackedVector2Array()
	var toward_target := button_transform.affine_inverse() * target_point - half_size
	var edge_factor := maxf(absf(toward_target.x) / half_size.x, absf(toward_target.y) / half_size.y)
	if edge_factor <= 1.0:
		return PackedVector2Array()
	# 从真实漂浮按钮边缘出发，避免虚线穿过文字或背景。
	var start := button_transform * (half_size + toward_target / edge_factor)
	var direction := target_point - start
	var distance := direction.length()
	var start_gap := maxf(button_gap, 0.0)
	var end_gap := maxf(target_gap, 0.0)
	if distance <= start_gap + end_gap:
		return PackedVector2Array()
	direction /= distance
	return PackedVector2Array([start + direction * start_gap, target_point - direction * end_gap])


func _refresh_button() -> void:
	# 编辑器热重载不会重跑 ready，补上新绘制回调并刷新实例覆盖样式。
	if not _button.draw.is_connected(_draw_button_border):
		_button.draw.connect(_draw_button_border)
		_style_dirty = true
	if _content_dirty:
		_button.text = text
		_button.disabled = disabled
		_content_dirty = false
	if not _style_dirty:
		return
	for state in [&"normal", &"hover", &"pressed", &"disabled", &"focus"]:
		var style := StyleBoxFlat.new()
		var tint := button_tint
		var fill := background_color
		if state == &"hover" or state == &"focus":
			tint = tint.lerp(Color.WHITE, 0.3)
		if state == &"pressed":
			fill = fill.lerp(button_tint, 0.2)
		if state == &"disabled":
			tint = Color(tint, tint.a * 0.4)
		style.bg_color = fill
		style.border_color = tint
		style.set_border_width_all(0)
		style.set_corner_radius_all(0)
		style.content_margin_left = maxf(horizontal_padding, 0.0)
		style.content_margin_right = maxf(horizontal_padding, 0.0)
		style.content_margin_top = 12.0
		style.content_margin_bottom = 12.0
		style.draw_center = state != &"focus"
		_button.add_theme_stylebox_override(state, style)
		_button.add_theme_color_override(StringName("font_%s_color" % state) if state != &"normal" else &"font_color", tint)
	_style_dirty = false
