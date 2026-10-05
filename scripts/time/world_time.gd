extends Node
## 所有世界时间推进的唯一入口。与现实日期无关，场景切换不重建时钟。

signal time_changed(previous_seconds: float, current_seconds: float)
signal event_reached(event: WorldTimeEvent)
signal loop_reset(loop_index: int)
signal loop_started(loop_index: int)
signal loop_ended(loop_index: int)
signal real_time_ended
signal timeline_stopped
signal timeline_started(world: int, loop_index: int)

enum Phase { READY, RUNNING, ENDED, RESETTING }
enum World { VIRTUAL, REAL }

var elapsed_seconds: float = 0.0
var loop_duration: float = 600.0
var flow_rate: float = 1.0
var loop_index: int = 0
var phase: Phase = Phase.READY
var world: World = World.VIRTUAL

var _schedule: Array[WorldTimeEvent] = []
var _pending: Array[Dictionary] = []
var _registered_ids: Dictionary = {}
var _sequence: int = 0
var _advancing: bool = false
var _stop_requested: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _process(delta: float) -> void:
	if not can_advance():
		return
	# 行动完成可能恢复倍率。剩余现实帧时间须按新倍率继续，避免快进超调。
	var remaining_real := delta
	while remaining_real > 0.0 and can_advance():
		var rate_before := flow_rate
		var advanced := advance_time(remaining_real * rate_before)
		if advanced <= 0.0:
			break
		remaining_real = maxf(0.0, remaining_real - advanced / rate_before)


func can_advance() -> bool:
	return phase == Phase.RUNNING and not get_tree().paused


func is_advancing() -> bool:
	return _advancing


func configure(duration: float, events: Array[WorldTimeEvent]) -> bool:
	if phase == Phase.RUNNING or _advancing or not is_valid_configuration(duration, events):
		return false
	loop_duration = duration
	_schedule.clear()
	for event in events:
		_schedule.append(event.duplicate(true) as WorldTimeEvent)
	return true


func is_valid_configuration(duration: float, events: Array[WorldTimeEvent]) -> bool:
	if not is_finite(duration) or duration <= 0.0:
		return false
	var ids: Dictionary = {}
	for event in events:
		if not _valid_event(event, duration) or ids.has(event.event_id):
			return false
		ids[event.event_id] = true
	return true


func start_loop() -> bool:
	if world != World.VIRTUAL:
		return false
	return _start_timeline(true, true)


func restart_virtual_loop(saved_loop_index: int) -> bool:
	# 失败后的重试沿用同一轮编号与已恢复的进度，不触发 loop_reset。
	if world != World.VIRTUAL or saved_loop_index < 1 or not _can_start():
		return false
	loop_index = saved_loop_index
	return _start_timeline(false, false, false)


func start_real_time(resuming_progress: bool = false) -> bool:
	if world != World.REAL:
		return false
	return _start_timeline(false, false, not resuming_progress)


func change_world(kind: World, duration: float, events: Array[WorldTimeEvent]) -> bool:
	# 先验证再停表。停止信号取消旧世界的行动，绝不伪造循环结束。
	if _advancing or get_tree().paused or not is_valid_configuration(duration, events):
		return false
	phase = Phase.READY
	flow_rate = 1.0
	timeline_stopped.emit()
	_pending.clear()
	_registered_ids.clear()
	world = kind
	return configure(duration, events)


func _can_start() -> bool:
	return not _advancing and not get_tree().paused and phase != Phase.RUNNING


func _start_timeline(next_loop: bool, reset_world: bool, initialize_events: bool = true) -> bool:
	if not _can_start():
		return false
	elapsed_seconds = 0.0
	flow_rate = 1.0
	if next_loop:
		loop_index += 1
	_pending.clear()
	_registered_ids.clear()
	_sequence = 0
	phase = Phase.RUNNING
	for event in _schedule:
		# 恢复进度时快照已经包含零时刻初始化，不能再次覆盖已完成的操作。
		if not initialize_events and event.at_seconds == 0.0:
			_registered_ids[event.event_id] = true
		else:
			schedule_event(event)
	# 先恢复世界，再执行零时刻事件，最后允许场景显示新一轮状态。
	_advancing = true
	if reset_world:
		loop_reset.emit(loop_index)
	_dispatch_due_events()
	_advancing = false
	time_changed.emit(0.0, 0.0)
	if world == World.VIRTUAL:
		loop_started.emit(loop_index)
	timeline_started.emit(world, loop_index)
	return true


func begin_reset() -> bool:
	if world != World.VIRTUAL or phase != Phase.ENDED or _advancing or get_tree().paused:
		return false
	phase = Phase.RESETTING
	return true


func set_flow_rate(value: float) -> bool:
	if not can_advance() or not is_finite(value) or value <= 0.0:
		return false
	flow_rate = value
	return true


func schedule_event(event: WorldTimeEvent) -> bool:
	if not _valid_event(event, loop_duration) or event.at_seconds < elapsed_seconds:
		return false
	if _registered_ids.has(event.event_id):
		return false
	_registered_ids[event.event_id] = true
	_pending.append({"event": event.duplicate(true), "sequence": _sequence})
	_sequence += 1
	_pending.sort_custom(_event_before)
	return true


func cancel_event(event_id: StringName) -> void:
	# 可在事件回调中移除尚未执行的行动完成事件；ID 本轮内仍不复用。
	for index in range(_pending.size() - 1, -1, -1):
		if (_pending[index]["event"] as WorldTimeEvent).event_id == event_id:
			_pending.remove_at(index)


func request_stop() -> void:
	# 执行期间条件失效时，在当前边界中止跳跃，不扣除剩余行动耗时。
	if _advancing:
		_stop_requested = true


func advance_time(seconds: float) -> float:
	if not can_advance() or _advancing or not is_finite(seconds) or seconds < 0.0:
		return 0.0
	var origin := elapsed_seconds
	var target := minf(loop_duration, elapsed_seconds + seconds)
	_advancing = true
	_stop_requested = false
	while can_advance():
		var next_time := target
		if not _pending.is_empty():
			next_time = minf(next_time, (_pending[0]["event"] as WorldTimeEvent).at_seconds)
		var previous := elapsed_seconds
		elapsed_seconds = next_time
		# 终点优先级最高：不结算恰好在终点完成的行动，也不推进到下一轮。
		if elapsed_seconds >= loop_duration:
			phase = Phase.ENDED
			flow_rate = 1.0
			_pending.clear()
			time_changed.emit(previous, elapsed_seconds)
			if world == World.VIRTUAL:
				loop_ended.emit(loop_index)
			else:
				real_time_ended.emit()
			break
		_dispatch_due_events()
		if elapsed_seconds != previous:
			time_changed.emit(previous, elapsed_seconds)
		if _stop_requested or elapsed_seconds >= target:
			break
	_advancing = false
	return elapsed_seconds - origin


func skip_to(target_seconds: float) -> float:
	if not is_finite(target_seconds) or target_seconds < elapsed_seconds:
		return 0.0
	return advance_time(target_seconds - elapsed_seconds)


func get_remaining_seconds() -> float:
	return maxf(0.0, loop_duration - elapsed_seconds)


func get_pending_events() -> Array[WorldTimeEvent]:
	# 按实际执行顺序返回副本，供演示/调试查看，不暴露可修改的队列。
	var result: Array[WorldTimeEvent] = []
	for entry in _pending:
		result.append((entry["event"] as WorldTimeEvent).duplicate(true) as WorldTimeEvent)
	return result


func _dispatch_due_events() -> void:
	# 使用区间跨越与队列，而非 time == 某个浮点数；低帧率和跳跃都不漏事件。
	while can_advance() and not _pending.is_empty():
		var event := _pending[0]["event"] as WorldTimeEvent
		if event.at_seconds > elapsed_seconds:
			break
		_pending.pop_front()
		event_reached.emit(event)
		if event.stop_advancement:
			_stop_requested = true


func _valid_event(event: WorldTimeEvent, duration: float) -> bool:
	return event != null and not event.event_id.is_empty() \
		and is_finite(event.at_seconds) and event.at_seconds >= 0.0 \
		and event.at_seconds < duration


func _event_before(left: Dictionary, right: Dictionary) -> bool:
	var a := left["event"] as WorldTimeEvent
	var b := right["event"] as WorldTimeEvent
	if a.at_seconds != b.at_seconds:
		return a.at_seconds < b.at_seconds
	if a.priority != b.priority:
		return a.priority < b.priority
	return int(left["sequence"]) < int(right["sequence"])
