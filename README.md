# godot_aiworld

已迁移 `E:\GDWork\021-food-statement` 的世界时间轴系统。

- F5 运行时间轴演示，或打开 `scenes/time_system_demo.tscn` 后按 F6；Esc 暂停/继续。
- 核心服务：`WorldTime → WorldState → ActionController → PauseController`，已按顺序注册为 Autoload。
- 时间表：`resources/time/demo_timeline.tres`，支持在检查器中编辑循环长度、初始状态和事件。
- 接入说明：[时间系统](docs/time_system.md)；完整接口：[时间系统接口与游戏流程](docs/time_system_api_and_game_flow.md)。
- 行为测试：`Godot --headless --path . res://tests/time_system_test.tscn`。

演示使用原生 Godot 控件与纯色背景，支持滚动；时间规则与源项目一致。现有 `scenes/test/test.tscn` 可继续独立运行。

