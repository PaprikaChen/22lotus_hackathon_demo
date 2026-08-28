class_name Player
extends CharacterBody2D
## Graybox platformer player — the coordinating body only.
##
## Owns: horizontal movement, jump, gravity, floor handling, spawn/respawn,
## a lightweight movement state enum, the source-based input lock and the
## movement mode switch (side-scroll / 2.5D depth).
## Does NOT own: DreamGap timing (child DreamGapAbility + WorldTimeManager),
## interaction targeting (child InteractionDetector), story flags, save
## format or UI.
##
## The player always runs on real `delta`, so the DreamGap ability never
## affects player movement, gravity, jumping or input response.
##
## Movement mode is decided by the LEVEL (LevelBase.movement_mode), never by
## checking a scene name here. SIDE_SCROLL is the default and its code path
## is unchanged from before the 2.5D mode existed.
##
## ORIGIN CONVENTION: the node origin is the GROUND-CONTACT point (the feet),
## not the middle of the body. Side-scroll levels get the body box standing
## above it; 2.5D levels get a shallow footprint centred on it and Y-sort
## against it. Everything that positions the player — spawn markers, saved
## positions, teleports — therefore addresses the point the character stands
## on. Saves written before this convention are migrated by SaveManager
## (save_version 2).

signal direction_changed(facing: int) ## -1 = left, +1 = right
signal state_changed(previous_state: State, current_state: State)

## Lightweight movement states. Presentation systems (animation, sfx) listen
## to state_changed; movement logic never depends on animation resources.
enum State { IDLE, RUN, JUMP, FALL, DISABLED, INTERACT }

## How this player is driven. Levels set it via LevelBase; the default keeps
## every existing scene on the original side-scrolling behaviour.
@export var movement_mode: MovementMode.Mode = MovementMode.Mode.SIDE_SCROLL:
	set = set_movement_mode

## 本关是否允许跳跃。由关卡通过 LevelBase 的 player_can_jump 下发。
## 刻意做成独立布尔而不是新的 MovementMode：它和移动模式正交——
## 2.5D 关卡本来就没有跳跃，横版关卡里"纯步行探索"也是一种合法配置。
@export var jump_enabled: bool = true

## TEST: 原始横向速度为 300.0；当前临时提高为 5 倍，测试后恢复此值。
@export var move_speed: float = 1500.0
@export var acceleration: float = 2000.0
@export var deceleration: float = 2600.0
@export var jump_velocity: float = -650.0
@export var gravity: float = 1600.0
@export var max_fall_speed: float = 1400.0

@export_group("Depth (2.5D)")
## Depth speed along y. Deliberately far below move_speed so left/right stays
## the dominant direction and forward/back only adjusts where you stand.
## TEST: 原始纵深速度为 110.0；当前临时提高为 5 倍，测试后恢复此值。
@export var depth_move_speed: float = 550.0
@export var depth_acceleration: float = 1100.0
@export var depth_deceleration: float = 1500.0

@onready var _body_collision: CollisionShape2D = $CollisionShape2D
@onready var _depth_collision: CollisionShape2D = $DepthCollisionShape2D
@onready var _detector: Area2D = $InteractionDetector

var _facing: int = 1
var _spawn_point: Vector2
var _state: State = State.IDLE
## Authored offset of the interaction volume (body-centred in side-scroll).
var _detector_offset: Vector2 = Vector2.ZERO

## Source-based input lock: e.g. lock_input(&"dialogue"). Control returns
## only when ALL sources have unlocked. Other systems must never flip a
## bare boolean on the player.
var _input_locks: Dictionary = {}
var _interacting: bool = false

# Rising-edge tracking for "press once" actions. We detect the edge manually
# from is_action_pressed() (rather than is_action_just_pressed) so the same
# code path is driven identically by a real keyboard and by injected/debugger
# input during automated testing.
var _jump_held: bool = false


func _ready() -> void:
	_detector_offset = _detector.position
	_apply_mode_geometry()
	_spawn_point = global_position


# --- Movement mode -----------------------------------------------------------

## Levels call this (through LevelBase) when they load. Switching clears
## leftover velocity so a fall speed from a platforming level can never leak
## into a depth level as backward drift.
func set_movement_mode(mode: MovementMode.Mode) -> void:
	movement_mode = mode
	# Depth mode is genuine free 2D motion: no floor, no snapping, no
	# up-direction — that is exactly what FLOATING means to CharacterBody2D.
	motion_mode = (CharacterBody2D.MOTION_MODE_FLOATING
		if mode == MovementMode.Mode.DEPTH_2_5D
		else CharacterBody2D.MOTION_MODE_GROUNDED)
	velocity = Vector2.ZERO
	# The scene may set this property before the children exist; _ready
	# applies the geometry again once they do.
	if is_node_ready():
		_apply_mode_geometry()


func is_depth_mode() -> bool:
	return movement_mode == MovementMode.Mode.DEPTH_2_5D


## The local y axis means different things per mode, so the collider does
## too: a standing body box above the feet in side-scroll, a shallow ground
## footprint centred on the contact point in 2.5D (otherwise the "tall" box
## would reach 48px into the depth axis and seal off narrow lanes).
func _apply_mode_geometry() -> void:
	var depth := is_depth_mode()
	_body_collision.disabled = depth
	_depth_collision.disabled = not depth
	# Interaction reach is symmetric around the body in side-scroll and
	# around the ground point in depth mode.
	_detector.position = Vector2.ZERO if depth else _detector_offset


## Half size of the collider active in the current mode. Levels use it to
## reason about how close the body can get to a wall; never hardcode 24.
func get_body_half_extents() -> Vector2:
	var shape := _depth_collision if is_depth_mode() else _body_collision
	var rect := shape.shape as RectangleShape2D
	return rect.size * 0.5 if rect != null else Vector2.ZERO


# --- Spawn ------------------------------------------------------------------

## Called by the level to define where respawns land.
func set_spawn_point(p: Vector2) -> void:
	_spawn_point = p


func respawn() -> void:
	global_position = _spawn_point
	velocity = Vector2.ZERO


# --- Input lock --------------------------------------------------------------

func lock_input(source: StringName) -> void:
	_input_locks[source] = true


func unlock_input(source: StringName) -> void:
	_input_locks.erase(source)


func is_input_locked() -> bool:
	return not _input_locks.is_empty()


func get_input_lock_sources() -> Array:
	return _input_locks.keys()


## Safety hatch for load-game / scene transitions so input can never stay
## permanently dead after a flow was interrupted mid-lock.
func clear_input_locks() -> void:
	_input_locks.clear()
	_interacting = false


## Marks the current lock as an interaction (state shows INTERACT instead of
## DISABLED). Call in pairs from interaction/dialogue flows.
func begin_interaction(source: StringName = &"interaction") -> void:
	_interacting = true
	lock_input(source)


func end_interaction(source: StringName = &"interaction") -> void:
	unlock_input(source)
	if not is_input_locked():
		_interacting = false


# --- State -------------------------------------------------------------------

func get_state() -> State:
	return _state


# --- Movement ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var input_allowed := not is_input_locked()
	if movement_mode == MovementMode.Mode.DEPTH_2_5D:
		_process_depth(delta, input_allowed)
	else:
		_process_side_scroll(delta, input_allowed)
	move_and_slide()
	_update_state()


## Classic platforming: y is height, gravity and jump apply.
func _process_side_scroll(delta: float, input_allowed: bool) -> void:
	# Gravity (real time — never scaled).
	if not is_on_floor():
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)

	# Jump (rising edge while grounded). Edge state is tracked even while
	# locked so holding jump through an unlock cannot fire a stale press.
	var jump_pressed := Input.is_action_pressed("jump")
	if input_allowed and jump_enabled and jump_pressed and not _jump_held and is_on_floor():
		velocity.y = jump_velocity
	_jump_held = jump_pressed

	# Horizontal movement with acceleration / friction.
	var dir := Input.get_axis("move_left", "move_right") if input_allowed else 0.0
	if not is_zero_approx(dir):
		velocity.x = move_toward(velocity.x, dir * move_speed, acceleration * delta)
		_update_facing(1 if dir > 0.0 else -1)
	else:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)


## 2.5D: y is DEPTH, not height. No gravity, no jump (§ no Z-axis jump yet);
## depth is much slower than horizontal so the level still plays as a
## side-scroller with a little room to step forward/back.
func _process_depth(delta: float, input_allowed: bool) -> void:
	# Keep tracking the jump edge even though jumping is disabled here, so a
	# key held across a scene change cannot fire a stale press after landing
	# back in a side-scrolling level.
	_jump_held = Input.is_action_pressed("jump")

	# get_vector() normalizes, so diagonal input is never faster than a
	# single axis before the per-axis speeds are applied.
	var input := (Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if input_allowed else Vector2.ZERO)
	var target := get_depth_velocity_target(input)

	var accel_x := acceleration if not is_zero_approx(target.x) else deceleration
	var accel_y := depth_acceleration if not is_zero_approx(target.y) else depth_deceleration
	velocity.x = move_toward(velocity.x, target.x, accel_x * delta)
	velocity.y = move_toward(velocity.y, target.y, accel_y * delta)

	if not is_zero_approx(input.x):
		_update_facing(1 if input.x > 0.0 else -1)


## Maps a (normalized) input vector to the depth-mode target velocity.
## Split out so the speed relationship is testable without injecting keys.
func get_depth_velocity_target(input: Vector2) -> Vector2:
	return Vector2(input.x * move_speed, input.y * depth_move_speed)


## 当前朝向：-1 = 左，+1 = 右。表现层进场时需要先对齐一次，
## 不能只依赖 direction_changed（那是变化时才发）。
func get_facing() -> int:
	return _facing


func _update_facing(new_facing: int) -> void:
	if new_facing != _facing:
		_facing = new_facing
		direction_changed.emit(_facing)


func _update_state() -> void:
	var new_state: State
	if is_input_locked():
		new_state = State.INTERACT if _interacting else State.DISABLED
	elif movement_mode == MovementMode.Mode.DEPTH_2_5D:
		# No floor and no air time in depth mode — only moving or standing.
		new_state = State.RUN if velocity.length() > 5.0 else State.IDLE
	elif not is_on_floor():
		new_state = State.JUMP if velocity.y < 0.0 else State.FALL
	elif absf(velocity.x) > 5.0:
		new_state = State.RUN
	else:
		new_state = State.IDLE
	if new_state != _state:
		var previous := _state
		_state = new_state
		state_changed.emit(previous, _state)
