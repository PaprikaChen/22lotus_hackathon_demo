class_name ShadowPlayFinale
extends CanvasLayer
## Interior_02 终幕字幕与制作人员名单的纯表现组件。
##
## 调用方只需 `play()`；本组件不读取输入、不操作 Player、不切换关卡。

signal finished

@export var title_path: NodePath
@export var credit_path: NodePath
@export var thanks_path: NodePath
@export var title_text: String = "第二章：庭院深深"
@export var credits: PackedStringArray = PackedStringArray([
	"制作人/程序：Paprika",
	"美术/策划：吉姞子之",
	"音乐/策划：Echo",
])
@export var thanks_text: String = "谢谢体验！"

@export_group("Timing")
@export_range(0.0, 10.0, 0.1) var title_hold_duration: float = 5.0
@export_range(0.0, 10.0, 0.1) var credit_hold_duration: float = 4.0
@export_range(0.0, 2.0, 0.05) var text_fade_duration: float = 0.55

var _title: Label = null
var _credit: Label = null
var _thanks: Label = null
var _tween: Tween = null
var _running: bool = false
var _complete: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_title = get_node_or_null(title_path) as Label
	_credit = get_node_or_null(credit_path) as Label
	_thanks = get_node_or_null(thanks_path) as Label
	_reset_labels()


func play() -> void:
	if _running or _complete:
		return
	if _title == null or _credit == null or _thanks == null:
		push_error("ShadowPlayFinale: 标题/名单/致谢 Label 路径未配置完整。")
		return
	_running = true
	_title.text = title_text
	await _show_hold_hide(_title, title_hold_duration)
	for credit_text: String in credits:
		_credit.text = credit_text
		await _show_hold_hide(_credit, credit_hold_duration)
	_thanks.text = thanks_text
	_thanks.visible = true
	_thanks.modulate.a = 0.0
	await _fade_to(_thanks, 1.0)
	_running = false
	_complete = true
	finished.emit()


func is_running() -> bool:
	return _running


func is_complete() -> bool:
	return _complete


func get_visible_text() -> String:
	for label: Label in [_title, _credit, _thanks]:
		if label != null and label.visible:
			return label.text
	return ""


func _show_hold_hide(label: Label, hold_duration: float) -> void:
	label.visible = true
	label.modulate.a = 0.0
	await _fade_to(label, 1.0)
	await _wait(hold_duration)
	await _fade_to(label, 0.0)
	label.visible = false


func _fade_to(label: Label, alpha: float) -> void:
	_kill_tween()
	if text_fade_duration <= 0.0:
		label.modulate.a = alpha
		await get_tree().process_frame
		return
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(label, ^"modulate:a", alpha, text_fade_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _tween.finished
	_tween = null


func _wait(duration: float) -> void:
	if duration <= 0.0:
		await get_tree().process_frame
		return
	await get_tree().create_timer(duration, true).timeout


func _reset_labels() -> void:
	for label: Label in [_title, _credit, _thanks]:
		if label != null:
			label.visible = false
			label.modulate.a = 0.0


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _exit_tree() -> void:
	_kill_tween()
