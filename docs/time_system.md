# 游戏内时间系统

详细接口参数、返回值、信号及正式游戏流程示例见 [时间系统接口与游戏流程构建指南](time_system_api_and_game_flow.md)。

F6 运行 `scenes/time_system_demo.tscn`，或 F5 运行项目。Esc 暂停/继续；阅读、查看地图和思考不暂停。演示中的时间表为测试规则，并非正式剧情定稿。

## 模块与配置

Autoload 顺序为 `WorldTime → WorldState → ActionController → PauseController → TextDatabase → WorldJourney`。世界状态先处理事件变化，行动再检查执行和完成条件。切换地点时这些服务仍然存在；新场景只读取状态，不应重新调用 `start_loop()`。

| 文件 | 职责 |
| --- | --- |
| `scripts/time/world_time.gd` | 正常计时、倍率、跳跃、按序触发事件、循环结束 |
| `scripts/time/world_state.gd` | 本轮世界标记、位置、跨轮知识 |
| `scripts/time/action_controller.gd` | 行动条件、额外耗时、持续执行、取消与结果 |
| `scripts/time/pause_controller.gd` | 暂停输入与 `SceneTree.paused` |
| `scripts/time/world_journey.gd` | 两世界切换、进度快照、现实失败与虚拟重试 |
| `resources/time/demo_timeline.tres` | 循环长度、初始标记、事件时刻及变化 |
| `resources/time/real_timeline.tres` | 现实世界的时间上限、初始位置与事件 |
| `resources/time/demo_real_timeline.tres` | 演示专用的 120 秒现实时限与三个固定事件 |

在检查器中编辑 `WorldTimeline` 的 `Events`，每个元素是 `WorldTimeEvent`：唯一 ID、世界秒数、优先级、标记变化字典。相同时刻按优先级从小到大执行，再按注册顺序执行。正式世界事件优先级应小于行动完成的保留优先级 `1000000`。零时刻事件在世界重置后执行；循环终点专门由时钟处理，不配置为普通事件。

时间单位统一为秒，内部保留小数，显示时转成分秒。`Engine.time_scale` 保持 1；常态 `flow_rate` 为 1。循环外、暂停中以及重入事件回调中的推进请求均被拒绝。

## 初始化和接入地点

```gdscript
const VIRTUAL_TIMELINE: WorldTimeline = preload("res://resources/exploration/preview_timeline.tres")
const REAL_TIMELINE: WorldTimeline = preload("res://resources/time/real_timeline.tres")

func _ready() -> void:
	WorldState.state_changed.connect(refresh_location)
	# 只有启动入口安装时间表并开始循环，普通地点场景不要重复初始化。
	if not WorldJourney.is_started():
		WorldJourney.start(VIRTUAL_TIMELINE, REAL_TIMELINE)
	refresh_location()

func refresh_location() -> void:
	$EnterButton.disabled = not WorldState.meets_conditions({&"gate_open": true})
```

未加载地点的标记同样随时间更新。位置、亮度等连续视觉变化应从 `WorldTime.elapsed_seconds` 计算；文字和按钮通过 `WorldState.state_changed` 刷新，避免每帧重建文字。

## 行动与耗时口径

```gdscript
var travel := WorldAction.new()
travel.action_id = &"travel"
travel.display_name = "前往观测站"
travel.duration_seconds = 60.0
travel.start_conditions = {&"gate_open": true}
travel.finish_conditions = {&"gate_open": true}
travel.destination = &"observatory"
ActionController.execute_instant(travel)
```

`execute_instant()` 的时长是操作额外耗时：实时流逝已经由时钟计入，移动演出额外播放 2 秒则总耗时为 62 秒。`execute_timed(action, 10.0)` 在后续帧以 10 倍速执行，时长表示总共经过的世界秒数，不再额外扣同一笔耗时；适合等待和需要中途暂停的行动。

返回 `true` 只代表接受并开始行动；最终结果监听 `action_finished(action, succeeded, reason)`。拒绝的行动不耗时。开始条件只检查一次；执行条件开始时及每次世界变化时检查；完成条件在完成时刻的世界事件处理后检查。

执行期间失效会在事件边界取消，未经过的耗时不再收取；完成条件失败则已经支付完整耗时。失败不写入目的地和结果。条件字典按所有标记同时满足处理，缺失标记不能满足要求，因此应在初始世界中明确定义 false 标记。复杂地点规则可在调用前检查，并把持续变化的条件投影为世界标记。

同一时间只执行一个行动。使用 `ActionController.cancel_action()` 取消持续行动；暂停期间不能取消。直接 `WorldTime.skip_to(target)` 会处理途中事件，但不允许倒退，也应由业务层避免在正在行动时重复提交跳跃。

事件和行动完成回调中不要递归推进、开始行动或重置循环；需串联下一行动时使用 `call_deferred()`，待当前结算结束后执行。行动资源与事件资源在注册时复制，后续修改原资源不影响已经开始的行动。

## 暂停与循环

项目入口从虚拟世界开始。探索界面仅在顶部时间前显示循环轮次，不提供世界切换按钮或现实剩余时间；剧情中的装置、交互对象调用 `WorldJourney.return_to_reality()` / `return_to_virtual()` 切换世界。`PlanetExplorationUI.set_header_visible(false/true)` 隐藏/恢复顶部的地点、层级、轮次与时间。

两个世界各有独立 `WorldTimeline`，共用一个 `WorldTime`，只推进当前世界。每次进入现实都从零重新计时，现实世界不发送 `loop_ended`，到达终点发送 `real_time_ended`，随后 `WorldJourney.failed` 为 true 并发送 `game_failed`。失败后时间与行动停止，读完失败提示后返回离开虚拟世界时的最后一轮，沿用该轮编号，从零重新计时。

切换时分别保存两个世界的 flags 和玩家位置；知识和 TextDatabase 信息始终共享。失败不会清空这些记录，重新进入现实也恢复上次现实进度。回到虚拟世界不会触发 `loop_reset`，因此不会清空该轮快照。恢复进度时不重放零时刻初始化事件，其他时间事件按新计时重新触发；虚拟世界自然耗尽并开启下一轮时，仍恢复初始临时标记和位置。未完成行动在切换或终点取消，不授予完成结果。

快照在当前进程内保存，尚未实现退出游戏后的磁盘存档。当前探索预览的虚拟与现实时间上限都是 600 秒，可分别在入口的 `timeline` / `real_timeline` 资源中修改；正式的 `resources/time/timeline.tres` 保持已有配置。

时钟和世界节点为 `Pausable`；暂停输入为 `Always`；暂停菜单为 `When Paused`。用 `PauseController.set_paused(true/false)` 保证菜单同步收到通知。暂停会停止计时和持续行动，恢复时不追补暂停期间的时间。

达到终点时立即停止正常行动，清除待执行事件，发出 `loop_ended`。同刻完成的行动也判失败，超出的时间不带入下一轮。重置文字期间保持 `ENDED`；调用 `begin_reset()` 标记重置展示，再在展示结束后调用 `start_loop()`。

`start_loop()` 恢复时间、倍率、地点、临时世界标记和事件队列；`record_knowledge()` 保存的知识跨轮保留。知识用于玩家记录和提示，系统不会据此自动满足本轮操作条件。首次安装和显式开始下一轮之外，不应重新安装时间表。

## 验证

`tests/time_system_test.tscn` 为行为测试场景，可通过 Godot headless 运行：

```text
Godot --headless --path <项目目录> res://tests/time_system_test.tscn
```

测试覆盖正常与实际帧计时、暂停键恢复、暂停期间操作拒绝、多事件跳跃、零时刻和同刻排序、资源复制、条件检查、加速完成后倍率恢复、取消后无旧事件、循环终点和跨轮知识。输出 `TIME_SYSTEM_TESTS passed=... failed=...`，失败时返回非零退出码。

`tests/world_journey_test.tscn` 覆盖两世界独立进度、时间重启、现实失败、最后一轮重试、零时刻初始化保护、终点行动取消和共享知识/信息；`tests/planet_exploration_ui_test.tscn` 还验证顶部显隐、剧情切换接口、失败文本队列、暂停恢复和场景重载。

## 完整演示场景

打开 `scenes/time_system_demo.tscn` 后按 F6。演示复用 WorldJourney、WorldTime、WorldState、ActionController 和 TextDatabase，不创建另一套游戏规则。左侧是操作，右侧显示当前 flags/位置、两个世界的进度摘要、实际待发生事件队列以及最近 100 条信号/行动记录。日志在本次场景运行内跨世界、跨循环保留，重载演示场景时重新开始记录。

| 演示操作 | 可观察的行为 |
| --- | --- |
| 跳过 60 秒 / 跳到下一个事件 / 推进到终点 | advance_time / skip_to 按实际队列结算，终点不溢出下一轮 |
| ×1 / ×10 / 等待 60 秒（×10） | 自由倍率与持续行动；行动完成/取消恢复原倍率 |
| 暂停 / Esc | 时间和行动冻结，恢复不追补暂停时间 |
| 立即观察（0 秒） | 零耗时行动立即完成，不阻塞后续操作 |
| 前往观测站 / 穿越通道 / 研究装置 | 分别展示开始+完成、执行期间、完成条件，以及位置/结果原子提交 |
| 取消当前行动 | 不提交未完成结果，不留下旧完成事件 |
| 恰好在终点完成 | 终点优先，行动失败，无奖励 |
| 完成操作 / 收集信息 | 当前世界操作计数增加，信息跨世界共享 |
| 返回现实 / 返回虚拟最后一轮 | 分别恢复各自进度，从零计时；可在行动中切换并观察取消原因 |
| 登记 +20 秒同刻事件 / 取消动态事件 | 优先级 0 在 10 前发生，后者停止当前推进请求；取消后不会再触发 |
| 重载场景 | 不重置常驻时钟、世界、进度或未完成行动；失败状态仍显示重试界面 |

演示虚拟时间表为 600 秒：03:00 入口开启、04:00 装置启动、04:40 入口关闭。演示现实时限为 120 秒：00:30 能源不足、01:00 连接开启、01:30 连接关闭，02:00 失败。这份现实资源只用于演示，探索主场景仍使用自己的 real_timeline。

建议体验：跳到入口开启 → 前往观测站（同刻装置启动先于到达）→ 研究装置 → 完成操作 → 返回现实 → 完成操作 → 推进到终点 → 返回最后一轮。右侧可核对虚拟位置/研究结果/操作计数未丢失，再进入现实时，现实操作计数仍保留且获得完整新计时。

`tests/time_system_demo_test.tscn` 通过演示按钮信号验证这些操作、动态事件副本保护、进度恢复、行动条件和运行/失败期间的场景重载。
