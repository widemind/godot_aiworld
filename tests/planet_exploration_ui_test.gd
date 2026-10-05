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
	_screen = preload("res://scenes/ui/exploration/planet_exploration.tscn").instantiate()
	add_child(_screen)
	_ui = _screen.get_node("PlanetExplorationUI")
	_ui.action_requested.connect(func(id: StringName, held: bool) -> void: _requests.append({"id": id, "held": held}))
	await get_tree().process_frame
	await get_tree().process_frame
	_test_text_database()
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
	await _test_guide()
	await _test_information_list()
	# 循环结束时替换普通文本，关闭后正确重置。
	var loop_before := WorldTime.loop_index
	WorldTime.advance_time(WorldTime.get_remaining_seconds())
	_check(_ui.is_text_open() and WorldTime.phase == WorldTime.Phase.ENDED, "循环终点展示回溯文本")
	await _send(_key(KEY_ENTER, true))
	await _send(_key(KEY_ENTER, false))
	_check(WorldTime.phase == WorldTime.Phase.RUNNING and WorldTime.loop_index == loop_before + 1, "关闭回溯文本开始下一轮")
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


func _test_information_list() -> void:
	WorldTime.set_process(false)
	var count_before := WorldState.get_collected_information().size()
	await _click(_ui.buttons[0].get_global_rect().get_center(), 0.02)
	_check(TextDatabase.get_record_texts().has(_ui.narrative.text), "探索成功反馈通过兼容接口加入 TextDatabase")
	_check(WorldState.get_collected_information().size() == count_before, "再次获取相同探索文本不会重复收集")
	_ui.close_text()
	var short_text := "最近获得的短文本。"
	var long_text := "较早获得的长文本会根据宽度自动换行。".repeat(30) + "\n\n保留段落。\n\n".repeat(35)
	_check(WorldState.record_information(long_text), "可记录长文本")
	_check(WorldState.record_information(short_text), "可记录短文本")
	_check(not WorldState.record_information("  \n"), "不记录空文本")
	# 原阅读框在子页关闭后仍保留原位置。
	_ui.show_text("保留的阅读文本。\n\n".repeat(40))
	await get_tree().process_frame
	await get_tree().process_frame
	_ui.narrative.get_v_scroll_bar().value = 80
	var reading_position := _ui.narrative.get_v_scroll_bar().value
	var clock := _ui.clock_label.text
	var time_before := WorldTime.elapsed_seconds
	PauseController.set_paused(true)
	await _click(_ui.get_node("%InformationListButton").get_global_rect().get_center(), 0.02)
	var page := _ui.information_list
	await get_tree().process_frame
	await get_tree().process_frame
	_check(page.visible and not _ui.pause_modal.visible and get_tree().paused, "暂停菜单按钮进入列表并保持暂停")
	_check(page.location_label.text == "测试星球" and page.clock_label.text == clock, "列表标题是打开时的地点与世界时间")
	_check(page.layer_label.text == "下层", "星球层级保留在顶部")
	var first := page.entries.get_child(1) as PanelContainer
	var second := page.entries.get_child(2) as PanelContainer
	_check(first.get_node("Text").text == short_text and second.get_node("Text").text == long_text, "文本按获取顺序从晚到早排列")
	_check(second.size.y > first.size.y and first.size.y < 150, "文本框按行数增高，短文本没有固定的大块空白")
	_check(first.get_child_count() == 1, "条目仅展示正文，没有时间地点")
	_check(not page.scroll.get_v_scroll_bar().visible and not page.scroll.get_h_scroll_bar().visible, "两个滚动条均隐藏")
	var original_scale_size := get_window().content_scale_size
	var original_height := second.size.y
	get_window().content_scale_size = Vector2i(960, 540)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(second.size.y > original_height, "窄窗口中正文重新换行并增加文本框高度")
	_check(first.size.x <= page.scroll.size.x and page.back_button.get_global_rect().end.x <= page.get_global_rect().end.x, "窄窗口条目和返回按钮不横向溢出")
	get_window().content_scale_size = original_scale_size
	await get_tree().process_frame
	await get_tree().process_frame
	await _send(_mouse(MOUSE_BUTTON_WHEEL_DOWN, true, page.scroll.get_global_rect().get_center()))
	_check(page.scroll.scroll_vertical > 0 and page.visible, "暂停时可滚动长信息列表")
	WorldTime._process(1.0)
	_check(WorldTime.elapsed_seconds == time_before, "信息列表内世界时间冻结")
	await _send(_key(KEY_ESCAPE, true))
	await _send(_key(KEY_ESCAPE, false))
	_check(not page.visible and _ui.pause_modal.visible and get_tree().paused, "Esc 返回暂停菜单，不解除暂停")
	_check(_ui.is_text_open() and _ui.narrative.get_v_scroll_bar().value == reading_position, "返回保留原阅读位置")
	_ui._on_information_list_pressed()
	await get_tree().process_frame
	_check(page.scroll.scroll_vertical == 0, "重开列表从最新文本开始")
	if page.back_button.is_visible_in_tree():
		await _click(page.back_button.get_global_rect().get_center(), 0.02)
	else:
		await _send(_key(KEY_ESCAPE, true))
		await _send(_key(KEY_ESCAPE, false))
	_check(not page.visible and get_tree().paused, "列表返回暂停菜单（兼容编辑器隐藏返回按钮）")
	PauseController.set_paused(false)
	_ui.close_text()
	WorldState.apply_changes({&"in_space": true}, &"space")
	PauseController.set_paused(true)
	_ui._on_information_list_pressed()
	_check(page.location_label.text == "太空" and page.layer_label.text.is_empty(), "太空显示太空，不显示旧星球及层级")
	# 页面标题不被后续 UI 更新改写。
	_ui.set_location("其他星球", "一层")
	_check(page.location_label.text == "太空", "地点标题保持打开时的快照")
	PauseController.set_paused(false)
	_check(not page.visible and not _ui.pause_modal.visible, "外部解除暂停会关闭子页")
	var no_texts: Array[String] = []
	page.open("太空", "00:00", "", no_texts)
	_check(page.empty_label.visible and page.entries.get_child_count() == 1, "空列表显示尚未获取提示，并清理旧条目")
	page.close()
	WorldState.apply_changes({&"in_space": false, &"planet_name": "水星", &"planet_layer": "上层"}, &"surface")
	var count := WorldState.get_collected_information().size()
	WorldTime.advance_time(WorldTime.get_remaining_seconds())
	_check(WorldState.get_collected_information().size() == count, "回溯提示不作为获取信息记录")
	_ui.close_text()
	await get_tree().process_frame
	_check(WorldState.get_collected_information().size() == count, "信息记录跨世界循环保留")
	WorldTime.set_process(true)


func _test_text_database() -> void:
	var first := TextPieces.new()
	first.text = "数据库第一条文本。"
	first.in_information_list = true
	var second := TextPieces.new()
	second.text = "数据库第二条文本。"
	second.in_information_list = true
	var ignored := TextPieces.new()
	ignored.text = "只展示，不收集的提示。"
	var collection_time := WorldTime.elapsed_seconds
	TextDatabase.collect_text(null)
	TextDatabase.collect_text(first)
	_check(TextDatabase.get_record_texts() == [first.text], "只有一条记录时也返回第一条文本")
	TextDatabase.collect_text(second)
	TextDatabase.collect_text(first.duplicate(true))
	TextDatabase.collect_text(ignored)
	var blank := TextPieces.new()
	blank.in_information_list = true
	blank.text = " \n"
	TextDatabase.collect_text(blank)
	_check(TextDatabase.get_record_texts() == [second.text, first.text], "数据库倒序完整返回，副本去重，提示与空文本不收集")
	_check(first.text_collection_id == 1 and second.text_collection_id == 2 \
		and first.text_collected_cycle_num == WorldTime.loop_index \
		and first.text_collected_time == collection_time, "收集顺序及首次获取的循环时间正确")
	_ui.show_text_piece(ignored)
	_check(_ui.narrative.text == ignored.text and TextDatabase.text_collection_list.size() == 2, "TextPieces 可显示而不加入信息列表")
	_ui.close_text()
	_ui.show_text_piece(second)
	_check(_ui.narrative.text == second.text and TextDatabase.text_collection_list.size() == 2, "已收集的 TextPieces 展示时不会重复记录")
	_ui.close_text()
	var copy := TextDatabase.get_record_texts()
	copy.clear()
	_check(TextDatabase.get_record_texts().size() == 2, "返回数组不暴露数据库内部记录")


func _test_guide() -> void:
	WorldTime.set_process(false)
	var page := _ui.guide
	var author_text := page.tutorial.text
	page.tutorial.text = "教程测试正文会随宽度换行。".repeat(24) + "\n\n居中的教程段落。\n\n".repeat(40)
	_ui.show_text("保留的游戏正文。\n\n".repeat(40))
	await get_tree().process_frame
	await get_tree().process_frame
	_ui.narrative.get_v_scroll_bar().value = 80
	var reading_position := _ui.narrative.get_v_scroll_bar().value
	var time_before := WorldTime.elapsed_seconds
	var information_count := WorldState.get_collected_information().size()
	PauseController.set_paused(true)
	await _click(_ui.get_node("%GuideButton").get_global_rect().get_center(), 0.02)
	_check(page.visible and not _ui.pause_modal.visible and get_tree().paused, "指南按钮打开指南并保持世界暂停")
	_check(page.location_label.text == "测试星球" and page.layer_label.text == "下层" \
		and page.clock_label.text == _ui.clock_label.text, "指南标题显示打开时的时间与地点")
	_check(page.tutorial.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "教程正文居中对齐")
	_check(page.tutorial.text.contains("教程测试正文"), "打开指南保留作者填写的正文")
	await get_tree().process_frame
	await _send(_mouse(MOUSE_BUTTON_WHEEL_DOWN, true, page.scroll.get_global_rect().get_center()))
	_check(page.scroll.scroll_vertical > 0 and page.visible, "暂停中可滚动长教程")
	_check(not page.scroll.get_v_scroll_bar().visible, "教程滚动条隐藏")
	WorldTime._process(1.0)
	_check(WorldTime.elapsed_seconds == time_before, "阅读指南不推进世界时间")
	_ui.set_location("其他星球", "一层")
	_ui._on_time_changed(0.0, 123.0)
	_check(page.location_label.text == "测试星球" and page.clock_label.text != "02:03", "指南标题保持打开时的快照")
	var original_scale_size := get_window().content_scale_size
	var original_height := page.tutorial.size.y
	get_window().content_scale_size = Vector2i(960, 540)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(page.tutorial.size.y > original_height and page.tutorial.size.x <= page.scroll.size.x, "窄窗口教程自动换行且不横向溢出")
	get_window().content_scale_size = original_scale_size
	await get_tree().process_frame
	await get_tree().process_frame
	await _send(_key(KEY_ESCAPE, true))
	var repeat_escape := _key(KEY_ESCAPE, true)
	repeat_escape.echo = true
	await _send(repeat_escape)
	await _send(_key(KEY_ESCAPE, false))
	_check(not page.visible and _ui.pause_modal.visible and get_tree().paused, "Esc 及重复输入仅返回暂停菜单")
	_check(_ui.is_text_open() and _ui.narrative.get_v_scroll_bar().value == reading_position, "指南返回保留原游戏阅读位置")
	_ui._on_guide_pressed()
	await get_tree().process_frame
	_check(page.scroll.scroll_vertical == 0, "重新打开教程从顶部开始")
	PauseController.set_paused(false)
	_check(not page.visible and not _ui.pause_modal.visible, "外部恢复游戏会关闭指南")
	_ui.close_text()
	WorldState.apply_changes({&"in_space": true}, &"space")
	PauseController.set_paused(true)
	_ui._on_guide_pressed()
	_check(page.location_label.text == "太空" and page.layer_label.text.is_empty(), "指南在太空显示太空并隐藏层级")
	await _send(_key(KEY_ENTER, true))
	await _send(_key(KEY_ENTER, false))
	_check(not page.visible and get_tree().paused, "确认键返回不会穿透并恢复游戏")
	PauseController.set_paused(false)
	page.tutorial.text = author_text
	WorldState.apply_changes({&"in_space": false, &"planet_name": "测试星球", &"planet_layer": "下层"}, &"surface")
	_ui._on_time_changed(0.0, WorldTime.elapsed_seconds)
	_check(WorldState.get_collected_information().size() == information_count, "指南不作为获取信息加入列表")
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
