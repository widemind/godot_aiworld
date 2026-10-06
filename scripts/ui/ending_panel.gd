extends Control
## 结局界面：玩家向太阳送出终极太阳语后进入太阳内层。
##
## 设计稿对应（故事流程）：
## - 「在解除模拟后向太阳发送终极太阳语对应的摩斯电码，再深入太阳内层，即通关达成结局」
## - 「离开模拟世界，进入现实」——是否解除模拟由 `mercury_is_simulation` 知识决定，
##   因此结局文本分两种：知道真相与还不知道真相。

signal closed

@onready var _title: Label = %EndingTitle
@onready var _body: Label = %EndingBody
@onready var _close_button: Button = %EndingClose


func _ready() -> void:
	hide()
	_close_button.pressed.connect(close)


## 根据是否已知「这是模拟」给出不同结局文本
static func ending_text(known: Dictionary) -> Dictionary:
	var title := "结局 · 深入太阳内层"
	if bool(known.get(&"mercury_is_simulation", false)):
		var body := "你把终极太阳语送了出去。\n\n"
		body += "模拟在身后一层层剥落——水星的水、火星的机房、地球的灯，都只是算出来的形状。\n\n"
		body += "你终于知道自己一直在两个世界里。太阳不是在等你回答，它是在等你出来。\n\n"
		body += "赤阳之心在你前方展开，你走了进去。"
		return {"title": title, "body": body}
	var unknown_body := "你把终极太阳语送了出去。\n\n"
	unknown_body += "太阳的内层向你打开。你说不清那句话到底是什么意思，"
	unknown_body += "但塔上的刻痕、水流的方向和玛斯的警告，此刻都指向同一个答案。\n\n"
	unknown_body += "赤阳之心在你前方展开，你走了进去。"
	return {"title": title, "body": unknown_body}


func open(known: Dictionary) -> void:
	var text := ending_text(known)
	_title.text = String(text["title"])
	_body.text = String(text["body"])
	show()


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()
