class_name ExplorationResponse
extends Resource
## 地点 × 操作 × 长/短按 × 世界条件对应的文本与耗时。

@export var location_id: StringName
@export_enum("observe", "probe", "wait") var action_id: String = "observe"
@export var long_press: bool = false
@export var conditions: Dictionary = {}
@export_range(0.0, 600.0, 1.0) var duration_seconds: float = 0.0
@export_multiline var text: String = ""


func matches(location: StringName, action: StringName, held: bool) -> bool:
	return location_id == location and StringName(action_id) == action \
		and long_press == held and WorldState.meets_conditions(conditions)
