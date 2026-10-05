@tool
class_name StarfieldBackground
extends Node2D
## 静态星空背景。原点位于左上角，实例化场景后在检查器中调整参数。
## 两张噪声纹理分别控制空间密度和星星的大小、亮度，没有逐帧动画。

const DENSITY_AREA := 10000.0
const MAX_CANDIDATES := 100000

@export_group("背景区域")
## 背景矩形的宽高，单位为像素。
@export var field_size := Vector2(1920.0, 1080.0):
	set(value):
		field_size = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
		_request_rebuild()
@export var background_color := Color("060b19"):
	set(value):
		background_color = value
		queue_redraw()
## 相同的种子和参数产生相同的星空。
@export var star_seed := 9021:
	set(value):
		star_seed = value
		_request_rebuild()

@export_group("分布")
## 密度范围：每 100×100 像素的期望星星数量。X 为最低，Y 为最高。
## 分布纹理的黑色对应最低密度，白色对应最高密度。
@export var density_range := Vector2(0.5, 12.0):
	set(value):
		density_range = _ordered_range(value, 0.0)
		_request_rebuild()
## 映射到整个背景区域。展开 Noise 可修改噪声种子、频率与分形参数。
@export var distribution_noise: NoiseTexture2D = _make_noise_texture(137, 0.008):
	set(value):
		_disconnect_texture(distribution_noise, _on_distribution_changed)
		distribution_noise = value
		_connect_texture(distribution_noise, _on_distribution_changed)
		_request_rebuild()

@export_group("大小与亮度")
## 第二张纹理的黑色对应最小、最暗，白色对应最大、最亮。
@export var appearance_noise: NoiseTexture2D = _make_noise_texture(829, 0.06):
	set(value):
		_disconnect_texture(appearance_noise, _on_appearance_changed)
		appearance_noise = value
		_connect_texture(appearance_noise, _on_appearance_changed)
		_request_rebuild()
## 星星半径范围，单位为像素。X 为最小，Y 为最大。
@export var radius_range := Vector2(0.45, 1.8):
	set(value):
		radius_range = _ordered_range(value, 0.0)
		_request_rebuild()
## 亮度乘数范围，0 为黑色，1 为原色，也支持大于 1 的 HDR 值。
@export var brightness_range := Vector2(0.25, 1.0):
	set(value):
		brightness_range = _ordered_range(value, 0.0)
		_request_rebuild()

@export_group("颜色范围")
## 在这两个端点颜色之间为每颗星星选择固定颜色，可调透明度。
@export var color_from := Color("a9c9ff"):
	set(value):
		color_from = value
		_request_rebuild()
@export var color_to := Color("fff0cd"):
	set(value):
		color_to = value
		_request_rebuild()

var _positions := PackedVector2Array()
var _radii := PackedFloat32Array()
var _colors := PackedColorArray()
var _rebuild_queued := false


func _ready() -> void:
	_connect_texture(distribution_noise, _on_distribution_changed)
	_connect_texture(appearance_noise, _on_appearance_changed)
	_request_rebuild()


func _request_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	_positions.clear()
	_radii.clear()
	_colors.clear()
	# NoiseTexture2D 在后台生成图像，完成后的 changed 信号会再次调用这里。
	var distribution_image: Image = distribution_noise.get_image() if distribution_noise else null
	var appearance_image: Image = appearance_noise.get_image() if appearance_noise else null
	if (distribution_noise and distribution_image == null) or (appearance_noise and appearance_image == null):
		queue_redraw()
		return
	var area := field_size.x * field_size.y
	var expected_candidates := area * density_range.y / DENSITY_AREA
	var candidate_count := mini(ceili(expected_candidates), MAX_CANDIDATES)
	if candidate_count > 0:
		# 均匀候选点再按分布噪声筛选，避免可见的规则网格。
		# 使用实际候选密度进行归一化，让小面积区域同样遵循密度范围。
		var candidate_density := float(candidate_count) * DENSITY_AREA / area
		var rng := RandomNumberGenerator.new()
		rng.seed = star_seed
		for index in range(candidate_count):
			var uv := Vector2(rng.randf(), rng.randf())
			var acceptance := rng.randf()
			var color_mix := rng.randf()
			var local_density := lerpf(density_range.x, density_range.y, _sample_noise(distribution_image, uv))
			if acceptance >= local_density / candidate_density:
				continue
			var appearance := _sample_noise(appearance_image, uv)
			var radius := lerpf(radius_range.x, radius_range.y, appearance)
			if radius <= 0.0:
				continue
			var brightness := lerpf(brightness_range.x, brightness_range.y, appearance)
			var tint := color_from.lerp(color_to, color_mix)
			_positions.append(uv * field_size)
			_radii.append(radius)
			_colors.append(Color(tint.r * brightness, tint.g * brightness, tint.b * brightness, tint.a))
	queue_redraw()
	update_configuration_warnings()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, field_size), background_color)
	for index in range(_positions.size()):
		# 裁剪边缘圆点，星星不会越过指定的背景区域。
		var p := _positions[index]
		var radius := _radii[index]
		if p.x < radius or p.y < radius or p.x > field_size.x - radius or p.y > field_size.y - radius:
			continue
		draw_circle(p, radius, _colors[index], true, -1.0, true)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if distribution_noise == null:
		warnings.append("未设置分布噪声纹理，将使用密度范围的中间值。")
	if appearance_noise == null:
		warnings.append("未设置大小与亮度噪声纹理，将使用范围的中间值。")
	if field_size.x * field_size.y * density_range.y / DENSITY_AREA > MAX_CANDIDATES:
		warnings.append("候选星星超过 100000，已限制生成数量。请减小区域或最高密度。")
	return warnings


static func _sample_noise(noise_image: Image, uv: Vector2) -> float:
	if noise_image == null or noise_image.is_empty():
		return 0.5
	var x := mini(int(uv.x * noise_image.get_width()), noise_image.get_width() - 1)
	var y := mini(int(uv.y * noise_image.get_height()), noise_image.get_height() - 1)
	return clampf(noise_image.get_pixel(x, y).r, 0.0, 1.0)


static func _ordered_range(value: Vector2, lower_bound: float) -> Vector2:
	return Vector2(maxf(minf(value.x, value.y), lower_bound), maxf(maxf(value.x, value.y), lower_bound))


static func _make_noise_texture(noise_seed: int, frequency: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = frequency
	var texture := NoiseTexture2D.new()
	texture.width = 512
	texture.height = 512
	texture.noise = noise
	return texture


func _connect_texture(texture: NoiseTexture2D, callback: Callable) -> void:
	if texture and not texture.changed.is_connected(callback):
		texture.changed.connect(callback)


func _disconnect_texture(texture: NoiseTexture2D, callback: Callable) -> void:
	if texture and texture.changed.is_connected(callback):
		texture.changed.disconnect(callback)


func _on_distribution_changed() -> void:
	_request_rebuild()


func _on_appearance_changed() -> void:
	_request_rebuild()
