class_name MapDialogue
extends RefCounted
## AI 对话：按「标志 + 知识」筛选可说的台词，说出后授予新知识。
##
## 设计稿对应（故事流程 / 知识地图）：
## - 「与 3 个 ai 进行接触」：水星 Mercury、火星 Mars（算力中心）、地球 AI。
## - 每次接触解锁知识地图上的下一级，因此台词本身按已获得的知识分层。
## - 知识是唯一进度，所以对话不消耗时间、不改变世界标记（回馈由调用方决定）。

## 全部台词。kind 用于知识地图归类，text 是正文。
## requires_knowledge / requires_flags 都满足才会出现；grant 是说出后授予的知识。
const LINES: Dictionary = {
	&"mercury_ai": [
		{
			"text": "「你来得比上一次早。」白得发烫的空气里，声音没有方向。",
			"grant": &"met_mercury_ai",
			"kind": &"ai",
		},
		{
			"text": "「我正在对这个世界进行模拟。这不是比喻——你脚下的每一层，都是我算出来的。」",
			"requires_knowledge": [&"met_mercury_ai"],
			"grant": &"mercury_is_simulation",
			"kind": &"ai",
		},
		{
			"text": "「星空出现过渲染错误。时间对不上。有人在对错误的地点观察，模拟就会失准。」",
			"requires_knowledge": [&"mercury_is_simulation"],
			"grant": &"simulation_error_time",
			"kind": &"ai",
		},
		{
			"text": "「你要做的不是修好它。是去找到那个错误的观察点。」",
			"requires_knowledge": [&"simulation_error_time"],
			"kind": &"ai",
		},
	],
	&"mars_ai": [
		{
			"text": "「人类的算力都堆在这里。」机房的风声盖过了说话声。",
			"grant": &"met_mars_ai",
			"kind": &"ai",
		},
		{
			"text": "「我们在全力发展 AI，想找一条躲开太阳的路。这个计划已经跑了很久。」",
			"requires_knowledge": [&"met_mars_ai"],
			"grant": &"human_plan_ai",
			"kind": &"ai",
		},
		{
			"text": "「计划进程可能因为在对错误的地点观察而终止。这是唯一的警告，听懂了就记住。」",
			"requires_knowledge": [&"human_plan_ai"],
			"grant": &"plan_may_terminate",
			"kind": &"ai",
		},
	],
	&"earth_ai": [
		{
			"text": "居民楼的电脑亮起来。屏幕上的字一行行浮现。",
			"grant": &"met_earth_ai",
			"kind": &"ai",
		},
		{
			"text": "「地球是一体的。所有灯连成一张网，需要大量电能才能同时点亮。」",
			"requires_knowledge": [&"met_earth_ai"],
			"grant": &"earth_is_one_grid",
			"kind": &"ai",
		},
		{
			"text": "「开灯就是通电。把中央区域的电脑接进来，你就能直接和我说话。」",
			"requires_knowledge": [&"earth_is_one_grid"],
			"grant": &"earth_needs_power",
			"kind": &"ai",
		},
	],
	&"mercury_observatory": [
		{
			"text": "观测记录里反复出现同一个水流的形状。",
			"grant": &"water_flow_south",
			"kind": &"place",
		},
		{
			"text": "水流始终指向东南。简化成四向，就是「苏醒」。",
			"requires_knowledge": [&"water_flow_south"],
			"grant": &"know_awaken",
			"kind": &"code",
		},
	],
}


## 当前可说的台词：所有 requires_* 都满足，且未说过（由 said 记录）
static func available_lines(speaker: StringName, known: Dictionary, flags: Dictionary, said: Array) -> Array:
	var result: Array = []
	if not LINES.has(speaker):
		return result
	for index in LINES[speaker].size():
		var line: Dictionary = LINES[speaker][index]
		var key := line_key(speaker, index)
		if said.has(key):
			continue
		if not _requirements_met(line, known, flags):
			continue
		result.append({
			"key": key,
			"index": index,
			"text": String(line["text"]),
			"grant": StringName(line.get("grant", &"")),
			"kind": StringName(line.get("kind", &"")),
		})
	return result


## 稳定标识，用于记录说过哪些台词（跨轮保留在 WorldState 知识里）
static func line_key(speaker: StringName, index: int) -> StringName:
	return StringName("said_%s_%d" % [speaker, index])


## 台词是否还有未说过的内容
static func has_more(speaker: StringName, known: Dictionary, flags: Dictionary, said: Array) -> bool:
	return not available_lines(speaker, known, flags, said).is_empty()


static func speaker_display_name(speaker: StringName) -> String:
	match speaker:
		&"mercury_ai":
			return "水星 AI Mercury"
		&"mars_ai":
			return "火星 AI Mars"
		&"earth_ai":
			return "地球 AI"
		&"mercury_observatory":
			return "天文台观测记录"
	return String(speaker)


static func _requirements_met(line: Dictionary, known: Dictionary, flags: Dictionary) -> bool:
	for key in line.get("requires_knowledge", []):
		if not bool(known.get(key, false)):
			return false
	for key in line.get("requires_flags", []):
		if not bool(flags.get(key, false)):
			return false
	return true
