class_name CGSequence
extends CanvasLayer
## 定格 CG 回忆片段：一张图 + 一句解释字幕，空格推进到下一张。
##
## 为什么不复用 NarrationOverlay：那块白幕只放文字（线稿记忆关卡的演出）。
## 这里是**图为主、字为辅**——整屏一张 CG，字幕压在下方。两者是并列的两种
## 演出件，不该互相迁就。
##
## 本节点**只管画面**：不锁玩家、不管前后的白幕过渡、不写 Flag，
## 那些是调用方（StoryDirector）的事。调用方要保证进入时画面已被遮住
## （通常是先把 ScreenFade 拉成全黑），因为本件的底色是瞬间出现的。
##
## 用法：
##     await cg.play()   # 逐张放完
##     cg.close()        # 调用方已经把画面重新遮住之后再收
##
## 层号取 82：盖住 FrameBars(50)/DialogueBox(60)/锁界面(70)，但低于
## ScreenFade(95)——白幕过渡必须还能盖住它。

signal page_shown(index: int)
signal finished
## 内部用：一页淡出结束。play() 靠它逐页往下走。
signal page_closed

## 图片与字幕按下标一一对应。分成两个数组而不是自定义 Resource：
## 这样在编辑器里改文案不用先建资源文件（和 prologue 的 segments 同一条纪律）。
@export var images: Array[Texture2D] = []
## 默认值必须写 PackedStringArray()：写 `[]` 会让导出类型退化，
## 场景里存的值会被**静默丢掉**。
@export var captions: PackedStringArray = PackedStringArray()

@export_group("Look")
## 图片之外的底色。默认黑，配合黑幕过渡；场景可改。
@export var backdrop_color: Color = Color(0, 0, 0, 1)
## 字幕（和右下角提示）的颜色，跟着底色走。
@export var caption_color: Color = Color(0.92, 0.90, 0.87, 1.0)
@export var caption_font: Font = null
@export var caption_font_size: int = 24
## 图片四周留白，避免 CG 顶到屏幕边。字幕另占下方一条。
@export var image_margin: int = 90
@export var caption_band_height: int = 130

@export_group("Timing")
@export var page_fade_duration: float = 0.45
## 每页至少停留这么久才接受输入，防连按一路跳过。
@export var min_hold_time: float = 0.35

const HINT_FONT_SIZE := 14

var _root: Control = null
var _backdrop: ColorRect = null
var _image_rect: TextureRect = null
var _caption: Label = null
var _hint: Label = null

var _index: int = -1
var _awaiting_page: bool = false
## 淡入淡出期间不接受推进，免得动画被打断。
var _busy: bool = false
var _elapsed: float = 0.0
var _accept_held: bool = false
var _tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 82
	_build()


func _process(delta: float) -> void:
	if not _awaiting_page:
		return
	_elapsed += delta
	# 手动上升沿而不是 is_action_just_pressed：同一段代码要能被真键盘和测试
	# 注入的输入同样驱动（AGENTS.md 的约定）。
	var accept := Input.is_action_pressed("ui_accept")
	if not _busy and _elapsed >= min_hold_time and accept and not _accept_held:
		_close_page()
	_accept_held = accept


# --- Public API -----------------------------------------------------------------

func is_showing() -> bool:
	return _root != null and _root.visible


func get_page_index() -> int:
	return _index


## 逐张放完。调用方 await 它，返回即全部播完（画面仍停在最后一张的底色上，
## 由调用方遮住画面后再 close()）。
func play() -> void:
	if images.is_empty():
		push_warning("CGSequence: images 为空，直接结束。")
		finished.emit()
		return
	_root.visible = true
	_root.modulate.a = 1.0
	_index = -1
	for i in images.size():
		await _show_page(i)
	_awaiting_page = false
	_hint.visible = false
	finished.emit()


## 收掉。调用方应先把画面遮住，否则会看到 CG 直接消失。
func close() -> void:
	_kill_tween()
	_awaiting_page = false
	_busy = false
	_root.visible = false
	_image_rect.texture = null
	_caption.text = ""
	_index = -1


## 测试 / 强制推进用：不依赖键盘也能翻到下一张。
func advance() -> void:
	if _awaiting_page and not _busy:
		_close_page()


# --- Internal ---------------------------------------------------------------------

func _show_page(index: int) -> void:
	_index = index
	_busy = true
	_elapsed = 0.0
	# 进场时把空格记成「已按下」，免得上一页的那次按键顺延推进这一页。
	_accept_held = true
	_image_rect.texture = images[index]
	_caption.text = captions[index] if index < captions.size() else ""
	_hint.text = "空格  返回" if index == images.size() - 1 else "空格  ▸"
	_hint.visible = true
	_awaiting_page = true
	page_shown.emit(index)
	await _fade_content_to(1.0)
	_busy = false
	# 等 _close_page() 把这一页收掉。
	await page_closed


func _close_page() -> void:
	_awaiting_page = false
	_busy = true
	_hint.visible = false
	await _fade_content_to(0.0)
	_busy = false
	page_closed.emit()


func _fade_content_to(alpha: float) -> void:
	_kill_tween()
	if page_fade_duration <= 0.0:
		_image_rect.modulate.a = alpha
		_caption.modulate.a = alpha
		return
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_parallel(true)
	_tween.tween_property(_image_rect, ^"modulate:a", alpha, page_fade_duration)
	_tween.tween_property(_caption, ^"modulate:a", alpha, page_fade_duration)
	await _tween.finished
	_tween = null


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)

	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = backdrop_color
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_backdrop)

	# 图片区：四周留白，下方给字幕让出一条。KEEP_ASPECT_CENTERED 保证不同
	# 比例的 CG 都不变形。
	var image_holder := MarginContainer.new()
	image_holder.name = "ImageHolder"
	image_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	image_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image_holder.add_theme_constant_override(&"margin_left", image_margin)
	image_holder.add_theme_constant_override(&"margin_right", image_margin)
	image_holder.add_theme_constant_override(&"margin_top", image_margin)
	image_holder.add_theme_constant_override(&"margin_bottom", caption_band_height)
	_root.add_child(image_holder)

	_image_rect = TextureRect.new()
	_image_rect.name = "Image"
	_image_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image_rect.modulate.a = 0.0
	image_holder.add_child(_image_rect)

	_caption = Label.new()
	_caption.name = "Caption"
	_caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.anchor_top = 1.0
	_caption.anchor_bottom = 1.0
	_caption.offset_top = -float(caption_band_height)
	_caption.offset_bottom = -30.0
	_caption.offset_left = float(image_margin)
	_caption.offset_right = -float(image_margin)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_size_override(&"font_size", caption_font_size)
	_caption.add_theme_color_override(&"font_color", caption_color)
	if caption_font != null:
		_caption.add_theme_font_override(&"font", caption_font)
	_caption.modulate.a = 0.0
	_root.add_child(_caption)

	_hint = Label.new()
	_hint.name = "ContinueHint"
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint.anchor_left = 1.0
	_hint.anchor_top = 1.0
	_hint.anchor_right = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = -200.0
	_hint.offset_top = -34.0
	_hint.offset_right = -24.0
	_hint.offset_bottom = -10.0
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override(&"font_size", HINT_FONT_SIZE)
	_hint.add_theme_color_override(&"font_color", caption_color)
	_hint.visible = false
	_root.add_child(_hint)


func _exit_tree() -> void:
	_kill_tween()
