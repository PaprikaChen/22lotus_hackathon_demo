extends StoryDirector
## interior_01 的剧情编排入口。
##
## 目前只编排一段演出：药碗调查点 → 失焦 → 丽娘的一句判断 → 黑幕过渡 →
## 定格 CG 回忆片段 → 黑底解说文字；以及架子解谜解开之后露出的那封信。
## 表现件（FocusBlur / ScreenFade /
## CGSequence / NarrationOverlay）各自只管画面，
## 「什么时候发生什么」全部写在这里（AGENTS.md §5.5）。

const SPEAKER_LINIANG := "丽娘"
## 回忆看过之后落这个 Flag：之后再调查药碗只出那三句旁白，不重播回忆。
const FLAG_MEDICINE_MEMORY_SEEN := &"interior_01.medicine_memory_seen"
const MEMORY_LOCK := &"medicine_memory"
const LINIANG_LINE := "“药里的，是浮游花。”"
const STONE_DETAIL_TEXT := "纸上写着：【丽娘最喜欢这一块。】"
## 定格动画之后压在黑底上的三段解说。空行 = 分页（NarrationOverlay 的约定），
## 每页各等一次空格。
const EPILOGUE_TEXT := """浮游花者，徒有其艳。

久服入药，则暗损元气，体渐虚羸，终至沉疴不起。

单恃此药，犹未必致此；然若朝夕相伴、日日亲之……"""

## 架子挪开之后露出的那封信。同样是空行分页，每段各等一次空格。
const FLAG_SHELF_PUZZLE_SOLVED := &"interior_01.shelf_puzzle_solved"
const LETTER_LOCK := &"letter_reading"
const LETTER_INTRO := "架子挪开的地方，压着一封未曾寄出的信。\n信上的墨迹有深有浅，看上去像是很多个日子慢慢写的。"
const LETTER_TEXT := """

怀瑾亲启：

忆昔初入杜府，亦是雨天。君立阶下相候，发梢尽湿，犹先为我拂雨。彼时便觉，此生得婿如此，是云岫之幸。

两载以来，君之待我，一一在心，不敢忘，亦不舍忘。此生所爱、来世所念，唯君一人而已。此语从未与人道，今日付诸笔端，字字皆真。

然正因爱君，有一事不得再瞒。

我非安分之人。这双手，拨算盘、走江湖、路见不平则拔刀，皆使得；独理不好这后宅琐碎、人情往来。两载如履薄冰，唯恐累及君与杜家，终究不是这块料，错漏难免，每错辄自愧。

成婚二载，又至今无所出，杜门望后，此节我愧对君，亦愧对杜氏先人。主母之任，我实不堪。

思之再三，有一言积于胸臆，今日终须与君言明——"""

## 信读完之后压在整屏上的最后一句，再按一次空格才收掉信。
const LETTER_CLOSING := "信的最后没写完。"
## 收掉信之后回到屋内，同时给一声提示音的那句字幕。
const SCREEN_CUE_TEXT := "刚刚路过的屏风那里好像有声音，要去看看吗？"
## 信读完之后落这个 Flag：屏风那个出口跟着它开放，读档也照此恢复。
const FLAG_LETTER_READ := &"interior_01.letter_read"

@export var dialogue_box_path: NodePath = ^"../DialogueBox"
@export var focus_blur_path: NodePath = ^"../FocusBlur"
## 回忆片段进出用的黑幕（ScreenFade 默认就是黑的）。
@export var memory_fade_path: NodePath = ^"../MemoryFade"
@export var cg_sequence_path: NodePath = ^"../CGSequence"
## 定格动画之后那三段黑底文字用的白幕件（底色已在场景里改成黑）。
@export var narration_overlay_path: NodePath = ^"../MemoryNarration"
## 信件用的整屏文字件（底色在场景里调成了纸色）。
@export var letter_overlay_path: NodePath = ^"../LetterOverlay"
@export var medicine_point_path: NodePath = ^"../Props/medicine"
@export var medicine_bowl_path: NodePath = ^"../Props/MedicineBowl"
@export var medicine_overlay_path: NodePath = ^"../MedicineOverlay/Root"
@export var medicine_bowl_image_path: NodePath = ^"../MedicineOverlay/Root/BowlImage"
@export var medicine_image_path: NodePath = ^"../MedicineOverlay/Root/MedicineImage"
@export var stones_path: NodePath = ^"../Props/stones"
@export var stone_overlay_path: NodePath = ^"../StoneOverlay/Root"
@export var stone_overview_path: NodePath = ^"../StoneOverlay/Root/Overview"
@export var stone_detail_path: NodePath = ^"../StoneOverlay/Root/Detail"
## 架子解谜。解开后才放出信件那个探索点。
@export var shelf_puzzle_path: NodePath = ^"../ShelfPuzzle/Puzzle"
## 信件探索点。解谜之前它是关掉的（不给提示、不吃交互、不参与碰撞）。
@export var letter_point_path: NodePath = ^"../Props/LetterPoint"
## 屏风后面的出口。读完信之前同样是关掉的。
@export var screen_passage_path: NodePath = ^"../Props/ScreenPassage"
## 提示音（占位：没有 stream 时安全跳过）。
@export var cue_sound_path: NodePath = ^"../CueSound"
## 信收掉之后等这么久，才给提示音和「去看看吗」那句字幕。
## 留一口气的时间：紧接着出会显得赶，玩家还没从信里出来。
@export_range(0.0, 10.0, 0.1, "suffix:s") var screen_cue_delay: float = 2.0
@export var player_path: NodePath = ^"../Player"

@export_group("BGM")
## 屋内的常规 BGM。回忆片段期间让位给 MemoryBgm，放完再淡回来。
@export var room_bgm_path: NodePath = ^"../Bgm"
## 定格动画专用的那条音轨。它 autoplay_on_ready = false，只由这里点。
@export var memory_bgm_path: NodePath = ^"../MemoryBgm"
## 解释字幕结束之后，这条音轨还要拖多久才开始淡出。
## 字幕一收音乐就停会显得断，留一口气让这段回忆自己散掉。
@export_range(0.0, 10.0, 0.1, "suffix:s") var memory_bgm_tail: float = 3.0

@export_group("Fade Timing")
## 「渐进黑幕」：刻意比常规过渡慢，让画面一点点沉下去。
@export_range(0.0, 5.0, 0.05, "suffix:s") var to_black_duration: float = 1.6
## 黑幕退开、露出 CG。
@export_range(0.0, 5.0, 0.05, "suffix:s") var reveal_cg_duration: float = 0.8
## 回忆放完，再次沉黑。
@export_range(0.0, 5.0, 0.05, "suffix:s") var cg_out_duration: float = 0.9
## 黑幕退开、露出黑底文字。
@export_range(0.0, 5.0, 0.05, "suffix:s") var reveal_text_duration: float = 0.8
## 文字读完，再次沉黑。
@export_range(0.0, 5.0, 0.05, "suffix:s") var text_out_duration: float = 0.9
## 黑幕退开、回到屋内。
@export_range(0.0, 5.0, 0.05, "suffix:s") var back_to_room_duration: float = 1.2

@onready var _interior: Node = get_node_or_null(level_path)
@onready var _dialogue: Node = get_node_or_null(dialogue_box_path)
@onready var _focus_blur: FocusBlur = get_node_or_null(focus_blur_path) as FocusBlur
@onready var _memory_fade: ScreenFade = get_node_or_null(memory_fade_path) as ScreenFade
@onready var _cg: CGSequence = get_node_or_null(cg_sequence_path) as CGSequence
@onready var _narration: NarrationOverlay = get_node_or_null(narration_overlay_path) as NarrationOverlay
@onready var _letter: NarrationOverlay = get_node_or_null(letter_overlay_path) as NarrationOverlay
@onready var _medicine_point: Interactable = get_node_or_null(medicine_point_path) as Interactable
@onready var _medicine_bowl: Interactable = get_node_or_null(medicine_bowl_path) as Interactable
@onready var _medicine_overlay: Control = get_node_or_null(medicine_overlay_path) as Control
@onready var _medicine_bowl_image: TextureRect = \
	get_node_or_null(medicine_bowl_image_path) as TextureRect
@onready var _medicine_image: TextureRect = get_node_or_null(medicine_image_path) as TextureRect
@onready var _stones: Interactable = get_node_or_null(stones_path) as Interactable
@onready var _stone_overlay: Control = get_node_or_null(stone_overlay_path) as Control
@onready var _stone_overview: TextureRect = get_node_or_null(stone_overview_path) as TextureRect
@onready var _stone_detail: TextureRect = get_node_or_null(stone_detail_path) as TextureRect
@onready var _shelf_puzzle: SequencePuzzle = get_node_or_null(shelf_puzzle_path) as SequencePuzzle
@onready var _letter_point: Interactable = get_node_or_null(letter_point_path) as Interactable
@onready var _screen_passage: Interactable = get_node_or_null(screen_passage_path) as Interactable
@onready var _cue_sound: AudioStreamPlayer = get_node_or_null(cue_sound_path) as AudioStreamPlayer
@onready var _room_bgm: LevelBgm = get_node_or_null(room_bgm_path) as LevelBgm
@onready var _memory_bgm: LevelBgm = get_node_or_null(memory_bgm_path) as LevelBgm
@onready var _player: Node = get_node_or_null(player_path)

## 演出进行中：期间再次触发直接忽略，别让两段演出叠在一起。
var _playing: bool = false
var _stones_playing: bool = false
var _medicine_point_playing: bool = false


func _connect_actors() -> void:
	if _medicine_bowl != null:
		_medicine_bowl.interacted.connect(_on_medicine_bowl_examined)
	if _medicine_point != null:
		_medicine_point.interacted.connect(_on_medicine_point_examined)
	if _stones != null:
		_stones.interacted.connect(_on_stones_examined)
	if _shelf_puzzle != null:
		_shelf_puzzle.solved.connect(_on_shelf_puzzle_solved)
	if _letter_point != null:
		_letter_point.interacted.connect(_on_letter_examined)


## 信件探索点跟着解谜 Flag 走：读档进关和现场解开都经过同一个函数。
func _restore_story_state() -> void:
	_apply_letter_point_availability()
	_apply_screen_passage_availability()
	_hide_stone_overlay()
	_hide_medicine_overlay()


func _on_story_ready() -> void:
	if _interior != null and _interior.has_method("autosave"):
		_interior.call("autosave")


# --- 石头调查图示 ---------------------------------------------------------------

## TextInteractable 已同步打开第一段文字；Director 只负责配图和第二段接续。
func _on_stones_examined(_player_node: Node) -> void:
	if _stones_playing:
		return
	_stones_playing = true
	_show_stone_image(false)
	await _wait_dialogue_closed()
	_show_stone_image(true)
	if _dialogue != null and _dialogue.has_method("show_text"):
		_dialogue.call("show_text", STONE_DETAIL_TEXT)
		await _wait_dialogue_closed()
	_hide_stone_overlay()
	_stones_playing = false


func _show_stone_image(show_detail: bool) -> void:
	if _stone_overlay != null:
		_stone_overlay.visible = true
	if _stone_overview != null:
		_stone_overview.visible = not show_detail
	if _stone_detail != null:
		_stone_detail.visible = show_detail


func _hide_stone_overlay() -> void:
	if _stone_overlay != null:
		_stone_overlay.visible = false


# --- 药碗 → 浮游花回忆 -----------------------------------------------------------

## 书案上的药材调查：配 `medicine.png`，文字关闭后收起，不触发回忆。
func _on_medicine_point_examined(_player_node: Node) -> void:
	if _medicine_point_playing:
		return
	_medicine_point_playing = true
	_show_medicine_overlay(false)
	await _wait_dialogue_closed()
	_hide_medicine_overlay()
	_medicine_point_playing = false


func _on_medicine_bowl_examined(_player_node: Node) -> void:
	# 三句旁白由调查点自己发 text_requested、关卡的共用对话框显示，
	# 这里同步显示配图，并在文字关闭后接续首次回忆。
	if _playing:
		return
	_playing = true
	_show_medicine_overlay(true)
	await _wait_dialogue_closed()
	_hide_medicine_overlay()
	# 已看过回忆时仍显示上面的调查配图，但不再播放失焦与回忆。
	if StoryFlagManager.has_flag(FLAG_MEDICINE_MEMORY_SEEN):
		_playing = false
		return
	# 对话框自己的输入锁在关框时就释放了，接下来的失焦和黑幕期间要自己锁住。
	_lock_player()

	if _focus_blur != null:
		await _focus_blur.pulse()

	if _dialogue != null and _dialogue.has_method("show_text"):
		_dialogue.call("show_text", LINIANG_LINE, null, SPEAKER_LINIANG)
		await _wait_dialogue_closed()

	await _play_memory()

	StoryFlagManager.set_flag(FLAG_MEDICINE_MEMORY_SEEN)
	_unlock_player()
	_playing = false
	if _interior != null and _interior.has_method("autosave"):
		_interior.call("autosave")


func _show_medicine_overlay(show_bowl: bool) -> void:
	if _medicine_overlay != null:
		_medicine_overlay.visible = true
	if _medicine_bowl_image != null:
		_medicine_bowl_image.visible = show_bowl
	if _medicine_image != null:
		_medicine_image.visible = not show_bowl


func _hide_medicine_overlay() -> void:
	if _medicine_overlay != null:
		_medicine_overlay.visible = false


## 黑幕过渡 + 定格 CG。CG 件低于黑幕层，所以顺序是：先全黑 → 让 CG 把底色铺上
## → 黑幕退开露出 CG → 放完 → 再全黑 → 收掉 CG → 黑幕退开回到屋内。
func _play_memory() -> void:
	if _cg == null:
		return
	# 音乐和画面同时开始交接：屋内 BGM 跟着黑幕一起沉下去，回忆的音轨
	# 在还全黑的时候就已经浮起来了，CG 露出来时它正好到位。
	if _room_bgm != null:
		_room_bgm.fade_out(to_black_duration)
	if _memory_bgm != null:
		_memory_bgm.fade_in()
	if _memory_fade != null:
		await _memory_fade.fade_out(to_black_duration)
	# 刻意不 await：play() 会先同步把 CG 的底色和第一张图铺上，
	# 黑幕这时才敢退开，否则中间会闪一下屋内画面。
	_cg.play()
	if _memory_fade != null:
		await _memory_fade.fade_in(reveal_cg_duration)
	await _cg.finished
	if _memory_fade != null:
		await _memory_fade.fade_out(cg_out_duration)
	_cg.close()
	await _play_epilogue_text()
	# 刻意不 await：音乐的尾巴要盖过「回到屋内」这个动作，玩家已经能动了
	# 音还没散完。await 会把回屋硬生生卡住三秒。
	_end_memory_bgm_after_tail()
	if _memory_fade != null:
		await _memory_fade.fade_in(back_to_room_duration)


## 定格动画之后的三段解说：黑底居中文字，空格逐段推进。
## 复用 NarrationOverlay（原本是白幕文字演出件），底色在场景里改成了黑，
## 所以它和前面的 CG、黑幕连成同一块黑。
##
## 进来时画面已经全黑（调用方刚 fade_out），所以先把这块底铺好再让黑幕退开，
## 中间不会闪一下屋内画面——和 CG 那段同一个道理。
func _play_epilogue_text() -> void:
	if _narration == null:
		return
	await _narration.begin_session()
	if _memory_fade != null:
		await _memory_fade.fade_in(reveal_text_duration)
	await _narration.show_line(EPILOGUE_TEXT)
	if _memory_fade != null:
		await _memory_fade.fade_out(text_out_duration)
	await _narration.end_session()


## 解释字幕结束之后再拖 `memory_bgm_tail` 秒，才把回忆音轨交还给屋内 BGM。
## 和 `_play_memory()` 并行跑，不挡回屋的流程。
func _end_memory_bgm_after_tail() -> void:
	if _memory_bgm == null:
		return
	if memory_bgm_tail > 0.0:
		# 最后一个参数 = 忽略 time_scale：DreamGap 的慢时间不该把音乐尾巴拉长。
		await get_tree().create_timer(memory_bgm_tail, true, false, true).timeout
	_memory_bgm.fade_out()
	if _room_bgm != null:
		_room_bgm.fade_in()


# --- 架子解谜 → 信件 -----------------------------------------------------------

func _on_shelf_puzzle_solved() -> void:
	_apply_letter_point_availability()


func _apply_letter_point_availability() -> void:
	_set_area_enabled(_letter_point, StoryFlagManager.has_flag(FLAG_SHELF_PUZZLE_SOLVED))


func _apply_screen_passage_availability() -> void:
	_set_area_enabled(_screen_passage, StoryFlagManager.has_flag(FLAG_LETTER_READ))


## 整屏读信：先一句旁白说明这是什么，再逐段放信文，空格推进。
func _on_letter_examined(_player_node: Node) -> void:
	if _letter == null or _letter.is_showing():
		return
	_lock_player_with(LETTER_LOCK)
	await _letter.show_line(LETTER_INTRO)
	await _letter.show_line(LETTER_TEXT)
	await _letter.show_line(LETTER_CLOSING)
	await _letter.end_session()
	_unlock_player_with(LETTER_LOCK)
	_on_letter_finished()


## 信收掉之后：一声提示音 + 一句字幕把玩家指回屏风，并放开那个出口。
## 重复读信不会重复放（Flag 已在就只放出口，不再提示）。
func _on_letter_finished() -> void:
	if StoryFlagManager.has_flag(FLAG_LETTER_READ):
		return
	# Flag 先落住，当重入闸门用：等待期间再点信件不会排第二次提示。
	StoryFlagManager.set_flag(FLAG_LETTER_READ)
	if screen_cue_delay > 0.0:
		# 等待期间玩家已经解锁，可以先走两步——声音是「过了一会儿才响」。
		await get_tree().create_timer(screen_cue_delay).timeout
	_apply_screen_passage_availability()
	if _cue_sound != null and _cue_sound.stream != null:
		_cue_sound.play()
	if _dialogue != null and _dialogue.has_method("show_text"):
		_dialogue.call("show_text", SCREEN_CUE_TEXT)
	if _interior != null and _interior.has_method("autosave"):
		_interior.call("autosave")


## 开关一个探索点：提示、交互、碰撞一起开关。不 queue_free，保持可逆。
func _set_area_enabled(area: Area2D, enabled: bool) -> void:
	if area == null:
		return
	area.monitoring = enabled
	area.monitorable = enabled
	area.input_pickable = enabled
	area.collision_layer = 1 if enabled else 0
	area.visible = enabled
	# 玩家可能正站在范围内；Godot 不保证为运行时改碰撞层补发 area_exited。
	if _player != null:
		for child in _player.get_children():
			if child is InteractionDetector:
				child.call_deferred("refresh_overlaps")


# --- 工具 ----------------------------------------------------------------------

func _wait_dialogue_closed() -> void:
	if _dialogue == null or not _dialogue.has_method("is_showing"):
		return
	if not _dialogue.call("is_showing"):
		return
	await Signal(_dialogue, &"closed")


func _lock_player() -> void:
	_lock_player_with(MEMORY_LOCK)


func _unlock_player() -> void:
	_unlock_player_with(MEMORY_LOCK)


func _lock_player_with(source: StringName) -> void:
	if _player != null and _player.has_method("begin_interaction"):
		_player.call("begin_interaction", source)


func _unlock_player_with(source: StringName) -> void:
	if _player != null and _player.has_method("end_interaction"):
		_player.call("end_interaction", source)
