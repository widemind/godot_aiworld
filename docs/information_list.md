# 信息列表

游戏中按 Esc 打开暂停菜单，点击「信息列表」进入。页面继续暂停世界，点击「返回暂停菜单 / Esc」或按 Esc 回到暂停菜单；再选择继续即可回到原来的探索或阅读界面。

顶部显示打开页面时的世界时间、当前星球及层级。`WorldState` 的 `in_space = true`、`player_location = &"space"` 或空 `planet_name` 表示太空，标题显示「太空」并隐藏星球层级。标题是打开时的快照。

信息条目仅显示获取的文本，直接读取 `TextDatabase.get_record_texts()`，按获取顺序从晚到早排列。相同正文再次获取会去重，保留首次获取的顺序。记录存放在 TextDatabase 中，顺序跨世界循环连续，场景切换和循环重置时保留；当前没有退出游戏后的磁盘存档。

新文本系统的片段可通过 `ui.show_text_piece(piece: TextPieces)` 展示；它调用 `TextDatabase.collect_text(piece)`，仅收集 `in_information_list = true` 的非空正文。若片段已经由 TextSelector 收集，再次展示也不会产生重复记录。只有正文呈现需求时，仍可用 `ui.show_text(content)`，此接口不会收集。

原探索入口的 `WorldState.record_information(content)` 保留兼容，内部将字符串转为可收集的 TextPieces 并交给 TextDatabase；`WorldState.get_collected_information()` 同样转接到数据库，不再维护独立记录。失败、空文本及循环回溯提示不会加入。

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
