# 游戏内时间系统

详细接口参数、返回值、信号及正式游戏流程示例见 [时间系统接口与游戏流程构建指南](time_system_api_and_game_flow.md)。

F6 运行 `scenes/time_system_demo.tscn`，或 F5 运行项目。Esc 暂停/继续；阅读、查看地图和思考不暂停。演示中的时间表为测试规则，并非正式剧情定稿。

## 模块与配置

Autoload 顺序为 `WorldTime → WorldState → ActionController → PauseController`。世界状态先处理事件变化，行动再检查执行和完成条件。切换地点时四个服务仍然存在；新场景只读取状态，不应重新调用 `start_loop()`。

| 文件 | 职责 |
| --- | --- |
| `scripts/time/world_time.gd` | 正常计时、倍率、跳跃、按序触发事件、循环结束 |
| `scripts/time/world_state.gd` | 本轮世界标记、位置、跨轮知识 |
| `scripts/time/action_controller.gd` | 行动条件、额外耗时、持续执行、取消与结果 |
| `scripts/time/pause_controller.gd` | 暂停输入与 `SceneTree.paused` |
| `resources/time/demo_timeline.tres` | 循环长度、初始标记、事件时刻及变化 |

在检查器中编辑 `WorldTimeline` 的 `Events`，每个元素是 `WorldTimeEvent`：唯一 ID、世界秒数、优先级、标记变化字典。相同时刻按优先级从小到大执行，再按注册顺序执行。正式世界事件优先级应小于行动完成的保留优先级 `1000000`。零时刻事件在世界重置后执行；循环终点专门由时钟处理，不配置为普通事件。

时间单位统一为秒，内部保留小数，显示时转成分秒。`Engine.time_scale` 保持 1；常态 `flow_rate` 为 1。循环外、暂停中以及重入事件回调中的推进请求均被拒绝。

## 初始化和接入地点

```gdscript
const TIMELINE: WorldTimeline = preload("res://resources/time/demo_timeline.tres")

func _ready() -> void:
	WorldState.state_changed.connect(refresh_location)
	# 只有启动入口安装时间表并开始循环，普通地点场景不要重复初始化。
	if WorldTime.phase == WorldTime.Phase.READY and TIMELINE.install():
		WorldTime.start_loop()
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

时钟和世界节点为 `Pausable`；暂停输入为 `Always`；暂停菜单为 `When Paused`。用 `PauseController.set_paused(true/false)` 保证菜单同步收到通知。暂停会停止计时和持续行动，恢复时不追补暂停期间的时间。

达到终点时立即停止正常行动，清除待执行事件，发出 `loop_ended`。同刻完成的行动也判失败，超出的时间不带入下一轮。重置文字期间保持 `ENDED`；调用 `begin_reset()` 标记重置展示，再在展示结束后调用 `start_loop()`。

`start_loop()` 恢复时间、倍率、地点、临时世界标记和事件队列；`record_knowledge()` 保存的知识跨轮保留。知识用于玩家记录和提示，系统不会据此自动满足本轮操作条件。首次安装和显式开始下一轮之外，不应重新安装时间表。

## 验证

`tests/time_system_test.tscn` 为行为测试场景，可通过 Godot headless 运行：

```text
Godot --headless --path <项目目录> res://tests/time_system_test.tscn
```

测试覆盖正常与实际帧计时、暂停键恢复、暂停期间操作拒绝、多事件跳跃、零时刻和同刻排序、资源复制、条件检查、加速完成后倍率恢复、取消后无旧事件、循环终点和跨轮知识。输出 `TIME_SYSTEM_TESTS passed=... failed=...`，失败时返回非零退出码。
