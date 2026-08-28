class_name FloatingVisual
extends Node2D
## 纯表现层的上下漂浮组件：只偏移自身位置，不参与交互、碰撞或剧情状态。

@export_range(0.0, 32.0, 0.1, "suffix:px") var amplitude: float = 4.0
@export_range(0.1, 20.0, 0.1, "suffix:s") var cycle_seconds: float = 2.8
## 以弧度设置初始相位；PI 从原位先向上，0 从原位先向下。
@export var phase: float = 0.0

var _base_position: Vector2
var _elapsed: float = 0.0


func _ready() -> void:
	_base_position = position


func _process(delta: float) -> void:
	_elapsed += delta
	var angular_speed: float = TAU / maxf(cycle_seconds, 0.1)
	position = _base_position + Vector2(0.0, sin(_elapsed * angular_speed + phase) * amplitude)
