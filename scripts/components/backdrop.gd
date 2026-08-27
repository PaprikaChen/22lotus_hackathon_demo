@tool
class_name Backdrop
extends Sprite2D
## 关卡背景图：自己算 scale，让贴图正好铺满一屏高，原点钉在世界 (0, 0)。
##
## 为什么不直接在场景里写死 scale：Godot 的贴图导入器会把超大图**按比例缩掉**
## 以适应上限（testbg 的 16366x1080 被压成 10786x712），所以「贴图像素 → 世界
## 像素」的倍率取决于导入结果，不是美术交付的尺寸。写死一个 scale 会在换图或
## 改导入设置时静默错位。这里改成声明**世界高度**，倍率反推出来，
## 长卷有多宽就多宽。
##
## 配合 `FollowCamera2D.bounds_source_path`：那边读 `texture.get_size() * scale`
## 当关卡边界，所以关卡变宽不用手改 world_bounds——但它约定背景
## `centered = false`、原点在左上，本脚本强制保证这一点。

## 贴图要铺满的世界高度。横版关卡 = 视口高度。
@export var world_height: float = 648.0:
	set(value):
		world_height = value
		_apply()


func _enter_tree() -> void:
	# 必须早于 FollowCamera2D._ready() 读边界。同级节点按场景树顺序进树，
	# 背景在相机前面，所以这里够早。
	_apply()


func _ready() -> void:
	_apply()


## 关卡里换了背景图可以手动重算。
func refresh() -> void:
	_apply()


## 背景铺出来的世界矩形。关卡/相机想知道边界用这个，别自己乘 scale。
func get_world_rect() -> Rect2:
	if texture == null:
		return Rect2()
	return Rect2(position, texture.get_size() * scale)


func _apply() -> void:
	# 边界推算和脚线对位都假设原点在左上。
	centered = false
	if texture == null:
		return
	var tex_height := texture.get_size().y
	if tex_height <= 0.0 or world_height <= 0.0:
		return
	var factor := world_height / tex_height
	scale = Vector2(factor, factor)
