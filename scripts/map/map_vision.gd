class_name MapVision
extends RefCounted
## 星图视野状态：基础视野 → 扫描扩大 → 点亮建筑提供固定视野。
##
## 设计稿原文（执行细节 / 基础细节）：
## - 玩家的交互范围等同于视野范围。
## - 扫描会让玩家短暂获得大于视野范围的区域的视野，浮现建筑，但扫描时间结束后
##   在视野范围内的建筑又会消失。
## - 地球建筑被点亮后，「在星球视图下建筑一定圆形范围内将持续获得视野」。
##
## 本类只做几何与状态判定，不碰节点显示，便于 headless 测试。

## 基础视野半径：玩家周围永远可见的范围
var base_radius: float = 420.0
## 扫描临时视野半径
var scan_radius: float = 1100.0
## 取景视野半径：观察文本与可交互范围使用的半径，等于当前生效的视野
var scan_remaining: float = 0.0

var _lit_buildings: Array[MapBuilding] = []


func set_base_radius(value: float) -> void:
	base_radius = maxf(value, 0.0)


func set_scan_radius(value: float) -> void:
	scan_radius = maxf(value, base_radius)


## 开始一次扫描：临时视野持续 seconds 秒
func begin_scan(seconds: float) -> void:
	scan_remaining = maxf(scan_remaining, seconds)


func tick(delta: float) -> void:
	if scan_remaining > 0.0:
		scan_remaining = maxf(0.0, scan_remaining - delta)


func is_scanning() -> bool:
	return scan_remaining > 0.0


## 当前生效的视野半径：扫描期间取更大值
func current_radius() -> float:
	return scan_radius if is_scanning() else base_radius


## 当前生效的视野是否覆盖某点
func covers_point(player_position: Vector2, point: Vector2) -> bool:
	return player_position.distance_to(point) <= current_radius()


## 基础视野是否覆盖某点（扫描结束后回落到这个判定）
func covers_in_base_vision(player_position: Vector2, point: Vector2) -> bool:
	return player_position.distance_to(point) <= base_radius


## 是否落在某个已点亮建筑提供的固定视野内
func covers_by_lit(player_position: Vector2, lit_buildings: Array[MapBuilding]) -> bool:
	for building in lit_buildings:
		if not is_instance_valid(building) or not building.lit:
			continue
		if player_position.distance_to(building.global_position) <= building.lit_vision_radius:
			return true
	return false


## 某点在当前视野下是否可达（交互与观察文本都用它）
func is_reachable(player_position: Vector2, point: Vector2, lit_buildings: Array[MapBuilding]) -> bool:
	if covers_point(player_position, point):
		return true
	return covers_by_lit(player_position, lit_buildings)


## 状态描述，供 HUD 显示
func label() -> String:
	if is_scanning():
		return "扫描中 %.1fs · 视野 %.0f" % [scan_remaining, current_radius()]
	return "基础视野 %.0f" % [base_radius]
