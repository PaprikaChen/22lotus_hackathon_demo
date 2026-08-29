extends StoryDirector
## courtyard_03 的剧情编排骨架。
##
## 负责三个调查点触发的丽娘对白，并在关卡状态恢复完成后自动存档。

const SPEAKER_LINIANG := "丽娘"
const FLAG_LANTERNS_CHANGED := &"courtyard_03.lanterns_changed"
const FLAG_INCENSE_MEMORY_FINISHED := &"courtyard_03.incense_memory_finished"
const FLAG_INCENSE_RETURN_PENDING := &"courtyard_03.incense_memory_return_pending"
const LANTERN_CHANGE_LOCK := &"lantern_change"
const INCENSE_MEMORY_LOCK := &"incense_memory"
const INCENSE_MEMORY_SCENE := "res://scenes/levels/courtyard_03_incense_memory.tscn"
const RETURN_DIALOGUE := "原来……\n竟也有人这样盼过我。"
const INVESTIGATION_01_TEXT := "我方才是不是……已经路过这里了？"
const INVESTIGATION_02_TEXT := "这个佛像是在盯着我看吗……"
const INVESTIGATION_03_TEXT := "似乎是某人的墓碑。"
## 从香炉记忆回来时玩家落回的横坐标。回忆是在灯笼区触发的，回来后要站到
## 这里继续往前，所以不沿用存档里的进入坐标。
const RETURN_POSITION_X := 4500.0
## 香炉记忆做完之前，画面右缘和玩家都停在这里：右边的院子先不给看。
## 回忆结束后闸门和挡墙一起撤掉。
const RIGHT_GATE_X := 7900

@export var dialogue_box_path: NodePath
@export var screen_fade_path: NodePath
@export var white_fade_path: NodePath
@export var player_path: NodePath
@export var camera_path: NodePath = ^"../FollowCamera2D"
@export var right_gate_wall_path: NodePath = ^"../Bounds/GateWallRight"
@export var lantern_one_changed_texture: Texture2D
@export var lantern_two_changed_texture: Texture2D

@onready var _courtyard: CourtyardLevel = get_node(level_path) as CourtyardLevel
@onready var _dialogue: Node = get_node_or_null(dialogue_box_path)
@onready var _player: Node2D = get_node_or_null(player_path) as Node2D
@onready var _investigation_01: Interactable = get_node_or_null(^"../Props/InvestigationPoint01") as Interactable
@onready var _investigation_02: Interactable = get_node_or_null(^"../Props/InvestigationPoint02") as Interactable
@onready var _investigation_03: Interactable = get_node_or_null(^"../Props/InvestigationPoint03") as Interactable
@onready var _lantern_change_trigger: Interactable = get_node_or_null(^"../Props/LanternChangeTrigger") as Interactable
@onready var _lantern_clue_01: Interactable = get_node_or_null(^"../Props/LanternClue01") as Interactable
@onready var _lantern_clue_02: Interactable = get_node_or_null(^"../Props/LanternClue02") as Interactable
@onready var _lantern_clue_03: Interactable = get_node_or_null(^"../Props/LanternClue03") as Interactable
@onready var _incense_memory_trigger: Interactable = get_node_or_null(^"../Props/IncenseMemoryTrigger") as Interactable
@onready var _lantern_one_art: Sprite2D = get_node_or_null(^"../Lanterns/LanternOne/Art") as Sprite2D
@onready var _lantern_two_art: Sprite2D = get_node_or_null(^"../Lanterns/LanternTwo/Art") as Sprite2D
@onready var _screen_fade: ScreenFade = get_node_or_null(screen_fade_path) as ScreenFade
@onready var _white_fade: ScreenFade = get_node_or_null(white_fade_path) as ScreenFade
@onready var _camera: FollowCamera2D = get_node_or_null(camera_path) as FollowCamera2D
@onready var _right_gate_wall: StaticBody2D = get_node_or_null(right_gate_wall_path) as StaticBody2D

var _lantern_one_original_texture: Texture2D = null
var _lantern_two_original_texture: Texture2D = null


func _connect_actors() -> void:
	if _lantern_one_art != null:
		_lantern_one_original_texture = _lantern_one_art.texture
	if _lantern_two_art != null:
		_lantern_two_original_texture = _lantern_two_art.texture
	if _investigation_01 != null:
		_investigation_01.interacted.connect(_on_investigation_01)
	if _investigation_02 != null:
		_investigation_02.interacted.connect(_on_investigation_02)
	if _investigation_03 != null:
		_investigation_03.interacted.connect(_on_investigation_03)
	if _lantern_change_trigger != null:
		_lantern_change_trigger.interacted.connect(_on_lantern_change_triggered)
	if _incense_memory_trigger != null:
		_incense_memory_trigger.interacted.connect(_on_incense_memory_triggered)


func _restore_story_state() -> void:
	_apply_lantern_change()
	_apply_incense_memory_availability()
	_apply_right_gate()


func _on_story_ready() -> void:
	if StoryFlagManager.has_flag(FLAG_INCENSE_RETURN_PENDING):
		_finish_incense_memory_return()
	elif _courtyard != null:
		_courtyard.autosave()


func _on_investigation_01(_player: Node) -> void:
	_show_liniang_dialogue(INVESTIGATION_01_TEXT)


func _on_investigation_02(_player: Node) -> void:
	_show_liniang_dialogue(INVESTIGATION_02_TEXT)


func _on_investigation_03(_player: Node) -> void:
	_show_liniang_dialogue(INVESTIGATION_03_TEXT)


func _on_lantern_change_triggered(player: Node) -> void:
	if StoryFlagManager.has_flag(FLAG_LANTERNS_CHANGED):
		return
	_lock_player(player)
	if _screen_fade != null:
		await _screen_fade.fade_out()
	StoryFlagManager.set_flag(FLAG_LANTERNS_CHANGED)
	_apply_lantern_change()
	_apply_incense_memory_availability()
	if _screen_fade != null:
		await _screen_fade.fade_in()
	_unlock_player(player)
	if _courtyard != null:
		_courtyard.autosave()


func _on_incense_memory_triggered(player: Node) -> void:
	if not StoryFlagManager.has_flag(FLAG_LANTERNS_CHANGED) \
			or StoryFlagManager.has_flag(FLAG_INCENSE_MEMORY_FINISHED):
		return
	_lock_player_with_source(player, INCENSE_MEMORY_LOCK)
	if _white_fade != null:
		await _white_fade.fade_out()
	if _courtyard == null or not _courtyard.go_to_temporary_scene(INCENSE_MEMORY_SCENE):
		if _white_fade != null:
			await _white_fade.fade_in()
		_unlock_player_with_source(player, INCENSE_MEMORY_LOCK)


func _finish_incense_memory_return() -> void:
	# 趁白幕还全白先挪人：玩家看不到这一下瞬移，相机没开平滑也会跟着到位。
	_place_player_at_return_point()
	if _white_fade != null:
		_white_fade.set_opaque(true)
		await _white_fade.fade_in()
	StoryFlagManager.clear_flag(FLAG_INCENSE_RETURN_PENDING)
	_apply_right_gate()
	if _dialogue != null and _dialogue.has_method("show_text"):
		_dialogue.call("show_text", RETURN_DIALOGUE, null, SPEAKER_LINIANG)
		var closed_signal: Signal = Signal(_dialogue, &"closed")
		await closed_signal
	if _courtyard != null:
		_courtyard.autosave()


func _place_player_at_return_point() -> void:
	if _player == null:
		return
	# 只改横坐标：纵坐标沿用进入回忆时的地面高度，免得凭空猜一个 y。
	_player.global_position = Vector2(RETURN_POSITION_X, _player.global_position.y)
	if _player.has_method("set_spawn_point"):
		_player.call("set_spawn_point", _player.global_position)


## 幂等摆终态：现场演出和读档恢复共用；这里不播放黑屏。
##
## 灯笼区一共三态，全部由 Flag 决定，不留参数——省得调用方各自判断：
##   · 未调查        原版美术，只开「调查灯笼」；
##   · 已变          换版美术，开三个线索调查点；
##   · 香炉回忆结束  美术变回原版，灯笼区所有调查点一律关掉。
func _apply_lantern_change() -> void:
	var changed := StoryFlagManager.has_flag(FLAG_LANTERNS_CHANGED)
	# 回忆做完，灯笼区这条线就结束了：美术复原、调查点收摊。
	var settled := StoryFlagManager.has_flag(FLAG_INCENSE_MEMORY_FINISHED)
	var show_changed_art := changed and not settled
	if _lantern_one_art != null:
		_lantern_one_art.texture = lantern_one_changed_texture if show_changed_art else _lantern_one_original_texture
	if _lantern_two_art != null:
		_lantern_two_art.texture = lantern_two_changed_texture if show_changed_art else _lantern_two_original_texture
	var clues_active := changed and not settled
	_set_interactable_active(_lantern_change_trigger, not changed and not settled)
	_set_interactable_active(_lantern_clue_01, clues_active)
	_set_interactable_active(_lantern_clue_02, clues_active)
	_set_interactable_active(_lantern_clue_03, clues_active)


## 右侧闸门：香炉记忆做完之前画面右缘停在 RIGHT_GATE_X，同时用 Bounds 里的
## 挡墙把人也拦住——相机只管画面，挡人是关卡的事。幂等，读档恢复共用。
func _apply_right_gate() -> void:
	var gated := not StoryFlagManager.has_flag(FLAG_INCENSE_MEMORY_FINISHED)
	if _camera != null:
		if gated:
			_camera.set_right_gate(RIGHT_GATE_X)
		else:
			_camera.release_right_gate()
	if _right_gate_wall != null:
		var collision := _right_gate_wall.get_node_or_null(^"CollisionShape2D") as CollisionShape2D
		if collision != null:
			collision.set_deferred(&"disabled", not gated)


func _apply_incense_memory_availability() -> void:
	var available: bool = (
		StoryFlagManager.has_flag(FLAG_LANTERNS_CHANGED)
		and not StoryFlagManager.has_flag(FLAG_INCENSE_MEMORY_FINISHED))
	_set_interactable_active(_incense_memory_trigger, available)


func _set_interactable_active(interactable: Interactable, active: bool) -> void:
	if interactable == null:
		return
	interactable.visible = active
	interactable.monitoring = active
	interactable.monitorable = active
	var collision := interactable.get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if collision != null:
		collision.set_deferred(&"disabled", not active)


func _lock_player(player: Node) -> void:
	_lock_player_with_source(player, LANTERN_CHANGE_LOCK)


func _unlock_player(player: Node) -> void:
	_unlock_player_with_source(player, LANTERN_CHANGE_LOCK)


func _lock_player_with_source(player: Node, source: StringName) -> void:
	if player != null and player.has_method("begin_interaction"):
		player.call("begin_interaction", source)


func _unlock_player_with_source(player: Node, source: StringName) -> void:
	if player != null and player.has_method("end_interaction"):
		player.call("end_interaction", source)


func _show_liniang_dialogue(text: String) -> void:
	if _dialogue != null and _dialogue.has_method("show_text"):
		_dialogue.call("show_text", text, null, SPEAKER_LINIANG)
