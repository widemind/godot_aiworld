extends CharacterBody2D
## 星图与各行星房间共用的玩家：WASD 移动，E 与场景交互。
##
## 位置逻辑之外的部分交给宿主（行星房间的 PlanetRoom 基类）处理，本脚本只负责
## 「能不能动」和「把交互请求转给宿主」。隐藏时视为不在场（例如星图在行星房间背后
## 仍然留在场景树里时，航道上的玩家不该继续响应输入）。

@export var speed: float = 520.0

@onready var _camera: Camera2D = get_node_or_null("Camera2D") as Camera2D


func _physics_process(_delta: float) -> void:
	if get_tree().paused or not visible:
		velocity = Vector2.ZERO
		return
	var direction := Input.get_vector(&"left", &"right", &"up", &"down")
	# 行星房间的相机是放大的，按视觉速度补偿，避免放大后显得过慢
	var zoom := 1.0
	if is_instance_valid(_camera) and _camera.zoom.x > 0.0:
		zoom = _camera.zoom.x
	velocity = direction * speed / zoom
	move_and_slide()
