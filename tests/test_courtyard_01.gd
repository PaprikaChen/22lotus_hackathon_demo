extends Node2D
## courtyard_01 / courtyard_02 与新流程的回归（`[TEST:courtyard]` 行）。
##
## 覆盖：
##   · 禁跳跃（player_can_jump = false 真的下发到玩家）
##   · A/D 行走 → RUN / IDLE 状态与朝向翻转
##   · 相机：人物居中；到左右边缘画面停住、人物继续走
##   · 场景边界墙挡住人物
##   · E 调查走共用对话框、提示语上屏
##   · 梦奁信物照常拾取（保留原系统）
##   · 出口门槛：没拿到信物走不了；拿到就能走
##   · 前情提要：逐段推进、最后一段之后发 finished
##   · 画廊 + 全局存储：解锁 / NEW 角标 / 跨"存档"保留
##
## 手动（真键盘）：走动手感、贴边感觉、前情提要节奏。

const LEVEL_01 := "res://scenes/levels/courtyard_01.tscn"
const PROLOGUE := "res://scenes/ui/prologue.tscn"
const GALLERY := "res://scenes/ui/gallery.tscn"
const HAIRPIN := &"mountain_bird_hairpin"

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		_run_self_test.call_deferred()


func _check(cond: bool, label: String) -> void:
	if cond:
		_pass_count += 1
		print("[TEST:courtyard] PASS  %s" % label)
	else:
		_fail_count += 1
		print("[TEST:courtyard] FAIL  %s" % label)


func _run_self_test() -> void:
	print("[TEST:courtyard] --- start ---")
	# 每个子测试都自己开一份场景，互不污染。
	await _test_level()
	await _test_camera()
	await _test_interaction_and_memory()
	await _test_exit_gate()
	await _test_new_game_flow()
	await _test_prologue()
	await _test_gallery()
	print("[TEST:courtyard] --- done: %d passed, %d failed ---" % [_pass_count, _fail_count])
	if DisplayServer.get_name() == "headless":
		get_tree().quit(_fail_count)


# --- 工具 ----------------------------------------------------------------------

func _load_level() -> Node:
	var level = load(LEVEL_01).instantiate()
	add_child(level)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return level


func _drop(node: Node) -> void:
	node.queue_free()
	await get_tree().process_frame


## 按住某个动作跑若干物理帧。MCP 注入不了按键边沿，所以用 Input 的
## action_press/release（和项目里"手动追踪上升沿"的约定兼容）。
func _hold(action: StringName, frames: int) -> void:
	Input.action_press(action)
	for i in frames:
		await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


# --- 关卡基础 -------------------------------------------------------------------

func _test_level() -> void:
	var level = await _load_level()
	var p: Player = level.get_node("Player")
	var spawn: Marker2D = level.get_node("SpawnPoint")

	_check(not p.jump_enabled, "player_can_jump=false 下发成 jump_enabled=false")
	_check(p.global_position.distance_to(spawn.global_position) < 32.0,
		"玩家落在关卡 SpawnPoint")
	_check(p.get_state() == Player.State.IDLE, "开局待机")

	# D 右移 → RUN + 朝右
	var x0 := p.global_position.x
	await _hold(&"move_right", 20)
	_check(p.global_position.x > x0 + 40.0, "按 D 向右移动")
	_check(p.get_facing() == 1, "向右时朝向 +1")

	# A 左移 → 朝左翻转
	await _hold(&"move_left", 20)
	_check(p.get_facing() == -1, "按 A 后朝向翻成 -1")

	# 松手回到待机
	for i in 30:
		await get_tree().physics_frame
	_check(p.get_state() == Player.State.IDLE, "松开左右键回到待机")

	# 跳跃被禁：按 jump 不该离地
	var y0 := p.global_position.y
	await _hold(&"jump", 12)
	_check(absf(p.global_position.y - y0) < 4.0, "禁跳关卡里按空格不会起跳")
	_check(p.is_on_floor(), "仍然贴地")

	# 左边界墙挡人
	p.global_position = Vector2(60.0, p.global_position.y)
	await _hold(&"move_left", 40)
	_check(p.global_position.x > -40.0, "左边界墙挡住玩家")

	await _drop(level)


# --- 相机 ----------------------------------------------------------------------

func _test_camera() -> void:
	var level = await _load_level()
	var p: Player = level.get_node("Player")
	var cam: Camera2D = level.get_node("FollowCamera2D")
	var view_w := cam.get_viewport_rect().size.x / cam.zoom.x
	var bounds: Rect2 = cam.get_bounds()

	_check(bounds.size.x > view_w, "场景宽度 ≥ 视口宽度（否则 limit 会冲突）")

	# 中段：人物居中 —— 画面中心跟人物 x 一致
	p.global_position.x = bounds.size.x * 0.5
	await get_tree().process_frame
	await get_tree().process_frame
	_check(absf(cam.get_screen_center_position().x - p.global_position.x) < 4.0,
		"场景中段：人物处在画面中心")

	# 贴边位置必须按视口宽度推算，不能写死像素：headless 是 64×64 的假窗口，
	# 写死的 "40px" 在那种视口下根本没进钳制区（限位区宽度 = 视口宽 / 2）。
	var inside_edge := view_w * 0.25

	# 贴左缘：画面停在左 limit，人物比画面中心更靠左
	p.global_position.x = bounds.position.x + inside_edge
	await get_tree().process_frame
	await get_tree().process_frame
	var centre_left := cam.get_screen_center_position().x
	_check(absf(centre_left - (bounds.position.x + view_w * 0.5)) < 4.0,
		"贴左缘：画面停在左边界")
	_check(p.global_position.x < centre_left, "贴左缘：人物偏离画面中心向左")

	# 贴右缘同理
	p.global_position.x = bounds.end.x - inside_edge
	await get_tree().process_frame
	await get_tree().process_frame
	var centre_right := cam.get_screen_center_position().x
	_check(absf(centre_right - (bounds.end.x - view_w * 0.5)) < 4.0,
		"贴右缘：画面停在右边界")
	_check(p.global_position.x > centre_right, "贴右缘：人物偏离画面中心向右")

	await _drop(level)


# --- 交互与信物 -----------------------------------------------------------------

func _test_interaction_and_memory() -> void:
	MemoryManager.reset()
	var level = await _load_level()
	var p: Player = level.get_node("Player")
	var box = level.get_node("DialogueBox")
	var prompt: Label = level.get_node("UI/PromptLabel")
	var gate: Interactable = level.get_node("Props/GateSpot")
	var pickup: Interactable = level.get_node("Props/HairpinPickup")

	# E 调查 → 文字进共用对话框
	gate.interact(p)
	_check(bool(box.is_showing()), "调查后共用对话框打开")
	_check(String(box.get_current_text()).contains("院门"), "院门文字进对话框")
	_check(p.is_input_locked(), "读文字期间玩家被锁")
	while bool(box.is_showing()):
		box.advance()
	_check(not p.is_input_locked(), "文字读完解锁")
	_check(StoryFlagManager.has_flag(&"courtyard_01.gate_examined"),
		"Director 记下了 gate_examined")

	# 提示语上屏（靠 InteractionDetector 的 prompt_changed）
	var detector: InteractionDetector = p.get_node("InteractionDetector")
	detector.prompt_changed.emit("测试提示")
	_check(prompt.text.contains("测试提示"), "提示语接到了 PromptLabel")

	# 调查井台 → Director 解锁占位 CG（画廊管线的现场链路）
	GalleryManager.reset()
	var well: Interactable = level.get_node("Props/WellSpot")
	well.interact(p)
	while bool(box.is_showing()):
		box.advance()
	_check(GalleryManager.has_cg(&"cg_placeholder_01"), "调查井台解锁了占位 CG")
	_check(GalleryManager.is_unseen(&"cg_placeholder_01"), "新解锁的 CG 带 NEW 角标")

	# 梦奁信物照常拾取
	_check(not MemoryManager.has_memory(HAIRPIN), "开局没有山鸟簪")
	pickup.interact(p)
	_check(MemoryManager.has_memory(HAIRPIN), "拾取后持有山鸟簪")
	_check(not pickup.can_interact(p), "拾取物是一次性的")

	await _drop(level)


# --- 出口门槛 -------------------------------------------------------------------

func _test_exit_gate() -> void:
	MemoryManager.reset()
	var level = await _load_level()
	var p: Player = level.get_node("Player")
	var exit_node: LevelExit = level.get_node("Props/ToNextLevel")
	var left: Array[String] = []
	level.level_left.connect(func(target: String) -> void: left.append(target))

	_check(not exit_node.is_open(), "没拿到信物时出口关着")
	exit_node.interact(p)
	_check(left.is_empty(), "门槛不满足时不会切场景")
	_check(exit_node.get_interaction_prompt() == exit_node.blocked_prompt_text,
		"门槛不满足时显示锁着提示")

	# 拿到信物 → Director 重算门槛
	(level.get_node("Props/HairpinPickup") as Interactable).interact(p)
	_check(exit_node.is_open(), "拿到山鸟簪后出口打开")
	exit_node.interact(p)
	_check(left.size() == 1 and left[0].ends_with("courtyard_02.tscn"),
		"门槛满足后走向 courtyard_02")
	exit_node.interact(p)
	_check(left.size() == 1, "重复触发只走一次")

	await _drop(level)


# --- 前情提要 -------------------------------------------------------------------

## 新游戏流程的接线：菜单 → 槽位菜单 → 前情提要 → courtyard_01。
## 断言"入口不是测试场景"而不是只比对一个字符串——前者才是真正要守住的性质。
func _test_new_game_flow() -> void:
	var entry := SaveManager.NEW_GAME_SCENE_PATH
	var prologue := SaveManager.PROLOGUE_SCENE_PATH
	_check(entry == LEVEL_01, "新游戏入口指向 courtyard_01")
	_check(not entry.begins_with("res://tests/"), "新游戏入口不是测试场景")
	_check(ResourceLoader.exists(entry), "入口场景存在")
	_check(ResourceLoader.exists(prologue), "前情提要场景存在")
	_check(prologue != entry, "前情提要和关卡是两个场景")

	# create_new_save 写进存档的必须是关卡，不是前情提要——否则在前情提要里
	# 退出再读档会重看一遍。这条是"只播一次"的实际保证。
	var slot := 3
	var backup := SaveManager.read_global("__test_backup")
	var had := SaveManager.save_exists(slot)
	var saved_before := SaveManager.get_save_summary(slot) if had else {}
	_check(SaveManager.create_new_save(slot), "能在槽位 3 建新档")
	_check(String(SaveManager.current_save.get("current_scene", "")) == entry,
		"新档的 current_scene 是关卡而不是前情提要")
	_check(bool(SaveManager.current_save.get("use_level_spawn", false)),
		"新档带 use_level_spawn=true（用关卡自己的出生点）")
	SaveManager.delete_save(slot)
	SaveManager.current_slot = -1
	SaveManager.current_save = {}
	if had:
		print("[TEST:courtyard] NOTE: 槽位 3 原有存档已被本测试覆盖并删除（%s）" % str(saved_before))
	if not backup.is_empty():
		SaveManager.write_global("__test_backup", backup)


func _test_prologue() -> void:
	var pro = load(PROLOGUE).instantiate()
	add_child(pro)
	await get_tree().process_frame
	var finished: Array[bool] = []
	pro.finished.connect(func() -> void: finished.append(true))

	var total: int = (pro.segments as PackedStringArray).size()
	_check(total > 0, "前情提要有占位文案（%d 段）" % total)
	_check(pro.get_segment_index() == 0, "开局显示第一段")
	_check(finished.is_empty(), "第一段时还没结束")

	# 逐段推进到最后一段
	for i in total - 1:
		pro.advance()
	_check(pro.get_segment_index() == total - 1, "推进到最后一段")
	_check(finished.is_empty(), "最后一段时还没结束")
	pro.advance()
	_check(pro.is_finished() and finished.size() == 1, "最后一段之后发 finished")
	pro.advance()
	_check(finished.size() == 1, "结束后重复推进不会重复发信号")

	await _drop(pro)


# --- 画廊 + 全局存储 -----------------------------------------------------------

func _test_gallery() -> void:
	var ids := GalleryManager.get_all_cgs()
	_check(ids.size() >= 2, "画廊注册到了占位 CG（%d 张）" % ids.size())
	if ids.is_empty():
		return
	var first := ids[0]
	var second := ids[1] if ids.size() > 1 else ids[0]

	GalleryManager.reset()
	_check(GalleryManager.get_unlocked_count() == 0, "reset 后没有已解锁的 CG")
	_check(not GalleryManager.has_cg(first), "首张 CG 初始未解锁")

	_check(GalleryManager.unlock_cg(first), "首次解锁返回 true")
	_check(GalleryManager.has_cg(first), "解锁后 has_cg 为真")
	_check(GalleryManager.is_unseen(first), "刚解锁的 CG 带 NEW 角标")
	_check(not GalleryManager.unlock_cg(first), "重复解锁返回 false")
	GalleryManager.mark_as_seen(first)
	_check(not GalleryManager.is_unseen(first), "看过之后角标消失")
	_check(GalleryManager.unlock_cg(&"cg_does_not_exist") == false,
		"未知 id 解锁失败且不崩")

	# 落盘 → 重新读回（等价于重启游戏 / 换存档槽）
	var reloaded := SaveManager.read_global("gallery")
	var cgs: Dictionary = reloaded.get("cgs", {})
	_check(cgs.has(String(first)), "解锁状态写进了 user://gallery.json")
	_check(not cgs.has(String(second)), "没解锁的 CG 不写盘")

	# 画廊 UI：未解锁的格子不显示标题（避免剧透）
	var screen = load(GALLERY).instantiate()
	add_child(screen)
	await get_tree().process_frame
	_check(screen.get_slot_count() == ids.size(), "画廊格子数 = CG 总数（含未解锁）")
	screen.open_cg(first)
	_check(screen.get_viewing() == first, "点开后进入看图")
	screen.close_cg()
	_check(screen.get_viewing() == &"", "关闭后回到网格")
	await _drop(screen)

	GalleryManager.reset()
