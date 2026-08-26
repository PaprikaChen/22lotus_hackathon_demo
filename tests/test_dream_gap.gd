extends LevelBase
## Test room: DreamGap (world slow-time).
##
## Contents: moving platform, patrolling test enemy, a time-affected spinner,
## a reveal-only shape, a both-effects spinner, and an unaffected spinner.
## Automated on start ([TEST:dreamgap] lines): activation, repeat-press no-op,
## measured slow ratio vs an unaffected object, reveal on/off, duration end,
## cooldown gate, cooldown recovery, reset_state() safety.
## Manual: Shift key (slow_time) toggle feel, player speed unchanged by eye,
## pause-and-resume timing.

@onready var _status: Label = $UI/StatusLabel
@onready var _spinner_affected: Node2D = $World/SpinnerAffected
@onready var _spinner_unaffected: Node2D = $World/SpinnerUnaffected
@onready var _reveal_only: Polygon2D = $World/RevealOnly

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	super._ready()
	_run_self_test.call_deferred()


func _process(_delta: float) -> void:
	var wtm := WorldTimeManager
	_status.text = "DreamGap: %s\nworld_time_scale: %.2f\n\nShift = slow time" % [
		["READY", "ACTIVE", "COOLDOWN"][wtm.current_state],
		wtm.world_time_scale,
	]


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass_count += 1
		print("[TEST:dreamgap] PASS  %s" % label)
	else:
		_fail_count += 1
		print("[TEST:dreamgap] FAIL  %s" % label)


func _run_self_test() -> void:
	print("[TEST:dreamgap] --- self-test start ---")
	var wtm := WorldTimeManager
	await get_tree().physics_frame

	_check(wtm.current_state == wtm.SlowTimeState.READY, "starts READY (LevelBase reset)")
	_check(not _reveal_only.visible, "reveal-only object hidden while inactive")

	# Activation.
	_check(wtm.request_slow_time(), "request_slow_time() succeeds when READY")
	_check(wtm.is_slow_time_active(), "state ACTIVE after request")
	_check(is_equal_approx(wtm.world_time_scale, wtm.slow_time_scale),
		"world_time_scale == slow_time_scale while active")
	_check(not wtm.request_slow_time(), "repeated request while ACTIVE is a no-op")
	_check(_reveal_only.visible, "reveal-only object visible while active")

	# Measure affected vs unaffected spinner over ~0.5 s of real time.
	var a0 := _spinner_affected.rotation
	var u0 := _spinner_unaffected.rotation
	await get_tree().create_timer(0.5).timeout
	var a_advance := _spinner_affected.rotation - a0
	var u_advance := _spinner_unaffected.rotation - u0
	var ratio := a_advance / u_advance if not is_zero_approx(u_advance) else -1.0
	_check(absf(ratio - wtm.slow_time_scale) < 0.1,
		"affected/unaffected speed ratio ~= %.2f (measured %.2f)" % [wtm.slow_time_scale, ratio])
	_check(u_advance > 0.0, "unaffected object keeps full speed during DreamGap")

	# Duration runs out on its own.
	await wtm.slow_time_ended
	_check(wtm.current_state == wtm.SlowTimeState.COOLDOWN, "COOLDOWN after duration ends")
	_check(is_equal_approx(wtm.world_time_scale, 1.0), "world speed restored on end")
	_check(not _reveal_only.visible, "reveal-only object hidden again after end")
	_check(not wtm.request_slow_time(), "cannot re-activate during cooldown")

	# Cooldown finishes.
	while wtm.current_state != wtm.SlowTimeState.READY:
		await wtm.slow_time_state_changed
	_check(true, "cooldown finished, READY again")
	_check(wtm.request_slow_time(), "usable again after cooldown")

	# reset_state() must clean up an active gap (load-game / scene-change path).
	wtm.reset_state()
	_check(wtm.current_state == wtm.SlowTimeState.READY, "reset_state() forces READY")
	_check(is_equal_approx(wtm.world_time_scale, 1.0), "reset_state() restores world speed")
	_check(not _reveal_only.visible, "reset_state() restores reveal visuals")

	print("[TEST:dreamgap] --- done: %d passed, %d failed ---" % [_pass_count, _fail_count])
	print("[TEST:dreamgap] MANUAL: player-speed-by-eye, Shift-key toggle, pause/resume timing, UI unaffected.")
	if DisplayServer.get_name() == "headless":
		get_tree().quit(_fail_count)
