class_name PassageGate
extends Interactable
## 挡路的障碍物（杂草、瓦砾、倒下的门板）：交互一次清掉，通路打开。
##
## 它自己只管三件事：把挡人的 StaticBody2D 关掉、把美术藏起来、发 `cleared`。
## **相机边界、Flag 因果、接下来发生什么由 StoryDirector 决定**——组件不碰剧情
## （AGENTS.md §5.5）。
##
## `set_cleared()` 是静默的幂等终态，读档恢复走它；`_on_interact()` 才是现场
## 链路，会发信号、出文字。两条路分开，恢复时不会重放一遍表现。

signal text_requested(text: String) ## 让关卡的共用 DialogueBox 显示
## 请关卡拿共用 DialogueBox 问一句。关卡选完后 `on_choice.call(下标)`。
signal choice_requested(text: String, options: PackedStringArray, on_choice: Callable)
signal cleared

## 先给的调查文字。`ask_before_clearing` 打开时，它放完就出「是 / 否」。
@export_multiline var display_text: String = ""
## 选「是」之后的一句反馈。留空则不出文字。
@export_multiline var cleared_text: String = ""
## 选「否」之后的一句反馈。留空则直接关框。
@export_multiline var declined_text: String = ""
## 关掉就是老行为：交互一次直接清除，不问。
@export var ask_before_clearing: bool = true
## 选项文案。约定**最后一项是否定项**（Esc 等于选它）。
@export var confirm_options: PackedStringArray = ["拔除", "算了"]
## 挡人的碰撞体。清除后碰撞层清零 + 隐藏，人就能走过去。
@export var blocker_path: NodePath
## 障碍物的美术 / 灰盒。清除后隐藏。
@export var visual_path: NodePath
## 清除后写的剧情 Flag，用于读档恢复。留空则不持久化（下次进关又长回来）。
@export var flag_to_set: StringName = &""

var _is_cleared: bool = false


func _ready() -> void:
	# 障碍物的开关状态自己恢复：它是这个物件的状态，不是剧情判断。
	# Director 只负责跟着它一起动的东西（相机边界）。
	if flag_to_set != &"" and StoryFlagManager.has_flag(flag_to_set):
		set_cleared(true)


func can_interact(player: Node) -> bool:
	return not _is_cleared and super(player)


func is_cleared() -> bool:
	return _is_cleared


## 静默设终态，不发信号、不出文字。读档恢复和调试摆位用。
func set_cleared(value: bool) -> void:
	_is_cleared = value
	var blocker := get_node_or_null(blocker_path) as CollisionObject2D
	if blocker != null:
		# 清空碰撞层而不是 queue_free：清除是可逆的（调试、剧情倒带），
		# 节点还在，Director 想再关回去也有东西可关。
		blocker.collision_layer = 0 if value else 1
		blocker.visible = not value
	var visual := get_node_or_null(visual_path) as CanvasItem
	if visual != null:
		visual.visible = not value


func _on_interact(_player: Node) -> void:
	if _is_cleared:
		return
	if not ask_before_clearing:
		_do_clear()
		return
	# 只发请求，不自己弹 UI——对话框是关卡的（一个出口，AGENTS.md §5.5）。
	choice_requested.emit(display_text, confirm_options, _on_choice)


## 选完之后回到这里。选否什么都不做，`_is_cleared` 还是 false，可以再来一次。
func _on_choice(index: int) -> void:
	if index == 0:
		_do_clear()
	elif not declined_text.is_empty():
		text_requested.emit(declined_text)


func _do_clear() -> void:
	if _is_cleared:
		return
	set_cleared(true)
	if flag_to_set != &"":
		StoryFlagManager.set_flag(flag_to_set)
	cleared.emit()
	# 反馈文字放在 cleared 之后：Director 接到 cleared 会开始滑镜头，
	# 让镜头先动起来，文字压在上面同时出现。
	if not cleared_text.is_empty():
		text_requested.emit(cleared_text)
