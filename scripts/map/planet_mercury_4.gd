extends PlanetRoom
## 水星 4 层（核心）：水星 AI Mercury。
##
## 设计稿对应（故事流程 / 知识地图）：
## - 「进入水星核心 → ai 正在对世界进行模拟，星空出现渲染错误（时间）」。
## - 「与 ai 对话 → 将地球所有灯都打开，能在中央区域的一个电脑直接与 ai 对话」。
## 这一层没有发电机、没有出口之外的可点亮建筑，只有 Mercury 本体。

const DIALOGUE := preload("res://scripts/map/map_dialogue.gd")

var _mercury: MapBuilding
var _talked: Array[StringName] = []


func _build_room() -> void:
	room_id = &"mercury_4"
	display_name = "水星"
	layer_name = "4 层 · 核心"
	room_size = Vector2(1600.0, 1000.0)
	exit_position = Vector2(140.0, 140.0)

	_mercury = add_building("mercury_core_ai", &"core", Vector2(1000.0, 500.0), &"", true, false, 420.0)
	feedback.emit("水星 4 层。核心的热度让空气发白，Mercury 在这里等着和你说第一句话。")


func _handle_building_interaction(building: MapBuilding) -> bool:
	if building != _mercury:
		return false
	# 与 Mercury 对话：按知识分层推进，台词来自共用的对话表
	var known := knowledge_snapshot()
	for key in _granted_keys():
		known[key] = WorldState.knows(key)
	var lines := DIALOGUE.available_lines(&"mercury_ai", known, WorldState.get_flags(), _said_keys())
	if lines.is_empty():
		feedback.emit("Mercury 沉默了。你已经问完了它愿意说的。")
		return true
	var line: Dictionary = lines[0]
	WorldState.record_knowledge(StringName(line["key"]))
	var grant := StringName(line["grant"])
	if grant != &"":
		WorldState.record_knowledge(grant)
	feedback.emit("【水星 AI Mercury】" + String(line["text"]))
	# 接触过 Mercury 之后，3 → 4 层的门永久打开
	WorldState.apply_changes({&"met_mercury_ai": true})
	return true


func _observe_text(building: MapBuilding) -> String:
	if building == _mercury:
		return TerrainState.mercury_observe_text(4, WorldState.get_flags())
	return super._observe_text(building)


func _said_keys() -> Array:
	var said: Array = []
	for index in DIALOGUE.LINES[&"mercury_ai"].size():
		var key := DIALOGUE.line_key(&"mercury_ai", index)
		if WorldState.knows(key):
			said.append(key)
	return said


func _granted_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	for index in DIALOGUE.LINES[&"mercury_ai"].size():
		var grant := StringName(DIALOGUE.LINES[&"mercury_ai"][index].get("grant", &""))
		if grant != &"" and not keys.has(grant):
			keys.append(grant)
	return keys
