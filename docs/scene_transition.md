# 全局像素溶解场景过渡

`SceneTransition` 自动加载 `scenes/effect/scene_transition.tscn`，在 CanvasLayer 90 绘制旧场景截图。实际顺序是游戏场景 / UI（layer < 90）→ 过渡层（90）→ GameCursor（100）→ GlobalCRT（128）。旧画面静止并按随机方块溶解，新场景在下方实时运行；不经过黑屏。

Shader 基于 cak3_lover 的 [Pixelate into view (Custom Resolution)](https://godotshaders.com/shader/pixelate-into-view-custom-resolution/)，源代码为 CC0。保留固定随机网格，以线性 `progress` 替代 `sin(time)`，并保证 0 完全覆盖、1 完全透明。

## 调用

```gdscript
# 按钮等当前场景内的入口：直接调用，流程由 Autoload 持续执行。
SceneTransition.change_scene_to_file("res://scenes/ui/menu/main_menu.tscn")

# 自定义时长和网格。网格是列数 × 行数，不是每个方块的像素尺寸。
SceneTransition.change_scene_to_file(target_path, 1.2, Vector2(160, 90))

# 只有持久节点才能等待完整结果，当前场景会在切换中释放。
var error: Error = await SceneTransition.change_scene_to_file(target_path)
if error != OK:
    push_warning("场景切换失败：%s" % error_string(error))
```

`duration < 0` 使用默认时长 0.8 秒，`duration = 0` 不截图、不溶解，直接切换并等待首帧。`grid = Vector2.ZERO` 使用默认 160 × 90 网格。1920 × 1080 下对应约 12 × 12 像素的方块。参数可以在过渡器场景检查器中修改，或由调用者传入。

信号：`transition_started(scene_path)`（开始加载）、`scene_revealed(scene_path)`（新场景已绘制首帧，开始溶解）、`transition_finished(scene_path)`（完成并释放截图）、`transition_failed(scene_path, error)`（失败）。`is_transitioning` 表示是否正在加载或过渡。并发请求直接返回 `ERR_BUSY`，不影响已有过渡。

## 加载、输入与暂停

先在线程中加载目标场景，旧画面仍保持显示；加载成功后才截图并切换。切换成功等待 `scene_changed` 和新场景首帧绘制，随后启动溶解。无效路径、加载失败、无效参数会返回错误；已有场景仍保留，恢复输入并清除过渡状态。

加载与过渡期间暂时禁用根视口事件输入，阻止 GUI、`_input`、`_unhandled_input` 和暂停键穿透。结束恢复调用前的输入锁状态。游戏逻辑如果主动轮询 `Input.is_action_pressed()`，应自行用 `SceneTransition.is_transitioning` 跳过处理；输入事件禁用不会清除全局 Input 状态。

过渡器为 `PROCESS_MODE_ALWAYS`，Tween 在暂停时继续，忽略 `Engine.time_scale`。不主动修改游戏暂停状态或时间倍率；如果从暂停菜单切换，希望新场景恢复运行，可由调用者显式恢复暂停。

## 截图与 CRT

截图前临时隐藏 `capture_exclusions` 中的全局层（默认 GlobalCRT 和 GameCursor），使用 `RenderingServer.force_draw(false)` 在不交换显示缓冲的情况下同步绘制并读回原始画面，然后立即恢复原可见状态。这个过程不等待正常显示帧，不向窗口呈现临时无滤镜画面。旧截图、新画面与当前光标随后一起经过一次 CRT；截图不会包含旧光标。

截图仅在每次切换时读回一次 GPU 图像，完成后释放。高分辨率截图可能带来一次短暂同步开销；资源线程加载也不免除新场景实例化和首次 Shader 编译的开销。

所有需要参与过渡的场景 CanvasLayer 必须低于 90；需要始终保留的全局 HUD 放在 90 以上，并把其路径加入 `capture_exclusions`。独立 OS 子窗口不属于根视口截图。

## 演示与验证

打开 `scenes/scene_transition_demo_a.tscn` 按 F6，再点击“切换场景”，可在冷蓝与炽阳轨道之间双向切换。新场景的轨道动画在溶解期间运行，光标与 CRT 持续显示。正式主场景仍由项目原配置启动。

`tests/scene_transition_test.tscn` 使用真实渲染器验证无效路径、并发请求、截图原色、输入锁、暂停、时间倍率、零时长、资源释放，以及实际 Shader 的起点 / 中点 / 终点和网格稳定性。请从编辑器运行，或使用 `Godot --path . res://tests/scene_transition_test.tscn`；不能使用无渲染的 dummy headless 后端。
