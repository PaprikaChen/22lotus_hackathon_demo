class_name ChoiceTextInteractable
extends Interactable
## 只出文字的多选调查点：先放 `display_text`，然后让玩家在 `options` 里选一项，
## 选完显示对应的 `option_texts[i]`。没有世界状态变化，纯阅读分支。
##
## 和 TextInteractable 的关系：那个是「看一眼就完」，这个是「看一眼再挑一样」。
## 需要真的改场景状态（清路、开门）用 PassageGate / StoryDoor，别往这里堆。
##
## 组件不自己弹 UI：只发 `choice_requested`，由关卡的共用 DialogueBox 处理
## （AGENTS.md §5.5，对话框只有一个出口）。

signal text_requested(text: String)
## 请关卡拿共用 DialogueBox 问一句。关卡选完后 `on_choice.call(下标)`。
signal choice_requested(text: String, options: PackedStringArray, on_choice: Callable)
## 选完之后发，方便 StoryDirector 挂剧情因果（组件自己不碰剧情）。
signal option_chosen(index: int)

## 提问时先放的文字。
@export_multiline var display_text: String = ""
## 选项文案。约定**最后一项是否定项**（Esc 等于选它）。
# 默认值必须写成 PackedStringArray()：写 `[]` 会让导出类型退化成 Variant/Array，
# 场景里存的 PackedStringArray(...) 类型不匹配会被**静默丢掉**，选项就消失了。
@export var options: PackedStringArray = PackedStringArray()
## 每个选项选中后显示的文字，下标与 `options` 对齐。留空的项不出文字。
@export var option_texts: PackedStringArray = PackedStringArray()


func _on_interact(_player: Node) -> void:
	if options.is_empty():
		# 退化成普通调查点，别因为忘填选项就变成哑物件。
		if not display_text.is_empty():
			text_requested.emit(display_text)
		return
	choice_requested.emit(display_text, options, _on_choice)


func _on_choice(index: int) -> void:
	if index < 0:
		return
	option_chosen.emit(index)
	if index < option_texts.size():
		var text := option_texts[index]
		if not text.is_empty():
			text_requested.emit(text)
