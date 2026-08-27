@tool
class_name ArchBridge
extends StaticBody2D
## 拱桥地形：一段有弧度的可行走表面。
##
## 节点原点 = 桥的**正中、桥面两端落地那条线上**（也就是地面高度）。
## 桥面是一段抛物线：左右两端在 y = 0，中点抬到 y = -arch_height。
## 玩家从平地走上来时会顺着弧度爬升、过顶后自然下坡，不是水平直走。
##
## 之所以在运行时生成而不是手画多边形：桥的跨度和拱高是**关卡节奏参数**，
## 要能在 Inspector 里反复试；手画的 CollisionPolygon2D 一改就得重描一遍。
## 编辑器里也生效（@tool），所以拖参数能立刻看到形状。
##
## 只负责碰撞。桥的美术由背景图或单独的 Sprite2D 提供——地形和贴图分开，
## 换美术不用动碰撞。

## 桥面水平跨度（像素）。
@export var span: float = 800.0: set = _set_span
## 桥顶比两端高多少像素。0 就是平桥。
@export var arch_height: float = 90.0: set = _set_arch_height
## 桥体往下的厚度，给碰撞体一个实心的下半部分，免得玩家从侧面钻进去。
@export var thickness: float = 160.0: set = _set_thickness
## 弧线采样段数。越多越平滑，代价是碰撞点数。16 段对 800px 跨度足够。
@export_range(4, 64, 1) var segments: int = 16: set = _set_segments
## 打开后画出桥面轮廓（灰盒用）。正式美术接上后关掉。
@export var show_graybox: bool = true: set = _set_show_graybox

var _collision: CollisionPolygon2D
var _graybox: Polygon2D


func _ready() -> void:
	_rebuild()


func _set_span(v: float) -> void:
	span = maxf(v, 1.0)
	_rebuild()


func _set_arch_height(v: float) -> void:
	arch_height = maxf(v, 0.0)
	_rebuild()


func _set_thickness(v: float) -> void:
	thickness = maxf(v, 1.0)
	_rebuild()


func _set_segments(v: int) -> void:
	segments = clampi(v, 4, 64)
	_rebuild()


func _set_show_graybox(v: bool) -> void:
	show_graybox = v
	if _graybox != null:
		_graybox.visible = v


## 桥面在本地 x 处的高度。抛物线：两端 0，中点 -arch_height。
## 公开出来是为了让摆放桥上道具的代码能问「这个 x 该放多高」，
## 而不是各处自己抄一遍公式。
func get_surface_y(local_x: float) -> float:
	var half := span * 0.5
	if absf(local_x) >= half:
		return 0.0
	var t := local_x / half
	return -arch_height * (1.0 - t * t)


func _rebuild() -> void:
	if not is_inside_tree():
		return
	_ensure_children()
	var half := span * 0.5
	var top: PackedVector2Array = []
	for i in range(segments + 1):
		var x := -half + span * (float(i) / float(segments))
		top.append(Vector2(x, get_surface_y(x)))
	# 下沿走同一条弧线往下平移一个厚度，桥底就跟着弧度走、不会出现
	# 中间薄两头厚的怪形状。
	var poly := top.duplicate()
	for i in range(segments, -1, -1):
		poly.append(top[i] + Vector2(0.0, thickness))
	_collision.polygon = poly
	_graybox.polygon = poly
	_graybox.visible = show_graybox


func _ensure_children() -> void:
	if _collision == null:
		_collision = get_node_or_null(^"Collision") as CollisionPolygon2D
	if _collision == null:
		_collision = CollisionPolygon2D.new()
		_collision.name = "Collision"
		add_child(_collision)
	if _graybox == null:
		_graybox = get_node_or_null(^"Graybox") as Polygon2D
	if _graybox == null:
		_graybox = Polygon2D.new()
		_graybox.name = "Graybox"
		_graybox.color = Color(0.36, 0.3, 0.26, 1.0)
		add_child(_graybox)
		move_child(_graybox, 0)
