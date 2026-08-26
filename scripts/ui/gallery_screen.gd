extends Control
## 画廊：已解锁 CG 的收集册。**独立场景**，从主菜单直接进。
##
## 因为 CG 收集是跨存档的全局数据（`user://gallery.json`），这里不需要任何
## 存档槽被载入，也不需要暂停世界或锁玩家输入——它不是游戏内叠层。
##
## 两级界面：
##   网格   每张 CG 一个格子；未解锁的显示占位（`？？？`，**不显示标题**，避免剧透）
##   看图   点开后全屏看大图 + 说明；Esc / 返回 回网格，再按一次回主菜单
##
## 结构参照 `memory_box_ui.tscn` 那套已经跑通的网格 + 详情面板。

const MAIN_MENU_PATH: String = "res://scenes/ui/MainMenu.tscn"
const SLOT_SIZE := Vector2(160, 110)

@onready var _grid: GridContainer = $Root/GridPanel/Margin/Rows/Scroll/Grid
@onready var _counter: Label = $Root/GridPanel/Margin/Rows/Header/Counter
@onready var _grid_panel: Control = $Root/GridPanel
@onready var _viewer: Control = $Root/Viewer
@onready var _viewer_image: TextureRect = $Root/Viewer/Margin/Rows/Image
@onready var _viewer_title: Label = $Root/Viewer/Margin/Rows/Title
@onready var _viewer_caption: Label = $Root/Viewer/Margin/Rows/Caption
@onready var _back_button: Button = $Root/GridPanel/Margin/Rows/Header/BackButton

## 当前正在看的 CG；网格模式下为空。
var _viewing: StringName = &""


func _ready() -> void:
	_back_button.pressed.connect(_go_to_main_menu)
	GalleryManager.cg_state_changed.connect(_on_cg_state_changed)
	_close_viewer()
	_rebuild_grid()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _viewing != &"":
		_close_viewer()
	else:
		_go_to_main_menu()


# --- 网格 ----------------------------------------------------------------------

func _rebuild_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()
	var ids := GalleryManager.get_all_cgs()
	for cg_id in ids:
		_grid.add_child(_make_slot(cg_id))
	_counter.text = "已收集  %d / %d" % [
		GalleryManager.get_unlocked_count(), GalleryManager.get_total_count()]
	if ids.is_empty():
		_counter.text = "还没有可收集的画面"


func _make_slot(cg_id: StringName) -> Button:
	var entry := GalleryManager.get_cg_data(cg_id)
	var unlocked := GalleryManager.has_cg(cg_id)
	var button := Button.new()
	button.custom_minimum_size = SLOT_SIZE
	button.clip_text = true
	button.disabled = not unlocked
	button.focus_mode = Control.FOCUS_ALL if unlocked else Control.FOCUS_NONE
	if unlocked:
		var badge := "  ●" if GalleryManager.is_unseen(cg_id) else ""
		button.text = "%s%s" % [entry.title if entry != null else String(cg_id), badge]
		button.icon = entry.get_thumbnail() if entry != null else null
		button.expand_icon = true
		button.pressed.connect(_open_viewer.bind(cg_id))
	else:
		# 未解锁：不透露标题，只占位。
		button.text = "？？？"
	return button


func _on_cg_state_changed(_cg_id: StringName) -> void:
	# 状态变化可能来自别处（调试解锁），整块重建最省心，格子数量很少。
	if _viewing == &"":
		_rebuild_grid()


# --- 看图 ----------------------------------------------------------------------

func _open_viewer(cg_id: StringName) -> void:
	var entry := GalleryManager.get_cg_data(cg_id)
	if entry == null:
		return
	_viewing = cg_id
	_viewer_image.texture = entry.image
	_viewer_title.text = entry.title
	_viewer_caption.text = entry.caption
	_grid_panel.visible = false
	_viewer.visible = true
	# 真的看过了才清 NEW 角标。
	GalleryManager.mark_as_seen(cg_id)


func _close_viewer() -> void:
	_viewing = &""
	_viewer.visible = false
	_grid_panel.visible = true
	_rebuild_grid()


func _go_to_main_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_PATH)


## 测试用：不点按钮也能打开 / 关闭。
func open_cg(cg_id: StringName) -> void:
	_open_viewer(cg_id)


func close_cg() -> void:
	_close_viewer()


func get_viewing() -> StringName:
	return _viewing


func get_slot_count() -> int:
	return _grid.get_child_count()
