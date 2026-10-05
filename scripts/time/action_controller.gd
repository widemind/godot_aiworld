extends Node
## 同时只执行一个行动。完成点进入世界事件表，确保中途事件先发生。

signal action_started(action: WorldAction)
signal action_finished(action: WorldAction, succeeded: bool, reason: StringName)

var _active: WorldAction
var _completion_id: StringName
var _generation: int = 0
var _previous_rate: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	WorldTime.event_reached.connect(_on_event_reached)
	WorldTime.loop_ended.connect(_on_loop_ended)
	WorldState.state_changed.connect(_on_state_changed)


func is_busy() -> bool:
	return _active != null


func get_active_action() -> WorldAction:
	return _active.duplicate(true) as WorldAction if _active != null else null


func execute_instant(action: WorldAction) -> bool:
	# true 表示成功开始；最终成功与否通过 action_finished 通知。
	if not _begin(action):
		return false
	if is_busy():
		WorldTime.advance_time(_active.duration_seconds)
	return true


func execute_timed(action: WorldAction, rate: float = 1.0) -> bool:
	if not is_finite(rate) or rate <= 0.0:
		return false
	if not _begin(action):
		return false
	if is_busy():
		WorldTime.set_flow_rate(rate)
	return true


func cancel_action(reason: StringName = &"cancelled") -> bool:
	if not WorldTime.can_advance() or not is_busy():
		return false
	WorldTime.request_stop()
	_complete(false, reason)
	return true


func _begin(action: WorldAction) -> bool:
	if not WorldTime.can_advance() or WorldTime.is_advancing() or is_busy():
		return false
	if action == null or action.action_id.is_empty() \
			or not is_finite(action.duration_seconds) or action.duration_seconds < 0.0:
		return false
	if not WorldState.meets_conditions(action.start_conditions) \
			or not WorldState.meets_conditions(action.during_conditions):
		return false
	_generation += 1
	_active = action.duplicate(true) as WorldAction
	_previous_rate = WorldTime.flow_rate
	_completion_id = StringName("_action_completion_%d" % _generation)
	var completion := WorldTimeEvent.new()
	completion.event_id = _completion_id
	completion.at_seconds = WorldTime.elapsed_seconds + _active.duration_seconds
	# 地点事件默认优先级 0；完成事件最后结算，读取该时刻更新后的状态。
	completion.priority = 1000000
	completion.stop_advancement = true
	if completion.at_seconds < WorldTime.loop_duration:
		if not WorldTime.schedule_event(completion):
			_active = null
			return false
	# 达到或超过终点时不注册完成事件，交由循环结束统一取消。
	action_started.emit(_active.duplicate(true) as WorldAction)
	if is_busy() and _active.duration_seconds == 0.0:
		WorldTime.advance_time(0.0)
	return true


func _on_event_reached(event: WorldTimeEvent) -> void:
	if is_busy() and event.event_id == _completion_id:
		var succeeded := WorldState.meets_conditions(_active.finish_conditions)
		_complete(succeeded, &"completed" if succeeded else &"finish_condition")


func _on_state_changed() -> void:
	if is_busy() and not WorldState.meets_conditions(_active.during_conditions):
		WorldTime.request_stop()
		_complete(false, &"during_condition")


func _on_loop_ended(_loop_index: int) -> void:
	if is_busy():
		_complete(false, &"loop_ended")


func _complete(succeeded: bool, reason: StringName) -> void:
	var action := _active
	WorldTime.cancel_event(_completion_id)
	# 先清理活动行动，结果写入触发 state_changed 时不会再次取消自己。
	_active = null
	if WorldTime.can_advance():
		WorldTime.set_flow_rate(_previous_rate)
	if succeeded:
		# 位置和结果一次写入，回调即使打开暂停菜单也不会留下半完成的行动。
		WorldState.apply_changes(action.result_changes, action.destination)
	action_finished.emit(action, succeeded, reason)
