extends Node
## Autoload "MemoryManager" — runtime state of the 梦奁 (Dream Box) memory
## keepsakes.
##
## Static data (MemoryEntry .tres under resources/memories/) and runtime
## state are strictly separated: this manager holds ONLY per-id runtime
## dictionaries {unlocked, current_stage, unread_state} and hands them to
## SaveManager as the "memories" save field.
##
## Boundaries: story conditions live in StoryFlagManager; this manager never
## infers plot. It owns keepsake unlock/stage/unread state and emits signals
## the UI (grid, toasts) listens to. It never touches UI nodes itself.

signal memory_unlocked(memory_id: StringName)
signal memory_updated(memory_id: StringName, old_stage: int, new_stage: int)
signal memory_read(memory_id: StringName)
signal memory_state_changed(memory_id: StringName)

const MEMORIES_DIR := "res://resources/memories/"

const UNREAD_NONE := ""
const UNREAD_NEW := "new"
const UNREAD_UPDATED := "updated"

## String id -> MemoryEntry, loaded once from MEMORIES_DIR.
var _entries: Dictionary = {}
## String id -> {"unlocked": bool, "current_stage": int, "unread_state": String}.
## JSON-safe primitives only; this dict IS the save payload.
var _states: Dictionary = {}


func _ready() -> void:
	_load_entries()


# --- Static data registry -----------------------------------------------------

func _load_entries() -> void:
	var dir := DirAccess.open(MEMORIES_DIR)
	if dir == null:
		push_warning("MemoryManager: cannot open %s; no memories registered." % MEMORIES_DIR)
		return
	for file_name in dir.get_files():
		# Exported builds may list "*.tres.remap"; load by the original name.
		var res_name := file_name.trim_suffix(".remap")
		if not res_name.ends_with(".tres"):
			continue
		var entry := load(MEMORIES_DIR + res_name) as MemoryEntry
		if entry == null or entry.id == &"":
			push_warning("MemoryManager: %s is not a valid MemoryEntry; skipped." % res_name)
			continue
		var key := String(entry.id)
		if _entries.has(key):
			push_warning("MemoryManager: duplicate memory id '%s'; keeping the first." % key)
			continue
		_entries[key] = entry


# --- Public API -----------------------------------------------------------------

## Unlocks a keepsake at stage 0 and marks it NEW. Returns true only when an
## actual unlock happened; re-unlocking an owned keepsake never resets state
## and never re-notifies.
func unlock_memory(memory_id: StringName) -> bool:
	var key := String(memory_id)
	if not _entries.has(key):
		push_warning("MemoryManager: unknown memory id '%s'." % key)
		return false
	if has_memory(memory_id):
		return false
	_states[key] = {
		"unlocked": true,
		"current_stage": 0,
		"unread_state": UNREAD_NEW,
	}
	memory_unlocked.emit(memory_id)
	memory_state_changed.emit(memory_id)
	return true


## Advances the SAME keepsake to its next interpretation stage and marks it
## UPDATED (never creates a duplicate item). At the last stage this is a
## no-op returning false. Advancing a not-yet-owned keepsake unlocks it at
## stage 0 instead (use set_memory_stage() to jump straight to a later one).
func advance_memory(memory_id: StringName) -> bool:
	var key := String(memory_id)
	if not _entries.has(key):
		push_warning("MemoryManager: unknown memory id '%s'." % key)
		return false
	if not has_memory(memory_id):
		return unlock_memory(memory_id)
	var entry: MemoryEntry = _entries[key]
	var old_stage := int(_states[key]["current_stage"])
	if old_stage >= entry.get_last_stage_index():
		return false
	_states[key]["current_stage"] = old_stage + 1
	_states[key]["unread_state"] = UNREAD_UPDATED
	memory_updated.emit(memory_id, old_stage, old_stage + 1)
	memory_state_changed.emit(memory_id)
	return true


## Jumps to an exact stage (story scripts that skip interpretations).
## Invalid stages are rejected; setting the current stage again is a silent
## no-op (no repeated toast); going backwards requires allow_regress = true.
func set_memory_stage(memory_id: StringName, stage_index: int, allow_regress: bool = false) -> bool:
	var key := String(memory_id)
	if not _entries.has(key):
		push_warning("MemoryManager: unknown memory id '%s'." % key)
		return false
	var entry: MemoryEntry = _entries[key]
	if stage_index < 0 or stage_index > entry.get_last_stage_index():
		push_warning("MemoryManager: stage %d out of range for '%s'." % [stage_index, key])
		return false
	if not has_memory(memory_id):
		_states[key] = {
			"unlocked": true,
			"current_stage": stage_index,
			"unread_state": UNREAD_NEW,
		}
		memory_unlocked.emit(memory_id)
		memory_state_changed.emit(memory_id)
		return true
	var old_stage := int(_states[key]["current_stage"])
	if stage_index == old_stage:
		return false
	if stage_index < old_stage and not allow_regress:
		push_warning("MemoryManager: refusing stage regress %d -> %d for '%s'." % [
			old_stage, stage_index, key])
		return false
	_states[key]["current_stage"] = stage_index
	_states[key]["unread_state"] = UNREAD_UPDATED
	memory_updated.emit(memory_id, old_stage, stage_index)
	memory_state_changed.emit(memory_id)
	return true


## Clears the NEW/UPDATED badge after the player actually viewed the detail.
func mark_as_read(memory_id: StringName) -> void:
	var key := String(memory_id)
	if not _states.has(key):
		return
	if String(_states[key].get("unread_state", UNREAD_NONE)) == UNREAD_NONE:
		return
	_states[key]["unread_state"] = UNREAD_NONE
	memory_read.emit(memory_id)
	memory_state_changed.emit(memory_id)


func has_memory(memory_id: StringName) -> bool:
	return bool(_states.get(String(memory_id), {}).get("unlocked", false))


## Static definition, or null for unknown ids.
func get_memory_data(memory_id: StringName) -> MemoryEntry:
	return _entries.get(String(memory_id))


## Copy of the runtime state ({} when never unlocked).
func get_memory_state(memory_id: StringName) -> Dictionary:
	var state: Dictionary = _states.get(String(memory_id), {})
	return state.duplicate(true)


func get_unread_state(memory_id: StringName) -> String:
	return String(_states.get(String(memory_id), {}).get("unread_state", UNREAD_NONE))


func get_current_stage(memory_id: StringName) -> int:
	return int(_states.get(String(memory_id), {}).get("current_stage", 0))


## Unlocked ids in registry (directory) order, ready for the UI grid.
func get_unlocked_memories() -> Array[StringName]:
	var result: Array[StringName] = []
	for key: String in _entries.keys():
		if has_memory(StringName(key)):
			result.append(StringName(key))
	return result


## Full reset (new game).
func reset() -> void:
	_states.clear()


# --- SaveManager integration -----------------------------------------------------

func get_save_data() -> Dictionary:
	return _states.duplicate(true)


## Replaces all runtime state from a save. Tolerant by design: missing field
## -> empty, unknown ids kept but inert, stages clamped into the entry's
## current range, bad unread values normalized. Old saves never break when
## resources gain or lose stages or text changes.
func load_save_data(data: Dictionary) -> void:
	_states.clear()
	for key: String in data.keys():
		var raw: Variant = data[key]
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var raw_dict: Dictionary = raw
		var stage := int(raw_dict.get("current_stage", 0))
		var entry: MemoryEntry = _entries.get(key)
		if entry != null:
			stage = clampi(stage, 0, entry.get_last_stage_index())
		else:
			stage = maxi(0, stage)
			push_warning("MemoryManager: save references unknown memory id '%s' (kept, ignored by UI)." % key)
		var unread := String(raw_dict.get("unread_state", UNREAD_NONE))
		if unread != UNREAD_NEW and unread != UNREAD_UPDATED:
			unread = UNREAD_NONE
		_states[key] = {
			"unlocked": bool(raw_dict.get("unlocked", false)),
			"current_stage": stage,
			"unread_state": unread,
		}
	for key: String in _states.keys():
		memory_state_changed.emit(StringName(key))
