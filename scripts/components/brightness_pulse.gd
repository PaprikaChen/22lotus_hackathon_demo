class_name BrightnessPulse
extends Node
## 纯表现层的非匀速亮度脉冲组件。
##
## 只调制指定 CanvasItem 的亮度，不处理位移、交互或剧情。主、副两组不同周期
## 的正弦波叠加后再做平滑，避免机械的线性明暗切换；不同实例通过周期与相位
## 配置自然错开。

@export var target_path: NodePath
@export_range(0.0, 1.0, 0.01) var minimum_brightness: float = 0.68
@export_range(0.0, 1.0, 0.01) var maximum_brightness: float = 1.0
@export_range(0.1, 20.0, 0.1, "suffix:s") var primary_period: float = 3.4
@export_range(0.1, 20.0, 0.1, "suffix:s") var secondary_period: float = 1.7
@export var primary_phase: float = 0.0
@export var secondary_phase: float = 1.4

var _target: CanvasItem = null
var _elapsed: float = 0.0


func _ready() -> void:
	_target = get_node_or_null(target_path) as CanvasItem
	if _target == null:
		push_warning("BrightnessPulse: 没接上 target，亮度动画不会播放。")
		set_process(false)


func _process(delta: float) -> void:
	_elapsed += delta
	var primary: float = sin(TAU * _elapsed / maxf(primary_period, 0.1) + primary_phase)
	var secondary: float = sin(TAU * _elapsed / maxf(secondary_period, 0.1) + secondary_phase)
	var mixed: float = clampf(0.5 + primary * 0.34 + secondary * 0.16, 0.0, 1.0)
	var eased: float = smoothstep(0.0, 1.0, mixed)
	var low: float = minf(minimum_brightness, maximum_brightness)
	var high: float = maxf(minimum_brightness, maximum_brightness)
	var brightness: float = lerpf(low, high, eased)
	_target.self_modulate = Color(brightness, brightness, brightness, 1.0)
