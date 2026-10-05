extends Button
## 将此脚本挂在矩形 Button 上，即可让全局指针平滑框选它。
## 已有按钮脚本也可以直接加入 cursor_frame_target 分组。


func _enter_tree() -> void:
	add_to_group(&"cursor_frame_target")
