@tool
class_name FrameBars
extends CanvasLayer
## 影院边框：把**新增出来的**上下两块画布填成纯黑。
##
## 它不是盖在游戏画面上的遮罩。真正的改动在 project.godot：设计分辨率的高度
## 从 648 提到 828，也就是画布上下各多出 90px 从前不存在的空间。原来那 648px
## 的游戏画面一寸没动，仍然按 1:1 显示在正中间；相机的可视世界高度也还是
## 648（`Backdrop.world_height`），多出来的部分本来就没有任何世界内容。
##
## 这个节点只负责让那两块空白是可控的纯黑（而不是依赖清屏色），并给字幕、
## 立绘一个明确的摆放范围。`_assert_no_overlap()` 保证它永远不会伸进游戏区。
##
## 想知道边框多高、字幕能摆在哪，问 `get_bar_height()` / `get_bottom_band_rect()`，
## 别各处抄 90。

## 原游戏画面的高度。**不要**改这个来调边框——它是"多出来之前"的高度，
## 改边框厚度请改 project.godot 里的 viewport_height。
@export var gameplay_height: float = 648.0: set = _set_gameplay_height
@export var bar_color: Color = Color(0, 0, 0, 1): set = _set_bar_color

var _root: Control
var _top: ColorRect
var _bottom: ColorRect


func _ready() -> void:
	_rebuild()


## 单条边框的高度 = （新画布高 - 原画面高）/ 2。
func get_bar_height() -> float:
	return maxf((_canvas_size().y - gameplay_height) * 0.5, 0.0)


## 下边框的矩形（相对画布左上角）。字幕就摆在这里面。
func get_bottom_band_rect() -> Rect2:
	var canvas := _canvas_size()
	var bar := get_bar_height()
	return Rect2(Vector2(0.0, canvas.y - bar), Vector2(canvas.x, bar))


## 上边框的矩形。以后放立绘 / 章节标题用。
func get_top_band_rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(_canvas_size().x, get_bar_height()))


## 原游戏画面在新画布里占的矩形。用来核对"画面没被动过"。
func get_gameplay_rect() -> Rect2:
	var bar := get_bar_height()
	return Rect2(Vector2(0.0, bar), Vector2(_canvas_size().x, gameplay_height))


func _set_gameplay_height(v: float) -> void:
	gameplay_height = maxf(v, 0.0)
	_rebuild()


func _set_bar_color(v: Color) -> void:
	bar_color = v
	_rebuild()


## 设计分辨率，不是窗口尺寸：stretch 模式是 canvas_items，UI 坐标系永远是
## 设计分辨率，读窗口尺寸会在放大的窗口里算出错的高度。
func _canvas_size() -> Vector2:
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1152)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 828)))


func _rebuild() -> void:
	if not is_inside_tree():
		return
	_ensure_children()
	var bar := get_bar_height()
	_assert_no_overlap(bar)
	# 锚在画布上下边缘，只用 offset 定厚度——改设计分辨率不用重算。
	_lay_out(_top, 0.0, 0.0, bar)
	_lay_out(_bottom, 1.0, -bar, 0.0)
	_top.color = bar_color
	_bottom.color = bar_color
	_top.visible = bar > 0.0
	_bottom.visible = bar > 0.0


## 边框只许待在新增的空间里。哪天有人把 viewport_height 改回 648（或者改小），
## 边框就会开始压到游戏画面上——那正是这次改动明确不要的东西，所以直接报错，
## 不要让它静默发生。
func _assert_no_overlap(bar: float) -> void:
	if _canvas_size().y < gameplay_height:
		push_error(
			"FrameBars: 画布高 %d 小于游戏画面高 %d，边框会盖住画面。"
			% [int(_canvas_size().y), int(gameplay_height)])


func _lay_out(node: Control, anchor: float, offset_top: float, offset_bottom: float) -> void:
	node.anchor_left = 0.0
	node.anchor_right = 1.0
	node.anchor_top = anchor
	node.anchor_bottom = anchor
	node.offset_left = 0.0
	node.offset_right = 0.0
	node.offset_top = offset_top
	node.offset_bottom = offset_bottom


func _ensure_children() -> void:
	if _root == null:
		_root = get_node_or_null(^"Root") as Control
	if _root == null:
		_root = Control.new()
		_root.name = "Root"
		_root.set_anchors_preset(Control.PRESET_FULL_RECT)
		_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_root)
	_top = _ensure_rect(_top, "TopBar")
	_bottom = _ensure_rect(_bottom, "BottomBar")


func _ensure_rect(current: ColorRect, node_name: String) -> ColorRect:
	if current != null:
		return current
	var found := _root.get_node_or_null(NodePath(node_name)) as ColorRect
	if found != null:
		return found
	var rect := ColorRect.new()
	rect.name = node_name
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(rect)
	return rect
