class_name StoryNPC
extends Node2D
## 剧情 NPC：只负责“我怎么进场、怎么离场、怎么说话”。
##
## **禁止**在 `_process` 里查 StoryFlagManager 决定自己出不出现。
## “为什么现在进场”是 StoryDirector 的事，NPC 只被调用。
##
## `enter_scene()` / `set_present()` 是一对：前者带表现，后者静默设终态，
## 读档恢复走后者，这样不必为了恢复表现另造一堆 Flag。

signal entered
signal left
signal dialogue_finished

@export var dialogue_box_path: NodePath
## 可选：这个 NPC 的搭话点。接上后由 NPC 自己把交互接到 start_dialogue()——
## “我怎么被搭话”是它自己的事，Director 只关心 dialogue_finished 之后怎么样。
@export var talk_interactable_path: NodePath
@export var speaker_name: String = ""
## 分页由 DialogueBox 负责，这里按行写即可。
@export_multiline var lines: String = ""
## 进场淡入时长（秒）。0 = 立即出现。
@export var fade_duration: float = 0.4

var _present: bool = false
var _talking: bool = false


func _ready() -> void:
	var talk := get_node_or_null(talk_interactable_path) as Interactable
	if talk != null:
		talk.interacted.connect(func(_player: Node) -> void: start_dialogue())
	# 默认不在场；由 StoryDirector 在 _restore_story_state() 里决定初始状态。
	set_present(false)


func is_present() -> bool:
	return _present


# --- 进出场 ---------------------------------------------------------------------

## 带表现地入场。已经在场则忽略。
func enter_scene() -> void:
	if _present:
		return
	set_present(true)
	if fade_duration > 0.0:
		modulate.a = 0.0
		create_tween().tween_property(self, ^"modulate:a", 1.0, fade_duration)
	entered.emit()


## 带表现地离场。
func leave_scene() -> void:
	if not _present:
		return
	if fade_duration > 0.0:
		var tween := create_tween()
		tween.tween_property(self, ^"modulate:a", 0.0, fade_duration)
		tween.tween_callback(func() -> void: set_present(false))
	else:
		set_present(false)
	left.emit()


## 静默设终态，不发信号、不播动画。读档恢复专用。
func set_present(present: bool) -> void:
	_present = present
	visible = present
	modulate.a = 1.0
	# 不在场的人不该还能被交互或挡路。
	process_mode = Node.PROCESS_MODE_INHERIT if present else Node.PROCESS_MODE_DISABLED


# --- 对话 ----------------------------------------------------------------------

## 走共用的 DialogueBox；读完转发成 `dialogue_finished`。
## 剧情后果由 StoryDirector 接这个信号决定，NPC 自己不推进剧情。
func start_dialogue() -> void:
	if _talking or not _present:
		return
	var box := get_node_or_null(dialogue_box_path)
	if box == null or not box.has_method("show_text"):
		push_warning("StoryNPC '%s': 没接上 DialogueBox，直接发 dialogue_finished。" % name)
		dialogue_finished.emit()
		return
	_talking = true
	box.closed.connect(_on_box_closed, CONNECT_ONE_SHOT)
	box.show_text(lines, null, speaker_name)


func is_talking() -> bool:
	return _talking


func _on_box_closed() -> void:
	if not _talking:
		return
	_talking = false
	dialogue_finished.emit()
