class_name RotaryLockUI
extends CanvasLayer
## 三重旋锁的界面 + 判定。数值一律来自 `InnerGateLockConfig`。
##
## 职责边界：
##   · 开 / 关界面，开着时 `paused = true` + 玩家输入锁（来源 `rotary_lock`，
##     只释放自己那一把，参照 `memory_box_ui.gd` 的做法）；
##   · 把鼠标按下的点按 **内 → 中 → 外** 的顺序问三层的 `contains_point()`，
##     命中谁就只拖谁——外层的四个花瓣因此不会盖住中层和内层；
##   · 收三层的 `detent_stepped`，按「层 / 方向 / 档数」的输入序列判定谜底；
##   · 档位音效和开锁音效是**两个独立**的 AudioStreamPlayer 事件。
##
## **它不碰门、不写 Flag、不切场景**：成功只发 `solved`，后果由 StoryDirector
## 决定（AGENTS.md §5.5）。主动关闭发 `closed`，不算成功、不改门的状态。
##
## 判定依据是逐档输入序列，不是三层的最终角度 —— 正反来回转不可能靠净角度
## 碰巧绕过顺序。

signal opened
signal closed ## 关闭（无论成功与否）
signal solved ## 完整正确序列，只发一次

const LOCK_SOURCE := &"rotary_lock"

## 被锁界面暂停 / 锁住的玩家（可留空，纯 UI 测试场景用）。
@export var player_path: NodePath
@export_group("Nodes")
@export var outer_ring_path: NodePath = ^"Root/LockCenter/OuterRing"
@export var middle_ring_path: NodePath = ^"Root/LockCenter/MiddleRing"
@export var inner_ring_path: NodePath = ^"Root/LockCenter/InnerRing"
@export var lock_center_path: NodePath = ^"Root/LockCenter"
@export var close_button_path: NodePath = ^"Root/CloseButton"
@export var hint_label_path: NodePath = ^"Root/HintLabel"
@export_group("Audio")
## 档位「咔哒」。**占位为空**：没挂资源时安全跳过，不影响功能。
@export var detent_sfx: AudioStream = null
## 开锁成功音。和档位音是不同事件，不要复用同一个 player。
@export var unlock_sfx: AudioStream = null

var _player: Node = null
var _center: Control = null
var _hint: Label = null
## 命中询问顺序：内 → 中 → 外。
var _rings: Array[RotaryLockRing] = []
var _rings_by_id: Dictionary = {}
var _detent_player: AudioStreamPlayer = null
var _unlock_player: AudioStreamPlayer = null

var _is_open: bool = false
var _was_paused: bool = false
var _is_solved: bool = false
## 正在播成功演出：期间禁止拖动、禁止再次判定。
var _is_finishing: bool = false
var _dragging_ring: RotaryLockRing = null

## 判定进度：当前在谜底的第几步、这一步已经走了几档。
var _step_index: int = 0
var _step_count: int = 0

var _cancel_held: bool = false
var _feedback_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_player = get_node_or_null(player_path)
	_center = get_node_or_null(lock_center_path) as Control
	_hint = get_node_or_null(hint_label_path) as Label
	_collect_rings()
	_build_audio()
	var close_button := get_node_or_null(close_button_path) as BaseButton
	if close_button != null:
		close_button.pressed.connect(close)
	_reset_progress()


func _collect_rings() -> void:
	# 顺序即命中优先级：小的图形先问，外层最后。
	for path in [inner_ring_path, middle_ring_path, outer_ring_path]:
		var ring := get_node_or_null(path) as RotaryLockRing
		if ring == null:
			push_warning("RotaryLockUI: 找不到锁的一层：%s" % path)
			continue
		_rings.append(ring)
		_rings_by_id[ring.layer_id] = ring
		ring.detent_stepped.connect(_on_detent_stepped.bind(ring))


func _build_audio() -> void:
	# 两个独立的 Audio Source：换正式素材只需要给导出属性挂 stream，
	# 谜题逻辑一行不用改。
	_detent_player = AudioStreamPlayer.new()
	_detent_player.name = "DetentSfx"
	_detent_player.stream = detent_sfx
	add_child(_detent_player)
	_unlock_player = AudioStreamPlayer.new()
	_unlock_player.name = "UnlockSfx"
	_unlock_player.stream = unlock_sfx
	add_child(_unlock_player)


# --- 开关 ---------------------------------------------------------------------

func is_open() -> bool:
	return _is_open


func is_solved() -> bool:
	return _is_solved


## 按 layer_id 取一层（`InnerGateLockConfig.LAYER_*`）。回归测试和调试用。
func get_ring(layer_id: StringName) -> RotaryLockRing:
	return _rings_by_id.get(layer_id, null) as RotaryLockRing


## 当前在谜底的第几步（0 起）。
func get_progress_step() -> int:
	return _step_index


## 当前这一步已经走了几档。
func get_progress_count() -> int:
	return _step_count


## 单一闸门：对话 / 过场 / 梦奁都持玩家输入锁，所以这里一句就够，
## 不用到处补各系统的判断。
func can_open() -> bool:
	if _is_open or _is_solved:
		return false
	if _player != null and _player.has_method("is_input_locked") and _player.is_input_locked():
		return false
	return true


func open() -> void:
	if not can_open():
		return
	_is_open = true
	visible = true
	_reset_progress()
	for ring in _rings:
		ring.set_input_locked(false)
	if _player != null and _player.has_method("lock_input"):
		_player.lock_input(LOCK_SOURCE)
	_was_paused = get_tree().paused
	get_tree().paused = true
	opened.emit()


## 关闭。主动关闭**不算成功**，也不改门的状态。
func close() -> void:
	if not _is_open:
		return
	_end_drag(true)
	_is_open = false
	visible = false
	get_tree().paused = _was_paused
	if _player != null and _player.has_method("unlock_input"):
		_player.unlock_input(LOCK_SOURCE)
	closed.emit()


## 读档 / 进关恢复：门已经开过了，锁不该再能玩。幂等。
func set_solved(value: bool) -> void:
	_is_solved = value
	for ring in _rings:
		ring.set_input_locked(value)


# --- 输入 ---------------------------------------------------------------------

func _process(_delta: float) -> void:
	# Esc 关闭。用轮询 + 手动上升沿，和项目其余输入检测保持一致
	# （AGENTS.md §2：MCP 注入不产生 just_pressed 边沿）。
	var cancel := Input.is_action_pressed("ui_cancel")
	if cancel and not _cancel_held and _is_open:
		close()
	_cancel_held = cancel


func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_try_begin_drag(_to_canvas(button.position))
		else:
			_end_drag(false)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging_ring != null:
		_dragging_ring.update_drag(_to_canvas((event as InputEventMouseMotion).position))
		get_viewport().set_input_as_handled()


## 鼠标事件的坐标是视口（已按 canvas_items 拉伸换算）坐标；本层没有额外
## 变换，所以直接就是各层 Node2D 所在的画布坐标。留一层函数是为了以后
## 万一给 CanvasLayer 加了 offset/scale 只改这里。
func _to_canvas(position: Vector2) -> Vector2:
	return transform.affine_inverse() * position


func _try_begin_drag(point: Vector2) -> void:
	if _is_solved or _is_finishing:
		return
	for ring in _rings:
		if ring.contains_point(point) and ring.begin_drag(point):
			_dragging_ring = ring
			return


func _end_drag(cancelled: bool) -> void:
	if _dragging_ring == null:
		return
	var ring := _dragging_ring
	# 先清引用：end_drag() 可能同步发出最后一档，回调里不该看到还在拖的状态。
	_dragging_ring = null
	if cancelled:
		ring.cancel_drag()
	else:
		ring.end_drag()


func _notification(what: int) -> void:
	# 失焦（切窗口）时安全结束拖拽，未完成的一段回弹、不计数。
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_end_drag(true)


# --- 判定 ---------------------------------------------------------------------

func _reset_progress() -> void:
	_step_index = 0
	_step_count = 0


func _on_detent_stepped(direction: int, ring: RotaryLockRing) -> void:
	# 每跨一档一次「咔哒」，和最终开锁音是两个事件。
	_play(_detent_player)
	if _is_solved or _is_finishing:
		return
	var expected: Dictionary = InnerGateLockConfig.SOLUTION[_step_index]
	if ring.layer_id != expected["layer"] or direction != int(expected["direction"]):
		InnerGateLockConfig.log_debug(
			"输入 %s/%+d 与第 %d 步 (%s/%+d) 不符 → 本轮失败"
			% [ring.layer_id, direction, _step_index, expected["layer"], expected["direction"]])
		_on_wrong_input()
		return
	_step_count += 1
	InnerGateLockConfig.log_debug("第 %d 步 %s 进度 %d/%d"
		% [_step_index, ring.layer_id, _step_count, expected["steps"]])
	if _step_count < int(expected["steps"]):
		return
	# 本步走满 → 进入下一步。下一次有效档位输入必须属于下一层，
	# 继续拨这一层就会在上面的层判定里失败（= 次数过多）。
	_step_index += 1
	_step_count = 0
	if _step_index >= InnerGateLockConfig.SOLUTION.size():
		_on_solved()


func _on_wrong_input() -> void:
	_reset_progress()
	_play_failure_feedback()


func _on_solved() -> void:
	_is_solved = true
	_is_finishing = true
	for ring in _rings:
		ring.set_input_locked(true)
	_play(_unlock_player)
	if _hint != null:
		_hint.text = "锁芯落下了。"
	# 成功演出：三层归零对齐 + 轻微发光。
	for ring in _rings:
		ring.set_detent_index(0, true)
	if _center != null:
		_kill_feedback_tween()
		_feedback_tween = create_tween()
		_feedback_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_feedback_tween.tween_property(_center, "modulate",
			Color(1.6, 1.55, 1.3, 1.0), InnerGateLockConfig.SUCCESS_SECONDS * 0.5)
		_feedback_tween.tween_property(_center, "modulate",
			Color.WHITE, InnerGateLockConfig.SUCCESS_SECONDS * 0.5)
	await get_tree().create_timer(
		InnerGateLockConfig.SUCCESS_SECONDS, true, false, true).timeout
	_is_finishing = false
	solved.emit()
	close()


## 失败反馈：轻微但明确的一下抖动。不改三层的视觉角度——重置的是「答案进度」，
## 不是玩家已经拨到的位置。
func _play_failure_feedback() -> void:
	if _center == null:
		return
	_kill_feedback_tween()
	var origin := _center.position
	_feedback_tween = create_tween()
	_feedback_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var quarter := InnerGateLockConfig.FAILURE_SECONDS * 0.25
	_feedback_tween.tween_property(_center, "position", origin + Vector2(7, 0), quarter)
	_feedback_tween.tween_property(_center, "position", origin - Vector2(7, 0), quarter)
	_feedback_tween.tween_property(_center, "position", origin + Vector2(4, 0), quarter)
	_feedback_tween.tween_property(_center, "position", origin, quarter)


func _kill_feedback_tween() -> void:
	if _feedback_tween != null and _feedback_tween.is_valid():
		_feedback_tween.kill()
	_feedback_tween = null


func _play(player: AudioStreamPlayer) -> void:
	# 没挂占位音频时静默降级，不 push_warning 刷屏。
	if player != null and player.stream != null:
		player.play()


func _exit_tree() -> void:
	_kill_feedback_tween()
	# 卸载时把暂停和输入锁还回去，别跨场景残留。
	if _is_open:
		get_tree().paused = _was_paused
		if _player != null and _player.has_method("unlock_input"):
			_player.unlock_input(LOCK_SOURCE)
		_is_open = false
