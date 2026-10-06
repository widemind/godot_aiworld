extends Control


var time_speed:float = 1.0


func _on_time_speed_1x_pressed() -> void:
	self.time_speed = 1.0

func _on_time_speed_2x_pressed() -> void:
	self.time_speed = 2.0


func _on_time_speed_5x_pressed() -> void:
	self.time_speed = 5.0
