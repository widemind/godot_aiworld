extends Control
## 暂停菜单子页。标题和条目在打开时快照，返回后仍然暂停。

signal closed

const CARD_SCENE: PackedScene = preload("res://scenes/ui/information/information_card.tscn")

@onready var location_label: Label = %InformationLocation
@onready var clock_label: Label = %InformationClock
@onready var layer_label: Label = %InformationLayer
@onready var scroll: ScrollContainer = %InformationScroll
@onready var entries: VBoxContainer = %InformationEntries
@onready var empty_label: Label = %EmptyInformation
@onready var back_button: Button = %InformationBack


func _ready() -> void:
	hide()


func open(location: String, clock: String, layer: String, texts: Array[String]) -> void:
	location_label.text = location if not location.strip_edges().is_empty() else "太空"
	clock_label.text = clock
	layer_label.text = "" if location_label.text == "太空" else layer
	for child in entries.get_children():
		if child == empty_label:
			continue
		entries.remove_child(child)
		child.queue_free()
	empty_label.visible = texts.is_empty()
	for content in texts:
		var card := CARD_SCENE.instantiate() as PanelContainer
		card.get_node("Text").text = content
		entries.add_child(card)
	scroll.scroll_vertical = 0
	show()
	back_button.grab_focus()


func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()
