extends PlanetRoom
## 水星 2 层：天文台与语言研究所。
##
## 设计稿对应（知识地图 / 水星 2 层）：
## - 「天文台：观测器侦测到太阳语言，但是乱码」「太阳观测器在水星」。
## - 「语言研究所：赤阳之塔的位置」「对太阳语言进行研究」。
## 因此这一层是「破译」层：先在天文台拿到乱码与水流方向，再去语言研究所问出塔的去处。

var _observatory: MapBuilding
var _language_lab: MapBuilding


func _build_room() -> void:
	room_id = &"mercury_2"
	display_name = "水星"
	layer_name = "2 层"
	room_size = Vector2(2200.0, 1400.0)
	exit_position = Vector2(140.0, 140.0)

	_observatory = add_building("mercury_observatory", &"observatory", Vector2(640.0, 480.0), &"", true, true, 380.0)
	# 语言研究所是隐藏建筑：必须扫描才会显形
	_language_lab = add_building("mercury_language_lab", &"language_lab", Vector2(1560.0, 900.0), &"", false, true, 380.0)
	add_obstacle("mercury2_wall_a", Rect2(1080.0, 120.0, 60.0, 520.0))
	add_obstacle("mercury2_wall_b", Rect2(1080.0, 760.0, 60.0, 520.0))

	feedback.emit("水星 2 层。天文台的镜面结着水汽，语言研究所藏在水雾里。")


func _handle_building_interaction(building: MapBuilding) -> bool:
	# 语言研究所：需要先在天文台拿到水流方向，才会说明塔的位置
	if building == _language_lab and not building.lit:
		if WorldState.knows(&"water_flow_south"):
			WorldState.record_knowledge(&"tower_location")
			building.light_up()
			feedback.emit("语言研究所把乱码对上了水流方向：赤阳之塔在地球 1 层的灯网中间。")
			return true
		feedback.emit("研究所的人指了指墙上的乱码：先去天文台把水流方向记下来。")
		return true
	return false


func _observe_text(building: MapBuilding) -> String:
	if building == _observatory:
		return TerrainState.observatory_read(WorldState.get_flags())
	if building == _language_lab:
		return "语言研究所的墙上贴满了点与划。三段最常见的太阳语被单独框了出来。"
	return super._observe_text(building)
