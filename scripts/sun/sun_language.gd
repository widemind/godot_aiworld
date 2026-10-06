extends RefCounted
class_name SunLanguage
## 太阳语字典：中文词 → 摩斯电码序列。
##
## 设计约束（见设计稿「知识地图 / 执行细节」）：
## - 太阳语由汉字文本与摩斯电码组成，靠「按顺序长按 / 短按」发送，即点划输入。
## - 判定与场景上下文绑定：同一个电码在不同层、不同星球含义不同。
## - 必须先获得对应知识才能理解与发送；理解前发送只会得到「你还读不懂」的反馈。
## - 完整序列两端不加字间隔，中间用字间隔（/）分隔，因此按字切分可无歧义还原。

## 判定结果（脚本加载，供所有调用方共用同一套枚举）
enum Result { EMPTY, UNKNOWN, LOCKED, WRONG_CONTEXT, SUCCESS }

## 码表：一个「太阳语字符」= 一个词 + 一字母摩斯码。
##
## 取「行首字母」规则：太阳=A(.-)、赤阳=B(-...)、塔=C(-.-.)、地球=D(-..)、
## 人类=I(..)、水星=M(--)、火星=N(-.)、苏醒=R(.-.)、模拟=S(...)、
## 疑惑=U(..-)、观测=W(.--)、回归=G(--.)、清除=K(-.-)。
## 词级映射保证每个码都自分隔且互不相同，任何分段都能无歧义还原。
const CODEX: Dictionary = {
	&"太阳": {"code": ".-", "meaning": "太阳"},
	&"赤阳": {"code": "-...", "meaning": "赤阳（太阳的第二种写法）"},
	&"塔": {"code": "-.-.", "meaning": "塔"},
	&"地球": {"code": "-..", "meaning": "地球"},
	&"人类": {"code": "..", "meaning": "人类"},
	&"水星": {"code": "--", "meaning": "水星"},
	&"火星": {"code": "-.", "meaning": "火星"},
	&"苏醒": {"code": ".-.", "meaning": "苏醒"},
	&"模拟": {"code": "...", "meaning": "模拟"},
	&"疑惑": {"code": "..-", "meaning": "疑惑"},
	&"观测": {"code": ".--", "meaning": "观测"},
	&"回归": {"code": "--.", "meaning": "回归"},
	&"清除": {"code": "-.-", "meaning": "清除"},
}

## 词条：玩家可以学会、可以发送的整句太阳语。
## context 为空表示任何场景都能发送；key 为空表示不要求知识（仅用于演示/测试）。
const WORDS: Dictionary = {
	&"death_clear": {
		"text": "清除",
		"chunks": ["清除"],
		"context": ["sun_outer"],
		"key": &"know_death_clear",
		"fragment": 0,
		"meaning": "死亡时触发的太阳语言：清除。",
	},
	&"awaken": {
		"text": "苏醒",
		"chunks": ["苏醒"],
		"context": ["sun_outer", "mercury_1"],
		"key": &"know_awaken",
		"fragment": 1,
		"meaning": "太阳观测塔收到的持续水流方向：苏醒。",
	},
	&"doubt": {
		"text": "疑惑",
		"chunks": ["疑惑"],
		"context": ["sun_outer"],
		"key": &"know_doubt",
		"fragment": 2,
		"meaning": "在模拟中打错电码时太阳的回应：疑惑。",
	},
	&"ultimate": {
		"text": "终极太阳语",
		"chunks": ["赤阳", "塔", "人类", "回归"],
		"context": ["sun_outer"],
		"key": &"know_ultimate",
		"fragment": -1,
		"meaning": "解除模拟后向太阳发送，深入太阳内层。",
	},
}

const FRAGMENT_WORDS: Array[StringName] = [&"death_clear", &"awaken", &"doubt"]
const ULTIMATE_WORD: StringName = &"ultimate"


## 把点划符号串（".-" / "-.-" 等）转成内部标记串；统一委托给 MorseInput
static func symbols_to_tokens(symbols: String) -> Array[StringName]:
	return MorseInput.symbols_to_tokens(symbols)


## 取一个太阳语字符的点划符号；未知字符返回空串
static func character_code(character: StringName) -> String:
	if not CODEX.has(character):
		return ""
	return String(CODEX[character]["code"])


static func has_character(character: StringName) -> bool:
	return CODEX.has(character)


static func character_meaning(character: StringName) -> String:
	if not CODEX.has(character):
		return ""
	return String(CODEX[character]["meaning"])


static func has_word(word: StringName) -> bool:
	return WORDS.has(word)


static func word_text(word: StringName) -> String:
	if not WORDS.has(word):
		return ""
	return String(WORDS[word]["text"])


static func word_meaning(word: StringName) -> String:
	if not WORDS.has(word):
		return ""
	return String(WORDS[word]["meaning"])


static func word_knowledge_key(word: StringName) -> StringName:
	if not WORDS.has(word):
		return &""
	return StringName(WORDS[word]["key"])


static func word_fragment_index(word: StringName) -> int:
	if not WORDS.has(word):
		return -1
	return int(WORDS[word]["fragment"])


## 该词在给定场景下是否允许发送；context 为空表示不限制
static func word_allows_context(word: StringName, context: StringName) -> bool:
	if not WORDS.has(word):
		return false
	var allowed: Array = WORDS[word]["context"]
	if allowed.is_empty():
		return true
	return allowed.has(String(context))


## 把某词的分段展开成点划标记串（段间插入字间隔）
static func word_tokens(word: StringName) -> Array[StringName]:
	var tokens: Array[StringName] = []
	if not WORDS.has(word):
		return tokens
	var chunks: Array = WORDS[word]["chunks"]
	for index in chunks.size():
		if index > 0:
			tokens.append(MorseInput.LETTER_GAP)
		tokens.append_array(symbols_to_tokens(character_code(StringName(chunks[index]))))
	return tokens


## 某词需要发送的整串点划与字间隔，供 UI 提示使用
static func word_hint(word: StringName) -> String:
	var tokens := word_tokens(word)
	var parts: PackedStringArray = []
	for token in tokens:
		if token == MorseInput.DOT:
			parts.append("·")
		elif token == MorseInput.DASH:
			parts.append("−")
		elif token == MorseInput.LETTER_GAP:
			parts.append(" ")
	return "".join(parts)


## 点划标记是否与目标词逐位一致。
## 尾部字间隔只表示「这个字已结束」，不参与比较，因此输入中与输入完都能判定。
static func matches_word(word: StringName, tokens: Array[StringName]) -> bool:
	var expected := word_tokens(word)
	if expected.is_empty():
		return false
	var actual := trimmed(tokens)
	if expected.size() != actual.size():
		return false
	for index in expected.size():
		if expected[index] != actual[index]:
			return false
	return true


## 去掉尾部字间隔；字间隔只用于分段，不构成电码本身
static func trimmed(tokens: Array[StringName]) -> Array[StringName]:
	var result := tokens.duplicate()
	while not result.is_empty() and result[-1] == MorseInput.LETTER_GAP:
		result.remove_at(result.size() - 1)
	return result


## 按字间隔把标记串切成分段（分隔符本身丢弃）
static func split_chunks(tokens: Array[StringName]) -> Array:
	var chunks: Array = []
	var current: Array[StringName] = []
	for token in tokens:
		if token == MorseInput.LETTER_GAP:
			if not current.is_empty():
				chunks.append(current)
				current = []
			continue
		current.append(token)
	if not current.is_empty():
		chunks.append(current)
	return chunks


## 由点划分段还原太阳语字符；任一段不在码表中则失败
static func decode_chunks(chunks: Array) -> Array[StringName]:
	var characters: Array[StringName] = []
	for chunk in chunks:
		var found := _character_for_tokens(chunk)
		if found == &"":
			return []
		characters.append(found)
	return characters


## 把标记串还原为太阳语文本；无法还原返回空串
static func decode_text(tokens: Array[StringName]) -> String:
	var characters := decode_chunks(split_chunks(tokens))
	if characters.is_empty():
		return ""
	var parts: PackedStringArray = []
	for character in characters:
		parts.append(String(character))
	return "".join(parts)


## 找出与目标词同形（点划序列一致）的候选词，用于提示「电码对但场景不对」
static func words_matching(tokens: Array[StringName]) -> Array[StringName]:
	var result: Array[StringName] = []
	for word in WORDS:
		if matches_word(word, tokens):
			result.append(word)
	return result


## 完整判定。world 与理解状态由调用方注入，本函数不访问全局服务，便于测试。
## 返回 {"result": Result, "word": StringName, "knowledge_key": StringName,
##       "fragment": int, "decoded": String}
static func verify(tokens: Array[StringName], context: StringName, known: Dictionary) -> Dictionary:
	var outcome := {
		"result": Result.EMPTY,
		"word": &"",
		"knowledge_key": &"",
		"fragment": -1,
		"decoded": "",
	}
	if tokens.is_empty():
		return outcome
	outcome["decoded"] = decode_text(tokens)
	var same_shape := words_matching(tokens)
	if same_shape.is_empty():
		outcome["result"] = Result.UNKNOWN
		return outcome
	# 同形词优先选场景允许的那个；都不允许则报场景错误。
	var chosen: StringName = &""
	for word in same_shape:
		if word_allows_context(word, context):
			chosen = word
			break
	if chosen == &"":
		outcome["word"] = same_shape[0]
		outcome["result"] = Result.WRONG_CONTEXT
		return outcome
	outcome["word"] = chosen
	outcome["knowledge_key"] = word_knowledge_key(chosen)
	outcome["fragment"] = word_fragment_index(chosen)
	var key := word_knowledge_key(chosen)
	# key 为空表示该词不需要理解即可发送（章节内的直接操作）。
	if not key.is_empty() and not bool(known.get(key, false)):
		outcome["result"] = Result.LOCKED
		return outcome
	outcome["result"] = Result.SUCCESS
	return outcome


static func result_label(result: int) -> String:
	match result:
		Result.EMPTY:
			return "空"
		Result.UNKNOWN:
			return "不是太阳语"
		Result.LOCKED:
			return "读不懂"
		Result.WRONG_CONTEXT:
			return "场景不对"
		Result.SUCCESS:
			return "成功"
	return "未知"


static func _character_for_tokens(tokens: Array) -> StringName:
	var wanted := ""
	for token in tokens:
		if token == MorseInput.DOT:
			wanted += "."
		elif token == MorseInput.DASH:
			wanted += "-"
		else:
			return &""
	if wanted.is_empty():
		return &""
	for character in CODEX:
		if String(CODEX[character]["code"]) == wanted:
			return character
	return &""
