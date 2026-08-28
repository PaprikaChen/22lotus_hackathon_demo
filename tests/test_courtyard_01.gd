extends Node2D
## courtyard_01 / courtyard_02 与新流程的回归（`[TEST:courtyard]` 行）。
##
## 覆盖：
##   · 禁跳跃（player_can_jump = false 真的下发到玩家）
##   · A/D 行走 → RUN / IDLE 状态与朝向翻转
##   · 相机：人物居中；到左右边缘画面停住、人物继续走
##   · 场景边界墙挡住人物
##   · E 调查走共用对话框、提示语上屏
##   · 尾部小关卡：x>=7900 一次性激活、x<=7800 黑幕重置回 x=8300、解锁后失效
##   · 三重旋锁：三层命中不互抢、45° 档位 / 半档回弹 / 跨 ±180°
##   · 原点是顺时针硬停点：只拨得动逆时针，拨回来停在原点
##   · 锁的判定：点「解锁」才结算；顺序错→归位+提示，次数错→静默归位
##   · 门后始终有实体阻挡；开锁 = 自动跳转 courtyard_02，不靠徒步走过去
##   · 出口门槛：锁没开走不了；开锁后按 E 走向 courtyard_02（含读档恢复）
##   · 前情提要：逐段推进、最后一段之后发 finished
##   · 画廊 + 全局存储：解锁 / NEW 角标 / 跨"存档"保留
##
## 手动（真键盘）：走动手感、贴边感觉、前情提要节奏。

const LEVEL_01 := "res://scenes/levels/courtyard_01.tscn"
const PROLOGUE := "res://scenes/ui/prologue.tscn"
const GALLERY := "res://scenes/ui/gallery.tscn"
const UNLOCK_FLAG := InnerGateLockConfig.FLAG_DOOR_UNLOCKED

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
	await _test_camera_left_gate_latch()
	await _test_interaction_and_memory()
	await _test_choice_layout()
	await _test_exit_gate()
	await _test_exit_gate_restored()
	await _test_backtrack_trap()
	await _test_rotary_lock()
	await _test_origin_clockwise_stop()
	await _test_rotary_lock_solution()
	await _test_unlock_button_click()
	await _test_gate_blocker()
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


## 「走过就落闸」的左闸门（`FollowCamera2D.arm_left_gate_latch()`）：
## 等**画面最左侧**自己走到闸门位置才落，落闸那一瞬间边界正好压在画面左缘上，
## 所以画面不会跳——这是尾部机关那道 7700 闸门用的机制。
##
## 全程把玩家留在场景中段：越过 x=7900 会激活尾部机关，那会挂上它自己的
## 闸门，两者会互相覆盖。
func _test_camera_left_gate_latch() -> void:
	var level = await _load_level()
	var p: Player = level.get_node("Player")
	var cam: FollowCamera2D = level.get_node("FollowCamera2D")
	var view_w := cam.get_viewport_rect().size.x / cam.zoom.x
	var west := 3000.0
	var east := 3000.0 + view_w
	# 闸门放在"人站在 east 时画面左缘刚好越过"的位置，同时保证站在 west 时
	# 画面左缘还没到——这样两个方向都是真的走出来的，不靠写死像素。
	var latch_x := int(west + view_w * 0.25)

	cam.arm_left_gate_latch(latch_x)
	p.global_position.x = west
	await get_tree().process_frame
	await get_tree().process_frame
	_check(cam.is_left_gate_latch_armed(), "闸门已挂上，等画面自己走到位")
	_check(cam.get_screen_left_edge() < float(latch_x), "画面左缘还在闸门以西")
	_check(cam.limit_left != latch_x, "画面左缘没到闸门位置时不落闸")

	p.global_position.x = east
	await get_tree().process_frame
	await get_tree().process_frame
	_check(cam.get_screen_left_edge() >= float(latch_x), "画面左缘已经走过闸门位置")
	_check(cam.limit_left == latch_x, "画面左缘走过闸门位置 → 落闸")

	p.global_position.x = west
	await get_tree().process_frame
	await get_tree().process_frame
	_check(cam.limit_left == latch_x, "落闸之后往西走画面也让不回去")

	await _drop(level)


# --- 交互与信物 -----------------------------------------------------------------

func _test_interaction_and_memory() -> void:
	var level = await _load_level()
	var p: Player = level.get_node("Player")
	var box = level.get_node("DialogueBox")
	var prompt: Label = level.get_node("UI/PromptLabel")
	var gate: Interactable = level.get_node("Props/GateSpot")

	# E 调查 → 文字进共用对话框
	gate.interact(p)
	_check(bool(box.is_showing()), "调查后共用对话框打开")
	_check(String(gate.display_text).begins_with(String(box.get_current_text())),
		"院门文字进对话框（对齐节点自己的文案，不写死措辞）")
	_check(p.is_input_locked(), "读文字期间玩家被锁")
	# 旁白字幕必须整块落在画布内（纵向居中之后，悬在画面外的面板会让字看不见）
	var narration_panel: Control = level.get_node("DialogueBox/Root/Panel")
	var canvas_h := narration_panel.get_viewport_rect().size.y
	_check(narration_panel.get_global_rect().end.y <= canvas_h + 0.01,
		"旁白字幕面板不出画布下缘")
	var bars: FrameBars = level.get_node("FrameBars")
	_check(narration_panel.get_global_rect().position.y >= canvas_h - bars.get_bar_height() - 0.01,
		"旁白字幕面板落在下方黑边框内")
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

	await _drop(level)


## 选项自成侧边一列：必须整块落在对话框面板内（塞在正文下面时会被挤出去）。
func _test_choice_layout() -> void:
	var level = await _load_level()
	var box = level.get_node("DialogueBox")
	var panel: Control = level.get_node("DialogueBox/Root/Panel")
	var choices: Control = level.get_node("DialogueBox/Root/Panel/Margin/HBox/ChoiceList")

	box.ask("（测试）要拔除这丛杂草吗？", PackedStringArray(["拔除", "算了"]))
	while not bool(box.is_choosing()):
		box.advance()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(choices.visible, "进入选择态后选项列显示")
	_check(choices.get_child_count() == 2, "两个选项都生成了")
	var panel_rect := panel.get_global_rect()
	var choice_rect := choices.get_global_rect()
	# 横向：选项列必须落在面板内（原来塞在正文下面时就是横向被挤掉的）。
	# **只查横向**：纵向取决于黑边多高，而 headless 的假窗口比正式分辨率小得多
	# （那里黑边只有 90px，正式是 180px），拿它断言纵向会假报错。
	_check(panel_rect.position.x <= choice_rect.position.x + 0.01
			and choice_rect.end.x <= panel_rect.end.x + 0.01,
		"选项列横向落在对话框面板内")
	for child in choices.get_children():
		var r := (child as Control).get_global_rect()
		_check(panel_rect.position.x <= r.position.x + 0.01
				and r.end.x <= panel_rect.end.x + 0.01,
			"选项「%s」横向完整显示" % (child as Label).text)
	# 纵向：按**设计分辨率**下的黑边（180）减去上下内缩来核对放不放得下，
	# 这条和当前视口无关，才是真正要守住的设计约束。
	_check(choices.get_combined_minimum_size().y <= 160.0,
		"选项列高度放得进正式分辨率的黑边内")
	# 选项在正文的侧边，不再压在正文下方
	var text_label: Control = level.get_node(
		"DialogueBox/Root/Panel/Margin/HBox/TextColumn/TextLabel")
	_check(choice_rect.position.x >= text_label.get_global_rect().end.x - 0.01
			or choice_rect.end.x <= text_label.get_global_rect().position.x + 0.01,
		"选项列在正文的左侧或右侧，不与正文上下叠")

	box.select_choice(0)
	await get_tree().process_frame
	_check(not bool(box.is_showing()), "选完之后框收掉")

	await _drop(level)


# --- 出口门槛：三重旋锁 -------------------------------------------------------

func _test_exit_gate() -> void:
	StoryFlagManager.clear_flag(UNLOCK_FLAG)
	var level = await _load_level()
	var p: Player = level.get_node("Player")
	var exit_node: LevelExit = level.get_node("Props/ToNextLevel")
	var lock: RotaryLockUI = level.get_node("RotaryLock")
	var left: Array[String] = []
	level.level_left.connect(func(target: String) -> void: left.append(target))

	_check(is_equal_approx(exit_node.global_position.x, 9000.0),
		"门的交互点在 x=9000")
	_check(not exit_node.is_open(), "锁没开时出口关着")
	exit_node.interact(p)
	_check(left.is_empty(), "锁没开时不会切场景")
	_check(exit_node.get_interaction_prompt() == exit_node.blocked_prompt_text,
		"锁没开时显示锁着提示")
	_check(lock.is_open(), "按 E 撞上锁着的门 → Director 弹出旋锁界面")
	_check(p.is_input_locked(), "旋锁界面打开期间玩家被锁")
	lock.close()
	_check(not lock.is_open(), "收手 / Esc 能关掉旋锁界面")
	_check(not p.is_input_locked(), "关掉界面后玩家解锁")
	_check(not StoryFlagManager.has_flag(UNLOCK_FLAG), "主动关闭不算解锁")
	_check(not exit_node.is_open(), "主动关闭没有改变门的状态")

	# 输完正确序列 → Director 写 Flag、门槛放开
	lock.open()
	await _solve_lock(lock)
	_check(StoryFlagManager.has_flag(UNLOCK_FLAG), "正确序列 → 写下门已解锁的 Flag")
	_check(not lock.is_open(), "成功后界面自动关闭")
	_check(exit_node.is_open(), "解锁后出口打开")
	_check(left.size() == 1 and left[0].ends_with("courtyard_02.tscn"),
		"开锁后自动跳转 courtyard_02")

	exit_node.interact(p)
	_check(left.size() == 1, "重复触发只走一次")

	await _drop(level)
	StoryFlagManager.clear_flag(UNLOCK_FLAG)


## 读档 / 重进关卡：Flag 在 → 锁不用再解，尾部封锁直接失效。
func _test_exit_gate_restored() -> void:
	StoryFlagManager.set_flag(UNLOCK_FLAG)
	var level = await _load_level()
	var exit_node: LevelExit = level.get_node("Props/ToNextLevel")
	var lock: RotaryLockUI = level.get_node("RotaryLock")
	var trap: BacktrackTrap = level.get_node("Props/InnerGateTrap")

	_check(exit_node.is_open(), "带着解锁 Flag 进关，门是开的")
	var left: Array[String] = []
	level.level_left.connect(func(target: String) -> void: left.append(target))
	exit_node.interact(level.get_node("Player"))
	_check(left.size() == 1 and left[0].ends_with("courtyard_02.tscn"),
		"已解锁时按 E 直接进里院")
	_check(lock.is_solved(), "锁已经是解开状态，不会再要求重解")
	_check(not trap.is_armed(), "解锁后返回封锁不再生效")

	await _drop(level)
	StoryFlagManager.clear_flag(UNLOCK_FLAG)


# --- 尾部返回封锁 + 黑幕重置 ---------------------------------------------------

func _test_backtrack_trap() -> void:
	StoryFlagManager.clear_flag(UNLOCK_FLAG)
	var level = await _load_level()
	var p: Player = level.get_node("Player")
	var trap: BacktrackTrap = level.get_node("Props/InnerGateTrap")
	var wall: StaticBody2D = level.get_node("Terrain/TrapWall")
	var box = level.get_node("DialogueBox")

	_check(not trap.is_activated(), "还没走到尾部时陷阱未激活")
	_check(wall.collision_layer == 0, "未激活时西侧硬边界不挡路")

	# 首次到达 7900 → 激活一次
	var activations := [0]
	trap.activated.connect(func() -> void: activations[0] += 1)
	p.global_position.x = InnerGateLockConfig.TRAP_ACTIVATE_X + 10.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(trap.is_activated(), "到达 x>=7900 激活陷阱")
	_check(not bool(box.is_showing()), "首次进入尾部区域不出字幕")
	_check(activations[0] == 1, "激活只发生一次")
	_check(wall.collision_layer == 1, "激活后西侧硬边界立起来")

	# 再往东走一段不会重复初始化
	p.global_position.x = InnerGateLockConfig.TRAP_ACTIVATE_X + 300.0
	await get_tree().physics_frame
	_check(activations[0] == 1, "继续移动不会重复激活")

	# 往西越过 7800 → 一次黑幕重置到 8300
	var resets := [0]
	trap.reset_started.connect(func() -> void: resets[0] += 1)
	var fade: ScreenFade = level.get_node("ScreenFade")
	_check(fade != null, "关卡里接上了共用黑幕 ScreenFade")
	p.global_position.x = InnerGateLockConfig.TRAP_RESET_X - 5.0
	await get_tree().physics_frame
	_check(trap.is_resetting(), "越过 x<=7800 开始黑幕重置")
	_check(fade.is_fading() or fade.is_opaque(), "重置走的是共用黑幕过渡")
	_check(p.is_input_locked(), "黑幕期间玩家被锁住")
	await get_tree().physics_frame
	_check(resets[0] == 1, "重置过程中不会重复触发")
	while trap.is_resetting():
		await get_tree().process_frame
	_check(is_equal_approx(p.global_position.x, InnerGateLockConfig.TRAP_RESPAWN_X),
		"重置后落在 x=8300")
	_check(absf(p.velocity.x) < 0.01, "重置后水平速度已清零")
	# 淡出后陷阱自己那把锁一定还掉了；此刻玩家可能仍被「被送回来」的
	# 那句台词（对话框锁）按住，那是对话框的正常行为，不属于本机关。
	_check(not p.get_input_lock_sources().has(BacktrackTrap.LOCK_SOURCE),
		"淡出后陷阱交还了自己那把输入锁")
	await get_tree().physics_frame
	_check(resets[0] == 1, "落点不会立刻再次触发重置")
	_check(bool(box.is_showing()), "第一次被送回来有字幕解释")
	while bool(box.is_showing()):
		box.advance()

	# 第二次被送回来：直接黑幕重生，不再重复那句解释
	p.global_position.x = InnerGateLockConfig.TRAP_RESET_X - 5.0
	await get_tree().physics_frame
	while trap.is_resetting():
		await get_tree().process_frame
	_check(resets[0] == 2, "可以再次触发黑幕重置")
	_check(is_equal_approx(p.global_position.x, InnerGateLockConfig.TRAP_RESPAWN_X),
		"第二次也落在 x=8300")
	_check(not bool(box.is_showing()), "第二次起不再出字幕")

	# 相机闸门：激活时只"挂上"待落闸门，落闸时机（画面左缘走到 7700）
	# 是相机自己的行为，在 _test_camera 里单测——那里可以随意摆位置，
	# 不会因为往西走越过 7800 而触发重置。
	var cam: FollowCamera2D = level.get_node("FollowCamera2D")
	_check(cam.is_left_gate_latch_armed(), "进入尾部区域后挂上待落的左闸门")
	_check(cam.limit_left != int(InnerGateLockConfig.TRAP_CAMERA_GATE_X),
		"刚激活时还没落闸（画面左缘还没走到 7700）")

	# 解锁后旧机关彻底失效
	StoryFlagManager.set_flag(UNLOCK_FLAG)
	var director = level.get_node("StoryDirector")
	director._apply_inner_gate_lock()
	_check(not trap.is_armed(), "解锁后机关解除")
	_check(wall.collision_layer == 0, "解锁后硬边界撤掉")
	p.global_position.x = InnerGateLockConfig.TRAP_RESET_X - 100.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(not trap.is_resetting(), "解锁后往西走不再被送回")
	_check(resets[0] == 2, "解锁后旧触发器不再传送玩家（次数停在解锁前的 2 次）")
	# 相机闸门交还给西侧通路：杂草还没拔 → 回到 1350，而不是彻底放开
	_check(cam.limit_left == 1350, "解锁后画面左边界交还给西侧杂草的闸门")
	_check(not cam.is_left_gate_latch_armed(), "解锁后待落闸门也撤掉了")

	await _drop(level)
	StoryFlagManager.clear_flag(UNLOCK_FLAG)


# --- 三重旋锁：拖拽 / 档位 / 判定 ---------------------------------------------

## 绕锁心把某一层拖过 delta_deg 度（分成 steps 段，模拟鼠标移动轨迹）。
## 纯逻辑驱动，headless 也能跑；真实鼠标手感仍需人工确认。
func _drag_ring(ring: RotaryLockRing, delta_deg: float, steps: int = 24) -> void:
	# 吸附 / 回弹期间这一层会拒绝新的拖拽（防状态错乱），所以先等它落定。
	await _wait_settled(ring)
	var center: Vector2 = (ring.get_parent() as Control).global_position
	var radius := 100.0
	ring.begin_drag(center + Vector2(radius, 0.0))
	for i in range(1, steps + 1):
		var a := delta_deg * float(i) / float(steps)
		ring.update_drag(center + Vector2(radius, 0.0).rotated(deg_to_rad(a)))
	ring.end_drag()
	await _wait_settled(ring)


func _wait_settled(ring: RotaryLockRing) -> void:
	while ring.is_settling():
		await get_tree().process_frame


## 按谜底输入完整正确序列，然后点「解锁」。谜底改了这里不用改——读同一份配置。
func _solve_lock(lock: RotaryLockUI) -> void:
	for step in InnerGateLockConfig.SOLUTION:
		await _turn(lock, step["layer"], int(step["steps"]))
	lock.try_unlock()
	# 成功演出有一小段时长（solved 在演出之后发），等界面自己关掉。
	while lock.is_open():
		await get_tree().process_frame


## 把某一层拨 steps 档。**逆时针**（负角度）——原点是顺时针的硬停点，
## 从 0 档只拨得动逆时针，测试必须走玩家真正能走的那条路。
func _turn(lock: RotaryLockUI, layer_id: StringName, steps: int) -> void:
	await _drag_ring(lock.get_ring(layer_id),
		-InnerGateLockConfig.DETENT_DEGREES * float(steps))


func _test_rotary_lock() -> void:
	var level = await _load_level()
	var lock: RotaryLockUI = level.get_node("RotaryLock")
	var outer: RotaryLockRing = lock.get_ring(InnerGateLockConfig.LAYER_OUTER)
	var middle: RotaryLockRing = lock.get_ring(InnerGateLockConfig.LAYER_MIDDLE)
	var inner: RotaryLockRing = lock.get_ring(InnerGateLockConfig.LAYER_INNER)
	_check(outer != null and middle != null and inner != null, "三层都在场上")
	var center: Vector2 = (outer.get_parent() as Control).global_position

	# 命中区域：外层从中层外缘接管到自己的大半径，不会无限扩张。
	_check(inner.contains_point(center + Vector2(20, 0)), "锁心附近命中内层")
	_check(not middle.contains_point(center + Vector2(20, 0)), "内层的点不属于中层")
	_check(not outer.contains_point(center + Vector2(20, 0)), "内层的点不属于外层")
	# 半径按正式素材实测：瓶子 109 / 圆环 109-226 / 四叶草 226-408
	_check(middle.contains_point(center + Vector2(160, 0)), "中环命中中层")
	_check(not outer.contains_point(center + Vector2(160, 0)), "中环的点不属于外层")
	_check(not inner.contains_point(center + Vector2(160, 0)), "中环的点不属于内层")
	_check(outer.contains_point(center + Vector2(0, -320)), "四叶草圈命中外层")
	_check(not middle.contains_point(center + Vector2(0, -320)), "外圈的点不属于中层")
	_check(not outer.contains_point(center + Vector2(0, -430)), "素材最外缘之外不命中")

	# 档位：不足半档回弹、不计数
	var steps: Array[int] = []
	outer.detent_stepped.connect(func(d: int) -> void: steps.append(d))
	await _drag_ring(outer, -10.0)
	_check(steps.is_empty(), "不足半档（10°）不产生档位输入")
	_check(outer.get_detent_index() == 0, "不足半档回弹到原档位")

	# 超过半档（45° 的半档 = 22.5°）→ 吸附到下一档并计一次：
	# 原点是顺时针的硬停点，从 0 档顺时针根本拨不动（另见
	# `_test_origin_clockwise_stop`）。
	steps.clear()
	await _drag_ring(outer, -(InnerGateLockConfig.HALF_DETENT_DEGREES + 1.0))
	_check(steps == [-1], "超过 22.5° 半档阈值后吸附到下一档并计一次")
	_check(outer.get_detent_index() == -1, "档位下标 -1")

	# 快速跨多档逐档计数（3 档 = 135°，一次拖到位）
	steps.clear()
	await _drag_ring(outer, -InnerGateLockConfig.DETENT_DEGREES * 3.0, 1)
	_check(steps == [-1, -1, -1], "一次快速拖过 3 档逐档计数，不漏计")
	_check(outer.get_detent_index() == -4, "档位累计正确")

	# 反向（拨回来）计数
	steps.clear()
	await _drag_ring(outer, InnerGateLockConfig.DETENT_DEGREES * 2.0)
	_check(steps == [1, 1], "反向拖动计成两档顺时针")
	_check(outer.get_detent_index() == -2, "反向后档位下标正确")

	# 跨 ±180° 不跳变：从 -170° 开始连续往逆时针拖 40°（正好跨过 ±180°）
	steps.clear()
	outer.set_detent_index(0)
	var radius := 100.0
	outer.begin_drag(center + Vector2(radius, 0.0).rotated(deg_to_rad(-170.0)))
	for i in range(1, 6):
		outer.update_drag(center + Vector2(radius, 0.0).rotated(deg_to_rad(-170.0 - i * 5.0)))
	outer.end_drag()
	_check(steps == [-1], "跨 -179°→179° 连续拖动仍是一档逆时针，无跳变")

	await _drop(level)


## 原点是顺时针方向的硬停点：从 0 档只拨得动逆时针。拨出去之后可以顺时针
## 拨回来，但回到原点就停住。这是给玩家的方向暗示。
func _test_origin_clockwise_stop() -> void:
	StoryFlagManager.clear_flag(UNLOCK_FLAG)
	var level = await _load_level()
	var lock: RotaryLockUI = level.get_node("RotaryLock")
	var ring: RotaryLockRing = lock.get_ring(InnerGateLockConfig.LAYER_MIDDLE)
	var steps := [0]
	ring.detent_stepped.connect(func(_d: int) -> void: steps[0] += 1)
	lock.open()

	# 原点往顺时针拨三档的量：一档都不该动
	await _drag_ring(ring, InnerGateLockConfig.DETENT_DEGREES * 3.0)
	_check(ring.get_detent_index() == 0, "原点顺时针拨不动（档位停在 0）")
	_check(steps[0] == 0, "原点顺时针拨不产生档位输入")
	_check(absf(ring.rotation_degrees) < 0.01, "原点顺时针拨不动（角度也没变）")
	_check(lock.get_input_log().is_empty(), "原点顺时针拨不进输入序列")

	# 逆时针照常
	await _drag_ring(ring, -InnerGateLockConfig.DETENT_DEGREES * 2.0)
	_check(ring.get_detent_index() == -2, "逆时针照常拨得动")
	_check(steps[0] == 2, "逆时针两档记两次")

	# 拨出去之后可以顺时针拨回来，但停在原点、不越过去
	await _drag_ring(ring, InnerGateLockConfig.DETENT_DEGREES * 5.0)
	_check(ring.get_detent_index() == 0, "顺时针只能拨回原点，不会越过")
	_check(steps[0] == 4, "拨回来的两档照常计数（只计到原点为止）")

	lock.close()
	await _drop(level)
	StoryFlagManager.clear_flag(UNLOCK_FLAG)


func _test_rotary_lock_solution() -> void:
	StoryFlagManager.clear_flag(UNLOCK_FLAG)
	var level = await _load_level()
	var lock: RotaryLockUI = level.get_node("RotaryLock")
	var solved := [0]
	lock.solved.connect(func() -> void: solved[0] += 1)
	var inner := InnerGateLockConfig.LAYER_INNER
	var outer := InnerGateLockConfig.LAYER_OUTER
	var middle := InnerGateLockConfig.LAYER_MIDDLE
	var hint: Label = level.get_node("RotaryLock/Root/HintLabel")
	var default_hint := hint.text

	lock.open()

	# 转动本身不结算：把正确序列拨完但**不点解锁**，锁不该开
	await _turn(lock, inner, 4)
	await _turn(lock, outer, 5)
	await _turn(lock, middle, 2)
	_check(solved[0] == 0, "转到位但没点解锁 → 不结算")
	_check(lock.get_input_log().size() == 3, "输入序列记成三个阶段")
	_check(int(lock.get_input_log()[0]["steps"]) == 4, "连续拨同一层并进同一阶段")

	# 顺序错：梅花 → 瓶子 → 圆
	lock.close()
	lock.open()
	await _turn(lock, outer, 5)
	await _turn(lock, inner, 4)
	await _turn(lock, middle, 2)
	lock.try_unlock()
	_check(solved[0] == 0, "顺序错不能开锁")
	_check(hint.text == lock.wrong_order_hint, "顺序错弹出提示")
	_check(lock.get_input_log().is_empty(), "顺序错后清空操作记录")
	_check(lock.get_ring(inner).get_detent_index() == 0
		and lock.get_ring(outer).get_detent_index() == 0
		and lock.get_ring(middle).get_detent_index() == 0,
		"顺序错后三层归位")

	# 顺序错（换层之后回头拨之前那层）：瓶子 → 梅花 → 瓶子 → 圆
	await _turn(lock, inner, 4)
	await _turn(lock, outer, 5)
	await _turn(lock, inner, 1)
	await _turn(lock, middle, 2)
	_check(lock.get_input_log().size() == 4, "回头拨之前那层会多出一个阶段")
	lock.try_unlock()
	_check(solved[0] == 0, "回头拨之前那层判成顺序错")
	_check(hint.text == lock.wrong_order_hint, "同样弹出顺序提示")

	# 次数错（顺序对）：瓶子×3 → 梅花×5 → 圆×2，静默归位
	await _turn(lock, inner, 3)
	_check(hint.text == default_hint, "重新开始转动后提示复位")
	await _turn(lock, outer, 5)
	await _turn(lock, middle, 2)
	lock.try_unlock()
	_check(solved[0] == 0, "次数错不能开锁")
	_check(hint.text == default_hint, "次数错**不**出任何提示")
	_check(lock.get_input_log().is_empty(), "次数错后同样清空操作记录")
	_check(lock.get_ring(inner).get_detent_index() == 0, "次数错后也归位")

	# 归位之后按钮还能继续用：这次输对
	await _solve_lock(lock)
	_check(solved[0] == 1, "失败归位后仍可再次提交，正确序列开锁")
	_check(lock.is_solved(), "开锁后锁进入已解状态")
	var unlock_button: Button = level.get_node("RotaryLock/Root/UnlockButton")
	_check(unlock_button.disabled, "开锁后解锁按钮禁用，防重复提交")
	lock.try_unlock()
	_check(solved[0] == 1, "开锁后再提交也不会重复结算")
	for step in InnerGateLockConfig.SOLUTION:
		var ring: RotaryLockRing = lock.get_ring(step["layer"])
		_check(not ring.begin_drag(Vector2.ZERO),
			"开锁后 %s 层不能再拖" % step["layer"])

	await _drop(level)
	StoryFlagManager.clear_flag(UNLOCK_FLAG)


# --- 「解锁」按钮的真实点击路径 -----------------------------------------------

## 用 `push_input()` 走**真正的输入管线**（_input → GUI 派发），确认锁体不会
## 把按钮的点击吞掉：`_input()` 跑在 GUI 之前，无条件 set_input_as_handled()
## 会让按钮完全点不动，这条测试就是为了钉住这一点。
func _click_at(position: Vector2) -> void:
	for is_pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = is_pressed
		ev.position = position
		ev.global_position = position
		get_viewport().push_input(ev, true)
		await get_tree().process_frame


func _test_unlock_button_click() -> void:
	StoryFlagManager.clear_flag(UNLOCK_FLAG)
	var level = await _load_level()
	var lock: RotaryLockUI = level.get_node("RotaryLock")
	var button: Button = level.get_node("RotaryLock/Root/UnlockButton")
	var clicks := [0]
	button.pressed.connect(func() -> void: clicks[0] += 1)

	lock.open()
	await get_tree().process_frame
	_check(button.visible and not button.disabled, "界面打开时「解锁」按钮可用")

	# 点按钮：事件必须穿过锁体到达 GUI
	await _click_at(button.get_global_rect().get_center())
	_check(clicks[0] == 1, "鼠标点击「解锁」按钮能触发（锁体没吞掉事件）")

	# 点在锁体上：这次应该被锁体接管（开始拖某一层），不透给 GUI
	var center: Vector2 = (lock.get_ring(InnerGateLockConfig.LAYER_INNER)
		.get_parent() as Control).global_position
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = center
	ev.global_position = center
	get_viewport().push_input(ev, true)
	_check(get_viewport().is_input_handled(), "点在锁体上时事件被锁体接管")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = center
	release.global_position = center
	get_viewport().push_input(release, true)
	await get_tree().process_frame
	_check(clicks[0] == 1, "拖锁体不会顺手按到按钮")

	lock.close()
	await _drop(level)
	StoryFlagManager.clear_flag(UNLOCK_FLAG)


# --- 未解锁时的通行阻挡 -------------------------------------------------------

func _test_gate_blocker() -> void:
	StoryFlagManager.clear_flag(UNLOCK_FLAG)
	var level = await _load_level()
	var p: Player = level.get_node("Player")
	var blocker: StaticBody2D = level.get_node("Terrain/InnerGateBlocker")
	var lock: RotaryLockUI = level.get_node("RotaryLock")
	var director = level.get_node("StoryDirector")
	var left: Array[String] = []
	level.level_left.connect(func(target: String) -> void: left.append(target))

	_check(blocker.collision_layer == 1, "锁没开时门后有实体阻挡")
	# 真的走过去撞一下：站在门前往东按住 D，不该越过挡墙
	p.global_position.x = 8950.0
	await get_tree().physics_frame
	await _hold(&"move_right", 60)
	_check(p.global_position.x < blocker.global_position.x,
		"锁没开时走不过门（被挡墙拦住）")

	# 开锁 → 自动进里院，**阻挡不撤**（右边那片地方永远走不进去）
	lock.open()
	await _solve_lock(lock)
	_check(StoryFlagManager.has_flag(UNLOCK_FLAG), "解锁 Flag 已写下")
	_check(left.size() == 1 and left[0].ends_with("courtyard_02.tscn"),
		"开锁后自动跳转 courtyard_02")
	_check(blocker.collision_layer == 1, "开锁后阻挡仍在，不能徒步绕到锁右边")
	await _hold(&"move_right", 60)
	_check(p.global_position.x < blocker.global_position.x, "开锁后依旧走不过挡墙")

	# 读档恢复链路同样保持阻挡
	director._apply_inner_gate_lock()
	_check(blocker.collision_layer == 1, "带解锁 Flag 恢复时阻挡照旧")

	await _drop(level)
	StoryFlagManager.clear_flag(UNLOCK_FLAG)


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
