extends StoryDirector
## courtyard_04 的剧情编排：首次靠近花圃时触发甜香与短暂失焦，之后开放花圃调查。

const FLAG_SWEET_SCENT_ENCOUNTERED := &"courtyard_04.sweet_scent_encountered"
const DIZZY_LOCK := &"courtyard_04_dizzy"
const SPEAKER_LINIANG := "丽娘"
const FIRST_SCENT_TEXT := "那股甜香再次飘来。"
const FLOWER_DIALOGUE := "住在这院里的人……每日都闻得到吗？"
const WINDOW_QUESTION := "这扇窗户破旧到摇摇欲坠。要翻窗户进去吗？"
const INTERIOR_01_SCENE := "res://scenes/levels/interior_01.tscn"

@onready var _courtyard: CourtyardLevel = get_node(level_path) as CourtyardLevel
@onready var _player: Player = get_node_or_null(^"../Player") as Player
@onready var _dialogue: Node = get_node_or_null(^"../DialogueBox")
@onready var _scent_trigger: Area2D = get_node_or_null(^"../Props/SweetScentTrigger") as Area2D
@onready var _flower_investigation: Interactable = \
	get_node_or_null(^"../Props/FlowerInvestigation") as Interactable
@onready var _broken_window: Interactable = \
	get_node_or_null(^"../Props/BrokenWindowInvestigation") as Interactable
@onready var _focus_blur: FocusBlur = get_node_or_null(^"../FocusBlur") as FocusBlur

var _investigation_followup_pending: bool = false
var _window_choice_pending: bool = false


func _connect_actors() -> void:
	if _scent_trigger != null:
		_scent_trigger.body_entered.connect(_on_scent_trigger_entered)
	if _flower_investigation != null:
		_flower_investigation.interacted.connect(_on_flower_investigated)
	if _broken_window != null:
		_broken_window.interacted.connect(_on_broken_window_investigated)


func _restore_story_state() -> void:
	_apply_scent_encounter()


func _on_story_ready() -> void:
	if _courtyard != null:
		_courtyard.autosave()


func _on_scent_trigger_entered(body: Node2D) -> void:
	if body is not Player or StoryFlagManager.has_flag(FLAG_SWEET_SCENT_ENCOUNTERED):
		return
	StoryFlagManager.set_flag(FLAG_SWEET_SCENT_ENCOUNTERED)
	_apply_scent_encounter()
	_run_scent_encounter(body as Player)


func _run_scent_encounter(player: Player) -> void:
	await _show_text_and_wait(FIRST_SCENT_TEXT)
	if player != null:
		player.begin_interaction(DIZZY_LOCK)
	if _focus_blur != null:
		await _focus_blur.pulse()
	if player != null:
		player.end_interaction(DIZZY_LOCK)
	if _courtyard != null:
		_courtyard.autosave()


func _on_flower_investigated(_player_node: Node) -> void:
	# TextInteractable 已经先让关卡打开了解释字幕；这里只编排字幕关闭后的对白。
	if _investigation_followup_pending or _dialogue == null:
		return
	_investigation_followup_pending = true
	await Signal(_dialogue, &"closed")
	_investigation_followup_pending = false
	_dialogue.call("show_text", FLOWER_DIALOGUE, null, SPEAKER_LINIANG)


func _on_broken_window_investigated(_player_node: Node) -> void:
	if _window_choice_pending or _dialogue == null or not _dialogue.has_method("ask"):
		return
	_window_choice_pending = true
	var choice: int = int(await _dialogue.call(
		"ask",
		WINDOW_QUESTION,
		PackedStringArray(["是", "否"])))
	_window_choice_pending = false
	if choice == 0 and _courtyard != null:
		_courtyard.go_to_next_level(INTERIOR_01_SCENE)


func _apply_scent_encounter() -> void:
	var encountered := StoryFlagManager.has_flag(FLAG_SWEET_SCENT_ENCOUNTERED)
	_set_area_active(_scent_trigger, not encountered)
	_set_area_active(_flower_investigation, encountered)
	if encountered:
		_refresh_flower_target_after_physics()
	if not encountered and _focus_blur != null:
		_focus_blur.reset()


func _refresh_flower_target_after_physics() -> void:
	# 碰撞启用是 deferred 的，等下一物理帧后再补登记；否则玩家已经站在范围内时
	# InteractionDetector 收不到 area_entered，EyeAnchor 对应的眼睛 UI 不会出现。
	await get_tree().physics_frame
	await get_tree().physics_frame
	if _player == null:
		return
	var detector := _player.get_node_or_null(^"InteractionDetector") as InteractionDetector
	if detector != null:
		detector.refresh_overlaps()


func _set_area_active(area: Area2D, active: bool) -> void:
	if area == null:
		return
	area.visible = active
	# 这个函数会从 body_entered 回调里调用；Godot 禁止在 in/out 信号处理中
	# 立即改监测状态，因此三项碰撞状态统一 deferred。
	area.set_deferred(&"monitoring", active)
	area.set_deferred(&"monitorable", active)
	var collision := area.get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if collision != null:
		collision.set_deferred(&"disabled", not active)


func _show_text_and_wait(text: String) -> void:
	if _dialogue == null or not _dialogue.has_method("show_text"):
		return
	_dialogue.call("show_text", text)
	await Signal(_dialogue, &"closed")
