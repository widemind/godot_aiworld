extends Control
## UI 入口及示例规则。正式地图可通过 WorldState 写入位置和星球/层级标记。

@export var timeline: WorldTimeline
@export var real_timeline: WorldTimeline
## 地点 ID 对应的文本选择器；地点节点也可动态写入此表。
@export var text_selectors: Dictionary[StringName, TextSelector] = {}
## 观察/探测额外耗时独立于文本；等待由 WaitController 接管。
@export var action_durations_seconds: Dictionary[StringName, float] = {
	&"observe": 0.0, &"observe_long": 5.0,
	&"detect": 10.0, &"detect_long": 30.0,
}

@onready var ui: PlanetExplorationUI = $PlanetExplorationUI

var _pending_selector: TextSelector
var _pending_text_action: StringName
var _reset_pending: bool = false
var _retry_pending: bool = false


func _ready() -> void:
	ui.action_requested.connect(_on_action_requested)
	ui.text_closed.connect(_on_text_closed)
	WorldState.state_changed.connect(_refresh_location)
	WorldTime.timeline_started.connect(_on_timeline_started)
	WorldTime.loop_ended.connect(_on_loop_ended)
	WorldJourney.game_failed.connect(_on_game_failed)
	PauseController.pause_changed.connect(_on_pause_changed)
	ActionController.action_started.connect(_on_action_started)
	ActionController.action_finished.connect(_on_action_finished)
	if not WorldJourney.is_started() and WorldTime.phase == WorldTime.Phase.READY:
		if not WorldJourney.start(timeline, real_timeline):
			push_error("探索入口需要有效的虚拟世界与现实世界时间表。")
	_refresh_location()
	_refresh_actions()
	if WorldTime.phase in [WorldTime.Phase.ENDED, WorldTime.Phase.RESETTING]:
		if WorldTime.world == WorldTime.World.VIRTUAL:
			_on_loop_ended(WorldTime.loop_index)
		elif WorldJourney.failed:
			_on_game_failed()


func _refresh_location() -> void:
	var in_space := bool(WorldState.get_flag(&"in_space", false)) or WorldState.player_location == &"space"
	var planet_name := String(WorldState.get_flag(&"planet_name", ""))
	if in_space or planet_name.strip_edges().is_empty() or planet_name == "太空":
		ui.set_location("太空", "")
	else:
		ui.set_location(planet_name, String(WorldState.get_flag(&"planet_layer", "")))


func _refresh_actions() -> void:
	ui.set_actions_available(WorldTime.can_advance() and not ActionController.is_busy())


func _on_action_requested(action_id: StringName, long_press: bool) -> void:
	# 等待节点直接监听 UI 请求，任何地点均不进入地点文本选择器。
	if action_id == &"wait":
		return
	if not WorldTime.can_advance() or WorldTime.is_advancing() \
			or ActionController.is_busy() or ui.is_text_open():
		return
	var selector := text_selectors.get(WorldState.player_location) as TextSelector
	if selector == null:
		return
	var text_action := &"detect" if action_id == &"probe" else action_id
	if long_press:
		text_action = StringName(String(text_action) + "_long")
	_pending_selector = selector
	_pending_text_action = text_action
	var action := WorldAction.new()
	action.action_id = &"exploration_text"
	action.duration_seconds = action_durations_seconds.get(text_action, 0.0)
	if not ActionController.execute_instant(action):
		_pending_selector = null
		_pending_text_action = &""


func _on_action_started(_action: WorldAction) -> void:
	_refresh_actions()


func _on_action_finished(action: WorldAction, succeeded: bool, _reason: StringName) -> void:
	if action.action_id == &"exploration_text" and _pending_selector != null:
		var selector := _pending_selector
		var text_action := _pending_text_action
		_pending_selector = null
		_pending_text_action = &""
		# 行动跨过时间轴事件时，按完成时的时间和世界状态选文本。
		# 失败/触及终点不选择，也不提前收集任何普通反馈。
		if succeeded:
			ui.show_text_piece(selector.text_selection(text_action))
	_refresh_actions()


func _on_timeline_started(_world: int, _loop_index: int) -> void:
	_reset_pending = false
	_retry_pending = false
	ui.clear_texts()
	_refresh_location()
	_refresh_actions()


func _on_loop_ended(_loop_index: int) -> void:
	_reset_pending = true
	ui.show_loop_end_text("太阳的光吞没了眼前的一切。\n\n世界正在回溯。\n\n按任意键或点击，开始下一轮。")
	_refresh_actions()


func _on_game_failed() -> void:
	_reset_pending = false
	_retry_pending = true
	ui.show_text("现实世界时间已耗尽，游戏失败。\n已完成进度和已获取信息已保留。\n按任意键或点击，返回虚拟世界最后一轮，从零重新计时。")
	_refresh_actions()


func _on_text_closed() -> void:
	# 回溯提示同样排队，必须读完当前及队列中的文本才能开始下一轮。
	if _reset_pending and not ui.is_text_open():
		_restart_loop.call_deferred()
	elif _retry_pending and not ui.is_text_open():
		_retry_virtual.call_deferred()


func _retry_virtual() -> void:
	if _retry_pending and not get_tree().paused and not ui.is_text_open():
		WorldJourney.return_to_virtual()


func _on_pause_changed(paused: bool) -> void:
	# 暂停期间脚本关闭提示时，恢复后继续尚未完成的回溯/重试。
	if not paused and not ui.is_text_open():
		if _retry_pending:
			_retry_virtual.call_deferred()
		elif _reset_pending:
			_restart_loop.call_deferred()


func _restart_loop() -> void:
	if not _reset_pending or WorldTime.world != WorldTime.World.VIRTUAL \
			or get_tree().paused or ui.is_text_open():
		return
	if WorldTime.phase == WorldTime.Phase.ENDED:
		WorldTime.begin_reset()
	if WorldTime.phase == WorldTime.Phase.RESETTING:
		WorldTime.start_loop()
