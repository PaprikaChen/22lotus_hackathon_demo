extends Control
## 前情提要：黑屏 + 居中文字，Space（`ui_accept`）逐段推进，最后一段之后进入
## 正式关卡。
##
## **只在新游戏流程里出现**——SaveSlotMenu 的新游戏分支跳到这里。它不是一个
## 「可以存档的地方」：`create_new_save()` 写进存档的 `current_scene` 直接是关卡，
## 所以玩家在这里退出再读档会直接进关卡，不会重看一遍。这是**流程保证的**，
## 不靠任何 Flag 判断。
##
## 用 `ui_accept`（引擎内建，含 Space 和 Enter）而不是 `jump`——`jump` 绑的
## 也是 Space，但语义是跳跃。`dialogue_box.gd` 推进文字用的也是这个约定，
## 所以**不需要改 input map**。
##
## 表现刻意极简（黑底白字 + 淡入淡出）。美术方案定稿后换掉 `_show_segment()`
## 即可，流程不用动。

signal finished

## 每段一条，逐段推进。文案存在场景的导出属性里、不写死在脚本中——
## 和 `text_interactable.gd` 的 display_text 同一条纪律，方便直接在编辑器里改。
@export var segments: PackedStringArray = []
@export var fade_duration: float = 0.8
## 切进关卡后黑幕淡出的时长。
@export var fade_in_duration: float = 1.0
## 每段至少停留这么久才接受输入，防止连按一路跳过。
@export var min_segment_time: float = 0.4
## Esc 整段跳过。
@export var allow_skip_all: bool = true
## 播完去哪。留空则用 SaveManager.NEW_GAME_SCENE_PATH。
@export_file("*.tscn") var next_scene: String = ""

@onready var _text: Label = $CenterContainer/TextLabel
@onready var _hint: Label = $ContinueHint

var _index: int = -1
var _segment_elapsed: float = 0.0
## 淡入淡出期间不接受推进，免得动画被打断。
var _busy: bool = false
var _done: bool = false


func _ready() -> void:
	_text.text = ""
	_text.modulate.a = 0.0
	_hint.modulate.a = 0.0
	if segments.is_empty():
		push_warning("PrologueScreen: segments 为空，直接进入关卡。")
		_finish()
		return
	_advance()


func _process(delta: float) -> void:
	_segment_elapsed += delta
	# 提示语缓慢呼吸，告诉玩家在等输入。
	if not _busy and not _done:
		_hint.modulate.a = 0.35 + 0.25 * sin(_segment_elapsed * 2.0)


func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if allow_skip_all and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_finish()
		return
	if not event.is_action_pressed(&"ui_accept"):
		return
	get_viewport().set_input_as_handled()
	if _busy or _segment_elapsed < min_segment_time:
		return
	_advance()


## 测试用：不依赖键盘也能推进一段。
func advance() -> void:
	if not _done:
		_advance()


func is_finished() -> bool:
	return _done


func get_segment_index() -> int:
	return _index


# --- 内部 ----------------------------------------------------------------------

func _advance() -> void:
	_index += 1
	if _index >= segments.size():
		_finish()
		return
	_show_segment(segments[_index])


func _show_segment(text: String) -> void:
	_busy = true
	_segment_elapsed = 0.0
	_hint.modulate.a = 0.0
	var is_last := _index == segments.size() - 1
	var tween := create_tween()
	# 第一段没有旧文字可淡出，省掉这一步免得开场干等。
	if _index > 0:
		tween.tween_property(_text, ^"modulate:a", 0.0, fade_duration * 0.5)
	tween.tween_callback(func() -> void: _text.text = text)
	tween.tween_property(_text, ^"modulate:a", 1.0, fade_duration)
	tween.tween_callback(func() -> void:
		_busy = false
		_segment_elapsed = 0.0
		_hint.text = "空格  进入" if is_last else "空格  ▸")


func _finish() -> void:
	if _done:
		return
	_done = true
	_hint.modulate.a = 0.0
	finished.emit()
	var target := next_scene if not next_scene.is_empty() else SaveManager.NEW_GAME_SCENE_PATH
	# 被当作子场景实例化（测试）时不切场景，只发 finished。
	if get_tree().current_scene != self:
		return
	if not ResourceLoader.exists(target):
		push_error("PrologueScreen: 目标场景不存在：%s" % target)
		return
	# 文字先淡出，黑幕停一拍，再切场景——切完由挂在 root 上的黑幕淡出，
	# 让「字幕页 → 关卡」看起来是一次连续的淡出淡入而不是硬切。
	var tween := create_tween()
	tween.tween_property(_text, ^"modulate:a", 0.0, fade_duration * 0.6)
	tween.tween_interval(0.2)
	tween.tween_callback(func() -> void: _enter_scene(target))


## 黑幕挂在 root 上而不是本场景里，这样它能活过 change_scene——否则场景一换
## 就跟着被 free，关卡会直接亮出来。
func _enter_scene(target: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 1)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(veil)
	get_tree().root.add_child(layer)
	get_tree().change_scene_to_file(target)
	var tween := veil.create_tween()
	tween.tween_interval(0.1)
	tween.tween_property(veil, ^"modulate:a", 0.0, fade_in_duration)
	tween.tween_callback(layer.queue_free)
