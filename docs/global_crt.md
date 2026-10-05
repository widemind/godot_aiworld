# 全局 CRT 后处理

来源：[CRT Visual Shader godot 4.0+](https://godotshaders.com/shader/crt-visual-shader-godot-4-0/)，作者 Lord0Sanz / PROJEKT SANS STUDIOS。MIT 许可见 `shaders/crt.LICENSE`。

`GlobalCRT` 自动加载 `scenes/global_crt.tscn`，在 CanvasLayer 128 对最终画面做一次全屏处理。ScreenCopy 先复制完整视口，ScreenEffect 再采样复制的画面。背景、游戏场景、菜单、暂停界面及其他 layer 小于 128 的 CanvasLayer 都会参与处理，切换主场景后效果继续存在。

全屏层忽略鼠标事件，始终处理，包括暂停期间。未来游戏画布应使用小于 128 的 layer，以纳入这一最终处理层。

参数在 `resources/rendering/global_crt.tres` 的 Shader Parameters 中调整。本项目完整保留 `021-food-statement` 当前材质配置，而非 Shader 的原始默认值：全屏 `overlay` 开启、采样栅格 `resolution` 为 1080×720、`pixelate` 和 `roll` 关闭，并启用扫描线、RGB 栅格、色差、噪点、弯曲边缘、暗角及 VHS 褪色。Shader 保留源项目的 `unshaded`，让最终画面不再次受 2D 灯光影响。

这是图像后处理，按钮输入区域仍使用原有布局坐标。`warp_amount` 和 `distort_intensity` 控制画面形变；`pixelate` 控制像素化；`roll` 控制滚动；其余效果也可在材质中逐项调整。
