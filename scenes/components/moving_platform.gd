extends AnimatableBody2D
## Graybox moving platform. Travels back and forth between two Marker2D nodes
## (assigned in the level) and carries any CharacterBody2D riding it.
##
## It moves using WorldTimeManager.get_scaled_delta(), so it slows down with
## the world during slow-time while the riding player keeps real-time control.
## AnimatableBody2D (sync_to_physics) is used instead of an AnimationPlayer so
## the motion correctly responds to the world time scale.

@export var speed: float = 120.0
@export var point_a_path: NodePath
@export var point_b_path: NodePath

var _a: Vector2
var _b: Vector2
var _moving_to_b: bool = true


func _ready() -> void:
	var a := get_node_or_null(point_a_path) as Node2D
	var b := get_node_or_null(point_b_path) as Node2D
	if a == null or b == null:
		push_warning("MovingPlatform: marker path(s) not set; platform will stay still.")
		_a = global_position
		_b = global_position
		return
	_a = a.global_position
	_b = b.global_position
	global_position = _a


func _physics_process(delta: float) -> void:
	if _a.is_equal_approx(_b):
		return
	var scaled := WorldTimeManager.get_scaled_delta(delta)
	var target := _b if _moving_to_b else _a
	global_position = global_position.move_toward(target, speed * scaled)
	if global_position.is_equal_approx(target):
		_moving_to_b = not _moving_to_b
