class_name ExplorationActionButton
extends Button
## 松开时结算一次。达到阈值为长按，移出按钮松开或暂停会取消。

signal action_requested(action_id: StringName, long_press: bool)

@export var action_id: StringName
@export_range(0.1, 3.0, 0.05) var long_press_seconds: float = 0.55

var _started_msec: int = -1
var _released_seconds: float = -1.0

@onready var hold_progress: ProgressBar = $HoldProgress


func _ready() -> void:
	hold_progress.hide()
	hold_progress.value = 0.0


func _process(_delta: float) -> void:
	if disabled and _started_msec >= 0:
		cancel_hold()
	if _started_msec >= 0:
		hold_progress.value = clampf(_held_seconds() / long_press_seconds, 0.0, 1.0) * hold_progress.max_value


func cancel_hold() -> void:
	_started_msec = -1
	_released_seconds = -1.0
	set_pressed_no_signal(false)
	hold_progress.hide()
	hold_progress.value = 0.0


func _begin_hold() -> void:
	_started_msec = Time.get_ticks_msec()
	_released_seconds = 0.0
	hold_progress.value = 0.0
	hold_progress.show()


func _end_hold() -> void:
	_released_seconds = _held_seconds() if _started_msec >= 0 else -1.0
	_started_msec = -1
	hold_progress.hide()


func _commit() -> void:
	# BaseButton 的 pressed 可以先于 button_up 发出，直接读取仍在进行的按压。
	var duration := _held_seconds() if _started_msec >= 0 else _released_seconds
	if duration < 0.0:
		return
	_started_msec = -1
	_released_seconds = -1.0
	hold_progress.hide()
	action_requested.emit(action_id, duration >= long_press_seconds)


func _held_seconds() -> float:
	return float(Time.get_ticks_msec() - _started_msec) / 1000.0
