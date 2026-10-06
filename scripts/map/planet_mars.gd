extends PlanetRoom
## 火星 1 层：算力中心与迷宫入口。
##
## 设计稿对应（知识地图 / 火星 1 层 + 执行细节）：
## - 「火星 AI Mars → 人类全力发展 ai，寻找躲避太阳危机的办法，警告模拟进程可能因为
##    在错误的地点观察而终止」。
## - 「1 层、2 层分布有阻挡移动的障碍，形成迷宫与洞穴」。
## - 「火星上切换层级只能通过分布在地图上的洞口」。

var _mars: MapBuilding
var _hole: MapBuilding


func _build_room() -> void:
	room_id = &"mars_1"
	display_name = "火星"
	layer_name = "1 层"
	room_size = Vector2(2200.0, 1500.0)
	exit_position = Vector2(140.0, 140.0)

	_mars = add_building("mars_computing_center", &"computing_center", Vector2(1700.0, 360.0), &"", true, true, 400.0)
	_hole = add_building("mars_hole_down", &"manufactory", Vector2(1800.0, 1180.0), &"", true, false)
	_hole.name = "mars_hole_down"

	# 迷宫：交错的岩壁，只留一条通往洞口的路
	add_obstacle("mars_a", Rect2(400.0, 300.0, 700.0, 70.0))
	add_obstacle("mars_b", Rect2(1000.0, 300.0, 70.0, 600.0))
	add_obstacle("mars_c", Rect2(560.0, 830.0, 700.0, 70.0))
	add_obstacle("mars_d", Rect2(560.0, 830.0, 70.0, 500.0))
	add_obstacle("mars_e", Rect2(1200.0, 700.0, 70.0, 700.0))

	feedback.emit("火星 1 层。岩壁把地表切成迷宫，洞口在东侧。")


func _handle_building_interaction(building: MapBuilding) -> bool:
	if building == _hole:
		# 洞穴只在 1 层；必须走到这里才能换层（星图会在洞口附近放行）
		if player().global_position.distance_to(building.global_position) <= 200.0:
			feedback.emit("洞口就在脚边。按 HUD 的「下一层」进入火星 2 层。")
		else:
			feedback.emit("洞口还离得很远，先走过去。")
		return true
	if building != _mars:
		return false
	# 与 Mars 对话：同样按知识分层
	var known := knowledge_snapshot()
	for index in MapDialogue.LINES[&"mars_ai"].size():
		var grant := StringName(MapDialogue.LINES[&"mars_ai"][index].get("grant", &""))
		if grant != &"":
			known[grant] = WorldState.knows(grant)
	var said: Array = []
	for index in MapDialogue.LINES[&"mars_ai"].size():
		var key := MapDialogue.line_key(&"mars_ai", index)
		if WorldState.knows(key):
			said.append(key)
	var lines := MapDialogue.available_lines(&"mars_ai", known, WorldState.get_flags(), said)
	if lines.is_empty():
		feedback.emit("Mars 不再回应。")
		return true
	var line: Dictionary = lines[0]
	WorldState.record_knowledge(StringName(line["key"]))
	var grant := StringName(line["grant"])
	if grant != &"":
		WorldState.record_knowledge(grant)
	feedback.emit("【火星 AI Mars】" + String(line["text"]))
	return true


func _observe_text(building: MapBuilding) -> String:
	if building == _mars:
		return "算力中心的风扇声盖过了一切。屏幕上跳出一行警告：观察地点错误会让模拟进程终止。"
	if building == _hole:
		return "洞口通向火星 2 层。"
	return super._observe_text(building)
