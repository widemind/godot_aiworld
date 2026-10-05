extends Node
## 暂停输入必须持续处理，否则暂停后无法再用同一按键恢复。

signal pause_changed(paused: bool)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game") and not event.is_echo():
		set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()


func set_paused(value: bool) -> void:
	if get_tree().paused == value:
		return
	get_tree().paused = value
	pause_changed.emit(value)
