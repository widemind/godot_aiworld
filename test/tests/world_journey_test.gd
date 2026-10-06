extends Node
## 两世界流程回归：快照、事件、暂停、行动取消与同一轮重试。

var _passed: int = 0
var _failed: int = 0
var _failure_count: int = 0
var _loop_end_count: int = 0
var _outcomes: Array[Dictionary] = []
var _zero_events: int = 0


func _ready() -> void:
	await get_tree().process_frame
	WorldTime.set_process(false)
	WorldJourney.game_failed.connect(func() -> void: _failure_count += 1)
	WorldTime.loop_ended.connect(func(_index: int) -> void: _loop_end_count += 1)
	WorldTime.event_reached.connect(func(event: WorldTimeEvent) -> void:
		if event.at_seconds == 0.0:
			_zero_events += 1)
	ActionController.action_finished.connect(func(_action: WorldAction, succeeded: bool, reason: StringName) -> void:
		_outcomes.append({"succeeded": succeeded, "reason": reason}))
	_test_journey()
	print("WORLD_JOURNEY_TESTS passed=%d failed=%d" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _timeline(location: StringName, duration: float) -> WorldTimeline:
	var timeline := WorldTimeline.new()
	timeline.loop_duration = duration
	timeline.initial_location = location
	timeline.initial_flags = {&"progress": false, &"visited": false}
	var zero := WorldTimeEvent.new()
	zero.event_id = &"initialize"
	zero.changes = {&"progress": false}
	var later := WorldTimeEvent.new()
	later.event_id = &"world_change"
	later.at_seconds = 5.0
	later.changes = {&"visited": true}
	timeline.events = [zero, later]
	return timeline


func _test_journey() -> void:
	var virtual := _timeline(&"virtual_start", 20.0)
	var real := _timeline(&"real_start", 10.0)
	var invalid := _timeline(&"invalid", 0.0)
	_check(not WorldJourney.start(virtual, invalid), "invalid real timeline cannot partially start journey")
	_check(not WorldJourney.is_started() and WorldTime.phase == WorldTime.Phase.READY, "invalid start leaves clock ready")
	_check(WorldJourney.start(virtual, real), "journey starts")
	_check(WorldTime.world == WorldTime.World.VIRTUAL and WorldTime.loop_index == 1, "starts in virtual loop one")
	_check(_zero_events == 1, "initial virtual zero event dispatched")
	_check(not WorldJourney.start(virtual, real), "scene reload cannot restart journey")
	# 自然结束仍重建虚拟世界；最后一轮的编号用于失败重试。
	WorldState.apply_changes({&"progress": true}, &"old_loop")
	WorldState.record_knowledge(&"shared_knowledge")
	WorldState.record_information("跨世界保留的信息")
	WorldTime.advance_time(100.0)
	_check(WorldTime.phase == WorldTime.Phase.ENDED and _failure_count == 0, "virtual timeout is not game failure")
	_check(WorldTime.begin_reset() and WorldTime.start_loop(), "virtual can loop naturally")
	_check(WorldTime.loop_index == 2 and WorldState.player_location == &"virtual_start", "natural loop restores initial location")
	_check(WorldState.get_flag(&"progress") == false, "natural loop restores temporary flags")
	WorldTime.advance_time(7.0)
	WorldState.apply_changes({&"progress": true, &"nested": [1, 2]}, &"virtual_checkpoint")
	var checkpoint := WorldState.capture_snapshot()
	PauseController.set_paused(true)
	_check(not WorldJourney.return_to_reality(), "paused switch rejected")
	PauseController.set_paused(false)
	var action := WorldAction.new()
	action.action_id = &"unfinished_virtual"
	action.duration_seconds = 8.0
	action.result_changes = {&"unfinished_result": true}
	_check(ActionController.execute_timed(action, 10.0), "virtual timed action starts")
	_check(WorldJourney.return_to_reality(), "switch cancels old-world action")
	_check(not ActionController.is_busy() and _outcomes.back().reason == &"world_changed", "switch reports action cancellation")
	_check(WorldTime.world == WorldTime.World.REAL and WorldTime.elapsed_seconds == 0.0 and WorldTime.flow_rate == 1.0, "real starts with fresh clock and rate")
	_check(WorldState.player_location == &"real_start" and not WorldState.get_flag(&"progress"), "real has its own initial state")
	_check(not WorldTime.start_loop() and not WorldTime.begin_reset(), "real cannot enter virtual loop APIs")
	var saved := WorldJourney.get_saved_progress(WorldTime.World.VIRTUAL)
	saved.flags[&"nested"].append(3)
	_check(WorldJourney.get_saved_progress(WorldTime.World.VIRTUAL) == checkpoint, "saved progress is a deep copy")
	WorldState.apply_changes({&"progress": true}, &"real_checkpoint")
	WorldTime.advance_time(6.0)
	var real_checkpoint := WorldState.capture_snapshot()
	_check(WorldJourney.return_to_virtual(), "early real return supported")
	_check(WorldState.capture_snapshot() == checkpoint and WorldTime.loop_index == 2 and WorldTime.elapsed_seconds == 0.0, "virtual restores latest loop progress with time zero")
	_check(WorldTime.flow_rate == 1.0 and not WorldJourney.failed, "return clears transient timing state")
	var zero_before := _zero_events
	_check(WorldJourney.return_to_reality(), "reenter real")
	_check(WorldState.capture_snapshot() == real_checkpoint and WorldTime.elapsed_seconds == 0.0, "real progress retained while timer restarts")
	_check(_zero_events == zero_before, "resume does not replay zero initialization over saved progress")
	WorldTime.advance_time(5.0)
	_check(WorldState.get_flag(&"visited"), "future time events replay on fresh real timer")
	action.action_id = &"terminal_real"
	action.duration_seconds = 5.0
	var virtual_end_count := _loop_end_count
	_check(ActionController.execute_instant(action), "terminal real action accepted")
	_check(WorldJourney.failed and _failure_count == 1 and WorldTime.phase == WorldTime.Phase.ENDED, "real deadline fails exactly once")
	_check(_loop_end_count == virtual_end_count and _outcomes.back().reason == &"real_time_ended", "real failure never emits virtual loop end")
	_check(not WorldState.get_flag(&"unfinished_result", false), "terminal unfinished action cannot grant progress")
	_check(WorldState.capture_snapshot() == real_checkpoint, "failure preserves completed real flags and location")
	_check(WorldTime.advance_time(100.0) == 0.0 and _failure_count == 1, "failure freezes time without repeated signal")
	_check(not WorldState.apply_changes({&"after_failure": true}), "failed game rejects new progress mutations")
	PauseController.set_paused(true)
	_check(not WorldJourney.return_to_virtual(), "paused retry blocked")
	PauseController.set_paused(false)
	_check(WorldJourney.return_to_virtual(), "failed game returns to virtual")
	_check(WorldTime.loop_index == 2 and WorldTime.elapsed_seconds == 0.0 and WorldState.capture_snapshot() == checkpoint, "failure retry retains last virtual loop and all its progress")
	_check(WorldState.knows(&"shared_knowledge") and TextDatabase.get_record_texts().has("跨世界保留的信息"), "knowledge and information survive failure and worlds")
	_check(WorldJourney.return_to_reality() and WorldState.capture_snapshot() == real_checkpoint, "failure real progress available on next attempt")
	_check(not WorldJourney.failed and WorldTime.elapsed_seconds == 0.0, "next real attempt receives full timer")
	WorldTime.advance_time(100.0)
	_check(_failure_count == 2, "next real attempt can fail independently")
	_check(WorldJourney.return_to_virtual(), "second failure can retry again")
	# 恢复的最后一轮耗尽后，仍能自然开启新一轮。
	WorldTime.advance_time(100.0)
	_check(WorldTime.begin_reset() and WorldTime.start_loop() and WorldTime.loop_index == 3, "retried virtual loop still advances naturally")
	_check(not WorldState.get_flag(&"progress") and WorldState.knows(&"shared_knowledge"), "new natural loop resets temporary state while retaining knowledge")


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("WORLD_JOURNEY_TEST FAILED: " + message)
