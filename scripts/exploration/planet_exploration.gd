extends Control
## UI 入口及示例规则。正式地图可通过 WorldState 写入位置和星球/层级标记。

@export var timeline: WorldTimeline
@export var responses: Array[ExplorationResponse] = []
## 短按等待时的世界时间倍率，持续到等待文本关闭。
@export_range(1.0, 100.0, 0.5) var short_wait_flow_rate: float = 10.0

@onready var ui: PlanetExplorationUI = $PlanetExplorationUI

var _pending_response: ExplorationResponse
var _reset_pending: bool = false
var _waiting: bool = false
var _previous_wait_rate: float = 1.0


func _ready() -> void:
	ui.action_requested.connect(_on_action_requested)
	ui.text_closed.connect(_on_text_closed)
	WorldState.state_changed.connect(_refresh_location)
	WorldTime.loop_started.connect(_on_loop_started)
	WorldTime.loop_ended.connect(_on_loop_ended)
	ActionController.action_started.connect(_on_action_started)
	ActionController.action_finished.connect(_on_action_finished)
	if WorldTime.phase == WorldTime.Phase.READY and timeline != null:
		if timeline.install():
			WorldTime.start_loop()
	_refresh_location()
	_refresh_actions()
	if WorldTime.phase in [WorldTime.Phase.ENDED, WorldTime.Phase.RESETTING]:
		_on_loop_ended(WorldTime.loop_index)


func _exit_tree() -> void:
	_stop_waiting()


func _refresh_location() -> void:
	ui.set_location(String(WorldState.get_flag(&"planet_name", "水星")), String(WorldState.get_flag(&"planet_layer", "上层")))


func _refresh_actions() -> void:
	ui.set_actions_available(WorldTime.can_advance() and not ActionController.is_busy())


func _on_action_requested(action_id: StringName, long_press: bool) -> void:
	if not WorldTime.can_advance() or WorldTime.is_advancing() \
			or ActionController.is_busy() or ui.is_text_open():
		return
	for response in responses:
		if not response.matches(WorldState.player_location, action_id, long_press):
			continue
		if action_id == &"wait" and not long_press:
			_start_waiting(response)
			return
		_pending_response = response
		var action := WorldAction.new()
		action.action_id = &"exploration_response"
		action.duration_seconds = response.duration_seconds
		action.start_conditions = response.conditions
		if not ActionController.execute_instant(action):
			_pending_response = null
		return


func _start_waiting(response: ExplorationResponse) -> void:
	if _waiting or response.text.is_empty():
		return
	_previous_wait_rate = WorldTime.flow_rate
	if not WorldTime.set_flow_rate(short_wait_flow_rate):
		return
	_waiting = true
	ui.show_text(response.text)
	_refresh_actions()


func _stop_waiting() -> void:
	if not _waiting:
		return
	_waiting = false
	if not is_instance_valid(WorldTime) or WorldTime.phase != WorldTime.Phase.RUNNING:
		return
	if WorldTime.set_flow_rate(_previous_wait_rate):
		return
	# 暂停时脚本关闭文本或卸载场景，恢复后由常驻时钟还原倍率。
	# Callable 绑定 WorldTime，避免场景释放后遗留失效的回调。
	if get_tree().paused:
		PauseController.pause_changed.connect(
			WorldTime.set_flow_rate.bind(_previous_wait_rate).unbind(1), CONNECT_ONE_SHOT)


func _on_action_started(_action: WorldAction) -> void:
	_refresh_actions()


func _on_action_finished(action: WorldAction, succeeded: bool, _reason: StringName) -> void:
	if action.action_id == &"exploration_response" and _pending_response != null:
		var response := _pending_response
		_pending_response = null
		if succeeded and not response.text.is_empty():
			ui.show_text(response.text)
	_refresh_actions()


func _on_loop_started(_loop_index: int) -> void:
	_waiting = false
	_reset_pending = false
	ui.close_text()
	_refresh_location()
	_refresh_actions()


func _on_loop_ended(_loop_index: int) -> void:
	_stop_waiting()
	_reset_pending = true
	ui.show_text("太阳的光吞没了眼前的一切。\n\n世界正在回溯。\n\n按任意键或点击，开始下一轮。")
	_refresh_actions()


func _on_text_closed() -> void:
	_stop_waiting()
	if _reset_pending:
		_restart_loop.call_deferred()


func _restart_loop() -> void:
	if get_tree().paused:
		return
	if WorldTime.phase == WorldTime.Phase.ENDED:
		WorldTime.begin_reset()
	if WorldTime.phase == WorldTime.Phase.RESETTING:
		WorldTime.start_loop()
