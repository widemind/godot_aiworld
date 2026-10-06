extends CanvasLayer
## 全局场景切换：旧场景截图按随机网格溶解，下方的新场景继续渲染。

signal transition_started(scene_path: String)
signal scene_revealed(scene_path: String)
signal transition_finished(scene_path: String)
signal transition_failed(scene_path: String, error: Error)

@export_range(0.0, 5.0, 0.05) var default_duration: float = 0.8
@export var custom_resolution: Vector2 = Vector2(160.0, 90.0)
## 截图时排除这些全局层；未来全局 HUD 也可加入此列表。
@export var capture_exclusions: Array[NodePath] = [NodePath("/root/GameCursor"), NodePath("/root/GlobalCRT")]

var is_transitioning: bool = false
var progress: float = 0.0
var _previous_input_disabled: bool = false
var _tween: Tween

@onready var _snapshot: TextureRect = $Snapshot
@onready var _material: ShaderMaterial = _snapshot.material as ShaderMaterial


## 必须从持久节点 await；当前场景会在调用期间释放。
## duration=0 为即时切换；负值使用默认时长。grid=ZERO 使用默认网格。
func change_scene_to_file(scene_path: String, duration: float = -1.0, grid: Vector2 = Vector2.ZERO) -> Error:
	if is_transitioning:
		return ERR_BUSY
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		transition_failed.emit(scene_path, ERR_FILE_NOT_FOUND)
		return ERR_FILE_NOT_FOUND
	var seconds := default_duration if duration < 0.0 else duration
	var cells := custom_resolution if grid == Vector2.ZERO else grid
	if not is_finite(seconds) or seconds < 0.0 or not cells.is_finite() or cells.x < 1.0 or cells.y < 1.0:
		transition_failed.emit(scene_path, ERR_INVALID_PARAMETER)
		return ERR_INVALID_PARAMETER
	_begin(scene_path)
	# 先异步加载，旧场景在加载过程中保持可见，避免读盘时空屏。
	var error := ResourceLoader.load_threaded_request(scene_path, "PackedScene")
	if error != OK:
		return _fail(scene_path, error)
	var status := ResourceLoader.load_threaded_get_status(scene_path)
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(scene_path)
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		return _fail(scene_path, ERR_CANT_OPEN)
	var next_scene := ResourceLoader.load_threaded_get(scene_path) as PackedScene
	if next_scene == null or not next_scene.can_instantiate():
		return _fail(scene_path, ERR_INVALID_DATA)
	# 从输入/物理回调进入时，先返回普通帧，避免在树锁定期间切换。
	await get_tree().process_frame
	if seconds > 0.0:
		var image := _capture_scene()
		if image == null or image.is_empty():
			return _fail(scene_path, ERR_CANT_CREATE)
		_snapshot.texture = ImageTexture.create_from_image(image)
		_material.set_shader_parameter(&"custom_resolution", cells.floor())
		_set_progress(0.0)
		_snapshot.show()
	error = get_tree().change_scene_to_packed(next_scene)
	if error != OK:
		return _fail(scene_path, error)
	await get_tree().scene_changed
	# ready 不等于已绘制：保持完整旧截图直到新场景的首帧真正完成。
	await RenderingServer.frame_post_draw
	scene_revealed.emit(scene_path)
	if seconds > 0.0:
		_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
		_tween.tween_method(_set_progress, 0.0, 1.0, seconds)
		await _tween.finished
	_cleanup()
	transition_finished.emit(scene_path)
	return OK


func _begin(scene_path: String) -> void:
	is_transitioning = true
	_previous_input_disabled = get_viewport().is_input_disabled()
	# 拦截整个视口，包括 _input、GUI、_unhandled_input 和暂停键。
	get_viewport().set_disable_input(true)
	transition_started.emit(scene_path)


func _capture_scene() -> Image:
	var hidden_nodes: Array[Node] = []
	for path in capture_exclusions:
		var node := get_node_or_null(path)
		if (node is CanvasLayer or node is CanvasItem) and node.visible:
			node.hide()
			hidden_nodes.append(node)
	# 不交换显示缓冲：临时关闭 CRT/光标后绘制一帧，只读回原始画面。
	# 整个过程同步完成，恢复后正常帧才显示到屏幕，不闪出无滤镜画面。
	RenderingServer.force_draw(false)
	var image := get_viewport().get_texture().get_image()
	for node in hidden_nodes:
		node.show()
	if image != null and get_viewport().use_hdr_2d:
		image.convert(Image.FORMAT_RGBA8)
		image.linear_to_srgb()
	return image


func _set_progress(value: float) -> void:
	progress = value
	_material.set_shader_parameter(&"progress", value)


func _cleanup() -> void:
	_snapshot.hide()
	_snapshot.texture = null
	_tween = null
	_set_progress(0.0)
	get_viewport().set_disable_input(_previous_input_disabled)
	is_transitioning = false


func _fail(scene_path: String, error: Error) -> Error:
	_cleanup()
	transition_failed.emit(scene_path, error)
	return error


func _exit_tree() -> void:
	if is_transitioning:
		if _tween != null and _tween.is_valid():
			_tween.kill()
		get_viewport().set_disable_input(_previous_input_disabled)
