# 指南 UI

游戏中按 Esc 打开暂停菜单，点击「指南」进入。顶部是打开时的时间、当前星球及层级；在太空显示「太空」并隐藏层级。查看指南时世界继续保持暂停，按 Esc 返回暂停菜单，再按 Esc 或选择继续恢复游戏。返回保留原游戏文本及阅读位置。

## 填写教程

打开 `scenes/ui/guide/guide_ui.tscn`，选择 `Frame/Body/GuideScroll/GuideText`，在检查器的 **Text** 属性中填写教程正文。当前只保留「指南文本」作为占位；脚本不会替换正文。支持直接输入换行和空行，正文按纯文本显示，水平居中、顶部开始，自动换行。超过页面高度时可用滚轮滚动，隐藏滚动条。

`GuideUI` 默认隐藏。需要在编辑器预览时打开根节点的可见性，运行时会自动隐藏；暂停菜单按钮打开页面。共用探索 UI 中的 GuideUI 已开启 Editable Children，可在实例中调整节点。

页面沿用 `resources/ui/planet_exploration_theme.tres` 的黑底、白框、字体和颜色，全局 CRT 继续生效。正文行距可在 GuideText 的 Theme Overrides → Constants → Line Spacing 调整；正文留白在 Body 的 StyleBox 中调整。

入口脚本 `scripts/ui/planet_exploration_ui.gd` 接入指南按钮并管理返回。`scripts/ui/guide_ui.gd` 只处理标题快照、页面显示与滚动位置。保留 `guide_requested` 信号，在内置指南打开后发出。

`tests/planet_exploration_ui_test.tscn` 验证暂停菜单入口、标题快照、星球/太空、长教程滚动、居中与窄窗口换行、Esc 返回、原阅读位置保留，以及指南不加入信息记录。
