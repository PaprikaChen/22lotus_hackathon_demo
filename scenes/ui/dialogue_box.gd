extends CanvasLayer
## Bottom-of-screen dialogue / interaction text box (graybox), PAGED:
## show_text() splits the text into sentences (one per line), displays one at
## a time; ui_accept (Space) advances, and after the last line the box hides.
##
## While the box is open the player is held with the source-based input lock
## ("dialogue_box", via begin_interaction so the state shows INTERACT) — so
## Space advances text instead of jumping, and world interaction pauses.
## Optional portrait (left) and speaker name for dialogue use. Runs while the
## tree is paused so future paused dialogue flows keep working.

signal line_shown(line: String)
signal closed

const LOCK_SOURCE := &"dialogue_box"

## Player to lock while the box is open (optional).
@export var player_path: NodePath

@onready var _panel: Control = $Root/Panel
@onready var _portrait: TextureRect = $Root/Panel/Margin/HBox/Portrait
@onready var _speaker_label: Label = $Root/Panel/Margin/HBox/TextColumn/SpeakerLabel
@onready var _text_label: Label = $Root/Panel/Margin/HBox/TextColumn/TextLabel
@onready var _continue_hint: Label = $Root/Panel/ContinueHint

var _lines: PackedStringArray = []
var _line_index: int = 0
var _player: Node = null

# Rising-edge tracking (project convention; see AGENTS.md).
var _accept_held: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.visible = false
	_player = get_node_or_null(player_path)


func _process(_delta: float) -> void:
	var pressed := Input.is_action_pressed("ui_accept")
	if pressed and not _accept_held and _panel.visible:
		advance()
	_accept_held = pressed


# --- Public API -----------------------------------------------------------------

## Splits `text` into non-empty lines and shows the first one. `portrait`
## and `speaker` are optional (dialogue use). Calling again while open
## replaces the content.
func show_text(text: String, portrait: Texture2D = null, speaker: String = "") -> void:
	var lines := PackedStringArray()
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if not line.is_empty():
			lines.append(line)
	if lines.is_empty():
		return
	_lines = lines
	_line_index = 0
	_panel.visible = true
	_portrait.texture = portrait
	_portrait.visible = portrait != null
	_speaker_label.text = speaker
	_speaker_label.visible = not speaker.is_empty()
	_lock_player()
	_show_current_line()


## Next line, or close after the last one.
func advance() -> void:
	if not _panel.visible:
		return
	_line_index += 1
	if _line_index >= _lines.size():
		hide_box()
	else:
		_show_current_line()


func hide_box() -> void:
	if not _panel.visible:
		return
	_panel.visible = false
	_lines = PackedStringArray()
	_unlock_player()
	closed.emit()


func is_showing() -> bool:
	return _panel.visible


## The line currently on screen ("" when hidden).
func get_current_text() -> String:
	return _text_label.text if _panel.visible else ""


# --- Internal ---------------------------------------------------------------------

func _show_current_line() -> void:
	_text_label.text = _lines[_line_index]
	var is_last := _line_index >= _lines.size() - 1
	_continue_hint.text = "空格 关闭" if is_last else "空格 ▸"
	line_shown.emit(_lines[_line_index])


func _lock_player() -> void:
	if _player == null:
		return
	if _player.has_method("begin_interaction"):
		_player.begin_interaction(LOCK_SOURCE)
	elif _player.has_method("lock_input"):
		_player.lock_input(LOCK_SOURCE)


func _unlock_player() -> void:
	if _player == null:
		return
	if _player.has_method("end_interaction"):
		_player.end_interaction(LOCK_SOURCE)
	elif _player.has_method("unlock_input"):
		_player.unlock_input(LOCK_SOURCE)
