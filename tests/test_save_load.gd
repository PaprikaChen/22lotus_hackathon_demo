extends Node2D
## Test scene: save / load compatibility and safety. Fully automated
## ([TEST:save] lines) — no player needed.
##
## Uses slot 3 only, and backs up / restores any real file living there so
## running the test never destroys user data.
##
## Covers: new save has save_version + story_flags, story-flag round trip,
## legacy (version-less, flag-less) saves stay readable, corrupt JSON does
## not crash, saving over a corrupt file recovers it, load-game clears an
## active DreamGap, session flags stay out of the save.

const TEST_SLOT: int = 3
const SLOT_PATH: String = "user://save_slot_3.json"

var _pass_count: int = 0
var _fail_count: int = 0
var _backup_text: String = ""
var _had_backup: bool = false


func _ready() -> void:
	_run_self_test.call_deferred()


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass_count += 1
		print("[TEST:save] PASS  %s" % label)
	else:
		_fail_count += 1
		print("[TEST:save] FAIL  %s" % label)


func _write_raw(text: String) -> void:
	var f := FileAccess.open(SLOT_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _run_self_test() -> void:
	print("[TEST:save] --- self-test start (slot %d, original backed up) ---" % TEST_SLOT)
	_backup_slot()

	# New save carries the new fields.
	_check(SaveManager.create_new_save(TEST_SLOT), "create_new_save succeeds")
	var created := SaveManager.load_game(TEST_SLOT)
	_check(int(created.get("save_version", -1)) == SaveManager.SAVE_VERSION,
		"new save has save_version == %d" % SaveManager.SAVE_VERSION)
	_check(created.get("story_flags") is Dictionary, "new save has story_flags dict")

	# Story-flag round trip; session flags must stay out of the file.
	StoryFlagManager.set_flag(&"test.save_load.round_trip_flag")
	StoryFlagManager.set_value(&"chapter_01.counter", 7)
	StoryFlagManager.set_value(&"temp.scratch", 1, false)
	_check(not StoryFlagManager.get_save_data().has("temp.scratch"),
		"session flags excluded from save data")
	_check(SaveManager.save_game(TEST_SLOT, SaveManager.current_save), "save_game succeeds")
	StoryFlagManager.reset()
	var loaded := SaveManager.load_game(TEST_SLOT)
	_check(not loaded.is_empty(), "load_game returns data")
	_check(StoryFlagManager.has_flag(&"test.save_load.round_trip_flag"), "bool flag survives round trip")
	_check(int(StoryFlagManager.get_value(&"chapter_01.counter", 0)) == 7,
		"value flag survives round trip")

	# Legacy save: only the original 8 fields, no version, no flags.
	var legacy := {
		"save_slot_id": TEST_SLOT,
		"created_at": "2026-01-01 00:00:00",
		"last_saved_at": "2026-01-01 00:00:00",
		"current_scene": SaveManager.NEW_GAME_SCENE_PATH,
		"checkpoint_id": "start",
		"player_position_x": 100.0,
		"player_position_y": 200.0,
		"play_time_seconds": 12.0,
	}
	_write_raw(JSON.stringify(legacy))
	var legacy_loaded := SaveManager.load_game(TEST_SLOT)
	_check(not legacy_loaded.is_empty(), "legacy save (no save_version) still loads")
	_check(int(legacy_loaded.get("save_version", -1)) == 0, "legacy save read as version 0")
	_check(legacy_loaded.get("story_flags", null) is Dictionary
		and (legacy_loaded["story_flags"] as Dictionary).is_empty(),
		"legacy save defaults to empty story_flags")
	_check(not StoryFlagManager.has_flag(&"test.save_load.round_trip_flag"),
		"flag state replaced (not merged) when loading a flag-less save")
	# Version < 2 stored the player's body centre; the origin is the feet now.
	_check(is_equal_approx(float(legacy_loaded["player_position_y"]),
			200.0 + SaveManager.LEGACY_CENTRE_ORIGIN_OFFSET_Y),
		"legacy player_position_y migrated from body centre to feet")
	_check(is_equal_approx(float(legacy_loaded["player_position_x"]), 100.0),
		"migration leaves x untouched")
	# A version-2 file must NOT be shifted again.
	var modern := (legacy as Dictionary).duplicate(true)
	modern["save_version"] = SaveManager.SAVE_VERSION
	_write_raw(JSON.stringify(modern))
	_check(is_equal_approx(float(SaveManager.load_game(TEST_SLOT)["player_position_y"]), 200.0),
		"current-version saves are read verbatim (no double migration)")

	# Corrupt JSON must not crash and must not count as a valid save.
	_write_raw("{ this is not valid json !!!")
	var corrupt_loaded := SaveManager.load_game(TEST_SLOT)
	_check(corrupt_loaded.is_empty(), "corrupt JSON returns {} instead of crashing")
	var summary := SaveManager.get_save_summary(TEST_SLOT)
	_check(bool(summary["exists"]) and not bool(summary["valid"]),
		"summary reports corrupt file as exists-but-invalid")

	# Saving over the corrupt file recovers the slot (temp-file write path).
	_check(SaveManager.save_game(TEST_SLOT, legacy), "save_game over corrupt file succeeds")
	_check(not SaveManager.load_game(TEST_SLOT).is_empty(), "slot readable again after resave")

	# Loading must clear an active DreamGap.
	WorldTimeManager.request_slow_time()
	SaveManager.load_game(TEST_SLOT)
	_check(WorldTimeManager.current_state == WorldTimeManager.SlowTimeState.READY,
		"load_game resets DreamGap to READY")
	_check(is_equal_approx(WorldTimeManager.world_time_scale, 1.0),
		"load_game restores world_time_scale = 1.0")

	_restore_slot()
	print("[TEST:save] --- done: %d passed, %d failed (slot %d restored) ---" % [
		_pass_count, _fail_count, TEST_SLOT])
	if DisplayServer.get_name() == "headless":
		get_tree().quit(_fail_count)


func _backup_slot() -> void:
	_had_backup = FileAccess.file_exists(SLOT_PATH)
	if _had_backup:
		var f := FileAccess.open(SLOT_PATH, FileAccess.READ)
		_backup_text = f.get_as_text()
		f.close()


func _restore_slot() -> void:
	# Leave no test session state behind either.
	StoryFlagManager.reset()
	WorldTimeManager.reset_state()
	SaveManager.current_slot = -1
	SaveManager.current_save = {}
	if _had_backup:
		_write_raw(_backup_text)
	elif FileAccess.file_exists(SLOT_PATH):
		DirAccess.remove_absolute(SLOT_PATH)
