class_name BacktrackTrap
extends Node2D
## 「走进去就回不了头」的返回封锁 + 黑幕重置机关（横版，只看世界 x）。
##
## 三件事，全部由 `InnerGateLockConfig` 提供数值：
##   1. 玩家第一次走到 `TRAP_ACTIVATE_X` → 激活（**一次性**）；
##   2. 激活后往西到 `TRAP_RESET_X` → 淡出 / 传送到 `TRAP_RESPAWN_X` / 淡入；
##   3. `TRAP_WALL_X` 上的硬边界墙作兜底，正常情况玩家先被黑幕送回。
##
## 相机闸门不在这里：Director 接到 `activated` 后给 FollowCamera2D 挂一道
## 待落闸门（走过去才落），"镜头能看多远"始终是关卡编排的事。
##
## **它不知道"为什么"锁着**：解锁条件、Flag、门的状态全部归 StoryDirector。
## Director 解锁后调 `disarm()`，之后这个节点即使还在场景里也不再传送、不再挡路。
##
## 为什么不每帧改玩家坐标：那样会抖。西侧封锁由一面真实的 StaticBody2D
## （`wall_path`）完成，本脚本只负责按需开关它的碰撞层——和 `PassageGate`
## 清障用的是同一套做法。
##
## 重入保护：`_is_resetting` 单闸门。黑幕期间玩家被输入锁按住
## （来源 `backtrack_reset`，与 dialogue / memory_box / cutscene 并存，
## 只释放自己那一把），水平速度清零，所以不会"传送完立刻又被旧速度带回去"。

signal activated ## 首次进入尾部区域（只发一次）
signal reset_started
signal reset_finished
signal text_requested(text: String) ## 走关卡的共用 DialogueBox（关卡自动接线）

const LOCK_SOURCE := &"backtrack_reset"

@export var player_path: NodePath
## 兜底硬边界用的 StaticBody2D。右侧面应对齐 `InnerGateLockConfig.TRAP_WALL_X`。
@export var wall_path: NodePath
## 全屏黑幕（`ScreenFade`）。没接上时退化为"不淡入淡出直接传送"，功能不阻塞。
@export var fade_path: NodePath
## 首次激活时的一句提示。留空则不出文字。
@export_multiline var activate_text: String = ""
## 被送回来时的一句提示。留空则不出文字。
@export_multiline var reset_text: String = ""
## 开着（默认）= 这句提示只在**第一次**被送回来时出；之后直接黑幕重生，
## 不再重复解释。反复读同一句话会把"回不去"这件事讲成噪音。
@export var reset_text_once: bool = true

var _player: Node2D = null
var _wall: CollisionObject2D = null
var _fade: ScreenFade = null

## 玩家是否已经首次到达尾部区域（本关运行时状态，不入档）。
var _is_activated: bool = false
## 是否正在执行黑幕重置。重入闸门。
var _is_resetting: bool = false
## 已经执行过几次黑幕重置。`reset_text_once` 靠它只让第一次出字幕。
var _reset_count: int = 0
## 机关是否仍然生效。锁一开就永久 false。
var _is_armed: bool = true


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node2D
	_wall = get_node_or_null(wall_path) as CollisionObject2D
	_fade = get_node_or_null(fade_path) as ScreenFade
	if _player == null:
		push_warning("BacktrackTrap: 没接上 player_path，机关不会生效。")
	_apply_wall()


func _physics_process(_delta: float) -> void:
	if not _is_armed or _is_resetting or _player == null:
		return
	var x := _player.global_position.x
	if not _is_activated:
		if x >= InnerGateLockConfig.TRAP_ACTIVATE_X:
			_activate()
		return
	if x <= InnerGateLockConfig.TRAP_RESET_X:
		_begin_reset()


# --- 状态查询（测试和 Director 用）---------------------------------------------

func is_activated() -> bool:
	return _is_activated


func is_resetting() -> bool:
	return _is_resetting


func get_reset_count() -> int:
	return _reset_count


func is_armed() -> bool:
	return _is_armed


# --- Director 调用 -------------------------------------------------------------

## 永久解除：撤掉硬边界、不再传送。幂等，读档恢复链路也调它。
func disarm() -> void:
	_is_armed = false
	_apply_wall()


## 重新武装（调试 / 剧情倒带用）。不会重置"已激活"状态。
func arm() -> void:
	_is_armed = true
	_apply_wall()


# --- 内部 ---------------------------------------------------------------------

func _activate() -> void:
	if _is_activated:
		return
	_is_activated = true
	_apply_wall()
	InnerGateLockConfig.log_debug("陷阱激活于 x=%.1f" % _player.global_position.x)
	activated.emit()
	if not activate_text.is_empty():
		text_requested.emit(activate_text)


## 硬边界只在「已激活且仍生效」时挡人：没走到尾部之前西边的路照常通行，
## 锁一开就彻底放开。
func _apply_wall() -> void:
	if _wall == null:
		return
	var blocking := _is_armed and _is_activated
	_wall.collision_layer = 1 if blocking else 0
	_wall.visible = false


func _begin_reset() -> void:
	if _is_resetting:
		return
	_is_resetting = true
	_do_reset()


func _do_reset() -> void:
	reset_started.emit()
	_lock_player()
	if _fade != null:
		await _fade.fade_out(InnerGateLockConfig.FADE_OUT_SECONDS)
	_teleport_player()
	if InnerGateLockConfig.FADE_HOLD_SECONDS > 0.0:
		await get_tree().create_timer(
			InnerGateLockConfig.FADE_HOLD_SECONDS, true, false, true).timeout
	if _fade != null:
		await _fade.fade_in(InnerGateLockConfig.FADE_IN_SECONDS)
	_unlock_player()
	_is_resetting = false
	_reset_count += 1
	reset_finished.emit()
	if not reset_text.is_empty() and not (reset_text_once and _reset_count > 1):
		text_requested.emit(reset_text)


func _teleport_player() -> void:
	if _player == null:
		return
	# 只改 x：y 保留玩家当前的合理高度（横版这一段是平地，落点必然在地面上），
	# 不去猜一个可能卡进碰撞体的新 y。玩家原点是脚底（AGENTS.md §2），
	# 所以这个坐标就是"她站的那一点"。
	_player.global_position.x = InnerGateLockConfig.TRAP_RESPAWN_X
	if _player is CharacterBody2D:
		# 清掉水平速度，否则松手前按着的方向会立刻把她带回触发线。
		var body := _player as CharacterBody2D
		body.velocity.x = 0.0
	# 出生点跟着走：这一段被封死之后，死亡重生不该把她扔回西边。
	if _player.has_method("set_spawn_point"):
		_player.set_spawn_point(_player.global_position)
	InnerGateLockConfig.log_debug("黑幕重置 → x=%.1f" % InnerGateLockConfig.TRAP_RESPAWN_X)


func _lock_player() -> void:
	if _player != null and _player.has_method("lock_input"):
		_player.lock_input(LOCK_SOURCE)
	if _player is CharacterBody2D:
		(_player as CharacterBody2D).velocity = Vector2.ZERO


func _unlock_player() -> void:
	if _player != null and _player.has_method("unlock_input"):
		_player.unlock_input(LOCK_SOURCE)


func _exit_tree() -> void:
	# 场景卸载时把锁还掉，别让输入锁跨场景残留（LevelBase 也会兜底清理）。
	if _is_resetting:
		_unlock_player()
