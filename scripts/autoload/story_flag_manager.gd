extends Node
## Autoload "StoryFlagManager" — lightweight story-progress state.
##
## Two clearly separated stores:
##  - persistent: written into the save file (via SaveManager) and restored
##    on load. Use for story progress, e.g. "chapter_01.intro_finished".
##  - session: level-local scratch state; never saved, cleared when a level
##    starts (LevelBase calls clear_session()).
##
## Flag ids must be hierarchical and readable ("chapter_01.screen_examined"),
## never "flag_1" / "event_a". Once a persistent id has shipped in a save
## file it must not be renamed.
##
## Derived conditions should be computed with functions, not stored twice.
## Only JSON-safe primitive values (bool/int/float/String) may be stored.

signal flag_changed(flag_id: StringName, value: Variant)

var _persistent: Dictionary = {}
var _session: Dictionary = {}


# --- Public API -------------------------------------------------------------

func set_flag(flag_id: StringName, value: bool = true, persistent: bool = true) -> void:
	set_value(flag_id, value, persistent)


func has_flag(flag_id: StringName) -> bool:
	return bool(get_value(flag_id, false))


## Session values shadow persistent ones when both exist (session is the
## more specific, temporary layer).
func get_value(flag_id: StringName, default_value: Variant = null) -> Variant:
	var key := String(flag_id)
	if _session.has(key):
		return _session[key]
	return _persistent.get(key, default_value)


func set_value(flag_id: StringName, value: Variant, persistent: bool = true) -> void:
	var key := String(flag_id)
	if persistent:
		_persistent[key] = value
	else:
		_session[key] = value
	flag_changed.emit(flag_id, value)


## Removes the flag from both stores.
func clear_flag(flag_id: StringName) -> void:
	var key := String(flag_id)
	_persistent.erase(key)
	_session.erase(key)
	flag_changed.emit(flag_id, null)


## Drops all level-local state. Called by LevelBase when a level starts.
func clear_session() -> void:
	_session.clear()


# --- SaveManager integration -------------------------------------------------

## Snapshot of the persistent flags for the save file.
func get_save_data() -> Dictionary:
	return _persistent.duplicate(true)


## Replaces all flag state from a save. Missing/legacy saves pass {} so old
## save files keep working with an empty flag set.
func load_save_data(data: Dictionary) -> void:
	_persistent = data.duplicate(true)
	_session.clear()


## Full reset (e.g. starting a brand-new game).
func reset() -> void:
	_persistent.clear()
	_session.clear()
