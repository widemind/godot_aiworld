extends Control
## 赤阳之塔内部：用已获得的太阳语料逐段打出电码，解锁塔的知识。
##
## 设计稿对应（知识地图 / 赤阳之塔分支）：
## - 「进入赤阳之塔的方法是把赤阳之塔框进点亮的建筑范围内」——塔不会进入被点亮区域，
##   所以真正的门槛是「先集齐三段太阳语料」，进入后在这里把它们打出来。
## - 「在赤阳之塔内打出（累积）三个太阳语料摩斯电码后，触发事件，玩家知晓终极太阳语的摩斯电码」。
## - 「太阳观测塔的位置和建造原因」——由前两次成功发送逐步给出。
##
## 因此本场景只是「发送台」：真正的判定仍走 SunLanguage.verify()，
## 与星图上发送用的是同一套码表，不会出现两套规则。

signal closed
## 每成功发送一段语料后发出，携带已完成的段数
signal progress_changed(completed: int)

const FRAGMENT_ORDER: Array[StringName] = [&"death_clear", &"awaken", &"doubt"]

@onready var _title: Label = %TowerTitle
@onready var _status: Label = %TowerStatus
@onready var _display: Label = %TowerDisplay
@onready var _log: Label = %TowerLog
@onready var _morse_button: Button = %TowerMorseButton
@onready var _wait_button: Button = %TowerWaitButton
@onready var _send_button: Button = %TowerSendButton
@onready var _clear_button: Button = %TowerClearButton
@onready var _leave_button: Button = %TowerLeaveButton

var morse := MorseInput.new()
## 已经在塔内成功打出的语料序号
var _completed: Array[int] = []
## 由星图注入：当前已获得的知识
var _known: Dictionary = {}


func _ready() -> void:
	hide()
	_morse_button.button_down.connect(_on_press)
	_morse_button.button_up.connect(_on_release)
	_wait_button.pressed.connect(_on_separator)
	_send_button.pressed.connect(func() -> void: send())
	_clear_button.pressed.connect(_on_clear)
	_leave_button.pressed.connect(close)


func _process(delta: float) -> void:
	if not visible:
		return
	morse.tick(delta)
	_refresh_display()


## 每段语料对应的知识：打出第一段给出塔的位置，第二段给出建造原因。
func static_knowledge_for(fragment_index: int) -> StringName:
	match fragment_index:
		0:
			return &"tower_location"
		1:
			return &"tower_build_reason"
	return &""


## 三段语料的标记键：与星图 `sun_fragment_<n>` 一一对应
const FRAGMENT_FLAGS: Array[StringName] = [
	&"sun_fragment_0", &"sun_fragment_1", &"sun_fragment_2",
]


## 是否可以进入塔内：需要已经集齐三段语料
static func room_ready(flags: Dictionary) -> bool:
	for flag in FRAGMENT_FLAGS:
		if not bool(flags.get(flag, false)):
			return false
	return true


## 打开塔内界面；known 是当前已获得的知识快照
func open(known: Dictionary) -> void:
	_known = known.duplicate()
	morse.clear()
	_title.text = "赤阳之塔 · 内部"
	_completed.clear()
	if not visible:
		_log.text = "塔内的石壁上刻着三段太阳语。把它们按顺序打出来。"
	show()
	_refresh_display()


func close() -> void:
	if not visible:
		return
	morse.clear()
	hide()
	closed.emit()


## 还需要打出的语料（供星图与测试查询）
func pending_fragments() -> Array[StringName]:
	var result: Array[StringName] = []
	for index in FRAGMENT_ORDER.size():
		if not _completed.has(index):
			result.append(FRAGMENT_ORDER[index])
	return result


func completed_count() -> int:
	return _completed.size()


## 塔内是否已完成三段（知晓终极太阳语）
func is_complete() -> bool:
	return _completed.size() >= FRAGMENT_ORDER.size()


func _on_press() -> void:
	morse.press()
	_refresh_display()


func _on_release() -> void:
	morse.release()
	_refresh_display()


func _on_separator() -> void:
	if morse.separator():
		_refresh_display()


func _on_clear() -> void:
	morse.clear()
	_log.text = "清空输入。"
	_refresh_display()


## 发送当前输入；成功则记录一段语料并给出对应知识
func send() -> Dictionary:
	var tokens := morse.effective_tokens()
	if tokens.is_empty():
		_log.text = "还没有输入任何电码。"
		return {"result": SunLanguage.Result.EMPTY, "fragment": -1}
	var known := _known.duplicate()
	# 塔内不限制场景：这里就是发送台，只校验是否已经学会
	for word in SunLanguage.WORDS:
		var key := SunLanguage.word_knowledge_key(word)
		if not key.is_empty():
			known[key] = true
	var outcome := SunLanguage.verify(tokens, &"sun_outer", known)
	var result := int(outcome["result"])
	var fragment := int(outcome["fragment"])
	if result != SunLanguage.Result.SUCCESS:
		_log.text = "石壁没有反应。（%s）" % [SunLanguage.result_label(result)]
		return outcome
	# 只接受三段语料，不接受终极太阳语（那是解锁后的下一步）
	if fragment < 0:
		_log.text = "终极太阳语已经不需要在这里打出了。"
		return outcome
	if _completed.has(fragment):
		_log.text = "「%s」已经打过了。" % [SunLanguage.word_text(StringName(outcome["word"]))]
		return outcome
	_completed.append(fragment)
	_completed.sort()
	morse.clear()
	var granted := static_knowledge_for(fragment)
	var lines: PackedStringArray = []
	lines.append("石壁亮起：「%s」。" % [SunLanguage.word_text(StringName(outcome["word"]))])
	if granted != &"":
		lines.append(_knowledge_text(granted))
	if is_complete():
		lines.append("三段语料连成一句。你知晓了终极太阳语的摩斯电码：%s" % [
			SunLanguage.word_hint(SunLanguage.ULTIMATE_WORD)])
	_log.text = "\n".join(lines)
	progress_changed.emit(_completed.size())
	_refresh_display()
	return outcome


func _knowledge_text(key: StringName) -> String:
	match key:
		&"tower_location":
			return "获得知识：太阳观测塔建在水星第 1 层的外层水流旁，位置由水流方向决定。"
		&"tower_build_reason":
			return "获得知识：观测塔的用途是把太阳语译成汉字——它是人类听懂太阳的第一只耳朵。"
	return "获得知识：%s" % [key]


func _refresh_display() -> void:
	_display.text = "输入：" + (morse.display() if not morse.is_empty() else "—")
	var pending := pending_fragments()
	if is_complete():
		_status.text = "三段语料已全部打出（3 / 3）"
		return
	var next_hint := ""
	if not pending.is_empty():
		next_hint = "　下一段提示：" + SunLanguage.word_hint(pending[0])
	_status.text = "已完成 %d / %d 段%s" % [_completed.size(), FRAGMENT_ORDER.size(), next_hint]
