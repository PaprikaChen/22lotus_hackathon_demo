extends Node2D
## Graybox patrolling hazard used to verify slow-time. No real AI / art.
##
## Moves left-right around its start position using WorldTimeManager scaled
## delta, so it visibly slows during slow-time. On contact with the player it
## emits `player_hit`, prints a test message, and asks the player to respawn.

signal player_hit

@export var speed: float = 90.0
@export var patrol_distance: float = 120.0

var _origin_x: float = 0.0
var _dir: float = 1.0


func _ready() -> void:
	_origin_x = position.x
	($HitArea as Area2D).body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	var scaled := WorldTimeManager.get_scaled_delta(delta)
	position.x += _dir * speed * scaled
	if absf(position.x - _origin_x) >= patrol_distance:
		position.x = _origin_x + signf(position.x - _origin_x) * patrol_distance
		_dir = -_dir


func _on_body_entered(body: Node) -> void:
	if body is CharacterBody2D:
		player_hit.emit()
		print("[TestEnemy] Player hit — respawning.")
		if body.has_method("respawn"):
			body.respawn()
