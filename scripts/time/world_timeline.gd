class_name WorldTimeline
extends Resource
## 将单轮长度、初始世界和事件表放在一起，供关卡在检查器中配置。

@export_range(1.0, 36000.0, 1.0) var loop_duration: float = 600.0
@export var initial_location: StringName = &"harbor"
@export var initial_flags: Dictionary = {}
@export var events: Array[WorldTimeEvent] = []


func install() -> bool:
	if not WorldTime.configure(loop_duration, events):
		return false
	return WorldState.configure_initial(initial_flags, initial_location)
