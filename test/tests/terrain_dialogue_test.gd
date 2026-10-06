extends Node
## 地形变换与 AI 对话的行为测试。
## headless 运行：Godot --headless --path . res://test/tests/terrain_dialogue_test.tscn

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await get_tree().process_frame
	_test_terrain()
	_test_dialogue()
	print("TERRAIN_DIALOGUE_TESTS passed=%d failed=%d" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("TERRAIN_DIALOGUE_TEST FAILED: " + message)


func _test_terrain() -> void:
	var pristine := {}
	_check(not TerrainState.mercury_surface_changed(pristine), "开局水星 1 层未变换")
	_check(TerrainState.observatory_operating(pristine), "10 分钟前观测塔在工作")
	_check(not TerrainState.can_enter_mercury_core(pristine, {}), "开局不能进入水星核心")

	# 10 分钟：太阳增亮，观测塔关闭
	var bright := {&"sun_bright": true}
	_check(not TerrainState.observatory_operating(bright), "太阳增亮后观测塔关闭")

	# 11 分钟：核心暴露，可进入 4 层，1 层文本变换
	var boiling := {&"mercury_boiling": true, &"mercury_core_open": true}
	_check(TerrainState.mercury_surface_changed(boiling), "11 分钟后 1 层已变换")
	var text_before := TerrainState.mercury_observe_text(1, pristine)
	var text_after := TerrainState.mercury_observe_text(1, boiling)
	_check(text_before != text_after, "1 层观察文本随变换改变")
	_check(text_before.contains("观测塔"), "变换前 1 层文本提到观测塔")
	_check(text_after.contains("水汽"), "变换后 1 层文本描述水汽")
	_check(TerrainState.can_enter_mercury_core(boiling, {}), "核心暴露后可以进入水星 4 层")
	_check(TerrainState.mercury_observe_text(3, boiling).contains("通道"), "3 层文本显示通道已开")
	_check(not TerrainState.mercury_observe_text(3, {}).contains("通道"), "未变换时 3 层不给通道线索")
	# 已接触过 Mercury 也可进入核心
	_check(TerrainState.can_enter_mercury_core({}, {&"met_mercury_ai": true}), "接触过 Mercury 后可进入核心")
	# 观测塔读数
	_check(TerrainState.observatory_read(pristine).contains("苏醒"), "观测塔在工作时给出苏醒")
	_check(TerrainState.observatory_read(bright).contains("关闭"), "观测塔关闭后不再给出水流方向")

	# 18 分钟：太阳暴晕
	var flaring := {&"sun_bright": true, &"sun_flare": true}
	_check(TerrainState.sun_flaring(flaring), "暴晕阶段可识别")
	_check(not TerrainState.sun_flaring(bright), "增亮阶段还不是暴晕")
	_check(TerrainState.sun_stage_label(pristine) == "太阳平静", "开局太阳平静")
	_check(TerrainState.sun_stage_label(bright) == "太阳增亮", "10 分钟后太阳增亮")
	_check(TerrainState.sun_stage_label(flaring) == "太阳暴晕", "18 分钟后太阳暴晕")


func _test_dialogue() -> void:
	var known := {}
	var flags := {}
	var said: Array = []
	# 首次接触：只有第一条台词
	var first := MapDialogue.available_lines(&"mercury_ai", known, flags, said)
	_check(first.size() == 1, "首次接触 Mercury 只有一条台词")
	_check(String(first[0]["grant"]) == "met_mercury_ai", "首条台词授予接触知识")
	# 说过之后不再出现
	var keys: Array = [first[0]["key"]]
	var again := MapDialogue.available_lines(&"mercury_ai", {&"met_mercury_ai": true}, flags, keys)
	_check(again.size() == 1, "说过第一条后出现第二条")
	_check(String(again[0]["grant"]) == "mercury_is_simulation", "第二条揭示这是模拟")
	# 条件不满足时整条被跳过
	var skipped := MapDialogue.available_lines(&"mars_ai", {}, flags, [])
	_check(skipped.size() == 1, "火星 AI 同样从第一条开始")
	var mars_all := MapDialogue.available_lines(&"mars_ai", {&"met_mars_ai": true}, flags, [])
	_check(mars_all.size() == 2, "满足条件后火星展开后续台词")
	# has_more
	_check(MapDialogue.has_more(&"earth_ai", {}, flags, []), "地球 AI 还有可说的内容")
	var all_said: Array = []
	for index in MapDialogue.LINES[&"earth_ai"].size():
		all_said.append(MapDialogue.line_key(&"earth_ai", index))
	_check(not MapDialogue.has_more(&"earth_ai", {}, flags, all_said), "全部记录后标记为无更多")
	# 三个 AI 都存在
	_check(MapDialogue.LINES.has(&"mercury_ai") and MapDialogue.LINES.has(&"mars_ai") \
		and MapDialogue.LINES.has(&"earth_ai"), "三个 AI 都有对话数据")
	_check(MapDialogue.speaker_display_name(&"mars_ai") == "火星 AI Mars", "说话人显示名可读")
	# 观测记录给出太阳语：苏醒
	var observatory := MapDialogue.available_lines(&"mercury_observatory", {}, flags, [])
	_check(observatory.size() == 1, "观测记录首条为水流方向")
	var obs_keys: Array = [observatory[0]["key"]]
	var obs_next := MapDialogue.available_lines(&"mercury_observatory", {&"water_flow_south": true}, flags, obs_keys)
	_check(obs_next.size() == 1 and String(obs_next[0]["grant"]) == "know_awaken", "观测记录第二步给出苏醒")

	# 知识地图解锁计数
	var map_known := {&"met_earth_ai": true, &"know_awaken": true}
	_check(_unlocked(map_known) == 2, "知识地图按知识键计数")
	_check(_unlocked({}) == 0, "空知识解锁数为 0")


## 知识地图的分支骨架必须覆盖每条台词授予的知识，否则玩家永远看不到某些线索
func _unlocked(known: Dictionary) -> int:
	var count := 0
	for entry in _knowledge_entries():
		if bool(known.get(entry, false)):
			count += 1
	return count


func _knowledge_entries() -> Array:
	var keys: Array = []
	for speaker in MapDialogue.LINES:
		for index in MapDialogue.LINES[speaker].size():
			var grant := StringName(MapDialogue.LINES[speaker][index].get("grant", &""))
			if grant != &"" and not keys.has(grant):
				keys.append(grant)
	return keys
