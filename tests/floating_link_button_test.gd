extends Node
## 检查实际坐标转换、漂浮范围与原生 Viewport 输入分发。

const BUTTON_SCENE := preload("res://scenes/ui/floating_link_button.tscn")
var _failures: int = 0
var _presses: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node2D.new()
	world.position = Vector2(850.0, 420.0)
	world.rotation = 0.25
	world.scale = Vector2(1.3, 0.8)
	add_child(world)
	var marker := Marker2D.new()
	marker.position = Vector2(90.0, 60.0)
	world.add_child(marker)
	var canvas := CanvasLayer.new()
	canvas.layer = 8
	canvas.offset = Vector2(40.0, 20.0)
	canvas.scale = Vector2(0.9, 1.1)
	add_child(canvas)
	var widget := BUTTON_SCENE.instantiate() as FloatingLinkButton
	widget.position = Vector2(230.0, 180.0)
	widget.rotation = -0.12
	widget.scale = Vector2(0.8, 1.2)
	canvas.add_child(widget)
	widget.bind_target(marker)
	widget.pressed.connect(func() -> void: _presses += 1)
	await get_tree().process_frame
	_check(widget.get_button().is_in_group(&"cursor_frame_target"), "兼容全局指针框选")
	var rest := widget.position
	var first := widget.get_connection_points()
	_check(first.size() == 2, "跨 CanvasLayer 建立连接")
	_check_endpoint(widget, marker, "父节点旋转与非等比缩放后目标端点正确")
	marker.position += Vector2(70.0, -30.0)
	await get_tree().process_frame
	var moved := widget.get_connection_points()
	_check(moved.size() == 2 and moved[1].distance_to(first[1]) > 20.0, "目标移动立即更新虚线")
	_check_endpoint(widget, marker, "移动后仍指向正确位置")
	# 相机画布变换也应参与世界目标 -> UI 的换算。
	var old_transform := get_viewport().canvas_transform
	get_viewport().canvas_transform = Transform2D(0.1, Vector2(1.15, 1.15), 0.0, Vector2(-90.0, 30.0))
	await get_tree().process_frame
	_check_endpoint(widget, marker, "相机平移、旋转、缩放后连接正确")
	get_viewport().canvas_transform = old_transform
	var movement := 0.0
	var initial_offset := widget.get_button().position
	for frame in 45:
		await get_tree().process_frame
		var offset := widget.get_button().position
		_check(absf(offset.x) <= widget.float_amplitude.x + 0.01 and absf(offset.y) <= widget.float_amplitude.y + 0.01, "漂浮始终限制在配置范围内")
		movement = maxf(movement, offset.distance_to(initial_offset))
	_check(movement > 0.1 and widget.position == rest, "内部按钮漂浮，摆放位置不累积漂移")
	await _click(widget.get_button().get_global_transform_with_canvas() * (widget.get_button().size * 0.5))
	_check(_presses == 1, "漂浮中的按钮可正常点击")
	widget.disabled = true
	await get_tree().process_frame
	await _click(widget.get_button().get_global_transform_with_canvas() * (widget.get_button().size * 0.5))
	_check(_presses == 1, "禁用时不发出点击信号")
	widget.disabled = false
	widget.float_enabled = false
	widget.size = Vector2(320.0, 84.0)
	await get_tree().process_frame
	_check(widget.get_button().position == Vector2.ZERO and widget.get_button().size.is_equal_approx(widget.size), "停止漂浮回到原位，尺寸跟随布局")
	var second_widget := BUTTON_SCENE.instantiate() as FloatingLinkButton
	second_widget.position = Vector2(230.0, 400.0)
	canvas.add_child(second_widget)
	widget.button_tint = Color.MAGENTA
	widget.line_color = Color.GREEN
	await get_tree().process_frame
	var first_style := widget.get_button().get_theme_stylebox(&"normal") as StyleBoxFlat
	var second_style := second_widget.get_button().get_theme_stylebox(&"normal") as StyleBoxFlat
	_check(first_style.border_color == Color.MAGENTA and widget.line_color == Color.GREEN, "支持运行时调整按钮与虚线色调")
	_check(second_style.border_color == second_widget.button_tint and second_style != first_style, "实例样式互不污染")
	marker.hide()
	_check(widget.get_connection_points().is_empty(), "隐藏目标时隐藏关联线")
	marker.show()
	widget.bind_target(null)
	_check(widget.get_connection_points().is_empty(), "解除绑定后仍保留按钮但不画线")
	var control_target := Control.new()
	control_target.position = Vector2(950.0, 400.0)
	control_target.size = Vector2(100.0, 80.0)
	canvas.add_child(control_target)
	widget.bind_target(control_target)
	_check_endpoint(widget, control_target, "Control 默认连接中心")
	widget.target_offset = Vector2(10.0, -8.0)
	_check_endpoint(widget, control_target, "支持目标局部偏移")
	control_target.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(widget.get_connection_points().is_empty(), "目标释放后安全停止绘线")
	print("FLOATING_LINK_BUTTON_TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _check_endpoint(widget: FloatingLinkButton, bound_target: CanvasItem, message: String) -> void:
	var points := widget.get_connection_points()
	if points.size() != 2:
		_check(false, message)
		return
	var local_anchor := widget.target_offset
	if bound_target is Control:
		local_anchor += (bound_target as Control).size * 0.5
	var expected := widget.make_canvas_position_local(bound_target.get_global_transform_with_canvas() * local_anchor)
	var end_delta := expected - points[1]
	var line := points[1] - points[0]
	_check(absf(end_delta.length() - widget.target_gap) < 0.05 and absf(end_delta.normalized().cross(line.normalized())) < 0.001, message)


func _click(point: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = point
	get_viewport().push_input(down)
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	get_viewport().push_input(up)
	await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FLOATING_LINK_BUTTON_TEST: " + message)
