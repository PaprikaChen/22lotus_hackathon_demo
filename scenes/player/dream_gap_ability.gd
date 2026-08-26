class_name DreamGapAbility
extends Node
## Player-side component for the DreamGap (world slow-time) ability.
##
## Responsibilities: read the ability input, respect the player's input lock,
## request activation/early-stop from WorldTimeManager, and re-emit
## UI-friendly signals (cooldown/duration bars listen HERE, not on the
## manager). The duration/cooldown state machine itself stays centralized in
## WorldTimeManager — this component is deliberately a thin facade so the
## proven timing logic is not duplicated.
##
## No enemy, platform or visual logic belongs in this script.

signal ability_started
signal ability_ended
signal cooldown_started
signal cooldown_finished
signal cooldown_changed(current: float, maximum: float)
signal duration_changed(current: float, maximum: float)

## Input action polled for activation (press to start, press again to end
## early — not hold-to-maintain).
@export var action_name: StringName = &"slow_time"

var _held: bool = false
var _last_state: int = WorldTimeManager.SlowTimeState.READY


func _ready() -> void:
	_last_state = WorldTimeManager.current_state
	WorldTimeManager.slow_time_started.connect(_on_started)
	WorldTimeManager.slow_time_ended.connect(_on_ended)
	WorldTimeManager.slow_time_state_changed.connect(_on_state_changed)
	WorldTimeManager.slow_time_energy_changed.connect(_on_energy_changed)


func _physics_process(_delta: float) -> void:
	# Rising edge from is_action_pressed() (same convention as player.gd, so
	# injected/held input in automated tests drives the identical path).
	var pressed := Input.is_action_pressed(action_name)
	if pressed and not _held and not _is_player_input_locked():
		toggle()
	_held = pressed


# --- Public API -------------------------------------------------------------

func toggle() -> void:
	if WorldTimeManager.is_slow_time_active():
		WorldTimeManager.stop_slow_time()
	else:
		WorldTimeManager.request_slow_time()


func is_ability_active() -> bool:
	return WorldTimeManager.is_slow_time_active()


func is_ability_ready() -> bool:
	return WorldTimeManager.is_slow_time_ready()


# --- Internal ---------------------------------------------------------------

func _is_player_input_locked() -> bool:
	var p := get_parent()
	return p != null and p.has_method("is_input_locked") and p.is_input_locked()


func _on_started() -> void:
	ability_started.emit()
	duration_changed.emit(
		WorldTimeManager.max_slow_duration, WorldTimeManager.max_slow_duration)


func _on_ended() -> void:
	ability_ended.emit()


func _on_state_changed(new_state: int) -> void:
	if new_state == WorldTimeManager.SlowTimeState.COOLDOWN:
		cooldown_started.emit()
		cooldown_changed.emit(
			WorldTimeManager.cooldown_duration, WorldTimeManager.cooldown_duration)
	elif (new_state == WorldTimeManager.SlowTimeState.READY
			and _last_state == WorldTimeManager.SlowTimeState.COOLDOWN):
		cooldown_finished.emit()
	_last_state = new_state


func _on_energy_changed(active_remaining: float, cooldown_remaining: float) -> void:
	match WorldTimeManager.current_state:
		WorldTimeManager.SlowTimeState.ACTIVE:
			duration_changed.emit(active_remaining, WorldTimeManager.max_slow_duration)
		WorldTimeManager.SlowTimeState.COOLDOWN:
			cooldown_changed.emit(cooldown_remaining, WorldTimeManager.cooldown_duration)
