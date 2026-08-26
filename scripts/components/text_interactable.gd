extends Interactable
## Story prop that carries its own multi-line placeholder text (kept on the
## node, NOT in UI or player scripts). On interact it emits the text; the
## level UI decides how to display it. Reusable for any examine-only prop.

signal text_requested(text: String)

@export_multiline var display_text: String = ""


func _on_interact(_player: Node) -> void:
	text_requested.emit(display_text)
