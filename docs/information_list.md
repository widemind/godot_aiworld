# 信息列表

游戏中按 Esc 打开暂停菜单，点击「信息列表」进入。页面继续暂停世界，点击「返回暂停菜单 / Esc」或按 Esc 回到暂停菜单；再选择继续即可回到原来的探索或阅读界面。

顶部显示打开页面时的世界时间、当前星球及层级。`WorldState` 的 `in_space = true`、`player_location = &"space"` 或空 `planet_name` 表示太空，标题显示「太空」并隐藏星球层级。标题是打开时的快照。

信息条目仅显示获取的文本，按获取顺序从晚到早排列。相同文本再次获取也会产生一条记录。顺序跨世界循环连续，不依赖每轮归零的时钟。记录存放在 WorldState 中，场景切换和循环重置时保留；当前没有退出游戏后的磁盘存档。

探索入口在成功展示观察、探测和等待反馈时调用 `WorldState.record_information(content)`；失败、空文本及循环回溯提示不会加入。其他地图或剧情系统可以在确实获取文本后调用同一接口，再调用 `ui.show_text(content)` 显示正文。`show_text()` 本身只负责展示，避免临时提示被自动收集。`WorldState.get_collected_information()` 返回倒序文本副本。

页面复用探索界面的 Theme、全局 CRT 和鼠标框选。列表由 ScrollContainer 和 VBoxContainer 组成，纵向可以滚动但不显示滚动条；横向不滚动，正文自动换行。每个条目为 PanelContainer + RichTextLabel，启用 Fit Content，按行数增长。

| 调整对象 | 文件 / 节点 |
| --- | --- |
| 页面边界、标题、列表留白、返回按钮 | `scenes/ui/information/information_list.tscn` |
| 每个文本框及正文样式 | `scenes/ui/information/information_card.tscn` |
| 列表间距 | `InformationEntries` 的 Separation |
| 字号、白框、正文行距 | `resources/ui/planet_exploration_theme.tres` |
| 快照及条目更新逻辑 | `scripts/ui/information_list.gd` |

暂停菜单的接入位于 `PlanetExplorationUI`，保留 `information_list_requested` 信号，现会在打开内置子页后发出。返回不关闭原阅读文本、不改变阅读位置、不解除暂停。外部直接解除暂停时也会关闭子页。

`tests/planet_exploration_ui_test.tscn` 验证自动收集、倒序、文本框高度、隐藏滚动条、暂停滚动、Esc/按钮返回、太空标题、快照、空状态与跨循环保留。
