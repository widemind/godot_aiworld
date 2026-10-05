class_name PlanetExplorationUI
extends Control
## 可直接叠加到地图上。地图的 _input 节点须放在此 UI 之前。

const InformationPage = preload("res://scripts/ui/information_list.gd")
const GuidePage = preload("res://scripts/ui/guide_ui.gd")

signal action_requested(action_id: StringName, long_press: bool)
signal text_closed
## 由上层场景接入对应页面；按钮自身保持世界暂停。
signal information_list_requested
signal guide_requested
signal main_menu_requested

@export_range(10, 200, 1) var wheel_scroll_pixels: int = 72

@onready var planet_label: Label = %PlanetLabel
@onready var clock_label: Label = %ClockLabel
@onready var layer_label: Label = %LayerLabel
@onready var action_bar: PanelContainer = %ActionBar
@onready var text_modal: Control = %TextModal
@onready var narrative: RichTextLabel = %Narrative
@onready var pause_modal: Control = %PauseModal
@onready var information_list: InformationPage = %InformationList
@onready var guide: GuidePage = %GuideUI
@onready var buttons: Array[ExplorationActionButton] = [%ObserveButton, %ProbeButton, %WaitButton]

var _actions_available: bool = true
var _dismissal_event: InputEvent


func _ready() -> void:
	# 编辑器里可以临时显示弹窗排版；运行时从正常探索界面开始。
	text_modal.hide()
	action_bar.show()
	WorldTime.time_changed.connect(_on_time_changed)
	PauseController.pause_changed.connect(_on_pause_changed)
	_on_time_changed(0.0, WorldTime.elapsed_seconds)
	_on_pause_changed(get_tree().paused)


func _on_resume_pressed() -> void:
	PauseController.set_paused(false)


func _on_information_list_pressed() -> void:
	if not get_tree().paused:
		return
	pause_modal.hide()
	information_list.open(planet_label.text, clock_label.text, layer_label.text, WorldState.get_collected_information())
	information_list_requested.emit()


func _on_information_list_closed() -> void:
	pause_modal.visible = get_tree().paused
	if get_tree().paused:
		%InformationListButton.grab_focus()


func _on_guide_pressed() -> void:
	if not get_tree().paused:
		return
	pause_modal.hide()
	guide.open(planet_label.text, clock_label.text, layer_label.text)
	guide_requested.emit()


func _on_guide_closed() -> void:
	pause_modal.visible = get_tree().paused
	if get_tree().paused:
		%GuideButton.grab_focus()


func _on_main_menu_pressed() -> void:
	main_menu_requested.emit()


func set_location(planet_name: String, layer_name: String) -> void:
	planet_label.text = planet_name
	layer_label.text = layer_name


func set_actions_available(available: bool) -> void:
	_actions_available = available
	_refresh_buttons()


func show_text(content: String) -> void:
	for button in buttons:
		button.cancel_hold()
	narrative.text = content
	narrative.get_v_scroll_bar().value = 0.0
	text_modal.show()
	# 让文本框的底色覆盖按钮；隐藏按钮也避免焦点与指针继续命中。
	action_bar.hide()
	get_viewport().gui_release_focus()
	_refresh_buttons()


func close_text() -> void:
	if not text_modal.visible:
		return
	text_modal.hide()
	action_bar.show()
	_refresh_buttons()
	text_closed.emit()


func is_text_open() -> bool:
	return text_modal.visible


func _input(event: InputEvent) -> void:
	if information_list.visible or guide.visible:
		var page: Variant = guide if guide.visible else information_list
		# 子页的 Esc 只返回菜单，不能交给 PauseController 解除暂停。
		if event.is_action("pause_game"):
			get_viewport().set_input_as_handled()
			if event.is_pressed() and not event.is_echo():
				_dismissal_event = event
				page.close()
			return
		# 指针/触摸交给 ScrollContainer 和返回按钮；其余输入不穿透地图。
		if not event is InputEventMouse and not event is InputEventScreenTouch and not event is InputEventScreenDrag:
			get_viewport().set_input_as_handled()
			if event.is_action_pressed("ui_accept") and not event.is_echo():
				_dismissal_event = event
				page.close()
		return
	if _dismissal_event != null and event.is_match(_dismissal_event):
		get_viewport().set_input_as_handled()
		if not event.is_pressed():
			_dismissal_event = null
		return
	# Esc 始终留给现有 PauseController；暂停菜单在文本框之上。
	if event is InputEventKey and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		return
	if event is InputEventAction and event.action == &"pause_game":
		return
	if get_tree().paused or not is_text_open():
		return
	get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var direction := -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			narrative.get_v_scroll_bar().value += direction * wheel_scroll_pixels * event.factor
		return
	# 鼠标移动和按键释放只拦截；避免打开文本的同次释放将文本关闭。
	var dismiss := event.is_pressed() and not event.is_echo()
	if event is InputEventJoypadMotion:
		dismiss = absf(event.axis_value) > 0.5
	if dismiss:
		_dismissal_event = event if not event is InputEventJoypadMotion else null
		close_text()


func _on_action_requested(action_id: StringName, long_press: bool) -> void:
	if _actions_available and not is_text_open() and not get_tree().paused:
		action_requested.emit(action_id, long_press)


func _on_time_changed(_previous: float, current: float) -> void:
	var seconds := int(current)
	clock_label.text = "%02d:%02d" % [seconds / 60, seconds % 60]


func _on_pause_changed(paused: bool) -> void:
	if not paused:
		information_list.close()
		guide.close()
	pause_modal.visible = paused and not information_list.visible and not guide.visible
	if paused:
		for button in buttons:
			button.cancel_hold()
	_refresh_buttons()


func _refresh_buttons() -> void:
	for button in buttons:
		button.disabled = not _actions_available or is_text_open() or get_tree().paused
