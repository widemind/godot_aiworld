extends PlanetRoom
## 火星 2 层：地下洞穴与制造厂。
##
## 设计稿对应（知识地图 / 火星 2 层）：
## - 「发电厂：地球开灯是通电、算力中心的位置」「制造厂：太阳观测器在水星 1 层水流源头、
##    扫描可用于打乱电码」。
## 2 层比 1 层更窄，障碍更密，是「洞穴」。

var _factory: MapBuilding
var _plant: MapBuilding


func _build_room() -> void:
	room_id = &"mars_2"
	display_name = "火星"
	layer_name = "2 层 · 洞穴"
	room_size = Vector2(1800.0, 1200.0)
	exit_position = Vector2(140.0, 140.0)

	_plant = add_building("mars_power_plant", &"power_plant", Vector2(520.0, 900.0), &"", true, true, 360.0)
	# 制造厂藏在地下：只有扫描才显形
	_factory = add_building("mars_manufactory", &"manufactory", Vector2(1380.0, 300.0), &"", false, true, 380.0)

	# 洞穴：弯曲的岩壁把制造厂围在深处
	add_obstacle("mars2_a", Rect2(300.0, 300.0, 70.0, 700.0))
	add_obstacle("mars2_b", Rect2(300.0, 300.0, 900.0, 70.0))
	add_obstacle("mars2_c", Rect2(1130.0, 300.0, 70.0, 500.0))
	add_obstacle("mars2_d", Rect2(700.0, 800.0, 600.0, 70.0))

	feedback.emit("火星 2 层。洞穴里的空气很干，深处有东西在发光。")


func _handle_building_interaction(building: MapBuilding) -> bool:
	if building == _factory and not building.lit:
		building.light_up()
		WorldState.record_knowledge(&"tower_build_reason")
		WorldState.record_knowledge(&"power_is_light")
		feedback.emit("制造厂的记录：太阳观测器在水星 1 层的水流源头；扫描可以用来打乱电码。")
		return true
	return false


func _observe_text(building: MapBuilding) -> String:
	if building == _plant:
		return "发电厂把灯连成网。记录里写着：地球开灯就是通电。"
	return super._observe_text(building)
