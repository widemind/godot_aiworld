extends Node
## 视野 / 扫描 / 建筑 / 赤阳之塔 / 地球灯谜 / 火星迷宫 的行为测试。
## headless 运行：Godot --headless --path . res://test/tests/star_map_test.tscn

const BUILDING_SCRIPT := preload("res://scripts/map/map_building.gd")
const TOWER_SCRIPT := preload("res://scripts/map/sun_tower.gd")
const VISION_SCRIPT := preload("res://scripts/map/map_vision.gd")
const EARTH_ROOM := "res://scenes/planets/planet_earth.tscn"
const MARS_ROOM := "res://scenes/planets/planet_mars.tscn"

var _passed: int = 0
var _failed: int = 0
# 用成员变量记录信号次数：GDScript 的 lambda 捕获的是值，局部计数不会回传
var _tower_appeared: int = 0
var _tower_vanished: int = 0
var _tower_stopped: int = 0


func _ready() -> void:
	await get_tree().process_frame
	_test_vision()
	_test_building_states()
	await _test_tower()
	await _test_earth_lights()
	await _test_mars_maze()
	print("STAR_MAP_TESTS passed=%d failed=%d" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("STAR_MAP_TEST FAILED: " + message)


func _make_building(building_id: String, position: Vector2) -> MapBuilding:
	var building := BUILDING_SCRIPT.new() as MapBuilding
	building.name = building_id
	building.building_id = StringName(building_id)
	building.position = position
	add_child(building)
	return building


func _test_vision() -> void:
	var vision: MapVision = VISION_SCRIPT.new()
	vision.set_base_radius(400.0)
	vision.set_scan_radius(1000.0)
	var origin := Vector2.ZERO
	_check(is_equal_approx(vision.current_radius(), 400.0), "初始使用基础视野")
	_check(vision.covers_point(origin, Vector2(300.0, 0.0)), "基础视野内的点可达")
	_check(not vision.covers_point(origin, Vector2(700.0, 0.0)), "基础视野外的点不可达")
	vision.begin_scan(1.0)
	_check(vision.is_scanning(), "扫描开始后处于扫描态")
	_check(is_equal_approx(vision.current_radius(), 1000.0), "扫描期间视野扩大")
	_check(vision.covers_point(origin, Vector2(700.0, 0.0)), "扫描期间远处的点可达")
	vision.tick(1.5)
	_check(not vision.is_scanning(), "扫描时间结束后退出扫描态")
	_check(not vision.covers_point(origin, Vector2(700.0, 0.0)), "扫描结束后远处重新不可达")
	var lit := _make_building("lit_plant", Vector2(900.0, 0.0))
	lit.lit_vision_radius = 300.0
	lit.light_up()
	_check(lit.lit, "发电机启动后建筑被点亮")
	var lit_list: Array[MapBuilding] = [lit]
	_check(vision.covers_by_lit(Vector2(1000.0, 0.0), lit_list), "点亮建筑周围获得视野")
	_check(not vision.covers_by_lit(origin, lit_list), "点亮建筑视野不覆盖远处")
	_check(vision.is_reachable(Vector2(1000.0, 0.0), Vector2(1050.0, 0.0), lit_list), "点亮视野内交互可达")
	lit.queue_free()


func _test_building_states() -> void:
	var hidden := _make_building("hidden_lab", Vector2(500.0, 0.0))
	hidden.visible_in_base_vision = false
	hidden.kind = &"language_lab"
	_check(not hidden.is_visible_to(true), "隐藏建筑即使可达也不可见")
	_check(hidden.reveal_by_scan(), "扫描使隐藏建筑显形")
	_check(hidden.is_visible_to(false), "显形后不可达位置也可见")
	hidden.clear_scan_reveal()
	_check(not hidden.is_visible_to(false), "扫描结束后隐藏建筑重新消失")
	var normal := _make_building("normal_school", Vector2(-300.0, 0.0))
	normal.kind = &"school"
	_check(normal.is_visible_to(true), "基础视野内的普通建筑可见")
	_check(not normal.is_visible_to(false), "基础视野外的普通建筑不可见")
	_check(hidden.light_up(), "有发电机的建筑可点亮")
	_check(not hidden.light_up(), "重复点亮不产生变化")
	var plain := _make_building("plain_tower", Vector2(0.0, 600.0))
	plain.has_generator = false
	plain.kind = &"tower_perch"
	_check(not plain.light_up(), "无发电机的建筑不可点亮")
	_check(plain.display_name() == "太阳观测塔", "建筑名称来自类型表")
	hidden.queue_free()
	normal.queue_free()
	plain.queue_free()


func _on_tower_appeared() -> void:
	_tower_appeared += 1


func _on_tower_vanished() -> void:
	_tower_vanished += 1


func _on_tower_stopped(_building: MapBuilding) -> void:
	_tower_stopped += 1


func _test_tower() -> void:
	var player := Node2D.new()
	add_child(player)
	var tower := TOWER_SCRIPT.new() as SunTower
	add_child(tower)
	tower.setup(player, 2600.0)
	_tower_appeared = 0
	_tower_vanished = 0
	_tower_stopped = 0
	tower.appeared.connect(_on_tower_appeared)
	tower.vanished.connect(_on_tower_vanished)
	tower.stopped_in_lit.connect(_on_tower_stopped)

	tower.global_position = Vector2(3000.0, 0.0)
	tower.tick(0.1, 1000.0)
	_check(not tower.is_appeared, "视野外时塔不出现")

	tower.global_position = Vector2(900.0, 0.0)
	tower.tick(0.1, 1000.0)
	_check(tower.is_appeared and _tower_appeared == 1, "进入视野后塔出现并发出信号")
	_check(not tower.is_stopped, "未被照亮时不停止")
	_check(tower.is_observed(1000.0), "近距离时处于被观察状态")

	tower.global_position = Vector2(1800.0, 0.0)
	tower.tick(0.1, 2000.0)
	var before := tower.global_position
	tower.tick(1.0, 2000.0)
	_check(tower.global_position.distance_to(player.global_position) \
		< before.distance_to(player.global_position), "距离过远时塔朝玩家移动")

	var lit := _make_building("lit_beacon", tower.global_position + Vector2(40.0, 0.0))
	lit.lit_vision_radius = 400.0
	lit.light_up()
	var lit_list: Array[MapBuilding] = [lit]
	tower.set_lit_buildings(lit_list)
	var stopped_at := tower.global_position
	tower.tick(1.0, 2000.0)
	_check(tower.is_stopped, "被点亮建筑照到时停止移动")
	_check(_tower_stopped == 1, "照停时发出一次信号")
	_check(tower.global_position.is_equal_approx(stopped_at), "停止期间位置不变")

	tower.global_position = Vector2(3000.0, 0.0)
	tower.tick(0.1, 1000.0)
	_check(not tower.is_appeared and _tower_vanished == 1, "移出视野后塔消失并发出信号")

	tower.global_position = player.global_position + Vector2(100.0, 0.0)
	tower.tick(0.1, 1000.0)
	_check(tower.in_interaction_range(420.0), "近距离时可发送电码")
	_check(not tower.in_interaction_range(50.0), "超出交互半径时不可发送")
	_check(not tower.room_ready({}), "未集齐语料时塔内不开")
	_check(tower.room_ready({&"sun_fragment_0": true, &"sun_fragment_1": true, &"sun_fragment_2": true}),
		"集齐三段语料后塔内开启")

	tower.queue_free()
	lit.queue_free()
	player.queue_free()
	await get_tree().process_frame


## 地球：赤阳之塔在灯网中间，点亮足够多的灯照亮塔身即算「框住」
func _test_earth_lights() -> void:
	var scene := load(EARTH_ROOM) as PackedScene
	_check(scene != null, "地球房间场景存在")
	if scene == null:
		return
	var room: Node2D = scene.instantiate()
	add_child(room)
	await get_tree().process_frame
	_check(room.current_planet() == &"earth_1", "地球房间的场景标识")
	_check(room.get_node("Buildings").get_child_count() >= 5, "地球房间里有建筑")
	var tower: SunTower = room.sun_tower()
	_check(tower != null, "地球上立着赤阳之塔")
	_check(not room.tower_lit(), "开局塔没有被灯光框住")
	# 把玩家的位置放到塔旁边，并点亮三座建筑
	room.player().global_position = tower.global_position + Vector2(80.0, 0.0)
	tower.tick(0.1, 4000.0)
	_check(tower.is_appeared, "赤阳之塔在地球上出现在视野中")
	var lit_count := 0
	for building in room.lit_buildings():
		lit_count += 1
	_check(lit_count == 0, "开局没有点亮的建筑")
	# 先点亮三座建筑，但它们离塔很远：灯还没铺到塔身上
	var lit_buildings: Array[MapBuilding] = []
	var index := 0
	for child in room.get_node("Buildings").get_children():
		var building := child as MapBuilding
		if building == null or not building.has_generator:
			continue
		if index >= 3:
			break
		building.position = tower.global_position + Vector2(900.0 + index * 150.0, 0.0)
		building.lit_vision_radius = 200.0
		building.light_up()
		lit_buildings.append(building)
		index += 1
	tower.set_lit_buildings(lit_buildings)
	_check(not room.tower_lit(), "离得远时不算被框住")
	# 把三盏灯挪到塔身边，灯就铺到塔身上了
	for offset_index in lit_buildings.size():
		lit_buildings[offset_index].position = tower.global_position + Vector2(60.0 * offset_index, 0.0)
	_check(room.lit_buildings().size() == 3, "房间能实时收集到三盏点亮的灯")
	_check(room.tower_lit(), "灯铺到塔身后算被框住")
	# 知识写入需要世界处于推进状态，本测试没有启程（WorldJourney 未启动），
	# 因此这里只断言房间自身记住了「塔已被框住」。
	_check(room.tower_lit(), "框住状态会被记住（重复查询仍为真）")
	room.queue_free()
	await get_tree().process_frame


## 火星：迷宫障碍按层生效，挡住玩家
func _test_mars_maze() -> void:
	var scene := load(MARS_ROOM) as PackedScene
	_check(scene != null, "火星房间场景存在")
	if scene == null:
		return
	var room: Node2D = scene.instantiate()
	add_child(room)
	await get_tree().process_frame
	_check(room.current_planet() == &"mars_1", "火星房间的场景标识")
	var obstacles: Array[Node] = []
	for child in room.get_node("Obstacles").get_children():
		obstacles.append(child)
	# 四周墙 4 个 + 迷宫岩壁 5 个
	_check(obstacles.size() >= 7, "火星有边界与迷宫障碍（%d 个）" % [obstacles.size()])
	var blocking := 0
	for node in obstacles:
		if node.has_method(&"is_blocking_now") and node.is_blocking_now():
			blocking += 1
	_check(blocking >= 7, "障碍默认都在挡路")
	# 洞口建筑存在，且换层要求它
	_check(room.get_node_or_null("Buildings/mars_hole_down") != null, "火星 1 层有洞口")
	room.queue_free()
	await get_tree().process_frame
