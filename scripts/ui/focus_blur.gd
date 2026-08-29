class_name FocusBlur
extends CanvasLayer
## 全屏短暂失焦表现。只负责模糊画面；是否锁玩家、何时播放由 StoryDirector 编排。

signal pulse_finished

@export_range(0.0, 12.0, 0.1, "suffix:px") var peak_blur_radius: float = 7.0
@export_range(0.0, 2.0, 0.01, "suffix:s") var blur_in_duration: float = 0.16
@export_range(0.0, 2.0, 0.01, "suffix:s") var hold_duration: float = 0.12
@export_range(0.0, 2.0, 0.01, "suffix:s") var blur_out_duration: float = 0.34

@onready var _rect: ColorRect = $BlurRect

var _tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect.visible = false
	_set_blur_radius(0.0)


func pulse() -> void:
	_kill_tween()
	_rect.visible = true
	_set_blur_radius(0.0)
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_method(_set_blur_radius, 0.0, peak_blur_radius, blur_in_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(hold_duration)
	_tween.tween_method(_set_blur_radius, peak_blur_radius, 0.0, blur_out_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await _tween.finished
	_tween = null
	_rect.visible = false
	pulse_finished.emit()


func reset() -> void:
	_kill_tween()
	_set_blur_radius(0.0)
	_rect.visible = false


func _set_blur_radius(value: float) -> void:
	var shader_material := _rect.material as ShaderMaterial
	if shader_material != null:
		shader_material.set_shader_parameter(&"blur_radius", value)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _exit_tree() -> void:
	_kill_tween()
