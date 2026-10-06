extends Node
## 独立行为测试场景：覆盖跨事件跳跃、同刻排序、暂停与循环边界。
## headless 运行后输出汇总并以失败数量决定进程退出码。

const TIMELINE: WorldTimeline = preload("res://resources/time/demo_timeline.tres")

var _passed: int = 0
var _failed: int = 0
var _events: Array[StringName] = []
var _outcomes: Array[Dictionary] = []


func _ready() -> void:
	await get_tree().process_frame
	WorldTime.set_process(false)
	WorldTime.event_reached.connect(func(event: WorldTimeEvent) -> void:
		if not String(event.event_id).begins_with("_action_"):
			_events.append(event.event_id))
	ActionController.action_finished.connect(func(action: WorldAction, succeeded: bool, reason: StringName) -> void:
		_outcomes.append({"id": action.action_id, "succeeded": succeeded, "reason": reason}))
	_test_normal_and_pause()
	_test_events_and_reset()
	_test_order_and_invalid_config()
	_test_action_conditions()
	_test_acceleration_and_cancellation()
	_test_loop_end()
	await _test_real_frames()
	print("TIME_SYSTEM_TESTS passed=%d failed=%d" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("TIME_SYSTEM_TEST FAILED: " + message)


func _new_loop(events: Array[WorldTimeEvent] = TIMELINE.events) -> void:
	PauseController.set_paused(false)
	if WorldTime.phase == WorldTime.Phase.RUNNING:
		WorldTime.advance_time(WorldTime.loop_duration)
	if WorldTime.phase == WorldTime.Phase.ENDED:
		_check(WorldTime.begin_reset(), "can enter reset phase")
	_check(WorldTime.configure(600.0, events), "valid timeline accepted")
	_check(WorldState.configure_initial(TIMELINE.initial_flags, &"harbor"), "initial world accepted")
	_events.clear()
	_outcomes.clear()
	_check(WorldTime.start_loop(), "loop starts")


func _action(duration: float, id: StringName = &"test") -> WorldAction:
	var result := WorldAction.new()
	result.action_id = id
	result.duration_seconds = duration
	return result


func _event(id: StringName, time: float, changes: Dictionary = {}, priority: int = 0) -> WorldTimeEvent:
	var result := WorldTimeEvent.new()
	result.event_id = id
	result.at_seconds = time
	result.changes = changes
	result.priority = priority
	return result


func _test_normal_and_pause() -> void:
	_new_loop()
	WorldTime._process(1.25)
	_check(is_equal_approx(WorldTime.elapsed_seconds, 1.25), "normal rate is 1:1")
	PauseController.set_paused(true)
	_check(WorldTime.advance_time(60.0) == 0.0, "paused instant advance blocked")
	_check(WorldTime.skip_to(300.0) == 0.0, "paused skip blocked")
	_check(not ActionController.execute_instant(_action(5.0)), "paused action blocked")
	_check(not WorldState.apply_changes({&"gate_open": true}), "paused state mutation blocked")
	WorldTime._process(10.0)
	_check(is_equal_approx(WorldTime.elapsed_seconds, 1.25), "paused frame does not advance")
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	PauseController._unhandled_input(escape)
	_check(not get_tree().paused, "pause key resumes")
	WorldTime._process(1.0)
	_check(is_equal_approx(WorldTime.elapsed_seconds, 2.25), "resume has no paused-time catch-up")
	_check(WorldTime.process_mode == Node.PROCESS_MODE_PAUSABLE, "clock is pausable")
	_check(PauseController.process_mode == Node.PROCESS_MODE_ALWAYS, "pause input remains active")


func _test_events_and_reset() -> void:
	_new_loop()
	WorldTime.skip_to(120.0)
	_check(is_equal_approx(WorldTime.advance_time(180.0), 180.0), "jump reaches target")
	_check(_events == [&"gate_open", &"machine_start", &"gate_close"], "all crossed events execute in order")
	_check(WorldState.get_flag(&"gate_open") == false, "gate final state closed")
	_check(WorldState.get_flag(&"machine_running") == true, "unvisited machine still changes")
	WorldTime.advance_time(0.0)
	_check(_events.size() == 3, "events never repeat within a loop")
	_check(WorldTime.skip_to(100.0) == 0.0, "backward skip rejected")
	_check(WorldTime.advance_time(-1.0) == 0.0, "negative duration rejected")
	_check(WorldTime.advance_time(NAN) == 0.0, "NaN duration rejected")
	WorldState.record_knowledge(&"known_method")
	WorldState.move_to(&"core")
	_new_loop()
	_check(WorldTime.elapsed_seconds == 0.0, "reset clears time")
	_check(WorldState.player_location == &"harbor", "reset restores location")
	_check(WorldState.get_flag(&"machine_running") == false, "reset restores temporary flags")
	_check(WorldState.knows(&"known_method"), "knowledge survives reset")
	WorldTime.skip_to(300.0)
	_check(_events == [&"gate_open", &"machine_start", &"gate_close"], "events repeat identically next loop")
	var snapshot := WorldState.get_flags()
	snapshot[&"gate_open"] = true
	_check(WorldState.get_flag(&"gate_open") == false, "snapshot cannot mutate world")


func _test_order_and_invalid_config() -> void:
	var events: Array[WorldTimeEvent] = [
		_event(&"second", 5.0, {}, 1), _event(&"first", 5.0, {}, 0),
		_event(&"third", 5.0, {}, 1), _event(&"zero", 0.0, {&"machine_running": true})]
	_new_loop(events)
	_check(_events == [&"zero"], "zero-time events execute after world reset")
	_check(WorldState.get_flag(&"machine_running") == true, "zero-time changes retained")
	WorldTime.advance_time(10.0)
	_check(_events == [&"zero", &"first", &"second", &"third"], "same-time priority and stable registration order")
	_check(not WorldTime.configure(600.0, events), "running timeline cannot be replaced")
	_check(not WorldState.meets_conditions({&"missing": false}), "missing flags do not satisfy false condition")
	WorldTime.advance_time(600.0)
	var duplicate_events: Array[WorldTimeEvent] = [_event(&"same", 1.0), _event(&"same", 2.0)]
	_check(not WorldTime.configure(600.0, duplicate_events), "duplicate IDs rejected")
	var terminal_events: Array[WorldTimeEvent] = [_event(&"terminal", 600.0)]
	_check(not WorldTime.configure(600.0, terminal_events), "terminal event rejected")
	_check(not WorldTime.configure(0.0, []), "nonpositive loop duration rejected")
	_check(not WorldTime.configure(INF, []), "infinite loop duration rejected")


func _test_action_conditions() -> void:
	_new_loop()
	var travel := _action(60.0)
	travel.start_conditions = {&"gate_open": true}
	travel.finish_conditions = {&"gate_open": true}
	travel.destination = &"observatory"
	_check(not ActionController.execute_instant(travel), "start condition prevents action")
	_check(WorldTime.elapsed_seconds == 0.0, "rejected action costs no time")
	WorldTime.skip_to(220.0)
	_check(ActionController.execute_instant(travel), "valid travel starts")
	_check(WorldTime.elapsed_seconds == 280.0, "instant action consumes extra duration")
	_check(WorldState.player_location == &"harbor", "failed arrival does not change location")
	_check(_outcomes.back()["reason"] == &"finish_condition", "arrival checks final world")
	_new_loop()
	WorldTime.skip_to(180.0)
	var research := _action(60.0)
	research.finish_conditions = {&"machine_running": true}
	research.result_changes = {&"deciphered": true}
	ActionController.execute_instant(research)
	_check(_outcomes.back()["succeeded"], "world event precedes completion at same time")
	_check(WorldState.get_flag(&"deciphered") == true, "successful result applies")
	# 结果变更通知可能打开菜单，位置与结果必须在通知前同时提交。
	_new_loop()
	var atomic_action := _action(1.0)
	atomic_action.destination = &"observatory"
	atomic_action.result_changes = {&"deciphered": true}
	var pause_on_result := func() -> void:
		if WorldState.get_flag(&"deciphered", false):
			PauseController.set_paused(true)
	WorldState.state_changed.connect(pause_on_result)
	ActionController.execute_instant(atomic_action)
	_check(WorldState.player_location == &"observatory", "completion callback cannot split location and result")
	_check(_outcomes.back()["succeeded"], "atomic completion succeeds despite callback pause")
	WorldState.state_changed.disconnect(pause_on_result)
	_new_loop()
	WorldTime.skip_to(220.0)
	travel.finish_conditions = {}
	ActionController.execute_instant(travel)
	_check(WorldState.player_location == &"observatory", "start-only condition need not persist")
	var transient_events: Array[WorldTimeEvent] = TIMELINE.events.duplicate()
	transient_events.append(_event(&"gate_reopen", 290.0, {&"gate_open": true}))
	_new_loop(transient_events)
	WorldTime.skip_to(220.0)
	var crossing := _action(80.0)
	crossing.during_conditions = {&"gate_open": true}
	crossing.destination = &"core"
	ActionController.execute_instant(crossing)
	_check(WorldTime.elapsed_seconds == 280.0, "during-condition failure stops at exact event boundary")
	_check(_outcomes.back()["reason"] == &"during_condition", "during-condition failure recorded")
	WorldTime.skip_to(310.0)
	_check(WorldState.player_location == &"harbor", "later reopening cannot revive cancelled action")
	_check(_outcomes.size() == 1, "cancelled completion event cannot fire")
	_check(ActionController.execute_instant(_action(0.0)), "zero-duration action completes")
	_check(not ActionController.is_busy(), "zero-duration action does not block future input")


func _test_acceleration_and_cancellation() -> void:
	_new_loop()
	WorldTime.skip_to(120.0)
	_check(ActionController.execute_timed(_action(60.0), 10.0), "accelerated wait starts")
	_check(not ActionController.execute_instant(_action(2.0)), "concurrent action rejected")
	WorldTime._process(6.5)
	_check(is_equal_approx(WorldTime.elapsed_seconds, 180.5), "remaining frame uses normal rate after completion")
	_check(WorldTime.flow_rate == 1.0, "completion restores rate")
	_check(not ActionController.is_busy(), "timed action completes")
	_new_loop()
	ActionController.execute_timed(_action(60.0), 10.0)
	WorldTime._process(1.0)
	PauseController.set_paused(true)
	WorldTime._process(20.0)
	_check(WorldTime.elapsed_seconds == 10.0, "pause freezes accelerated action")
	_check(ActionController.is_busy(), "pause preserves active action")
	_check(not ActionController.cancel_action(), "paused cancellation blocked")
	PauseController.set_paused(false)
	_check(ActionController.cancel_action(), "unpaused cancellation accepted")
	_check(WorldTime.flow_rate == 1.0, "cancel restores rate")
	WorldTime.skip_to(100.0)
	_check(_outcomes.size() == 1 and _outcomes[0]["reason"] == &"cancelled", "no stale finish after cancellation")
	_check(not ActionController.execute_timed(_action(2.0), 0.0), "zero acceleration rate rejected")


func _test_loop_end() -> void:
	_new_loop()
	WorldTime.skip_to(590.0)
	var action := _action(10.0)
	action.destination = &"escaped"
	action.result_changes = {&"deciphered": true}
	var loop_before := WorldTime.loop_index
	ActionController.execute_instant(action)
	_check(WorldTime.phase == WorldTime.Phase.ENDED, "exact terminal completion ends loop")
	_check(_outcomes.back()["reason"] == &"loop_ended", "terminal action cancelled")
	_check(WorldState.player_location == &"harbor", "terminal action cannot move player")
	_check(WorldState.get_flag(&"deciphered") == false, "terminal action cannot apply results")
	_check(WorldTime.advance_time(1000.0) == 0.0, "ended loop refuses advancement")
	_check(WorldTime.loop_index == loop_before, "excess duration does not spill into next loop")
	_check(WorldTime.begin_reset(), "reset presentation begins")
	_check(WorldTime.start_loop(), "next loop starts explicitly")
	_check(WorldTime.flow_rate == 1.0 and WorldTime.elapsed_seconds == 0.0, "new loop restores clock")
	_check(not ActionController.is_busy(), "new loop has no stale action")


func _test_real_frames() -> void:
	_new_loop()
	WorldTime.set_process(true)
	await get_tree().create_timer(0.15).timeout
	_check(WorldTime.elapsed_seconds >= 0.1 and WorldTime.elapsed_seconds < 0.5, "actual frame processing advances clock")
	PauseController.set_paused(true)
	var paused_time := WorldTime.elapsed_seconds
	await get_tree().create_timer(0.1, true).timeout
	_check(WorldTime.elapsed_seconds == paused_time, "actual paused frames keep clock frozen")
	PauseController.set_paused(false)
