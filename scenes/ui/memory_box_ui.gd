extends CanvasLayer
## 梦奁（Dream Box）graybox UI — a drawer-of-slots view over MemoryManager.
##
## All text/icons come from MemoryEntry resources at display time; nothing is
## hardcoded here and nothing here writes save data. Opening freezes the
## world with get_tree().paused (this layer runs ALWAYS), which also freezes
## an active DreamGap's timers — the ability resumes untouched on close.
## A pre-existing pause is respected and restored, never cancelled.
##
## Input: `open_action` toggles (press once open, again close), ui_cancel
## (Esc) closes. Player control is held with the source-based input lock
## ("memory_box") and ONLY that source is released on close — locks held by
## dialogue/cutscenes stay intact.

signal opened
signal closed

const LOCK_SOURCE := &"memory_box"
const SLOT_SIZE := Vector2(112, 112)

## The player to lock while the box is open (optional; UI-only scenes may
## leave it unset).
@export var player_path: NodePath
@export var open_action: StringName = &"open_memory_box"

@onready var _grid: GridContainer = $Root/MemoryGrid
@onready var _empty_label: Label = $Root/EmptyLabel
@onready var _icon: TextureRect = $Root/DetailPanel/Icon
@onready var _memory_title: Label = $Root/DetailPanel/MemoryTitle
@onready var _status_label: Label = $Root/DetailPanel/StatusLabel
@onready var _description: Label = $Root/DetailPanel/Description

var _player: Node = null
var _is_open: bool = false
var _was_paused: bool = false
var _selected_id: StringName = &""

# Rising-edge tracking (project convention; see AGENTS.md).
var _open_held: bool = false
var _cancel_held: bool = false
var _warned_missing_action: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_player = get_node_or_null(player_path)
	MemoryManager.memory_state_changed.connect(_on_memory_state_changed)


func _process(_delta: float) -> void:
	if InputMap.has_action(open_action):
		var pressed := Input.is_action_pressed(open_action)
		if pressed and not _open_held:
			toggle()
		_open_held = pressed
	elif not _warned_missing_action:
		push_warning("MemoryBoxUI: input action '%s' does not exist." % open_action)
		_warned_missing_action = true

	var cancel_pressed := Input.is_action_pressed("ui_cancel")
	if cancel_pressed and not _cancel_held and _is_open:
		close()
	_cancel_held = cancel_pressed


# --- Public API -----------------------------------------------------------------

func is_open() -> bool:
	return _is_open


## Single gate for "may the box open right now". Dialogue, cutscenes, death
## and other flows hold player input locks, so they block opening here
## without scattering per-system checks.
func can_open_memory_box() -> bool:
	if _is_open:
		return false
	if _player != null and _player.has_method("is_input_locked") and _player.is_input_locked():
		return false
	return true


func toggle() -> void:
	if _is_open:
		close()
	elif can_open_memory_box():
		open()


func open() -> void:
	if _is_open or not can_open_memory_box():
		return
	_is_open = true
	visible = true
	if _player != null and _player.has_method("lock_input"):
		_player.lock_input(LOCK_SOURCE)
	_was_paused = get_tree().paused
	get_tree().paused = true
	_selected_id = &""
	_clear_detail()
	_rebuild_grid()
	_focus_first_slot()
	opened.emit()


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	get_tree().paused = _was_paused
	if _player != null and _player.has_method("unlock_input"):
		_player.unlock_input(LOCK_SOURCE)
	closed.emit()


# --- Grid -----------------------------------------------------------------------

func _rebuild_grid() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var ids := MemoryManager.get_unlocked_memories()
	_empty_label.visible = ids.is_empty()
	for id in ids:
		_grid.add_child(_make_slot(id))


func _make_slot(memory_id: StringName) -> Button:
	var entry := MemoryManager.get_memory_data(memory_id)
	var btn := Button.new()
	btn.set_meta("memory_id", String(memory_id))
	btn.custom_minimum_size = SLOT_SIZE
	btn.icon = entry.icon
	btn.expand_icon = true
	btn.clip_text = true
	btn.text = _slot_text(memory_id)
	btn.pressed.connect(_on_slot_pressed.bind(memory_id))
	return btn


func _slot_text(memory_id: StringName) -> String:
	var entry := MemoryManager.get_memory_data(memory_id)
	var text := entry.title if entry != null else String(memory_id)
	var badge := _badge_text(memory_id)
	if not badge.is_empty():
		text += "\n" + badge
	return text


func _badge_text(memory_id: StringName) -> String:
	match MemoryManager.get_unread_state(memory_id):
		MemoryManager.UNREAD_NEW:
			return "[NEW]"
		MemoryManager.UNREAD_UPDATED:
			return "[UPDATED]"
		_:
			return ""


func _focus_first_slot() -> void:
	if _grid.get_child_count() > 0:
		(_grid.get_child(0) as Button).grab_focus()


func _find_slot(memory_id: StringName) -> Button:
	for child in _grid.get_children():
		if child is Button and String(child.get_meta("memory_id", "")) == String(memory_id):
			return child
	return null


# --- Detail ---------------------------------------------------------------------

func _on_slot_pressed(memory_id: StringName) -> void:
	_show_detail(memory_id)
	# Viewing the detail is what clears NEW/UPDATED — opening the box alone
	# must not mark anything as read.
	MemoryManager.mark_as_read(memory_id)


func _show_detail(memory_id: StringName) -> void:
	var entry := MemoryManager.get_memory_data(memory_id)
	if entry == null:
		_clear_detail()
		return
	_selected_id = memory_id
	var stage_index := MemoryManager.get_current_stage(memory_id)
	_icon.texture = entry.icon
	_memory_title.text = entry.title
	var status := "记忆 %d / %d" % [stage_index + 1, entry.get_stage_count()]
	var badge := _badge_text(memory_id)
	if not badge.is_empty():
		status += "   " + badge
	_status_label.text = status
	var stage := entry.get_stage(stage_index)
	var desc := entry.get_stage_description(stage_index)
	if stage != null and not stage.stage_title.is_empty():
		desc = stage.stage_title + "\n\n" + desc
	_description.text = desc


func _clear_detail() -> void:
	_selected_id = &""
	_icon.texture = null
	_memory_title.text = ""
	_status_label.text = ""
	_description.text = ""


# --- Reactions --------------------------------------------------------------------

func _on_memory_state_changed(memory_id: StringName) -> void:
	if not _is_open:
		return
	var slot := _find_slot(memory_id)
	if slot == null:
		# Unlocked while the box is open: add the new slot without stealing focus.
		_rebuild_grid()
		return
	slot.text = _slot_text(memory_id)
	if _selected_id == memory_id:
		_show_detail(memory_id)
