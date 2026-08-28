class_name RotaryLockRing
extends Node2D
## 三重旋锁里**一层**可旋转的圈。三层共用这一个脚本，只靠导出属性区分
## 命中形状和占位画法。
##
## 职责边界：只管“这一层怎么转”——鼠标角度、22.5° 机械档位、半档回弹、
## 吸附插值，以及每跨一档发一次 `detent_stepped`。
## **不判断谜底、不播音效、不碰门和玩家**，那些归 `RotaryLockUI` 和 Director。
##
## 角度全部用「相对锁心的极角」计算，不看水平位移；相邻两次鼠标事件之间用
## `angle_difference()` 求增量，所以 179° → -179° 不会跳变。
##
## 换正式美术：给 `visual_texture` 挂一张图（图心 = 锁心），几何占位自动让位，
## **旋转逻辑一行不用改**。占位几何只在 `_draw()` 里。
##
## 命中区域用 `contains_point()` 对外提供，由 `RotaryLockUI` 按
## 内 → 中 → 外的顺序询问，所以外层的四个花瓣不会盖住中层和内层。

signal detent_stepped(direction: int) ## +1 顺时针 / -1 逆时针，每跨一档一次
signal settled ## 吸附 / 回弹结束

## 命中形状。占位画法也跟着它走。
enum Shape {
	DISC,   ## 实心圆（内层瓶身）
	RING,   ## 圆环（中层）
	PETALS, ## 四叶草：上下左右四个圆瓣（外层）
}

@export var layer_id: StringName = &""
@export var shape: Shape = Shape.RING

@export_group("Geometry")
## DISC：半径。RING：内半径。PETALS：中心禁区半径（小于它交给内层）。
@export var inner_radius: float = 62.0
## RING 的外半径；PETALS 时无意义。
@export var outer_radius: float = 132.0
## 花瓣圆心到锁心的距离（PETALS）。
@export var petal_distance: float = 186.0
## 花瓣半径（PETALS）。
@export var petal_radius: float = 74.0

@export_group("Placeholder Art")
## 挂上正式图层素材后，下面的几何占位自动不画。图心必须是锁心。
@export var visual_texture: Texture2D = null
@export var line_color: Color = Color(0.86, 0.83, 0.74, 1.0)
@export var fill_color: Color = Color(0.16, 0.15, 0.18, 0.92)
@export var line_width: float = 3.0

## 已锁定的档位下标（可正可负，×22.5° = 角度）。
var _detent_index: int = 0
## 拖拽中：上一次鼠标极角（度）。
var _last_drag_angle: float = 0.0
## 拖拽中：本次拖拽累计转过的角度（度，已解缠，可超过 ±360）。
var _drag_total: float = 0.0
## 拖拽中：本次拖拽已经完成的整档数（带符号）。
var _drag_detents: int = 0
var _is_dragging: bool = false
var _is_locked: bool = false
var _tween: Tween = null


func _ready() -> void:
	rotation_degrees = _detent_index * InnerGateLockConfig.DETENT_DEGREES


# --- 对外状态 -----------------------------------------------------------------

func get_detent_index() -> int:
	return _detent_index


func is_dragging() -> bool:
	return _is_dragging


func is_settling() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


## 解锁成功后禁止继续拖动。
func set_input_locked(value: bool) -> void:
	_is_locked = value
	if value:
		cancel_drag()


## 点在这一层的命中区域内吗？point 是**全局**坐标（含本层自身旋转）。
func contains_point(point: Vector2) -> bool:
	var local := to_local(point)
	var r := local.length()
	match shape:
		Shape.DISC:
			return r <= inner_radius
		Shape.RING:
			return r > inner_radius and r <= outer_radius
		Shape.PETALS:
			if r <= inner_radius:
				return false
			for dir in _petal_directions():
				if local.distance_to(dir * petal_distance) <= petal_radius:
					return true
			return false
	return false


# --- 拖拽（由 RotaryLockUI 驱动）-----------------------------------------------

## point 为全局坐标；返回是否真的接管了这次拖拽。
func begin_drag(point: Vector2) -> bool:
	if _is_locked or _is_dragging or is_settling():
		return false
	_is_dragging = true
	_last_drag_angle = _angle_to(point)
	_drag_total = 0.0
	_drag_detents = 0
	return true


func update_drag(point: Vector2) -> void:
	if not _is_dragging:
		return
	var angle := _angle_to(point)
	# 增量用 angle_difference 求：跨 ±180° 时不会突然跳一圈。
	# 鼠标拖出图形外也照常累计，直到松手（拖拽由 UI 层全局捕获）。
	_drag_total += rad_to_deg(angle_difference(deg_to_rad(_last_drag_angle), deg_to_rad(angle)))
	_last_drag_angle = angle
	_follow_drag()
	_emit_completed_detents()


## 松手。返回本次拖拽最终落在哪个档位。
func end_drag() -> int:
	if not _is_dragging:
		return _detent_index
	_is_dragging = false
	var detent := InnerGateLockConfig.DETENT_DEGREES
	var partial := _drag_total - _drag_detents * detent
	var target := _detent_index + _drag_detents
	if absf(partial) >= InnerGateLockConfig.HALF_DETENT_DEGREES:
		# 达到半档：补成完整一档，并且**计入**输入序列。
		var direction := int(signf(partial))
		target += direction
		_detent_index = target
		_settle_to(target, InnerGateLockConfig.SNAP_SECONDS)
		detent_stepped.emit(direction)
	else:
		# 不足半档：回弹到之前的档位，这段未完成的旋转不计数。
		_detent_index = target
		_settle_to(target, InnerGateLockConfig.RECOIL_SECONDS)
	_drag_total = 0.0
	_drag_detents = 0
	return _detent_index


## UI 关闭 / 失焦 / 输入取消：安全结束拖拽，未完成的一段一律回弹、不计数。
func cancel_drag() -> void:
	if not _is_dragging:
		return
	_is_dragging = false
	_detent_index += _drag_detents
	_drag_total = 0.0
	_drag_detents = 0
	_settle_to(_detent_index, InnerGateLockConfig.RECOIL_SECONDS)


## 静默摆终态（读档 / 调试 / 成功演出对齐用），不发信号、不计数。
func set_detent_index(index: int, animate: bool = false) -> void:
	cancel_drag()
	_detent_index = index
	if animate:
		_settle_to(index, InnerGateLockConfig.SUCCESS_SECONDS)
	else:
		_kill_tween()
		rotation_degrees = index * InnerGateLockConfig.DETENT_DEGREES


# --- 内部 ---------------------------------------------------------------------

## 极角相对**锁心**（父节点）算，不用 to_local()：那会把本层自身的旋转
## 也算进去，拖着转的时候角度会自我追逐。
func _angle_to(point: Vector2) -> float:
	var center := global_position
	var parent_node := get_parent() as Node2D
	if parent_node != null:
		center = parent_node.global_position
	return rad_to_deg((point - center).angle())


func _follow_drag() -> void:
	_kill_tween()
	rotation_degrees = _detent_index * InnerGateLockConfig.DETENT_DEGREES + _drag_total


## 逐档计数：向零截断保证「跨过一个完整档位」才算一档，
## 快速拖过多档时按差值逐档补发，绝不漏计；反向拖回同样逐档发反向档。
func _emit_completed_detents() -> void:
	var detent := InnerGateLockConfig.DETENT_DEGREES
	var completed := int(_drag_total / detent) # 向零截断
	if completed == _drag_detents:
		return
	var step := 1 if completed > _drag_detents else -1
	while _drag_detents != completed:
		_drag_detents += step
		detent_stepped.emit(step)


func _settle_to(index: int, duration: float) -> void:
	_kill_tween()
	var target := index * InnerGateLockConfig.DETENT_DEGREES
	if duration <= 0.0:
		rotation_degrees = target
		settled.emit()
		return
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(self, "rotation_degrees", target, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(settled.emit)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _exit_tree() -> void:
	_kill_tween()


# --- 占位视觉（换正式素材时只动这一段）---------------------------------------

func _petal_directions() -> Array[Vector2]:
	return [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]


func _draw() -> void:
	if visual_texture != null:
		draw_texture(visual_texture, -visual_texture.get_size() * 0.5)
		return
	match shape:
		Shape.DISC:
			_draw_vase()
		Shape.RING:
			_draw_ring()
		Shape.PETALS:
			_draw_petals()
	# 一道细刻线，让“这一层转到哪了”看得出来。
	draw_line(Vector2.ZERO, Vector2.UP * _notch_length(), line_color, line_width)


func _notch_length() -> float:
	match shape:
		Shape.DISC:
			return inner_radius * 0.8
		Shape.RING:
			return outer_radius
		_:
			return petal_distance + petal_radius


func _draw_ring() -> void:
	draw_arc(Vector2.ZERO, (inner_radius + outer_radius) * 0.5, 0.0, TAU, 96,
		fill_color, outer_radius - inner_radius, false)
	draw_arc(Vector2.ZERO, inner_radius, 0.0, TAU, 96, line_color, line_width, true)
	draw_arc(Vector2.ZERO, outer_radius, 0.0, TAU, 96, line_color, line_width, true)
	# 16 道档位刻度，正好一圈的档数。
	var steps := int(round(360.0 / InnerGateLockConfig.DETENT_DEGREES))
	for i in steps:
		var dir := Vector2.RIGHT.rotated(deg_to_rad(i * InnerGateLockConfig.DETENT_DEGREES))
		draw_line(dir * inner_radius, dir * (inner_radius + 14.0), line_color, 1.5)


func _draw_petals() -> void:
	for dir in _petal_directions():
		var c: Vector2 = dir * petal_distance
		draw_circle(c, petal_radius, fill_color)
		draw_arc(c, petal_radius, 0.0, TAU, 64, line_color, line_width, true)


## 内层瓷瓶：一个粗糙的对称瓶形轮廓，能看出“瓶”就够了。
func _draw_vase() -> void:
	var half := [
		Vector2(0.10, -1.00), Vector2(0.26, -0.86), Vector2(0.20, -0.66),
		Vector2(0.46, -0.40), Vector2(0.62, -0.02), Vector2(0.52, 0.52),
		Vector2(0.30, 0.86), Vector2(0.34, 1.00),
	]
	var points := PackedVector2Array()
	for p in half:
		points.append(p * inner_radius)
	for i in range(half.size() - 1, -1, -1):
		var p: Vector2 = half[i]
		points.append(Vector2(-p.x, p.y) * inner_radius)
	draw_colored_polygon(points, fill_color)
	var outline := PackedVector2Array(points)
	outline.append(points[0])
	draw_polyline(outline, line_color, line_width)
