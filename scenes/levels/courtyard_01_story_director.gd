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
## 西侧杂草已拔除 —— 拔完相机左边界才放开、才走得过去。
const FLAG_WEEDS_CLEARED := &"courtyard_01.weeds_cleared"

## 信物：是否持有只问 MemoryManager，不另配 Flag。
const MEMORY_HAIRPIN := &"mountain_bird_hairpin"

## 杂草未清除时画面最左侧停在哪。和场景里 WeedBlocker 的右侧面对齐。
const WEST_GATE_X := 1350
## 拔完草之后镜头滑开用多久。
const WEST_GATE_SLIDE := 1.4
## 滑镜头期间的输入锁来源。
const LOCK_CAMERA_SLIDE := &"west_gate_slide"

@export var dialogue_box_path: NodePath

@onready var _courtyard: CourtyardLevel = get_node(level_path) as CourtyardLevel
@onready var _gate: Interactable = get_node_or_null(^"../Props/GateSpot")
@onready var _well: Interactable = get_node_or_null(^"../Props/WellSpot")
@onready var _hairpin: Interactable = get_node_or_null(^"../Props/HairpinPickup")
@onready var _exit: LevelExit = get_node_or_null(^"../Props/ToNextLevel")
@onready var _weeds: PassageGate = get_node_or_null(^"../Props/WeedsGate") as PassageGate
@onready var _camera: FollowCamera2D = get_node_or_null(^"../FollowCamera2D") as FollowCamera2D


func _connect_actors() -> void:
	if _gate != null:
		_gate.interacted.connect(_on_gate_examined)
	if _well != null:
		_well.interacted.connect(_on_well_examined)
	if _hairpin != null:
		_hairpin.interacted.connect(_on_hairpin_taken)
	if _weeds != null:
		_weeds.cleared.connect(_on_weeds_cleared)


func _restore_story_state() -> void:
	_apply_exit_state()
	_apply_west_passage()


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


func _on_weeds_cleared() -> void:
	# 障碍物自己已经把碰撞关掉、把 Flag 写好（PassageGate）。
	# Director 只决定"清完之后世界怎么变"——这里是把画面往西缓缓放开。
	if _camera == null:
		return
	# 滑动期间锁住玩家：让玩家看清楚西边多出来的那截路，也免得他一边走
	# 一边镜头在动，两个位移叠在一起看着晃。
	var player := get_node_or_null(^"../Player")
	if player != null and player.has_method("lock_input"):
		player.lock_input(LOCK_CAMERA_SLIDE)
		_camera.left_gate_opened.connect(
			func() -> void: player.unlock_input(LOCK_CAMERA_SLIDE),
			CONNECT_ONE_SHOT)
	_camera.slide_left_gate_open(WEST_GATE_SLIDE)


# --- 恢复链路 -------------------------------------------------------------------

## 西侧通路：杂草没拔掉之前画面最左停在 1350，拔掉后回到真实场景边界。
## 相机闸门放在 Director 而不是 PassageGate 里——"清障之后镜头能看多远"是
## 关卡编排，不是那丛草自己的事。
func _apply_west_passage() -> void:
	if _camera == null:
		return
	if StoryFlagManager.has_flag(FLAG_WEEDS_CLEARED):
		# 恢复链路只摆终态、不放动画——读档回来不该再看一遍镜头滑动。
		_camera.release_left_gate()
	else:
		_camera.set_left_gate(WEST_GATE_X)


## 占位门槛：拿到山鸟簪才能往里走。等剧情定稿后换成真正的条件。
func _apply_exit_state() -> void:
	if _exit == null:
		return
	var owned := MemoryManager.has_memory(MEMORY_HAIRPIN)
	_exit.required_memory = MEMORY_HAIRPIN if not owned else &""
	_exit.blocked_prompt_text = "（占位）里院的门闩着——手上似乎少了什么"
