class_name EyeFollowVisual
extends Node2D
## 纯表现层的眼神跟随组件。
##
## 让挂在本节点下的眼睛图层朝目标方向小幅偏移；只改变自身位置，不处理交互、
## 碰撞或剧情。固定视线原点由独立 Marker2D 提供，避免整幅透明定位图的左上角
## 被误当成眼睛中心。

@export var player_path: NodePath
@export var eye_origin_path: NodePath
@export_range(0.0, 32.0, 0.1, "suffix:px") var max_offset: float = 10.0
## 玩家距离视线原点达到该值时，眼睛偏移到最大范围。
@export_range(1.0, 4000.0, 1.0, "suffix:px") var full_offset_distance: float = 600.0
@export_range(0.0, 30.0, 0.1) var response_speed: float = 10.0

var _player: Node2D = null
var _eye_origin: Node2D = null
var _base_position: Vector2


func _ready() -> void:
	_base_position = position
	_player = get_node_or_null(player_path) as Node2D
	_eye_origin = get_node_or_null(eye_origin_path) as Node2D
	if _player == null or _eye_origin == null:
		push_warning("EyeFollowVisual: 没接上 player 或 eye_origin，眼神不会跟随。")
		set_process(false)


func _process(delta: float) -> void:
	var toward_player: Vector2 = _player.global_position - _eye_origin.global_position
	var distance: float = toward_player.length()
	var target_offset := Vector2.ZERO
	if distance > 0.001:
		var strength: float = clampf(distance / maxf(full_offset_distance, 1.0), 0.0, 1.0)
		target_offset = toward_player / distance * max_offset * strength
	var target_position: Vector2 = _base_position + target_offset
	if response_speed <= 0.0:
		position = target_position
		return
	var weight: float = 1.0 - exp(-response_speed * delta)
	position = position.lerp(target_position, weight)
