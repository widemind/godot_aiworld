# 星球探索 UI

主场景为 `scenes/ui/exploration/planet_exploration.tscn`，运行项目即可预览。中间地图区域留给后续地图，当前只实现示意图的白色 UI。已有全局 CRT 效果仍作用于画面。

顶部左侧星球名、中央 `第 N 轮 · MM:SS`（循环轮次在时间前）、右侧上/中/下层；底部三个按钮等宽、间距 16。使用锚点适应窗口尺寸，基准为项目现有 1920 × 1080。按钮加入 `cursor_frame_target`，复用 GameCursor 的四角平滑框选。

界面不单独标注世界类型，也不提供返回现实按钮或现实剩余时间。世界切换由剧情/交互对象调用 WorldJourney 接口。现实终点的失败提示排在已有文本之后，全部读完后回到虚拟世界最后一轮，保留进度并从零计时。普通虚拟循环终点仍进入下一轮；场景重载会读取常驻世界/失败状态。

按住不足 0.55 秒后松开是短按；达到阈值后松开是长按，每次只结算一次。按住时底边显示进度，移出按钮松开或暂停取消。每个按钮检查器中的 `long_press_seconds` 可调整阈值。

短按等待立即打开匹配的地点文本，并以入口节点的 `short_wait_flow_rate` 加速世界时间（默认 10 倍）。关闭等待文本时恢复等待前的倍率，即使还有文本排队，后续文本也按原倍率阅读。不会额外扣除固定秒数；短按等待响应的 `duration_seconds` 不参与结算。滚轮阅读不结束等待，Esc 暂停时冻结计时，恢复后继续加速。循环终点会结束等待，并将回溯文本加入队列；卸载探索场景时也会清理加速，暂停期间的清理在恢复时还原倍率。长按等待仍按配置耗时结算。

文本框覆盖底部按钮，并以全屏透明输入层拦截地图及其他 UI。鼠标移动不关闭文本；按键、鼠标点击、触摸按下、手柄按钮或有效摇杆输入关闭文本。关闭用的输入及其重复、释放不会激活底层按钮。上下滚轮在屏幕任意位置滚动正文，隐藏滚动条。Esc 调用既有 PauseController，暂停菜单在文本之上，恢复后保留文本与阅读位置；阅读本身不暂停时钟。

`show_text()` 和 `show_text_piece()` 共用先进先出的显示队列。正在阅读时的新请求不会覆盖当前正文或改变滚动位置；关闭当前文本立即显示下一条，并从顶部开始。一轮关闭输入只处理一条，重复和释放不会跳过下一条；队列读完才显示行动按钮。暂停恢复保留队列。TextPieces 仍在请求时收集，排队不会改变获取顺序。

`text_closed` 每关闭一条文本均发出，有下一条时通知发出前已显示下一条，可通过 `is_text_open()` 判断是否读完全部文本。`clear_texts()` 清理当前及排队文本，用于新循环等主动清理。循环终点冻结世界后，读完当前、排队文本及回溯提示才开始下一轮；新循环不保留旧队列。

## 在编辑器中调整 UI

直接打开 `scenes/ui/exploration/planet_exploration_ui.tscn` 编辑共用界面。主场景中的 `PlanetExplorationUI` 已开启 Editable Children，也可在主场景中展开并调整子节点，修改会作为该实例的覆盖值保存。

| 调整对象 | 编辑节点或资源 |
| --- | --- |
| 顶部边框的位置、宽高 | `Header` 的 Layout / Anchors / Offsets |
| 星球名、时间、层级 | `Header/Content` 下的三个 Label |
| 顶部整栏默认显隐 | 根节点检查器的 `header_visible`，运行时调用 `set_header_visible()` |
| 底部整体位置与高度 | `ActionBar` 的 Layout |
| 按钮间距 | `ActionBar/Buttons` 的 Theme Overrides → Constants → Separation |
| 按钮文字和长按阈值 | 三个 Button 的 Text 和 Long Press Seconds |
| 长按进度的位置、高度 | 各 Button 下的 `HoldProgress`（ProgressBar） |
| 文本框位置、大小与留白 | `TextModal/TextPanel` 和 `TextMargin` |
| 暂停菜单排版 | `PauseModal` 下的 Shade、Panel、Column、Title、ResumeButton |
| 共用字体大小、颜色、边框、进度颜色 | `resources/ui/theme.tres` |

文本框和暂停层默认隐藏；需要调整时在场景树打开其可见性。Narrative 中有编辑器预览文本；运行时会由实际地点反馈替换。开始运行时自动恢复普通界面，所以可以保存弹窗预览状态。按钮进度也可临时显示，开始运行时自动隐藏。

所有探索 UI 控件、长按进度、主题、节点组和按钮信号连接都保存在场景或资源中。脚本只处理世界状态、输入与控件显示/数值，不创建控件、不重写布局，也不绘制按钮进度。

暂停菜单的四个按钮位于 `PauseModal/Panel/Column`：继续、信息列表、指南、返回主菜单。均为场景中的 Button 节点，高度 60，间距由 Column 的 Separation 调整。信息列表和指南已接入内置子页，Esc 回到暂停菜单并保持暂停，详见 [信息列表](information_list.md) 和 [指南 UI](guide_ui.md)。后三个按钮仍分别发出 `information_list_requested`、`guide_requested`、`main_menu_requested` 信号；返回主菜单尚待上层场景接入。

## 接入地图与地点内容

将 `planet_exploration_ui.tscn` 实例放在地图节点之后，地图输入节点也放在 UI 之前，使 UI 的 `_input` 优先拦截。GUI 控件由全屏输入层阻挡。自定义轮询 `Input.is_*` 的地图还须检查 `ui.is_text_open()` / 暂停状态，轮询不会经过事件拦截。

业务连接 `action_requested(action_id: StringName, long_press: bool)`，三个 ID 为 `observe`、`probe`、`wait`。调用 `ui.show_text(content)` 展示文本；`text_closed` 通知关闭；`set_actions_available()` 控制行动可用性。`set_location(planet_name, layer_name)` 可单独更新标题，时间自动监听 WorldTime。

`set_header_visible(false)` 隐藏顶部整栏，包括地点、层级、循环轮次、时间和边框；传入 true 重新显示。隐藏期间世界时间和地点数据仍更新，重新显示时立即呈现当前值。默认值可在检查器中设置 `header_visible`；不会影响暂停菜单、信息列表、指南或游戏计时。也可在节点 ready 之前调用接口：设定会在 ready 时应用。

```gdscript
$PlanetExplorationUI.set_header_visible(false) # 剧情中隐藏
$PlanetExplorationUI.set_header_visible(true)  # 探索时恢复
```

接入 TextSelector 时可调用 `ui.show_text_piece(selector.text_selection(action))`，展示 TextPieces 正文并依据 `in_information_list` 加入 TextDatabase。信息列表直接读取 `TextDatabase.get_record_texts()`；相同正文去重，只保留首次获取的顺序。`show_text()` 仍适用于不收集的纯文本提示。

现有入口脚本读取 WorldState 标记 `planet_name`、`planet_layer`，并使用 `player_location` 匹配内容。地点移动仍使用既有 WorldAction / WorldState，不要另建时钟。`responses` 数组中的 ExplorationResponse 资源可配置地点 ID、操作、长短按、世界标记条件、文本和额外耗时；按数组顺序选择首个匹配规则，未匹配不展示文本。结果在 ActionController 成功完成后展示，触及循环终点则展示回溯文本。

主场景的水星/上层、surface 地点、六条响应、虚拟和现实各 10 分钟的计时及操作耗时均为界面演示配置，不代表已确定的剧情或关卡规则。替换 `timeline`、`real_timeline` 与 `responses` 即可接入正式内容。原时间演示场景保留。

## 验证

`tests/planet_exploration_ui_test.tscn` 通过 Viewport 的实际输入分发验证三按钮的长/短按、拖出取消、滚轮阅读、关闭不穿透地图/按钮、Esc 暂停恢复、地点条件匹配、循环重置、顶部显隐以及剧情接口切换后的失败重试。

```powershell
& '<Godot.exe>' --headless --path 'E:\GDWork\Into-the-Sun' res://tests/planet_exploration_ui_test.tscn
```
