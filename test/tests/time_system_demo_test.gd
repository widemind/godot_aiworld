extends Node
## 演示按钮端到端回归：走正式时钟、行动与两个世界流程。

const DEMO: PackedScene = preload("res://scenes/time_system_demo.tscn")

var _demo: Control
var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await get_tree().process_frame
	WorldTime.set_process(false)
	_demo = DEMO.instantiate()
	add_child(_demo)
	_test_controls()
	await _test_reload()
	print("TIME_SYSTEM_DEMO_TESTS passed=%d failed=%d" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _press(id: StringName) -> void:
	var button: Button = _demo._controls[id]
	_check(not button.disabled, "button available: " + String(id))
	if not button.disabled:
		button.pressed.emit()


func _test_controls() -> void:
	_check(WorldJourney.is_started() and WorldTime.world == WorldTime.World.VIRTUAL, "demo starts virtual journey")
	_check(WorldTime.get_pending_events().size() == 3 and _demo._queue_label.text.contains("03:00"), "fixed events displayed from live queue")
	_press(&"travel")
	_check(WorldTime.elapsed_seconds == 0.0 and _demo._feedback_label.text.contains("开始条件"), "rejected travel costs no time and explains why")
	_press(&"observe")
	_check(not ActionController.is_busy() and WorldTime.elapsed_seconds == 0.0, "zero duration action completes immediately")
	_press(&"checkpoint")
	_check(WorldState.get_flag(&"demo_progress") == 1 and TextDatabase.get_record_texts().size() == 1, "checkpoint grants world progress and shared information")
	_press(&"dynamic")
	var pending := WorldTime.get_pending_events()
	_check(pending.size() == 5 and pending[0].priority == 0 and pending[1].priority == 10, "dynamic same-time events ordered by priority")
	pending[0].changes[&"dynamic_last_priority"] = 99
	pending[0].at_seconds = 500.0
	_press(&"skip")
	_check(WorldTime.elapsed_seconds == 20.0 and WorldState.get_flag(&"dynamic_last_priority") == 10, "queue snapshots cannot mutate events; stop event truncates jump")
	_check(_demo._log_label.text.contains("event_reached / P0 / demo_pair_") \
		and _demo._log_label.text.contains("event_reached / P10 / demo_pair_"), "both dynamic events appear in signal log")
	_press(&"dynamic")
	_press(&"cancel_dynamic")
	_check(WorldTime.get_pending_events().size() == 3 and _demo._controls[&"cancel_dynamic"].disabled, "cancelled dynamic events removed from queue and controls")
	_press(&"rate_10")
	_check(WorldTime.flow_rate == 10.0 and _demo._clock_label.text.contains("×10.0"), "rate control updates clock display")
	_press(&"rate_1")
	_press(&"wait")
	_check(ActionController.is_busy() and _demo._controls[&"skip"].disabled \
		and not _demo._controls[&"cancel"].disabled, "busy controls disable overlapping actions and permit cancel")
	WorldTime._process(1.0)
	var paused_time := WorldTime.elapsed_seconds
	_press(&"pause")
	WorldTime._process(20.0)
	_check(get_tree().paused and _demo._pause_panel.visible and WorldTime.elapsed_seconds == paused_time, "pause modal freezes timed action")
	(_demo._pause_panel.get_node("Card/Margin/Column/Continue") as Button).pressed.emit()
	_check(not get_tree().paused and not _demo._pause_panel.visible, "resume button restores game")
	_press(&"cancel")
	_check(not ActionController.is_busy() and WorldTime.flow_rate == 1.0 \
		and _demo._feedback_label.text.contains("主动取消"), "cancel restores previous rate and explains outcome")
	_press(&"next_event")
	_check(WorldTime.elapsed_seconds == 180.0 and WorldState.get_flag(&"gate_open"), "next event jump updates gate")
	_press(&"travel")
	_check(WorldState.player_location == &"observatory" and WorldState.get_flag(&"machine_running"), "travel completion follows same-time world event")
	_press(&"investigate")
	_check(WorldState.get_flag(&"deciphered") and WorldState.knows(&"machine_method"), "research grants temporary flag and permanent knowledge")
	_press(&"checkpoint")
	var virtual_checkpoint := WorldState.capture_snapshot()
	var info_count := TextDatabase.get_record_texts().size()
	var loop_before := WorldTime.loop_index
	_press(&"wait")
	_press(&"switch")
	_check(WorldTime.world == WorldTime.World.REAL and WorldTime.elapsed_seconds == 0.0 \
		and not ActionController.is_busy(), "world switch cancels active old-world action and restarts time")
	_check(_demo._log_label.text.contains("world_changed") and _demo._controls[&"travel"].disabled, "world switch visible in log and actions reflect world")
	_press(&"next_event")
	_check(WorldTime.elapsed_seconds == 30.0 and WorldState.get_flag(&"energy_low"), "real timeline uses its own events")
	_press(&"next_event")
	_check(WorldTime.elapsed_seconds == 60.0 and WorldState.get_flag(&"link_ready"), "real link event displayed")
	_press(&"checkpoint")
	_press(&"terminal")
	_check(WorldJourney.failed and WorldTime.phase == WorldTime.Phase.ENDED \
		and _demo._end_panel.visible and _demo._end_title.text.contains("游戏失败"), "real terminal opens failure overlay")
	_check(not WorldState.get_flag(&"terminal_reward", false) and _demo._log_label.text.contains("real_time_ended"), "terminal action fails before granting result")
	var real_checkpoint := WorldState.capture_snapshot()
	_demo._continue_button.pressed.emit()
	_check(WorldTime.world == WorldTime.World.VIRTUAL and WorldTime.loop_index == loop_before \
		and WorldTime.elapsed_seconds == 0.0 and WorldState.capture_snapshot() == virtual_checkpoint, "failure retry restores last virtual loop and full progress")
	_check(not _demo._end_panel.visible and TextDatabase.get_record_texts().size() == info_count + 1, "retry clears overlay and keeps shared information")
	_press(&"switch")
	_check(WorldTime.elapsed_seconds == 0.0 and WorldState.capture_snapshot() == real_checkpoint, "next real attempt restores real progress with full timer")
	_press(&"switch")
	_press(&"end")
	_check(not WorldJourney.failed and _demo._end_title.text.contains("本轮结束"), "virtual terminal shows cycle overlay instead of failure")
	_demo._continue_button.pressed.emit()
	_check(WorldTime.loop_index == loop_before + 1 and WorldState.player_location == &"harbor" \
		and WorldState.get_flag(&"demo_progress", 0) == 0 and WorldState.knows(&"machine_method"), "natural next cycle resets temporary state and retains knowledge")
	WorldTime.skip_to(220.0)
	_press(&"cross")
	WorldTime._process(6.0)
	_check(not ActionController.is_busy() and WorldTime.elapsed_seconds == 280.0 \
		and WorldState.player_location == &"harbor" and _demo._feedback_label.text.contains("执行期间"), "during condition cancels at gate close")
	_press(&"end")
	_demo._continue_button.pressed.emit()
	WorldTime.skip_to(220.0)
	_press(&"travel")
	_check(WorldTime.elapsed_seconds == 280.0 and WorldState.player_location == &"harbor" \
		and _demo._feedback_label.text.contains("完成条件"), "finish condition fails at destination time")


func _test_reload() -> void:
	_press(&"wait")
	var elapsed := WorldTime.elapsed_seconds
	var loop_before := WorldTime.loop_index
	_demo.queue_free()
	await get_tree().process_frame
	_demo = DEMO.instantiate()
	add_child(_demo)
	_check(WorldTime.elapsed_seconds == elapsed and WorldTime.loop_index == loop_before \
		and ActionController.is_busy() and _demo._action_label.text.contains("加速等待"), "scene reload retains timer, loop, action and display")
	_press(&"cancel")
	_press(&"switch")
	_press(&"end")
	_demo.queue_free()
	await get_tree().process_frame
	_demo = DEMO.instantiate()
	add_child(_demo)
	_check(WorldJourney.failed and _demo._end_panel.visible \
		and _demo._end_title.text.contains("游戏失败"), "failed real scene reload remains failed")
	_demo._continue_button.pressed.emit()
	_check(WorldTime.world == WorldTime.World.VIRTUAL and WorldTime.loop_index == loop_before, "reloaded failure can retry same virtual loop")


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("TIME_SYSTEM_DEMO_TEST FAILED: " + message)
