class_name Cutscene
extends Node
## 演出单元：只管表现——相机、动画、淡入淡出、音频、玩家输入锁。
##
## **禁止**在 Cutscene 里写剧情 Flag、推进信物、解锁门、生成 NPC、决定下一段
## 剧情。演完发 `finished`，剧情后果一律由 StoryDirector 决定。
##
## 子类重写 `_perform()`，演完自己调 `finish()`（基类不 await，避免协程语义坑）。
##
## 输入锁用独立来源 `cutscene`，与 `dialogue_box` / `memory_box` / `area_switch`
## 并存互不干扰——演出结束只会释放自己这一把。

signal started
signal finished

const LOCK_SOURCE := &"cutscene"

@export var player_path: NodePath
## 演出期间是否锁玩家输入。纯环境演出（远景变化）可以关掉。
@export var lock_player: bool = true

var _playing: bool = false


func is_playing() -> bool:
	return _playing


func play() -> void:
	if _playing:
		return
	_playing = true
	if lock_player:
		_lock_player()
	started.emit()
	_perform()


## 提前结束（跳过键、场景切换打断）。表现层自行处理收尾。
func skip() -> void:
	if _playing:
		finish()


## 子类演完后调用。重复调用安全。
func finish() -> void:
	if not _playing:
		return
	_playing = false
	if lock_player:
		_unlock_player()
	finished.emit()


# --- 子类实现 -------------------------------------------------------------------

## 相机推移 / AnimationPlayer / 淡入淡出 / 音频。完成后必须调 `finish()`。
func _perform() -> void:
	finish()


# --- 内部 ----------------------------------------------------------------------

func _get_player() -> Node:
	return get_node_or_null(player_path)


func _lock_player() -> void:
	var p := _get_player()
	if p != null and p.has_method("lock_input"):
		p.lock_input(LOCK_SOURCE)


func _unlock_player() -> void:
	var p := _get_player()
	if p != null and p.has_method("unlock_input"):
		p.unlock_input(LOCK_SOURCE)
