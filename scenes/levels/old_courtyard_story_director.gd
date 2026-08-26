class_name OldCourtyardStoryDirector
extends StoryDirector
## 旧院的剧情编排。**打开这个文件应该能一眼读出旧院的故事按什么顺序发生。**
##
## ── 因果链（文案为占位，等叙事定稿后替换）─────────────────────────
##   调查药圃（枝叶的苦味）   ┐
##                           ├→ 两处都看过 → 母亲幻觉 Cutscene
##   调查侧窗（山鸟纹）       ┘
##   幻觉结束 → 推进信物「山鸟簪」→ 丫鬟入场
##   与丫鬟对话结束 → 丫鬟离场 + 侧窗解锁 → 侧窗变成主屋入口
##
## 双条件入场是刻意的：“丫鬟为什么现在出现”的答案完整地写在
## `_try_play_mother_memory()` 里，任何 NPC 都不轮询剧情状态。
##
## ── 读档恢复 ──────────────────────────────────────────────
## 终态只由 `_apply_*` 系列设置，现场链路也调同一批函数，所以读档进关不会
## 重播任何演出，也不需要为“恢复表现”另造 Flag。详见
## NARRATIVE_LAYER_DESIGN.md §4。

# 剧情 Flag。持久层，命名 <level_id>.<过去式>（见设计文档 §6）。
const FLAG_POISON_DISCOVERED := &"old_courtyard.poison_discovered"
const FLAG_HAIRPIN_NOTICED := &"old_courtyard.hairpin_noticed"
const FLAG_MOTHER_MEMORY_SEEN := &"old_courtyard.mother_memory_seen"
const FLAG_MAID_TALKED := &"old_courtyard.maid_talked"

## “是否持有山鸟簪”只问 MemoryManager，不另配 Flag（设计文档 §6.2）。
const MEMORY_HAIRPIN := &"mountain_bird_hairpin"

@export var courtyard_path: NodePath = ^".."
@export var dialogue_box_path: NodePath
@export var herb_bed_path: NodePath
@export var side_window_path: NodePath
@export var mother_cutscene_path: NodePath
@export var maid_path: NodePath

@onready var _courtyard: OldCourtyard = get_node(courtyard_path)
@onready var _dialogue: Node = get_node(dialogue_box_path)
@onready var _herb_bed: Interactable = get_node(herb_bed_path)
@onready var _side_window: Interactable = get_node(side_window_path)
@onready var _mother_cutscene: Cutscene = get_node(mother_cutscene_path)
@onready var _maid: StoryNPC = get_node(maid_path)

## 侧窗解锁后才是主屋入口。缓存自 Flag，唯一写入点是 _apply_side_window_state()。
var _house_open: bool = false
## “读完这段文字之后再做某事”。原本散在关卡脚本里，按计划 §8 收进 Director。
var _pending_mother_memory: bool = false
var _pending_enter_house: bool = false


# --- 连线 ----------------------------------------------------------------------

func _connect_actors() -> void:
	_herb_bed.interacted.connect(_on_herb_bed_examined)
	_side_window.interacted.connect(_on_side_window_examined)
	_mother_cutscene.finished.connect(_on_mother_cutscene_finished)
	_maid.dialogue_finished.connect(_on_maid_dialogue_finished)
	_dialogue.closed.connect(_on_dialogue_closed)


# --- 恢复链路（幂等，无表现）--------------------------------------------------

func _restore_story_state() -> void:
	_apply_maid_state()
	_apply_side_window_state()


func _apply_maid_state() -> void:
	if StoryFlagManager.has_flag(FLAG_MAID_TALKED):
		_maid.set_present(false)          # 谈过了，人已离场
	else:
		# 幻觉看过但还没谈 → 她应该正等在院里，但不重播入场动画。
		_maid.set_present(StoryFlagManager.has_flag(FLAG_MOTHER_MEMORY_SEEN))


func _apply_side_window_state() -> void:
	_house_open = StoryFlagManager.has_flag(FLAG_MAID_TALKED)
	# 提示语跟着状态走：解锁前它只是一扇可以看的窗，解锁后才是入口。
	_side_window.prompt_text = "从侧窗进屋" if _house_open else "查看侧窗"


# --- 现场链路（一次性，带表现）------------------------------------------------

func _on_herb_bed_examined(_player: Node) -> void:
	if StoryFlagManager.has_flag(FLAG_POISON_DISCOVERED):
		return
	StoryFlagManager.set_flag(FLAG_POISON_DISCOVERED)
	_try_play_mother_memory()


func _on_side_window_examined(_player: Node) -> void:
	# 侧窗身兼两职：解锁前是“调查山鸟纹”，解锁后是主屋入口。
	if _house_open:
		_pending_enter_house = true
		return
	if not StoryFlagManager.has_flag(FLAG_HAIRPIN_NOTICED):
		StoryFlagManager.set_flag(FLAG_HAIRPIN_NOTICED)
	_try_play_mother_memory()


## 两个线索都看过才触发。演出要等交互文字读完再开始，否则会和对话框抢屏幕。
func _try_play_mother_memory() -> void:
	if StoryFlagManager.has_flag(FLAG_MOTHER_MEMORY_SEEN):
		return
	if not StoryFlagManager.has_flag(FLAG_POISON_DISCOVERED):
		return
	if not StoryFlagManager.has_flag(FLAG_HAIRPIN_NOTICED):
		return
	_pending_mother_memory = true


func _on_dialogue_closed() -> void:
	# 只处理本 Director 自己挂起的事；演出内部的文字关闭在这里是空转。
	if _pending_enter_house:
		_pending_enter_house = false
		_courtyard.enter_main_house()
		return
	if _pending_mother_memory:
		_pending_mother_memory = false
		_mother_cutscene.play()


func _on_mother_cutscene_finished() -> void:
	if StoryFlagManager.has_flag(FLAG_MOTHER_MEMORY_SEEN):
		return
	StoryFlagManager.set_flag(FLAG_MOTHER_MEMORY_SEEN)
	# 幻觉之后才真正“认得”这支簪子——信物状态归 MemoryManager。
	MemoryManager.advance_memory(MEMORY_HAIRPIN)
	_maid.enter_scene()


func _on_maid_dialogue_finished() -> void:
	if StoryFlagManager.has_flag(FLAG_MAID_TALKED):
		return
	StoryFlagManager.set_flag(FLAG_MAID_TALKED)
	_maid.leave_scene()
	_apply_side_window_state()
