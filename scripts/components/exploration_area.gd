extends Node2D
## One horizontal exploration area inside a chapter level (see
## old_courtyard.tscn). Content uses LOCAL coordinates so the whole area can
## be repositioned by dragging this node; camera limits are exported as
## local values and converted to world space here.
##
## Expected children: "SpawnPoint" (Marker2D, left entry), optional
## "SpawnPointRight" (Marker2D, used when the player walks BACK into this
## area from the next one), "ExitTrigger" (Area2D, right edge — omit on the
## last area) and optional "ExitTriggerLeft" (Area2D, left edge — returns to
## the previous area; omit on the first). AreaFlowController discovers areas
## as the ordered children of the AreaContainer.

## Camera limits in this area's LOCAL space (usually 0 .. area width).
## Default is exactly one 1152x648 window: the camera stays fixed and the
## area switches when the player reaches the window's right edge.
@export var camera_limit_left: float = 0.0
@export var camera_limit_right: float = 1152.0


func get_camera_limit_left_world() -> float:
	return global_position.x + camera_limit_left


func get_camera_limit_right_world() -> float:
	return global_position.x + camera_limit_right


func get_spawn_position() -> Vector2:
	var marker := get_node_or_null("SpawnPoint") as Node2D
	return marker.global_position if marker != null else global_position


## Entry point when walking back in from the NEXT area. Falls back to the
## normal spawn when no SpawnPointRight exists.
func get_spawn_position_right() -> Vector2:
	var marker := get_node_or_null("SpawnPointRight") as Node2D
	return marker.global_position if marker != null else get_spawn_position()


func get_exit_trigger() -> Area2D:
	return get_node_or_null("ExitTrigger") as Area2D


func get_left_exit_trigger() -> Area2D:
	return get_node_or_null("ExitTriggerLeft") as Area2D


## True when a world-space x coordinate falls inside this area's camera span
## (used to pick the starting area after a save restore).
func contains_x(world_x: float) -> bool:
	return world_x >= get_camera_limit_left_world() and world_x <= get_camera_limit_right_world()
