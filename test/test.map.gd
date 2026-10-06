extends Node2D


#能否扫描
@export var able_scan = true
#扫描半径
@export var max_radius := 2000
#扫描效果时间
@export var duration := 2
@export var ring_color := Color(1.0, 1.0, 1.0, 1.0)
@export var ring_thickness := 6   # 近似线宽
@export var segments := 64

@onready var ring: Polygon2D = $player/Camera2D/ring
@onready var arrow: Node2D = $player/arrow



#场上存在行星
@onready var planets: Node2D = $planets


# 生成一个半径=1的圆环多边形（内外双圈），后面靠scale放大
func _ready() -> void:
	ring.polygon = _ring_polygon(1.0, ring_thickness)
	ring.color = ring_color
	ring.visible = false
	


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
func scan_once(target: Array = []) -> void:
	if able_scan:
		able_scan = false
		ring.visible = true
		ring.scale = Vector2.ZERO
		ring.modulate = Color(1, 1, 1, 1)
		var t := create_tween()
		t.tween_property(ring, "scale", Vector2(max_radius, max_radius), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(ring, "modulate:a", 0.0, duration)
		t.tween_callback(func(): self.able_scan = true)
		if target != []:
			point_arrow(target)

# 箭头指向目标，并停在“当前半径比例”处；不传则指向不动
func point_arrow(target: Array, radius_factor := 100) -> void:
	await get_tree().create_timer(0.3).timeout
	_make_triangle(target,radius_factor)


# Arrow 脚本，或写在 Scanner 里初始化
func _make_triangle(target: Array, radius_factor := 1.0) -> void:
	for i in target:
		var dir = i.global_position - ring.global_position
		if dir.length() < 0.001:
			return
		var poly := Polygon2D.new()
		# 尖朝右(+X)，底在左；单位尺寸，后面用scale调大小
		poly.polygon = PackedVector2Array([
			Vector2(20, 0),    # 箭尖
			Vector2(-10, 12),
			Vector2(-10, -12),
		])
		poly.color = Color(1.0, 1.0, 1.0, 1.0)
		poly.look_at(global_position + dir)   # Node2D.look_at 用全局点 [17](@ref)
		poly.global_position = global_position + dir.normalized()  * radius_factor
		arrow.add_child(poly)
		
		var t := create_tween()
		t.tween_property(poly,"color",Color(1.0, 1.0, 1.0, 0.0),1.7)

func _on_scan_pressed() -> void:
	scan_once(planets.get_children())
	await get_tree().create_timer(2.5).timeout
	for i in arrow.get_children():
		i.queue_free()


func _on_inter_body_entered(body: Node2D, planet_name: String) -> void:
	match planet_name:
		"sun":
			pass
		"water_planet":
			pass
		"fire_planet":
			pass
		"earth":
			pass
