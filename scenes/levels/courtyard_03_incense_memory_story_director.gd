extends StoryDirector
## courtyard_03 香炉记忆的对白编排。
##
## 三个调查点严格按“香炉 → 木马 → 岁安绦”依次开放；每段内部按“对白 → 旁白”
## 播放。全部完成后写入结果、挂起返回对白标记，以白幕返回主庭院。

const FLAG_MEMORY_FINISHED := &"courtyard_03.incense_memory_finished"
const FLAG_RETURN_PENDING := &"courtyard_03.incense_memory_return_pending"
const MEMORY_DIALOGUE_LOCK := &"incense_memory_dialogue"

const CHILD_LINIANG := "幼年丽娘"
const CHILD_CHUNXIANG := "幼年春香"
const ADULT_LINIANG := "丽娘"

@export var dialogue_box_path: NodePath
@export var white_fade_path: NodePath
@export var narration_overlay_path: NodePath
@export var player_path: NodePath

@onready var _memory_level: Courtyard03IncenseMemoryLevel = get_node(level_path) as Courtyard03IncenseMemoryLevel
@onready var _dialogue: Node = get_node_or_null(dialogue_box_path)
@onready var _white_fade: ScreenFade = get_node_or_null(white_fade_path) as ScreenFade
@onready var _narration: NarrationOverlay = get_node_or_null(narration_overlay_path) as NarrationOverlay
@onready var _player: Node = get_node_or_null(player_path)
@onready var _incense: Interactable = get_node_or_null(^"../Props/IncenseMemory") as Interactable
@onready var _wooden_horse: Interactable = get_node_or_null(^"../Props/WoodenHorseMemory") as Interactable
@onready var _prayer_cloth: Interactable = get_node_or_null(^"../Props/PrayerClothMemory") as Interactable

var _incense_done: bool = false
var _horse_done: bool = false
var _cloth_done: bool = false
var _playing: bool = false


func _connect_actors() -> void:
	if _incense != null:
		_incense.interacted.connect(_on_incense_interacted)
	if _wooden_horse != null:
		_wooden_horse.interacted.connect(_on_wooden_horse_interacted)
	if _prayer_cloth != null:
		_prayer_cloth.interacted.connect(_on_prayer_cloth_interacted)


func _restore_story_state() -> void:
	_apply_interaction_order()


func _on_story_ready() -> void:
	_lock_player(_player)
	if _white_fade != null:
		_white_fade.set_opaque(true)
		await _white_fade.fade_in()
	_unlock_player(_player)


func _on_incense_interacted(player: Node) -> void:
	if _playing or _incense_done:
		return
	_playing = true
	_lock_player(player)
	await _begin_scene_text()
	await _show_text("春香，去世的人，还会回来吗？", CHILD_LINIANG)
	await _show_text("不会呀。", CHILD_CHUNXIANG)
	await _show_text("可香一点，她就来了。\n香灭了，就又不见了。", CHILD_LINIANG)
	await _show_text(
		"从三岁到五岁，这炉香总在丽娘生辰燃起。\n"
		+ "\n"
		+ "那段记忆里，总有一个模糊而亲切的面孔。")
	# 成年丽娘是「现在的自己」在回望，用普通对话框 + 立绘把她和白幕里的
	# 幼年记忆区分开——所以先把白幕收掉再说这句。
	await _end_scene_text()
	await _show_dialogue_box("这声音……是我？", ADULT_LINIANG)
	_incense_done = true
	await _finish_interaction(player)


func _on_wooden_horse_interacted(player: Node) -> void:
	if _playing or _horse_done or not _incense_done:
		return
	_playing = true
	_lock_player(player)
	await _begin_scene_text()
	await _show_text("她陪你做什么？", CHILD_CHUNXIANG)
	await _show_text("量个子，陪我骑马。\n还讲江州的雨，岷山的雪。", CHILD_LINIANG)
	await _show_text("她是谁呀？", CHILD_CHUNXIANG)
	await _show_text("幼年丽娘想了很久。")
	await _show_text("我不记得了。", CHILD_LINIANG)
	await get_tree().create_timer(0.7).timeout
	await _show_text("可她认得我。", CHILD_LINIANG)
	await _show_text(
		"三道刻痕，记下丽娘三岁、四岁、五岁的身高。\n"
        + "\n"
		+ "有人陪她长大，也把未走完的山河讲给她听。")
	_horse_done = true
	await _finish_interaction(player)


func _on_prayer_cloth_interacted(player: Node) -> void:
	if _playing or _cloth_done or not _horse_done:
		return
	_playing = true
	_lock_player(player)
	await _begin_scene_text()
	await _show_text("明年，她还来吗？", CHILD_CHUNXIANG)
	await _show_text("不来了。", CHILD_LINIANG)
	await _show_text("为什么？", CHILD_CHUNXIANG)
	await _show_text(
		"她说，不能老在梦里待着。\n"
        + "\n"
		+ "还说，看得见也好，看不见也好……\n"
        + "\n"
		+ "我好好的，她就放心了。", CHILD_LINIANG)
	await _show_text(
		"最后一次生辰，那人没有留下姓名，也没有再许下来年。\n"
        + "\n"
        + "褪色的布条在风中轻轻摇曳，上面写着：\n"
        + "\n"
		+ "“愿丽娘岁岁平安。”")
	_cloth_done = true
	await _finish_interaction(player)


func _finish_interaction(player: Node) -> void:
	await _end_scene_text()
	_apply_interaction_order()
	if not (_incense_done and _horse_done and _cloth_done):
		_playing = false
		_unlock_player(player)
		return
	StoryFlagManager.set_flag(FLAG_MEMORY_FINISHED)
	StoryFlagManager.set_flag(FLAG_RETURN_PENDING)
	if _white_fade != null:
		await _white_fade.fade_out()
	if _memory_level == null or not _memory_level.return_to_courtyard():
		_playing = false
		_unlock_player(player)
		if _white_fade != null:
			await _white_fade.fade_in()


func _apply_interaction_order() -> void:
	_set_interactable_active(_incense, not _incense_done)
	_set_interactable_active(_wooden_horse, _incense_done and not _horse_done)
	_set_interactable_active(_prayer_cloth, _horse_done and not _cloth_done)


func _set_interactable_active(interactable: Interactable, active: bool) -> void:
	if interactable == null:
		return
	interactable.visible = active
	interactable.monitoring = active
	interactable.monitorable = active
	var collision := interactable.get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	if collision != null:
		collision.set_deferred(&"disabled", not active)


## 本关的幼年记忆（幼年对白 + 旁白）都在白幕上呈现；只有成年丽娘那句回望走
## 常规对话框，见 _show_dialogue_box()。
## `speaker` 为空即旁白；白幕由 _begin_scene_text() / _end_scene_text() 统一
## 开合，一次交互里的所有句子共用同一块白幕。
func _show_text(text: String, speaker: String = "") -> void:
	if _narration != null:
		await _narration.show_line(text, speaker)
		return
	# 没挂白幕件时退化成对话框，流程不能因为缺一个表现件就卡住。
	await _show_dialogue_box(text, speaker)


## 走关卡常规的对话框（带立绘）。白幕演出之外的少数句子用它。
func _show_dialogue_box(text: String, speaker: String = "") -> void:
	if _dialogue == null or not _dialogue.has_method("show_text"):
		return
	_dialogue.call("show_text", text, null, speaker)
	await Signal(_dialogue, &"closed")


func _begin_scene_text() -> void:
	if _narration != null:
		await _narration.begin_session()


func _end_scene_text() -> void:
	if _narration != null:
		await _narration.end_session()


func _lock_player(player: Node) -> void:
	if player != null and player.has_method("begin_interaction"):
		player.call("begin_interaction", MEMORY_DIALOGUE_LOCK)


func _unlock_player(player: Node) -> void:
	if player != null and player.has_method("end_interaction"):
		player.call("end_interaction", MEMORY_DIALOGUE_LOCK)
