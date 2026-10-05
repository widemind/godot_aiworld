extends Control
## 开发用完整时间轴演示。复用正式服务，不另建计时/进度系统。

const VIRTUAL_TIMELINE: WorldTimeline = preload("res://resources/time/demo_timeline.tres")
const REAL_TIMELINE: WorldTimeline = preload("res://resources/time/demo_real_timeline.tres")
const CURSOR_FRAME_BUTTON: Script = preload("res://scripts/effect/cursor_frame_button.gd")
const EVENT_NAMES: Dictionary = {
	&"gate_open": "虚拟入口开启", &"machine_start": "装置启动", &"gate_close": "虚拟入口关闭",
	&"real_energy_low": "现实能源不足", &"real_link_ready": "现实连接窗口开启", &"real_link_closed": "现实连接窗口关闭"
}

var _clock_label: Label
var _state_label: Label
var _snapshot_label: Label
var _action_label: Label
var _feedback_label: Label
var _queue_label: RichTextLabel
var _log_label: RichTextLabel
var _progress: ProgressBar
var _pause_panel: Control
var _end_panel: Control
var _end_title: Label
var _end_detail: Label
var _continue_button: Button
var _controls: Dictionary[StringName, Button] = {}
var _messages: Array[String] = []


func _ready() -> void:
	resized.connect(_resize_background)
	_resize_background()
	_build_interface()
	WorldTime.time_changed.connect(_on_time_changed)
	WorldTime.event_reached.connect(_on_event_reached)
	WorldTime.loop_reset.connect(_on_loop_reset)
	WorldTime.loop_ended.connect(_on_loop_ended)
	WorldTime.timeline_started.connect(_on_timeline_started)
	WorldTime.timeline_stopped.connect(_on_timeline_stopped)
	WorldJourney.world_changed.connect(_on_world_changed)
	WorldJourney.game_failed.connect(_on_game_failed)
	WorldState.state_changed.connect(_refresh_state)
	WorldState.knowledge_changed.connect(_refresh_state)
	ActionController.action_started.connect(_on_action_started)
	ActionController.action_finished.connect(_on_action_finished)
	PauseController.pause_changed.connect(_on_pause_changed)
	if not WorldJourney.is_started() and WorldTime.phase == WorldTime.Phase.READY:
		if not WorldJourney.start(VIRTUAL_TIMELINE, REAL_TIMELINE):
			_feedback_label.text = "启动失败：请检查两份演示时间表。"
	else:
		_feedback_label.text = "沿用当前世界与进度，重载演示场景不会重置时间。"
	_refresh_state()
	if ActionController.is_busy():
		_on_action_started(ActionController.get_active_action())
	else:
		_action_label.text = "当前没有进行中的行动。"
	if WorldTime.phase in [WorldTime.Phase.ENDED, WorldTime.Phase.RESETTING]:
		_show_end()
	_on_pause_changed(get_tree().paused)
	_on_time_changed(0.0, WorldTime.elapsed_seconds)


func _process(_delta: float) -> void:
	# 倍率切换没有 time_changed 信号，逐帧读取也能正确显示暂停前的倍率。
	_on_time_changed(0.0, WorldTime.elapsed_seconds)


func _resize_background() -> void:
	$StarfieldBackground.set(&"field_size", size)


func _build_interface() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)
	_add_label(column, "Into the Sun / 时间轴功能演示", 30)
	_clock_label = _add_label(column, "", 24)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size.y = 10.0
	_progress.show_percentage = false
	column.add_child(_progress)
	_add_label(column, "虚拟世界自然循环；现实每次进入从零计时，超时失败；失败后可返回虚拟最后一轮保留进度重试。", 18)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	column.add_child(body)
	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.size_flags_stretch_ratio = 1.1
	controls.add_theme_constant_override("separation", 10)
	body.add_child(controls)
	var inspector := VBoxContainer.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.add_theme_constant_override("separation", 10)
	body.add_child(inspector)
	var clock_grid := _make_group(controls, "时间推进 / 暂停")
	_add_button(clock_grid, &"skip", "跳过 60 秒", _skip_minute)
	_add_button(clock_grid, &"next_event", "跳到下一个事件", _next_event)
	_add_button(clock_grid, &"rate_1", "恢复正常 ×1", _set_rate.bind(1.0))
	_add_button(clock_grid, &"rate_10", "自由快进 ×10", _set_rate.bind(10.0))
	_add_button(clock_grid, &"end", "推进到时间终点", _advance_to_end)
	_add_button(clock_grid, &"pause", "暂停 / Esc", _pause)
	var action_grid := _make_group(controls, "行动 / 开始、期间、完成条件")
	_add_button(action_grid, &"observe", "立即观察（0 秒）", _observe)
	_add_button(action_grid, &"wait", "等待 60 秒（×10）", _wait_minute)
	_add_button(action_grid, &"travel", "前往观测站（60 秒）", _travel)
	_add_button(action_grid, &"cross", "穿越通道（80 秒 / ×10）", _cross_passage)
	_add_button(action_grid, &"investigate", "研究装置（30 秒）", _investigate)
	_add_button(action_grid, &"cancel", "取消当前行动", _cancel_action)
	_add_button(action_grid, &"terminal", "恰好在终点完成（失败）", _terminal_action)
	_add_button(action_grid, &"checkpoint", "完成操作 / 收集信息", _checkpoint)
	var world_grid := _make_group(controls, "两个世界 / 进度保留")
	_add_button(world_grid, &"switch", "返回现实世界", _switch_world)
	_add_button(world_grid, &"dynamic", "登记 +20 秒同刻事件", _schedule_dynamic)
	_add_button(world_grid, &"cancel_dynamic", "取消动态事件", _cancel_dynamic)
	_add_button(world_grid, &"reload", "重载场景（保留时间）", _reload_scene)
	_add_label(controls, "观测站路线：开始和到达时入口须开启。通道：全过程须开启。研究：完成时装置须运行。\n同刻事件按 priority 排序，世界事件先于行动完成；切换世界会取消未完成行动。", 16)
	_action_label = _add_label(controls, "", 20)
	_feedback_label = _add_label(controls, "阅读与思考期间，世界时间继续流逝。", 18)
	_add_label(inspector, "当前世界数据", 22)
	_state_label = _add_label(inspector, "", 18)
	_snapshot_label = _add_label(inspector, "", 18)
	_add_label(inspector, "待发生事件（实际队列 / 时间 → 优先级）", 22)
	_queue_label = _add_rich_label(inspector, 230.0)
	_add_label(inspector, "信号与行动记录（跨世界、跨循环保留）", 22)
	_log_label = _add_rich_label(inspector, 250.0)
	_log_label.scroll_following = true
	_pause_panel = _make_overlay("世界已暂停", "时间和行动冻结，恢复后不补计暂停时间。", "继续 / Esc", _resume)
	_pause_panel.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_end_panel = _make_overlay("", "", "", _continue_after_end)
	_end_title = _end_panel.get_node("Card/Margin/Column/Title") as Label
	_end_detail = _end_panel.get_node("Card/Margin/Column/Detail") as Label
	_continue_button = _end_panel.get_node("Card/Margin/Column/Continue") as Button
	move_child(_pause_panel, get_child_count() - 1)


func _make_group(parent: Node, title: String) -> GridContainer:
	_add_label(parent, title, 22)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	return grid


func _add_label(parent: Node, content: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = content
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _add_rich_label(parent: Node, height: float) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.custom_minimum_size.y = height
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", 18)
	parent.add_child(label)
	return label


func _add_button(parent: Node, id: StringName, content: String, callback: Callable) -> void:
	var button: Button = CURSOR_FRAME_BUTTON.new()
	button.name = String(id).to_pascal_case() + "Button"
	button.text = content
	button.custom_minimum_size.y = 44.0
	button.add_theme_font_size_override("font_size", 18)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	_controls[id] = button


func _make_overlay(title: String, detail: String, button_text: String, callback: Callable) -> Control:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.hide()
	add_child(overlay)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.85)
	overlay.add_child(shade)
	var card := PanelContainer.new()
	card.name = "Card"
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left = -440.0
	card.offset_right = 440.0
	card.offset_top = -180.0
	card.offset_bottom = 180.0
	overlay.add_child(card)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.name = "Column"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 22)
	margin.add_child(box)
	var heading := _add_label(box, title, 28)
	heading.name = "Title"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var note := _add_label(box, detail, 20)
	note.name = "Detail"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var button: Button = CURSOR_FRAME_BUTTON.new()
	button.name = "Continue"
	button.text = button_text
	button.custom_minimum_size.y = 54.0
	button.add_theme_font_size_override("font_size", 22)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(callback)
	box.add_child(button)
	return overlay


func _make_action(id: StringName, title: String, duration: float) -> WorldAction:
	var action := WorldAction.new()
	action.action_id = id
	action.display_name = title
	action.duration_seconds = duration
	return action


func _skip_minute() -> void:
	var advanced := WorldTime.advance_time(60.0)
	_add_log("advance_time(60)：实际推进 %.2f 秒" % advanced)
	_refresh_state()


func _next_event() -> void:
	var pending := WorldTime.get_pending_events()
	if pending.is_empty():
		_feedback_label.text = "没有待发生事件，可直接推进到终点。"
		return
	var advanced := WorldTime.skip_to(pending[0].at_seconds)
	_add_log("skip_to：实际推进 %.2f 秒" % advanced)
	_refresh_state()


func _advance_to_end() -> void:
	var advanced := WorldTime.skip_to(WorldTime.loop_duration)
	_add_log("请求推进到终点：实际推进 %.2f 秒" % advanced)
	_refresh_state()


func _set_rate(rate: float) -> void:
	if WorldTime.set_flow_rate(rate):
		_add_log("flow_rate = %.1f" % rate)
		_on_time_changed(0.0, WorldTime.elapsed_seconds)


func _observe() -> void:
	ActionController.execute_instant(_make_action(&"observe", "立即观察", 0.0))


func _wait_minute() -> void:
	ActionController.execute_timed(_make_action(&"wait", "加速等待", 60.0), 10.0)


func _travel() -> void:
	var action := _make_action(&"travel", "前往观测站", 60.0)
	action.start_conditions = {&"gate_open": true}
	action.finish_conditions = {&"gate_open": true}
	action.destination = &"observatory"
	if not ActionController.execute_instant(action):
		_feedback_label.text = "开始条件不满足：入口未开启，不扣时间。"


func _cross_passage() -> void:
	var action := _make_action(&"cross", "穿越通道", 80.0)
	action.start_conditions = {&"gate_open": true}
	action.during_conditions = {&"gate_open": true}
	action.destination = &"core"
	if not ActionController.execute_timed(action, 10.0):
		_feedback_label.text = "开始条件不满足：通道未开启，不扣时间。"


func _investigate() -> void:
	if WorldState.player_location != &"observatory":
		_feedback_label.text = "请先到达观测站。"
		return
	var action := _make_action(&"investigate", "研究装置", 30.0)
	action.finish_conditions = {&"machine_running": true}
	action.result_changes = {&"deciphered": true}
	ActionController.execute_instant(action)


func _cancel_action() -> void:
	ActionController.cancel_action()


func _terminal_action() -> void:
	var action := _make_action(&"terminal", "终点行动", WorldTime.get_remaining_seconds())
	action.result_changes = {&"terminal_reward": true}
	ActionController.execute_instant(action)


func _checkpoint() -> void:
	var action := _make_action(&"checkpoint", "完成操作", 0.0)
	action.result_changes = {&"demo_progress": int(WorldState.get_flag(&"demo_progress", 0)) + 1}
	ActionController.execute_instant(action)


func _switch_world() -> void:
	var success := WorldJourney.return_to_reality() if WorldTime.world == WorldTime.World.VIRTUAL else WorldJourney.return_to_virtual()
	if not success:
		_feedback_label.text = "当前不能切换世界：请先恢复游戏或等待本次结算结束。"
	_refresh_state()


func _schedule_dynamic() -> void:
	if WorldTime.elapsed_seconds + 20.0 >= WorldTime.loop_duration:
		_feedback_label.text = "终点前不足 20 秒，不能在终点或其后登记事件。"
		return
	var stamp := Time.get_ticks_usec()
	# 故意先登记优先级 10，再登记 0，验证同刻执行次序由 priority 决定。
	for priority in [10, 0]:
		var event := WorldTimeEvent.new()
		event.event_id = StringName("demo_pair_%d_%d" % [stamp, priority])
		event.at_seconds = WorldTime.elapsed_seconds + 20.0
		event.priority = priority
		event.stop_advancement = priority == 10
		event.changes = {&"dynamic_last_priority": priority}
		if not WorldTime.schedule_event(event):
			_feedback_label.text = "动态事件注册被拒绝。"
			return
	_add_log("schedule_event：+20 秒，同刻 priority 0 → 10，停止本次推进")
	_refresh_queue()
	_refresh_buttons()


func _cancel_dynamic() -> void:
	var count := 0
	for event in WorldTime.get_pending_events():
		if String(event.event_id).begins_with("demo_pair_"):
			WorldTime.cancel_event(event.event_id)
			count += 1
	_add_log("cancel_event：取消 %d 个动态事件" % count)
	_refresh_queue()
	_refresh_buttons()


func _reload_scene() -> void:
	get_tree().reload_current_scene()


func _pause() -> void:
	PauseController.set_paused(true)


func _resume() -> void:
	PauseController.set_paused(false)


func _continue_after_end() -> void:
	if get_tree().paused or WorldTime.is_advancing():
		return
	if WorldTime.world == WorldTime.World.REAL:
		WorldJourney.return_to_virtual()
	else:
		if WorldTime.phase == WorldTime.Phase.ENDED:
			WorldTime.begin_reset()
		if WorldTime.phase == WorldTime.Phase.RESETTING:
			WorldTime.start_loop()


func _on_time_changed(_previous: float, current: float) -> void:
	_clock_label.text = "%s · 第 %d 轮    已过 %s / %s    剩余 %s    ×%.1f    %s" % [
		_world_name(), WorldTime.loop_index, _format_time(current), _format_time(WorldTime.loop_duration),
		_format_time(ceilf(WorldTime.get_remaining_seconds())), WorldTime.flow_rate,
		"已暂停" if get_tree().paused else str(WorldTime.Phase.keys()[WorldTime.phase])]
	_progress.max_value = WorldTime.loop_duration
	_progress.value = current
	_refresh_queue()


func _refresh_state() -> void:
	_state_label.text = "位置：%s\nflags：%s\n方法知识：%s / 信息记录：%d 条" % [
		WorldState.player_location, JSON.stringify(WorldState.get_flags()),
		"已掌握" if WorldState.knows(&"machine_method") else "尚未掌握", TextDatabase.get_record_texts().size()]
	_snapshot_label.text = "进度快照（各世界独立，知识/信息共享）\n%s\n%s" % [
		_snapshot_summary(WorldTime.World.VIRTUAL), _snapshot_summary(WorldTime.World.REAL)]
	_refresh_queue()
	_refresh_buttons()


func _snapshot_summary(world: int) -> String:
	var snapshot := WorldJourney.get_saved_progress(world)
	var title := "虚拟" if world == WorldTime.World.VIRTUAL else "现实"
	if snapshot.is_empty():
		return title + "：尚未进入"
	var flags: Dictionary = snapshot.get("flags", {})
	return "%s：位置 %s / 操作计数 %d / 研究 %s" % [title, snapshot.get("location", &""),
		int(flags.get(&"demo_progress", 0)), "完成" if flags.get(&"deciphered", false) else "未完成"]


func _refresh_queue() -> void:
	var lines: Array[String] = []
	for event in WorldTime.get_pending_events():
		var title := String(EVENT_NAMES.get(event.event_id, event.event_id))
		if String(event.event_id).begins_with("_action_completion_"):
			title = "当前行动完成"
		elif String(event.event_id).begins_with("demo_pair_"):
			title = "动态同刻事件"
		lines.append("%s · P%d · %s%s" % [_format_time(event.at_seconds), event.priority, title,
			" / 停止本次推进" if event.stop_advancement else ""])
	_queue_label.text = "\n".join(lines) if not lines.is_empty() else "没有待发生事件。终点由时钟单独处理。"


func _refresh_buttons() -> void:
	var running := WorldTime.can_advance()
	var busy := ActionController.is_busy()
	for button in _controls.values():
		button.disabled = not running or busy
	_controls[&"cancel"].disabled = not running or not busy
	# 服务允许世界切换取消尚未完成的行动，演示刻意保留这个入口。
	_controls[&"switch"].disabled = not running or not WorldJourney.is_started()
	_controls[&"switch"].text = "返回现实世界" if WorldTime.world == WorldTime.World.VIRTUAL else "返回虚拟最后一轮"
	_controls[&"pause"].disabled = get_tree().paused
	_controls[&"reload"].disabled = get_tree().paused
	for id in [&"travel", &"cross", &"investigate"]:
		_controls[id].disabled = not running or busy or WorldTime.world != WorldTime.World.VIRTUAL
	var has_dynamic := false
	for event in WorldTime.get_pending_events():
		if String(event.event_id).begins_with("demo_pair_"):
			has_dynamic = true
	_controls[&"cancel_dynamic"].disabled = not running or not has_dynamic


func _on_event_reached(event: WorldTimeEvent) -> void:
	_add_log("event_reached / P%d / %s" % [event.priority, EVENT_NAMES.get(event.event_id, event.event_id)])
	_refresh_state()


func _on_action_started(action: WorldAction) -> void:
	_action_label.text = "正在执行：%s / %.1f 世界秒" % [action.display_name, action.duration_seconds]
	_add_log("action_started / " + String(action.action_id))
	_refresh_buttons()


func _on_action_finished(action: WorldAction, succeeded: bool, reason: StringName) -> void:
	_action_label.text = "当前没有进行中的行动。"
	var reasons := {&"finish_condition": "完成条件不成立", &"during_condition": "执行期间条件失效",
		&"loop_ended": "虚拟循环终点", &"real_time_ended": "现实时间耗尽", &"world_changed": "世界已切换", &"cancelled": "主动取消"}
	_feedback_label.text = "%s：%s" % [action.display_name, "完成" if succeeded else reasons.get(reason, "失败")]
	if succeeded and action.action_id == &"investigate":
		WorldState.record_knowledge(&"machine_method")
		WorldState.record_information("已掌握观测站装置的使用方法。")
	if succeeded and action.action_id == &"checkpoint":
		WorldState.record_information("%s完成操作 #%d" % [_world_name(), WorldState.get_flag(&"demo_progress", 0)])
	_add_log("action_finished / %s / %s / %s" % [action.action_id, "成功" if succeeded else "失败", reason])
	_refresh_state()


func _on_loop_reset(index: int) -> void:
	_add_log("loop_reset / 第 %d 轮，恢复初始临时世界" % index)


func _on_timeline_started(_world: int, index: int) -> void:
	_end_panel.hide()
	_action_label.text = "当前没有进行中的行动。"
	_feedback_label.text = "计时从零开始；请对照右侧快照检查两个世界的独立进度。"
	_add_log("timeline_started / 第 %d 轮" % index)
	_refresh_state()
	_on_time_changed(0.0, WorldTime.elapsed_seconds)


func _on_timeline_stopped() -> void:
	_add_log("timeline_stopped / 旧世界停表，未完成行动取消")


func _on_world_changed(_world: int) -> void:
	_add_log("world_changed / " + _world_name())
	_refresh_state()


func _on_loop_ended(index: int) -> void:
	_add_log("loop_ended / 第 %d 轮，等待开启下一轮" % index)
	_show_end()


func _on_game_failed() -> void:
	_add_log("game_failed / 现实无循环，已完成进度保留")
	_show_end()


func _show_end() -> void:
	if WorldTime.world == WorldTime.World.REAL:
		_end_title.text = "现实时间耗尽 · 游戏失败"
		_end_detail.text = "两个世界的 flags、位置、知识和信息均保留。\n返回虚拟世界第 %d 轮，从零重新计时。\n再次进入现实时恢复现实进度，并获得完整计时。" % WorldTime.loop_index
		_continue_button.text = "返回最后一轮（保留进度）"
	else:
		_end_title.text = "虚拟世界时间耗尽 · 本轮结束"
		_end_detail.text = "下一轮恢复初始位置与临时标记。\n已掌握的知识和已获取的信息跨循环保留。"
		_continue_button.text = "开始下一轮"
	_end_panel.show()
	_refresh_buttons()


func _on_pause_changed(paused: bool) -> void:
	_pause_panel.visible = paused
	_continue_button.disabled = paused
	_add_log("pause_changed / " + ("暂停" if paused else "继续"))
	_refresh_buttons()
	_on_time_changed(0.0, WorldTime.elapsed_seconds)


func _add_log(message: String) -> void:
	_messages.append("[%s #%d %s] %s" % [_world_name(), WorldTime.loop_index, _format_time(WorldTime.elapsed_seconds), message])
	if _messages.size() > 100:
		_messages.pop_front()
	_log_label.text = "\n".join(_messages)


func _world_name() -> String:
	return "虚拟" if WorldTime.world == WorldTime.World.VIRTUAL else "现实"


func _format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%02d:%02d" % [total / 60, total % 60]
