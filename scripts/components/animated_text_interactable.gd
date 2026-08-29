class_name AnimatedTextInteractable
extends "res://scripts/components/text_interactable.gd"
## 纯调查物的局部表现：保留 TextInteractable 的文本职责，只在交互时播放可选摇摆
## 或显示一张附属图片。它不写剧情 Flag、不管理玩家输入锁。

@export_group("Presentation")
## 要围绕自身原点摇摆的 Node2D（例如木马的图层支点）。留空则不摇摆。
@export var animated_visual_path: NodePath
@export_range(0.0, 30.0, 0.1, "suffix:deg") var sway_degrees: float = 8.0
@export_range(0.0, 3.0, 0.05, "suffix:s") var sway_duration: float = 0.6
## 交互后显示的附属视觉（例如纸条）。留空则不显示。
@export var reveal_visual_path: NodePath
@export_range(0.0, 3.0, 0.05, "suffix:s") var reveal_duration: float = 0.22
## 摇摆时播放的音效（例如木马吱呀）。指向场景里的 AudioStreamPlayer；
## 留空或没挂 stream 时静默跳过，和 `passage_gate.gd` 的占位约定一致。
## 只跟着摇摆走——`sway_degrees` / `sway_duration` 为 0 的纯文本调查点不会响。
@export var sway_sound_path: NodePath

var _sway_tween: Tween
var _reveal_tween: Tween


func _on_interact(player: Node) -> void:
	_play_sway()
	_reveal_visual()
	super._on_interact(player)


func _play_sway() -> void:
	var visual := get_node_or_null(animated_visual_path) as Node2D
	if visual == null or sway_degrees <= 0.0 or sway_duration <= 0.0:
		return
	if _sway_tween != null and _sway_tween.is_valid():
		_sway_tween.kill()
	_play_sway_sound()
	var base_rotation: float = 0.0
	visual.rotation = base_rotation
	var sway: float = deg_to_rad(sway_degrees)
	var beat: float = sway_duration * 0.25
	_sway_tween = create_tween()
	_sway_tween.tween_property(visual, "rotation", base_rotation + sway, beat).set_trans(Tween.TRANS_SINE)
	_sway_tween.tween_property(visual, "rotation", base_rotation - sway * 0.6, beat).set_trans(Tween.TRANS_SINE)
	_sway_tween.tween_property(visual, "rotation", base_rotation + sway * 0.28, beat).set_trans(Tween.TRANS_SINE)
	_sway_tween.tween_property(visual, "rotation", base_rotation, beat).set_trans(Tween.TRANS_SINE)


func _reveal_visual() -> void:
	var visual := get_node_or_null(reveal_visual_path) as CanvasItem
	if visual == null:
		return
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()
	visual.visible = true
	visual.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_reveal_tween = create_tween()
	_reveal_tween.tween_property(visual, "modulate", Color.WHITE, reveal_duration)


func _play_sway_sound() -> void:
	var sound := get_node_or_null(sway_sound_path) as AudioStreamPlayer
	if sound != null and sound.stream != null:
		sound.play()
