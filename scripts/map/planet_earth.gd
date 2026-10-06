extends PlanetRoom
## 地球 1 层：赤阳之塔的所在地。
##
## 设计稿对应（知识地图 / 地球 + 执行细节）：
## - 地球节点下有：赤阳之塔、学校（太阳观测塔在水星 / 水光蒸发）、发电机（每个建筑中可点亮）、
##   居民楼（地球 AI 需要大量电能 → 电脑）、政府（地球电网连通、Mars 在算力中心）。
## - 「每个建筑中（除赤阳之塔）中有一个发电机，与发电机交互后当前建筑会被点亮，
##    在星球视图下建筑一定圆形范围内将持续获得视野」。
## - 「进入赤阳之塔的方法是把赤阳之塔框进点亮的建筑范围内」——塔本身无法点亮，
##    所以要先把周围的建筑灯点亮，把光铺到塔身上。

const TOWER_SCRIPT := preload("res://scripts/map/sun_tower.gd")
const TOWER_ROOM := preload("res://scenes/ui/tower/tower_room.tscn")

## 点亮多少座建筑后塔才承认被「框住」
const LIGHTS_REQUIRED := 3

var _tower: SunTower
var _tower_lit: bool = false
var _tower_room: Control
var _enter_tower_button: Button


func _build_room() -> void:
	room_id = &"earth_1"
	display_name = "地球"
	layer_name = "1 层"
	room_size = Vector2(2400.0, 1500.0)
	exit_position = Vector2(140.0, 140.0)

	# 地表：学校、发电机、发电厂、居民楼、政府
	add_building("earth_school", &"school", Vector2(520.0, 1180.0), &"", true, true, 300.0)
	add_building("earth_generator", &"generator", Vector2(420.0, 780.0), &"", true, true, 360.0)
	add_building("earth_power_plant", &"power_plant", Vector2(900.0, 420.0), &"", true, true, 420.0)
	add_building("earth_residence", &"residence", Vector2(1420.0, 300.0), &"", true, true, 360.0)
	add_building("earth_government", &"government", Vector2(1900.0, 560.0), &"", true, true, 400.0)
	# 赤阳之塔的基座：不可点亮，塔会停在这附近
	var perch := add_building("earth_tower_perch", &"tower_perch", Vector2(1980.0, 1120.0), &"", true, false)
	perch.lit_vision_radius = 0.0

	# 赤阳之塔本体：只在被观察时出现，被点亮的灯照到会停下
	_tower = TOWER_SCRIPT.new() as SunTower
	_tower.name = "SunTower"
	_tower.global_position = Vector2(1600.0, 1050.0)
	_tower.stop_light_radius = 340.0
	var sprite := Polygon2D.new()
	sprite.polygon = PackedVector2Array([
		Vector2(0.0, -70.0), Vector2(44.0, 60.0), Vector2(-44.0, 60.0),
	])
	sprite.color = Color(1.0, 0.55, 0.35)
	_tower.add_child(sprite)
	var label := Label.new()
	label.position = Vector2(-90.0, 70.0)
	label.add_theme_font_size_override(&"font_size", 28)
	label.text = "赤阳之塔"
	_tower.add_child(label)
	add_child(_tower)
	_tower.setup(player(), 3000.0)

	# 塔内的发送台：以覆盖层形式挂在本房间的 HUD 上
	_tower_room = TOWER_ROOM.instantiate() as Control
	_tower_room.visible = false
	_hud.add_child(_tower_room)
	_tower_room.progress_changed.connect(_on_tower_progress)
	_enter_tower_button = add_hud_button("进入赤阳之塔", _enter_tower)
	_enter_tower_button.disabled = true

	feedback.emit("地球 1 层。赤阳之塔立在城区的灯网中间——它只在被看见时才移动。")


func _process(delta: float) -> void:
	super._process(delta)
	if _tower == null:
		return
	_tower.set_lit_buildings(lit_buildings())
	_tower.tick(delta, vision.current_radius())
	# 进入赤阳之塔：塔被灯框住之后，走到塔身边才能进
	var near := tower_distance() <= interaction_radius
	var ready := _tower_lit and near
	if ready and not _tower_room.visible:
		feedback.emit("赤阳之塔就在眼前。石壁上刻着三段太阳语——进去把它们打出来。")
	if _enter_tower_button != null:
		_enter_tower_button.disabled = not ready


## 打开塔内发送台
func _enter_tower() -> void:
	if not _tower_lit:
		feedback.emit("塔还立在那里动也不动——先用灯把它框住。")
		return
	if tower_distance() > interaction_radius:
		feedback.emit("赤阳之塔不在附近。")
		return
	if _tower_room.visible:
		return
	_tower_room.open(knowledge_snapshot())
	feedback.emit("你走进了赤阳之塔。石壁上刻着三段太阳语。")


## 塔内每打出一段语料，就把对应知识写入世界状态
func _on_tower_progress(completed: int) -> void:
	var index := completed - 1
	if index < 0:
		return
	var granted: StringName = _tower_room.static_knowledge_for(index)
	if granted != &"":
		WorldState.record_knowledge(granted)
	if completed >= _tower_room.FRAGMENT_ORDER.size():
		WorldState.record_knowledge(&"know_ultimate")
		WorldState.record_knowledge(&"tower_build_reason")
		feedback.emit("三段语料连成一句。你知晓了终极太阳语：" \
			+ SunLanguage.word_hint(SunLanguage.ULTIMATE_WORD))


func tower_room() -> Control:
	return _tower_room


## 灯铺到塔身上就算「框住」，之后可以进入。
## 每次都从场景树重新收集已点亮的建筑：玩家是在运行中逐个点亮发电机的，
## 只靠初始化时的那份列表会看不到后来的灯。
func tower_lit() -> bool:
	if _tower_lit:
		return true
	collect_buildings()
	var lights := lit_buildings()
	if lights.size() < LIGHTS_REQUIRED:
		return false
	if _tower_lit or _tower == null:
		return _tower_lit
	for building in lights:
		if _tower.global_position.distance_to(building.global_position) <= building.lit_vision_radius:
			_tower_lit = true
			WorldState.record_knowledge(&"tower_lit")
			feedback.emit("灯光铺到了赤阳之塔身上，塔停住了。现在走到塔边就能进入。")
			return true
	return false


func sun_tower() -> SunTower:
	return _tower


## 塔所在位置与玩家的距离（供测试与交互判定）
func tower_distance() -> float:
	if _tower == null:
		return INF
	return _tower.global_position.distance_to(player().global_position)


func _observe_text(building: MapBuilding) -> String:
	match building.kind:
		&"school":
			return "学校的天文课讲过：太阳观测塔建在水星外层，用来记录水流的方向。水光蒸发之后，塔就停了。"
		&"power_plant":
			return "发电厂把地球所有的灯连成一体。灯亮起来的地方，你才看得见东西。"
		&"government":
			return "政府的地球电网在这里汇流。记录里写着：人类的算力中心在火星。"
		&"residence":
			return "居民楼的电脑亮着。它需要大量电能，似乎在等整张电网接通。"
		&"tower_perch":
			return "赤阳之塔的基座。塔本身点不亮，只能靠四周的灯把它照住。"
	return super._observe_text(building)
