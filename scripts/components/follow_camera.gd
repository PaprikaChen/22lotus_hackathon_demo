class_name FollowCamera2D
extends Camera2D
## 横版关卡相机：横向跟人、纵向锁死；走到场景左右边缘时**画面停住、人物继续走**。
##
## 后半句由 Camera2D 内建的 `limit_left/right/top/bottom` 完成，本脚本**不写
## 任何 clamp**。limit 钳制的是相机的渲染中心：相机节点位置可以继续跟着人走，
## 但画面到边界就停，人物于是自然地偏离屏幕中心走向边缘。
##
## 要读「画面实际中心」用 `get_screen_center_position()`，
## **不要**读 `position`——limit 生效时两者不同。
##
## 硬约束：场景宽度必须 ≥ 视口宽度，否则左右 limit 互相冲突，画面会抖。
## `_ready()` 会检查并 push_warning。

@export var target_path: NodePath

@export_group("Bounds")
## 世界可见范围（世界坐标）。size 为 0 时改从 bounds_source_path 推算。
@export var world_bounds: Rect2 = Rect2()
## 背景 Sprite2D：用它的贴图尺寸 × scale 当边界。world_bounds 留空时才读它。
@export var bounds_source_path: NodePath

@export_group("Follow")
## 横版关卡通常锁死纵向，避免走坡时画面上下晃。
@export var follow_y: bool = false
## follow_y 为 false 时相机固定的 y。
@export var fixed_y: float = 324.0
## 0 = 硬跟随。轻微平滑（0.08~0.15）走动更舒服，但贴边会多半帧才停。
@export var smoothing_seconds: float = 0.0

var _target: Node2D = null


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node2D
	if _target == null:
		push_warning("FollowCamera2D: 没接上 target，相机不会跟随。")
	_apply_bounds(_resolve_bounds())
	_apply_smoothing()
	make_current()


func _process(_delta: float) -> void:
	if _target == null:
		return
	# 只管把相机放到人身上；越界由 limit_* 负责，这里不 clamp。
	position.x = _target.global_position.x
	position.y = _target.global_position.y if follow_y else fixed_y


# --- 边界 ----------------------------------------------------------------------

## 关卡改了背景尺寸后可以手动重算，不必重进关卡。
func refresh_bounds() -> void:
	_apply_bounds(_resolve_bounds())


func get_bounds() -> Rect2:
	return Rect2(
		Vector2(float(limit_left), float(limit_top)),
		Vector2(float(limit_right - limit_left), float(limit_bottom - limit_top)))


func _resolve_bounds() -> Rect2:
	if world_bounds.size.x > 0.0 and world_bounds.size.y > 0.0:
		return world_bounds
	var source := get_node_or_null(bounds_source_path) as Sprite2D
	if source != null and source.texture != null:
		var size := source.texture.get_size() * source.scale
		# 约定：背景 Sprite2D 用 centered = false，原点在左上。
		var origin := source.global_position
		if source.centered:
			origin -= size * 0.5
		return Rect2(origin, size)
	push_warning("FollowCamera2D: 既没有 world_bounds 也没有可用的背景 Sprite2D，limit 保持场景里的值。")
	return Rect2()


func _apply_bounds(bounds: Rect2) -> void:
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	limit_left = int(bounds.position.x)
	limit_top = int(bounds.position.y)
	limit_right = int(bounds.position.x + bounds.size.x)
	limit_bottom = int(bounds.position.y + bounds.size.y)
	var view := get_viewport_rect().size / zoom
	if bounds.size.x < view.x:
		push_warning(
			"FollowCamera2D: 场景宽 %d < 视口宽 %d，左右 limit 会冲突导致画面抖动。"
			% [int(bounds.size.x), int(view.x)])


func _apply_smoothing() -> void:
	position_smoothing_enabled = smoothing_seconds > 0.0
	if position_smoothing_enabled:
		position_smoothing_speed = 1.0 / smoothing_seconds
