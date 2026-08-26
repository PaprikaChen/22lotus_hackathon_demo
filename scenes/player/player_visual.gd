class_name PlayerVisual
extends Node2D
## 玩家表现层：把 Player 的状态和朝向映射到动画与左右翻转。
##
## 单向依赖：只监听 player 的 `state_changed` / `direction_changed`，
## **绝不**反向驱动移动。AGENTS.md 硬规则——移动逻辑不得依赖动画资源名，
## 所以这份「状态 → 动画名」的映射只存在于本文件。
##
## 素材还没交付时自动退化为现有的灰盒 Polygon2D：`sprite_path` 指向的
## AnimatedSprite2D 没有 SpriteFrames 就走灰盒，所以这个组件可以先落地，
## 等 liniang_idle.png / liniang_walk.png 到位再填帧。
##
## 朝向：美术只画朝右的一套，向左由 `flip_h` 镜像（见 2D 人物 Sprite 交付规范）。

@export var player_path: NodePath = ^".."
## AnimatedSprite2D。没有 SpriteFrames 时本组件自动隐藏它并显示灰盒。
@export var sprite_path: NodePath
## 现有的灰盒 Polygon2D。接上真素材后自动隐藏。
@export var graybox_path: NodePath

@export_group("Animation Names")
@export var anim_idle: StringName = &"idle"
@export var anim_walk: StringName = &"walk"
@export var anim_interact: StringName = &"interact"

var _player: Player = null
var _sprite: AnimatedSprite2D = null
var _graybox: CanvasItem = null
## 有真素材可播。false = 灰盒模式，本组件只做翻转不碰动画。
var _has_frames: bool = false


func _ready() -> void:
	_player = get_node_or_null(player_path) as Player
	_sprite = get_node_or_null(sprite_path) as AnimatedSprite2D
	_graybox = get_node_or_null(graybox_path) as CanvasItem
	_has_frames = _sprite != null and _sprite.sprite_frames != null \
		and not _sprite.sprite_frames.get_animation_names().is_empty()

	if _sprite != null:
		_sprite.visible = _has_frames
	if _graybox != null:
		_graybox.visible = not _has_frames

	if _player == null:
		push_warning("PlayerVisual: 没找到 Player，表现层不会更新。")
		return
	_player.state_changed.connect(_on_state_changed)
	_player.direction_changed.connect(_on_direction_changed)
	# 进场先对齐一次，别等第一次状态变化才正确。
	_apply_state(_player.get_state())
	_apply_facing(_player.get_facing())


# --- 信号回调 -------------------------------------------------------------------

func _on_state_changed(_previous: Player.State, current: Player.State) -> void:
	_apply_state(current)


func _on_direction_changed(facing: int) -> void:
	_apply_facing(facing)


# --- 表现 ----------------------------------------------------------------------

## 状态 → 动画。DISABLED 刻意不换动画：过场 / 区域切换期间保持原样，
## 免得镜头里的人突然抽一下。
func _apply_state(state: Player.State) -> void:
	if not _has_frames:
		return
	var anim := _animation_for(state)
	if anim == &"" or _sprite.animation == anim:
		return
	if not _sprite.sprite_frames.has_animation(anim):
		push_warning("PlayerVisual: SpriteFrames 里没有动画 '%s'。" % anim)
		return
	_sprite.play(anim)


func _animation_for(state: Player.State) -> StringName:
	match state:
		Player.State.RUN:
			return anim_walk
		Player.State.INTERACT:
			return anim_interact
		Player.State.IDLE:
			return anim_idle
		Player.State.JUMP, Player.State.FALL:
			# 禁跳关卡里正常走不到；踩空的一两帧回落 idle 最安全。
			return anim_idle
		_:
			return &""          # DISABLED：保持当前动画


func _apply_facing(facing: int) -> void:
	if _sprite != null:
		_sprite.flip_h = facing < 0
	# 灰盒模式下也翻一下，方便没素材时肉眼确认朝向判定是对的。
	if _graybox is Node2D:
		(_graybox as Node2D).scale.x = -1.0 if facing < 0 else 1.0
