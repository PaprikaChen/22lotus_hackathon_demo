class_name FootstepSfx
extends AudioStreamPlayer
## 丽娘的脚步声：跟着 Player 的移动状态循环播放，停下即停。
##
## 挂在 player.tscn 上而不是各个关卡里——脚步是**角色**的表现而不是场景布置，
## 挂一次所有关卡都有，也不会出现某个关卡漏配的情况。
##
## 单向依赖：只监听 Player 的 `state_changed`，绝不反向驱动移动
## （和 `player_visual.gd` 同一条纪律）。
##
## 素材是一段连续的脚步循环，所以运行时把 stream 复制一份并打开 `loop`，
## 而不是去改 `.import`——导入设置是全项目共享的，别的地方要一次性播放
## 同一个文件时不该被这里的循环需求影响。

@export var player_path: NodePath = ^".."
## 整关开关。关卡通过 LevelBase.player_footsteps → Player.set_footsteps_enabled()
## 下发。关掉时立刻收声，不等淡出——关掉的场合（上船、过场）都不希望还有余音。
@export var enabled: bool = true:
	set = set_enabled
## 从静止到起步的淡入时长，避免瞬间满音量的爆音。
@export var fade_in: float = 0.08
## 停步的淡出时长。比淡入稍长一点，听起来像最后一步收住。
@export var fade_out: float = 0.12
## 正常行走时的音量。淡入淡出都以它为基准。
@export var walk_volume_db: float = -6.0

var _player: Player = null
var _fade: Tween = null


func _ready() -> void:
	if stream != null:
		var looped := stream.duplicate()
		# AudioStreamMP3 / OggVorbis / WAV 都有 loop，但类型不保证，做个防御。
		if "loop" in looped:
			looped.set("loop", true)
		stream = looped
	volume_db = walk_volume_db
	_player = get_node_or_null(player_path) as Player
	if _player == null:
		push_warning("FootstepSfx: 没找到 Player，脚步声不会响。")
		return
	_player.state_changed.connect(_on_state_changed)
	_apply_state(_player.get_state())


func _on_state_changed(_previous: Player.State, current: Player.State) -> void:
	_apply_state(current)


## 只有 RUN 才有脚步。跳跃 / 下落在空中，INTERACT 和 DISABLED 人没在走。
func _apply_state(state: Player.State) -> void:
	if not enabled:
		return
	if state == Player.State.RUN:
		_start()
	else:
		_stop()


func _start() -> void:
	if stream == null:
		return
	_kill_fade()
	if not playing:
		volume_db = walk_volume_db - 24.0
		play()
	if fade_in > 0.0:
		_fade = create_tween()
		_fade.tween_property(self, ^"volume_db", walk_volume_db, fade_in)
	else:
		volume_db = walk_volume_db


func _stop() -> void:
	if not playing:
		return
	_kill_fade()
	if fade_out <= 0.0:
		stop()
		return
	_fade = create_tween()
	_fade.tween_property(self, ^"volume_db", walk_volume_db - 24.0, fade_out)
	_fade.tween_callback(stop)


func _kill_fade() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = null


func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled and is_node_ready():
		_kill_fade()
		if playing:
			stop()
