extends Node2D

@export var max_radius := 220.0
@export var duration := 0.8
@export var ring_color := Color(0.2, 0.9, 1.0, 1.0)
@export var ring_thickness := 6.0   # 近似线宽
@export var segments := 64

@onready var ring: Polygon2D = $"."
@onready var arrow: Node2D = $Arrow

# 生成一个半径=1的圆环多边形（内外双圈），后面靠scale放大
func _ready() -> void:
	ring.polygon = _ring_polygon(1.0, ring_thickness)
	ring.color = ring_color
	ring.visible = false
	
	scan_once()

func _ring_polygon(r: float, thickness: float) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	var inner := maxf(r - thickness / r, 0.0)  # 近似内半径
	# 用内外两个圆交替生成环形带
	for i in range(segments):
		var a1 = TAU * i / segments
		var a2 = TAU * (i + 1) / segments
		pts.append(Vector2(cos(a1), sin(a1)) * r)
		pts.append(Vector2(cos(a2), sin(a2)) * r)
		pts.append(Vector2(cos(a2), sin(a2)) * inner)
		pts.append(Vector2(cos(a1), sin(a1)) * inner)
	return pts

# 触发一次扫描
func scan_once(target: Node2D = null) -> void:
	ring.visible = true
	ring.scale = Vector2.ZERO
	ring.modulate = Color(1, 1, 1, 1)
	var t := create_tween()
	t.tween_property(ring, "scale", Vector2(max_radius, max_radius), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(ring, "modulate:a", 0.0, duration)
	t.tween_callback(func(): ring.visible = false)
	if target != null:
		point_arrow(target)

# 箭头指向目标，并停在“当前半径比例”处；不传则指向不动
func point_arrow(target: Node2D, radius_factor := 1.0) -> void:
	var dir := target.global_position - global_position
	if dir.length() < 0.001:
		return
	arrow.look_at(global_position + dir)   # Node2D.look_at 用全局点 [17](@ref)
	arrow.global_position = global_position + dir.normalized() * max_radius * radius_factor
