class_name WorldTimeEvent
extends Resource
## 一个世界时间事件。资源只保存配置，每轮的触发记录由 WorldTime 保存。

@export var event_id: StringName
@export_range(0.0, 36000.0, 0.1) var at_seconds: float = 0.0
## 同一时刻先处理较小优先级；相同优先级按注册顺序执行。
@export var priority: int = 0
@export var changes: Dictionary = {}
## 行动完成后结束本次推进，让剩余帧时间按恢复后的倍率计算。
@export var stop_advancement: bool = false
