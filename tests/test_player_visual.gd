extends LevelBase
## Test room: 立娘 sprite 表现层（idle / walk 切换 + 朝向 + 脚线对位）。
##
## Automated on start (results printed as [TEST:visual] lines):
##  - SpriteFrames 真的挂上了，idle 4 帧 / walk 6 帧
##  - 有真素材时 Sprite 显示、灰盒隐藏
##  - 按住 move_right/move_left 走 → walk 动画；松手减速停下 → idle
##  - 朝左 flip_h = true，朝右 flip_h = false
##  - 脚线落在 Player 原点上（原点 = 着地点，是全项目的对位约定）
##  - 碰撞盒高度和贴图里人物的实际高度相称
## Manual (real keyboard): A/D 来回走，肉眼确认不打滑、不悬空、不左右跳。

## 单帧尺寸。素材约定：512x512，人物朝右。
const FRAME_SIZE: int = 512
## 人物在单帧里的脚线 / 头顶（用 alpha 边界量出来的，改素材要同步改这里）。
const SOURCE_FOOT_Y: float = 484.0
const SOURCE_HEAD_Y: float = 15.0

@onready var _p: CharacterBody2D = get_node(player_path)
@onready var _visual: PlayerVisual = _p.get_node("PlayerVisual")
@onready var _sprite: AnimatedSprite2D = _p.get_node("PlayerVisual/Sprite")
@onready var _graybox: CanvasItem = _p.get_node("Visual")
@onready var _status: Label = $UI/StatusLabel

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	super._ready()
	_run_self_test.call_deferred()


func _process(_delta: float) -> void:
	_status.text = "State: %s\nAnim: %s   flip_h: %s\nvel.x: %.0f\n\nA/D 走动" % [
		_p.State.keys()[_p.get_state()],
		_sprite.animation, str(_sprite.flip_h), _p.velocity.x,
	]


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass_count += 1
		print("[TEST:visual] PASS  %s" % label)
	else:
		_fail_count += 1
		print("[TEST:visual] FAIL  %s" % label)


## 按住某个动作跑若干物理帧。用 Input.action_press 而不是伪造事件，
## 走的就是 player.gd 里真实的 get_axis 路径。
func _hold(action: StringName, frames: int) -> void:
	if action != &"":
		Input.action_press(action)
	for _i in frames:
		await get_tree().physics_frame
	if action != &"":
		Input.action_release(action)


func _run_self_test() -> void:
	print("[TEST:visual] --- self-test start ---")

	# --- 素材接上了没 ---
	var frames := _sprite.sprite_frames
	_check(frames != null, "Sprite 挂上了 SpriteFrames")
	if frames == null:
		_finish()
		return
	_check(frames.has_animation(&"idle") and frames.has_animation(&"walk"),
		"SpriteFrames 里有 idle 和 walk")
	_check(frames.get_frame_count(&"idle") == 4,
		"idle 4 帧（实际 %d）" % frames.get_frame_count(&"idle"))
	_check(frames.get_frame_count(&"walk") == 6,
		"walk 6 帧（实际 %d）" % frames.get_frame_count(&"walk"))
	_check(frames.get_animation_loop(&"idle") and frames.get_animation_loop(&"walk"),
		"两个动画都是循环播放")
	# 图集切分：每帧 512x512，横向依次排开。
	var region_ok := true
	for anim in [&"idle", &"walk"]:
		for i in frames.get_frame_count(anim):
			var tex := frames.get_frame_texture(anim, i) as AtlasTexture
			if tex == null or tex.region != Rect2(i * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE):
				region_ok = false
	_check(region_ok, "每帧图集区域 = Rect2(i*512, 0, 512, 512)")

	# --- 真素材模式下灰盒让位 ---
	_check(_sprite.visible and not _graybox.visible,
		"有真素材时 Sprite 显示、灰盒隐藏")

	# --- 对位：脚线落在原点，碰撞盒配得上人物高度 ---
	# Sprite centered = true：源像素 py 画在局部 (py - 256 + offset.y) * scale.y。
	var half := float(FRAME_SIZE) * 0.5
	var foot_local: float = (SOURCE_FOOT_Y - half + _sprite.offset.y) * _sprite.scale.y
	var head_local: float = (SOURCE_HEAD_Y - half + _sprite.offset.y) * _sprite.scale.y
	_check(_sprite.centered, "Sprite centered = true（flip_h 绕人物中轴镜像）")
	_check(absf(foot_local) <= 2.0,
		"脚线对在 Player 原点上（偏差 %.1fpx）" % foot_local)
	var visual_height := absf(head_local - foot_local)
	var box_height: float = _p.get_body_half_extents().y * 2.0
	_check(absf(box_height - visual_height) / visual_height < 0.15,
		"碰撞盒高 %.0f 和人物贴图高 %.0f 相称" % [box_height, visual_height])
	# 碰撞盒必须整个站在原点之上，否则脚会陷进地板。
	var box_shape: CollisionShape2D = _p.get_node("CollisionShape2D")
	_check(is_equal_approx(box_shape.position.y, -_p.get_body_half_extents().y),
		"碰撞盒完整地站在原点之上")

	# --- idle / walk 来回切 ---
	await _hold(&"", 4)
	_check(_p.get_state() == _p.State.IDLE, "落地静止 → IDLE")
	_check(_sprite.animation == &"idle", "IDLE → 播 idle（实际 '%s'）" % _sprite.animation)

	await _hold(&"move_right", 12)
	# action_release 之后立刻看：这一帧还在减速，仍应是 walk。
	_check(_sprite.animation == &"walk",
		"按 D 向右走 → 播 walk（实际 '%s'）" % _sprite.animation)
	_check(not _sprite.flip_h, "向右不翻转")
	_check(_p.get_facing() == 1, "向右 facing = +1")

	# 减速停下（deceleration 2600，几帧就够）。
	await _hold(&"", 20)
	_check(_p.get_state() == _p.State.IDLE, "松手减速后 → IDLE")
	_check(_sprite.animation == &"idle",
		"松手后自动切回 idle（实际 '%s'）" % _sprite.animation)

	await _hold(&"move_left", 12)
	_check(_sprite.animation == &"walk",
		"按 A 向左走 → 播 walk（实际 '%s'）" % _sprite.animation)
	_check(_sprite.flip_h, "向左 flip_h = true")
	_check(_p.get_facing() == -1, "向左 facing = -1")

	await _hold(&"", 20)
	_check(_sprite.animation == &"idle", "再次松手 → idle")
	_check(_sprite.flip_h, "停下后保持朝左（idle 不重置朝向）")

	# 动画确实在推进，不是卡在第 0 帧。
	_check(_sprite.is_playing(), "动画在播放中，没有停住")

	_finish()


func _finish() -> void:
	print("[TEST:visual] --- self-test done: %d pass, %d fail ---"
		% [_pass_count, _fail_count])
	if DisplayServer.get_name() == "headless":
		get_tree().quit(_fail_count)
