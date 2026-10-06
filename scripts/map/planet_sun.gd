extends PlanetRoom
## 太阳外层：发送终极太阳语的地方。
##
## 设计稿对应（故事流程 / 执行细节）：
## - 「在星图中移动至太阳上时或位于太阳外层时（以程序执行哪种更方便为选择依据），
##    按顺序长按、电脑扫描键即为向太阳发送摩斯电码」。
## - 「在太阳上打错误的摩斯电码或模拟的时候打摩斯电码，太阳会返回太阳语料 3」。
## - 「在解除模拟后向太阳发送终极太阳语对应的摩斯电码，再深入太阳内层，即通关达成结局」。
##
## 这里没有建筑也没有发电机，只有一片灼热的地表和一个发送台：
## 它把房间的 room_id 定为 `sun_outer`，因此太阳语判定只在这里接受终极太阳语。

var _sent_ultimate: bool = false


func _build_room() -> void:
	room_id = &"sun_outer"
	display_name = "太阳"
	layer_name = "外层"
	room_size = Vector2(1600.0, 900.0)
	exit_position = Vector2(140.0, 140.0)
	# 太阳外层就是发送台：电码键常驻
	morse_enabled = true
	morse_send_allowed = true

	# 发送台：地面上刻着点与划的圆盘，靠近即可发送
	var pad := add_building("sun_send_pad", &"tower_perch", Vector2(800.0, 640.0), &"", true, false)
	pad.name = "SunSendPad"

	feedback.emit("太阳外层。地表烫得发白，脚下刻着一个可以打字的圆盘。")


func _handle_building_interaction(building: MapBuilding) -> bool:
	if building.kind == &"tower_perch":
		feedback.emit("圆盘上的刻痕是点与划。用下面的电码键按顺序长按，就是把话说给太阳听。")
		return true
	return false


## 覆写发送流程：在这里判定成功与否，并接住终极太阳语触发结局
func send_morse() -> Dictionary:
	var outcome := _verify_current()
	if outcome.is_empty():
		feedback.emit("还没有输入任何电码。")
		return {}
	morse_sent.emit(outcome)
	var result := int(outcome["result"])
	if result == SunLanguage.Result.SUCCESS:
		var word := StringName(outcome["word"])
		if word == SunLanguage.ULTIMATE_WORD:
			_on_ultimate_sent()
		else:
			# 普通语料：记下来，并把错误电码的回应也交给太阳
			_record_fragment(int(outcome["fragment"]))
			feedback.emit("你送出了「%s」。" % [SunLanguage.word_text(word)])
	elif result == SunLanguage.Result.UNKNOWN:
		# 设计稿：错误的电码会换回太阳语料 3「疑惑」
		WorldState.record_knowledge(&"know_doubt")
		WorldState.apply_changes({&"sun_fragment_2": true, &"sun_fragment_doubt": true})
		feedback.emit("错误的电码。太阳返回一段回应：疑惑。（已记录为太阳语料 3）")
	else:
		feedback.emit(describe_outcome(outcome))
	morse.clear()
	return outcome


func _record_fragment(index: int) -> void:
	if index < 0:
		return
	WorldState.apply_changes({("sun_fragment_%d" % index): true})
	match index:
		0:
			WorldState.record_knowledge(&"know_death_clear")
		1:
			WorldState.record_knowledge(&"know_awaken")
		2:
			WorldState.record_knowledge(&"know_doubt")


func _on_ultimate_sent() -> void:
	if _sent_ultimate:
		return
	_sent_ultimate = true
	WorldState.record_knowledge(&"ultimate_sun_language")
	WorldState.apply_changes({&"ultimate_sent": true})
	feedback.emit("终极太阳语被送出。太阳的内层开始向这里打开——你走了进去。")
	show_ending()


func ultimate_sent() -> bool:
	return _sent_ultimate
