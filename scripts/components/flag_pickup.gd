class_name FlagPickup
extends Interactable
## 只记一个剧情 Flag 的拾取物（钥匙、信件、凭证一类）。
##
## 如果这件东西应该进梦奁，用 `MemoryPickup` 而不是这个——
## “玩家拥有什么”属于 MemoryManager，`FlagPickup` 记的是“故事进行到哪里”。

signal picked_up(flag_id: StringName)

@export var flag_to_set: StringName = &""


func _on_interact(_player: Node) -> void:
	if flag_to_set != &"":
		StoryFlagManager.set_flag(flag_to_set)
	set_taken(true)
	picked_up.emit(flag_to_set)


## 静默设终态，读档恢复用。
func set_taken(is_taken: bool) -> void:
	var visual := get_node_or_null("Visual") as CanvasItem
	if visual != null:
		visual.visible = not is_taken
