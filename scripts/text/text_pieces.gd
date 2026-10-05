class_name TextPieces
extends Resource

## 文本片段，用于存储文本、筛选条件与是否作为信息录入信息列表。

## 要展示的文本。
@export_multiline var text:String

## 是否作为信息录入信息列表。
@export var in_information_list:bool

## 时间(秒)筛选条件，在该时间后通过。
@export var time_requirements:float

## 非时间筛选条件，满足所有要求才通过。无要求则保持通过。
## 要求键为StringName, 值为时间轴上条件。
@export var text_requirements:Dictionary

## 该条文本的注释
@export_group("Annotation")
@export_multiline var annotation:String

## 文本收集顺序
var text_collection_id:int

## 收集到文本时的循环数和时间(秒)
var text_collected_cycle_num:int
var text_collected_time:float
