class_name MemoryPickup
extends Interactable
## 梦奁信物的拾取点 / 调查点。
##
## UNLOCK   物理拾取：解锁信物并隐藏 Visual（配合 `one_shot = true`）。
## ADVANCE  调查点：把**同一件**信物推进到下一阶段，绝不产生重复道具。
##
## 边界（NARRATIVE_LAYER_DESIGN.md §6.2）：“玩家是否持有这件信物”只由
## MemoryManager 回答，不要再配一个 `got_xxx` 的剧情 Flag。`flag_to_set`
## 只用来记录“故事进行到哪里”，两者不是一回事。

signal collected(memory_id: StringName)

enum Mode { UNLOCK, ADVANCE }

@export var memory_id: StringName = &""
@export var mode: Mode = Mode.UNLOCK
## 可选：与信物变化一起记录的剧情 Flag。
@export var flag_to_set: StringName = &""


func _ready() -> void:
	# 已经拿到手的东西不该还摆在原地。这不是剧情判断，而是这件道具自己的
	# 持有状态，所以由它自己恢复，不必劳动 StoryDirector 去逐个摆位。
	if mode == Mode.UNLOCK and memory_id != &"" and MemoryManager.has_memory(memory_id):
		set_collected(true)


func can_interact(player: Node) -> bool:
	return not (mode == Mode.UNLOCK and _is_hidden()) and super(player)


## 静默设终态，不发信号。读档恢复与 StoryDirector 强制摆位用。
func set_collected(is_collected: bool) -> void:
	var visual := get_node_or_null("Visual") as CanvasItem
	if visual != null:
		visual.visible = not is_collected


func _on_interact(_player: Node) -> void:
	if flag_to_set != &"":
		StoryFlagManager.set_flag(flag_to_set)
	match mode:
		Mode.UNLOCK:
			MemoryManager.unlock_memory(memory_id)
			set_collected(true)
		Mode.ADVANCE:
			MemoryManager.advance_memory(memory_id)
	collected.emit(memory_id)


func _is_hidden() -> bool:
	var visual := get_node_or_null("Visual") as CanvasItem
	return visual != null and not visual.visible
