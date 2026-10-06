# 星球探索 UI

主场景为 `scenes/ui/exploration/planet_exploration.tscn`，运行项目即可预览。中间地图区域留给后续地图，当前只实现示意图的白色 UI。已有全局 CRT 效果仍作用于画面。

顶部左侧星球名、中央 `第 N 轮 · MM:SS`（循环轮次在时间前）、右侧上/中/下层；底部三个按钮等宽、间距 16。使用锚点适应窗口尺寸，基准为项目现有 1920 × 1080。按钮加入 `cursor_frame_target`，复用 GameCursor 的四角平滑框选。

界面不单独标注世界类型，也不提供返回现实按钮或现实剩余时间。世界切换由剧情/交互对象调用 WorldJourney 接口。现实终点的失败提示排在已有文本之后，全部读完后回到虚拟世界最后一轮，保留进度并从零计时。普通虚拟循环终点仍进入下一轮；场景重载会读取常驻世界/失败状态。

按住不足 0.55 秒后松开是短按；达到阈值后松开是长按，每次只结算一次。按住时底边显示进度，移出按钮松开或暂停取消。每个按钮检查器中的 `long_press_seconds` 可调整阈值。

场景中的 `WaitController` 节点统一接管短按和长按等待，直接监听 UI 的等待请求。在星球、太空、没有配置地点选择器或使用自定义选择器时，等待均使用此节点，不经过地点 TextSelector。暂停、已有文本、其他行动执行中或世界已结束时不启动新等待。

短按等待立即打开节点的 `short_wait_text`，并以 `short_wait_flow_rate` 加速世界时间（默认 10 倍）。关闭等待文本时恢复等待前的倍率，即使还有文本排队，后续文本也按原倍率阅读。不会额外扣除固定秒数。滚轮阅读不结束等待，Esc 暂停时冻结计时，恢复后继续加速。虚拟循环终点、现实终点和世界切换都会结束等待；卸载探索场景或 UI 时也会清理加速，暂停期间的清理在恢复时还原倍率。

长按等待通过 ActionController 推进 `long_wait_seconds`（默认 60 秒），期间按时间顺序处理事件，成功后展示 `long_wait_text`；途中事件已打开文本时，完成提示排在它们之后。触及终点或失败不展示、也不收集完成提示。两种等待提示均为可编辑的 TextPieces，依据 `in_information_list` 收集，换行逐段显示；未填写有效正文时使用可关闭的内置提示。剧情可调用 `$WaitController.request_wait(long_press)` 请求等待，或 `stop_waiting()` 结束加速。

暂停菜单的「等待至循环结束」位于「继续 / Esc」下方、「信息列表」上方，由 WaitController 接收 `wait_until_loop_end_requested`。按钮复用 ExplorationActionButton，与探索三个按钮一样显示底边长按进度，默认按住至少 0.55 秒后松开触发；短按无效，移出按钮松开或关闭暂停菜单会取消按压。触发后关闭暂停，结束当前加速等待，清理旧显示队列，按时间顺序推进剩余世界事件；中途停止推进的事件或行动完成点不会提前结束此操作。到达终点后展示结束页面，全部文本读完才开始下一轮，时间归零、倍率恢复 1。已获取的信息和知识保留，等待途中事件收集的信息也保留。现实世界没有虚拟循环，此按钮不可用；已结束的循环也不能再次触发。剧情可调用 `wait_until_loop_end()` 使用同一流程，此接口只推进至终点。

自然到达循环终点和主动等待至终点均使用同一个结束页面：`TextModal/LoopEndPanel` 的文本框居于屏幕正中，`LoopEndShade` 将下层地图和 UI 变暗。普通探索仍使用原底部 TextPanel。结束正文与探索正文共用段落队列、点击/按键关闭、滚轮滚动、隐藏滚动条和输入拦截；重复及释放不跳段，Esc 暂停恢复保留正文与阅读位置。先前排队的普通正文按原顺序显示，然后进入结束页面；全部正文与结束段落读完后才进入下一轮。

文本框覆盖底部按钮，并以全屏透明输入层拦截地图及其他 UI。鼠标移动不关闭文本；按键、鼠标点击、触摸按下、手柄按钮或有效摇杆输入关闭文本。关闭用的输入及其重复、释放不会激活底层按钮。上下滚轮在屏幕任意位置滚动正文，隐藏滚动条。Esc 调用既有 PauseController，暂停菜单在文本之上，恢复后保留文本与阅读位置；阅读本身不暂停时钟。

`show_text()` 和 `show_text_piece()` 共用先进先出的显示队列。正在阅读时的新请求不会覆盖当前正文或改变滚动位置；关闭当前文本立即显示下一条，并从顶部开始。一轮关闭输入只处理一条，重复和释放不会跳过下一条；队列读完才显示行动按钮。暂停恢复保留队列。TextPieces 仍在请求时收集，排队不会改变获取顺序。

探索文本按显式换行逐段显示：例如 `第一段\n第二段\n第三段` 先显示第一段，点掉后显示第二段，再显示第三段。支持 LF、CRLF 和 CR，连续空行及纯空白段落不会生成空文本框；界面宽度导致的自动换行仍属于同一段。一次请求的全部段落保持连续顺序，后收到的事件文本排在它们之后。拆段仅作用于显示副本，TextDatabase 和信息列表仍保留一条完整原文，按原始换行排版。指南正文也保持原样。

每关闭一个段落都会发出 `text_closed`。关闭加速等待的首个文本框会恢复等待前倍率，其余段落和后续事件按原倍率阅读。回溯/失败提示同样拆段，全部段落读完后才进入下一轮或重试。

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
| 循环结束文本框及下层变暗程度 | `TextModal/LoopEndPanel`、其 TextMargin 及 `LoopEndShade` 的 Color |
| 暂停菜单等待至终点的长按阈值与进度 | `WaitUntilLoopEndButton` 的 Long Press Seconds 及其 HoldProgress |
| 暂停菜单排版 | `PauseModal` 下的 Shade、Panel、Column、Title、ResumeButton |
| 共用字体大小、颜色、边框、进度颜色 | `resources/ui/theme.tres` |

文本框和暂停层默认隐藏；需要调整时在场景树打开其可见性。Narrative 中有编辑器预览文本；运行时会由实际地点反馈替换。开始运行时自动恢复普通界面，所以可以保存弹窗预览状态。按钮进度也可临时显示，开始运行时自动隐藏。

所有探索 UI 控件、长按进度、主题、节点组和按钮信号连接都保存在场景或资源中。脚本只处理世界状态、输入与控件显示/数值，不创建控件、不重写布局，也不绘制按钮进度。

暂停菜单的五个按钮位于 `PauseModal/Panel/Column`：继续、等待至循环结束、信息列表、指南、返回主菜单。均为场景中的 Button 节点，高度 60，间距由 Column 的 Separation 调整。信息列表和指南已接入内置子页，Esc 回到暂停菜单并保持暂停，详见 [信息列表](information_list.md) 和 [指南 UI](guide_ui.md)。后三个按钮仍分别发出 `information_list_requested`、`guide_requested`、`main_menu_requested` 信号；返回主菜单尚待上层场景接入。

## 接入地图与地点内容

将 `planet_exploration_ui.tscn` 实例放在地图节点之后，地图输入节点也放在 UI 之前，使 UI 的 `_input` 优先拦截。GUI 控件由全屏输入层阻挡。自定义轮询 `Input.is_*` 的地图还须检查 `ui.is_text_open()` / 暂停状态，轮询不会经过事件拦截。

业务连接 `action_requested(action_id: StringName, long_press: bool)`，三个 ID 为 `observe`、`probe`、`wait`。调用 `ui.show_text(content)` 展示文本；`text_closed` 通知关闭；`set_actions_available()` 控制行动可用性。`set_location(planet_name, layer_name)` 可单独更新标题，时间自动监听 WorldTime。

`set_header_visible(false)` 隐藏顶部整栏，包括地点、层级、循环轮次、时间和边框；传入 true 重新显示。隐藏期间世界时间和地点数据仍更新，重新显示时立即呈现当前值。默认值可在检查器中设置 `header_visible`；不会影响暂停菜单、信息列表、指南或游戏计时。也可在节点 ready 之前调用接口：设定会在 ready 时应用。

```gdscript
$PlanetExplorationUI.set_header_visible(false) # 剧情中隐藏
$PlanetExplorationUI.set_header_visible(true)  # 探索时恢复
```

接入 TextSelector 时可调用 `ui.show_text_piece(selector.text_selection(action))`，展示 TextPieces 正文并依据 `in_information_list` 加入 TextDatabase。信息列表直接读取 `TextDatabase.get_record_texts()`；相同正文去重，只保留首次获取的顺序。`show_text()` 仍适用于不收集的纯文本提示。

现有入口脚本读取 WorldState 标记 `planet_name`、`planet_layer`，并以 `player_location` 在 `text_selectors` 字典中查找 TextSelector。检查器中为每个地点 ID 配置一个选择器；未配置的地点不执行观察/探测文本操作，等待仍由 WaitController 处理。地点移动仍使用既有 WorldAction / WorldState。

| 按钮操作 | TextSelector 操作名 | 文本列表 | 默认额外耗时 |
| --- | --- | --- | --- |
| 观察短按 | `observe` | `text_when_observed` | 0 秒 |
| 观察长按 | `observe_long` | `text_when_observed_long` | 5 秒 |
| 探测短按 | `detect` | `text_when_detected` | 10 秒 |
| 探测长按 | `detect_long` | `text_when_detected_long` | 30 秒 |
| 等待短按 | WaitController 接管 | 节点的 `short_wait_text` | 持续加速 |
| 等待长按 | WaitController 接管 | 节点的 `long_wait_text` | 节点的 `long_wait_seconds`，默认 60 秒 |

观察/探测的各列表按顺序选择首个满足条件的 TextPieces：当前秒数达到 `time_requirements`，且全部 `text_requirements` 标记存在并匹配。没有匹配内容时显示 TextDatabase 的默认文本。可以覆写 `special_text_selection()` 自定义选择；返回 null 会继续基本列表筛选。观察/探测耗时在入口的 `action_durations_seconds` 中独立配置，键使用上表的 TextSelector 操作名。等待文本不使用 TextSelector 的筛选条件，直接使用等待节点配置的提示。

观察/探测在 ActionController 成功完成后才按完成时的时间与世界状态选择和收集文本，因此操作期间发生的时间轴事件会影响选择结果。失败或触及循环终点不会收集普通反馈；终点仍展示回溯文本。短按等待直接展示节点的提示。文本仅在 `in_information_list = true` 时收集；探索界面按换行逐段展示，信息列表保留完整原文。

主场景的水星/上层、surface 地点的 TextSelector、观察/探测及等待文本、虚拟和现实各 10 分钟的计时及操作耗时均为界面演示配置，不代表已确定的剧情或关卡规则。替换 `timeline`、`real_timeline`、`text_selectors`、`action_durations_seconds` 及 WaitController 的配置即可接入正式内容。原时间演示场景保留。

## 验证

`tests/planet_exploration_ui_test.tscn` 通过 Viewport 的实际输入分发验证三按钮的长/短按、拖出取消、滚轮阅读、关闭不穿透地图/按钮、Esc 暂停恢复、地点条件匹配、循环重置、顶部显隐以及剧情接口切换后的失败重试。

```powershell
& '<Godot.exe>' --headless --path 'E:\GDWork\Into-the-Sun' res://tests/planet_exploration_ui_test.tscn
```
