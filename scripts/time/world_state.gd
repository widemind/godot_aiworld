extends Node
## 世界数据不依赖地点场景是否加载。知识记录跨轮保留，临时标记每轮重建。

signal state_changed
signal knowledge_changed

var player_location: StringName = &"harbor"
var _flags: Dictionary = {}
var _knowledge: Dictionary = {}
var _collected_information: Array[String] = []
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
	# 获取顺序跨轮连续；回溯只重置世界状态，不清除已经读到的文本。
	if not WorldTime.can_advance() or content.strip_edges().is_empty():
		return false
	_collected_information.append(content)
	return true


func get_collected_information() -> Array[String]:
	# 返回副本，页面按从晚到早的顺序展示，不暴露可修改的内部数组。
	var newest_first: Array[String] = _collected_information.duplicate()
	newest_first.reverse()
	return newest_first


func _on_event_reached(event: WorldTimeEvent) -> void:
	apply_changes(event.changes)


func _on_loop_reset(_loop_index: int) -> void:
	_flags = _initial_flags.duplicate(true)
	player_location = _initial_location
	state_changed.emit()
