extends StoryDirector
## courtyard_01（前院）的剧情编排。**打开这个文件应该能一眼读出这一关的故事
## 按什么顺序发生。**
##
## 目前是占位骨架：真实存在的因果只有——进关自动存档、调查过的物件记 Flag、
## 拔草放开西侧镜头、尾部的三重旋锁小关卡。
## 其余因果链（谁触发幻觉、丫鬟什么时候来、解锁哪张 CG）等叙事定稿后填。
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
## 里院的门已经开锁。**Flag 名和小关卡的全部数值都归 `InnerGateLockConfig`**，
## 这里只引用，不另抄一份字符串。
const FLAG_INNER_GATE_UNLOCKED := InnerGateLockConfig.FLAG_DOOR_UNLOCKED

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
@onready var _trap: BacktrackTrap = get_node_or_null(^"../Props/InnerGateTrap") as BacktrackTrap
@onready var _lock: RotaryLockUI = get_node_or_null(^"../RotaryLock") as RotaryLockUI


func _connect_actors() -> void:
	if _gate != null:
		_gate.interacted.connect(_on_gate_examined)
	if _well != null:
		_well.interacted.connect(_on_well_examined)
	if _weeds != null:
		_weeds.cleared.connect(_on_weeds_cleared)
	# 门锁着时按 E 的反馈就是「把锁翻出来」：门自己只回答能不能走，
	# 「现在该弹锁界面」是编排，不是门的事。
	if _exit != null:
		_exit.interaction_blocked.connect(_on_locked_gate_tried)
	if _lock != null:
		_lock.solved.connect(_on_gate_lock_solved)
	if _trap != null:
		_trap.activated.connect(_on_trap_activated)


func _restore_story_state() -> void:
	_apply_west_passage()
	_apply_inner_gate_lock()


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


## 门锁着时按 E：把三重旋锁翻出来。UI 自己有 `can_open()` 闸门，
## 连按或按住不放都只会有一个界面，也不会开完立刻被同一次输入关掉。
func _on_locked_gate_tried(_player: Node) -> void:
	if _lock != null:
		_lock.open()


## 走进尾部区域之后给相机挂一道待落的左闸门：**等画面最左侧自己走到 7700 才
## 落闸**，所以画面不会在某一帧跳一下，之后西边的视野也让不回来了。
## 和西侧杂草共用 FollowCamera2D 的同一层闸门，所以解锁时不能直接
## `release_left_gate()`，要重新跑一遍 `_apply_west_passage()`（见下）。
func _on_trap_activated() -> void:
	if _camera != null:
		_camera.arm_left_gate_latch(int(InnerGateLockConfig.TRAP_CAMERA_GATE_X))


## 锁开了。**这里是唯一写「门已解锁」的地方**：锁界面只发 `solved`，
## 门槛怎么放开、尾部的返回封锁怎么撤，都在这一条链上。
func _on_gate_lock_solved() -> void:
	if StoryFlagManager.has_flag(FLAG_INNER_GATE_UNLOCKED):
		return
	StoryFlagManager.set_flag(FLAG_INNER_GATE_UNLOCKED)
	_apply_inner_gate_lock()


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


## 里院门锁的终态。门槛本身是 `LevelExit.required_flag`（场景里已填同一个
## Flag，这里补一次保证 Flag 名只有一个来源）；这里摆的是**跟着它一起变**
## 的东西：尾部返回封锁还生不生效、锁界面还能不能玩。
## 幂等 —— 现场解锁和读档恢复走同一条路。
func _apply_inner_gate_lock() -> void:
	var unlocked := StoryFlagManager.has_flag(FLAG_INNER_GATE_UNLOCKED)
	if _exit != null:
		_exit.required_flag = FLAG_INNER_GATE_UNLOCKED
	if _lock != null:
		_lock.set_solved(unlocked)
	if _trap != null and unlocked:
		# 锁一开：硬边界撤掉、x=7800 的黑幕重置失效。旧触发器留在场景里
		# 也不会再传送玩家，西边被封的那一段重新走得通。
		_trap.disarm()
	if unlocked and _camera != null:
		# 待落闸门撤掉，并把画面左边界交还给西侧通路的规则
		# （杂草没拔 → 1350，拔了 → 场景边界）。不能直接 release：
		# 那会顺手把杂草那道闸门也打开。
		_camera.arm_left_gate_latch(-1)
		_apply_west_passage()
