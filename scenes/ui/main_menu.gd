extends Control
## Main menu. Three buttons route to the slot menu (new / load) or quit.

const SLOT_MENU_PATH: String = "res://scenes/ui/SaveSlotMenu.tscn"

@onready var _start_button: Button = $CenterContainer/VBoxContainer/StartNewGameButton
@onready var _load_button: Button = $CenterContainer/VBoxContainer/LoadGameButton
@onready var _exit_button: Button = $CenterContainer/VBoxContainer/ExitButton


func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_load_button.pressed.connect(_on_load_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)


func _on_start_pressed() -> void:
	SaveManager.slot_menu_mode = "new"
	get_tree().change_scene_to_file(SLOT_MENU_PATH)


func _on_load_pressed() -> void:
	SaveManager.slot_menu_mode = "load"
	get_tree().change_scene_to_file(SLOT_MENU_PATH)


func _on_exit_pressed() -> void:
	get_tree().quit()
