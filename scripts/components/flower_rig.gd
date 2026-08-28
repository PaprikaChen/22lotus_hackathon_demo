class_name FlowerRig
extends Node2D
## Lightweight decorative animation for a small Skeleton2D flower rig.
## It only moves its authored Bone2D branches; it has no collision, gameplay,
## or interaction responsibilities.

@export var bone_paths: Array[NodePath] = []
@export_range(0.0, 8.0, 0.1, "suffix:deg") var sway_degrees: float = 2.4
@export_range(0.1, 4.0, 0.05, "suffix:s") var sway_speed: float = 1.15
@export_range(0.0, 20.0, 0.1, "suffix:px") var float_amplitude: float = 6.0

var _bones: Array[Bone2D] = []
var _base_positions: Array[Vector2] = []
var _base_rotations: Array[float] = []
var _time: float = 0.0


func _ready() -> void:
	for path in bone_paths:
		var bone := get_node_or_null(path) as Bone2D
		if bone == null:
			push_warning("FlowerRig: missing Bone2D at '%s'." % path)
			continue
		_bones.append(bone)
		_base_positions.append(bone.position)
		_base_rotations.append(bone.rotation)


func _process(delta: float) -> void:
	_time += delta
	for index in _bones.size():
		var phase := float(index) * 1.713
		var sway := sin(_time * sway_speed * (0.83 + index * 0.09) + phase)
		var drift := sin(_time * sway_speed * 0.57 + phase * 1.91)
		var bone := _bones[index]
		bone.rotation = _base_rotations[index] + deg_to_rad(sway_degrees) * (sway + drift * 0.32)
		bone.position = _base_positions[index] + Vector2(drift * float_amplitude * 0.22, sway * float_amplitude)
