extends LevelBase
## Integration graybox room — every base system working together in one
## small level slice, structured the same way a real level will be.
##
## Route: spawn → save point → pit with a fast moving platform (Shift slow
## time makes boarding easier; the 山纹奇石 memory pickup floats over the
## platform's path so riding it — no jump — brings it into E range) →
## patrolling enemy → stone investigation spot (advances the memory) →
## key pickup → locked door → goal.
##
## Manual play: A/D move, Space jump, Shift slow time, E interact.
## Headless mode runs a scripted smoke test of the system interactions
## instead ([TEST:integration] lines) and quits by itself.

const KEY_FLAG := &"test.integration.key_found"

@onready var _p: CharacterBody2D = get_node(player_path)
@onready var _detector: InteractionDetector = _p.get_node("InteractionDetector")
@onready var _status: Label = $UI/StatusLabel
@onready var _prompt_label: Label = $UI/PromptLabel
@onready var _result_label: Label = $UI/ResultLabel
@onready var _key: Interactable = $World/KeyPickup
@onready var _door: StoryDoor = $World/Door
@onready var _save_point: SavePoint = $World/SavePoint
@onready var _stone_pickup: Interactable = $World/StonePickup
@onready var _stone_spot: Interactable = $World/StoneSpot
@onready var _memory_box: CanvasLayer = $MemoryBoxUI
@onready var _death_zone: Area2D = $World/DeathZone
@onready var _goal: Area2D = $World/Goal

const STONE_MEMORY := &"mountain_stone"

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	super._ready()
	_detector.prompt_changed.connect(_on_prompt_changed)
	_death_zone.body_entered.connect(_on_death_zone_entered)
	_goal.body_entered.connect(_on_goal_entered)
	_key.interacted.connect(func(_pl: Node) -> void: _show("拾取了钥匙"))
	_door.interacted.connect(func(_pl: Node) -> void: _show("门开了"))
	_door.interaction_blocked.connect(func(_pl: Node) -> void: _show("门锁着——先去找钥匙"))
	_save_point.save_finished.connect(_show)
	if DisplayServer.get_name() == "headless":
		_run_smoke_test.call_deferred()


func _process(_delta: float) -> void:
	var stone_status := "未获得"
	if MemoryManager.has_memory(STONE_MEMORY):
		stone_status = "阶段 %d" % (MemoryManager.get_current_stage(STONE_MEMORY) + 1)
	_status.text = "DreamGap: %s    钥匙: %s    山纹奇石: %s\nA/D 移动   空格 跳   Shift 慢时间   E 交互   Tab 梦奁" % [
		["READY", "ACTIVE", "COOLDOWN"][WorldTimeManager.current_state],
		"已获得" if StoryFlagManager.has_flag(KEY_FLAG) else "未获得",
		stone_status,
	]


func _show(message: String) -> void:
	_result_label.text = message


func _on_prompt_changed(text: String) -> void:
	_prompt_label.text = "[E] %s" % text if not text.is_empty() else ""


func _on_death_zone_entered(body: Node) -> void:
	if body == _p:
		_p.respawn()
		_show("掉进深渊——已重生")


func _on_goal_entered(body: Node) -> void:
	if body == _p:
		_show("到达终点！")
		complete_level()


# --- Headless smoke test ------------------------------------------------------

func _check(cond: bool, label: String) -> void:
	if cond:
		_pass_count += 1
		print("[TEST:integration] PASS  %s" % label)
	else:
		_fail_count += 1
		print("[TEST:integration] FAIL  %s" % label)


func _run_smoke_test() -> void:
	print("[TEST:integration] --- smoke test start ---")
	await get_tree().physics_frame

	_check(WorldTimeManager.current_state == WorldTimeManager.SlowTimeState.READY,
		"DreamGap READY on level start (LevelBase reset)")

	# Door before key: blocked path, stays closed and solid.
	_door.interact(_p)
	_check(not _door.is_open(), "door stays closed without the key")

	# Key: sets the persistent flag, consumes itself.
	_key.interact(_p)
	_check(StoryFlagManager.has_flag(KEY_FLAG), "key pickup sets the story flag")
	_check(not _key.can_interact(_p), "key is one-shot")

	# Door after key: opens.
	_door.interact(_p)
	_check(_door.is_open(), "door opens once the key flag is set")

	# Save point without an active slot must not write anything.
	_save_point.interact(_p)
	_check(SaveManager.current_slot == -1, "save point skips writing without an active slot")

	# Memory keepsake flow: pickup unlocks, investigation advances the SAME
	# keepsake, the box opens/closes cleanly inside the level.
	_stone_pickup.interact(_p)
	_check(MemoryManager.has_memory(STONE_MEMORY)
		and MemoryManager.get_current_stage(STONE_MEMORY) == 0,
		"stone pickup unlocks the memory at stage 0")
	_stone_spot.interact(_p)
	_check(MemoryManager.get_current_stage(STONE_MEMORY) == 1,
		"investigation advances the same memory to stage 1")
	_check(StoryFlagManager.has_flag(&"test.integration.stone_checked"),
		"investigation also records its story flag")
	_memory_box.open()
	_check(_memory_box.is_open() and _p.is_input_locked() and get_tree().paused,
		"memory box opens in-level (locked + paused)")
	_memory_box.close()
	_check(not _p.is_input_locked() and not get_tree().paused,
		"memory box closes cleanly in-level")
	MemoryManager.reset()

	# Ability still usable inside the level; leave the world clean.
	_check(WorldTimeManager.request_slow_time(), "DreamGap usable inside the level")
	WorldTimeManager.reset_state()
	_check(is_equal_approx(WorldTimeManager.world_time_scale, 1.0), "world speed clean after reset")

	print("[TEST:integration] --- done: %d passed, %d failed ---" % [_pass_count, _fail_count])
	print("[TEST:integration] MANUAL: full playthrough (platform ride, enemy dodge, goal) needs a real keyboard.")
	if DisplayServer.get_name() == "headless":
		get_tree().quit(_fail_count)
