extends CharacterBody2D

@export var speed: float = 250.0          # 移动速度（像素/秒）
@onready var time_control: Control = $Camera2D/time_control

func _physics_process(delta: float) -> void:
	# 获取四方向输入（WASD / 方向键）
	var direction := Input.get_vector("left", "right", "up", "down")
	# 应用速度
	velocity = direction * speed * time_control.time_speed
	# 执行移动并检测碰撞
	move_and_slide()
