class_name SequencePuzzle
extends Node
## 「按正确顺序点物品」解谜的裁判：只管顺序对不对、以及对错之后播什么表现。
##
## 物品自己不知道顺序（SequencePuzzleItem 只会亮、会晃），本节点持有 `items`
## 这个**已按正确顺序排列**的列表，所以改谜题答案 = 在编辑器里调数组顺序，
## 不用改代码。
##
## 文字统一发 `text_requested`，由关卡的共用 DialogueBox 显示——和
## TextInteractable / PassageGate 同一条纪律，不自弹 UI。
## 剧情因果（解开之后发生什么）留给 StoryDirector，本节点只落自己的完成 Flag。

signal text_requested(text: String)
## 请关卡把共用对话框收掉（解开之后那句提示自己消失，不用玩家再按空格）。
signal text_dismiss_requested
signal armed
signal wrong_order
signal solved

## 靠近时提示、按 E 启动解谜的交互点（架子本身）。
@export var trigger_path: NodePath
## 解开之后整体平移的那个 Node2D：架子和上面所有物品都挂在它下面。
@export var group_path: NodePath
## 物品，**按正确顺序**排列。
@export var items: Array[NodePath] = []
## 可选的选中音效（占位：没有 stream 时安全跳过）。
@export var select_sound_path: NodePath
## 解谜期间淡出的玩家（留空 = 不管玩家）。丽娘站在架子前会挡住要点的物件，
## 所以解谜一开始把她淡出、结束再淡回来。
@export var player_path: NodePath
## 解开之后落的 Flag，用于读档恢复。留空则不持久化。
@export var flag_to_set: StringName = &""

@export_group("Text")
@export_multiline var arm_text: String = "按顺序检查一下这些架子上的物品吧。"
@export_multiline var wrong_text: String = "好像顺序不太对，要不再试试吧。"
@export_multiline var solved_text: String = ""

@export_group("Motion")
## 解开之后整组平移的位移量。
@export var move_offset: Vector2 = Vector2(200.0, 0.0)
@export_range(0.0, 10.0, 0.05, "suffix:s") var move_duration: float = 2.4
## 顺序错误时整组一起颤动的幅度与时长。
@export_range(0.0, 40.0, 0.5, "suffix:px") var reset_shake_pixels: float = 7.0
@export_range(0.05, 2.0, 0.01, "suffix:s") var reset_shake_duration: float = 0.4
## 解开之后整组一边右移一边淡出；0 = 不淡出，只移动。
@export_range(0.0, 1.0, 0.01) var solved_final_alpha: float = 0.0
## 玩家淡出 / 淡回的时长。
@export_range(0.0, 3.0, 0.05, "suffix:s") var player_fade_duration: float = 0.5

const PLAYER_LOCK := &"sequence_puzzle"

var _trigger: Interactable = null
var _group: Node2D = null
var _player: Node2D = null
var _player_tween: Tween = null
var _sound: AudioStreamPlayer = null
var _items: Array[SequencePuzzleItem] = []
## 已经按对的个数 = 下一个该点的下标。
var _progress: int = 0
var _is_armed: bool = false
var _is_solved: bool = false
var _group_base_position: Vector2 = Vector2.ZERO
## 交互点原本的碰撞层，禁用后要能还原（调试 / 剧情倒带）。
var _trigger_layer: int = 1
var _tween: Tween = null


func _ready() -> void:
	_trigger = get_node_or_null(trigger_path) as Interactable
	_group = get_node_or_null(group_path) as Node2D
	_sound = get_node_or_null(select_sound_path) as AudioStreamPlayer
	_player = get_node_or_null(player_path) as Node2D
	for path in items:
		var item := get_node_or_null(path) as SequencePuzzleItem
		if item == null:
			push_warning("SequencePuzzle: items 里有接不上的物品: %s" % path)
			continue
		item.selected.connect(_on_item_selected)
		_items.append(item)
	if _group != null:
		_group_base_position = _group.position
	if _trigger != null:
		_trigger_layer = _trigger.collision_layer
		_trigger.interacted.connect(_on_trigger_interacted)
	# 解过的谜题自己恢复终态：这是物件状态，不是剧情判断（PassageGate 同一做法）。
	if flag_to_set != &"" and StoryFlagManager.has_flag(flag_to_set):
		set_solved(true)


# --- 公开 ----------------------------------------------------------------------

func is_armed() -> bool:
	return _is_armed


func is_solved() -> bool:
	return _is_solved


func get_progress() -> int:
	return _progress


## 静默设终态，不播表现、不发信号。读档恢复和调试摆位用。
func set_solved(value: bool) -> void:
	_is_solved = value
	_is_armed = false
	_progress = 0
	_kill_tween()
	for item in _items:
		item.set_armed(false)
	if _group != null:
		_group.position = _group_base_position + (move_offset if value else Vector2.ZERO)
		_group.modulate.a = solved_final_alpha if value else 1.0
	# 解开之后这个探索点彻底不在了：不给提示、不吃交互、不参与碰撞。
	_set_trigger_enabled(not value)


# --- 现场链路 ------------------------------------------------------------------

func _on_trigger_interacted(_player: Node) -> void:
	if _is_solved or _is_armed:
		return
	_is_armed = true
	_progress = 0
	for item in _items:
		item.set_armed(true)
		item.set_highlight(true)
	# 解谜一开始就把「查看架子」这个探索点收掉：解谜期间不该再冒提示，
	# 解开之后它也不会回来（_complete 不再启用它）。
	_set_trigger_enabled(false)
	_set_player_hidden(true)
	armed.emit()
	text_requested.emit(arm_text)


func _on_item_selected(item: SequencePuzzleItem) -> void:
	if not _is_armed or _is_solved:
		return
	_play_select_sound()
	item.nudge()
	if _progress < _items.size() and _items[_progress] == item:
		item.lock_in()
		_progress += 1
		if _progress >= _items.size():
			_complete()
		return
	_fail()


func _fail() -> void:
	_progress = 0
	wrong_order.emit()
	# 集体颤动 = reset 的可读信号：架子和物品一起抖，玩家知道整串清零了。
	_shake_group()
	for item in _items:
		item.reset_selection()
	text_requested.emit(wrong_text)


func _complete() -> void:
	_is_solved = true
	_is_armed = false
	for item in _items:
		item.set_armed(false)
	if flag_to_set != &"":
		StoryFlagManager.set_flag(flag_to_set)
	_slide_group()
	_set_player_hidden(false)
	if solved_text.is_empty():
		# 解开的瞬间「按顺序检查…」这句提示已经没用了，自动收掉。
		text_dismiss_requested.emit()
	else:
		text_requested.emit(solved_text)
	solved.emit()


# --- 表现 ----------------------------------------------------------------------

func _slide_group() -> void:
	if _group == null:
		return
	_kill_tween()
	var target := _group_base_position + move_offset
	if move_duration <= 0.0:
		_group.position = target
		_group.modulate.a = solved_final_alpha
		return
	# 位移和淡出同时进行：架子一边往右挪一边消失。
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_group, ^"position", target, move_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_group, ^"modulate:a", solved_final_alpha, move_duration).set_trans(Tween.TRANS_SINE)



func _shake_group() -> void:
	if _group == null:
		return
	_kill_tween()
	var base := _group.position
	_tween = create_tween()
	var beat: float = reset_shake_duration / 4.0
	for offset in [reset_shake_pixels, -reset_shake_pixels * 0.7, reset_shake_pixels * 0.4]:
		_tween.tween_property(_group, ^"position",
			base + Vector2(offset, 0.0), beat).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_group, ^"position", base, beat).set_trans(Tween.TRANS_SINE)


## 开关架子那个探索点。禁用 = 提示、交互、碰撞一起没有，视觉也隐掉。
## **不 queue_free**：和 PassageGate 一样保持可逆，调试和剧情倒带还能开回来。
func _set_trigger_enabled(enabled: bool) -> void:
	if _trigger == null:
		return
	_trigger.monitoring = enabled
	_trigger.monitorable = enabled
	_trigger.input_pickable = enabled
	_trigger.collision_layer = _trigger_layer if enabled else 0
	_trigger.visible = enabled
	# 玩家可能正站在范围内。Godot 不保证为「运行时改碰撞层」补发 area_exited，
	# InteractionDetector 为此留了 refresh_overlaps()，这里用它重同步一次。
	_refresh_player_detector()


func _refresh_player_detector() -> void:
	if _player == null:
		return
	for child in _player.get_children():
		if child is InteractionDetector:
			child.call_deferred("refresh_overlaps")


## 解谜期间把玩家淡出（渐进渐出），同时锁住输入——人看不见了就不该还能走。
func _set_player_hidden(hidden: bool) -> void:
	if _player == null:
		return
	if hidden:
		if _player.has_method("begin_interaction"):
			_player.call("begin_interaction", PLAYER_LOCK)
	else:
		if _player.has_method("end_interaction"):
			_player.call("end_interaction", PLAYER_LOCK)
	var target_alpha: float = 0.0 if hidden else 1.0
	if _player_tween != null and _player_tween.is_valid():
		_player_tween.kill()
	if player_fade_duration <= 0.0:
		_player.modulate.a = target_alpha
		return
	_player_tween = create_tween()
	_player_tween.tween_property(_player, ^"modulate:a", target_alpha, player_fade_duration).set_trans(Tween.TRANS_SINE)


func _play_select_sound() -> void:
	# 占位音效：场景里挂了 AudioStreamPlayer 但还没给 stream 时安全跳过。
	if _sound != null and _sound.stream != null:
		_sound.play()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _exit_tree() -> void:
	_kill_tween()
	if _player_tween != null and _player_tween.is_valid():
		_player_tween.kill()
