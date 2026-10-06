extends Node
## 太阳语与摩斯输入的行为测试。
## headless 运行：Godot --headless --path . res://test/tests/sun_language_test.tscn

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await get_tree().process_frame
	_test_codex()
	_test_morse_timing()
	_test_morse_separator()
	_test_verify_gating()
	print("SUN_LANGUAGE_TESTS passed=%d failed=%d" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("SUN_LANGUAGE_TEST FAILED: " + message)


## 符号串转标记；"." 点、"-" 划、"/" 字间隔
func _seq(symbols: String) -> Array[StringName]:
	return MorseInput.symbols_to_tokens(symbols)


func _test_codex() -> void:
	_check(SunLanguage.has_word(&"death_clear"), "清除词条存在")
	_check(SunLanguage.word_text(&"death_clear") == "清除", "词条正文正确")
	_check(SunLanguage.character_code(&"清除") == "-.-", "清除码为 -.-")
	_check(SunLanguage.character_code(&"苏醒") == ".-.", "苏醒码为 .-.")
	_check(SunLanguage.character_code(&"疑惑") == "..-", "疑惑码为 ..-")
	_check(SunLanguage.character_code(&"赤阳") == "-...", "赤阳码为 -...")
	_check(SunLanguage.character_code(&"塔") == "-.-.", "塔码为 -.-.")
	_check(SunLanguage.character_code(&"人类") == "..", "人类码为 ..")
	_check(SunLanguage.character_code(&"回归") == "--.", "回归码为 --.")
	_check(SunLanguage.character_code(&"不存在") == "", "未知字符返回空码")
	# 终极太阳语的每个字都必须能在码表中查到，否则词条不可发送。
	var ultimate_chunks: Array = SunLanguage.WORDS[&"ultimate"]["chunks"]
	var all_known := true
	for chunk in ultimate_chunks:
		if SunLanguage.character_code(StringName(chunk)) == "":
			all_known = false
	_check(all_known, "终极太阳语的每个字都有码")
	# 每个码必须唯一，否则同一串电码会有歧义。
	var codes: Dictionary = {}
	var duplicates: PackedStringArray = []
	for character in SunLanguage.CODEX:
		var code := SunLanguage.character_code(character)
		if codes.has(code):
			duplicates.append("%s:%s/%s" % [code, codes[character], character])
		codes[code] = character
	_check(duplicates.is_empty(), "所有太阳语字符码互不相同 %s" % [duplicates])


func _test_morse_timing() -> void:
	var morse := MorseInput.new()
	_check(morse.display() == "", "初始为空")

	# 短按 -> 点
	morse.press()
	morse.tick(0.1)
	_check(morse.release() == _seq("."), "短按释放返回点")
	_check(morse.effective_tokens() == _seq("."), "短按产生点")
	_check(morse.effective_tokens() == _seq("."), "重复读取结果一致（UI 每帧轮询）")
	_check(morse.has_open_chunk(), "点仍在当前段内")
	_check(morse.tokens().is_empty(), "未断字时敲定串仍为空")

	# 长按 -> 划
	morse.press()
	morse.tick(0.35)
	morse.release()
	_check(morse.effective_tokens() == _seq(".-"), "长按产生划")
	_check(morse.open_chunk_symbols() == ".-", "当前段符号为 .-")

	# 抖动不产生电码
	var jitter := MorseInput.new()
	jitter.press()
	jitter.tick(0.001)
	_check(jitter.release().is_empty(), "过短按压不返回标记")
	_check(jitter.is_empty(), "过短的按压被忽略")

	# 静默自动断字
	morse.tick(0.7)
	_check(not morse.has_open_chunk(), "静默后自动断字")
	_check(morse.tokens() == _seq(".-/"), "断字后敲定串含字间隔")
	_check(morse.effective_tokens() == _seq(".-/"), "断字后有效串含字间隔")
	_check(SunLanguage.split_chunks(morse.tokens()).size() == 1, "断字后仍是一段")

	# 断字后继续输入：新段落在字间隔之后
	morse.press()
	morse.tick(0.05)
	morse.release()
	_check(morse.effective_tokens() == _seq(".-/."), "新段落在字间隔之后")
	morse.clear()
	_check(morse.is_empty() and morse.display() == "", "清空后为空")


func _test_morse_separator() -> void:
	# 空段不产生分隔
	var empty_input := MorseInput.new()
	_check(empty_input.separator() == false, "空段不产生分隔")
	_check(empty_input.is_empty(), "空段的等待键不写入任何标记")

	var manual := MorseInput.new()
	manual.press()
	manual.tick(0.05)
	manual.release()
	manual.press()
	manual.tick(0.3)
	manual.release()
	_check(manual.has_open_chunk(), "连续输入后仍处于同一段")
	_check(manual.effective_tokens() == _seq(".-"), "两枚电码同属一段")
	_check(manual.separator(), "等待键切出当前字")
	_check(not manual.has_open_chunk(), "切出后当前段已清空")
	_check(manual.tokens() == _seq(".-/"), "分隔后敲定串含字间隔")
	# 手动分隔与静默断字必须产生同一种标记串，两条输入路径可互换
	var silent := MorseInput.new()
	silent.press()
	silent.tick(0.05)
	silent.release()
	silent.press()
	silent.tick(0.3)
	silent.release()
	silent.tick(0.7)
	_check(silent.tokens() == manual.tokens(), "手动分隔与静默断字结果一致")
	# 两种路径都能被同一切分逻辑识别为一段
	_check(SunLanguage.split_chunks(silent.tokens()) == SunLanguage.split_chunks(manual.tokens()), "两条路径切分结果一致")
	# 断字后继续输入，产生第二个字
	manual.press()
	manual.tick(0.05)
	manual.release()
	_check(SunLanguage.split_chunks(manual.effective_tokens()).size() == 2, "分隔符产生新的字")
	_check(manual.display() == "·− ·", "显示形式为点划加空格")
	_check(manual.separator(), "第二个字也可手动切出")
	_check(manual.tokens() == _seq(".-/./"), "两次分隔产生两个尾部字间隔")
	manual.clear()
	_check(manual.is_empty() and manual.display() == "", "清空后为空")


func _test_verify_gating() -> void:
	# 完整序列：按字间隔切分后应与符号串逐位一致
	var death := SunLanguage.word_tokens(&"death_clear")
	_check(death == _seq("-.-"), "清除的发送序列与码表一致")
	_check(SunLanguage.decode_text(death) == "清除", "电码可还原为清除")
	_check(SunLanguage.matches_word(&"death_clear", death), "词条逐位匹配")
	var ultimate := SunLanguage.word_tokens(&"ultimate")
	_check(ultimate == _seq("-.../-.-./../--."), "终极太阳语为赤阳/塔/人类/回归")
	_check(SunLanguage.decode_text(ultimate) == "赤阳塔人类回归", "终极序列可还原")
	_check(SunLanguage.word_hint(&"ultimate") == "−··· −·−· ·· −−·", "提示串可直接展示")
	_check(SunLanguage.word_hint(&"awaken") == "·−·", "单字词提示串正确")

	# 场景 + 知识双重门控
	var unknown := {}
	var learnt := {
		&"know_death_clear": true,
		&"know_awaken": true,
		&"know_doubt": true,
		&"know_ultimate": true,
	}
	var locked := SunLanguage.verify(death, &"sun_outer", unknown)
	_check(locked["result"] == SunLanguage.Result.LOCKED, "未理解时发送被拒绝")
	_check(locked["word"] == &"death_clear" and locked["fragment"] == 0, "被锁时仍能定位词条")
	var wrong_context := SunLanguage.verify(SunLanguage.word_tokens(&"awaken"), &"earth_1", learnt)
	_check(wrong_context["result"] == SunLanguage.Result.WRONG_CONTEXT, "场景不符时拒绝")
	var success := SunLanguage.verify(death, &"sun_outer", learnt)
	_check(success["result"] == SunLanguage.Result.SUCCESS, "知识与场景齐备时成功")
	_check(success["word"] == &"death_clear" and success["fragment"] == 0, "成功时回传词条与语料序号")
	_check(success["decoded"] == "清除", "成功时回传还原文本")
	var garbage := SunLanguage.verify(_seq("....."), &"sun_outer", learnt)
	_check(garbage["result"] == SunLanguage.Result.UNKNOWN, "不存在的电码报未知")
	var empty_tokens: Array[StringName] = []
	var empty := SunLanguage.verify(empty_tokens, &"sun_outer", learnt)
	_check(empty["result"] == SunLanguage.Result.EMPTY, "空输入报空")
	# 同形电码优先匹配当前场景允许的词
	var at_mercury := SunLanguage.verify(SunLanguage.word_tokens(&"awaken"), &"mercury_1", learnt)
	_check(at_mercury["result"] == SunLanguage.Result.SUCCESS, "水星 1 层允许苏醒")
	_check(SunLanguage.result_label(SunLanguage.Result.LOCKED) == "读不懂", "结果标签可读")
	# 终极太阳语只在太阳外层生效，且需要集齐语料
	var ultimate_locked := SunLanguage.verify(ultimate, &"sun_outer", unknown)
	_check(ultimate_locked["result"] == SunLanguage.Result.LOCKED, "未集齐语料时终极太阳语被拒绝")
	var ultimate_ok := SunLanguage.verify(ultimate, &"sun_outer", learnt)
	_check(ultimate_ok["result"] == SunLanguage.Result.SUCCESS, "集齐语料后终极太阳语可发送")
	_check(ultimate_ok["word"] == &"ultimate" and ultimate_ok["fragment"] == -1, "终极太阳语不是普通语料")
