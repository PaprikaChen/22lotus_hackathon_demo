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

## 闸门滑动结束时发。等它滑完再解锁玩家输入的地方接这个。
signal left_gate_opened

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

@export_group("Gate")
## ≥ 0 时开局把左边界额外收窄到这个世界 x：画面最左侧就停在这里，
## 左边的场景先看不见。被 `release_left_gate()` 放开后回到真实场景边界。
##
## 为什么不直接改 limit_left：`_apply_bounds()` 会按背景尺寸重算 limit，
## 手改的值会被下一次 refresh_bounds() 冲掉。闸门是独立的一层，
## 每次算完边界都会重新叠上去。
@export var left_gate_x: int = -1: set = set_left_gate
## ≥ 0 时把右边界额外收窄到这个世界 x：画面最右侧就停在这里，右边的场景先
## 看不见。剧情放行后调 `release_right_gate()` 回到真实场景边界。
##
## 注意闸门只管**画面**。要让人物也走不过去，得在关卡里另外摆一堵墙——
## 相机不负责挡人（AGENTS.md：相机不做碰撞）。
@export var right_gate_x: int = -1: set = set_right_gate

var _target: Node2D = null
## 背景算出来的真实左右边界，闸门放开后要回到这些值。
var _bounds_limit_left: int = 0
var _bounds_limit_right: int = 0
## 待落的左闸门位置（见 `arm_left_gate_latch()`）。-1 = 没有。
var _left_gate_latch_x: int = -1


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
	_update_left_gate_latch()


# --- 边界 ----------------------------------------------------------------------

## 关卡改了背景尺寸后可以手动重算，不必重进关卡。
func refresh_bounds() -> void:
	_apply_bounds(_resolve_bounds())


func get_bounds() -> Rect2:
	return Rect2(
		Vector2(float(limit_left), float(limit_top)),
		Vector2(float(limit_right - limit_left), float(limit_bottom - limit_top)))


## 平滑放开左侧闸门：画面缓缓往左滑到真实边界，而不是一帧跳过去。
## 幂等——闸门本来就是开的时候立刻发信号返回。
##
## 滑的是 limit_left 而不是相机位置：相机每帧都被钉在玩家身上，
## 动它会被下一帧覆盖；边界往外让，画面就自己跟着让出来。
func slide_left_gate_open(duration: float = 1.2) -> void:
	if not is_left_gate_closed():
		left_gate_opened.emit()
		return
	var tween := create_tween()
	tween.tween_method(set_left_gate, left_gate_x, _bounds_limit_left, duration) 		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(release_left_gate)
	tween.tween_callback(left_gate_opened.emit)


## 放开左侧闸门（例：拔掉挡路的杂草之后）。幂等，读档恢复也调它。
func release_left_gate() -> void:
	set_left_gate(-1)


## 收窄/移动左侧闸门。传 -1 = 取消闸门。
func set_left_gate(x: int) -> void:
	left_gate_x = x
	if is_inside_tree():
		_apply_left_gate()


func is_left_gate_closed() -> bool:
	return left_gate_x >= 0


# --- 右侧闸门 -------------------------------------------------------------------

## 放开右侧闸门。幂等，读档恢复也调它。
func release_right_gate() -> void:
	set_right_gate(-1)


## 收窄/移动右侧闸门。传 -1 = 取消闸门。
func set_right_gate(x: int) -> void:
	right_gate_x = x
	if is_inside_tree():
		_apply_right_gate()


func is_right_gate_closed() -> bool:
	return right_gate_x >= 0


## 画面最右侧的世界坐标。和 get_screen_left_edge() 一样读的是**画面中心**。
func get_screen_right_edge() -> float:
	return get_screen_center_position().x + get_viewport_rect().size.x / zoom.x * 0.5


# --- 左侧闸门的「走过就落闸」模式 -----------------------------------------------

## 挂一道待落的左闸门：**等画面最左侧自己走到 x 再落闸**，而不是人一到某个
## 坐标就啪一下把边界收过来。这样画面不会跳——落闸的那一瞬间边界正好压在
## 当前画面的左缘上，观感是"走过去之后就再也让不回来了"。
##
## 传 -1 撤掉待落闸门。幂等；已经落下的闸门不受影响（撤的是"待落"这件事）。
func arm_left_gate_latch(x: int) -> void:
	_left_gate_latch_x = x


func is_left_gate_latch_armed() -> bool:
	return _left_gate_latch_x >= 0


## 画面最左侧的世界坐标。注意读的是**画面中心**（`get_screen_center_position()`），
## 不是节点位置——limit 生效时两者不同。
func get_screen_left_edge() -> float:
	return get_screen_center_position().x - get_viewport_rect().size.x / zoom.x * 0.5


func _update_left_gate_latch() -> void:
	if _left_gate_latch_x < 0:
		return
	# 只有当现有闸门比待落位置更靠西（= 视野更宽）时才需要落闸，
	# 否则画面已经被更靠东的闸门管着了。
	if left_gate_x >= _left_gate_latch_x:
		return
	if get_screen_left_edge() >= float(_left_gate_latch_x):
		set_left_gate(_left_gate_latch_x)


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
	_bounds_limit_left = int(bounds.position.x)
	limit_left = _bounds_limit_left
	_bounds_limit_right = int(bounds.position.x + bounds.size.x)
	limit_right = _bounds_limit_right
	var view := get_viewport_rect().size / zoom
	# 纵向 limit 只在世界比画面高的时候才有意义。画布上下多出影院边框之后
	# 画面（888）比世界（648）高，这时钳制会把相机往里推，游戏画面就不再
	# 居中、边框区域反而被塞进世界内容。所以这种情况直接放开纵向。
	if bounds.size.y > view.y:
		limit_top = int(bounds.position.y)
		limit_bottom = int(bounds.position.y + bounds.size.y)
	else:
		limit_top = -10000000
		limit_bottom = 10000000
	if bounds.size.x < view.x:
		push_warning(
			"FollowCamera2D: 场景宽 %d < 视口宽 %d，左右 limit 会冲突导致画面抖动。"
			% [int(bounds.size.x), int(view.x)])
	_apply_left_gate()
	_apply_right_gate()


## 闸门只会**收窄**可见范围，永远不会把画面推到场景外面去。
func _apply_left_gate() -> void:
	limit_left = maxi(_bounds_limit_left, left_gate_x) if left_gate_x >= 0 else _bounds_limit_left


func _apply_right_gate() -> void:
	limit_right = mini(_bounds_limit_right, right_gate_x) if right_gate_x >= 0 else _bounds_limit_right


func _apply_smoothing() -> void:
	position_smoothing_enabled = smoothing_seconds > 0.0
	if position_smoothing_enabled:
		position_smoothing_speed = 1.0 / smoothing_seconds
