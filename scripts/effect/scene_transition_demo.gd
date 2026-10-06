extends Control
## F6 运行任一演示场景，点击按钮在两个不同画面之间溶解切换。

@export var destination: String = "res://scenes/scene_transition_demo_b.tscn"
@export var title: String = "冷蓝轨道"
@export var background_color: Color = Color(0.025, 0.10, 0.22)
@export var accent_color: Color = Color(0.28, 0.78, 1.0)
var elapsed: float = 0.0
var input_presses: int = 0


func _ready() -> void:
	var panel := VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	panel.offset_left = 100.0
	panel.offset_top = -170.0
	panel.offset_right = 740.0
	panel.offset_bottom = 170.0
	panel.add_theme_constant_override("separation", 24)
	add_child(panel)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 64)
	heading.add_theme_color_override("font_color", accent_color)
	panel.add_child(heading)
	var description := Label.new()
	description.text = "旧画面按方块溶解，直接露出新画面。\n新场景的轨道动画在过渡期间继续运行。"
	description.add_theme_font_size_override("font_size", 26)
	panel.add_child(description)
	var button := Button.new()
	button.text = "切换场景"
	button.custom_minimum_size = Vector2(360.0, 72.0)
	button.add_theme_font_size_override("font_size", 30)
	button.add_to_group(&"cursor_frame_target")
	button.pressed.connect(_switch_scene)
	panel.add_child(button)
	var hint := Label.new()
	hint.text = "默认 0.8 秒 · 160 × 90 网格\nEsc 暂停 / 继续"
	hint.add_theme_font_size_override("font_size", 22)
	panel.add_child(hint)
	resized.connect(queue_redraw)
	queue_redraw()


func _switch_scene() -> void:
	# 当前场景即将释放，不在这里 await。流程由持久 Autoload 执行。
	SceneTransition.change_scene_to_file(destination)


func _input(event: InputEvent) -> void:
	if event.is_pressed():
		input_presses += 1


func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), background_color)
	var center := size * Vector2(0.75, 0.5)
	var radius := minf(size.x, size.y) * 0.22
	for ring in [0.5, 0.8, 1.1]:
		draw_arc(center, radius * ring, 0.0, TAU, 120, Color(accent_color, 0.35), 2.0, true)
	draw_circle(center, radius * 0.22, accent_color, true, -1.0, true)
	var satellite := center + Vector2(cos(elapsed * 1.8), sin(elapsed * 1.8)) * radius * 0.8
	draw_circle(satellite, 14.0, Color.WHITE, true, -1.0, true)
