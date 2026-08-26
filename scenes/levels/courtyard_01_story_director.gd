extends StoryDirector
## courtyard_01（前院）的剧情编排。**打开这个文件应该能一眼读出这一关的故事
## 按什么顺序发生。**
##
## 目前是占位骨架：只做两件真实的事——进关自动存档、调查过的物件记 Flag。
## 因果链（谁触发幻觉、丫鬟什么时候来、解锁哪张 CG）等叙事定稿后填。
##
## 写新剧情节点时照这个模板：
##   `_on_<事件>()`   现场触发，一次性，幂等闸门 → 写 Flag/Memory/CG → 触发表现
##   `_apply_<节点>()` 幂等摆终态，无表现，现场链路和恢复链路都调它
##   `_restore_story_state()` 把所有 `_apply_*` 跑一遍
## 详见 NARRATIVE_LAYER_DESIGN.md §4。

# 本关剧情节点。持久层，命名 <level_id>.<过去式>。
const FLAG_GATE_EXAMINED := &"courtyard_01.gate_examined"
const FLAG_WELL_EXAMINED := &"courtyard_01.well_examined"

## 信物：是否持有只问 MemoryManager，不另配 Flag。
const MEMORY_HAIRPIN := &"mountain_bird_hairpin"

@export var dialogue_box_path: NodePath

@onready var _courtyard: CourtyardLevel = get_node(level_path) as CourtyardLevel
@onready var _gate: Interactable = get_node_or_null(^"../Props/GateSpot")
@onready var _well: Interactable = get_node_or_null(^"../Props/WellSpot")
@onready var _hairpin: Interactable = get_node_or_null(^"../Props/HairpinPickup")
@onready var _exit: LevelExit = get_node_or_null(^"../Props/ToNextLevel")


func _connect_actors() -> void:
	if _gate != null:
		_gate.interacted.connect(_on_gate_examined)
	if _well != null:
		_well.interacted.connect(_on_well_examined)
	if _hairpin != null:
		_hairpin.interacted.connect(_on_hairpin_taken)


func _restore_story_state() -> void:
	_apply_exit_state()


func _on_story_ready() -> void:
	# 进关自动存一次。放在恢复之后，存下来的就是玩家真正看到的状态。
	# 没有活动槽位时（F6 单开、headless 测试）不写盘。
	if _courtyard != null:
		_courtyard.autosave()


# --- 现场链路 -------------------------------------------------------------------

func _on_gate_examined(_player: Node) -> void:
	if StoryFlagManager.has_flag(FLAG_GATE_EXAMINED):
		return
	StoryFlagManager.set_flag(FLAG_GATE_EXAMINED)


func _on_well_examined(_player: Node) -> void:
	if StoryFlagManager.has_flag(FLAG_WELL_EXAMINED):
		return
	StoryFlagManager.set_flag(FLAG_WELL_EXAMINED)
	# 占位接线：让画廊管线能被真正走通一遍（解锁 → NEW 角标 → 跨档保留）。
	# 剧情定稿后换成真正该在这里解锁的那张 CG。
	GalleryManager.unlock_cg(&"cg_placeholder_01")


func _on_hairpin_taken(_player: Node) -> void:
	# 拾取本身由 MemoryPickup 完成（它已经调过 unlock_memory）。
	# Director 只决定"拿到之后怎么样"。
	_apply_exit_state()


# --- 恢复链路 -------------------------------------------------------------------

## 占位门槛：拿到山鸟簪才能往里走。等剧情定稿后换成真正的条件。
func _apply_exit_state() -> void:
	if _exit == null:
		return
	var owned := MemoryManager.has_memory(MEMORY_HAIRPIN)
	_exit.required_memory = MEMORY_HAIRPIN if not owned else &""
	_exit.blocked_prompt_text = "（占位）里院的门闩着——手上似乎少了什么"
