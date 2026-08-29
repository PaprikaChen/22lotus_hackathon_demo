class_name ShadowPuppetActor
extends Node2D
## 皮影 Player 的纯表现组件：贴图脚点对齐、朝向翻转、行走摆动与停步复位。
##
## 不读取输入、不推动 Player、不负责换幕。移动状态只来自 Player 的 velocity，
## 因而不会把这套演出逻辑耦合进公共 Player 控制器。

@export var player_path: NodePath = ^".."
@export var sprite_path: NodePath = ^"Sprite"
@export var bob_height: float = 7.0
@export var sway_degrees: float = 2.8
@export var motion_frequency: float = 2.2
@export var settle_speed: float = 10.0

var _player: Player = null
var _sprite: Sprite2D = null
var _phase: float = 0.0


func _ready() -> void:
	_player = get_node_or_null(player_path) as Player
	_sprite = get_node_or_null(sprite_path) as Sprite2D
	if _player == null or _sprite == null:
		push_warning("ShadowPuppetActor: Player 或 Sprite 路径无效。")
		set_process(false)
		return
	_player.direction_changed.connect(_on_direction_changed)
	_on_direction_changed(_player.get_facing())


func _process(delta: float) -> void:
	if _player == null:
		return
	var moving: bool = not _player.is_input_locked() and absf(_player.velocity.x) > 5.0
	if moving:
		_phase += delta * TAU * motion_frequency
		var target_y: float = sin(_phase * 2.0) * bob_height
		var target_rotation: float = sin(_phase) * deg_to_rad(sway_degrees)
		position.y = lerpf(position.y, target_y, minf(1.0, settle_speed * delta))
		rotation = lerpf(rotation, target_rotation, minf(1.0, settle_speed * delta))
	else:
		_phase = 0.0
		position.y = lerpf(position.y, 0.0, minf(1.0, settle_speed * delta))
		rotation = lerpf(rotation, 0.0, minf(1.0, settle_speed * delta))


func set_art(texture: Texture2D, foot_anchor: Vector2, art_scale: float) -> void:
	if _sprite == null:
		return
	_sprite.texture = texture
	_sprite.centered = false
	_sprite.scale = Vector2.ONE * art_scale
	_sprite.position = -foot_anchor * art_scale
	visible = texture != null
	position.y = 0.0
	rotation = 0.0


func clear_art() -> void:
	if _sprite != null:
		_sprite.texture = null
	visible = false
	_phase = 0.0
	position.y = 0.0
	rotation = 0.0


func get_texture_path() -> String:
	if _sprite == null or _sprite.texture == null:
		return ""
	return _sprite.texture.resource_path


func _on_direction_changed(facing: int) -> void:
	# 整个 Pivot 围绕脚点翻转，素材锚点不会因 flip_h 横向漂移。
	scale.x = -1.0 if facing < 0 else 1.0
