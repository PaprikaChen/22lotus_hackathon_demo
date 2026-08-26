extends LevelBase
## 主屋内 — graybox placeholder interior, entered from the 旧院 side window.
## One fixed screen. Real interior content is intentionally NOT designed
## here; the only flow is: look around (placeholder text) and climb back out
## through the window to the courtyard.

const COURTYARD_SCENE := "res://scenes/levels/old_courtyard.tscn"

@onready var _p: CharacterBody2D = get_node(player_path)
@onready var _detector: InteractionDetector = _p.get_node("InteractionDetector")
@onready var _prompt_label: Label = $UI/PromptLabel
@onready var _dialogue: CanvasLayer = $DialogueBox
@onready var _exit_window: Interactable = $Interactables/ExitWindow

var _pending_exit: bool = false


func _ready() -> void:
	super._ready()
	_detector.prompt_changed.connect(_on_prompt_changed)
	for prop in _collect_text_props(self):
		prop.text_requested.connect(_show_text)
	_exit_window.interacted.connect(func(_player: Node) -> void: _pending_exit = true)
	_dialogue.closed.connect(_on_dialogue_closed)


func _on_prompt_changed(text: String) -> void:
	_prompt_label.text = "[E] %s" % text if not text.is_empty() else ""


func _show_text(text: String) -> void:
	_dialogue.show_text(text)


func _collect_text_props(node: Node, found: Array = []) -> Array:
	for child in node.get_children():
		if child.has_signal("text_requested"):
			found.append(child)
		_collect_text_props(child, found)
	return found


func _on_dialogue_closed() -> void:
	if not _pending_exit:
		return
	_pending_exit = false
	# Only change scenes when running standalone (not instanced inside a test).
	if get_tree().current_scene == self:
		get_tree().change_scene_to_file.call_deferred(COURTYARD_SCENE)
