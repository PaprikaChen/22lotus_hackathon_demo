extends CanvasLayer
## Bottom-of-screen dialogue / interaction text box (graybox), PAGED:
## show_text() splits the text into sentences (one per line), displays one at
## a time; ui_accept (Space) advances, and after the last line the box hides.
##
## While the box is open the player is held with the source-based input lock
## ("dialogue_box", via begin_interaction so the state shows INTERACT) — so
## Space advances text instead of jumping, and world interaction pauses.
## Optional portrait (left) and speaker name for dialogue use. Runs while the
## tree is paused so future paused dialogue flows keep working.

signal line_shown(line: String)
signal closed
## 玩家选完之后发，参数是选项下标（0 = 第一个）。
signal choice_selected(index: int)

const LOCK_SOURCE := &"dialogue_box"

## Player to lock while the box is open (optional).
@export var player_path: NodePath

@onready var _panel: Control = $Root/Panel
@onready var _portrait: TextureRect = $Root/Panel/Margin/HBox/Portrait
@onready var _speaker_label: Label = $Root/Panel/Margin/HBox/TextColumn/SpeakerLabel
@onready var _text_label: Label = $Root/Panel/Margin/HBox/TextColumn/TextLabel
@onready var _continue_hint: Label = $Root/Panel/ContinueHint
@onready var _choice_list: VBoxContainer = $Root/Panel/Margin/HBox/TextColumn/ChoiceList

var _lines: PackedStringArray = []
var _line_index: int = 0
var _player: Node = null

## 选择态：文字放完之后不关框，改成等玩家选。
var _options: PackedStringArray = []
var _choice_index: int = 0
var _choosing: bool = false

# Rising-edge tracking (project convention; see AGENTS.md).
var _accept_held: bool = false
var _up_held: bool = false
var _down_held: bool = false
var _cancel_held: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.visible = false
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

## Splits `text` into non-empty lines and shows the first one. `portrait`
## and `speaker` are optional (dialogue use). Calling again while open
## replaces the content.
func show_text(text: String, portrait: Texture2D = null, speaker: String = "") -> void:
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
	_panel.visible = true
	_portrait.texture = portrait
	_portrait.visible = portrait != null
	_speaker_label.text = speaker
	_speaker_label.visible = not speaker.is_empty()
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
		_panel.visible = true
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
	_panel.visible = false
	_lines = PackedStringArray()
	_exit_choice_mode()
	_unlock_player()
	closed.emit()


func is_showing() -> bool:
	return _panel.visible


## The line currently on screen ("" when hidden).
func get_current_text() -> String:
	return _text_label.text if _panel.visible else ""


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
		label.add_theme_font_size_override(&"font_size", 20)
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
