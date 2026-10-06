extends StaticBody2D
## 星图上的阻挡物：火星地表的障碍，形成迷宫与洞穴。
##
## 设计稿对应（执行细节 / 火星）：
## - 「1 层、2 层分布有阻挡移动的障碍，形成迷宫与洞穴」
## - 「火星上切换层级只能通过分布在地图上的洞口，不像水星一样能自由切换层级」
##
## 因此障碍只需要挡住玩家，不使用碰撞伤害；洞口位置（`mars_hole` 分组）才是通关点。
## 碰撞形状由场景里的 CollisionShape2D 提供，本脚本只负责按层显隐。

## 该障碍属于哪一层；留空表示所有层都生效
@export var layer: StringName = &""
## 是否参与碰撞（调试时可以临时关闭）
@export var blocking: bool = true

@onready var _shape: CollisionShape2D = get_node_or_null("CollisionShape2D")
@onready var _visual: Polygon2D = get_node_or_null("Visual")


func _ready() -> void:
	add_to_group(&"map_obstacle")
	_refresh()


## 只显示当前层的障碍；层为空表示常驻
func set_layer_active(active_layer: StringName) -> void:
	var active := layer == &"" or layer == active_layer
	visible = active
	if _shape != null:
		# 隐藏的障碍不参与碰撞，避免玩家撞到看不见的墙
		_shape.disabled = not (active and blocking)
	if _visual != null:
		_visual.visible = active
	process_mode = Node.PROCESS_MODE_INHERIT


func is_blocking_now() -> bool:
	return visible and blocking and (_shape == null or not _shape.disabled)


func _refresh() -> void:
	if _shape != null:
		_shape.disabled = not blocking
