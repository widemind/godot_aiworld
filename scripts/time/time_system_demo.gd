extends Control
## 供开发阶段直接体验时间规则；未来地点场景可复用相同服务。

const TIMELINE: WorldTimeline = preload("res://resources/time/demo_timeline.tres")

var _clock_label: Label
var _state_label: Label
var _action_label: Label
var _feedback_label: Label
var _log_label: Label
var _pause_panel: PanelContainer
var _reset_panel: PanelContainer
var _buttons: Array[Button] = []
var _messages: Array[String] = []


func _ready() -> void:
	_build_interface()
	WorldTime.time_changed.connect(_on_time_changed)
	WorldTime.event_reached.connect(_on_event_reached)
	WorldTime.loop_started.connect(_on_loop_started)
	WorldTime.loop_ended.connect(_on_loop_ended)
	WorldState.state_changed.connect(_refresh_state)
	ActionController.action_started.connect(_on_action_started)
	ActionController.action_finished.connect(_on_action_finished)
	PauseController.pause_changed.connect(_on_pause_changed)
	if WorldTime.phase == WorldTime.Phase.READY:
		if TIMELINE.install():
			WorldTime.start_loop()
	else:
		# 场景再次加载时只读取状态，不能无意重置正在进行的循环。
		_refresh_state()
		_on_time_changed(0.0, WorldTime.elapsed_seconds)
		if ActionController.is_busy():
			_on_action_started(ActionController.get_active_action())
		else:
			_action_label.text = "当前没有进行中的行动。"
		_reset_panel.visible = WorldTime.phase != WorldTime.Phase.RUNNING
	_on_pause_changed(get_tree().paused)


func _build_interface() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 16)
	scroll.add_child(column)
	_add_label(column, "Into the Sun  /  世界时间演示", 32)
	_clock_label = _add_label(column, "", 28)
	_add_label(column, "入口 03:00 开启 · 装置 04:00 启动 · 入口 04:40 关闭 · 太阳 10:00 爆炸", 18)
	_state_label = _add_label(column, "", 20)
	_action_label = _add_label(column, "", 18)
	var row := GridContainer.new()
	row.columns = 2
	row.add_theme_constant_override("h_separation", 16)
	row.add_theme_constant_override("v_separation", 12)
	column.add_child(row)
	_add_button(row, "跳过 60 秒", _skip_minute)
	_add_button(row, "等待 60 秒（10 倍速）", _wait_minute)
	_add_button(row, "前往观测站（60 秒）", _travel)
	_add_button(row, "研究装置（30 秒）", _investigate)
	var second_row := HBoxContainer.new()
	second_row.add_theme_constant_override("separation", 16)
	column.add_child(second_row)
	_add_button(second_row, "穿越通道（80 秒）", _cross_passage)
	_add_button(second_row, "取消等待", func() -> void: ActionController.cancel_action())
	var pause_button := Button.new()
	pause_button.text = "暂停 / Esc"
	pause_button.add_theme_font_size_override("font_size", 22)
	pause_button.pressed.connect(func() -> void: PauseController.set_paused(true))
	second_row.add_child(pause_button)
	_feedback_label = _add_label(column, "阅读与思考期间，世界仍在变化。", 22)
	_log_label = _add_label(column, "", 22)
	_pause_panel = _make_overlay("世界已暂停", "继续 / Esc", _resume)
	_pause_panel.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_reset_panel = _make_overlay("太阳爆炸，世界回溯。\n本轮行动终止，已知的方法仍然保留。", "开始下一轮", _restart)
	_reset_panel.process_mode = Node.PROCESS_MODE_PAUSABLE
	# 暂停层最后绘制，循环结束时仍可用 Esc 打开并关闭暂停菜单。
	move_child(_pause_panel, get_child_count() - 1)


func _add_label(parent: Node, content: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = content
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _add_button(parent: Node, content: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = content
	button.add_theme_font_size_override("font_size", 18)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	_buttons.append(button)


func _make_overlay(content: String, button_text: String, callback: Callable) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.visible = false
	add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 28)
	panel.add_child(box)
	var label := _add_label(box, content, 32)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var button := Button.new()
	button.text = button_text
	button.add_theme_font_size_override("font_size", 26)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(callback)
	box.add_child(button)
	return panel


func _make_action(id: StringName, title: String, duration: float) -> WorldAction:
	var action := WorldAction.new()
	action.action_id = id
	action.display_name = title
	action.duration_seconds = duration
	return action


func _skip_minute() -> void:
	ActionController.execute_instant(_make_action(&"skip", "跳过时间", 60.0))


func _wait_minute() -> void:
	ActionController.execute_timed(_make_action(&"wait", "加速等待", 60.0), 10.0)


func _travel() -> void:
	var action := _make_action(&"travel", "前往观测站", 60.0)
	action.start_conditions = {&"gate_open": true}
	action.finish_conditions = {&"gate_open": true}
	action.destination = &"observatory"
	if not ActionController.execute_instant(action):
		_feedback_label.text = "入口尚未开启，无法出发。"


func _cross_passage() -> void:
	var action := _make_action(&"cross", "穿越通道", 80.0)
	action.start_conditions = {&"gate_open": true}
	action.during_conditions = {&"gate_open": true}
	action.destination = &"core"
	if not ActionController.execute_timed(action, 10.0):
		_feedback_label.text = "通道未开启，无法穿越。"


func _investigate() -> void:
	if WorldState.player_location != &"observatory":
		_feedback_label.text = "请先到达观测站。"
		return
	var action := _make_action(&"investigate", "研究装置", 30.0)
	action.finish_conditions = {&"machine_running": true}
	action.result_changes = {&"deciphered": true}
	ActionController.execute_instant(action)


func _resume() -> void:
	PauseController.set_paused(false)


func _restart() -> void:
	if WorldTime.begin_reset():
		WorldTime.start_loop()


func _on_time_changed(_previous: float, current: float) -> void:
	_clock_label.text = "第 %d 轮    %s / %s    时间速度 ×%.1f" % [
		WorldTime.loop_index, _format_time(current), _format_time(WorldTime.loop_duration), WorldTime.flow_rate]


func _refresh_state() -> void:
	var location: String = {&"harbor": "起点", &"observatory": "观测站", &"core": "核心"}.get(WorldState.player_location, "未知地点")
	_state_label.text = "当前位置：%s\n入口：%s    装置：%s    本轮研究：%s    已知方法：%s" % [
		location, "开启" if WorldState.get_flag(&"gate_open", false) else "关闭",
		"运行中" if WorldState.get_flag(&"machine_running", false) else "尚未启动",
		"已完成" if WorldState.get_flag(&"deciphered", false) else "未完成",
		"已记录" if WorldState.knows(&"machine_method") else "待发现"]
	_refresh_buttons()


func _refresh_buttons() -> void:
	for button in _buttons:
		button.disabled = not WorldTime.can_advance() or ActionController.is_busy()
	# 取消按钮在行动期间可用，空闲时不可用。
	_buttons[5].disabled = not WorldTime.can_advance() or not ActionController.is_busy()


func _on_event_reached(event: WorldTimeEvent) -> void:
	var descriptions := {&"gate_open": "入口开启", &"machine_start": "装置启动", &"gate_close": "入口关闭"}
	if descriptions.has(event.event_id):
		_messages.append("%s  %s" % [_format_time(WorldTime.elapsed_seconds), descriptions[event.event_id]])
		_update_log()


func _on_action_started(action: WorldAction) -> void:
	_action_label.text = "正在执行：%s" % action.display_name
	_refresh_buttons()


func _on_action_finished(action: WorldAction, succeeded: bool, reason: StringName) -> void:
	_action_label.text = "当前没有进行中的行动。"
	var reasons := {&"finish_condition": "到达时条件不成立", &"during_condition": "执行期间条件失效", &"loop_ended": "本轮时间耗尽", &"cancelled": "已取消"}
	_feedback_label.text = "%s：%s" % [action.display_name, "完成" if succeeded else reasons.get(reason, "失败")]
	if succeeded and action.action_id == &"investigate":
		WorldState.record_knowledge(&"machine_method")
	_refresh_state()


func _on_loop_started(_loop_index: int) -> void:
	_reset_panel.hide()
	_messages.clear()
	_update_log()
	_action_label.text = "当前没有进行中的行动。"
	_feedback_label.text = "世界回到初始状态。阅读与思考期间，时间继续流逝。"
	_refresh_state()


func _on_loop_ended(_loop_index: int) -> void:
	_reset_panel.show()
	_refresh_buttons()


func _on_pause_changed(paused: bool) -> void:
	_pause_panel.visible = paused
	_refresh_buttons()


func _update_log() -> void:
	_log_label.text = "本轮事件记录\n" + "\n".join(_messages)


func _format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%02d:%02d" % [total / 60, total % 60]
