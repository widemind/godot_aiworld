class_name MapBuilding
extends Area2D
## 星图上的建筑。可被扫描显形、可被点亮提供固定视野、可挂发电机。
##
## 设计稿要求：
## - 「观察出现的文本与当前所在层和星图中的位置有关」→ 通过 `kind` / `layer` 区分。
## - 「扫描会让玩家短暂获得大于视野范围的区域的视野，浮现建筑，但扫描时间结束后
##    在视野范围内的建筑又会消失」→ 用「基础视野」与「点亮视野」两个半径共同判定。
## - 「每个建筑中（除赤阳之塔）中有一个发电机，与发电机交互后（点击按钮）当前建筑
##    会被点亮，在星球视图下建筑一定圆形范围内将持续获得视野」→ `generator_ready` 与点亮视野。

signal clicked(building: MapBuilding)
signal generator_activated(building: MapBuilding)

const KIND_LABEL: Dictionary = {
	&"tower_perch": "太阳观测塔",
	&"school": "学校",
	&"generator": "发电机",
	&"residence": "居民楼",
	&"government": "政府",
	&"observatory": "天文台",
	&"language_lab": "语言研究所",
	&"computing_center": "算力中心",
	&"power_plant": "发电厂",
	&"manufactory": "制造厂",
	&"core": "行星核心",
}

@export var building_id: StringName = &""
## 建筑类型，决定交互文本与可提供的知识
@export var kind: StringName = &"residence"
## 该建筑属于哪一层；切换层级时只显示该层建筑
@export var layer: StringName = &"1"
## 与发电机交互后是否有用（赤阳之塔除外）；无发电机的建筑不可点亮
@export var has_generator: bool = true
## 是否已经被点亮
@export var lit: bool = false
## 点亮后提供的固定视野半径
@export var lit_vision_radius: float = 320.0
## 基础视野下是否可见；false 表示只有扫描才会显形（隐藏建筑）
@export var visible_in_base_vision: bool = true

@onready var _shape: CollisionShape2D = get_node_or_null("CollisionShape2D")
@onready var _label: Label = get_node_or_null("Label")

var _revealed_by_scan: bool = false


func _ready() -> void:
	# 星图与行星房间都靠这个分组发现建筑，漏掉它就等于所有建筑都不可见、不可交互
	add_to_group(&"map_building")
	input_pickable = true
	input_event.connect(_on_input_event)
	if _label != null and _label.text.strip_edges().is_empty():
		_label.text = display_name()
	_refresh_visual()


## 玩家可见名字，用于文本框与知识地图
func display_name() -> String:
	if KIND_LABEL.has(kind):
		return String(KIND_LABEL[kind])
	return "未知建筑：" + String(kind)


## 当前是否处于「本次扫描的临时视野」中
func is_revealed_by_scan() -> bool:
	return _revealed_by_scan


## 扫描到达时调用；返回是否因此新显形
func reveal_by_scan() -> bool:
	if _revealed_by_scan:
		return false
	_revealed_by_scan = true
	_refresh_visual()
	return true


## 扫描结束后收回临时显形；已点亮的建筑仍然可见
func clear_scan_reveal() -> void:
	if not _revealed_by_scan:
		return
	_revealed_by_scan = false
	_refresh_visual()


## 该建筑当前应该可见吗？点亮 或 被扫描显形 或 基础视野可达。
## 注意：`visible_in_base_vision` 只决定「基础视野是否算作可达」，不能单独让它可见，
## 否则隐藏建筑会在扫描结束后仍然显示。
func is_visible_to(reachable: bool) -> bool:
	if lit or _revealed_by_scan:
		return true
	return reachable and visible_in_base_vision


## 点亮本建筑；返回是否发生了变化
func light_up() -> bool:
	if lit or not has_generator:
		return false
	lit = true
	generator_activated.emit(self)
	_refresh_visual()
	return true


## 重新按可见性刷新显示与拾取；不可见时不可点击，避免隔空交互
func _refresh_visual() -> void:
	var show_now := lit or _revealed_by_scan or visible_in_base_vision
	if _label != null:
		_label.visible = show_now
		_label.text = display_name() + ("（已点亮）" if lit else "")
	if _shape != null:
		# 隐藏建筑在未显形前不参与点击，防止玩家点到看不见的东西
		_shape.disabled = not show_now
	input_pickable = show_now


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			clicked.emit(self)
			get_viewport().set_input_as_handled()
