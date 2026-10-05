# godot_aiworld

已迁移 `E:\GDWork\021-food-statement` 的世界时间轴系统。

- F5 运行时间轴演示，或打开 `scenes/time_system_demo.tscn` 后按 F6；Esc 暂停/继续。
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

