class_name StoryDoor
extends Interactable
## 门：可以由剧情 Flag 和 / 或梦奁信物把关，也可以由 StoryDirector 直接开关。
##
## 场景约定（沿用灰盒既有结构，两者都可选，缺了就跳过对应表现）：
##   Visual                     CanvasItem，开门后淡出到 opened_alpha
##   Blocker/CollisionShape2D   StaticBody2D 的碰撞，开门后禁用
##
## 门槛：基类的 `required_flag` 与本类的 `required_memory` **叠加**，
## 两个都填就都要满足；都留空则永远可开。
##
## 为什么信物门槛直接问 MemoryManager，而不是要求拾取时顺手写一个 StoryFlag：
## 那样“持有信物”和“Flag 存在”会变成两份各自持久化的状态，一旦信物通过别的
## 途径给出（对话奖励、存档迁移）门就打不开了。条件本身只有一个来源。

signal opened

## 需要持有的梦奁信物 id；留空表示不看信物。
@export var required_memory: StringName = &""

## 开门后视觉保留的不透明度（0 = 完全消失）。
@export var opened_alpha: float = 0.15

var _is_open: bool = false


func is_open() -> bool:
	return _is_open


# --- 门槛 ---------------------------------------------------------------------

func is_requirement_met() -> bool:
	if not super():
		return false
	return required_memory == &"" or MemoryManager.has_memory(required_memory)


## 开着的门不再是交互目标，提示语也就不会继续挂在屏幕上。
func can_interact(player: Node) -> bool:
	return not _is_open and super(player)


# --- 开关 ---------------------------------------------------------------------

## 带表现地开门并发 `opened`。门槛已由基类 `interact()` 把关，这里不重复判断。
func open() -> void:
	if _is_open:
		return
	set_unlocked(true)
	opened.emit()


## 静默设终态，不发信号。读档恢复专用：StoryDirector 的 `_apply_*` 调它，
## 现场链路走 `open()`（见 NARRATIVE_LAYER_DESIGN.md §4）。
func set_unlocked(unlocked: bool) -> void:
	_is_open = unlocked
	var visual := get_node_or_null("Visual") as CanvasItem
	if visual != null:
		visual.modulate.a = opened_alpha if unlocked else 1.0
	var blocker := get_node_or_null("Blocker/CollisionShape2D") as CollisionShape2D
	if blocker != null:
		blocker.set_deferred("disabled", unlocked)


func _on_interact(_player: Node) -> void:
	open()
