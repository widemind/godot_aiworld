extends PlanetRoom
## 水星 1 层：太阳观测塔基座与水流方向。
##
## 设计稿对应（知识地图 / 水星 1 层 + 执行细节）：
## - 「水星分 1.2.3.4 层，常驻玩家可在 1.2.3 层间自由切换，而 3 到 4 层会被拒绝」。
## - 「10 分钟后 1 层发生变换，但不消失，在 1 层时观察出现的文本产生变化」。
## - 「1 层节点：太阳观测塔（太阳语料 1 / 进入赤阳之塔的方法 / 观测塔开关 / 观测塔结果）、
##    10 分钟水星消失」。

## 前往 2 层的通道口
var _layer_gate: MapBuilding


func _build_room() -> void:
	room_id = &"mercury_1"
	display_name = "水星"
	layer_name = "1 层"
	room_size = Vector2(2400.0, 1400.0)
	exit_position = Vector2(140.0, 140.0)

	add_building("mercury_tower_perch", &"tower_perch", Vector2(760.0, 620.0), &"", true, false)
	_layer_gate = add_building("mercury_gate_to_2", &"school", Vector2(1820.0, 420.0), &"", true, false)
	_layer_gate.name = "mercury_gate_to_2"
	# 水星 1 层的地表障碍：水流切出的沟壑
	add_obstacle("mercury_rift_a", Rect2(1000.0, 200.0, 60.0, 620.0))
	add_obstacle("mercury_rift_b", Rect2(1000.0, 980.0, 60.0, 300.0))

	feedback.emit("水星 1 层。地表还结着冰，水流沿着塔基缓缓经过。")


func _observe_text(building: MapBuilding) -> String:
	if building == _layer_gate:
		return "往下走的通道。水星 1 到 3 层可以自由来去，3 层之下要看核心有没有露出来。"
	if building.kind == &"tower_perch":
		return TerrainState.observatory_read(WorldState.get_flags())
	return super._observe_text(building)
