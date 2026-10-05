extends Node
## 世界数据不依赖地点场景是否加载。知识记录跨轮保留，临时标记每轮重建。

signal state_changed
signal knowledge_changed

var player_location: StringName = &"harbor"
var _flags: Dictionary = {}
var _knowledge: Dictionary = {}
var _initial_flags: Dictionary = {}
var _initial_location: StringName = &"harbor"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	# Autoload 顺序保证世界事件先落入数据，再由行动控制器检查条件。
	WorldTime.event_reached.connect(_on_event_reached)
	WorldTime.loop_reset.connect(_on_loop_reset)


func configure_initial(flags: Dictionary, location: StringName) -> bool:
	if WorldTime.phase == WorldTime.Phase.RUNNING or WorldTime.is_advancing():
		return false
	_initial_flags = flags.duplicate(true)
	_initial_location = location
	return true


func get_flag(key: StringName, fallback: Variant = null) -> Variant:
	return _flags.get(key, fallback)


func get_flags() -> Dictionary:
	return _flags.duplicate(true)


func capture_snapshot() -> Dictionary:
	# 知识和 TextDatabase 常驻且跨世界共享，无需在切换时重建。
	return {"flags": _flags.duplicate(true), "location": player_location}


func restore_snapshot(snapshot: Dictionary) -> bool:
	if WorldTime.phase == WorldTime.Phase.RUNNING or WorldTime.is_advancing() or get_tree().paused:
		return false
	if not snapshot.get("flags") is Dictionary or not snapshot.has("location"):
		return false
	_flags = snapshot["flags"].duplicate(true)
	player_location = StringName(snapshot["location"])
	state_changed.emit()
	return true


func restore_initial() -> bool:
	return restore_snapshot({"flags": _initial_flags, "location": _initial_location})


func meets_conditions(conditions: Dictionary) -> bool:
	for key in conditions:
		# 缺失标记不应误满足条件；要求 false 的标记也需在初始数据中定义。
		if not _flags.has(key) or _flags[key] != conditions[key]:
			return false
	return true


func apply_changes(changes: Dictionary, destination: StringName = &"") -> bool:
	if not WorldTime.can_advance():
		return false
	if changes.is_empty() and destination.is_empty():
		return true
	# 一组变化原子写入，再通知行动和场景，避免观察到半更新的世界。
	_flags.merge(changes.duplicate(true), true)
	if not destination.is_empty():
		player_location = destination
	state_changed.emit()
	return true


func move_to(location: StringName) -> bool:
	if not WorldTime.can_advance() or location.is_empty():
		return false
	return apply_changes({}, location)


func record_knowledge(knowledge_id: StringName) -> bool:
	if not WorldTime.can_advance() or knowledge_id.is_empty():
		return false
	if not _knowledge.has(knowledge_id):
		_knowledge[knowledge_id] = true
		knowledge_changed.emit()
	return true


func knows(knowledge_id: StringName) -> bool:
	return _knowledge.has(knowledge_id)


func record_information(content: String) -> bool:
	# 兼容既有探索的字符串接口，收集统一交给 TextDatabase。
	if not WorldTime.can_advance() or content.strip_edges().is_empty():
		return false
	var piece := TextPieces.new()
	piece.text = content
	piece.in_information_list = true
	TextDatabase.collect_text(piece)
	return true


func get_collected_information() -> Array[String]:
	# 兼容旧调用方，不再维护另一份信息记录。
	return TextDatabase.get_record_texts()


func _on_event_reached(event: WorldTimeEvent) -> void:
	apply_changes(event.changes)


func _on_loop_reset(_loop_index: int) -> void:
	_flags = _initial_flags.duplicate(true)
	player_location = _initial_location
	state_changed.emit()
