extends Node
## 使用真正的 Viewport 输入分发，检查模态输入不会穿透地图与按钮。

class MapSpy extends Control:
	var presses: int = 0
	func _input(event: InputEvent) -> void:
		if event.is_pressed():
			presses += 1

class CustomTextSelector extends TextSelector:
	var chosen: TextPieces
	func special_text_selection(_action: StringName) -> TextPieces:
		return chosen

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
		_drain_texts()
		await _click(button.get_global_rect().get_center(), 0.62)
		_check(_ui.is_text_open() and _requests[-1].held, "长按识别并产生文本")
		_drain_texts()
	_check(_requests.size() == 6, "三按钮共六次操作，无长短按双触发")
	# 长按中暂停会取消正在按住的操作，恢复后松开不结算。
	await _send(_mouse(MOUSE_BUTTON_LEFT, true, a.get_center()))
	PauseController.set_paused(true)
	PauseController.set_paused(false)
	await _send(_mouse(MOUSE_BUTTON_LEFT, false, a.get_center()))
	_check(_requests.size() == 6, "暂停取消按压，恢复后的松开不触发")
	await _click(a.get_center(), 0.02, Vector2(960, 500))
	_check(_requests.size() == 6, "移出按钮松开取消操作")
	_ui.show_text("滚动测试长段落，自动换行不拆成新文本框。".repeat(100))
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
	await _test_paragraphs()
	await _test_text_queue()
	await _test_text_selector()
	await _test_wait_controller()
	await _test_guide()
	await _test_information_list()
	await _test_loop_end_modal()
	await _test_wait_until_loop_end()
	# 循环结束时替换普通文本，关闭后正确重置。
	var loop_before := WorldTime.loop_index
	WorldTime.advance_time(WorldTime.get_remaining_seconds())
	_check(_ui.is_loop_end_text_open() and WorldTime.phase == WorldTime.Phase.ENDED \
		and _ui.loop_end_shade.visible, "自然循环终点展示居中结束文本与遮罩")
	await _send(_key(KEY_ENTER, true))
	await _send(_key(KEY_ENTER, false))
	_check(WorldTime.phase == WorldTime.Phase.ENDED and _ui.is_text_open(), "回溯提示第一段关闭后仍需读完后续段落")
	await _dismiss_remaining_texts()
	_check(WorldTime.phase == WorldTime.Phase.RUNNING and WorldTime.loop_index == loop_before + 1, "关闭回溯文本开始下一轮")
	await _test_world_journey_ui()
	await _test_short_wait()
	print("PLANET_EXPLORATION_UI_TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _test_loop_end_modal() -> void:
	WorldTime.set_process(false)
	_ui.show_loop_end_text("居中结束文本滚动测试。".repeat(100) + "\n第二段结束文本。")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_ui.is_loop_end_text_open() and _ui.loop_end_shade.visible \
		and _ui.loop_end_shade.color.a > 0.0 and _ui.action_bar.visible, "结束文本显示遮罩并保留下层变暗的 UI")
	_check(_ui.loop_end_panel.get_global_rect().get_center().distance_to(_ui.get_global_rect().get_center()) < 1.0, \
		"结束文本框位于屏幕正中间")
	var map_before := _map.presses
	var requests_before := _requests.size()
	await _send(_mouse(MOUSE_BUTTON_WHEEL_DOWN, true, Vector2(960, 500)))
	_check(_ui.is_loop_end_text_open() and _ui.narrative.get_v_scroll_bar().value > 0.0 \
		and not _ui.narrative.get_v_scroll_bar().visible, "结束文本同样支持滚轮，不关闭且隐藏滚动条")
	var scroll := _ui.narrative.get_v_scroll_bar().value
	PauseController.set_paused(true)
	PauseController.set_paused(false)
	_check(_ui.is_loop_end_text_open() and _ui.narrative.get_v_scroll_bar().value == scroll, "暂停恢复保留结束页面及阅读位置")
	await _click(_ui.buttons[2].get_global_rect().get_center(), 0.02)
	_check(_ui.narrative.text == "第二段结束文本。" and _ui.is_loop_end_text_open() \
		and _map.presses == map_before and _requests.size() == requests_before, "点击切换结束段落，不穿透下层按钮和地图")
	await _send(_key(KEY_SPACE, true))
	await _send(_key(KEY_SPACE, false))
	_check(not _ui.is_text_open() and not _ui.loop_end_shade.is_visible_in_tree(), "读完结束文本隐藏页面和遮罩")
	_ui.show_text("普通探索正文。")
	_check(not _ui.is_loop_end_text_open() and not _ui.loop_end_shade.visible \
		and _ui.narrative == _ui.exploration_narrative, "下一条普通文本仍使用原探索面板")
	_ui.close_text()
	WorldTime.set_process(true)


func _test_wait_until_loop_end() -> void:
	WorldTime.set_process(false)
	var waiting := _screen.get_node("WaitController")
	var skip: Button = _ui.get_node("%WaitUntilLoopEndButton")
	var resume: Button = _ui.get_node("%ResumeButton")
	var info: Button = _ui.get_node("%InformationListButton")
	_check(skip.get_index() == resume.get_index() + 1 and info.get_index() == skip.get_index() + 1, \
		"等待至循环结束位于继续按钮下面、信息列表上面")
	WorldTime.set_flow_rate(2.0)
	_check(waiting.request_wait(), "暂停菜单结束循环前已有加速等待")
	_ui.show_text("等待至终点前的排队文本。")
	var record_count := TextDatabase.get_record_texts().size()
	var event_piece := TextPieces.new()
	event_piece.text = "主动等待至终点期间收集的信息。"
	event_piece.in_information_list = true
	var reached: Array[StringName] = []
	var on_event := func(event: WorldTimeEvent) -> void:
		if event.event_id in [&"skip_zero", &"skip_middle", &"skip_last"]:
			reached.append(event.event_id)
			if event.event_id == &"skip_last":
				_ui.show_text_piece(event_piece)
				WorldState.record_knowledge(&"skip_loop_knowledge")
	WorldTime.event_reached.connect(on_event)
	for index in 3:
		var event := WorldTimeEvent.new()
		event.event_id = [&"skip_zero", &"skip_middle", &"skip_last"][index]
		event.at_seconds = WorldTime.elapsed_seconds + [0.0, 2.0, 3.0][index]
		event.stop_advancement = index < 2
		_check(WorldTime.schedule_event(event), "注册主动等待至终点事件")
	var before_loop := WorldTime.loop_index
	PauseController.set_paused(true)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not skip.disabled and skip.get_global_rect().position.y > resume.get_global_rect().end.y \
		and info.get_global_rect().position.y > skip.get_global_rect().end.y, "暂停菜单新增按钮可用且纵向顺序正确")
	await _click(skip.get_global_rect().get_center(), 0.02)
	_check(get_tree().paused and WorldTime.loop_index == before_loop \
		and WorldTime.phase == WorldTime.Phase.RUNNING, "等待至终点短按不触发")
	var held: ExplorationActionButton = skip as ExplorationActionButton
	_check(is_equal_approx(held.long_press_seconds, _ui.buttons[0].long_press_seconds), "菜单复用探索按钮的长按阈值")
	await _send(_mouse(MOUSE_BUTTON_LEFT, true, skip.get_global_rect().get_center()))
	await get_tree().create_timer(0.12, true).timeout
	_check(held.hold_progress.visible and held.hold_progress.value > 0.0, "暂停期间长按仍显示探索同款进度")
	await _send(_mouse(MOUSE_BUTTON_LEFT, false, Vector2(10, 10)))
	_check(get_tree().paused and WorldTime.phase == WorldTime.Phase.RUNNING, "长按移出菜单按钮松开取消")
	await _send(_mouse(MOUSE_BUTTON_LEFT, true, skip.get_global_rect().get_center()))
	PauseController.set_paused(false)
	PauseController.set_paused(true)
	await _send(_mouse(MOUSE_BUTTON_LEFT, false, skip.get_global_rect().get_center()))
	_check(get_tree().paused and WorldTime.phase == WorldTime.Phase.RUNNING \
		and not held.hold_progress.visible, "关闭再打开暂停取消尚未完成的长按")
	await _click(skip.get_global_rect().get_center(), 0.62)
	_check(not get_tree().paused and not _ui.pause_modal.visible and _ui.is_text_open(), \
		"长按关闭暂停并展示结束前已收集的事件文本")
	_check(WorldTime.phase == WorldTime.Phase.ENDED and WorldTime.loop_index == before_loop \
		and WorldTime.flow_rate == 1.0 and not waiting.is_waiting(), "长按只推进至终点，不提前开启下一轮")
	await _click(Vector2(960, 540), 0.02)
	_check(_ui.is_loop_end_text_open() and _ui.loop_end_shade.visible \
		and _ui.narrative.text.contains("太阳的光"), "事件文本点完后展示相同的居中结束页面")
	await _send(_key(KEY_SPACE, true))
	var repeated := _key(KEY_SPACE, true)
	repeated.echo = true
	await _send(repeated)
	await _send(_key(KEY_SPACE, false))
	_check(_ui.narrative.text == "世界正在回溯。" and WorldTime.loop_index == before_loop, \
		"结束页逐段关闭，重复输入和释放不跳过下一段或提前重置")
	await _dismiss_remaining_texts()
	_check(WorldTime.phase == WorldTime.Phase.RUNNING and WorldTime.loop_index == before_loop + 1 \
		and WorldTime.elapsed_seconds == 0.0 and not _ui.is_text_open(), "全部结束段落读完后仅进入下一轮一次")
	_check(reached == [&"skip_zero", &"skip_middle", &"skip_last"], \
		"零时刻和中途停止事件仍按顺序处理，推进持续到循环终点")
	_check(TextDatabase.get_record_texts().size() == record_count + 1 \
		and TextDatabase.get_record_texts().has(event_piece.text) and WorldState.knows(&"skip_loop_knowledge"), \
		"循环结束保留已有信息与途中获取的信息、知识")
	_check(WorldState.player_location == &"surface" and WorldState.get_flag(&"planet_name") == "水星", \
		"下一轮正常恢复初始地点及世界状态")
	WorldTime.event_reached.disconnect(on_event)
	# 正在执行的定时行动也不会让等待提前停在行动完成点。
	var action := WorldAction.new()
	action.action_id = &"skip_loop_active_action"
	action.duration_seconds = 2.0
	_check(ActionController.execute_timed(action, 3.0), "主动结束循环前启动定时行动")
	PauseController.set_paused(true)
	await get_tree().process_frame
	before_loop = WorldTime.loop_index
	await _click(skip.get_global_rect().get_center(), 0.62)
	_check(WorldTime.loop_index == before_loop and WorldTime.phase == WorldTime.Phase.ENDED \
		and _ui.is_loop_end_text_open() and not ActionController.is_busy() and not get_tree().paused, \
		"进行中的行动完成后仍推进到终点并展示结束页面")
	await _dismiss_remaining_texts()
	_check(WorldTime.loop_index == before_loop + 1 and WorldTime.elapsed_seconds == 0.0, "读完结束页面再开启新循环")
	WorldTime.set_process(true)


func _test_world_journey_ui() -> void:
	WorldTime.set_process(false)
	WorldState.apply_changes({&"ui_progress": true}, &"surface")
	var checkpoint := WorldState.capture_snapshot()
	var loop_before := WorldTime.loop_index
	_check(_ui.clock_label.text.begins_with("第 %d 轮 · " % loop_before) \
		and not _ui.has_node("Header/Content/RemainingLabel") \
		and not _ui.has_node("Header/Content/WorldSwitchButton"), "轮次在时间前，探索界面不含世界切换和剩余时间")
	_ui.set_header_visible(false)
	WorldTime.advance_time(1.0)
	_ui.set_location("隐藏时更新的地点", "下层")
	_check(not _ui.header.visible and _ui.planet_label.text == "隐藏时更新的地点", "隐藏顶部仍持续更新数据")
	_ui.set_header_visible(true)
	_check(_ui.header.visible and _ui.clock_label.text.ends_with("00:01"), "顶部可重新显示最新时间与地点")
	var waiting := _screen.get_node("WaitController")
	_check(waiting.request_wait(), "世界切换前开始等待")
	_check(WorldJourney.return_to_reality(), "剧情接口可切换到现实")
	_check(not waiting.is_waiting() and WorldTime.flow_rate == 1.0 and not _ui.is_text_open(), "世界切换清理等待与加速")
	_check(WorldTime.world == WorldTime.World.REAL and WorldTime.elapsed_seconds == 0.0, "剧情切换现实从零计时")
	_check(_ui.clock_label.text == "第 %d 轮 · 00:00" % loop_before, "现实 HUD 仅显示轮次与当前时间")
	PauseController.set_paused(true)
	_check(_ui.get_node("%WaitUntilLoopEndButton").disabled and not waiting.wait_until_loop_end() \
		and get_tree().paused and WorldTime.elapsed_seconds == 0.0, "现实世界不执行虚拟循环结束按钮")
	PauseController.set_paused(false)
	WorldState.apply_changes({&"real_ui_progress": true}, &"reality")
	WorldState.record_knowledge(&"ui_shared_knowledge")
	WorldState.record_information("失败后保留的信息")
	var real_checkpoint := WorldState.capture_snapshot()
	var original_wait_piece: TextPieces = waiting.short_wait_text
	var real_wait_piece := TextPieces.new()
	real_wait_piece.text = "现实结束前正在阅读的文本。"
	waiting.short_wait_text = real_wait_piece
	_check(waiting.request_wait(), "现实世界未配置地点文本时也能等待")
	waiting.short_wait_text = original_wait_piece
	WorldTime.advance_time(WorldTime.get_remaining_seconds())
	_check(not waiting.is_waiting() and WorldTime.flow_rate == 1.0, "现实终点结束等待并清理加速")
	_check(WorldJourney.failed and WorldTime.phase == WorldTime.Phase.ENDED \
		and _ui.buttons[0].disabled, "现实失败停止行动")
	_check(_ui.narrative.text == "现实结束前正在阅读的文本。", "失败提示不覆盖正在阅读的文本")
	await _send(_key(KEY_ENTER, true))
	await _send(_key(KEY_ENTER, false))
	_check(WorldTime.world == WorldTime.World.REAL and _ui.narrative.text.contains("游戏失败"), "先显示失败提示，读完前不重试")
	PauseController.set_paused(true)
	_drain_texts()
	await get_tree().process_frame
	_check(WorldJourney.failed and WorldTime.world == WorldTime.World.REAL, "暂停中关闭失败文本不会切换世界")
	PauseController.set_paused(false)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not WorldJourney.failed and WorldTime.world == WorldTime.World.VIRTUAL \
		and WorldTime.loop_index == loop_before and WorldTime.elapsed_seconds == 0.0, "恢复后回到同一虚拟循环，从零重试")
	_check(WorldState.capture_snapshot() == checkpoint and not _ui.is_text_open(), "重试保留虚拟进度并清理失败文本")
	_check(WorldState.knows(&"ui_shared_knowledge") and TextDatabase.get_record_texts().has("失败后保留的信息"), "失败重试保留知识与信息")
	_check(WorldJourney.return_to_reality(), "剧情接口再次进入现实")
	_check(WorldState.capture_snapshot() == real_checkpoint and WorldTime.elapsed_seconds == 0.0, "再次进入现实保留现实进度并重新计时")
	WorldTime.advance_time(1.0)
	# 场景卸载/重载不会丢失常驻流程，失败界面重载也不能误开虚拟新轮。
	await _reload_exploration()
	_check(WorldTime.world == WorldTime.World.REAL and WorldTime.elapsed_seconds == 1.0 \
		and not _ui.is_text_open(), "运行中的现实世界重载场景不重置计时")
	WorldTime.advance_time(WorldTime.get_remaining_seconds())
	await _reload_exploration()
	_check(WorldJourney.failed and WorldTime.world == WorldTime.World.REAL \
		and _ui.narrative.text.contains("游戏失败"), "失败时重载场景仍显示失败提示")
	await _dismiss_remaining_texts()
	_check(WorldTime.world == WorldTime.World.VIRTUAL and WorldTime.loop_index == loop_before \
		and WorldState.capture_snapshot() == checkpoint, "重载后的失败提示可正常重试同一循环")
	WorldTime.advance_time(WorldTime.get_remaining_seconds())
	await _dismiss_remaining_texts()
	_check(WorldTime.loop_index == loop_before + 1, "重试后的虚拟世界仍可以正常开启下一轮")
	WorldTime.set_process(true)


func _reload_exploration() -> void:
	_screen.queue_free()
	await get_tree().process_frame
	_screen = preload("res://scenes/ui/exploration/planet_exploration.tscn").instantiate()
	add_child(_screen)
	_ui = _screen.get_node("PlanetExplorationUI")
	await get_tree().process_frame
	await get_tree().process_frame


func _test_short_wait() -> void:
	# 使用实际按钮输入，再手动推进帧时间，精确检查耗时口径和倍率恢复。
	# 测试多段等待提示，场景内的作者正文保持原样。
	var waiting := _screen.get_node("WaitController")
	var paragraph_piece: TextPieces = waiting.short_wait_text.duplicate(true)
	paragraph_piece.text = "你在原地等待，时间加速流逝。\n关闭文本框以结束等待。"
	waiting.short_wait_text = paragraph_piece
	WorldTime.set_process(false)
	WorldTime.set_flow_rate(2.0)
	var wait_position := _ui.buttons[2].get_global_rect().get_center()
	var before := WorldTime.elapsed_seconds
	await _click(wait_position, 0.02)
	_check(_ui.is_text_open() and WorldTime.flow_rate == 10.0, "短按等待打开文本并立即加速")
	_check(WorldTime.elapsed_seconds == before, "短按等待不额外扣除十秒")
	var wait_text := _ui.narrative.text
	_ui.show_text("等待期间收到的第一条事件文本。")
	_ui.show_text("等待期间收到的第二条事件文本。")
	_check(_ui.narrative.text == wait_text and WorldTime.flow_rate == 10.0, "排队事件不覆盖等待文本，也不提前结束加速")
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
	_check(_ui.is_text_open() and _ui.narrative.text == "关闭文本框以结束等待。" \
		and WorldTime.flow_rate == 2.0, "关闭等待第一段立即显示第二段，并在队列未读完时恢复之前倍率")
	WorldTime._process(0.25)
	_check(is_equal_approx(WorldTime.elapsed_seconds - before, 0.5), "关闭后按原倍率继续计时")
	_ui.close_text()
	_check(_ui.narrative.text == "等待期间收到的第一条事件文本。", "原文本的全部段落排在后来的事件文本之前")
	_ui.close_text()
	_check(_ui.narrative.text == "等待期间收到的第二条事件文本。" and WorldTime.flow_rate == 2.0, "后续排队文本按正常倍率阅读")
	_ui.close_text()
	await _click(_ui.buttons[0].get_global_rect().get_center(), 0.02)
	_check(_ui.is_text_open() and WorldTime.flow_rate == 2.0, "普通观察文本不会加速")
	_drain_texts()
	before = WorldTime.elapsed_seconds
	await _click(wait_position, 0.62)
	_check(_ui.is_text_open() and WorldTime.flow_rate == 2.0 \
		and is_equal_approx(WorldTime.elapsed_seconds - before, 60.0), "长按等待保留一分钟耗时")
	_drain_texts()
	# 等待时到达循环终点，不能让加速泄漏到回溯文本或下一轮。
	await _click(wait_position, 0.02)
	_ui.show_text("循环终点之前已排队的事件文本。")
	var previous_loop := WorldTime.loop_index
	WorldTime.advance_time(WorldTime.get_remaining_seconds())
	_check(WorldTime.phase == WorldTime.Phase.ENDED and WorldTime.flow_rate == 1.0 \
		and _ui.is_text_open(), "加速等待到终点后显示回溯文本并还原倍率")
	await _send(_key(KEY_ENTER, true))
	await _send(_key(KEY_ENTER, false))
	_check(_ui.narrative.text == "关闭文本框以结束等待。", "循环终点之后仍依次显示等待文本剩余段落")
	await _send(_key(KEY_ENTER, true))
	await _send(_key(KEY_ENTER, false))
	_check(WorldTime.loop_index == previous_loop and _ui.narrative.text == "循环终点之前已排队的事件文本。", "循环终点不丢弃已有队列，不提前开始下一轮")
	await _send(_key(KEY_ENTER, true))
	await _send(_key(KEY_ENTER, false))
	_check(WorldTime.loop_index == previous_loop and _ui.is_text_open() \
		and _ui.narrative.text.contains("太阳的光"), "循环终点的回溯文本排在等待文本之后，不提前重置")
	await _dismiss_remaining_texts()
	_check(WorldTime.loop_index == previous_loop + 1 and WorldTime.flow_rate == 1.0, "下一轮不残留等待加速")
	# 长按正好到终点时不展示/收集完成反馈。
	var unfinished := TextPieces.new()
	unfinished.text = "触及终点的等待不应生成这条完成信息。"
	unfinished.in_information_list = true
	var original_long_piece: TextPieces = waiting.long_wait_text
	waiting.long_wait_text = unfinished
	WorldTime.advance_time(WorldTime.get_remaining_seconds() - waiting.long_wait_seconds)
	_check(waiting.request_wait(true), "开始将触及终点的长按等待")
	_check(WorldTime.phase == WorldTime.Phase.ENDED and not waiting.is_waiting() \
		and not TextDatabase.get_record_texts().has(unfinished.text), "长按等待到终点取消普通反馈且不提前收集")
	waiting.long_wait_text = original_long_piece
	await _dismiss_remaining_texts()
	# 关闭点击不能穿透，暂停期间程序关闭文本也要在恢复时还原。
	await _click(wait_position, 0.02)
	await _click(wait_position, 0.02)
	_check(_ui.is_text_open() and WorldTime.flow_rate == 1.0, "点击关闭等待第一段并恢复倍率，不会再次开始等待")
	_drain_texts()
	WorldTime.set_flow_rate(3.0)
	await _click(wait_position, 0.02)
	_ui.show_text("暂停时关闭等待后仍需阅读的事件文本。")
	PauseController.set_paused(true)
	_ui.close_text()
	PauseController.set_paused(false)
	_check(WorldTime.flow_rate == 3.0 and _ui.is_text_open(), "暂停期间关闭等待文本后，恢复时还原倍率并保留下一条")
	_drain_texts()
	await _click(wait_position, 0.02)
	PauseController.set_paused(true)
	_screen.queue_free()
	await get_tree().process_frame
	PauseController.set_paused(false)
	_check(WorldTime.flow_rate == 3.0, "暂停期间卸载等待场景不遗留加速")
	WorldTime.set_flow_rate(1.0)
	WorldTime.set_process(true)


func _test_paragraphs() -> void:
	WorldTime.set_process(false)
	var piece := TextPieces.new()
	piece.text = "\r\n  \n第一段。\r\n\r\n第二段。\n \n第三段。\r"
	piece.in_information_list = true
	var count_before := TextDatabase.get_record_texts().size()
	_ui.show_text_piece(piece)
	_check(_ui.narrative.text == "第一段。", "传入多段 TextPieces 先显示第一段，跳过前导空行")
	_ui.show_text("后续请求第一段。\n后续请求第二段。")
	var requests_before := _requests.size()
	await _click(_ui.buttons[0].get_global_rect().get_center(), 0.02)
	_check(_ui.narrative.text == "第二段。" and _requests.size() == requests_before, "关闭第一段立即出现第二段，鼠标释放不再翻页或穿透按钮")
	PauseController.set_paused(true)
	_ui._on_information_list_pressed()
	await get_tree().process_frame
	await get_tree().process_frame
	var card := _ui.information_list.entries.get_child(1)
	_check(card.get_node("Text").text == piece.text, "信息列表仍在一个条目中显示完整原文及原始换行")
	_check(TextDatabase.get_record_texts().size() == count_before + 1, "多段文本只收集一条完整记录")
	await _send(_key(KEY_ESCAPE, true))
	await _send(_key(KEY_ESCAPE, false))
	PauseController.set_paused(false)
	_check(_ui.narrative.text == "第二段。", "信息列表返回保留当前段落和后续段落队列")
	await _send(_key(KEY_SPACE, true))
	var repeated := _key(KEY_SPACE, true)
	repeated.echo = true
	await _send(repeated)
	await _send(_key(KEY_SPACE, false))
	_check(_ui.narrative.text == "第三段。", "换行格式 LF/CRLF/CR 均正确处理，重复按键不跳段")
	_ui.close_text()
	_check(_ui.narrative.text == "后续请求第一段。", "原文全部段落读完后才显示后续请求")
	_ui.close_text()
	_check(_ui.narrative.text == "后续请求第二段。" and not _ui.action_bar.visible, "后续请求同样分段，读完前行动按钮持续隐藏")
	_ui.close_text()
	_check(not _ui.is_text_open() and _ui.action_bar.visible, "所有段落读完后才关闭文本界面")
	_ui.show_text("\n\r\n \n\t")
	_check(not _ui.is_text_open(), "纯空行不会产生空白文本框")
	_ui.show_text("  保留原有缩进与空格。  ")
	_check(_ui.narrative.text == "  保留原有缩进与空格。  ", "正文内容保留，只跳过空白段落")
	_ui.show_text("\n\n")
	_ui.close_text()
	_check(not _ui.is_text_open(), "空白请求不会排入队列")
	WorldTime.set_process(true)


func _test_text_queue() -> void:
	WorldTime.set_process(false)
	var closed_states: Array[String] = []
	var on_closed := func() -> void:
		closed_states.append(_ui.narrative.text if _ui.is_text_open() else "")
	_ui.text_closed.connect(on_closed)
	_ui.show_text("原文本滚动位置测试，自动换行保留在同一个段落。".repeat(80))
	await get_tree().process_frame
	await get_tree().process_frame
	_ui.narrative.get_v_scroll_bar().value = 80
	var original := _ui.narrative.text
	var position := _ui.narrative.get_v_scroll_bar().value
	_ui.show_text("第二条文本。")
	var third := TextPieces.new()
	third.text = "第三条 TextPieces 文本。"
	third.in_information_list = true
	_ui.show_text_piece(third)
	_check(_ui.narrative.text == original and _ui.narrative.get_v_scroll_bar().value == position \
		and closed_states.is_empty(), "新请求排队，不覆盖正在阅读的文本及滚动位置")
	var requests_before := _requests.size()
	var map_before := _map.presses
	await _click(_ui.buttons[2].get_global_rect().get_center(), 0.02)
	_check(_ui.narrative.text == "第二条文本。" and _ui.is_text_open() \
		and not _ui.action_bar.visible, "点掉当前文本后立即显示下一条且不露出行动按钮")
	_check(_requests.size() == requests_before and _map.presses == map_before, "换页点击及释放不穿透，不开启加速等待")
	_check(_ui.narrative.get_v_scroll_bar().value == 0, "下一条从正文顶部开始")
	await _send(_key(KEY_SPACE, true))
	var repeated := _key(KEY_SPACE, true)
	repeated.echo = true
	await _send(repeated)
	await _send(_key(KEY_SPACE, false))
	_check(_ui.narrative.text == third.text and _ui.is_text_open(), "按键关闭一条，重复及释放不会跳过下一条")
	_check(TextDatabase.get_record_texts().has(third.text), "排队的 TextPieces 正常收集")
	PauseController.set_paused(true)
	_ui.show_text("暂停期间排队的第四条文本。")
	PauseController.set_paused(false)
	_check(_ui.narrative.text == third.text, "暂停恢复保留当前文本及待显示队列")
	_ui.close_text()
	_check(_ui.narrative.text == "暂停期间排队的第四条文本。", "普通文本和 TextPieces 共用先进先出队列")
	_ui.close_text()
	_check(not _ui.is_text_open() and _ui.action_bar.visible and closed_states.size() == 4, "队列读完才关闭界面，每条文本均发出关闭通知")
	# 两个实际时间轴事件在同一时刻请求显示，按事件优先级排队。
	var event_one := WorldTimeEvent.new()
	event_one.event_id = &"queue_test_one"
	event_one.at_seconds = WorldTime.elapsed_seconds + 1.0
	var event_two := WorldTimeEvent.new()
	event_two.event_id = &"queue_test_two"
	event_two.at_seconds = event_one.at_seconds
	event_two.priority = 1
	var on_event := func(event: WorldTimeEvent) -> void:
		if event.event_id == event_one.event_id:
			_ui.show_text("时间轴事件一。")
		elif event.event_id == event_two.event_id:
			_ui.show_text("时间轴事件二。")
	WorldTime.event_reached.connect(on_event)
	_check(WorldTime.schedule_event(event_one) and WorldTime.schedule_event(event_two), "注册实际文本事件")
	_ui.show_text("时间轴事件发生前的正文。")
	WorldTime.advance_time(1.0)
	_check(_ui.narrative.text == "时间轴事件发生前的正文。", "实际时间轴事件在阅读时发生并排队")
	_ui.close_text()
	_check(_ui.narrative.text == "时间轴事件一。", "先展示较早处理的事件文本")
	_ui.close_text()
	_check(_ui.narrative.text == "时间轴事件二。", "再展示同一时刻后处理的事件文本")
	_ui.close_text()
	WorldTime.event_reached.disconnect(on_event)
	_ui.show_text("即将清理的当前文本。")
	_ui.show_text("即将清理的排队文本。")
	_ui.clear_texts()
	_ui.show_text("清理后的新文本。")
	_ui.close_text()
	_check(not _ui.is_text_open(), "主动清理不会把旧队列留给下次阅读")
	_ui.text_closed.disconnect(on_closed)
	WorldTime.set_process(true)


func _test_text_selector() -> void:
	WorldTime.set_process(false)
	var selector := TextSelector.new()
	var missing := TextPieces.new()
	missing.text = "缺失标记不应匹配。"
	missing.text_requirements = {&"selector_missing_flag": false}
	var future := TextPieces.new()
	future.text = "时间与事件条件满足后的正文。"
	future.time_requirements = WorldTime.elapsed_seconds + 1.0
	future.text_requirements = {&"selector_ready": true}
	future.in_information_list = true
	var fallback := TextPieces.new()
	fallback.text = "尚未满足条件的正文。"
	selector.text_when_observed = [null, missing, future, fallback]
	_check(selector.text_selection(&"observe") == fallback, "基本选择器跳过空资源、缺失标记和未到时间的文本")
	var record_count := TextDatabase.text_collection_list.size()
	_check(selector.text_selection(&"detect") == TextDatabase.default_text_pieces \
		and TextDatabase.text_collection_list.size() == record_count, "空列表使用默认文本且不收集提示")
	var custom := CustomTextSelector.new()
	custom.chosen = fallback
	custom.text_when_observed = [future]
	_check(custom.text_selection(&"observe") == fallback, "自定义选择器优先于基本列表")
	custom.chosen = null
	custom.discard_basic_text_selection = true
	_check(custom.text_selection(&"observe") == TextDatabase.default_text_pieces, "禁用基本选择器后仍有默认文本")
	# 行动跨过实际事件后，按完成时的时间与状态选择，而非点击时选择。
	var original_selector: TextSelector = _screen.text_selectors[&"surface"]
	var original_duration: float = _screen.action_durations_seconds[&"observe"]
	_screen.text_selectors[&"surface"] = selector
	_screen.action_durations_seconds[&"observe"] = 1.0
	var event := WorldTimeEvent.new()
	event.event_id = &"selector_condition_event"
	event.at_seconds = future.time_requirements
	event.changes = {&"selector_ready": true}
	_check(WorldTime.schedule_event(event), "注册文本选择条件事件")
	await _click(_ui.buttons[0].get_global_rect().get_center(), 0.02)
	_check(_ui.narrative.text == future.text and is_equal_approx(WorldTime.elapsed_seconds, future.time_requirements), \
		"操作完成时到达时间门槛并应用事件条件，优先选择对应文本")
	_check(TextDatabase.get_record_texts().has(future.text) \
		and not TextDatabase.get_record_texts().has(fallback.text), "仅收集实际选中的可收集正文")
	var recorded: TextPieces = TextDatabase.text_collection_list[-1]
	_check(recorded.text == future.text and recorded.text_collected_time == WorldTime.elapsed_seconds, \
		"信息获取时间为操作完成时间")
	_screen.text_selectors[&"surface"] = original_selector
	_screen.action_durations_seconds[&"observe"] = original_duration
	_drain_texts()
	WorldTime.set_process(true)


func _test_wait_controller() -> void:
	WorldTime.set_process(false)
	var waiting := _screen.get_node("WaitController")
	var location := WorldState.player_location
	var original_selector: TextSelector = _screen.text_selectors[&"surface"]
	var custom := CustomTextSelector.new()
	custom.chosen = TextPieces.new()
	custom.chosen.text = "地点选择器不应接管等待。"
	custom.chosen.in_information_list = true
	_screen.text_selectors[&"surface"] = custom
	for place: StringName in [&"unconfigured_location", &"space", &"surface"]:
		WorldState.move_to(place)
		var before := WorldTime.elapsed_seconds
		await _click(_ui.buttons[2].get_global_rect().get_center(), 0.02)
		_check(waiting.is_waiting() and _ui.narrative.text == waiting.short_wait_text.text \
			and WorldTime.flow_rate == waiting.short_wait_flow_rate and WorldTime.elapsed_seconds == before, \
			"未配置地点、太空与自定义选择器地点均使用等待节点")
		_check(not waiting.request_wait(), "已有等待不可重复启动")
		_drain_texts()
		_check(not waiting.is_waiting() and WorldTime.flow_rate == 1.0, "等待关闭由节点恢复倍率")
	# 长按期间事件文本先排队，结束反馈排在事件之后。
	var duration: float = waiting.long_wait_seconds
	waiting.long_wait_seconds = 2.0
	var event := WorldTimeEvent.new()
	event.event_id = &"wait_controller_event"
	event.at_seconds = WorldTime.elapsed_seconds + 1.0
	var on_event := func(reached: WorldTimeEvent) -> void:
		if reached.event_id == event.event_id:
			_ui.show_text("长按等待期间发生的事件。")
	WorldTime.event_reached.connect(on_event)
	_check(WorldTime.schedule_event(event), "注册长按等待事件")
	WorldState.move_to(&"unconfigured_location")
	var before := WorldTime.elapsed_seconds
	await _click(_ui.buttons[2].get_global_rect().get_center(), 0.62)
	_check(is_equal_approx(WorldTime.elapsed_seconds - before, 2.0) \
		and _ui.narrative.text == "长按等待期间发生的事件。", "未配置地点的长按等待由节点推进，途中事件先展示")
	_ui.close_text()
	_check(_ui.narrative.text == waiting.long_wait_text.text.split("\n", false)[0], "等待完成反馈在途中事件之后展示")
	_drain_texts()
	WorldTime.event_reached.disconnect(on_event)
	_check(not TextDatabase.get_record_texts().has(custom.chosen.text), "等待不选择或收集地点选择器的文本")
	PauseController.set_paused(true)
	_check(not waiting.request_wait(), "暂停时不启动等待")
	PauseController.set_paused(false)
	var short_piece: TextPieces = waiting.short_wait_text
	waiting.short_wait_text = null
	_check(waiting.request_wait() and _ui.is_text_open(), "未填写提示仍提供可关闭的等待文本")
	_drain_texts()
	waiting.short_wait_text = short_piece
	waiting.long_wait_seconds = duration
	_screen.text_selectors[&"surface"] = original_selector
	WorldState.move_to(location)
	WorldTime.set_process(true)


func _test_information_list() -> void:
	WorldTime.set_process(false)
	var count_before := WorldState.get_collected_information().size()
	await _click(_ui.buttons[0].get_global_rect().get_center(), 0.02)
	_check(TextDatabase.get_record_texts().has(_screen.text_selectors[&"surface"].text_when_observed[0].text), "探索成功反馈以完整原文加入 TextDatabase")
	_check(WorldState.get_collected_information().size() == count_before, "再次获取相同探索文本不会重复收集")
	_drain_texts()
	var short_text := "最近获得的短文本。"
	var long_text := "较早获得的长文本会根据宽度自动换行。".repeat(30) + "\n\n保留段落。\n\n".repeat(35)
	_check(WorldState.record_information(long_text), "可记录长文本")
	_check(WorldState.record_information(short_text), "可记录短文本")
	_check(not WorldState.record_information("  \n"), "不记录空文本")
	# 原阅读框在子页关闭后仍保留原位置。
	_ui.show_text("保留的长阅读文本，自动换行。".repeat(100))
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
	_drain_texts()
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
	_ui.show_text("保留的长游戏正文，自动换行。".repeat(100))
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


func _drain_texts() -> void:
	for _index in range(256):
		if not _ui.is_text_open():
			return
		_ui.close_text()
	_check(false, "文本队列清理未结束")


func _dismiss_remaining_texts() -> void:
	for _index in range(256):
		if not _ui.is_text_open():
			return
		await _send(_key(KEY_ENTER, true))
		await _send(_key(KEY_ENTER, false))
	_check(false, "逐段输入关闭未结束")


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
