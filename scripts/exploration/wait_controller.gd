class_name ExplorationWaitController
extends Node
## 接管探索 UI 的全部等待请求，不依赖地点或 TextSelector。

@export var ui: PlanetExplorationUI
@export_range(1.0, 100.0, 0.5) var short_wait_flow_rate: float = 10.0
@export_range(0.0, 600.0, 1.0) var long_wait_seconds: float = 60.0
@export var short_wait_text: TextPieces
@export var long_wait_text: TextPieces

var _waiting: bool = false
var _previous_rate: float = 1.0
var _pending_long_wait: bool = false
var _ending_loop: bool = false
var _end_request_pending: bool = false


func _ready() -> void:
	if ui == null:
		push_error("WaitController 需要配置探索 UI。")
		return
	ui.action_requested.connect(_on_action_requested)
	ui.wait_until_loop_end_requested.connect(_on_wait_until_loop_end_requested)
	ui.set_wait_until_loop_end_available(true)
	ui.text_closed.connect(stop_waiting)
	ui.tree_exiting.connect(stop_waiting)
	WorldTime.timeline_stopped.connect(stop_waiting)
	WorldTime.loop_ended.connect(stop_waiting.unbind(1))
	WorldTime.real_time_ended.connect(stop_waiting)
	ActionController.action_finished.connect(_on_action_finished)


func _exit_tree() -> void:
	stop_waiting()
	_pending_long_wait = false
	if is_instance_valid(ui):
		ui.set_wait_until_loop_end_available(false)


func is_waiting() -> bool:
	return _waiting or _pending_long_wait or _ending_loop or _end_request_pending


func is_ending_loop() -> bool:
	return _ending_loop


## 暂停菜单主动推进至虚拟循环终点，结束页面读完后由入口开启下一轮。
func wait_until_loop_end() -> bool:
	_end_request_pending = false
	if not _can_end_loop():
		if is_instance_valid(ui) and not _ending_loop:
			ui.set_wait_until_loop_end_available(true)
		return false
	_ending_loop = true
	ui.set_wait_until_loop_end_available(false)
	PauseController.set_paused(false)
	stop_waiting()
	ui.clear_texts()
	while WorldTime.can_advance() and WorldTime.world == WorldTime.World.VIRTUAL:
		var pending_before := WorldTime.get_pending_events().size()
		var advanced := WorldTime.advance_time(WorldTime.get_remaining_seconds())
		# 行动完成和 stop_advancement 事件可能提前停止一次推进；继续至终点。
		# 零时刻停止事件被消费后也能继续，避免无进展时反复循环。
		if advanced <= 0.0 and WorldTime.get_pending_events().size() >= pending_before:
			break
	var success := WorldTime.world == WorldTime.World.VIRTUAL \
		and WorldTime.phase == WorldTime.Phase.ENDED and not get_tree().paused
	_ending_loop = false
	ui.set_wait_until_loop_end_available(true)
	return success


func _can_end_loop() -> bool:
	return is_instance_valid(ui) and not _ending_loop and not WorldTime.is_advancing() \
		and WorldTime.world == WorldTime.World.VIRTUAL and WorldTime.phase == WorldTime.Phase.RUNNING


func _on_wait_until_loop_end_requested() -> void:
	if _end_request_pending or not _can_end_loop():
		return
	_end_request_pending = true
	ui.set_wait_until_loop_end_available(false)
	# 等菜单输入分发结束后再恢复/重建循环，避免触发底层地图。
	wait_until_loop_end.call_deferred()


## 剧情也可直接调用；暂停、终点、已有文本或行动时不开始新等待。
func request_wait(long_press: bool = false) -> bool:
	if not is_instance_valid(ui) or ui.is_text_open() or is_waiting() \
			or not WorldTime.can_advance() or WorldTime.is_advancing() or ActionController.is_busy():
		return false
	if long_press:
		var action := WorldAction.new()
		action.action_id = &"exploration_wait"
		action.duration_seconds = long_wait_seconds
		_pending_long_wait = true
		if not ActionController.execute_instant(action):
			_pending_long_wait = false
			return false
		return true
	_previous_rate = WorldTime.flow_rate
	if not WorldTime.set_flow_rate(short_wait_flow_rate):
		return false
	_waiting = true
	_show_wait_text(short_wait_text, "你在原地等待，时间加速流逝。关闭文本框以结束等待。")
	return true


func stop_waiting() -> void:
	if not _waiting:
		return
	_waiting = false
	if not is_instance_valid(WorldTime) or WorldTime.phase != WorldTime.Phase.RUNNING:
		return
	if WorldTime.set_flow_rate(_previous_rate):
		return
	if get_tree().paused:
		# 静态回调在节点卸载后仍有效；世界/轮次变化后不恢复旧倍率。
		PauseController.pause_changed.connect(
			_restore_after_pause.bind(_previous_rate, WorldTime.world, WorldTime.loop_index), CONNECT_ONE_SHOT)


static func _restore_after_pause(paused: bool, rate: float, world: int, loop: int) -> void:
	if not paused and WorldTime.world == world and WorldTime.loop_index == loop:
		WorldTime.set_flow_rate(rate)


func _on_action_requested(action_id: StringName, long_press: bool) -> void:
	if action_id == &"wait":
		request_wait(long_press)


func _on_action_finished(action: WorldAction, succeeded: bool, _reason: StringName) -> void:
	if action.action_id != &"exploration_wait" or not _pending_long_wait:
		return
	_pending_long_wait = false
	if succeeded and is_instance_valid(ui):
		_show_wait_text(long_wait_text, "等待结束。")


func _show_wait_text(piece: TextPieces, fallback: String) -> void:
	if piece == null or piece.text.strip_edges().is_empty():
		ui.show_text(fallback)
	else:
		ui.show_text_piece(piece)
