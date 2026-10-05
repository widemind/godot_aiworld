extends Node

var default_text_pieces = preload("res://resources/text/default_text_pieces.tres")

var text_collection_list:Array[TextPieces] = []

## 收集文本信息，已按照文本去重
func collect_text(text_pieces:TextPieces) -> void:
	if text_pieces == null or not text_pieces.in_information_list \
			or text_pieces.text.strip_edges().is_empty():
		return
	for recorded_text in text_collection_list:
		# 选择器传入资源副本，须按正文比较才能对同一条文本去重。
		if text_pieces.text == recorded_text.text:
			return
	text_pieces.text_collection_id = len(text_collection_list) + 1
	text_pieces.text_collected_cycle_num = WorldTime.loop_index
	text_pieces.text_collected_time = WorldTime.elapsed_seconds
	text_collection_list.append(text_pieces)

## 获取收集到的信息，已按照从晚到早的顺序排好
func get_record_texts() -> Array[String]:
	var string_list:Array[String] = []
	for i in range(len(text_collection_list)-1, -1, -1):
		string_list.append(text_collection_list[i].text)
	return string_list
