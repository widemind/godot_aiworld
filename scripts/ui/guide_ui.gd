extends Control
## 指南正文保存在场景的 GuideText 节点中，由作者在编辑器填写。

signal closed

@onready var location_label: Label = %GuideLocation
@onready var clock_label: Label = %GuideClock
@onready var layer_label: Label = %GuideLayer
@onready var scroll: ScrollContainer = %GuideScroll
@onready var tutorial: Label = %GuideText


func _ready() -> void:
	hide()


func open(location: String, clock: String, layer: String) -> void:
	location_label.text = location if not location.strip_edges().is_empty() else "太空"
	clock_label.text = clock
	layer_label.text = "" if location_label.text == "太空" else layer
	scroll.scroll_vertical = 0
	show()
	get_viewport().gui_release_focus()


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()
