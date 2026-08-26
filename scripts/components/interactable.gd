class_name Interactable
extends Area2D
## Base class for everything the player can interact with (doors, memory
## items, mechanisms, story props). The player's InteractionDetector finds
## the best candidate and calls interact(); what happens then is entirely
## this object's business — never the player's.
##
## Subclasses override _on_interact() (and optionally _on_blocked_interact()
## for the "requirement not met" fallback). Base class already handles
## one-shot consumption, priority and story-flag gating.

signal interacted(player: Node)
signal interaction_blocked(player: Node)

## Prompt shown while this is the active target.
@export var prompt_text: String = "调查"

## Higher priority wins when several interactables overlap; ties break by
## distance to the player. (Named interact_priority because Area2D already
## has a native `priority` property.)
@export var interact_priority: int = 0

## Consume after one successful interaction.
@export var one_shot: bool = false

## Optional StoryFlagManager gate; empty = always available. When the flag
## is missing, interact() runs the blocked path instead of _on_interact().
@export var required_flag: StringName = &""

## Prompt while the requirement is unmet. Empty string keeps prompt_text.
@export var blocked_prompt_text: String = ""

var _consumed: bool = false


# --- Interface used by InteractionDetector -----------------------------------

func can_interact(_player: Node) -> bool:
	return not (one_shot and _consumed)


func get_interaction_prompt() -> String:
	if not is_requirement_met() and not blocked_prompt_text.is_empty():
		return blocked_prompt_text
	return prompt_text


func interact(player: Node) -> void:
	if not can_interact(player):
		return
	if not is_requirement_met():
		_on_blocked_interact(player)
		interaction_blocked.emit(player)
		return
	if one_shot:
		_consumed = true
	_on_interact(player)
	interacted.emit(player)


func is_requirement_met() -> bool:
	if required_flag == &"":
		return true
	return StoryFlagManager.has_flag(required_flag)


# --- Virtuals for subclasses --------------------------------------------------

## The actual interaction result. Override in subclasses.
func _on_interact(_player: Node) -> void:
	pass


## Fallback when required_flag is missing (e.g. "锁着的 — 需要钥匙" feedback).
func _on_blocked_interact(_player: Node) -> void:
	pass
