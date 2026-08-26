extends Control
## Save-slot selection. Reused for both "new" and "load" via
## SaveManager.slot_menu_mode. All file I/O goes through SaveManager.

const MAIN_MENU_PATH: String = "res://scenes/ui/MainMenu.tscn"

@onready var _mode_label: Label = $CenterContainer/VBoxContainer/ModeLabel
@onready var _back_button: Button = $CenterContainer/VBoxContainer/BackButton
@onready var _confirm_dialog: ConfirmationDialog = $ConfirmOverwriteDialog

var _slot_buttons: Array[Button] = []
var _pending_overwrite_slot: int = -1


func _ready() -> void:
	_slot_buttons = [
		$CenterContainer/VBoxContainer/Slot1Button,
		$CenterContainer/VBoxContainer/Slot2Button,
		$CenterContainer/VBoxContainer/Slot3Button,
	]
	for i in _slot_buttons.size():
		var slot_id := i + 1
		_slot_buttons[i].pressed.connect(_on_slot_pressed.bind(slot_id))
	_back_button.pressed.connect(_on_back_pressed)
	_confirm_dialog.confirmed.connect(_on_overwrite_confirmed)
	_refresh()


func _refresh() -> void:
	var is_new := SaveManager.slot_menu_mode == "new"
	_mode_label.text = "Start New Game — choose a slot" if is_new else "Load Game — choose a slot"
	for i in _slot_buttons.size():
		var slot_id := i + 1
		var btn := _slot_buttons[i]
		var summary := SaveManager.get_save_summary(slot_id)
		btn.disabled = false
		var exists: bool = summary["exists"]
		var valid: bool = summary["valid"]
		if not exists or not valid:
			# Empty (or corrupt) slot.
			if exists and not valid:
				btn.text = "Slot %d\n[corrupt save]" % slot_id
			else:
				btn.text = "Slot %d\nEmpty" % slot_id
			# In load mode an empty/corrupt slot cannot be read.
			if not is_new:
				btn.disabled = true
		else:
			btn.text = "Slot %d\nLast saved: %s\nScene: %s\nPlay time: %s" % [
				slot_id,
				summary["last_saved_at"],
				_scene_name(summary["current_scene"]),
				SaveManager.format_play_time(summary["play_time_seconds"]),
			]


func _scene_name(path: String) -> String:
	return path.get_file().get_basename()


func _on_slot_pressed(slot_id: int) -> void:
	if SaveManager.slot_menu_mode == "new":
		if SaveManager.save_exists(slot_id):
			# Confirm before overwriting an existing save.
			_pending_overwrite_slot = slot_id
			_confirm_dialog.dialog_text = "Slot %d already has a save.\nOverwrite it with a new game?" % slot_id
			_confirm_dialog.popup_centered()
		else:
			_start_new_game(slot_id)
	else:
		_load_existing_game(slot_id)


func _on_overwrite_confirmed() -> void:
	if _pending_overwrite_slot != -1:
		var slot_id := _pending_overwrite_slot
		_pending_overwrite_slot = -1
		_start_new_game(slot_id)


func _start_new_game(slot_id: int) -> void:
	if not SaveManager.create_new_save(slot_id):
		push_error("SaveSlotMenu: failed to create a save in slot %d" % slot_id)
		return
	# 新游戏先播前情提要，它播完自己去 NEW_GAME_SCENE_PATH。
	# 存档里的 current_scene 写的是关卡而不是前情提要，所以中途退出再读档
	# 会直接进关卡，不会重看一遍。
	get_tree().change_scene_to_file(SaveManager.PROLOGUE_SCENE_PATH)


func _load_existing_game(slot_id: int) -> void:
	var data := SaveManager.load_game(slot_id)
	if data.is_empty():
		push_error("SaveSlotMenu: slot %d is missing or corrupt; returning to menu." % slot_id)
		_go_to_main_menu()
		return
	var scene_path: String = String(data["current_scene"])
	if not ResourceLoader.exists(scene_path):
		push_error("SaveSlotMenu: saved scene '%s' not found; returning to menu." % scene_path)
		_go_to_main_menu()
		return
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("SaveSlotMenu: failed to load scene '%s' (err %d)." % [scene_path, err])
		_go_to_main_menu()


func _on_back_pressed() -> void:
	_go_to_main_menu()


func _go_to_main_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_PATH)
