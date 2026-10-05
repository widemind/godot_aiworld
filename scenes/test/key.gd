extends Area2D
class_name key

@onready var test: Node2D = $".."

var type:String
var front_loading:Dictionary
var activate_status:String = "inactive"
var create_status:String = "not_create"
var lock
var keyname:String


func _on_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			self.click_to_get_event()

func click_to_get_event():
	if activate_status == "inactive":
		self.activate_status = "active"
		self.scale = Vector2(0.3,0.3)
		self.position = Vector2(500,250-50*test.already_key_array.size())
		test.already_key_array.append(self)
	
		print(test.already_key_array)
	
