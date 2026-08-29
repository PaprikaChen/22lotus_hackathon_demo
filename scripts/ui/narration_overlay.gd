class_name NarrationOverlay
extends CanvasLayer
## 白幕文字演出：整块白底淡入，一次交互里的对白和旁白都在这块白幕正中央逐句
## 呈现，整段交互结束之后白幕才淡出。
##
## 为什么不复用 DialogueBox：DialogueBox 是「下边框字幕 + 立绘对话框」，服务
## 正常关卡。线稿记忆关卡要的是另一种演出——白底、居中、小字，一句一句地换。
## 两者是并列的两种表现，不该互相迁就。
##
## 层号取 80：盖住 FrameBars(50)/DialogueBox(60)/锁界面(70)，但低于
## ScreenFade(95)——切场景的白幕必须还能盖住它。
##
## 本节点**只管画面**：不锁玩家、不动流程，那是调用方（Director）的事。
##
## 用法（一次完整交互）：
##     await overlay.begin_session()
##     await overlay.show_line("……", "丽娘")
##     await overlay.show_line("……")          # 无说话人 = 旁白
##     await overlay.end_session()

signal line_finished
signal session_finished

## 白底不透明度。1.0 是纯白全遮；留成导出属性方便美术调。
@export var backdrop_color: Color = Color(1, 1, 1, 1)
@export var text_color: Color = Color(0.12, 0.10, 0.14, 1.0)
## 没有专属配色的说话人用这个。具体人名的颜色见 SPEAKER_COLORS。
@export var speaker_color: Color = Color(0.31, 0.28, 0.35, 1.0)
## 白幕上刻意用小字：整块白底已经够抢眼，字再大就压不住。
@export var font: Font = null
@export var font_size: int = 22
## 正文对齐。信件这类长段落左对齐更好读；旁白保持居中。
## 只作用于正文——说话人和推进提示始终居中。
@export var text_alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER
@export var speaker_font_size: int = 17
## 白幕整体进出。
@export var fade_in_duration: float = 0.35
@export var fade_out_duration: float = 0.35
## 句与句之间的换字淡入淡出，比白幕更快，免得读起来发黏。
@export var line_fade_duration: float = 0.15
## 每句至少停留这么久才接受推进，防连按一路跳过。
@export var min_hold_time: float = 0.25
## 说话人立绘：只有 `portrait_speaker` 这个人名带图，其他人（含幼年角色）不带。
## 规则和 dialogue_box.gd 一致，图片由场景指定，脚本不依赖素材路径。
@export var portrait: Texture2D = null
@export var portrait_speaker: String = "丽娘"

## 人名配色。低饱和为主，和 dialogue_box.gd 的 SPEAKER_COLOR_* 保持同一套语感：
## 丽娘（含幼年）紫、幼年春香深蓝。没列到的人走 speaker_color。
const SPEAKER_COLORS := {
	"丽娘": Color(0.34, 0.24, 0.40, 1.0),
	"幼年丽娘": Color(0.34, 0.24, 0.40, 1.0),
	"幼年春香": Color(0.11, 0.19, 0.44, 1.0),
}

## 分页符：正文里**空一行**就翻页——空格推进到下一页之后才继续。
## 单个换行符只是换行，还在同一页。这样在 Director 里写文案时，页与页的
## 边界一眼就能看出来，不用记额外的标记语法。
const PAGE_SEPARATOR := "\n\n"

## 正文两侧留白；有立绘时右侧让到 PORTRAIT_MARGIN，免得文字压在立绘上。
const TEXT_MARGIN := 220
const PORTRAIT_MARGIN := 440

var _center: MarginContainer = null
var _root: Control = null
var _backdrop: ColorRect = null
var _column: VBoxContainer = null
var _speaker_label: Label = null
var _label: Label = null
var _hint: Label = null
var _portrait_rect: TextureRect = null
var _root_tween: Tween = null
var _text_tween: Tween = null

## 白幕是否亮着（begin_session 到 end_session 之间）。
var _session_open: bool = false
## 当前是否有一句在等玩家推进。
var _awaiting_line: bool = false
## 淡入淡出期间不接受推进。
var _busy: bool = false
var _elapsed: float = 0.0
# 手动上升沿（项目约定：真键盘和注入输入要走同一条路径）。
var _accept_held: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 80
	_build()


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.modulate.a = 0.0
	_root.visible = false
	add_child(_root)

	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = backdrop_color
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_backdrop)

	# 居中容器 + 两侧留白：长句在正中央换行，不会顶到屏幕边。
	var center := MarginContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_theme_constant_override(&"margin_left", TEXT_MARGIN)
	center.add_theme_constant_override(&"margin_right", TEXT_MARGIN)
	_root.add_child(center)
	_center = center

	# 说话人和正文一起淡入淡出，所以放同一列里整列改 alpha。
	_column = VBoxContainer.new()
	_column.name = "TextColumn"
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_column.add_theme_constant_override(&"separation", 14)
	center.add_child(_column)

	_speaker_label = _make_label("SpeakerLabel", speaker_font_size, speaker_color)
	_speaker_label.visible = false
	_column.add_child(_speaker_label)

	_label = _make_label("TextLabel", font_size, text_color)
	_label.horizontal_alignment = text_alignment
	_column.add_child(_label)

	# 立绘悬在白幕右侧，正文列靠左侧留白避让，二者互不挤压。
	_portrait_rect = TextureRect.new()
	_portrait_rect.name = "Portrait"
	_portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_rect.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_portrait_rect.offset_left = -float(PORTRAIT_MARGIN)
	_portrait_rect.offset_top = -424.0
	_portrait_rect.offset_right = -60.0
	_portrait_rect.visible = false
	_root.add_child(_portrait_rect)

	# 推进提示单独挂在底部，不跟着正文换字淡入淡出。
	_hint = _make_label("ContinueHint", speaker_font_size - 3, Color(text_color.r, text_color.g, text_color.b, 0.45))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -72.0
	_hint.offset_bottom = -40.0
	_hint.text = "空格 ▸"
	_hint.visible = false
	_root.add_child(_hint)


func _make_label(node_name: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	if font != null:
		label.add_theme_font_override(&"font", font)
	return label


func _process(delta: float) -> void:
	if not _awaiting_line:
		return
	_elapsed += delta
	var accept := Input.is_action_pressed("ui_accept")
	if (not _busy and _elapsed >= min_hold_time
			and accept and not _accept_held):
		_close_line()
	_accept_held = accept


func is_showing() -> bool:
	return _session_open


# --- Public API -----------------------------------------------------------------

## 点亮白幕。已经亮着时立刻返回，重复调用安全。
func begin_session() -> void:
	if _session_open:
		return
	_session_open = true
	_busy = true
	_set_line_text("", "")
	_column.modulate.a = 0.0
	_root.visible = true
	await _fade_root_to(1.0, fade_in_duration)
	_busy = false


## 放一句（`speaker` 为空 = 旁白），等玩家按空格之后淡出这句文字，白幕不动。
## 正文里空一行就分页：每页各等一次空格，说话人和立绘跨页保持不变。
## 白幕没亮时会自己先点亮，调用方可以只管放句子。
func show_line(text: String, speaker: String = "") -> void:
	if text.strip_edges().is_empty():
		return
	if not _session_open:
		await begin_session()
	for page in split_pages(text):
		await _show_page(page, speaker)


## 把一段文案按空行切成若干页。公开出来是为了让测试能断言分页结果。
static func split_pages(text: String) -> PackedStringArray:
	var pages := PackedStringArray()
	for raw_page in text.split(PAGE_SEPARATOR):
		var page := raw_page.strip_edges()
		if not page.is_empty():
			pages.append(page)
	return pages


func _show_page(page: String, speaker: String) -> void:
	_busy = true
	_elapsed = 0.0
	# 进场时把空格记成「已按下」，免得上一页的那次按键顺延推进这一页。
	_accept_held = true
	_set_line_text(page, speaker)
	_hint.visible = true
	_awaiting_line = true
	await _fade_column_to(1.0, line_fade_duration)
	_busy = false
	await line_finished


## 收掉白幕。没亮着时立刻返回。
func end_session() -> void:
	if not _session_open:
		return
	_busy = true
	_awaiting_line = false
	_hint.visible = false
	await _fade_root_to(0.0, fade_out_duration)
	_root.visible = false
	_set_line_text("", "")
	_column.modulate.a = 0.0
	_session_open = false
	_busy = false
	session_finished.emit()


## 测试 / 强制推进用：不依赖键盘也能收掉当前这句。
func advance() -> void:
	if _awaiting_line and not _busy:
		_close_line()


# --- Internal ---------------------------------------------------------------------

func _close_line() -> void:
	_awaiting_line = false
	_busy = true
	_hint.visible = false
	await _fade_column_to(0.0, line_fade_duration)
	_busy = false
	line_finished.emit()


func _set_line_text(text: String, speaker: String) -> void:
	_label.text = text
	_speaker_label.text = speaker
	_speaker_label.visible = not speaker.is_empty()
	_speaker_label.add_theme_color_override(&"font_color", _get_speaker_color(speaker))
	var show_portrait := portrait != null and speaker == portrait_speaker
	_portrait_rect.texture = portrait if show_portrait else null
	_portrait_rect.visible = show_portrait
	_center.add_theme_constant_override(
		&"margin_right", PORTRAIT_MARGIN if show_portrait else TEXT_MARGIN)


func _get_speaker_color(speaker: String) -> Color:
	return SPEAKER_COLORS.get(speaker, speaker_color)


func _fade_root_to(target_alpha: float, duration: float) -> void:
	_root_tween = await _fade_to(_root, _root_tween, target_alpha, duration)


func _fade_column_to(target_alpha: float, duration: float) -> void:
	_text_tween = await _fade_to(_column, _text_tween, target_alpha, duration)


func _fade_to(target: CanvasItem, tween: Tween, alpha: float, duration: float) -> Tween:
	_kill(tween)
	if duration <= 0.0:
		target.modulate.a = alpha
		return null
	var t := create_tween()
	# 暂停期间也要能淡入淡出（锁界面会 paused = true）。
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(target, "modulate:a", alpha, duration)
	await t.finished
	return null


func _kill(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()


func _exit_tree() -> void:
	_kill(_root_tween)
	_kill(_text_tween)
