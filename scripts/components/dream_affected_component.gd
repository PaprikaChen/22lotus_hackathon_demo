class_name DreamAffectedComponent
extends Node
## Unified opt-in for world objects that react to DreamGap.
##
## Add as a child of an enemy / platform / trap and:
##  - TIME_SCALE: the owner drives its motion with get_scaled_delta(delta)
##    pulled from THIS component every physics frame (same pull model the
##    existing moving_platform.gd / test_enemy.gd use directly — those stay
##    as they are; new objects go through this component).
##  - VISUAL_REVEAL: the parent CanvasItem is hidden normally and shown while
##    DreamGap is active (or listen to the signals for custom presentation).
##
## Registration is signal-based (connect on _ready, auto-disconnect on free):
## nothing scans the scene tree, and the player never holds object references.

signal dream_gap_started
signal dream_gap_ended
signal reveal_changed(revealed: bool)

enum DreamEffectType { TIME_SCALE, VISUAL_REVEAL, BOTH }

@export var effect_type: DreamEffectType = DreamEffectType.TIME_SCALE

## Custom slow factor while DreamGap is active. < 0.0 means "use the global
## WorldTimeManager rate". 0.0 freezes the object completely.
@export var custom_time_scale: float = -1.0

## When the effect includes VISUAL_REVEAL, automatically toggle the parent
## CanvasItem's visibility. Disable to drive custom visuals via signals.
@export var auto_apply_reveal: bool = true


func _ready() -> void:
	WorldTimeManager.slow_time_started.connect(_on_slow_time_started)
	WorldTimeManager.slow_time_ended.connect(_on_slow_time_ended)
	if affects_reveal():
		_apply_reveal(WorldTimeManager.is_slow_time_active())


# --- Public API -------------------------------------------------------------

func affects_time() -> bool:
	return effect_type == DreamEffectType.TIME_SCALE or effect_type == DreamEffectType.BOTH


func affects_reveal() -> bool:
	return effect_type == DreamEffectType.VISUAL_REVEAL or effect_type == DreamEffectType.BOTH


## Owners call this from _physics_process instead of using raw delta.
## Objects not affected by time (reveal-only / none) always get real delta.
func get_scaled_delta(delta: float) -> float:
	if not affects_time() or not WorldTimeManager.is_slow_time_active():
		return delta
	if custom_time_scale >= 0.0:
		return delta * custom_time_scale
	return delta * WorldTimeManager.world_time_scale


# --- Internal ---------------------------------------------------------------

func _on_slow_time_started() -> void:
	dream_gap_started.emit()
	if affects_reveal():
		_apply_reveal(true)


func _on_slow_time_ended() -> void:
	dream_gap_ended.emit()
	if affects_reveal():
		_apply_reveal(false)


func _apply_reveal(revealed: bool) -> void:
	if auto_apply_reveal:
		var canvas := get_parent() as CanvasItem
		if canvas != null:
			canvas.visible = revealed
	reveal_changed.emit(revealed)
