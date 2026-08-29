extends CanvasLayer
## Bottom-of-screen dialogue / interaction text box (graybox), PAGED:
## show_text() splits the text into sentences (one per line), displays one at
## a time; ui_accept (Space) advances, and after the last line the box hides.
##
## While the box is open the player is held with the source-based input lock
## ("dialogue_box", via begin_interaction so the state shows INTERACT) — so
## Space advances text instead of jumping, and world interaction pauses.
## Any named speaker uses the illustrated dialogue frame. Only Liniang gets a
## right-side portrait for now; narration keeps the compact subtitle layout.
## Runs while the tree is paused so future paused dialogue flows keep working.

signal line_shown(line: String)
signal closed
## 玩家选完之后发，参数是选项下标（0 = 第一个）。
signal choice_selected(index: int)

const LOCK_SOURCE := &"dialogue_box"
## 旁白字幕面板在下边框里留的上下内缩。
const SUBTITLE_BAND_INSET := 10.0
## 场景里没有 FrameBars 时旁白字幕面板的高度。
const SUBTITLE_BAND_FALLBACK := 148.0
## 人名使用低饱和的莫兰迪色，正文保持统一，避免颜色抢过台词本身。
const SPEAKER_COLOR_DEFAULT := Color(0.31, 0.28, 0.35, 1.0)
const SPEAKER_COLOR_LINIANG := Color(0.34, 0.24, 0.40, 1.0)
const SPEAKER_COLOR_SERVANT := Color(0.23, 0.32, 0.38, 1.0)
const SPEAKER_COLOR_CHUNXIANG := Color(0.40, 0.27, 0.33, 1.0)
const SPEAKER_COLOR_MAID := Color(0.36, 0.27, 0.31, 1.0)

## Player to lock while the box is open (optional).
@export var player_path: NodePath
## 目前唯一接入的说话角色立绘；场景资源负责指定图片，脚本不依赖素材路径。
@export var liniang_portrait: Texture2D
## 特殊演出可保留“丽娘”说话人样式但关闭立绘（例如幼年记忆关卡）。
@export var liniang_portrait_enabled: bool = true
## 半透明黑幕压暗世界。它的用途是**给压在画面上的展示物让出注意力**——
## 立绘、以后的信纸／物品图。纯字幕（调查点的解释文字）没有展示物，压暗只会
## 让玩家以为场景变了，所以默认不压。个别演出想让旁白也压暗时把它打开。
@export var dim_world_for_narration: bool = false
## 同关卡里的 FrameBars（默认取同级节点）。只用来问下边框多高——
## 旁白字幕要摆在那条黑边里。找不到就走 SUBTITLE_BAND_FALLBACK。
@export var frame_bars_path: NodePath = ^"../FrameBars"

@onready var _panel: Control = $Root/Panel
@onready var _world_dimmer: CanvasLayer = $WorldDimmer
@onready var _speech_frame: TextureRect = $Root/Panel/SpeechFrame
@onready var _margin: MarginContainer = $Root/Panel/Margin
@onready var _content_row: HBoxContainer = $Root/Panel/Margin/HBox
@onready var _portrait: TextureRect = $Root/Portrait
@onready var _speaker_label: Label = $Root/Panel/Margin/HBox/TextColumn/SpeakerLabel
@onready var _text_label: Label = $Root/Panel/Margin/HBox/TextColumn/TextLabel
@onready var _continue_hint: Label = $Root/Panel/ContinueHint
## 选项自成一列（挂在 HBox 下，不在正文列里）：放在正文侧边才有横向空间把
## 选项文字显示完整——塞在正文下面时那点高度会把选项挤掉。
@onready var _choice_list: VBoxContainer = $Root/Panel/Margin/HBox/ChoiceList

var _lines: PackedStringArray = []
var _line_index: int = 0
var _player: Node = null

## 选择态：文字放完之后不关框，改成等玩家选。
var _options: PackedStringArray = []
var _choice_index: int = 0
var _choosing: bool = false
var _is_spoken_dialogue: bool = false

# Rising-edge tracking (project convention; see AGENTS.md).
var _accept_held: bool = false
var _up_held: bool = false
var _down_held: bool = false
var _cancel_held: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_set_dialogue_visible(false)
	_choice_list.visible = false
	_player = get_node_or_null(player_path)


func _process(_delta: float) -> void:
	# 全部走手动上升沿而不是 is_action_just_pressed：同一段代码要能被真键盘和
	# 测试注入的输入同样驱动（AGENTS.md 的约定）。
	var accept := Input.is_action_pressed("ui_accept")
	var up := Input.is_action_pressed("ui_up") or Input.is_action_pressed("move_up")
	var down := Input.is_action_pressed("ui_down") or Input.is_action_pressed("move_down")
	var cancel := Input.is_action_pressed("ui_cancel")
	if _panel.visible:
		if _choosing:
			if up and not _up_held:
				_move_choice(-1)
			if down and not _down_held:
				_move_choice(1)
			if accept and not _accept_held:
				_confirm_choice()
			# Esc 等于选最后一项（约定：最后一项是"否 / 算了"）。
			if cancel and not _cancel_held:
				_choice_index = maxi(_options.size() - 1, 0)
				_confirm_choice()
		elif accept and not _accept_held:
			advance()
	_accept_held = accept
	_up_held = up
	_down_held = down
	_cancel_held = cancel


# --- Public API -----------------------------------------------------------------

## Splits `text` into non-empty lines and shows the first one. A non-empty
## `speaker` selects the spoken-dialogue presentation. Calling again while
## open replaces the content.
func show_text(text: String, _portrait_override: Texture2D = null, speaker: String = "") -> void:
	var lines := PackedStringArray()
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if not line.is_empty():
			lines.append(line)
	if lines.is_empty():
		return
	_exit_choice_mode()
	_lines = lines
	_line_index = 0
	_set_dialogue_visible(true)
	_apply_presentation(not speaker.is_empty())
	var show_liniang_portrait: bool = (
		speaker == "丽娘" and liniang_portrait_enabled and liniang_portrait != null)
	_portrait.texture = liniang_portrait if show_liniang_portrait else null
	_portrait.visible = show_liniang_portrait
	_speaker_label.text = speaker
	_speaker_label.visible = not speaker.is_empty()
	_speaker_label.add_theme_color_override(&"font_color", _get_speaker_color(speaker))
	_lock_player()
	_show_current_line()


## 先放 `text`（分句翻页），最后一句之后不关框、改成让玩家在 `options` 里选。
## 用 await 拿结果：`var i := await dialogue.ask(text, options)`。
##
## 为什么返回值走 await 而不是回调：调用方（关卡）读起来是一条直线，
## 不用把"选完之后干什么"拆到另一个函数里。
func ask(text: String, options: PackedStringArray,
		portrait: Texture2D = null, speaker: String = "") -> int:
	if options.is_empty():
		push_warning("DialogueBox.ask(): options 为空，退化成普通文字。")
		show_text(text, portrait, speaker)
		return -1
	_options = options
	show_text(text, portrait, speaker)
	# show_text() 会清掉选择态，所以选项在它之后再挂上。
	_options = options
	if _lines.is_empty():
		# 没有文字可放，直接进选择态（show_text 这时没开框，得自己开）。
		_set_dialogue_visible(true)
		_lock_player()
		_enter_choice_mode()
	return await choice_selected


func is_choosing() -> bool:
	return _choosing


## 测试用：不依赖键盘也能选。
func select_choice(index: int) -> void:
	if not _choosing:
		return
	_choice_index = clampi(index, 0, _options.size() - 1)
	_confirm_choice()


## Next line, or close after the last one.
func advance() -> void:
	if not _panel.visible:
		return
	if _choosing:
		return
	_line_index += 1
	if _line_index >= _lines.size():
		# 有选项就停在这里等选择，别把框关掉。
		if not _options.is_empty():
			_enter_choice_mode()
			return
		hide_box()
	else:
		_show_current_line()


func hide_box() -> void:
	if not _panel.visible:
		return
	_set_dialogue_visible(false)
	_lines = PackedStringArray()
	_exit_choice_mode()
	_unlock_player()
	closed.emit()


func is_showing() -> bool:
	return _panel.visible


## The line currently on screen ("" when hidden).
func get_current_text() -> String:
	return _text_label.text if _panel.visible else ""


func _set_dialogue_visible(visible: bool) -> void:
	_panel.visible = visible
	if not visible:
		_portrait.visible = false
	_refresh_world_dimmer()


## 黑幕跟着「画面上有没有展示物」走，不是跟着「对话框开没开」走。
## 以后接入物品展示（信纸等）时，把那个判断并进这里，别再各处自己开黑幕。
func _refresh_world_dimmer() -> void:
	_world_dimmer.visible = (
		_panel.visible and (_is_spoken_dialogue or dim_world_for_narration))


# --- Internal ---------------------------------------------------------------------

func _show_current_line() -> void:
	_text_label.text = _lines[_line_index]
	var is_last := _line_index >= _lines.size() - 1
	if is_last:
		_continue_hint.text = "空格 ▸" if not _options.is_empty() else "空格 关闭"
	else:
		_continue_hint.text = "空格 ▸"
	line_shown.emit(_lines[_line_index])


# --- 选择 -----------------------------------------------------------------------

func _enter_choice_mode() -> void:
	_choosing = true
	_choice_index = 0
	_continue_hint.text = "W/S 选择   空格 确定"
	for child in _choice_list.get_children():
		child.queue_free()
	# 选项按 options 现场生成而不是在场景里摆死几个 Label：选项数量是调用方的
	# 事，两项三项都得能用。
	for option in _options:
		var label := Label.new()
		label.text = option
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override(&"font_size", 20)
		label.add_theme_color_override(&"font_color", Color(0.15, 0.12, 0.18, 1.0) if _is_spoken_dialogue else Color.WHITE)
		_choice_list.add_child(label)
	_choice_list.visible = true
	_refresh_choice_labels()


func _exit_choice_mode() -> void:
	_choosing = false
	_options = PackedStringArray()
	_choice_list.visible = false
	for child in _choice_list.get_children():
		child.queue_free()


func _move_choice(step: int) -> void:
	if _options.is_empty():
		return
	_choice_index = posmod(_choice_index + step, _options.size())
	_refresh_choice_labels()


func _refresh_choice_labels() -> void:
	var children := _choice_list.get_children()
	for i in children.size():
		var label := children[i] as Label
		if label == null:
			continue
		var selected := i == _choice_index
		label.text = ("▸ %s" if selected else "   %s") % _options[i]
		label.modulate = Color(1, 1, 1, 1) if selected else Color(1, 1, 1, 0.55)


func _get_speaker_color(speaker: String) -> Color:
	match speaker:
		"丽娘", "幼年丽娘":
			return SPEAKER_COLOR_LINIANG
		"家丁":
			return SPEAKER_COLOR_SERVANT
		"丫鬟春香", "幼年春香":
			return SPEAKER_COLOR_CHUNXIANG
		"丫鬟":
			return SPEAKER_COLOR_MAID
		_:
			return SPEAKER_COLOR_DEFAULT


## Keeps narration and character speech as two visual presentations of the
## same DialogueBox, so interaction flow and input locking remain unchanged.
func _apply_presentation(spoken: bool) -> void:
	_is_spoken_dialogue = spoken
	_speech_frame.visible = spoken
	_refresh_world_dimmer()
	if spoken:
		# 2388 x 614 的对话框保持接近原图比例，落在画面中下方。
		_panel.anchor_left = 0.5
		_panel.anchor_top = 1.0
		_panel.anchor_right = 0.5
		_panel.anchor_bottom = 1.0
		_panel.offset_left = -530.0
		_panel.offset_top = -252.0
		_panel.offset_right = 530.0
		_panel.offset_bottom = 20.0
		_margin.add_theme_constant_override(&"margin_left", 110)
		_margin.add_theme_constant_override(&"margin_top", 62)
		# 大立绘独立悬在 Panel 右侧，正文在右边预留空间，二者互不挤压。
		_margin.add_theme_constant_override(&"margin_right", 380)
		_margin.add_theme_constant_override(&"margin_bottom", 48)
		_content_row.add_theme_constant_override(&"separation", 8)
		_content_row.move_child(_choice_list, _content_row.get_child_count() - 1)
		_text_label.add_theme_color_override(&"font_color", Color(0.15, 0.12, 0.18, 1.0))
		_continue_hint.add_theme_color_override(&"font_color", Color(0.15, 0.12, 0.18, 1.0))
	else:
		# 旁白 / 调查字幕：整块摆进**下方黑边框**里。
		# 高度问 FrameBars 而不是抄一个常数（AGENTS.md：边框厚度只有一个来源），
		# 拿不到就退化成一个不出画的保守值。
		# 注意 offset_bottom 必须 ≤ 0：正数会把面板推到画布外面，
		# 字幕纵向居中之后就正好落在看不见的那一半里。
		var band := _bottom_band_height()
		_panel.anchor_left = 0.0
		_panel.anchor_top = 1.0
		_panel.anchor_right = 1.0
		_panel.anchor_bottom = 1.0
		_panel.offset_left = 48.0
		_panel.offset_top = -band + SUBTITLE_BAND_INSET
		_panel.offset_right = -48.0
		_panel.offset_bottom = -SUBTITLE_BAND_INSET
		_margin.add_theme_constant_override(&"margin_left", 14)
		_margin.add_theme_constant_override(&"margin_top", 12)
		_margin.add_theme_constant_override(&"margin_right", 14)
		_margin.add_theme_constant_override(&"margin_bottom", 12)
		_content_row.add_theme_constant_override(&"separation", 16)
		_text_label.add_theme_color_override(&"font_color", Color.WHITE)
		_continue_hint.add_theme_color_override(&"font_color", Color.WHITE)


## 下方黑边框的高度。问 FrameBars（`get_bar_height()`），它是这个数唯一的来源；
## 没有边框的场景（前情提要、纯 UI 测试）退化成 SUBTITLE_BAND_FALLBACK。
func _bottom_band_height() -> float:
	var bars := get_node_or_null(frame_bars_path)
	if bars != null and bars.has_method("get_bar_height"):
		var h: float = bars.get_bar_height()
		if h > SUBTITLE_BAND_INSET * 4.0:
			return h
	return SUBTITLE_BAND_FALLBACK


func _confirm_choice() -> void:
	var index := _choice_index
	_choosing = false
	# 先关框再发信号：await 方等到结果时框已经收掉，紧接着做的镜头动画
	# 不会被对话框压在上面。
	hide_box()
	choice_selected.emit(index)


func _lock_player() -> void:
	if _player == null:
		return
	if _player.has_method("begin_interaction"):
		_player.begin_interaction(LOCK_SOURCE)
	elif _player.has_method("lock_input"):
		_player.lock_input(LOCK_SOURCE)


func _unlock_player() -> void:
	if _player == null:
		return
	if _player.has_method("end_interaction"):
		_player.end_interaction(LOCK_SOURCE)
	elif _player.has_method("unlock_input"):
		_player.unlock_input(LOCK_SOURCE)
