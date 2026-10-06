class_name TerrainState
extends RefCounted
## 随时间变化的地形规则：把 WorldTime 的世界事件翻译成「哪些建筑可用」。
##
## 设计稿对应（执行细节 / 解谜细节）：
## - 水星分 1.2.3.4 层，玩家只在 1.2.3 层间切换，3 层到 4 层被拒绝。
## - 10 分钟后 1 层发生变换但不消失，1 层观察文本变化；11 分钟后 3 层发生变换。
## - 11 分钟后可从水星 3 层深入水星 4 层，与水星 AI Mercury 对话。
## - 太阳 10 分钟亮度提高；18 分钟太阳暴晕。
## - 太阳观测塔在 10 分钟前是启动的（可观察水流方向），之后关闭。

## 地形规则本身只做判定，不访问全局服务，便于 headless 测试。
## 需要的时间/标记由调用方注入。

## 水星 1 层：10 分钟后发生变换（水汽上升，观察文本变化）
const MERCURY_SURFACE_SHIFT_SECONDS: float = 600.0
## 水星 3 层：11 分钟后发生变换，并露出通往核心的通道
const MERCURY_LAYER3_SHIFT_SECONDS: float = 660.0


## 水星 1 层是否已经变换
static func mercury_surface_changed(flags: Dictionary) -> bool:
	return bool(flags.get(&"mercury_boiling", false))


## 水星 3 层是否已经变换（核心暴露）
static func mercury_core_exposed(flags: Dictionary) -> bool:
	return bool(flags.get(&"mercury_core_open", false))


## 太阳观测塔现在是否还在工作：10 分钟前启动，之后关闭
static func observatory_operating(flags: Dictionary) -> bool:
	return not bool(flags.get(&"sun_bright", false))


## 太阳是否已进入暴晕阶段（18 分钟）
static func sun_flaring(flags: Dictionary) -> bool:
	return bool(flags.get(&"sun_flare", false))


## 太阳当前的亮度阶段，供显示与后续视觉使用
static func sun_stage_label(flags: Dictionary) -> String:
	if sun_flaring(flags):
		return "太阳暴晕"
	if bool(flags.get(&"sun_bright", false)):
		return "太阳增亮"
	return "太阳平静"


## 水星 3 层能否进入 4 层：需要核心暴露（11 分钟后）或已经接触过 Mercury
static func can_enter_mercury_core(flags: Dictionary, known: Dictionary) -> bool:
	if mercury_core_exposed(flags):
		return true
	return bool(known.get(&"met_mercury_ai", false))


## 水星某层的观察文本随变换改变；未变换时不给核心线索
static func mercury_observe_text(layer: int, flags: Dictionary) -> String:
	var changed := mercury_surface_changed(flags)
	match layer:
		1:
			if changed:
				return "水汽从地表升起，1 层的轮廓在水雾里变了形状——不是消失，是换了一副样子。水流的痕迹指向更高的地方。"
			return "水星 1 层。地表的冰还结着，太阳观测塔在远处立着，水流沿着塔基缓缓经过。"
		2:
			return "水星 2 层。天文台的镜面结着水汽，观测记录把水流方向写成了同一个字。"
		3:
			if mercury_core_exposed(flags):
				return "水星 3 层。水已经全部蒸发，脚下的地层裂开，露出了通往核心的通道。"
			return "水星 3 层。热浪压着岩层，下面还有东西，但现在过不去。"
		4:
			return "水星 4 层。核心的热度让空气发白，Mercury 在这里等着和你说第一句话。"
	return "水星第 %d 层。" % [layer]


## 太阳观测塔的观察结果：10 分钟前给出水流方向（太阳语料 1 的线索），之后关闭
static func observatory_read(flags: Dictionary) -> String:
	if observatory_operating(flags):
		return "观测塔仍在工作。外层水流持续地朝着同一个方向流动，那个方向对应的太阳语是：「苏醒」。"
	return "观测塔已经关闭。镜面上只剩下一层水汽，水流的方向看不出来了。"
