class_name StoryDirector
extends Node
## 关卡剧情编排层：只回答“什么时候发生什么”，不实现任何具体行为。
##
## 每个正式关卡挂一个自己的子类（`<level>_story_director.gd`），
## 作为关卡根的**普通子节点**。**不要做成 Autoload。**
##
## 子类实现三个钩子，执行顺序固定：
##   _connect_actors()       连信号。此时禁止读剧情状态（见下方时序说明）。
##   _restore_story_state()  幂等：按现有 Flag / Memory 把场景摆成应有的终态。
##   _on_story_ready()       恢复完成后的一次性开场（可选）。
##
## ── 时序（这是本类存在的主要理由）──────────────────────────────
## Godot 的 `_ready()` 是**子节点先于父节点**。Director 挂在关卡根下，
## 所以 `StoryDirector._ready()` 跑的时候：
##   · 玩家还没被 `LevelBase._place_player()` 放置；
##   · `StoryFlagManager.clear_session()` 还没执行——此刻读到的 session flag
##     是上一关的残留，而且马上会被清掉；
##   · `WorldTimeManager.reset_state()` 还没执行；
##   · MovementMode 还没下发。
## 因此恢复剧情状态必须等 `LevelBase` 跑完。`LevelBase` 在 `_ready()` 末尾发
## `level_started`，而子节点的 `_ready()` 先跑，所以 Director 一定来得及连上
## 这个信号——比 `call_deferred` 猜时序更确定，且 `LevelBase` 一行不用改。
##
## ── 职责边界 ───────────────────────────────────────────────
## Director 是导演，不是演员。可以调 `npc.enter_scene()` / `cutscene.play()` /
## `door.set_unlocked()`，但不实现寻路、动画、相机、音频、开门表现。
## 反过来，演员不许自己决定剧情：Cutscene 不写 Flag，NPC 不轮询剧情状态，
## Dialogue 不决定下一段剧情。

## 宿主关卡。默认取父节点——Director 必须是关卡根的直接子节点。
@export var level_path: NodePath = ^".."

var _level: LevelBase = null


func _ready() -> void:
	_level = get_node_or_null(level_path) as LevelBase
	_connect_actors()
	if _level != null:
		_level.level_started.connect(_on_level_started, CONNECT_ONE_SHOT)
	else:
		# 宿主不是 LevelBase（临时测试壳）时退化为延迟一帧，行为等价但不保证
		# 顺序，正式关卡不应该走到这里。
		push_warning("StoryDirector: 宿主不是 LevelBase，退化为 call_deferred 恢复。")
		_on_level_started.call_deferred()


func _on_level_started() -> void:
	_restore_story_state()
	_on_story_ready()


# --- 子类实现 -------------------------------------------------------------------

## 连接演员的信号。只连线，不读状态、不改场景。
func _connect_actors() -> void:
	pass


## 幂等地把场景摆成“当前剧情状态对应的终态”，**不播任何表现**。
## 读档进关和从头玩到这里都会经过它，所以它必须能重复调用。
## 约定：终态只由 `_apply_*` 系列函数设置，现场链路也调同一批函数。
func _restore_story_state() -> void:
	pass


## 恢复完成之后的一次性开场（进关旁白、首次进入的提示等）。
func _on_story_ready() -> void:
	pass
