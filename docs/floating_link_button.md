# 浮动关联按钮

将 `scenes/ui/floating_link_button.tscn` 拖入 UI 即可使用。根节点 `FloatingLinkButton` 保存你摆放的位置和尺寸，只有内部原生 `Button` 在该位置附近轻微漂浮。移动关联目标时按钮不会跟着移动，只会更新两者之间的虚线。

## 绑定与交互

检查器的 **Connection → Target** 可直接拖入 `Node2D`、`Marker2D`、`Sprite2D` 或 `Control` 等节点。Node2D 连接局部原点，Control 连接中心；`target_offset` 在目标的局部坐标中调整连接位置。

```gdscript
@onready var action: FloatingLinkButton = $FloatingLinkButton

func _ready() -> void:
	action.text = "观察目标"
	action.bind_target($World/Planet)
	action.pressed.connect(_on_action_pressed)
	action.button_tint = Color("71d9ff")
	action.line_color = Color("71d9ffb3")

func _on_action_pressed() -> void:
	print("点击关联按钮")
```

`pressed`、`button_down`、`button_up` 从内部 Button 转发，也可直接在场景信号面板连接。`disabled` 控制禁用；`get_button()` 返回内部 Button，用于键盘焦点、快捷键和其他原生按钮功能。按钮已加入 `cursor_frame_target`，兼容项目的全局光标框选。

`bind_target(null)` 解除绑定。目标隐藏、释放、移出场景树，或处于另一个 Viewport 时，虚线自动隐藏，按钮仍可使用。绑定不同 CanvasLayer 的目标时，使用视口坐标转换，包含父级旋转 / 缩放和 Camera2D 画布变换。

## 参数

| 分组 | 参数 | 作用 |
| --- | --- | --- |
| Button | `text` / `disabled` | 显示文字与交互状态 |
| Button | `button_tint` | 按钮边框与文字色调，各交互状态自动调整 |
| Button | `background_color` | 按钮底色，支持透明度 |
| Button | `horizontal_padding` | 文字左右最小边距，默认各 10 |
| Button | `border_dot_radius` / `border_dot_spacing` | 直角矩形圆点虚线边框的点半径和间距 |
| Float | `float_amplitude` | X/Y 最大漂浮距离，默认 ±6 / ±4 个局部单位 |
| Float | `float_speed` / `float_phase` | 漂浮速度与起始相位，多个按钮可错开节奏 |
| Float | `float_enabled` | 开关漂浮，关闭后内部按钮回到原位 |
| Float | `preview_float_in_editor` | 在编辑器中预览漂浮，默认关闭以方便摆放 |
| Connection | `line_color` | 虚线色调与透明度，可与按钮颜色分别设置 |
| Connection | `line_width` / `dash_length` | 线宽与虚线段长度 |
| Connection | `button_gap` / `target_gap` | 按钮边缘和目标连接点处留空，默认 8 / 18 |
| Connection | `connection_enabled` | 只开关连线，不影响绑定与按钮 |

虚线从实际漂浮按钮的边缘出发，在按钮后方绘制，不覆盖文字、不接收鼠标事件。目标与按钮重叠或两端间距不足时不画线。为圆形目标设置 `target_gap` 为目标半径，可让连线停在目标边缘。

组件支持 Container 和锚点布局；根节点保持布局位置，内部按钮按根节点尺寸伸缩。虚线会延伸到根节点矩形之外，因此不要给其祖先启用 `clip_contents`，否则会裁剪关联线。颜色样式按实例创建，不会修改共享 Theme 或其他按钮。组件正常遵循父级暂停规则。

## 演示与测试

打开 `scenes/floating_link_button_demo.tscn` 按 F6。两个不同色调的按钮关联同一移动目标；拖拽圆点可以自由移动，点击“自动移动 / 停止”切换目标运动，点击“切换色调”验证运行时改色。点击浮动按钮可验证正常按钮信号。

`tests/floating_link_button_test.tscn` 检查跨 CanvasLayer 的目标连接、父级 / 相机变换、目标移动、漂浮范围、点击与禁用、布局尺寸、实例颜色隔离、Control 中心偏移及目标释放。
