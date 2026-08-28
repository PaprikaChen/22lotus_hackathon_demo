class_name ScreenFade
extends CanvasLayer
## 全屏黑幕：`fade_out()` 变黑、`fade_in()` 变亮，两个都是 await 得到的协程。
##
## 为什么单独抽一个节点：项目里原本只有 `area_flow_controller.gd` 内联的一段
## Tween（同场景内换区域用），没有可复用的过渡件。这里把它抽成最小可复用
## 实现——**只管画面变黑变亮**，不锁玩家、不动相机、不切场景，
## 那些是调用方（关卡 / 陷阱 / Director）的事。
##
## 层号高于 FrameBars(50) / DialogueBox(60) / 锁界面(70)，黑幕必须盖住全部。
##
## 重入保护：正在过渡时再调用会先掐掉上一个 Tween，绝不会出现两个 Tween
## 同时抢同一个 alpha。想知道现在是否在过渡问 `is_fading()`。

signal fade_finished(opaque: bool)

@export var color: Color = Color(0, 0, 0, 1): set = _set_color

var _rect: ColorRect = null
var _tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 95
	_build()


func _build() -> void:
	_rect = ColorRect.new()
	_rect.name = "FadeRect"
	_rect.color = Color(color.r, color.g, color.b, 0.0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 黑幕期间不该吃掉鼠标事件的判断权交给调用方：全黑时世界已经暂停/锁住，
	# 这里保持 IGNORE，免得挡住下面正在关闭的 UI 的按钮。
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)


func is_fading() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


func is_opaque() -> bool:
	return _rect != null and _rect.color.a >= 1.0


## 变黑。duration <= 0 立刻生效。
func fade_out(duration: float = 0.4) -> void:
	await _fade_to(1.0, duration)


## 变亮。
func fade_in(duration: float = 0.4) -> void:
	await _fade_to(0.0, duration)


## 不做过渡直接设定，切场景 / 强制复位用。
func set_opaque(opaque: bool) -> void:
	_kill_tween()
	if _rect != null:
		_rect.color.a = 1.0 if opaque else 0.0


func _fade_to(target_alpha: float, duration: float) -> void:
	if _rect == null:
		return
	_kill_tween()
	if duration <= 0.0:
		_rect.color.a = target_alpha
		fade_finished.emit(target_alpha >= 1.0)
		return
	_tween = create_tween()
	# 暂停期间也要能淡入淡出（锁界面会 paused = true）。
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(_rect, "color:a", target_alpha, duration)
	await _tween.finished
	_tween = null
	fade_finished.emit(target_alpha >= 1.0)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _set_color(value: Color) -> void:
	color = value
	if _rect != null:
		_rect.color = Color(value.r, value.g, value.b, _rect.color.a)


func _exit_tree() -> void:
	# 场景卸载时把 Tween 清掉，别留悬挂回调。
	_kill_tween()
