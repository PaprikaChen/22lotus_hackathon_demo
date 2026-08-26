extends LevelBase
## Test scene for the 梦奁 memory keepsake system.
##
## Manual: buttons unlock/advance the three sample keepsakes and drive
## save/clear/load on slot 3 (the original slot-3 file is snapshotted to
## save_slot_3.backup.json before the first test write). Tab opens/closes
## the box, Esc closes, arrows/mouse navigate slots.
## Headless: runs the automated checklist ([TEST:memorybox] lines) with an
## in-memory slot-3 backup/restore, then quits.

const TEST_SLOT := 3
const SLOT_PATH := "user://save_slot_3.json"
const DISK_BACKUP_PATH := "user://save_slot_3.backup.json"

const STONE := &"mountain_stone"
const LANTERN := &"extinguished_water_lantern"
const HAIRPIN := &"mountain_bird_hairpin"

@onready var _p: CharacterBody2D = get_node(player_path)
@onready var _box: CanvasLayer = $MemoryBoxUI
@onready var _toast: CanvasLayer = $MemoryToast
@onready var _info: Label = $UI/InfoLabel

var _pass_count: int = 0
var _fail_count: int = 0
var _backup_text: String = ""
var _had_backup: bool = false
var _disk_backup_done: bool = false


func _ready() -> void:
	super._ready()
	$UI/Buttons/UnlockStone.pressed.connect(func() -> void: MemoryManager.unlock_memory(STONE))
	$UI/Buttons/AdvanceStone.pressed.connect(func() -> void: MemoryManager.advance_memory(STONE))
	$UI/Buttons/UnlockLantern.pressed.connect(func() -> void: MemoryManager.unlock_memory(LANTERN))
	$UI/Buttons/AdvanceLantern.pressed.connect(func() -> void: MemoryManager.advance_memory(LANTERN))
	$UI/Buttons/UnlockHairpin.pressed.connect(func() -> void: MemoryManager.unlock_memory(HAIRPIN))
	$UI/Buttons/AdvanceHairpin.pressed.connect(func() -> void: MemoryManager.advance_memory(HAIRPIN))
	$UI/Buttons/SaveButton.pressed.connect(_on_save_pressed)
	$UI/Buttons/ClearButton.pressed.connect(func() -> void: MemoryManager.reset())
	$UI/Buttons/LoadButton.pressed.connect(func() -> void: SaveManager.load_game(TEST_SLOT))
	if DisplayServer.get_name() == "headless":
		_run_self_test.call_deferred()


func _process(_delta: float) -> void:
	_info.text = "已解锁信物: %d    梦奁: %s    暂停: %s\n输入锁: %s\nTab 开关梦奁   Esc 关闭   A/D 移动 空格 跳" % [
		MemoryManager.get_unlocked_memories().size(),
		"开" if _box.is_open() else "关",
		str(get_tree().paused),
		str(_p.get_input_lock_sources()),
	]


# --- Manual save helpers -------------------------------------------------------

func _on_save_pressed() -> void:
	# One-time safety net for manual testing: keep the original slot 3.
	if not _disk_backup_done and FileAccess.file_exists(SLOT_PATH) \
			and not FileAccess.file_exists(DISK_BACKUP_PATH):
		DirAccess.copy_absolute(SLOT_PATH, DISK_BACKUP_PATH)
		print("[test_memory_box] slot 3 backed up to %s" % DISK_BACKUP_PATH)
	_disk_backup_done = true
	var data := SaveManager.current_save.duplicate(true)
	if data.is_empty():
		data = _minimal_save_dict()
	SaveManager.save_game(TEST_SLOT, data)


func _minimal_save_dict() -> Dictionary:
	return {
		"save_slot_id": TEST_SLOT,
		"created_at": "2026-01-01 00:00:00",
		"last_saved_at": "2026-01-01 00:00:00",
		"current_scene": scene_file_path,
		"checkpoint_id": "start",
		"player_position_x": 200.0,
		"player_position_y": 480.0,
		"play_time_seconds": 0.0,
	}


func _write_raw(text: String) -> void:
	var f := FileAccess.open(SLOT_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


# --- Automated checklist --------------------------------------------------------

func _check(cond: bool, label: String) -> void:
	if cond:
		_pass_count += 1
		print("[TEST:memorybox] PASS  %s" % label)
	else:
		_fail_count += 1
		print("[TEST:memorybox] FAIL  %s" % label)


func _grid() -> GridContainer:
	return _box.get_node("Root/MemoryGrid") as GridContainer


func _press_slot(index: int) -> void:
	(_grid().get_child(index) as Button).pressed.emit()


func _run_self_test() -> void:
	print("[TEST:memorybox] --- self-test start (slot %d backed up in memory) ---" % TEST_SLOT)
	_had_backup = FileAccess.file_exists(SLOT_PATH)
	if _had_backup:
		var f := FileAccess.open(SLOT_PATH, FileAccess.READ)
		_backup_text = f.get_as_text()
		f.close()
	MemoryManager.reset()
	await get_tree().physics_frame

	# 1. Empty start.
	_check(MemoryManager.get_unlocked_memories().is_empty(), "initial box is empty")

	# 2. Unlock -> NEW + toast.
	var toasts_before := int(_toast.pending_count())
	_check(MemoryManager.unlock_memory(STONE), "unlock_memory returns true first time")
	_check(MemoryManager.get_unread_state(STONE) == MemoryManager.UNREAD_NEW, "state NEW after unlock")
	_check(int(_toast.pending_count()) > toasts_before, "unlock queues a toast")

	# 3-4. Open box, see slot, select clears NEW.
	_box.open()
	_check(_box.is_open() and _grid().get_child_count() == 1, "box shows 1 slot after unlock")
	_press_slot(0)
	_check(MemoryManager.get_unread_state(STONE) == MemoryManager.UNREAD_NONE,
		"selecting the slot clears NEW")
	_box.close()

	# 5-6. Advance -> UPDATED, description switches stage.
	_check(MemoryManager.advance_memory(STONE), "advance_memory returns true")
	_check(MemoryManager.get_unread_state(STONE) == MemoryManager.UNREAD_UPDATED, "state UPDATED")
	_check(MemoryManager.get_current_stage(STONE) == 1, "stage advanced to 1")
	_box.open()
	_press_slot(0)
	var entry := MemoryManager.get_memory_data(STONE)
	var desc: String = (_box.get_node("Root/DetailPanel/Description") as Label).text
	_check(desc.contains(entry.get_stage_description(1).substr(0, 8)),
		"detail shows the stage-1 description")
	# 7. Selecting cleared UPDATED.
	_check(MemoryManager.get_unread_state(STONE) == MemoryManager.UNREAD_NONE,
		"selecting clears UPDATED")
	_box.close()

	# 8-9. No repeated unlock / no advance past the last stage, no extra toasts.
	toasts_before = int(_toast.pending_count())
	_check(not MemoryManager.unlock_memory(STONE), "re-unlock is a no-op")
	_check(not MemoryManager.advance_memory(STONE), "advance past last stage is a no-op")
	_check(int(_toast.pending_count()) == toasts_before, "no-ops queue no toasts")

	# 10. Stage validation and regress rules.
	_check(not MemoryManager.set_memory_stage(STONE, 5), "out-of-range stage rejected")
	_check(not MemoryManager.set_memory_stage(STONE, 1), "same-stage set is a silent no-op")
	_check(not MemoryManager.set_memory_stage(STONE, 0), "regress rejected by default")
	_check(MemoryManager.set_memory_stage(STONE, 0, true), "regress allowed with explicit flag")
	MemoryManager.set_memory_stage(STONE, 1)
	MemoryManager.mark_as_read(STONE)

	# 11. Multiple unlocks queue toasts in order.
	toasts_before = int(_toast.pending_count())
	MemoryManager.unlock_memory(LANTERN)
	MemoryManager.unlock_memory(HAIRPIN)
	_check(int(_toast.pending_count()) >= toasts_before + 2, "rapid unlocks all queued (FIFO)")

	# 12-13. Input lock + world pause while open.
	_box.open()
	_check(_p.is_input_locked(), "player input locked while box is open")
	_check(get_tree().paused, "world paused while box is open")
	_box.close()
	_check(not _p.is_input_locked(), "player input restored on close")
	_check(not get_tree().paused, "world unpaused on close")

	# 14. Foreign input locks survive the box closing.
	_box.open()
	_p.lock_input(&"dialogue")
	_box.close()
	_check(_p.is_input_locked(), "dialogue lock kept after box closes")
	_p.unlock_input(&"dialogue")

	# Pre-existing pause is respected.
	get_tree().paused = true
	_box.open()
	_box.close()
	_check(get_tree().paused, "pre-existing pause not cancelled by the box")
	get_tree().paused = false

	# 15. DreamGap: cannot start while open (lock gates the ability input),
	# and an active gap freezes instead of draining.
	WorldTimeManager.request_slow_time()
	var remaining_before := WorldTimeManager.get_active_time_remaining()
	_box.open()
	_check(_p.is_input_locked(), "ability input gated while box open (player locked)")
	await get_tree().create_timer(0.4, true).timeout
	_check(is_equal_approx(WorldTimeManager.get_active_time_remaining(), remaining_before),
		"active DreamGap frozen while box open")
	_box.close()
	_check(WorldTimeManager.is_slow_time_active(), "DreamGap resumes after close")
	WorldTimeManager.reset_state()
	_check(is_equal_approx(WorldTimeManager.world_time_scale, 1.0), "world speed clean afterwards")

	# 16. Save / clear / load round trip via SaveManager.
	var state_before := MemoryManager.get_save_data()
	_check(SaveManager.save_game(TEST_SLOT, _minimal_save_dict()), "save_game writes memories")
	MemoryManager.reset()
	_check(MemoryManager.get_unlocked_memories().is_empty(), "runtime state cleared")
	SaveManager.load_game(TEST_SLOT)
	_check(MemoryManager.get_save_data() == state_before, "load restores identical memory state")

	# 17. Legacy save without "memories" loads as empty.
	_write_raw(JSON.stringify(_minimal_save_dict()))
	SaveManager.load_game(TEST_SLOT)
	_check(MemoryManager.get_unlocked_memories().is_empty(),
		"legacy save (no memories field) loads as empty box")

	# 18. Invalid stage / unread values sanitized on load.
	var bad := _minimal_save_dict()
	bad["memories"] = {String(STONE): {"unlocked": true, "current_stage": 99, "unread_state": "??"}}
	_write_raw(JSON.stringify(bad))
	SaveManager.load_game(TEST_SLOT)
	_check(MemoryManager.get_current_stage(STONE) == entry.get_last_stage_index(),
		"out-of-range saved stage clamped to last stage")
	_check(MemoryManager.get_unread_state(STONE) == MemoryManager.UNREAD_NONE,
		"invalid unread value normalized")

	# 19. Empty state UI.
	MemoryManager.reset()
	_box.open()
	_check((_box.get_node("Root/EmptyLabel") as Label).visible, "empty state label shown")
	_check(_grid().get_child_count() == 0, "no slots when box is empty")
	_box.close()

	# Cleanup: restore slot 3 and leave global state clean.
	if _had_backup:
		_write_raw(_backup_text)
	elif FileAccess.file_exists(SLOT_PATH):
		DirAccess.remove_absolute(SLOT_PATH)
	MemoryManager.reset()
	StoryFlagManager.reset()
	SaveManager.current_slot = -1
	SaveManager.current_save = {}
	get_tree().paused = false

	print("[TEST:memorybox] --- done: %d passed, %d failed (slot %d restored) ---" % [
		_pass_count, _fail_count, TEST_SLOT])
	print("[TEST:memorybox] MANUAL: Tab/Esc key presses, mouse + arrow-key slot navigation, toast visuals.")
	if DisplayServer.get_name() == "headless":
		get_tree().quit(_fail_count)
