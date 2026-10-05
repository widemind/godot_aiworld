extends Node
## 使用真正的 Viewport 输入分发，检查模态输入不会穿透地图与按钮。

class MapSpy extends Control:
	var presses: int = 0
	func _input(event: InputEvent) -> void:
		if event.is_pressed():
			presses += 1

var _failures: int = 0
var _requests: Array[Dictionary] = []
var _screen: Control
var _ui: PlanetExplorationUI
var _map: MapSpy


func _ready() -> void:
	_map = MapSpy.new()
	add_child(_map)
	_screen = preload("res://scenes/planet_exploration.tscn").instantiate()
	add_child(_screen)
	_ui = _screen.get_node("PlanetExplorationUI")
	_ui.action_requested.connect(func(id: StringName, held: bool) -> void: _requests.append({"id": id, "held": held}))
	await get_tree().process_frame
	await get_tree().process_frame
	var a := _ui.buttons[0].get_global_rect()
	var b := _ui.buttons[1].get_global_rect()
	var c := _ui.buttons[2].get_global_rect()
	_check(absf(a.size.x - b.size.x) <= 1.0 and absf(b.size.x - c.size.x) <= 1.0, "三个按钮等宽（容器取整容差 1px）")
	_check(is_equal_approx(b.position.x - a.end.x, c.position.x - b.end.x), "三个按钮等间距")
	for button in _ui.buttons:
		await _click(button.get_global_rect().get_center(), 0.02)
		_check(_ui.is_text_open(), "短按产生地点文本")
		_check(not _requests[-1].held, "短按只发一次短按请求")
		_ui.close_text()
		await _click(button.get_global_rect().get_center(), 0.62)
		_check(_ui.is_text_open() and _requests[-1].held, "长按识别并产生文本")
		_ui.close_text()
	_check(_requests.size() == 6, "三按钮共六次操作，无长短按双触发")
	# 长按中暂停会取消正在按住的操作，恢复后松开不结算。
	await _send(_mouse(MOUSE_BUTTON_LEFT, true, a.get_center()))
	PauseController.set_paused(true)
	PauseController.set_paused(false)
	await _send(_mouse(MOUSE_BUTTON_LEFT, false, a.get_center()))
	_check(_requests.size() == 6, "暂停取消按压，恢复后的松开不触发")
	await _click(a.get_center(), 0.02, Vector2(960, 500))
	_check(_requests.size() == 6, "移出按钮松开取消操作")
	_ui.show_text("滚动测试段落。\n\n".repeat(70))
	await get_tree().process_frame
	await get_tree().process_frame
	var map_before := _map.presses
	var time_before := WorldTime.elapsed_seconds
	await _send(_mouse(MOUSE_BUTTON_WHEEL_DOWN, true, Vector2(960, 500)))
	_check(_ui.is_text_open() and _ui.narrative.get_v_scroll_bar().value > 0, "地图区域滚轮也能滚动文本，不关闭")
	_check(not _ui.narrative.get_v_scroll_bar().visible, "不显示滚动条")
	_check(_map.presses == map_before, "滚轮不穿透地图")
	_check(WorldTime.elapsed_seconds > time_before, "阅读期间世界时间继续")
	var reading_position := _ui.narrative.get_v_scroll_bar().value
	await _send(_key(KEY_ESCAPE, true))
	_check(get_tree().paused and _ui.is_text_open(), "Esc 暂停且保留文本")
	await _send(_key(KEY_ESCAPE, false))
	await _send(_key(KEY_ESCAPE, true))
	await _send(_key(KEY_ESCAPE, false))
	_check(not get_tree().paused and _ui.is_text_open(), "Esc 恢复并返回原文本")
	_check(_ui.narrative.get_v_scroll_bar().value == reading_position, "暂停恢复保留阅读位置")
	map_before = _map.presses
	await _click(c.get_center(), 0.02)
	_check(not _ui.is_text_open() and _requests.size() == 6, "文本上的点击只关闭，不触发底层按钮")
	_check(_map.presses == map_before, "关闭点击及释放不穿透地图")
	_ui.show_text("按键关闭测试")
	await _send(_key(KEY_SPACE, true))
	var repeat_event := _key(KEY_SPACE, true)
	repeat_event.echo = true
	await _send(repeat_event)
	await _send(_key(KEY_SPACE, false))
	_check(not _ui.is_text_open() and _requests.size() == 6, "按键关闭后的重复及释放不激活 UI")
	# 不匹配的地点不出现文本。
	WorldState.move_to(&"unconfigured_location")
	await _click(a.get_center(), 0.02)
	_check(not _ui.is_text_open(), "仅匹配地点与操作的规则出现文本")
	WorldState.apply_changes({&"planet_name": "测试星球", &"planet_layer": "下层"}, &"surface")
	_check(_ui.planet_label.text == "测试星球" and _ui.layer_label.text == "下层", "地点与层级随世界状态刷新")
	# 循环结束时替换普通文本，关闭后正确重置。
	WorldTime.advance_time(WorldTime.get_remaining_seconds())
	_check(_ui.is_text_open() and WorldTime.phase == WorldTime.Phase.ENDED, "循环终点展示回溯文本")
	await _send(_key(KEY_ENTER, true))
	await _send(_key(KEY_ENTER, false))
	_check(WorldTime.phase == WorldTime.Phase.RUNNING and WorldTime.loop_index == 2, "关闭回溯文本开始下一轮")
	await _test_short_wait()
	print("PLANET_EXPLORATION_UI_TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _test_short_wait() -> void:
	# 使用实际按钮输入，再手动推进帧时间，精确检查耗时口径和倍率恢复。
	WorldTime.set_process(false)
	WorldTime.set_flow_rate(2.0)
	var wait_position := _ui.buttons[2].get_global_rect().get_center()
	var before := WorldTime.elapsed_seconds
	await _click(wait_position, 0.02)
	_check(_ui.is_text_open() and WorldTime.flow_rate == 10.0, "短按等待打开文本并立即加速")
	_check(WorldTime.elapsed_seconds == before, "短按等待不额外扣除十秒")
	WorldTime._process(0.25)
	_check(is_equal_approx(WorldTime.elapsed_seconds - before, 2.5), "等待期间世界按十倍速推进")
	PauseController.set_paused(true)
	before = WorldTime.elapsed_seconds
	WorldTime._process(1.0)
	_check(WorldTime.elapsed_seconds == before and _ui.is_text_open(), "等待期间暂停冻结时间并保留文本")
	PauseController.set_paused(false)
	_check(WorldTime.flow_rate == 10.0, "暂停恢复后继续等待加速")
	await _send(_mouse(MOUSE_BUTTON_WHEEL_DOWN, true, Vector2(960, 500)))
	_check(_ui.is_text_open() and WorldTime.flow_rate == 10.0, "滚轮阅读不结束等待")
	await _send(_key(KEY_SPACE, true))
	await _send(_key(KEY_SPACE, false))
	_check(not _ui.is_text_open() and WorldTime.flow_rate == 2.0, "按键关闭等待文本恢复之前倍率")
	WorldTime._process(0.25)
	_check(is_equal_approx(WorldTime.elapsed_seconds - before, 0.5), "关闭后按原倍率继续计时")
	await _click(_ui.buttons[0].get_global_rect().get_center(), 0.02)
	_check(_ui.is_text_open() and WorldTime.flow_rate == 2.0, "普通观察文本不会加速")
	_ui.close_text()
	before = WorldTime.elapsed_seconds
	await _click(wait_position, 0.62)
	_check(_ui.is_text_open() and WorldTime.flow_rate == 2.0 \
		and is_equal_approx(WorldTime.elapsed_seconds - before, 60.0), "长按等待保留一分钟耗时")
	_ui.close_text()
	# 等待时到达循环终点，不能让加速泄漏到回溯文本或下一轮。
	await _click(wait_position, 0.02)
	var previous_loop := WorldTime.loop_index
	WorldTime.advance_time(WorldTime.get_remaining_seconds())
	_check(WorldTime.phase == WorldTime.Phase.ENDED and WorldTime.flow_rate == 1.0 \
		and _ui.is_text_open(), "加速等待到终点后显示回溯文本并还原倍率")
	await _send(_key(KEY_ENTER, true))
	await _send(_key(KEY_ENTER, false))
	_check(WorldTime.loop_index == previous_loop + 1 and WorldTime.flow_rate == 1.0, "下一轮不残留等待加速")
	# 关闭点击不能穿透，暂停期间程序关闭文本也要在恢复时还原。
	await _click(wait_position, 0.02)
	await _click(wait_position, 0.02)
	_check(not _ui.is_text_open() and WorldTime.flow_rate == 1.0, "点击关闭等待文本且不会再次开始等待")
	WorldTime.set_flow_rate(3.0)
	await _click(wait_position, 0.02)
	PauseController.set_paused(true)
	_ui.close_text()
	PauseController.set_paused(false)
	_check(WorldTime.flow_rate == 3.0, "暂停期间程序关闭等待文本在恢复时还原倍率")
	await _click(wait_position, 0.02)
	PauseController.set_paused(true)
	_screen.queue_free()
	await get_tree().process_frame
	PauseController.set_paused(false)
	_check(WorldTime.flow_rate == 3.0, "暂停期间卸载等待场景不遗留加速")
	WorldTime.set_flow_rate(1.0)
	WorldTime.set_process(true)


func _click(position: Vector2, duration: float, release_position: Vector2 = Vector2.INF) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	await _send(motion)
	await _send(_mouse(MOUSE_BUTTON_LEFT, true, position))
	await get_tree().create_timer(duration, true).timeout
	var finish := position if release_position == Vector2.INF else release_position
	if finish != position:
		motion = InputEventMouseMotion.new()
		motion.position = finish
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		await _send(motion)
	await _send(_mouse(MOUSE_BUTTON_LEFT, false, finish))


func _send(event: InputEvent) -> void:
	get_viewport().push_input(event, true)
	await get_tree().process_frame


func _mouse(index: MouseButton, pressed: bool, position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = position
	event.global_position = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and index == MOUSE_BUTTON_LEFT else 0
	return event


func _key(code: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	return event


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
