extends Node
## Global save system. Registered as the "SaveManager" Autoload.
##
## Centralizes ALL reading/writing of save files under user://.
## UI scripts must never touch the filesystem directly — they call here.
## Only primitive values (int/float/String/bool) are written to JSON;
## never node references or Godot Objects.

const SLOT_COUNT: int = 3
## Scene a NEW game starts in — the first real chapter level, never a test room.
const NEW_GAME_SCENE_PATH: String = "res://scenes/levels/courtyard_01.tscn"
## 新游戏先播前情提要，播完再进 NEW_GAME_SCENE_PATH。
## 注意：存档里的 current_scene 写的是 NEW_GAME_SCENE_PATH 而不是这个——
## 前情提要不是一个"可以存档的地方"，中途退出再读档应该直接进关卡。
const PROLOGUE_SCENE_PATH: String = "res://scenes/ui/prologue.tscn"
## Placeholder coordinates for a brand-new save. They are deliberately NOT
## used for placement: a new save also carries use_level_spawn = true, and
## LevelBase then honours the level's own SpawnPoint instead. Keeping real
## numbers here only keeps the JSON schema uniform.
const DEFAULT_SPAWN := Vector2(320.0, 320.0)

## Current save format version, written into every save as "save_version".
## Legacy files without the field are read as version 0 and receive safe
## defaults for every newer field. Bump this ONLY together with migration
## logic in _read_validated().
##
## History:
##   0 — pre-versioning files (no save_version field).
##   1 — added save_version, story_flags, memories.
##   2 — player_position_* now addresses the player's GROUND-CONTACT point.
##       Files below 2 stored the body CENTRE; see _read_validated().
const SAVE_VERSION: int = 2

## Vertical distance from the old body-centre origin down to the feet. Saves
## older than version 2 are shifted by it on read, otherwise a restored
## player would materialise half a body above where it was saved (and over a
## pit, fall somewhere else entirely).
const LEGACY_CENTRE_ORIGIN_OFFSET_Y: float = 24.0

## Every valid save file must contain these keys.
## NEVER add new fields here — that would invalidate existing saves.
## New fields are read with data.get("field", safe_default) instead.
const REQUIRED_KEYS: PackedStringArray = [
	"save_slot_id",
	"created_at",
	"last_saved_at",
	"current_scene",
	"checkpoint_id",
	"player_position_x",
	"player_position_y",
	"play_time_seconds",
]

# --- Session state (navigation / active game; not a file itself) ---

## Mode the slot menu opens in: "new" or "load".
var slot_menu_mode: String = "new"
## Slot currently being played, -1 when none.
var current_slot: int = -1
## In-memory copy of the active save.
var current_save: Dictionary = {}


# --- Public API -------------------------------------------------------------

func create_new_save(slot_id: int) -> bool:
	if not _is_valid_slot(slot_id):
		push_error("SaveManager: invalid slot id %d" % slot_id)
		return false
	var now := _now_string()
	var data: Dictionary = {
		"save_version": SAVE_VERSION,
		"save_slot_id": slot_id,
		"created_at": now,
		"last_saved_at": now,
		"current_scene": NEW_GAME_SCENE_PATH,
		"checkpoint_id": "start",
		"player_position_x": DEFAULT_SPAWN.x,
		"player_position_y": DEFAULT_SPAWN.y,
		# A new game has no real coordinates yet — the level's SpawnPoint wins.
		# Cleared automatically by the first save_game().
		"use_level_spawn": true,
		"play_time_seconds": 0.0,
		"story_flags": {},
		"memories": {},
	}
	if not _write_file(slot_id, data):
		return false
	current_slot = slot_id
	current_save = data.duplicate(true)
	# A brand-new game starts with clean story/ability state.
	StoryFlagManager.reset()
	MemoryManager.reset()
	WorldTimeManager.reset_state()
	return true


func save_game(slot_id: int, save_data: Dictionary) -> bool:
	if not _is_valid_slot(slot_id):
		push_error("SaveManager: invalid slot id %d" % slot_id)
		return false
	# Defensive copy; enforce slot id and refresh the save timestamp here so
	# callers never have to remember to stamp it.
	var data := save_data.duplicate(true)
	data["save_slot_id"] = slot_id
	data["last_saved_at"] = _now_string()
	data["save_version"] = SAVE_VERSION
	# 默认清掉「用关卡自己的 SpawnPoint」这个提示——绝大多数存档都带真坐标，
	# 存档点不需要记得这件事。只有明确传了 true 的调用者（跨关卡切换）才保留。
	data["use_level_spawn"] = bool(save_data.get("use_level_spawn", false))
	if not data.has("created_at"):
		data["created_at"] = data["last_saved_at"]
	# Systems that own persistent state contribute it here; callers never
	# assemble story flags or memory states by hand.
	data["story_flags"] = StoryFlagManager.get_save_data()
	data["memories"] = MemoryManager.get_save_data()
	if not _write_file(slot_id, data):
		return false
	if slot_id == current_slot:
		current_save = data.duplicate(true)
	return true


## 便捷写档：把「当前场景 + 玩家坐标」写进正在使用的槽位，其余字段沿用
## current_save。存档点和关卡自动存共用这一条路径，免得各处自己拼字典。
##
## 没有活动槽位时（F6 单开场景、headless 测试）返回 false 且**不写盘**——
## 测试跑动永远碰不到真实存档文件。
## use_level_spawn 传 true 表示「坐标不作数，进关用关卡自己的 SpawnPoint」——
## 跨关卡切换时用它，否则下一关会被上一关写进去的坐标钉在错误位置。
func save_progress(scene_path: String, player_position: Vector2,
		use_level_spawn: bool = false) -> bool:
	if current_slot == -1:
		return false
	var data := current_save.duplicate(true)
	data["current_scene"] = scene_path
	data["player_position_x"] = player_position.x
	data["player_position_y"] = player_position.y
	data["use_level_spawn"] = use_level_spawn
	return save_game(current_slot, data)


func load_game(slot_id: int) -> Dictionary:
	var data := _read_validated(slot_id)
	if data.is_empty():
		return {}
	current_slot = slot_id
	current_save = data.duplicate(true)
	# Restore registered persistent systems. Legacy saves without the fields
	# fall back to empty sets (never an error).
	StoryFlagManager.load_save_data(data.get("story_flags", {}))
	MemoryManager.load_save_data(data.get("memories", {}))
	# Loading must never leak an active/cooling-down DreamGap into the
	# restored world.
	WorldTimeManager.reset_state()
	return data


func delete_save(slot_id: int) -> bool:
	if not _is_valid_slot(slot_id):
		push_error("SaveManager: invalid slot id %d" % slot_id)
		return false
	if not save_exists(slot_id):
		return false
	var err := DirAccess.remove_absolute(_slot_path(slot_id))
	if err != OK:
		push_error("SaveManager: failed to delete slot %d (err %d)" % [slot_id, err])
		return false
	if slot_id == current_slot:
		current_slot = -1
		current_save = {}
	return true


func save_exists(slot_id: int) -> bool:
	if not _is_valid_slot(slot_id):
		return false
	return FileAccess.file_exists(_slot_path(slot_id))


## Returns a small display-friendly dictionary. Never throws.
## Keys: slot_id, exists (bool), valid (bool) and, when valid:
## last_saved_at, current_scene, play_time_seconds, checkpoint_id.
func get_save_summary(slot_id: int) -> Dictionary:
	var summary := {"slot_id": slot_id, "exists": false, "valid": false}
	if not save_exists(slot_id):
		return summary
	summary["exists"] = true
	var data := _read_validated(slot_id)
	if data.is_empty():
		# File present but corrupt or missing fields.
		return summary
	summary["valid"] = true
	summary["last_saved_at"] = String(data["last_saved_at"])
	summary["current_scene"] = String(data["current_scene"])
	summary["play_time_seconds"] = float(data["play_time_seconds"])
	summary["checkpoint_id"] = String(data["checkpoint_id"])
	return summary


# --- 跨存档槽的全局数据 --------------------------------------------------------
# 画廊 CG 收集（将来还可能是设置、成就）与三个存档槽完全无关：不进
# REQUIRED_KEYS、不参与 save_version 迁移、删存档不影响它。放在这里是因为
# 「所有文件 I/O 只在 SaveManager 内」这条规则，顺带复用临时文件安全写入。

## 读一个全局存储。文件不存在或损坏时返回 {}，永不抛错。
func read_global(store_name: String) -> Dictionary:
	var path := _global_path(store_name)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("SaveManager: 打不开全局存储 %s (err %d)" % [
			path, FileAccess.get_open_error()])
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveManager: 全局存储 %s 损坏，按空处理。" % path)
		return {}
	return parsed


## 写一个全局存储。走和存档槽同一条 .tmp → 替换路径，写失败不破坏原文件。
func write_global(store_name: String, data: Dictionary) -> bool:
	return _write_json_safely(_global_path(store_name), data)


func _global_path(store_name: String) -> String:
	return "user://%s.json" % store_name


## Utility shared by the UI: seconds -> "MM:SS" (or "H:MM:SS").
func format_play_time(seconds: float) -> String:
	var total := int(max(0.0, seconds))
	@warning_ignore("integer_division") var h := total / 3600
	@warning_ignore("integer_division") var m := (total % 3600) / 60
	var s := total % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, s]
	return "%02d:%02d" % [m, s]


# --- Internal helpers -------------------------------------------------------

func _is_valid_slot(slot_id: int) -> bool:
	return slot_id >= 1 and slot_id <= SLOT_COUNT


func _slot_path(slot_id: int) -> String:
	return "user://save_slot_%d.json" % slot_id


func _now_string() -> String:
	# Local time with a space separator, e.g. "2026-06-23 14:05:30".
	return Time.get_datetime_string_from_system(false, true)


## Writes to a temp file first and only then replaces the real slot file,
## so a failed/interrupted write can never destroy an existing valid save.
func _write_file(slot_id: int, data: Dictionary) -> bool:
	return _write_json_safely(_slot_path(slot_id), data)


## 安全写入：先写 .tmp 再替换正式文件，写失败不破坏已有文件。
## 存档槽和全局存储共用这一条路径。
func _write_json_safely(path: String, data: Dictionary) -> bool:
	var tmp_path := path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot open %s for writing (err %d)" % [
			tmp_path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	# Windows rename fails onto an existing target; the temp file is already
	# complete and valid at this point, so removing the old file first is safe.
	if FileAccess.file_exists(path):
		var rm_err := DirAccess.remove_absolute(path)
		if rm_err != OK:
			push_error("SaveManager: cannot replace %s (err %d)" % [path, rm_err])
			return false
	var mv_err := DirAccess.rename_absolute(tmp_path, path)
	if mv_err != OK:
		push_error("SaveManager: cannot rename %s -> %s (err %d)" % [
			tmp_path, path, mv_err])
		return false
	return true


## Reads, parses, validates and normalizes a slot file with NO session
## side effects. Returns {} on any failure (missing file, bad JSON,
## missing fields). Errors are pushed so they show up in Output/Debugger.
func _read_validated(slot_id: int) -> Dictionary:
	if not _is_valid_slot(slot_id):
		push_error("SaveManager: invalid slot id %d" % slot_id)
		return {}
	var path := _slot_path(slot_id)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("SaveManager: cannot open %s (err %d)" % [
			path, FileAccess.get_open_error()])
		return {}
	var text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveManager: slot %d is corrupt (not a JSON object)" % slot_id)
		return {}

	var data: Dictionary = parsed
	for key in REQUIRED_KEYS:
		if not data.has(key):
			push_error("SaveManager: slot %d is missing required field '%s'" % [slot_id, key])
			return {}

	# JSON numbers come back as float; normalize the typed fields.
	data["save_slot_id"] = int(data["save_slot_id"])
	data["player_position_x"] = float(data["player_position_x"])
	data["player_position_y"] = float(data["player_position_y"])
	data["play_time_seconds"] = float(data["play_time_seconds"])

	# --- Version-0 (legacy) tolerance: fields added after the first release
	# are normalized with safe defaults instead of being required.
	# save_version keeps reporting what the FILE says; migrations only touch
	# the values, and the next save_game() stamps the current version.
	data["save_version"] = int(data.get("save_version", 0))
	# Absent in every save written before the field existed — those all hold
	# real coordinates, so false is the correct default and no migration is
	# needed (the field is NOT in REQUIRED_KEYS).
	data["use_level_spawn"] = bool(data.get("use_level_spawn", false))
	if data["save_version"] < 2:
		# Player origin moved from the body centre to the feet.
		data["player_position_y"] = float(data["player_position_y"]) + LEGACY_CENTRE_ORIGIN_OFFSET_Y
	var flags: Variant = data.get("story_flags", {})
	if typeof(flags) != TYPE_DICTIONARY:
		push_warning("SaveManager: slot %d has malformed story_flags; using empty set." % slot_id)
		flags = {}
	data["story_flags"] = flags
	var memories: Variant = data.get("memories", {})
	if typeof(memories) != TYPE_DICTIONARY:
		push_warning("SaveManager: slot %d has malformed memories; using empty set." % slot_id)
		memories = {}
	data["memories"] = memories
	return data
