extends Node
## 两个世界的流程与进度快照。只在当前运行期间保存，不作为磁盘存档。

signal world_changed(world: int)
signal game_failed

var failed: bool = false
var _virtual_timeline: WorldTimeline
var _real_timeline: WorldTimeline
var _virtual_snapshot: Dictionary = {}
var _real_snapshot: Dictionary = {}
var _virtual_loop: int = 0
var _transitioning: bool = false


func _ready() -> void:
	WorldTime.real_time_ended.connect(_on_real_time_ended)


func is_started() -> bool:
	return _virtual_timeline != null


func start(virtual_timeline: WorldTimeline, real_timeline: WorldTimeline) -> bool:
	if is_started() or _transitioning or WorldTime.phase != WorldTime.Phase.READY \
			or get_tree().paused or not _valid(virtual_timeline) or not _valid(real_timeline):
		return false
	_transitioning = true
	_virtual_timeline = virtual_timeline.duplicate(true) as WorldTimeline
	_real_timeline = real_timeline.duplicate(true) as WorldTimeline
	WorldTime.world = WorldTime.World.VIRTUAL
	var success := _virtual_timeline.install() and WorldTime.start_loop()
	if success:
		world_changed.emit(WorldTime.world)
	else:
		_virtual_timeline = null
		_real_timeline = null
	_transitioning = false
	return success


func return_to_reality() -> bool:
	if not _can_switch() or WorldTime.world != WorldTime.World.VIRTUAL or not WorldTime.can_advance():
		return false
	_transitioning = true
	_virtual_snapshot = WorldState.capture_snapshot()
	_virtual_loop = WorldTime.loop_index
	var success := _enter(WorldTime.World.REAL, _real_timeline, _real_snapshot)
	if success:
		failed = false
		success = WorldTime.start_real_time(not _real_snapshot.is_empty())
	if success:
		world_changed.emit(WorldTime.world)
	_transitioning = false
	return success


func return_to_virtual() -> bool:
	if not _can_switch() or WorldTime.world != WorldTime.World.REAL or _virtual_snapshot.is_empty():
		return false
	_transitioning = true
	# 即使现实已经失败，也保留失败时的 flags 和位置，供下一次进入现实使用。
	_real_snapshot = WorldState.capture_snapshot()
	var success := _enter(WorldTime.World.VIRTUAL, _virtual_timeline, _virtual_snapshot)
	if success:
		failed = false
		success = WorldTime.restart_virtual_loop(_virtual_loop)
	if success:
		world_changed.emit(WorldTime.world)
	_transitioning = false
	return success


func get_saved_progress(world: int) -> Dictionary:
	if world == WorldTime.world:
		return WorldState.capture_snapshot()
	return (_virtual_snapshot if world == WorldTime.World.VIRTUAL else _real_snapshot).duplicate(true)


func _can_switch() -> bool:
	return is_started() and not _transitioning and not WorldTime.is_advancing() and not get_tree().paused


func _valid(timeline: WorldTimeline) -> bool:
	return timeline != null and WorldTime.is_valid_configuration(timeline.loop_duration, timeline.events)


func _enter(world: WorldTime.World, timeline: WorldTimeline, snapshot: Dictionary) -> bool:
	if not WorldTime.change_world(world, timeline.loop_duration, timeline.events):
		return false
	if not WorldState.configure_initial(timeline.initial_flags, timeline.initial_location):
		return false
	return WorldState.restore_initial() if snapshot.is_empty() else WorldState.restore_snapshot(snapshot)


func _on_real_time_ended() -> void:
	if not is_started() or failed:
		return
	_real_snapshot = WorldState.capture_snapshot()
	failed = true
	game_failed.emit()
