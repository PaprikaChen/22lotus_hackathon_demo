extends Node2D
## Graybox spinning object for the DreamGap test room. If a child named
## "DreamAffectedComponent" exists it pulls scaled delta through it;
## otherwise it spins on raw delta (the control/unaffected case).

@export var spin_speed: float = TAU ## radians per second

@onready var _dream: DreamAffectedComponent = get_node_or_null("DreamAffectedComponent")


func _physics_process(delta: float) -> void:
	var d := _dream.get_scaled_delta(delta) if _dream != null else delta
	rotation += spin_speed * d
