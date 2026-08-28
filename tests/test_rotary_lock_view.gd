extends Node2D
## 三重旋锁的**肉眼检查**房：开局就把锁界面打开，用来看占位几何的层次、
## 居中和大小（断言判断不了这些）。逻辑回归在 tests/test_courtyard_01.gd。
##
##   Godot --path D:/22lotus --resolution 1616x1008 \
##       res://tests/helpers/capture_scene.tscn \
##       -- --scene=res://tests/test_rotary_lock_view.tscn --out=user://lock.png

const LOCK_SCENE := "res://scenes/ui/rotary_lock.tscn"


func _ready() -> void:
	var lock := (load(LOCK_SCENE) as PackedScene).instantiate() as RotaryLockUI
	add_child(lock)
	# 摆几个不同角度，方便看清三层是各自独立旋转的。
	lock.open()
	lock.get_ring(InnerGateLockConfig.LAYER_OUTER).set_detent_index(1)
	lock.get_ring(InnerGateLockConfig.LAYER_MIDDLE).set_detent_index(-2)
	lock.get_ring(InnerGateLockConfig.LAYER_INNER).set_detent_index(3)
