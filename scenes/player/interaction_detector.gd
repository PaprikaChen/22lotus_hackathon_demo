class_name InteractionDetector
extends Area2D
## The player's single interaction sensor. Tracks nearby Interactable areas,
## picks the best target (priority, then distance), surfaces the prompt via
## signal, and calls interact() on the key press. The player never needs to
## know what kind of object it is talking to.
##
## Candidates register/unregister through area_entered/area_exited — no
## per-frame scene-tree scanning.

signal target_changed(target: Interactable) ## null when nothing in range
signal prompt_changed(text: String) ## "" when there is no prompt

@export var action_name: StringName = &"interact"

var _candidates: Array[Interactable] = []
var _target: Interactable = null
var _prompt: String = ""
var _held: bool = false


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func _physics_process(_delta: float) -> void:
	_update_target()

	# Rising edge from is_action_pressed() (project convention; see player.gd).
	# The edge is tracked even while input is locked so a press held through a
	# dialogue cannot re-trigger the moment the lock lifts.
	var pressed := Input.is_action_pressed(action_name)
	if pressed and not _held and _target != null and not _is_player_input_locked():
		_target.interact(get_parent())
	_held = pressed


func get_current_target() -> Interactable:
	return _target


## 动态启用调查物时，玩家可能已经站在它的范围内，Godot 不保证为这种情况
## 补发 area_entered。由启用方在下一物理帧调用一次，重同步当前重叠候选。
## 这不是每帧扫描，只用于运行时开关碰撞的调查物。
func refresh_overlaps() -> void:
	var overlaps := get_overlapping_areas()
	for candidate in _candidates.duplicate():
		if not overlaps.has(candidate):
			_candidates.erase(candidate)
	for area in overlaps:
		_on_area_entered(area)
	_update_target()


# --- Internal ---------------------------------------------------------------

func _on_area_entered(area: Area2D) -> void:
	var interactable := area as Interactable
	if interactable != null and not _candidates.has(interactable):
		_candidates.append(interactable)


func _on_area_exited(area: Area2D) -> void:
	var interactable := area as Interactable
	if interactable != null:
		_candidates.erase(interactable)


func _update_target() -> void:
	var player := get_parent()
	var best: Interactable = null
	for c in _candidates:
		if not is_instance_valid(c) or not c.can_interact(player):
			continue
		if best == null or _is_better(c, best):
			best = c
	var new_prompt := best.get_interaction_prompt() if best != null else ""
	if best != _target:
		_target = best
		target_changed.emit(_target)
	if new_prompt != _prompt:
		_prompt = new_prompt
		prompt_changed.emit(_prompt)


func _is_better(a: Interactable, b: Interactable) -> bool:
	if a.interact_priority != b.interact_priority:
		return a.interact_priority > b.interact_priority
	var pos := global_position
	return pos.distance_squared_to(a.global_position) < pos.distance_squared_to(b.global_position)


func _is_player_input_locked() -> bool:
	var p := get_parent()
	return p != null and p.has_method("is_input_locked") and p.is_input_locked()
