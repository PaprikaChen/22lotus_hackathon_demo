extends LevelBase
## Test room: unified interaction system.
##
## Contents: SignA (dialogue-sim 0.5 s), SignB (adjacent to A, higher
## priority), OneShotC, LockedD (needs test.interaction.locked_door_key with a blocked
## fallback). Automated on start ([TEST:interaction] lines): target picking,
## priority overlap, prompt clearing, one-shot consumption, flag gating with
## fallback, input lock during simulated dialogue.
## Manual: walk with A/D and press E to interact; prompt label follows.

@onready var _p: CharacterBody2D = get_node(player_path)
@onready var _detector: InteractionDetector = _p.get_node("InteractionDetector")
@onready var _prompt_label: Label = $UI/PromptLabel
@onready var _result_label: Label = $UI/ResultLabel
@onready var _sign_a: Interactable = $World/SignA
@onready var _sign_b: Interactable = $World/SignB
@onready var _one_shot_c: Interactable = $World/OneShotC
@onready var _locked_d: Interactable = $World/LockedD

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	super._ready()
	_detector.prompt_changed.connect(_on_prompt_changed)
	# On-screen feedback so manual testing does not depend on the console.
	for obj: Interactable in [_sign_a, _sign_b, _one_shot_c, _locked_d]:
		obj.interacted.connect(_on_object_interacted.bind(obj))
		obj.interaction_blocked.connect(_on_object_blocked.bind(obj))
	# Picked-up one-shot visibly disappears.
	_one_shot_c.interacted.connect(
		func(_player: Node) -> void: (_one_shot_c.get_node("Visual") as Polygon2D).visible = false)
	_run_self_test.call_deferred()


func _on_prompt_changed(text: String) -> void:
	_prompt_label.text = "[E] %s" % text if not text.is_empty() else ""


func _on_object_interacted(_player: Node, obj: Interactable) -> void:
	_result_label.text = "已触发：%s（%s）" % [obj.display_name, obj.prompt_text]


func _on_object_blocked(_player: Node, obj: Interactable) -> void:
	_result_label.text = "无法触发：%s —— %s" % [obj.display_name, obj.get_interaction_prompt()]


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass_count += 1
		print("[TEST:interaction] PASS  %s" % label)
	else:
		_fail_count += 1
		print("[TEST:interaction] FAIL  %s" % label)


## Teleports the player and waits for the physics server to refresh overlaps.
func _move_player_to(pos: Vector2) -> void:
	_p.global_position = pos
	_p.velocity = Vector2.ZERO
	for i in 3:
		await get_tree().physics_frame


func _run_self_test() -> void:
	print("[TEST:interaction] --- self-test start ---")

	# Single object in range.
	await _move_player_to(_one_shot_c.global_position + Vector2(0, -30))
	_check(_detector.get_current_target() == _one_shot_c, "nearest single object targeted")

	# Out of range clears target and prompt.
	await _move_player_to(Vector2(150, 420))
	_check(_detector.get_current_target() == null, "target cleared after leaving range")
	_check(_prompt_label.text.is_empty(), "prompt cleared after leaving range")

	# Two overlapping objects: higher priority wins.
	await _move_player_to((_sign_a.global_position + _sign_b.global_position) / 2.0 + Vector2(0, -30))
	_check(_detector.get_current_target() == _sign_b,
		"higher-priority object wins in overlap (B over A)")

	# One-shot consumes exactly once and drops out of targeting.
	_one_shot_c.interact(_p)
	_one_shot_c.interact(_p)
	_check(_one_shot_c.interact_count == 1, "one-shot object fires exactly once")
	await _move_player_to(_one_shot_c.global_position + Vector2(0, -30))
	_check(_detector.get_current_target() != _one_shot_c,
		"consumed one-shot no longer targeted")

	# Flag-gated object: blocked fallback first, works after flag is set.
	await _move_player_to(_locked_d.global_position + Vector2(0, -30))
	_check(_locked_d.get_interaction_prompt() == _locked_d.blocked_prompt_text,
		"blocked prompt shown while flag missing")
	_locked_d.interact(_p)
	_check(_locked_d.blocked_count == 1 and _locked_d.interact_count == 0,
		"blocked path taken while flag missing")
	StoryFlagManager.set_flag(&"test.interaction.locked_door_key")
	_locked_d.interact(_p)
	_check(_locked_d.interact_count == 1, "interaction works after flag set")
	_check(_locked_d.get_interaction_prompt() == _locked_d.prompt_text,
		"normal prompt restored after flag set")
	StoryFlagManager.clear_flag(&"test.interaction.locked_door_key")

	# Simulated dialogue locks input for its duration, then restores control.
	await _move_player_to(_sign_a.global_position + Vector2(-40, -30))
	_sign_a.interact(_p)
	await get_tree().physics_frame
	_check(_p.is_input_locked(), "input locked during simulated dialogue")
	_check(_p.get_state() == _p.State.INTERACT, "player state INTERACT during dialogue")
	await get_tree().create_timer(0.8).timeout
	_check(not _p.is_input_locked(), "input restored after dialogue ends")

	print("[TEST:interaction] --- done: %d passed, %d failed ---" % [_pass_count, _fail_count])
	print("[TEST:interaction] MANUAL: E-key press path and no re-trigger while a dialogue holds the lock.")
	if DisplayServer.get_name() == "headless":
		get_tree().quit(_fail_count)
