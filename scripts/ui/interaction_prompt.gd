class_name InteractionPrompt
extends Control
## Screen-space presentation for the player's currently selected Interactable.
## It only listens to InteractionDetector; target selection and the E-key
## interaction flow remain owned by the existing detector/component pair.

@export var player_path: NodePath
@export var eye_pulse_speed: float = 2.4

@onready var _eye: TextureRect = $Eye

var _detector: InteractionDetector = null
var _target: Interactable = null
var _pulse_time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var player := get_node_or_null(player_path)
	if player != null:
		_detector = player.get_node_or_null("InteractionDetector") as InteractionDetector
	if _detector != null:
		_detector.target_changed.connect(_on_target_changed)
		_on_target_changed(_detector.get_current_target())


func _process(delta: float) -> void:
	if not is_instance_valid(_target):
		visible = false
		return
	visible = true
	# EyeAnchor is a visible Marker2D child artists can directly move in the
	# editor. Older/future props without one safely fall back to their origin.
	var anchor := _target.get_node_or_null("EyeAnchor") as Marker2D
	var canvas_position := anchor.get_global_transform_with_canvas().origin if anchor != null else _target.get_global_transform_with_canvas().origin
	_eye.position = canvas_position - Vector2(22.0, 22.0)
	_pulse_time += delta * eye_pulse_speed
	_eye.modulate = Color(1.0, 0.92, 1.0, 0.72 + sin(_pulse_time) * 0.28)


func _on_target_changed(target: Interactable) -> void:
	_target = target
	visible = _target != null
