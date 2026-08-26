extends Node
## Sequential exploration-area flow inside ONE level scene — no
## change_scene_to_file() involved. Areas are the ordered children of the
## AreaContainer (each with exploration_area.gd attached).
##
## Switch flow: right-edge ExitTrigger goes forward, left-edge
## ExitTriggerLeft goes back → lock player input (source "area_switch", so
## dialogue/cutscene locks are never touched) → fade to black → teleport the
## player to the target area's spawn (left SpawnPoint going forward,
## SpawnPointRight coming back) → move Camera2D limits → fade back → unlock.
## `is_switching` blocks re-entry; the last area has no right trigger and
## the first has no left one, so the sequence cannot escape its bounds.
##
## Player control, interaction text, DreamGap and UI logic do NOT live here.

signal area_changed(area_index: int)

const LOCK_SOURCE := &"area_switch"
const FADE_SECONDS := 0.25
const CAMERA_LIMIT_TOP := 0
const CAMERA_LIMIT_BOTTOM := 648

@export var area_container_path: NodePath
@export var player_path: NodePath
@export var camera_path: NodePath
## Optional fullscreen ColorRect used for the fade (alpha is animated).
@export var fade_rect_path: NodePath

var current_area_index: int = 0
var is_switching: bool = false

## Untyped on purpose: elements are Node2D with exploration_area.gd attached,
## accessed through its methods.
var _areas: Array = []
var _player: Node2D = null
var _camera: Camera2D = null
var _fade: ColorRect = null


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node2D
	_camera = get_node_or_null(camera_path) as Camera2D
	_fade = get_node_or_null(fade_rect_path) as ColorRect
	var container := get_node_or_null(area_container_path)
	if container == null:
		push_warning("AreaFlowController: area container not found; flow disabled.")
		return
	for child in container.get_children():
		if child is Node2D and child.has_method("get_exit_trigger"):
			_areas.append(child)
	for i in _areas.size():
		var trigger: Area2D = _areas[i].get_exit_trigger()
		if trigger != null:
			if i + 1 >= _areas.size():
				push_warning("AreaFlowController: last area has an ExitTrigger; ignored.")
			else:
				trigger.body_entered.connect(_on_exit_trigger_entered.bind(i + 1, false))
				# Authoring visuals on triggers are editor-only.
				trigger.visible = false
		var left_trigger: Area2D = _areas[i].get_left_exit_trigger()
		if left_trigger != null:
			if i == 0:
				push_warning("AreaFlowController: first area has an ExitTriggerLeft; ignored.")
			else:
				left_trigger.body_entered.connect(_on_exit_trigger_entered.bind(i - 1, true))
				left_trigger.visible = false
	if _fade != null:
		_fade.color.a = 0.0
	# Deferred so LevelBase (the scene root, whose _ready runs after this
	# child's) has already placed the player — including a save restore that
	# may land in a later area.
	_initialize_current_area.call_deferred()


func _initialize_current_area() -> void:
	if _areas.is_empty():
		return
	var index := 0
	if _player != null:
		for i in _areas.size():
			if _areas[i].contains_x(_player.global_position.x):
				index = i
				break
	current_area_index = index
	_apply_area_camera(index)
	area_changed.emit(index)


# --- Switching --------------------------------------------------------------

## enter_from_right: place the player at the target area's SpawnPointRight
## (walking backwards) instead of its left SpawnPoint.
func switch_to_area(next_area_index: int, enter_from_right: bool = false) -> void:
	if is_switching:
		return
	if next_area_index < 0 or next_area_index >= _areas.size():
		return
	if next_area_index == current_area_index:
		return
	is_switching = true
	_do_switch(next_area_index, enter_from_right)


func _on_exit_trigger_entered(body: Node, next_index: int, enter_from_right: bool) -> void:
	if body != _player:
		return
	switch_to_area(next_index, enter_from_right)


func _do_switch(index: int, enter_from_right: bool) -> void:
	if _player != null and _player.has_method("lock_input"):
		_player.lock_input(LOCK_SOURCE)
	if _player is CharacterBody2D:
		(_player as CharacterBody2D).velocity = Vector2.ZERO
	await _fade_to(1.0)

	var spawn: Vector2 = _areas[index].get_spawn_position_right() if enter_from_right \
			else _areas[index].get_spawn_position()
	if _player != null:
		_player.global_position = spawn
		if _player.has_method("set_spawn_point"):
			_player.set_spawn_point(spawn)
	_apply_area_camera(index)
	current_area_index = index
	area_changed.emit(index)

	await _fade_to(0.0)
	if _player != null and _player.has_method("unlock_input"):
		_player.unlock_input(LOCK_SOURCE)
	is_switching = false


func _apply_area_camera(index: int) -> void:
	if _camera == null:
		return
	var area: Node2D = _areas[index]
	_camera.limit_left = int(area.get_camera_limit_left_world())
	_camera.limit_right = int(area.get_camera_limit_right_world())
	_camera.limit_top = CAMERA_LIMIT_TOP
	_camera.limit_bottom = CAMERA_LIMIT_BOTTOM
	# Snap to the area immediately so camera and player never desync during
	# the black frame; the level's follow logic takes over next frame.
	_camera.global_position.x = area.get_spawn_position().x
	_camera.reset_smoothing()


func _fade_to(target_alpha: float) -> void:
	if _fade == null:
		return
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", target_alpha, FADE_SECONDS)
	await tween.finished
