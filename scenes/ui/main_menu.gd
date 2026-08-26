extends Control
## 主菜单：新游戏 / 读取存档 / 画廊 / 退出。
##
## 新游戏和读取存档都先去槽位菜单（`SaveManager.slot_menu_mode` 决定它开在
## 哪个模式）；画廊是独立场景，**不需要任何存档槽**——CG 收集是跨存档的全局
## 数据（`user://gallery.json`），所以从主菜单直接能看。
##
## 三个槽位全空时"读取存档"置灰：没档可读却能点进去是个死路。

const SLOT_MENU_PATH: String = "res://scenes/ui/SaveSlotMenu.tscn"
const GALLERY_PATH: String = "res://scenes/ui/gallery.tscn"

@onready var _start_button: Button = $CenterContainer/VBoxContainer/StartNewGameButton
@onready var _load_button: Button = $CenterContainer/VBoxContainer/LoadGameButton
@onready var _gallery_button: Button = $CenterContainer/VBoxContainer/GalleryButton
@onready var _exit_button: Button = $CenterContainer/VBoxContainer/ExitButton


func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_load_button.pressed.connect(_on_load_pressed)
	_gallery_button.pressed.connect(_on_gallery_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)
	_refresh_load_button()
	_start_button.grab_focus()


## 有任何一个槽位存在就可以读档。用 save_exists() 而不是 get_save_summary()：
## 这里只关心"有没有档"，损坏的档留给槽位菜单去报错。
func _refresh_load_button() -> void:
	var any := false
	for slot_id in range(1, SaveManager.SLOT_COUNT + 1):
		if SaveManager.save_exists(slot_id):
			any = true
			break
	_load_button.disabled = not any
	_load_button.tooltip_text = "" if any else "还没有任何存档"


func _on_start_pressed() -> void:
	SaveManager.slot_menu_mode = "new"
	get_tree().change_scene_to_file(SLOT_MENU_PATH)


func _on_load_pressed() -> void:
	SaveManager.slot_menu_mode = "load"
	get_tree().change_scene_to_file(SLOT_MENU_PATH)


func _on_gallery_pressed() -> void:
	get_tree().change_scene_to_file(GALLERY_PATH)


func _on_exit_pressed() -> void:
	get_tree().quit()
