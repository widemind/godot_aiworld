extends Control
## 目标自动移动，也可拖拽；两个不同色调的按钮关联同一个目标。

@export var auto_move: bool = true
var _elapsed: float = 0.0
var _dragging: bool = false
var _alternate_palette: bool = false

@onready var _target: Node2D = $World/Target
@onready var _cyan: FloatingLinkButton = $UI/Controls/CyanButton
@onready var _orange: FloatingLinkButton = $UI/Controls/OrangeButton
@onready var _status: Label = $UI/Controls/Status


func _ready() -> void:
	resized.connect(queue_redraw)
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	if auto_move and not _dragging:
		_target.position = size * Vector2(0.70, 0.52) + Vector2(sin(_elapsed * 0.65) * 130.0, cos(_elapsed * 0.9) * 150.0)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _target.get_global_transform_with_canvas().origin.distance_to(event.position) < 48.0:
			_dragging = true
			auto_move = false
			get_viewport().set_input_as_handled()
		elif not event.pressed:
			_dragging = false
	if event is InputEventMouseMotion and _dragging:
		var world := _target.get_parent() as Node2D
		_target.position = world.get_global_transform_with_canvas().affine_inverse() * event.position
		get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.018, 0.027, 0.045))
	for x in range(0, int(size.x), 64):
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), Color(0.14, 0.2, 0.28, 0.2))
	for y in range(0, int(size.y), 64):
		draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(0.14, 0.2, 0.28, 0.2))
	if not is_instance_valid(_target):
		return
	var point := make_canvas_position_local(_target.get_global_transform_with_canvas().origin)
	var tint := Color(0.65, 0.88, 1.0)
	draw_circle(point, 44.0, Color(tint, 0.1), true, -1.0, true)
	draw_arc(point, 34.0, 0.0, TAU, 80, tint, 2.0, true)
	draw_circle(point, 10.0, tint, true, -1.0, true)
	draw_line(point - Vector2(50.0, 0.0), point - Vector2(40.0, 0.0), tint, 2.0)
	draw_line(point + Vector2(40.0, 0.0), point + Vector2(50.0, 0.0), tint, 2.0)
	draw_string(get_theme_default_font(), point + Vector2(-52.0, 72.0), "移动目标", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 26, tint)


func _on_cyan_pressed() -> void:
	_status.text = "已点击「观察目标」——原生按钮信号正常触发"


func _on_orange_pressed() -> void:
	_status.text = "已点击「目标信息」——两个按钮可以绑定同一个目标"


func _on_auto_pressed() -> void:
	auto_move = not auto_move
	_status.text = "目标自动移动" if auto_move else "目标已停住，可以直接拖拽圆点"


func _on_palette_pressed() -> void:
	_alternate_palette = not _alternate_palette
	_cyan.button_tint = Color(0.76, 0.56, 1.0) if _alternate_palette else Color(0.45, 0.85, 1.0)
	_cyan.line_color = Color(_cyan.button_tint, 0.8)
	_orange.button_tint = Color(0.50, 1.0, 0.66) if _alternate_palette else Color(1.0, 0.68, 0.35)
	_orange.line_color = Color(_orange.button_tint, 0.8)
	_status.text = "按钮与虚线已切换色调，颜色按实例独立保存"
