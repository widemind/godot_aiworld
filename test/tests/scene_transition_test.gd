extends Node
## 需真实渲染器：从编辑器运行或 Godot --path . res://tests/scene_transition_test.tscn。

const SCENE_A := "res://scenes/scene_transition_demo_a.tscn"
const SCENE_B := "res://scenes/scene_transition_demo_b.tscn"
var _failures: int = 0
var _finished: int = 0
var _result: Error = FAILED
var _raw_color: Color
var _exclusions_restored: bool = false
var _snapshot: TextureRect


func _ready() -> void:
	_watchdog()
	_run.call_deferred()


func _watchdog() -> void:
	await get_tree().create_timer(20.0, true, false, true).timeout
	push_error("SCENE_TRANSITION_TEST: timed out")
	get_tree().quit(1)


func _run() -> void:
	# 将测试运行器移出 current_scene，确保场景切换后仍能执行断言。
	reparent(get_tree().root)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_snapshot = SceneTransition.get_node("Snapshot")
	var previous_scene := get_tree().current_scene
	_check(await SceneTransition.change_scene_to_file("res://missing_transition_scene.tscn") == ERR_FILE_NOT_FOUND, "无效路径返回错误")
	_check(not SceneTransition.is_transitioning and get_tree().current_scene == previous_scene, "失败不切换场景、不留下忙状态")
	_check(await SceneTransition.change_scene_to_file(SCENE_B, 0.1, Vector2(0.0, 90.0)) == ERR_INVALID_PARAMETER, "拒绝无效网格")
	SceneTransition.transition_finished.connect(func(_path: String) -> void: _finished += 1)
	SceneTransition.scene_revealed.connect(_on_revealed)
	_change_to_b()
	_check(SceneTransition.is_transitioning and get_viewport().is_input_disabled(), "加载开始立即锁住输入")
	_check(await SceneTransition.change_scene_to_file(SCENE_A) == ERR_BUSY, "拒绝并发切换")
	while SceneTransition.is_transitioning:
		await get_tree().process_frame
	_check(_result == OK and _finished == 1, "一次切换只完成一次")
	_check(absf(_raw_color.r - 0.025) < 0.012 and absf(_raw_color.g - 0.10) < 0.012 and absf(_raw_color.b - 0.22) < 0.012, "截图保留旧场景原色，未包含 CRT")
	_check(_exclusions_restored, "截图后恢复 CRT 和光标可见状态")
	_check(get_tree().current_scene.name == "WarmOrbit", "新场景已替换")
	_check(get_tree().current_scene.elapsed > 0.05, "溶解期间新场景继续动画")
	_check(get_tree().current_scene.input_presses == 0, "溶解期间输入不穿透")
	_check(not get_viewport().is_input_disabled() and not _snapshot.visible and _snapshot.texture == null, "完成恢复输入并释放截图")
	# 暂停与时间倍率不阻止持久过渡器，也不能擅自改变原暂停状态。
	get_tree().paused = true
	Engine.time_scale = 0.1
	_check(await SceneTransition.change_scene_to_file(SCENE_A, 0.15) == OK, "暂停、低时间倍率时仍能完成过渡")
	_check(get_tree().paused and is_equal_approx(Engine.time_scale, 0.1), "保留原暂停状态与时间倍率")
	get_tree().paused = false
	Engine.time_scale = 1.0
	# 调用前已有输入锁，结束后仍保留该锁。
	get_viewport().set_disable_input(true)
	_check(await SceneTransition.change_scene_to_file(SCENE_B, 0.0) == OK, "支持零时长切换")
	_check(get_viewport().is_input_disabled(), "保留调用前已有输入锁")
	get_viewport().set_disable_input(false)
	await _test_shader()
	print("SCENE_TRANSITION_TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _change_to_b() -> void:
	_result = await SceneTransition.change_scene_to_file(SCENE_B, 0.35)


func _on_revealed(path: String) -> void:
	if path != SCENE_B or _snapshot.texture == null:
		return
	var image := _snapshot.texture.get_image()
	_raw_color = image.get_pixel(image.get_width() / 32, image.get_height() / 10)
	_exclusions_restored = get_node("/root/GlobalCRT").visible and get_node("/root/GameCursor").visible
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.pressed = true
	get_viewport().push_input(event)


func _test_shader() -> void:
	# 用红/蓝两张纯色画面验证实际 GPU 输出，而非镜像实现的随机算法。
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 144)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var blue := ColorRect.new()
	blue.size = Vector2(viewport.size)
	blue.color = Color.BLUE
	viewport.add_child(blue)
	var red_image := Image.create(256, 144, false, Image.FORMAT_RGBA8)
	red_image.fill(Color.RED)
	var red := TextureRect.new()
	red.texture = ImageTexture.create_from_image(red_image)
	red.size = Vector2(viewport.size)
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/scene_pixel_dissolve.gdshader")
	material.set_shader_parameter(&"custom_resolution", Vector2(32.0, 18.0))
	red.material = material
	viewport.add_child(red)
	await get_tree().process_frame
	var counts: Array[int] = []
	var midpoint: Image
	for value in [0.0, 0.5, 1.0]:
		material.set_shader_parameter(&"progress", value)
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var old_pixels := 0
		var other_pixels := 0
		for y in image.get_height():
			for x in image.get_width():
				var color := image.get_pixel(x, y)
				if color.r > 0.9:
					old_pixels += 1
				elif color.b < 0.9:
					other_pixels += 1
		counts.append(old_pixels)
		_check(other_pixels == 0, "进度 %.1f 无黑屏或混色" % value)
		if value == 0.5:
			midpoint = image
	_check(counts[0] == 256 * 144 and counts[2] == 0, "起点完全旧画面、终点完全新画面")
	_check(counts[1] > counts[0] / 4 and counts[1] < counts[0] * 3 / 4, "中点同时显示两个场景")
	material.set_shader_parameter(&"progress", 0.5)
	await RenderingServer.frame_post_draw
	_check(midpoint.get_data() == viewport.get_texture().get_image().get_data(), "固定进度网格不随时间闪烁")
	viewport.queue_free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("SCENE_TRANSITION_TEST: " + message)
