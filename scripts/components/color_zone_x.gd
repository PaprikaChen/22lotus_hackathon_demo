class_name ColorZoneX
extends Node
## 按目标节点的世界 X 坐标切换其饱和度 / 亮度：区间内保持原色，区间外去色变暗。
##
## 为什么放在关卡侧而不是玩家侧：这是本关的美术表现规则，玩家不该知道
## 「屋里哪一段是彩色的」。组件只写 ShaderMaterial 的 uniform，
## 不碰移动、碰撞或动画。
##
## target_paths 里的每个节点都会被套上**各自**的 ShaderMaterial 实例
## （共用一份会让 uniform 互相覆盖）。

const SHADER: Shader = preload("res://shaders/effects/saturation_tint.gdshader")

## 观察世界 X 坐标的节点（通常是玩家本体）。
@export var subject_path: NodePath
## 实际要改颜色的 CanvasItem（玩家的 Sprite、灰盒等）。
@export var target_paths: Array[NodePath] = []

@export_group("Zone")
## 彩色区间（含端点）的左右边界，世界坐标。
@export var color_min_x: float = 1000.0
@export var color_max_x: float = 1500.0

@export_group("Outside Look")
## 区间外的饱和度。0 = 纯黑白。
@export_range(0.0, 1.0) var outside_saturation: float = 0.0
## 区间外的亮度。略低于 1 即「暗一点」。
@export_range(0.0, 1.0) var outside_brightness: float = 0.9
## 过渡速度（每秒插值比例）。设 0 = 硬切。
@export var blend_speed: float = 8.0

var _subject: Node2D = null
var _materials: Array[ShaderMaterial] = []
var _saturation: float = 1.0
var _brightness: float = 1.0


func _ready() -> void:
	_subject = get_node_or_null(subject_path) as Node2D
	if _subject == null:
		push_warning("ColorZoneX: 没找到 subject，颜色分区不会生效。")
		set_process(false)
		return
	for path in target_paths:
		var item := get_node_or_null(path) as CanvasItem
		if item == null:
			push_warning("ColorZoneX: target 不是 CanvasItem: %s" % path)
			continue
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		item.material = mat
		_materials.append(mat)
	if _materials.is_empty():
		set_process(false)
		return
	# 进场先落到正确的值，别在第一帧闪一下原色。
	var target := _target_values()
	_saturation = target.x
	_brightness = target.y
	_push_uniforms()


func _process(delta: float) -> void:
	var target := _target_values()
	if blend_speed <= 0.0:
		_saturation = target.x
		_brightness = target.y
	else:
		var t := clampf(delta * blend_speed, 0.0, 1.0)
		_saturation = lerpf(_saturation, target.x, t)
		_brightness = lerpf(_brightness, target.y, t)
	_push_uniforms()


func _target_values() -> Vector2:
	var x := _subject.global_position.x
	if x >= color_min_x and x <= color_max_x:
		return Vector2(1.0, 1.0)
	return Vector2(outside_saturation, outside_brightness)


func _push_uniforms() -> void:
	for mat in _materials:
		mat.set_shader_parameter(&"saturation", _saturation)
		mat.set_shader_parameter(&"brightness", _brightness)
