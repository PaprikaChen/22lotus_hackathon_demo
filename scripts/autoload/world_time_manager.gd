extends Node
## Autoload "WorldTimeManager" — the single authority for the slow-time ability.
##
## Design contract:
##  - Player runs on REAL delta and is never affected here.
##  - World objects (platforms, enemies, traps) voluntarily pull
##    get_scaled_delta() and use it for their own movement.
##  - Duration and cooldown use REAL time: Engine.time_scale is NEVER changed,
##    so the delta this node receives is always real.
##  - One state machine, no per-object state, no extra Timers.
##  - Art/UI react via signals only; no art logic lives in here.

signal slow_time_started
signal slow_time_ended
signal slow_time_state_changed(new_state: SlowTimeState)
signal slow_time_energy_changed(active_remaining: float, cooldown_remaining: float)

enum SlowTimeState { READY, ACTIVE, COOLDOWN }

@export var slow_time_scale: float = 0.25
@export var max_slow_duration: float = 3.0
@export var cooldown_duration: float = 2.0

var world_time_scale: float = 1.0
var current_state: SlowTimeState = SlowTimeState.READY
var remaining_active_time: float = 0.0
var remaining_cooldown_time: float = 0.0


func _process(delta: float) -> void:
	# delta is real time (Engine.time_scale is never touched).
	match current_state:
		SlowTimeState.ACTIVE:
			remaining_active_time = maxf(0.0, remaining_active_time - delta)
			slow_time_energy_changed.emit(remaining_active_time, 0.0)
			if remaining_active_time <= 0.0:
				_enter_cooldown()
		SlowTimeState.COOLDOWN:
			remaining_cooldown_time = maxf(0.0, remaining_cooldown_time - delta)
			slow_time_energy_changed.emit(0.0, remaining_cooldown_time)
			if remaining_cooldown_time <= 0.0:
				_set_state(SlowTimeState.READY)
				slow_time_energy_changed.emit(0.0, 0.0)


# --- Public API -------------------------------------------------------------

## Start the ability. Returns false if not currently READY (e.g. on cooldown),
## which makes repeated key presses safe — they simply no-op.
func request_slow_time() -> bool:
	if current_state != SlowTimeState.READY:
		return false
	remaining_active_time = max_slow_duration
	world_time_scale = slow_time_scale
	_set_state(SlowTimeState.ACTIVE)
	slow_time_started.emit()
	slow_time_energy_changed.emit(remaining_active_time, 0.0)
	return true


## End the ability early. No-op unless currently ACTIVE.
func stop_slow_time() -> void:
	if current_state != SlowTimeState.ACTIVE:
		return
	_enter_cooldown()


func is_slow_time_active() -> bool:
	return current_state == SlowTimeState.ACTIVE


func is_slow_time_ready() -> bool:
	return current_state == SlowTimeState.READY


func get_scaled_delta(delta: float) -> float:
	return delta * world_time_scale


func get_active_time_remaining() -> float:
	return remaining_active_time


func get_cooldown_time_remaining() -> float:
	return remaining_cooldown_time


## Hard reset to READY with world_time_scale = 1.0. Call on load-game, scene
## change, player death or return-to-menu so no ACTIVE/COOLDOWN state leaks
## across those boundaries. Emits slow_time_ended if the ability was active
## so visual listeners restore themselves.
func reset_state() -> void:
	var was_active := current_state == SlowTimeState.ACTIVE
	world_time_scale = 1.0
	remaining_active_time = 0.0
	remaining_cooldown_time = 0.0
	_set_state(SlowTimeState.READY)
	if was_active:
		slow_time_ended.emit()
	slow_time_energy_changed.emit(0.0, 0.0)


# --- Internal ---------------------------------------------------------------

func _enter_cooldown() -> void:
	world_time_scale = 1.0
	remaining_active_time = 0.0
	remaining_cooldown_time = cooldown_duration
	_set_state(SlowTimeState.COOLDOWN)
	slow_time_ended.emit()
	slow_time_energy_changed.emit(0.0, remaining_cooldown_time)


func _set_state(new_state: SlowTimeState) -> void:
	if new_state == current_state:
		return
	current_state = new_state
	slow_time_state_changed.emit(new_state)
