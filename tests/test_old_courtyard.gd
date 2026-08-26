extends Node2D
## Headless checks for the 旧院 graybox level ([TEST:oldcourtyard] lines).
## Instances the real level scene and drives it: window-sized areas, trigger
## → fade → teleport switching, camera limits, re-entry guards, no 4th area,
## all placeholder interactions routed through the bottom DialogueBox, and
## the side-window single entry signal.
## Manual (real keyboard): walking pace, fade feel, box/portrait look.

# Untyped on purpose: the level and controller are addressed dynamically.
@onready var _level = $Level
@onready var _flow = $Level/AreaFlowController
@onready var _box = $Level/DialogueBox
@onready var _p: CharacterBody2D = $Level/Player
@onready var _camera: Camera2D = $Level/Camera2D

var _pass_count: int = 0
var _fail_count: int = 0
var _entered_count: int = 0

## 落点断言的容差（像素）。见下方 use_level_spawn 那段的注释。
const POS_TOLERANCE: float = 32.0


func _ready() -> void:
	_level.entered_main_house.connect(func() -> void: _entered_count += 1)
	if DisplayServer.get_name() == "headless":
		_run_self_test.call_deferred()


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass_count += 1
		print("[TEST:oldcourtyard] PASS  %s" % label)
	else:
		_fail_count += 1
		print("[TEST:oldcourtyard] FAIL  %s" % label)


func _await_switch_done() -> void:
	var waited := 0.0
	while _flow.is_switching and waited < 3.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1


## 再实例化一份关卡，等价于“读档后重新进关”。LevelBase._ready() 在 add_child
## 里同步跑完，所以返回时 StoryDirector 的恢复已经执行过了。
func _reload_level() -> Node:
	var level = load("res://scenes/levels/old_courtyard.tscn").instantiate()
	add_child(level)
	await get_tree().process_frame
	return level


func _free_level(level: Node) -> void:
	level.queue_free()
	await get_tree().process_frame


## 等某个条件成立，最多等 timeout 秒。用于等淡入淡出这类按时间推进的表现。
func _await_until(cond: Callable, timeout: float = 3.0) -> void:
	var waited := 0.0
	while not bool(cond.call()) and waited < timeout:
		await get_tree().create_timer(0.05).timeout
		waited += 0.05


func _interactable(path: String) -> Interactable:
	return _level.get_node("AreaContainer/" + path) as Interactable


func _run_self_test() -> void:
	print("[TEST:oldcourtyard] --- self-test start ---")
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Initial state: one window-sized area, dialogue box hidden.
	_check(int(_flow.current_area_index) == 0, "starts in area 0")
	_check(_camera.limit_left == 0 and _camera.limit_right == 1152,
		"area 0 camera limits are exactly one window")
	_check(not bool(_box.is_showing()), "dialogue box hidden at start")
	_check(not _level.get_node("AreaContainer/Area01_LandingGate/ExitTrigger").visible,
		"exit trigger authoring visual hidden at runtime")

	# Area 1 -> 2 via the right-edge trigger.
	_p.global_position = Vector2(1120, 480)
	for i in 3:
		await get_tree().physics_frame
	_check(bool(_flow.is_switching), "switch started at the window's right edge")
	_check(_p.is_input_locked(), "player input locked during switch")
	_flow.switch_to_area(0)
	await _await_switch_done()
	_check(not bool(_flow.is_switching), "switch finished")
	_check(int(_flow.current_area_index) == 1, "arrived in area 2 (re-entry call ignored)")
	_check(absf(_p.global_position.x - 2100.0) < 10.0, "player placed at area 2 spawn")
	_check(_camera.limit_left == 2000 and _camera.limit_right == 3152,
		"camera limits moved to area 2")
	_check(not _p.is_input_locked(), "input restored after switch")

	# Area 2 -> 3 via its trigger.
	_p.global_position = Vector2(3120, 480)
	for i in 3:
		await get_tree().physics_frame
	await _await_switch_done()
	_check(int(_flow.current_area_index) == 2, "arrived in area 3")
	_check(_camera.limit_left == 4000 and _camera.limit_right == 5152,
		"camera limits moved to area 3")

	# No 4th area, no trigger on the last area.
	_flow.switch_to_area(3)
	await get_tree().create_timer(0.2).timeout
	_check(int(_flow.current_area_index) == 2 and not bool(_flow.is_switching),
		"no switch past the last area")
	_check(_level.get_node("AreaContainer/Area03_MainHouse").get_exit_trigger() == null,
		"last area has no exit trigger")

	# Walking to the LEFT edge returns to the previous area, arriving at its
	# right side (and not inside its right trigger).
	_p.global_position = Vector2(4030, 480)
	for i in 3:
		await get_tree().physics_frame
	await _await_switch_done()
	_check(int(_flow.current_area_index) == 1, "left edge of area 3 returns to area 2")
	_check(absf(_p.global_position.x - 3030.0) < 10.0,
		"returning places the player at the previous area's right side")
	for i in 5:
		await get_tree().physics_frame
	_check(not bool(_flow.is_switching), "right-side spawn does not immediately re-trigger")
	_p.global_position = Vector2(2030, 480)
	for i in 3:
		await get_tree().physics_frame
	await _await_switch_done()
	_check(int(_flow.current_area_index) == 0, "left edge of area 2 returns to area 1")
	_check(absf(_p.global_position.x - 1030.0) < 10.0, "arrived at area 1's right side")
	_check(_level.get_node("AreaContainer/Area01_LandingGate").get_left_exit_trigger() == null,
		"first area has no left trigger")
	# Forward still works after going back (full round trip).
	_p.global_position = Vector2(1120, 480)
	for i in 3:
		await get_tree().physics_frame
	await _await_switch_done()
	_check(int(_flow.current_area_index) == 1, "forward switch works again after going back")

	# Paged display: gate text is 3 sentences — one per page, Space advances,
	# box closes after the last, player held while reading.
	_interactable("Area01_LandingGate/Interactables/GateDoor").interact(_p)
	_check(bool(_box.is_showing()), "dialogue box appears on interact")
	_check(String(_box.get_current_text()) == "门锁已经锈死。", "shows only the first sentence")
	_check(_p.is_input_locked(), "player locked while the box is open")
	_box.advance()
	_check(String(_box.get_current_text()).contains("这里不像是最近才被封起来"),
		"advance shows the second sentence")
	_box.advance()
	_check(String(_box.get_current_text()).contains("很多年没有人"), "third sentence shown")
	_box.advance()
	_check(not bool(_box.is_showing()), "box closes after the last sentence")
	_check(not _p.is_input_locked(), "player released when the box closes")

	# Remaining props: first sentence lands in the box, then page them shut.
	_interactable("Area01_LandingGate/Interactables/AgeMarksSpot").interact(_p)
	_check(String(_box.get_current_text()).contains("三岁"), "age marks text in the box")
	while bool(_box.is_showing()):
		_box.advance()
	_interactable("Area02_BegoniaTree/Interactables/TreeCloth").interact(_p)
	_check(String(_box.get_current_text()).contains("布条曾经应该是红色"), "tree cloth text in the box")
	while bool(_box.is_showing()):
		_box.advance()
	_interactable("Area03_MainHouse/Interactables/MainDoorSpot").interact(_p)
	_check(String(_box.get_current_text()).contains("藤蔓已经清理干净"), "main door text in the box")
	while bool(_box.is_showing()):
		_box.advance()
	_interactable("Area03_MainHouse/Interactables/WoodenHorseSpot").interact(_p)
	_check(String(_box.get_current_text()).contains("木马"), "wooden horse text in the box")
	while bool(_box.is_showing()):
		_box.advance()
	_interactable("Area03_MainHouse/Interactables/HerbBedSpot").interact(_p)
	_check(String(_box.get_current_text()).contains("其他花草都已经枯死"), "herb bed text in the box")
	while bool(_box.is_showing()):
		_box.advance()

	# Portrait slot: optional, shown only when a texture is passed.
	var portrait_rect: TextureRect = _box.get_node("Root/Panel/Margin/HBox/Portrait")
	_box.show_text("测试无立绘")
	_check(not portrait_rect.visible, "portrait hidden for plain interaction text")
	_box.advance()
	_box.show_text("测试立绘", load("res://icon.svg"))
	_check(portrait_rect.visible, "portrait shown when a texture is provided")
	_box.hide_box()
	_check(not bool(_box.is_showing()), "hide_box() hides the panel")

	# --- StoryDirector 剧情链 ---------------------------------------------
	# 药圃 + 侧窗 → 母亲幻觉 → 丫鬟入场 → 对话 → 侧窗解锁 → 进主屋。
	# 药圃已经在上面调查过，poison_discovered 应已写入。
	var maid = _level.get_node("AreaContainer/Area03_MainHouse/NPCs/Maid")
	var cutscene = _level.get_node("Cutscenes/MotherMemoryCutscene")
	var window := _interactable("Area03_MainHouse/Interactables/SideWindow")

	_check(StoryFlagManager.has_flag(&"old_courtyard.poison_discovered"),
		"调查药圃写入 poison_discovered")
	_check(not bool(maid.is_present()), "丫鬟开局不在场")
	_check(window.prompt_text == "查看侧窗", "侧窗未解锁时提示语是调查")

	# 侧窗第一次只是调查，不是入口。
	window.interact(_p)
	_check(String(_box.get_current_text()).contains("山鸟纹"), "side window text in the box")
	_check(_entered_count == 0, "not entered while text is still open")
	while bool(_box.is_showing()):
		_box.advance()
	_check(_entered_count == 0, "侧窗未解锁时读完文字也不进屋")
	_check(StoryFlagManager.has_flag(&"old_courtyard.hairpin_noticed"),
		"调查侧窗写入 hairpin_noticed")

	# 两条线索齐备 → 幻觉在文字读完之后自动开演，并锁住玩家。
	_check(bool(cutscene.is_playing()), "两处线索齐备后母亲幻觉开演")
	_check(_p.is_input_locked(), "幻觉期间玩家被锁")
	await _await_until(func() -> bool: return bool(_box.is_showing()))
	while bool(_box.is_showing()):
		_box.advance()
	await _await_until(func() -> bool: return not bool(cutscene.is_playing()))

	# 幻觉的剧情后果由 Director 写，不在 Cutscene 里。
	_check(MemoryManager.has_memory(&"mountain_bird_hairpin"), "幻觉结束后获得山鸟簪")
	_check(bool(maid.is_present()), "幻觉结束后丫鬟入场")
	_check(not _p.is_input_locked(), "幻觉结束后输入锁释放")

	# 还没谈过话，侧窗仍然不是入口。
	window.interact(_p)
	while bool(_box.is_showing()):
		_box.advance()
	_check(_entered_count == 0, "同丫鬟谈话前侧窗仍不是入口")

	# 同丫鬟对话 → 解锁侧窗。
	(maid.get_node("TalkSpot") as Interactable).interact(_p)
	_check(String(_box.get_current_text()).contains("姑娘"), "丫鬟台词进对话框")
	while bool(_box.is_showing()):
		_box.advance()
	_check(StoryFlagManager.has_flag(&"old_courtyard.maid_talked"), "对话结束写入 maid_talked")
	_check(window.prompt_text == "从侧窗进屋", "解锁后侧窗提示语变成入口")

	# 现在侧窗才是入口，而且只进一次。
	window.interact(_p)
	while bool(_box.is_showing()):
		_box.advance()
	_check(_entered_count == 1, "entered_main_house emitted once after text ends")
	window.interact(_p)
	while bool(_box.is_showing()):
		_box.advance()
	_check(_entered_count == 1, "second visit does not re-enter")

	# Area switches clear leftover text.
	_box.show_text("残留文字")
	_flow.switch_to_area(0)
	await _await_switch_done()
	_check(not bool(_box.is_showing()), "dialogue box cleared on area change")

	# World left clean.
	_check(WorldTimeManager.current_state == WorldTimeManager.SlowTimeState.READY,
		"DreamGap state clean")
	_check(not _p.is_input_locked(), "no leftover input locks")

	# --- 读档恢复：带着已有剧情状态重进本关，不许重播任何演出 --------------
	# 再实例化一份关卡 = 读档后重新进关（Flag / Memory 都在 Autoload 里）。
	# 关键点：终态由 _apply_* 摆出来，Cutscene 和入场动画一次都不应该跑。

	# 情形一：幻觉看过、但还没和丫鬟谈过 → 丫鬟应在场，且不重播幻觉。
	StoryFlagManager.clear_flag(&"old_courtyard.maid_talked")
	var mid = await _reload_level()
	_check(not bool(mid.get_node("Cutscenes/MotherMemoryCutscene").is_playing()),
		"读档恢复：不重播母亲幻觉")
	_check(bool(mid.get_node("AreaContainer/Area03_MainHouse/NPCs/Maid").is_present()),
		"读档恢复：幻觉已看未谈话 → 丫鬟在场")
	_check((mid.get_node("AreaContainer/Area03_MainHouse/Interactables/SideWindow")
		as Interactable).prompt_text == "查看侧窗",
		"读档恢复：未谈话时侧窗还不是入口")
	await _free_level(mid)

	# 情形二：全部完成 → 丫鬟已离场，侧窗是入口。
	StoryFlagManager.set_flag(&"old_courtyard.maid_talked")
	var done = await _reload_level()
	_check(not bool(done.get_node("Cutscenes/MotherMemoryCutscene").is_playing()),
		"读档恢复（已完成）：不重播母亲幻觉")
	_check(not bool(done.get_node("AreaContainer/Area03_MainHouse/NPCs/Maid").is_present()),
		"读档恢复（已完成）：丫鬟已离场")
	_check((done.get_node("AreaContainer/Area03_MainHouse/Interactables/SideWindow")
		as Interactable).prompt_text == "从侧窗进屋",
		"读档恢复（已完成）：侧窗是入口")
	await _free_level(done)

	# --- 新游戏入口：新档必须落在关卡自己的 SpawnPoint ----------------------
	# create_new_save() 会写死一份占位坐标；没有 use_level_spawn 这一条，
	# LevelBase 会拿那份占位坐标当真，新游戏永远落错地方。
	var prev_save := SaveManager.current_save
	var spawn_marker := (_level.get_node("AreaContainer/Area01_LandingGate/SpawnPoint")
		as Node2D).global_position
	SaveManager.current_save = {
		"current_scene": "res://scenes/levels/old_courtyard.tscn",
		"player_position_x": 9999.0,
		"player_position_y": 9999.0,
		"use_level_spawn": true,
	}
	var fresh = await _reload_level()
	# 用距离而不是 is_equal_approx：玩家是受重力的 CharacterBody2D，放置到断言
	# 之间跑几个物理帧不固定，每帧会下坠约 0.4px。两个候选落点相差数千像素，
	# 所以宽松阈值完全能表达"用的是哪一个"。
	_check((fresh.get_node("Player") as Node2D).global_position.distance_to(spawn_marker) < POS_TOLERANCE,
		"新档 use_level_spawn=true → 落在关卡 SpawnPoint")
	await _free_level(fresh)

	# 真实存档点写的档带真坐标，仍然优先于 SpawnPoint。
	SaveManager.current_save["use_level_spawn"] = false
	var loaded = await _reload_level()
	_check((loaded.get_node("Player") as Node2D).global_position.distance_to(
		Vector2(9999.0, 9999.0)) < POS_TOLERANCE,
		"真实存档 use_level_spawn=false → 用存档坐标")
	await _free_level(loaded)
	SaveManager.current_save = prev_save

	print("[TEST:oldcourtyard] --- done: %d passed, %d failed ---" % [_pass_count, _fail_count])
	print("[TEST:oldcourtyard] MANUAL: walk pace, fade feel, box readability, portrait layout, Tab memory box.")
	if DisplayServer.get_name() == "headless":
		get_tree().quit(_fail_count)
