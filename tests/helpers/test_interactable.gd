extends Interactable
## Configurable interactable for the interaction test room. Counts calls so
## the automated self-test can assert on behavior; optionally simulates a
## short dialogue by locking player input for a while.

@export var display_name: String = "object"
## > 0.0: on interact, lock player input for this long (dialogue stand-in).
@export var simulate_dialogue_seconds: float = 0.0

var interact_count: int = 0
var blocked_count: int = 0


func _on_interact(player: Node) -> void:
	interact_count += 1
	print("[TestInteractable] %s interacted (count %d)" % [display_name, interact_count])
	if simulate_dialogue_seconds > 0.0 and player != null and player.has_method("begin_interaction"):
		player.begin_interaction()
		await get_tree().create_timer(simulate_dialogue_seconds).timeout
		player.end_interaction()


func _on_blocked_interact(_player: Node) -> void:
	blocked_count += 1
	print("[TestInteractable] %s blocked (count %d)" % [display_name, blocked_count])
