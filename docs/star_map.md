# 星图与行星地图

正式入口是 **星图枢纽** `scenes/map/map.tscn`（`project.godot` 的 `run/main_scene`）。
星图本身只是空的航道：玩家在轨道间移动、扫描、走到某颗行星旁边按 E 进入。
**每颗行星是独立场景**（`scenes/planets/*.tscn`，基类 `scripts/map/planet_room.gd`），
有各自的地形、建筑、障碍与谜题，因此「进入行星」是真的换了一张地图。

## 场景结构

| 场景 | 内容 |
| --- | --- |
| `scenes/map/map.tscn` | 航道枢纽：四颗行星、扫描、进入判定、知识地图与结局覆盖层 |
| `scenes/planets/planet_earth.tscn` | **地球 1 层：赤阳之塔所在地**、学校/发电机/发电厂/居民楼/政府 |
| `scenes/planets/planet_mercury.tscn` | 水星 1 层：太阳观测塔基座、水流沟壑、通往 2 层的通道 |
| `scenes/planets/planet_mercury2.tscn` | 水星 2 层：天文台、语言研究所（隐藏建筑，需扫描） |
| `scenes/planets/planet_mercury3.tscn` | 水星 3 层：核心通道，11 分钟前过不去 |
| `scenes/planets/planet_mercury4.tscn` | 水星 4 层：水星 AI Mercury |
| `scenes/planets/planet_mars.tscn` | 火星 1 层：算力中心（Mars）、迷宫岩壁、向下的洞口 |
| `scenes/planets/planet_mars2.tscn` | 火星 2 层：洞穴、发电厂、制造厂（隐藏建筑） |
| `scenes/planets/planet_sun.tscn` | 太阳外层：发送台，终极太阳语在这里生效 |

## 房间 HUD

每个行星房间自带一套 HUD（`PlanetRoom._build_hud()`），左上角显示**行星名 · 层**
（`display_name` / `layer_name`，例如「水星 · 2 层」），中间是世界时间与轮次。
底部按钮栏：

| 按钮 | 出现条件 |
| --- | --- |
| 上一层 / 下一层 | **只有多层的行星才有**（水星 4 层、火星 2 层）；地球与太阳单层，整组隐藏。不能走时变灰 |
| **返回宇宙地图** | 总是出现，直接回航道（不必走回出口） |
| 扫描（Tab） | 总是出现 |
| 知识地图（K） | 总是出现 |
| 电码键 / 等待键 / 发送 | **只在能发送的地方出现**（见下） |

### 摩斯按钮什么时候出现

设计稿要求摩斯输入是「在特定地点对着特定对象说话」，因此这三个按钮默认隐藏
（`morse_enabled = false`），只在两种情况下打开：

| 地点 | 条件 |
| --- | --- |
| 太阳外层 | 常驻打开（那里就是发送台） |
| 地球 1 层 · 赤阳之塔 | 塔被灯框住（`tower_lit()`）**且**玩家走到塔的交互范围内；靠近时会出现「进入赤阳之塔」按钮，塔内的发送台里同样有电码键 |

行星地表（水星、火星、地球未靠近塔时）看不到这三个按钮，避免玩家在无处可发的地方乱按。
开关由 `PlanetRoom.set_morse_available()` 控制，切走时会清空未发送的输入。

## 行星房间基类

`scripts/map/planet_room.gd` 提供所有星球共用的东西，子类只实现 `_build_room()`：

| 能力 | 接口 |
| --- | --- |
| 玩家移动与四周边界墙 | `_build_boundaries()` 自动加 4 面墙 |
| 放建筑 / 放障碍 | `add_building(...)` / `add_obstacle(rect, layer)` |
| 视野经济与扫描 | `vision`（`MapVision`）+ `scan()` |
| 摩斯电码输入台 | `press_morse()` / `release_morse()` / `separator_morse()` / `send_morse()` |
| 建筑交互与观察文本 | `_handle_building_interaction()` / `_observe_text()` 覆写 |
| 自带 HUD | 顶部地点/轮次/时间、底部扫描/电码/等待/发送/知识地图 |
| 知识地图与结局 | `toggle_knowledge_map()` / `show_ending()`（每个房间各有一份实例） |
| 返回航道 | `request_exit()`，走到 `exit_position` 附近按 E 或直接调用 |

## 视野经济

设计稿原文是「玩家的交互范围等同于视野范围」与「扫描会让玩家短暂获得大于视野范围的区域的视野，
浮现建筑，但扫描时间结束后在视野范围内的建筑又会消失」。实现放在 `scripts/map/map_vision.gd`，
只做几何判定，不碰节点：

| 状态 | 半径 | 说明 |
| --- | --- | --- |
| 基础视野 | `base_vision_radius`（房间默认 420） | 玩家周围始终可见的范围 |
| 扫描视野 | `scan_vision_radius`（默认 1100） | 扫描后 `scan_duration`（1.6s）内生效 |
| 点亮视野 | 每个建筑自己的 `lit_vision_radius` | 点亮后在其周围持续提供视野 |

## 建筑与发电机

`scripts/map/map_building.gd` 挂在 `Area2D` 上并加入 `map_building` 分组（**必须加组**，
星图与房间都靠它发现建筑）。`kind` 决定名称与观察文本，`has_generator` 决定能否点亮，
`visible_in_base_vision = false` 表示隐藏建筑（只有扫描才显形）。
点亮会写入 `lit_<id>` 标记与知识，并提供固定视野。

## 赤阳之塔（在地球）

设计稿「知识地图」把赤阳之塔挂在**地球**节点下，因此塔在地球 1 层的灯网中间。

| 设计稿 | 实现 |
| --- | --- |
| 只在被观察时移动 | `SunTower.tick(delta, 当前视野半径)`：离开视野就 `_disappear()`，再进视野重现 |
| 与玩家保持视野范围外的距离 | `preferred_distance`，超过 1.6 倍才追近 |
| 被视野照射到会停止移动 | 进入已点亮建筑的 `stop_light_radius`（地球房间设 340）即停止 |
| 进入方法：把塔框进点亮的建筑范围内 | 塔自身点不亮（`has_generator = false`）；点亮 ≥3 座建筑并把灯铺到塔身（`tower_lit()`）后，记录 `tower_lit` 知识，塔内开启 |

## 10 分钟太阳循环与地形变换

`resources/time/timeline.tres` 是正式时间轴（1200 秒一轮）：

| 时刻 | 事件 | 效果 |
| --- | --- | --- |
| 600s | `sun_brighten` | 太阳增亮；太阳观测塔停转（之前给水流方向） |
| 660s | `mercury_boil` | 水星 1 层变换（不消失，观察文本改写） |
| 660s | `mercury_core_open`（优先级 1） | 水星 3 层地下裂开，可以深入 4 层 |
| 1080s | `sun_flare` | 太阳暴晕 |
| 1200s | 循环终点 | 进入下一轮 |

`scripts/map/terrain_state.gd` 把这些事件翻译成可用性判定与文本。

## AI 对话

`scripts/map/map_dialogue.gd` 保存三个 AI 与观测记录的台词，按 `requires_knowledge` 分层，
`grant` 授予下一条知识；说过的台词记入知识跨轮保留。对话不消耗时间、不改世界标记。

| 说话人 | 所在地 | 授予链 |
| --- | --- | --- |
| 水星 AI Mercury | 水星 4 层核心 | `met_mercury_ai` → `mercury_is_simulation` → `simulation_error_time` |
| 火星 AI Mars | 火星 1 层算力中心 | `met_mars_ai` → `human_plan_ai` → `plan_may_terminate` |
| 地球 AI | 地球 1 层居民楼 | `met_earth_ai` → `earth_is_one_grid` → `earth_needs_power` |
| 天文台观测记录 | 水星 2 层天文台 | `water_flow_south` → `know_awaken`（太阳语：苏醒） |

## 赤阳之塔内部与结局

`scripts/ui/tower_room.gd`。门槛是**先集齐三段太阳语料**（`SunTower.room_ready()`），
进入后在塔内依次打出三段语料：第一段给 `tower_location`，第二段给 `tower_build_reason`，
三段齐了学会 `know_ultimate`。最后在太阳外层发送终极太阳语（赤阳/塔/人类/回归），
写入 `ultimate_sent` 并弹出 `scripts/ui/ending_panel.gd` 的结局
（文本按是否已知 `mercury_is_simulation` 分两种）。

## 怎么进入行星

宇宙地图**不需要玩家移动**：相机固定在星图中心并按窗口缩放，整张图一屏放得下（`_fit_camera()`），
航道上的玩家节点隐藏。操作是**「选中 → 进入」**：

| 操作 | 效果 |
| --- | --- |
| ← / → 或「上一颗」「下一颗」按钮 | 切换选中的行星（地球 → 水星 → 火星 → 太阳 循环） |
| R 或「进入 X」按钮 | 进入当前选中的行星 |
| Tab 或「扫描」按钮 | 发出扫描波形，并在右侧列出结果 |

选中的行星会显示一圈高亮，底部状态栏与「进入」按钮都写着目标名字。
水星会记住你上次所在的层，进入时直接回到那一层（前提是那一层仍然允许进入）。

## 扫描波形与结果

`StarMap.scan()` 做三件事：

1. **波形**：`planets/ScanWave` 是一个 64 段圆环 `Line2D`，从星图中心按 `scan_duration`
   扩张到 `scan_vision_radius`，半透明青色描边；结束后自动隐藏。
2. **浮现**：波前半径扫到哪颗行星，那颗就闪一下（`_flash_planet()` 用 tween 提亮再回落），
   并且不会再闪第二次。
3. **结果**：`UI/ScanResult` 面板列出每颗行星一行：

```
扫描结果
· 地球　相距 780　可进入 1 层　赤阳之塔的位置、塔已被灯框住
· 水星　相距 480　可进入 4 层　水流方向、水星核心
· 火星　相距 700　可进入 2 层　无已知线索
· 太阳　相距 560　可进入 1 层　终极太阳语
```

「可进入 N 层」来自 `PLANET_ROOMS`，「已知线索」由 `_planet_knowledge_hint()` 依据
`WorldState` 的知识与标记生成——扫描因此不只是视觉效果，而是把当前进度摊在你面前。

## 行星内的层级按钮

每个行星房间的 HUD 底部都有 **「上一层」/「下一层」** 按钮（`PlanetRoom.request_layer_step()`），
请求交给星图判定，因此规则集中在一处：

| 行星 | 规则 |
| --- | --- |
| 水星 | 1 ↔ 2 ↔ 3 自由；3 → 4 需要核心露出（11 分钟后）或已接触过 Mercury |
| 火星 | 1 → 2 不能直接走：必须站在 1 层洞口（`mars_hole_down`）200 像素内 |
| 地球 / 太阳 | 只有一层，**上下层按钮整组隐藏**（`PLANET_ROOMS` 里只有一个场景时 `set_layer_buttons_visible(false)`） |

不能走时按钮会**变灰**（`PlanetRoom.set_layer_availability()`），按下也会给出原因文本。

## 操作

| 操作 | 键 / 控件 |
| --- | --- |
| 换目标 | ← / →，或「上一颗」「下一颗」 |
| 进入行星 | R 或「进入 X」按钮 |
| 扫描 | Tab（`ui_select`）或「扫描」按钮 |
| 返回航道 | 房间内走到出口按 E |
| 交互 | E（`ui_accept`）或点击 |
| 上下层 | 房间 HUD 的「上一层」「下一层」按钮 |
| 电码输入 | 「电码键」短按 = 点，长按 = 划 |
| 手动分段 | 「等待键」 |
| 发送 | 「发送」按钮 |
| 知识地图 | K，「知识地图」按钮，或 Esc 关闭 |
| 暂停 | Esc（`pause_game`） |
| 移动（房间内） | WASD |

## 验证

```powershell
& '<Godot.exe>' --headless --path '<项目目录>' res://test/tests/star_map_test.tscn
& '<Godot.exe>' --headless --path '<项目目录>' res://test/tests/star_map_scene_test.tscn
& '<Godot.exe>' --headless --path '<项目目录>' res://test/tests/terrain_dialogue_test.tscn
```

`star_map_scene_test.tscn` 加载整棵 `map.tscn`，逐一进入四颗行星、检查每个房间自带 HUD 与建筑、
扫描、返回航道，并验证知识地图开/关与 Esc 关闭、结局覆盖层；
`star_map_test.tscn` 覆盖视野三态、隐藏建筑、发电机点亮、赤阳之塔出现/追踪/照停/消失、
**地球灯谜**（离得远不算框住、灯铺到塔身才算）与火星迷宫障碍；
`terrain_dialogue_test.tscn` 覆盖 10/11/18 分钟阶段与全部台词的解锁链。

## 尚未接入的部分

- 水星各层是独立房间，但层与层之间目前靠返回航道再进入下一层，没有做「层内楼梯」的连续场景。
- 死亡触发太阳语 `death_clear` 没有死亡/重试流程，只能通过观察文本与对话学到。
- 知识树是分层连线的节点图，节点不能点击展开详情。
- 各行星房间的地形目前用简单多边形（房间自带绘制）与矩形障碍表示，没有美术资源。

主场景为 `scenes/map/map.tscn`（`project.godot` 的 `run/main_scene`）。星图是正式入口：首次进入时安装 `resources/time/timeline.tres`（虚拟世界）与 `resources/time/real_timeline.tres`（现实世界）并开始第一轮，之后只读取常驻的 `WorldTime` / `WorldState`，不另建时钟。
