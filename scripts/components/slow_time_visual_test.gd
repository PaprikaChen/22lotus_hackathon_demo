extends CanvasModulate
## Demo art hook proving future visuals can react to slow-time purely via
## signals. It tints the whole 2D world while slow-time is active and restores
## on end. WorldTimeManager knows nothing about this node — the coupling is
## one-way (this listens to the manager).
##
## Not a final shader / not an eye animation — just a placeholder demonstration.

@export var normal_color: Color = Color(1, 1, 1, 1)
@export var slow_color: Color = Color(0.55, 0.65, 1.0, 1)


func _ready() -> void:
	color = normal_color
	WorldTimeManager.slow_time_started.connect(_on_slow_time_started)
	WorldTimeManager.slow_time_ended.connect(_on_slow_time_ended)


func _on_slow_time_started() -> void:
	color = slow_color


func _on_slow_time_ended() -> void:
	color = normal_color
