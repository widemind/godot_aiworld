extends Control
## 全局指针：圆点跟随鼠标，四角平滑框选 cursor_frame_target 组内的按钮。

const TARGET_GROUP: StringName = &"cursor_frame_target"

@export_range(20.0, 100.0, 1.0) var idle_side_length: float = 36.0
@export_range(2.0, 20.0, 0.5) var corner_length: float = 8.0
@export_range(1.0, 5.0, 0.5) var line_width: float = 2.0
@export_range(1.0, 6.0, 0.5) var dot_radius: float = 2.5
@export_range(0.0, 20.0, 1.0) var button_padding: float = 6.0
@export_range(1.0, 40.0, 1.0) var transition_speed: float = 18.0
@export var cursor_color: Color = Color(0.92, 0.98, 1.0)
@export var outline_color: Color = Color(0.02, 0.04, 0.08, 0.85)

var _frame_rect: Rect2
var _mouse_position: Vector2
var _initialized: bool = false
var _was_framing: bool = false
var _inside_window: bool = true
var _previous_mouse_mode: Input.MouseMode


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	get_window().mouse_entered.connect(_on_mouse_entered)
	get_window().mouse_exited.connect(_on_mouse_exited)


func _exit_tree() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = _previous_mouse_mode


func _process(delta: float) -> void:
	var viewport := get_viewport()
	visible = _inside_window and viewport.get_visible_rect().has_point(viewport.get_mouse_position())
	if not visible:
		_initialized = false
		return
	var previous_mouse := _mouse_position
	_mouse_position = get_local_mouse_position()
	var button := _find_hovered_button()
	var framing := button != null
	var target_rect := _idle_rect(_mouse_position)
	if framing:
		target_rect = _button_rect(button).grow(button_padding)
	if not _initialized:
		_frame_rect = _idle_rect(_mouse_position)
		_initialized = true
	elif not framing and not _was_framing:
		# 普通移动时与圆点同步；收回过程仍跟随鼠标，不留拖尾。
		_frame_rect.position += _mouse_position - previous_mouse
	var weight := 1.0 - exp(-transition_speed * delta)
	_frame_rect.position = _frame_rect.position.lerp(target_rect.position, weight)
	_frame_rect.size = _frame_rect.size.lerp(target_rect.size, weight)
	_was_framing = framing
	queue_redraw()


func _find_hovered_button() -> BaseButton:
	# 以 GUI 实际命中的控件为准，避免框选被弹窗遮挡的底层按钮。
	var hovered := get_viewport().gui_get_hovered_control()
	while hovered != null:
		if hovered is BaseButton:
			var button := hovered as BaseButton
			if button.is_in_group(TARGET_GROUP) and not button.disabled and button.can_process():
				return button
			return null
		hovered = hovered.get_parent_control()
	return null


func _idle_rect(center: Vector2) -> Rect2:
	# 保证正方形边长严格大于直角边长的两倍，四条边中间始终留空。
	var side := maxf(idle_side_length, corner_length * 2.0 + line_width * 2.0)
	return Rect2(center - Vector2.ONE * side * 0.5, Vector2.ONE * side)


func _button_rect(button: Control) -> Rect2:
	# 将按钮变换到指针画布；支持窗口缩放、容器布局及不同 CanvasLayer。
	var transform_to_cursor := get_global_transform_with_canvas().affine_inverse() * button.get_global_transform_with_canvas()
	var bounds := Rect2(transform_to_cursor * Vector2.ZERO, Vector2.ZERO)
	for corner in [Vector2(button.size.x, 0.0), button.size, Vector2(0.0, button.size.y)]:
		bounds = bounds.expand(transform_to_cursor * corner)
	return bounds


func _draw() -> void:
	if not _initialized:
		return
	var start := _frame_rect.position
	var end := _frame_rect.end
	var arm := minf(corner_length, minf(_frame_rect.size.x, _frame_rect.size.y) * 0.5 - line_width)
	arm = maxf(arm, 0.0)
	_draw_corner(start, Vector2(1.0, 1.0), arm)
	_draw_corner(Vector2(end.x, start.y), Vector2(-1.0, 1.0), arm)
	_draw_corner(end, Vector2(-1.0, -1.0), arm)
	_draw_corner(Vector2(start.x, end.y), Vector2(1.0, -1.0), arm)
	draw_circle(_mouse_position, dot_radius + 1.0, outline_color, true, -1.0, true)
	draw_circle(_mouse_position, dot_radius, cursor_color, true, -1.0, true)


func _draw_corner(corner: Vector2, direction: Vector2, arm: float) -> void:
	var points := PackedVector2Array([
		corner + Vector2(direction.x * arm, 0.0),
		corner,
		corner + Vector2(0.0, direction.y * arm),
	])
	draw_polyline(points, outline_color, line_width + 2.0, true)
	draw_polyline(points, cursor_color, line_width, true)


func _on_mouse_entered() -> void:
	_inside_window = true


func _on_mouse_exited() -> void:
	_inside_window = false
