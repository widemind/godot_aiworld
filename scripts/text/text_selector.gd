class_name TextSelector
extends Resource

## 文本选择器，用于管理一个节点的所有文本。
## 暂定支持8种操作的对应文本。
## 默认按优先级从高到低选择文本。
## 可以覆写选择器以输出所需文本。

## 8种操作的对应文本
## 基本操作，四种
@export_group("Basic Action")
@export var text_when_observed:Array[TextPieces]
@export var text_when_observed_long:Array[TextPieces]
@export var text_when_detected:Array[TextPieces]
@export var text_when_detected_long:Array[TextPieces]
## 特殊操作，四种，包含操作名(StringName)与对应文本
@export_group("Special Action")
@export var action_1:StringName
@export var text_when_action_1:Array[TextPieces]
@export var action_2:StringName
@export var text_when_action_2:Array[TextPieces]
@export var action_3:StringName
@export var text_when_action_3:Array[TextPieces]
@export var action_4:StringName
@export var text_when_action_4:Array[TextPieces]

## 是否不使用普通选择器，改为true则不使用普通选择器。
var discard_basic_text_selection:bool = false

## 特殊选择器，实现自定义文本选择。
@warning_ignore("unused_parameter")
func special_text_selection(action:StringName) -> TextPieces:
	# 返回 null 才会继续使用基本选择器；最终未匹配时统一使用默认文本。
	return null

## 默认选择器，依据操作选择对应的列表，并按优先级选择文本。
## 可以覆写特殊选择器以改变选择方式。
## 如果需要建议覆写特殊选择器但使用普通选择器，提供null处理与信息列表推送
func text_selection(action:StringName) -> TextPieces:
	var text_pieces:TextPieces = null
	text_pieces = special_text_selection(action)
	if not discard_basic_text_selection and text_pieces == null:
		match action:
			"observe":
				text_pieces = list_text_selection(text_when_observed)
			"observe_long":
				text_pieces = list_text_selection(text_when_observed_long)
			"detect":
				text_pieces = list_text_selection(text_when_detected)
			"detect_long":
				text_pieces = list_text_selection(text_when_detected_long)
			action_1:
				text_pieces = list_text_selection(text_when_action_1)
			action_2:
				text_pieces = list_text_selection(text_when_action_2)
			action_3:
				text_pieces = list_text_selection(text_when_action_3)
			action_4:
				text_pieces = list_text_selection(text_when_action_4)
			_:
				push_error("Nonexistent action was passed into TextSelector")
	if text_pieces == null:
		text_pieces = TextDatabase.default_text_pieces
	TextDatabase.collect_text(text_pieces.duplicate(true))
	return text_pieces

## 列表内文本筛选器，按优先级选择文本
func list_text_selection(list:Array[TextPieces]) -> TextPieces:
	for pieces in list:
		if pieces == null or WorldTime.elapsed_seconds < pieces.time_requirements:
			continue
		if WorldState.meets_conditions(pieces.text_requirements):
			return pieces
	return null
