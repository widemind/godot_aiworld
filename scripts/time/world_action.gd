class_name WorldAction
extends Resource
## 地点和关卡可用 .tres 配置行动，无需自行维护计时器。

@export var action_id: StringName
@export var display_name: String = ""
## 瞬时结算时是额外耗时；持续执行时是从开始到完成的世界时长。
@export_range(0.0, 36000.0, 0.1) var duration_seconds: float = 0.0
@export var start_conditions: Dictionary = {}
@export var during_conditions: Dictionary = {}
@export var finish_conditions: Dictionary = {}
@export var result_changes: Dictionary = {}
## 空字符串表示不改变玩家位置。
@export var destination: StringName
