class_name LevelBase
extends Node2D
## Lightweight common level lifecycle. New levels and test rooms extend this;
## existing scenes (TestLevel, dream_platforming_test) are NOT forced to
## migrate — they keep working as-is and can adopt LevelBase later.
##
## On _ready it: hard-resets DreamGap (no ACTIVE state may leak across a
## scene change or load), clears session story flags, places the player
## (saved position if the active save points at this scene, otherwise the
## spawn marker) and clears any stale input locks.

signal level_started
signal level_completed

## Stable id for save/progress purposes. Persisted ids must never be renamed.
@export var level_id: StringName = &""

## How the player moves in this level. Movement style is level configuration:
## the level declares it here and the player is told on load. Default keeps
## every existing level side-scrolling.
@export var movement_mode: MovementMode.Mode = MovementMode.Mode.SIDE_SCROLL

## The player node in this level (optional — UI-only scenes leave it unset).
@export var player_path: NodePath

## Marker2D giving the default spawn. Unset = keep the player where the
## scene placed it.
@export var spawn_point_path: NodePath

var _player: Node2D = null


func _ready() -> void:
	WorldTimeManager.reset_state()
	StoryFlagManager.clear_session()
	_player = get_node_or_null(player_path) as Node2D
	_apply_movement_mode()
	_place_player()
	on_level_started()
	level_started.emit()


# --- Hooks for subclasses -----------------------------------------------------

func on_level_started() -> void:
	pass


func on_level_completed() -> void:
	pass


func get_default_spawn_position() -> Vector2:
	var marker := get_node_or_null(spawn_point_path) as Node2D
	if marker != null:
		return marker.global_position
	if _player != null:
		return _player.global_position
	return Vector2.ZERO


# --- Public API ----------------------------------------------------------------

func complete_level() -> void:
	on_level_completed()
	level_completed.emit()


# --- Internal -------------------------------------------------------------------

## Told once per level load, before placement, so the body is already in the
## right mode when the spawn position is applied.
func _apply_movement_mode() -> void:
	if _player != null and _player.has_method("set_movement_mode"):
		_player.set_movement_mode(movement_mode)


func _place_player() -> void:
	if _player == null:
		return
	var pos := get_default_spawn_position()
	# Restore the saved position only when the active save was made in THIS
	# scene; otherwise the level's own spawn wins. A brand-new save names this
	# scene too but carries no real coordinates yet (use_level_spawn), so it
	# must fall through to the spawn marker as well.
	var save := SaveManager.current_save
	if not save.is_empty() \
			and String(save.get("current_scene", "")) == scene_file_path \
			and not bool(save.get("use_level_spawn", false)):
		pos = Vector2(
			float(save.get("player_position_x", pos.x)),
			float(save.get("player_position_y", pos.y)),
		)
	_player.global_position = pos
	if _player.has_method("set_spawn_point"):
		_player.set_spawn_point(pos)
	# Input must never arrive dead from an interrupted lock in a previous scene.
	if _player.has_method("clear_input_locks"):
		_player.clear_input_locks()
