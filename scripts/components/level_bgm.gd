class_name LevelBgm
extends AudioStreamPlayer
## 关卡 BGM：进关渐入，离场渐出。挂在关卡根节点下当子节点用。
##
## 职责边界：**只管一条音轨的音量包络**。它不认识关卡、不读 Flag、不切场景；
## 什么时候该响由挂它的场景决定，什么时候该停由「场景没了」或调用方决定。
##
## 为什么不做 BgmManager 自动加载：项目现在连 SceneManager 都刻意没抽
## （见 `level_exit.gd` 的说明），而且改 autoload 要先问。这里用一个纯组件
## 达到同样效果，等真需要跨关卡续播同一条曲子时再谈单例。
##
## **离场渐出怎么活过 change_scene**：切场景是硬切，本节点会被连同关卡一起
## free，Tween 根本没机会跑完。所以 `tree_exiting` 时另起一个脱离本场景的
## AudioStreamPlayer 挂到 root 上，从同一个播放位置接着放并在那边淡出、
## 播完自己 queue_free。和 `prologue_screen.gd` 里黑幕/入场音效挂 root
## 是同一条思路——要活过场景切换，就不能待在被切掉的那棵树里。

## 淡入 / 淡出时长。渐入渐出是这一件的存在理由，默认给得比音效长得多。
@export var fade_in_duration: float = 2.5
@export var fade_out_duration: float = 2.0
## 正常播放音量。淡入淡出都以它为基准。
@export var bgm_volume_db: float = -10.0
## 进关就自动淡入。演出专用的音轨（例如回忆片段）设 false，由 Director 点。
@export var autoplay_on_ready: bool = true
## 离场（本节点退出场景树）自动淡出。
@export var fade_out_on_exit: bool = true
## 循环播放。BGM 基本都要，运行时改 stream 副本，不动 .import。
@export var loop_stream: bool = true

## 淡出的终点。不用 -80：到 -40 已经完全听不见，曲线也更自然。
const SILENT_OFFSET_DB := 40.0

var _tween: Tween = null
## 已经把淡出交接给 root 上的临时节点了，别重复交接。
var _handed_off: bool = false


func _ready() -> void:
	# 过场里常有 `get_tree().paused = true`（锁界面、暂停菜单）。BGM 不该
	# 跟着断掉，否则每次开界面音乐都会咔一下。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_loop()
	volume_db = _silent_db()
	tree_exiting.connect(_on_tree_exiting)
	if autoplay_on_ready:
		fade_in()


## 淡入并开始播放。已经在播就只把音量拉回来，不会从头重放。
func fade_in(duration: float = -1.0) -> void:
	if stream == null:
		return
	var seconds := fade_in_duration if duration < 0.0 else duration
	_kill_tween()
	if not playing:
		volume_db = _silent_db()
		play()
	if seconds <= 0.0:
		volume_db = bgm_volume_db
		return
	_tween = _make_tween()
	_tween.tween_property(self, ^"volume_db", bgm_volume_db, seconds)


## 淡出并停止。淡完才 stop，中途再 fade_in() 可以无缝接回来。
func fade_out(duration: float = -1.0) -> void:
	if not playing:
		return
	var seconds := fade_out_duration if duration < 0.0 else duration
	_kill_tween()
	if seconds <= 0.0:
		stop()
		return
	_tween = _make_tween()
	_tween.tween_property(self, ^"volume_db", _silent_db(), seconds)
	_tween.tween_callback(stop)


func is_fading() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


# --- 内部 ----------------------------------------------------------------------

func _silent_db() -> float:
	return bgm_volume_db - SILENT_OFFSET_DB


## Tween 也要能在暂停期间跑，否则暂停菜单一开淡入淡出就卡住。
func _make_tween() -> Tween:
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return tween


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


## 循环开在 stream 的**副本**上：导入设置是全项目共享的，别的地方要一次性
## 播放同一个文件时不该被这里的循环需求影响（和 `footstep_sfx.gd` 同一条纪律）。
func _apply_loop() -> void:
	if stream == null or not loop_stream:
		return
	var looped := stream.duplicate()
	# MP3 / OggVorbis 是 `loop`（bool），WAV 是 `loop_mode`（枚举）。
	if "loop_mode" in looped:
		looped.set("loop_mode", AudioStreamWAV.LOOP_FORWARD)
	elif "loop" in looped:
		looped.set("loop", true)
	stream = looped


## 离场交接。此时本节点马上就要被 free，所以淡出必须换个地方做。
func _on_tree_exiting() -> void:
	if not fade_out_on_exit or _handed_off or stream == null or not playing:
		return
	if fade_out_duration <= 0.0:
		return
	var tree := get_tree()
	if tree == null or tree.root == null or tree.root.is_queued_for_deletion():
		return
	_handed_off = true
	var fader := AudioStreamPlayer.new()
	fader.name = "BgmFadeOut"
	fader.stream = stream
	fader.bus = bus
	fader.volume_db = volume_db
	fader.process_mode = Node.PROCESS_MODE_ALWAYS
	var position := get_playback_position()
	var target := _silent_db()
	var seconds := fade_out_duration
	fader.ready.connect(func() -> void:
		fader.play(position)
		var tween := fader.create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(fader, ^"volume_db", target, seconds)
		tween.tween_callback(fader.queue_free))
	# 必须 deferred：这一刻旧场景正在被拆，直接往 root 上挂节点不安全。
	# 延到下一次空闲时，旧场景已经拆完、新场景已经进来，接着淡出即可。
	tree.root.add_child.call_deferred(fader)


func _exit_tree() -> void:
	_kill_tween()
