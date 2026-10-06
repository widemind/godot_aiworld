class_name MorseInput
extends RefCounted
## 摩斯电码输入：短按 = 点，长按 = 划，静默自动断字，等待键可手动分段。
##
## 纯逻辑，不依赖任何全局服务，便于 headless 测试。
## 时间由外部推入（通常来自 _process 的 delta），因此同一套逻辑可用于真实输入与回放。
##
## 不变量：
## - `_tokens` 只保存已敲定的标记，可能以字间隔（LETTER_GAP）结尾。
## - `_current_chunk` 保存当前正在输入、尚未断字的点划。
## - `effective_tokens()` 可重复调用且结果一致（UI 每帧轮询），不会重复附加当前段。

enum Token { DOT, DASH, LETTER_GAP }

const DOT: StringName = &"dot"
const DASH: StringName = &"dash"
const LETTER_GAP: StringName = &"gap"

## 短按上限：按住不超过该值算点
var dot_max_seconds: float = 0.22
## 静默多久自动断字（手动分隔符也可强制断字）
var letter_gap_seconds: float = 0.6
## 两次输入之间至少间隔这么久，避免同一次按下被重复计入
var repeat_guard_seconds: float = 0.04

var _tokens: Array[StringName] = []
var _current_chunk: Array[StringName] = []
var _pressed: bool = false
var _press_seconds: float = 0.0
var _silence_seconds: float = 0.0


## 开始一次按压（对应按钮 button_down）
func press() -> void:
	if _pressed:
		return
	_pressed = true
	_press_seconds = 0.0


## 结束一次按压（对应按钮 button_up）。返回本次产生的新标记，空数组表示被忽略。
func release() -> Array[StringName]:
	if not _pressed:
		return []
	_pressed = false
	_silence_seconds = 0.0
	# 同一帧内的重复按放不足以构成电码，直接丢弃。
	if _press_seconds < repeat_guard_seconds:
		_press_seconds = 0.0
		return []
	var token := DASH if _press_seconds > dot_max_seconds else DOT
	_press_seconds = 0.0
	_append(token)
	var created: Array[StringName] = []
	created.append(token)
	return created


## 手动分段（对应等待键）：把当前字切出来，即使静默时间还没到。
## 与静默断字产生完全相同的标记串，两条路径可互换。
func separator() -> bool:
	if _current_chunk.is_empty():
		return false
	_silence_seconds = 0.0
	_tokens.append_array(_current_chunk)
	_current_chunk.clear()
	_tokens.append(LETTER_GAP)
	return true


## 推进时间；静默超过阈值会自动断字
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	if _pressed:
		_press_seconds += delta
		return
	_silence_seconds += delta
	if not _current_chunk.is_empty() and _silence_seconds >= letter_gap_seconds:
		_flush_chunk()


## 已敲定的标记串（不含当前正在输入的段）
func tokens() -> Array[StringName]:
	return _tokens.duplicate()


## 已敲定标记 + 当前未断字段；可重复调用，结果一致
func effective_tokens() -> Array[StringName]:
	var result := _tokens.duplicate()
	if _current_chunk.is_empty():
		return result
	if not result.is_empty() and result[-1] != LETTER_GAP:
		result.append(LETTER_GAP)
	result.append_array(_current_chunk)
	return result


func is_empty() -> bool:
	return _tokens.is_empty() and _current_chunk.is_empty()


func has_open_chunk() -> bool:
	return not _current_chunk.is_empty()


## 当前正在输入、尚未断字的点划符号（如 ".-"）
func open_chunk_symbols() -> String:
	var text := ""
	for token in _current_chunk:
		text += "." if token == DOT else "-"
	return text


func clear() -> void:
	_tokens.clear()
	_current_chunk.clear()
	_pressed = false
	_press_seconds = 0.0
	_silence_seconds = 0.0


## 人类可读形式：· − 为点划，空格为字间隔
func display() -> String:
	var text := ""
	for token in effective_tokens():
		if token == DOT:
			text += "·"
		elif token == DASH:
			text += "−"
		else:
			text += " "
	return text.strip_edges()


## 把点划符号串（".-/.--" 等）转成标记串；"/" 表示字间隔。
## 测试与资源文本共用同一套解析，避免期望值与被测逻辑各写一遍。
static func symbols_to_tokens(symbols: String) -> Array[StringName]:
	var result: Array[StringName] = []
	for index in symbols.length():
		var symbol := symbols[index]
		if symbol == ".":
			result.append(DOT)
		elif symbol == "-":
			result.append(DASH)
		elif symbol == "/":
			result.append(LETTER_GAP)
	return result


func _append(token: StringName) -> void:
	_current_chunk.append(token)


func _flush_chunk() -> void:
	if _current_chunk.is_empty():
		return
	_tokens.append_array(_current_chunk)
	_current_chunk.clear()
	_tokens.append(LETTER_GAP)
