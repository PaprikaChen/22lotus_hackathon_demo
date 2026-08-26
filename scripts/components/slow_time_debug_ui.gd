extends Label
## Development-only debug readout for the slow-time ability.
## Reads ONLY the public WorldTimeManager interface — no private internals.

func _ready() -> void:
	WorldTimeManager.slow_time_state_changed.connect(_on_state_changed)
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	var state_names := ["READY", "ACTIVE", "COOLDOWN"]
	var s := "Slow Time State: %s\n" % state_names[WorldTimeManager.current_state]
	s += "Active Time Remaining: %.2f\n" % WorldTimeManager.get_active_time_remaining()
	s += "Cooldown Remaining: %.2f\n" % WorldTimeManager.get_cooldown_time_remaining()
	s += "World Time Scale: %.2f" % WorldTimeManager.world_time_scale
	if WorldTimeManager.is_slow_time_active():
		s += "\n[SLOW TIME ACTIVE]"
	text = s


func _on_state_changed(_new_state: int) -> void:
	_refresh()
