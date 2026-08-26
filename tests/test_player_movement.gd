extends LevelBase
## Test room: player movement, state machine and input lock.
##
## Automated on start (results printed as [TEST:movement] lines):
##  - multi-source input lock / unlock / clear
##  - IDLE after landing, JUMP/FALL/IDLE transition on a programmatic jump
##  - DISABLED state while locked
## Manual (real keyboard): A/D run, Space jump, feel of accel/decel.

@onready var _p: CharacterBody2D = get_node(player_path)
@onready var _status: Label = $UI/StatusLabel

var _pass_count: int = 0
var _fail_count: int = 0
var _transitions: Array[String] = []


func _ready() -> void:
	super._ready()
	_p.state_changed.connect(_on_state_changed)
	_run_self_test.call_deferred()


func _process(_delta: float) -> void:
	_status.text = "State: %s\nLocks: %s\n\nA/D move, Space jump" % [
		_state_name(_p.get_state()),
		str(_p.get_input_lock_sources()),
	]


func _state_name(s: int) -> String:
	return _p.State.keys()[s]


func _on_state_changed(prev: int, cur: int) -> void:
	_transitions.append("%s->%s" % [_state_name(prev), _state_name(cur)])


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass_count += 1
		print("[TEST:movement] PASS  %s" % label)
	else:
		_fail_count += 1
		print("[TEST:movement] FAIL  %s" % label)


func _run_self_test() -> void:
	print("[TEST:movement] --- self-test start ---")

	# Movement mode: a level that says nothing stays side-scrolling. This is
	# the regression guard for the 2.5D depth mode — gravity, jump and floor
	# handling below must keep working exactly as before.
	_check(_p.movement_mode == MovementMode.Mode.SIDE_SCROLL,
		"default movement mode is SIDE_SCROLL")
	_check(_p.motion_mode == CharacterBody2D.MOTION_MODE_GROUNDED,
		"side-scroll keeps GROUNDED motion (floor detection intact)")
	# Origin convention: the node origin is the ground-contact point, so the
	# body box stands entirely above it and a spawn marker marks where the
	# character's feet land.
	var body_shape := _p.get_node("CollisionShape2D") as CollisionShape2D
	_check(is_equal_approx(body_shape.position.y, -_p.get_body_half_extents().y),
		"body collider stands above the origin (origin = feet)")
	var visual := _p.get_node("Visual") as Polygon2D
	var lowest := -INF
	for point: Vector2 in visual.polygon:
		lowest = maxf(lowest, point.y)
	_check(lowest <= 0.5, "player visual is drawn above the origin")

	# Input lock: multiple simultaneous sources.
	_p.lock_input(&"dialogue")
	_p.lock_input(&"cutscene")
	_check(_p.is_input_locked(), "locked with two sources")
	_p.unlock_input(&"dialogue")
	_check(_p.is_input_locked(), "still locked after removing one of two sources")
	_p.unlock_input(&"cutscene")
	_check(not _p.is_input_locked(), "unlocked after all sources removed")
	_p.lock_input(&"stale")
	_p.clear_input_locks()
	_check(not _p.is_input_locked(), "clear_input_locks() recovers from a stale lock")

	# DISABLED state while locked.
	_p.lock_input(&"test")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_p.get_state() == _p.State.DISABLED, "state DISABLED while input locked")
	_p.unlock_input(&"test")

	# Land, then a programmatic jump exercises JUMP -> FALL -> IDLE.
	await get_tree().create_timer(0.6).timeout
	_check(_p.is_on_floor(), "player landed on ground")
	_check(_p.get_state() == _p.State.IDLE, "IDLE while standing still")
	_transitions.clear()
	_p.velocity.y = _p.jump_velocity
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_p.get_state() == _p.State.JUMP, "JUMP while moving upward")
	await get_tree().create_timer(1.2).timeout
	_check(_p.get_state() == _p.State.IDLE, "back to IDLE after the arc")
	_check(_transitions.has("JUMP->FALL"), "saw JUMP->FALL transition (%s)" % str(_transitions))

	print("[TEST:movement] --- done: %d passed, %d failed ---" % [_pass_count, _fail_count])
	print("[TEST:movement] MANUAL: run/jump feel, held-key behavior need a real keyboard.")
	if DisplayServer.get_name() == "headless":
		get_tree().quit(_fail_count)
