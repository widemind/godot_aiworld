# godot_aiworld

可复用浮动关联按钮：`scenes/ui/floating_link_button.tscn`。绑定可移动的 Node2D / Control，按钮在摆放位置附近漂浮，虚线实时连接目标，按钮和虚线颜色独立可调。演示：`scenes/floating_link_button_demo.tscn`（F6）；接入说明：[浮动关联按钮](docs/floating_link_button.md)。

全局像素溶解场景过渡已接入 `SceneTransition` Autoload。调用 `SceneTransition.change_scene_to_file(target_path)`，旧画面按方块溶解后直接露出新场景；保留全局光标和单次 CRT 处理。演示：打开 `scenes/scene_transition_demo_a.tscn` 按 F6。参数与接口见 [场景过渡](docs/scene_transition.md)。

已迁移 `E:\GDWork\021-food-statement` 的世界时间轴系统。

- F5 运行星球探索界面；时间轴演示可打开 `scenes/time_system_demo.tscn` 后按 F6。Esc 暂停/继续。
- 核心服务：`WorldTime → WorldState → ActionController → PauseController`，已按顺序注册为 Autoload。
- 时间表：`resources/time/demo_timeline.tres`，支持在检查器中编辑循环长度、初始状态和事件。
- 接入说明：[时间系统](docs/time_system.md)；完整接口：[时间系统接口与游戏流程](docs/time_system_api_and_game_flow.md)。
- 行为测试：`Godot --headless --path . res://tests/time_system_test.tscn`。

演示使用原生 Godot 控件与星空背景，支持滚动；时间规则与源项目一致。现有 `scenes/test/test.tscn` 可继续独立运行。

已迁移源项目的全局 CRT 后处理与静态星空背景，保留原有 Shader、材质参数及许可证。

- `GlobalCRT` 自动加载 `scenes/global_crt.tscn`，在 CanvasLayer 128 统一处理游戏画面和暂停界面；参数位于 `resources/rendering/global_crt.tres`。
- 将 `scenes/starfield_background.tscn` 拖入 2D 场景即可复用；`scenes/starfield_demo.tscn` 可用 F6 独立预览。
- 时间轴演示已接入星空，背景尺寸随演示窗口变化。
- 配置说明：[全局 CRT](docs/global_crt.md)；[星空背景](docs/starfield_background.md)。

已迁移全局鼠标指针：`GameCursor` 自动加载 `scenes/game_cursor.tscn`，隐藏系统指针，以圆点和四角平滑框选按钮。指针在 CanvasLayer 100 绘制，参与全局 CRT 处理，暂停时继续工作。

时间轴演示的所有按钮已接入。其他按钮可挂载 `scripts/ui/cursor_frame_button.gd`，或加入 `cursor_frame_target` 分组。参数与接入说明见 [游戏内鼠标指针](docs/game_cursor.md)。

已迁移星球探索 UI，主场景为 `scenes/planet_exploration.tscn`。共用界面在 `scenes/planet_exploration_ui.tscn`，字体、颜色和边框在 `resources/ui/planet_exploration_theme.tres`，布局和信号连接保留在场景中，可直接在 Godot 编辑器调整。

- 顶部星球名、世界时间及层级；底部观察、探测、等待三个按钮支持短按和长按进度。
- 短按等待打开文本并持续加速时间（默认 10 倍），关闭文本后恢复原倍率；入口节点的 `short_wait_flow_rate` 可调整倍率。
- 文本支持滚轮阅读、关闭输入不穿透、阅读时继续计时；Esc 暂停后保留阅读位置。
- 复用既有时间系统、全局指针和 CRT。中央地图区域与源项目一致，保留黑色占位。
- `resources/exploration/preview_timeline.tres` 与入口的 `responses` 是演示配置。暂停菜单已接入 [信息列表](docs/information_list.md) 和 [指南](docs/guide_ui.md)；指南教程在 `GuideText` 节点的 Text 属性中填写。“返回主菜单”发出信号供后续接入。
- 配置说明：[星球探索 UI](docs/planet_exploration_ui.md)。行为测试：`Godot --headless --path . res://tests/planet_exploration_ui_test.tscn`。

