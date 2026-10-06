class_name SunTower
extends Node2D
## 赤阳之塔：只在被观察时存在，并朝玩家视野的指向移动。
##
## 设计稿原文（执行细节 / 解谜细节）：
## - 「赤阳之塔会与玩家保持扫描范围内，视野范围外的距离」
## - 「赤阳之塔被视野照射到会停止移动」
## - 「玩家朝赤阳之塔移动且赤阳之塔距离内时，朝玩家移动；如果移出星球圆形范围则消失，
##    直到重进场景再次出现」
## - 「进入赤阳之塔的方法是把赤阳之塔框进点亮的建筑范围内」（实际上塔不会进入被点亮的
##    区域，所以需要玩家在塔被照停的瞬间完成发送）
##
## 实现把「消失」做成可观察状态：塔一旦离开玩家当前视野就隐藏，
## 再次进入视野时重新出现（对应「直到重进场景再次出现」）。

signal appeared
signal vanished
signal stopped_in_lit(building: MapBuilding)
signal entered_range

## 只有被观察到才会移动
@export var move_speed: float = 90.0
## 与玩家的期望距离：塔会保持在这个距离附近
@export var preferred_distance: float = 700.0
## 被视野照射而停止移动的判定半径（小于玩家视野半径，玩家看得到这个「照停」状态）
@export var stop_light_radius: float = 260.0
## 重新出现时相对玩家的最小距离
@export var respawn_distance: float = 900.0

var is_appeared: bool = false
## 是否处于被照射而停止移动的状态
var is_stopped: bool = false

var _player: Node2D
var _lit_buildings: Array[MapBuilding] = []
var _map_bounds: float = 2600.0
var _state_before_stop: bool = false


func setup(player: Node2D, map_bounds: float) -> void:
	_player = player
	_map_bounds = maxf(map_bounds, 100.0)


func set_lit_buildings(buildings: Array[MapBuilding]) -> void:
	_lit_buildings = buildings


## 塔当前是否处于被观察状态（由星图按当前视野半径判定）
func is_observed(visible_radius: float) -> bool:
	if _player == null:
		return false
	return is_appeared and global_position.distance_to(_player.global_position) <= visible_radius


## 推进一帧。visible_radius 由星图给出，使塔的规则与扫描机制联动。
func tick(delta: float, visible_radius: float) -> void:
	if _player == null:
		return
	var distance := global_position.distance_to(_player.global_position)
	var observed := distance <= visible_radius
	if not observed:
		if is_appeared:
			_disappear()
		return
	if not is_appeared:
		_appear()
	# 被点亮的建筑照到就停止移动：这是「把赤阳之塔框进点亮建筑范围」的可操作窗口
	var lit_hit := _find_lit_touch()
	if lit_hit != null:
		if not is_stopped:
			is_stopped = true
			stopped_in_lit.emit(lit_hit)
		return
	if is_stopped:
		is_stopped = false
	if distance < preferred_distance or distance > preferred_distance * 1.6:
		_drift_toward_player(delta, distance)


## 玩家是否已在塔的交互范围内（可发送电码）
func in_interaction_range(interaction_radius: float) -> bool:
	if _player == null:
		return false
	return is_appeared and global_position.distance_to(_player.global_position) <= interaction_radius


## 三段太阳语料的标记键：集齐后塔内才会开启，玩家可以进去把它们打出来
const FRAGMENT_FLAGS: Array[StringName] = [
	&"sun_fragment_0", &"sun_fragment_1", &"sun_fragment_2",
]


## 塔内是否已开启：设计稿要求先把三段语料集齐，塔才让进
func room_ready(flags: Dictionary) -> bool:
	for flag in FRAGMENT_FLAGS:
		if not bool(flags.get(flag, false)):
			return false
	return true


func distance_to_player() -> float:
	if _player == null:
		return INF
	return global_position.distance_to(_player.global_position)


## 塔在星球圆形范围之外就消失，等玩家重进场景再出现
func _drift_toward_player(delta: float, distance: float) -> void:
	if distance <= 0.001:
		return
	var direction := (_player.global_position - global_position) / distance
	# 远处追近，太近则退开，从而围绕 preferred_distance 保持距离
	var step := move_speed * delta
	if distance > preferred_distance:
		global_position += direction * step
	else:
		global_position -= direction * step
	if global_position.length() > _map_bounds:
		_disappear()


func _find_lit_touch() -> MapBuilding:
	for building in _lit_buildings:
		if not is_instance_valid(building) or not building.lit:
			continue
		if global_position.distance_to(building.global_position) <= stop_light_radius:
			return building
	return null


func _appear() -> void:
	is_appeared = true
	show()
	appeared.emit()


func _disappear() -> void:
	is_appeared = false
	is_stopped = false
	hide()
	vanished.emit()
