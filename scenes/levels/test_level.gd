extends Node2D
## Minimal test scene used to exercise the save/load flow.
## NOT a real gameplay system: just a movable placeholder and two buttons.

const MAIN_MENU_PATH: String = "res://scenes/ui/MainMenu.tscn"
const MOVE_SPEED: float = 220.0

@onready var _player: Node2D = $Player
@onready var _info_label: Label = $UI/Controls/InfoLabel
@onready var _save_button: Button = $UI/Controls/SaveButton
@onready var _return_button: Button = $UI/Controls/ReturnButton

var _slot_id: int = -1
var _save: Dictionary = {}
var _play_time_base: float = 0.0   # play_time_seconds carried in from the save
var _session_start_ms: int = 0     # Time.get_ticks_msec() when this scene began


func _ready() -> void:
	_save_button.pressed.connect(_on_save_pressed)
	_return_button.pressed.connect(_on_return_pressed)

	_slot_id = SaveManager.current_slot
	_save = SaveManager.current_save.duplicate(true)

	if _save.is_empty() or _slot_id == -1:
		# Reached here without an active save (e.g. scene run directly).
		push_warning("TestLevel: no active save; using default spawn.")
		_player.position = SaveManager.DEFAULT_SPAWN
		_play_time_base = 0.0
	else:
		_player.position = Vector2(
			float(_save.get("player_position_x", SaveManager.DEFAULT_SPAWN.x)),
			float(_save.get("player_position_y", SaveManager.DEFAULT_SPAWN.y)),
		)
		_play_time_base = float(_save.get("play_time_seconds", 0.0))

	_session_start_ms = Time.get_ticks_msec()
	_update_info()


func _process(delta: float) -> void:
	# Arrow keys / WASD move the placeholder so position changes are visible.
	var dir := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down"),
	)
	if dir != Vector2.ZERO:
		_player.position += dir.normalized() * MOVE_SPEED * delta
	_update_info()


func _current_play_time() -> float:
	return _play_time_base + float(Time.get_ticks_msec() - _session_start_ms) / 1000.0


func _update_info() -> void:
	_info_label.text = "Slot: %s\nPlay time: %s\nPos: (%.0f, %.0f)\nArrows / WASD to move" % [
		str(_slot_id) if _slot_id != -1 else "—",
		SaveManager.format_play_time(_current_play_time()),
		_player.position.x,
		_player.position.y,
	]


func _on_save_pressed() -> void:
	if _slot_id == -1:
		push_error("TestLevel: no active slot to save into.")
		return
	# Update only the mutable fields; created_at / checkpoint_id carry over.
	_save["current_scene"] = scene_file_path
	_save["player_position_x"] = _player.position.x
	_save["player_position_y"] = _player.position.y
	_save["play_time_seconds"] = _current_play_time()
	if SaveManager.save_game(_slot_id, _save):
		# Rebase the play-time clock so it keeps counting from the saved total.
		_play_time_base = _current_play_time()
		_session_start_ms = Time.get_ticks_msec()
		_save = SaveManager.current_save.duplicate(true)
		print("TestLevel: saved slot %d." % _slot_id)


func _on_return_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_PATH)
