class_name PauseMenu
extends CanvasLayer
## 游戏内暂停菜单。只负责 Esc 开关、暂停树、玩家输入锁，以及把三个按钮
## 交给现有 SaveManager / 主菜单流程；不读取或写入文件，也不持有关卡剧情。

const LOCK_SOURCE := &"pause_menu"
const MAIN_MENU_PATH := "res://scenes/ui/MainMenu.tscn"

var _player: Node2D = null
var _is_open := false
var _was_paused := false
var _cancel_held := false

@onready var _root: Control = $Root
@onready var _save_button: Button = $Root/CenterContainer/Panel/VBox/SaveButton
@onready var _main_menu_button: Button = $Root/CenterContainer/Panel/VBox/MainMenuButton
@onready var _quit_button: Button = $Root/CenterContainer/Panel/VBox/QuitButton
@onready var _status_label: Label = $Root/CenterContainer/Panel/VBox/StatusLabel


func set_player(player: Node2D) -> void:
	_player = player


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false
	_save_button.pressed.connect(_save_progress)
	_main_menu_button.pressed.connect(_return_to_main_menu)
	_quit_button.pressed.connect(_quit_game)


func _process(_delta: float) -> void:
	var cancel_pressed := Input.is_action_pressed(&"ui_cancel")
	if cancel_pressed and not _cancel_held:
		if _is_open:
			close()
		elif not get_tree().paused and _can_open():
			open()
	_cancel_held = cancel_pressed


func open() -> void:
	if _is_open or not _can_open():
		return
	_is_open = true
	_was_paused = get_tree().paused
	_status_label.text = ""
	_root.visible = true
	if _player != null and _player.has_method("lock_input"):
		_player.lock_input(LOCK_SOURCE)
	get_tree().paused = true
	_save_button.grab_focus()


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_root.visible = false
	get_tree().paused = _was_paused
	if _player != null and _player.has_method("unlock_input"):
		_player.unlock_input(LOCK_SOURCE)


func _can_open() -> bool:
	if _player == null:
		return false
	if _player.has_method("is_input_locked") and _player.is_input_locked():
		return false
	return true


func _save_progress() -> void:
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path.is_empty() or _player == null:
		_status_label.text = "当前状态不能存档。"
		return
	var slot := SaveManager.save_progress_to_oldest_slot(scene.scene_file_path, _player.global_position)
	if slot == -1:
		_status_label.text = "没有活动存档，无法保存。"
		return
	_status_label.text = "已保存到槽位 %d。" % slot


func _return_to_main_menu() -> void:
	close()
	WorldTimeManager.reset_state()
	get_tree().change_scene_to_file(MAIN_MENU_PATH)


func _quit_game() -> void:
	get_tree().quit()
