extends PlanetRoom
## 水星 3 层：水汽与通往核心的通道。
##
## 设计稿对应（知识地图 / 水星 3 层）：
## - 「11 分钟水星内层蒸发，露出水星核心」「10 分钟后 3 层发生变换，同理」。
## - 3 到 4 层会被拒绝，直到核心露出（或已经接触过 Mercury）。

var _core_gate: MapBuilding


func _build_room() -> void:
	room_id = &"mercury_3"
	display_name = "水星"
	layer_name = "3 层"
	room_size = Vector2(2000.0, 1200.0)
	exit_position = Vector2(140.0, 140.0)

	_core_gate = add_building("mercury_core_gate", &"core", Vector2(1500.0, 600.0), &"", true, false)
	add_obstacle("mercury3_ridge", Rect2(820.0, 0.0, 70.0, 460.0))
	add_obstacle("mercury3_ridge2", Rect2(820.0, 740.0, 70.0, 460.0))

	var flags := WorldState.get_flags()
	if TerrainState.mercury_core_exposed(flags):
		feedback.emit("水星 3 层。水已经全部蒸发，脚下的地层裂开了。")
	else:
		feedback.emit("水星 3 层。热浪压着岩层，下面还有东西，但现在过不去。")


func _observe_text(building: MapBuilding) -> String:
	if building == _core_gate:
		return TerrainState.mercury_observe_text(3, WorldState.get_flags())
	return super._observe_text(building)
