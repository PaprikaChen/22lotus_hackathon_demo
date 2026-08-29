extends Control
## 主菜单：新游戏 / 读取存档 / 退出。
##
## 新游戏和读取存档都先去槽位菜单（`SaveManager.slot_menu_mode` 决定它开在
## 哪个模式）。
##
## 三个槽位全空时"读取存档"置灰：没档可读却能点进去是个死路。

const SLOT_MENU_PATH: String = "res://scenes/ui/SaveSlotMenu.tscn"

const NORMAL_TINT := Color(0.82, 0.82, 0.86, 1.0)
const SELECTED_TINT := Color(1.35, 1.18, 1.42, 1.0)
const DISABLED_TINT := Color(0.34, 0.34, 0.38, 0.7)

@onready var _start_button: Button = $MenuButtons/StartNewGameButton
@onready var _load_button: Button = $MenuButtons/LoadGameButton
@onready var _exit_button: Button = $MenuButtons/ExitButton
@onready var _start_art: CanvasItem = $OptionArt/NewGame
@onready var _load_art: CanvasItem = $OptionArt/LoadGame
@onready var _exit_art: CanvasItem = $OptionArt/Exit

var _buttons: Array[Button] = []
var _art_by_button: Dictionary = {}
var _selected_button: Button = null


func _ready() -> void:
	_setup_selection_feedback()
	_start_button.pressed.connect(_on_start_pressed)
	_load_button.pressed.connect(_on_load_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)
	_refresh_load_button()
	_start_button.grab_focus()
	_select_button(_start_button)


func _setup_selection_feedback() -> void:
	_buttons = [_start_button, _load_button, _exit_button]
	_art_by_button = {
		_start_button: _start_art,
		_load_button: _load_art,
		_exit_button: _exit_art,
	}
	for button in _buttons:
		button.focus_entered.connect(_select_button.bind(button))
		button.mouse_entered.connect(_focus_from_mouse.bind(button))


func _focus_from_mouse(button: Button) -> void:
	if not button.disabled:
		button.grab_focus()


func _select_button(button: Button) -> void:
	if button.disabled:
		return
	_selected_button = button
	_refresh_selection_visuals()


func _refresh_selection_visuals() -> void:
	for button in _buttons:
		var art := _art_by_button.get(button) as CanvasItem
		var selected := button == _selected_button and not button.disabled
		if art != null:
			art.modulate = DISABLED_TINT if button.disabled else (SELECTED_TINT if selected else NORMAL_TINT)


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
	# 读取存档置灰时，键盘焦点要直接跨到退出，不能卡在不可聚焦的按钮上。
	var next_after_start := NodePath("../LoadGameButton") if any else NodePath("../ExitButton")
	var previous_before_exit := NodePath("../LoadGameButton") if any else NodePath("../StartNewGameButton")
	_start_button.focus_neighbor_right = next_after_start
	_start_button.focus_neighbor_bottom = next_after_start
	_exit_button.focus_neighbor_left = previous_before_exit
	_exit_button.focus_neighbor_top = previous_before_exit
	_refresh_selection_visuals()


func _on_start_pressed() -> void:
	SaveManager.slot_menu_mode = "new"
	get_tree().change_scene_to_file(SLOT_MENU_PATH)


func _on_load_pressed() -> void:
	SaveManager.slot_menu_mode = "load"
	get_tree().change_scene_to_file(SLOT_MENU_PATH)


func _on_exit_pressed() -> void:
	get_tree().quit()
