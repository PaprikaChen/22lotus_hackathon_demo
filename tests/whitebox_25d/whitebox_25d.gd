extends LevelBase
## 2.5D 白盒验证关卡 — 纯几何测试房，不是正式关卡内容。
##
## 验证目标：横向为主、纵深为辅的移动模式（MovementMode.DEPTH_2_5D）能和
## 现有的纯 2D 横版模式共存，且 Y Sort / 碰撞 / 信物 / 存档全部照常工作。
##
## 本关卡自己只负责三件白盒专属的事：相机跟随（X 跟随、Y 固定）、调试叠层、
## 可关闭的纵深缩放实验。移动模式本身属于正式系统（MovementMode + player.gd），
## 这里只是把 movement_mode 配成 DEPTH_2_5D 而已。
##
## 手动操作：A/D 左右，W/S 前后（纵深），E 交互，Tab 梦奁，Shift 慢时间。
## F1 开关调试叠层，F2 开关 Y Sort 原点标记。空格在本模式下无效（无跳跃）。
##
## 无头模式会跑一遍结构与碰撞断言（[TEST:whitebox25d] 行）并自动退出。

## 纵深可行走带在世界坐标里的前后边界，用于归一化显示与缩放实验。
@export var depth_back_y: float = 240.0
@export var depth_front_y: float = 520.0

@export_group("Camera")
## 相机 Y 固定：纵深范围很小，跟随 Y 会让画面上下漂。
@export var camera_fixed_y: float = 380.0

@export_group("Debug")
@export var show_debug_overlay: bool = true
@export var show_origin_gizmos: bool = true

@export_group("Depth scaling (实验性)")
## 第一阶段默认关闭：先确认移动/排序/碰撞/镜头，再谈视觉缩放。
@export var enable_depth_scaling: bool = false
@export var depth_scale_back: float = 0.92
@export var depth_scale_front: float = 1.0

const COLLECTIBLE_01 := &"whitebox_25d_collectible_01"
const COLLECTIBLE_02 := &"whitebox_25d_collectible_02"

@onready var _p: CharacterBody2D = get_node(player_path)
@onready var _detector: InteractionDetector = _p.get_node("InteractionDetector")
@onready var _camera: Camera2D = $Camera2D
@onready var _ysort_root: Node2D = $YSortRoot
@onready var _background: Node2D = $Background
@onready var _foreground: Node2D = $Foreground
@onready var _overlay: Label = $UI/DebugOverlay
@onready var _prompt_label: Label = $UI/PromptLabel
@onready var _result_label: Label = $UI/ResultLabel
@onready var _pillar: Node2D = $YSortRoot/TestPillar
@onready var _tree: Node2D = $YSortRoot/TestTree
@onready var _collectible_01: Interactable = $YSortRoot/Collectible01
@onready var _collectible_02: Interactable = $YSortRoot/Collectible02
@onready var _save_point: Interactable = $YSortRoot/SavePoint
@onready var _goal: Area2D = $YSortRoot/Goal

var _pass_count: int = 0
var _fail_count: int = 0
var _f1_held: bool = false
var _f2_held: bool = false


func _ready() -> void:
	super._ready()
	_detector.prompt_changed.connect(_on_prompt_changed)
	_collectible_01.interacted.connect(func(_pl: Node) -> void: _show("拾取了 白盒信物 甲"))
	_collectible_02.interacted.connect(func(_pl: Node) -> void: _show("拾取了 白盒信物 乙"))
	_save_point.connect("save_finished", _show)
	_goal.body_entered.connect(_on_goal_entered)
	_apply_gizmo_visibility()
	_update_camera()
	if DisplayServer.get_name() == "headless":
		_run_self_test.call_deferred()


func _process(_delta: float) -> void:
	_read_debug_keys()
	_update_camera()
	_apply_depth_scaling()
	_overlay.visible = show_debug_overlay
	if show_debug_overlay:
		_overlay.text = _build_debug_text()


# --- Camera (§34-36: follow X, fixed Y) ---------------------------------------

func _update_camera() -> void:
	# Camera2D limits clamp the horizontal follow; Y never follows the player
	# because the depth band is only a few hundred pixels tall.
	_camera.global_position = Vector2(_p.global_position.x, camera_fixed_y)


# --- Depth helpers -------------------------------------------------------------

## 0.0 at the far edge, 1.0 at the near edge.
func get_depth_normalized() -> float:
	var span := depth_front_y - depth_back_y
	if is_zero_approx(span):
		return 0.0
	return clampf((_p.global_position.y - depth_back_y) / span, 0.0, 1.0)


## Optional experiment (§37): further back reads slightly smaller. Only the
## player's Visual is scaled — never the body, so collision stays honest.
func _apply_depth_scaling() -> void:
	var visual := _p.get_node_or_null("Visual") as Node2D
	if visual == null:
		return
	if not enable_depth_scaling:
		if not visual.scale.is_equal_approx(Vector2.ONE):
			visual.scale = Vector2.ONE
		return
	var s := lerpf(depth_scale_back, depth_scale_front, get_depth_normalized())
	visual.scale = Vector2(s, s)


# --- Debug overlay --------------------------------------------------------------

func _read_debug_keys() -> void:
	# Raw physical keys: debug toggles deliberately stay out of the InputMap.
	var f1 := Input.is_physical_key_pressed(KEY_F1)
	if f1 and not _f1_held:
		show_debug_overlay = not show_debug_overlay
	_f1_held = f1

	var f2 := Input.is_physical_key_pressed(KEY_F2)
	if f2 and not _f2_held:
		show_origin_gizmos = not show_origin_gizmos
		_apply_gizmo_visibility()
	_f2_held = f2


func _apply_gizmo_visibility() -> void:
	for node in get_tree().get_nodes_in_group(&"origin_gizmo"):
		var item := node as CanvasItem
		if item != null:
			item.visible = show_origin_gizmos


func _build_debug_text() -> String:
	var slot := "无（直接运行场景）" if SaveManager.current_slot == -1 else str(SaveManager.current_slot)
	return "\n".join([
		"Movement Mode : %s" % MovementMode.get_mode_name(_p.movement_mode),
		"Player X      : %.1f" % _p.global_position.x,
		"Player Y      : %.1f  (纵深)" % _p.global_position.y,
		"Depth Norm    : %.2f  (0=后 1=前)" % get_depth_normalized(),
		"Speed X / Y   : %.0f / %.0f" % [_p.move_speed, _p.depth_move_speed],
		"Current Level : %s" % String(level_id),
		"Save Slot     : %s" % slot,
		"Collected     : %d / 2   Depth Scaling: %s" % [
			_collected_count(), "ON" if enable_depth_scaling else "OFF"],
		"",
		"A/D 左右   W/S 前后   E 交互   Tab 梦奁   F1 叠层   F2 原点标记",
	])


func _collected_count() -> int:
	var n := 0
	if MemoryManager.has_memory(COLLECTIBLE_01):
		n += 1
	if MemoryManager.has_memory(COLLECTIBLE_02):
		n += 1
	return n


func _show(message: String) -> void:
	_result_label.text = message


func _on_prompt_changed(text: String) -> void:
	_prompt_label.text = "[E] %s" % text if not text.is_empty() else ""


func _on_goal_entered(body: Node) -> void:
	if body == _p:
		_show("到达终点（白盒验证完成）")
		complete_level()


# --- Headless self-test ----------------------------------------------------------

func _check(cond: bool, label: String) -> void:
	if cond:
		_pass_count += 1
		print("[TEST:whitebox25d] PASS  %s" % label)
	else:
		_fail_count += 1
		print("[TEST:whitebox25d] FAIL  %s" % label)


## True when every Polygon2D under `root` is drawn at or above its owner's
## origin — i.e. the origin is the ground-contact point (§15/§16).
func _polygons_sit_on_origin(root: Node) -> bool:
	var found := false
	for child in root.get_children():
		var poly := child as Polygon2D
		if poly == null or poly.is_in_group(&"origin_gizmo"):
			continue
		found = true
		for point: Vector2 in poly.polygon:
			if point.y + poly.position.y > 0.5:
				return false
	return found


func _run_self_test() -> void:
	print("[TEST:whitebox25d] --- self-test start ---")
	await get_tree().physics_frame

	# --- Movement mode -----------------------------------------------------
	_check(_p.movement_mode == MovementMode.Mode.DEPTH_2_5D,
		"level puts the player in DEPTH_2_5D")
	_check(_p.motion_mode == CharacterBody2D.MOTION_MODE_FLOATING,
		"body switched to FLOATING motion (no floor / no snapping)")
	_check(_p.get_body_half_extents().y < 24.0,
		"depth mode uses the shallow ground footprint, not the standing body box")
	_check(_p.get_node("InteractionDetector").position.is_zero_approx(),
		"interaction reach is centred on the ground point in depth mode")
	_check(_p.depth_move_speed < _p.move_speed,
		"depth speed (%.0f) is clearly slower than horizontal (%.0f)" % [
			_p.depth_move_speed, _p.move_speed])
	_check(_p.get_depth_velocity_target(Vector2(1.0, 1.0).normalized()).x
			< _p.get_depth_velocity_target(Vector2.RIGHT).x,
		"diagonal input is not faster than a single axis (normalized)")

	# --- Spawn keeps BOTH coordinates (§46) --------------------------------
	var marker := get_node_or_null(spawn_point_path) as Node2D
	_check(marker != null and _p.global_position.is_equal_approx(marker.global_position),
		"spawned at the Marker2D with full Vector2 (x AND y)")

	# --- No gravity in depth mode ------------------------------------------
	var y_before := _p.global_position.y
	await get_tree().create_timer(0.5).timeout
	_check(absf(_p.global_position.y - y_before) < 0.5,
		"player does not fall: y unchanged after 0.5s (%.2f)" % _p.global_position.y)

	# --- Walkable-area boundaries (§12 / Boundary Test) --------------------
	_p.global_position = Vector2(1000.0, 400.0)
	await get_tree().physics_frame
	var t := _p.global_transform
	_check(_p.test_move(t, Vector2(0.0, -400.0)), "back boundary blocks moving further back")
	_check(_p.test_move(t, Vector2(0.0, 400.0)), "front boundary blocks moving further front")
	_check(_p.test_move(t, Vector2(-1200.0, 0.0)), "left boundary blocks")
	_check(_p.test_move(t, Vector2(2500.0, 0.0)), "right boundary blocks")
	_check(not _p.test_move(t, Vector2(0.0, -60.0)) and not _p.test_move(t, Vector2(0.0, 60.0)),
		"free to move inside the walkable band")

	# --- Obstacles: blocked head-on, walkable around (§Depth Test) ---------
	# The lanes are measured at the REACHABLE edges of the band, not at some
	# arbitrary offset: an obstacle whose footprint reaches past the back
	# boundary would silently seal the level off, and that must fail here.
	var body_half: float = _p.get_body_half_extents().y
	var back_lane := depth_back_y + body_half + 1.0
	var front_lane := depth_front_y - body_half - 1.0
	for obstacle: Node2D in [_pillar, _tree]:
		_p.global_position = Vector2(obstacle.global_position.x - 90.0, obstacle.global_position.y)
		await get_tree().physics_frame
		_check(_p.test_move(_p.global_transform, Vector2(180.0, 0.0)),
			"%s blocks a head-on approach at its own depth" % obstacle.name)
		_p.global_position = Vector2(obstacle.global_position.x - 90.0, back_lane)
		await get_tree().physics_frame
		_check(not _p.test_move(_p.global_transform, Vector2(220.0, 0.0)),
			"%s can be passed BEHIND at the far edge of the band" % obstacle.name)
		_p.global_position = Vector2(obstacle.global_position.x - 90.0, front_lane)
		await get_tree().physics_frame
		_check(not _p.test_move(_p.global_transform, Vector2(220.0, 0.0)),
			"%s can be passed IN FRONT at the near edge of the band" % obstacle.name)

	# --- Y Sort wiring (§14/§15/§17/§21) -----------------------------------
	_check(_ysort_root.y_sort_enabled, "YSortRoot has Y Sort enabled")
	_check(_background.get_index() < _ysort_root.get_index()
			and _ysort_root.get_index() < _foreground.get_index(),
		"draw order: Background < YSortRoot < Foreground")
	_check(not _background.y_sort_enabled and not _foreground.y_sort_enabled,
		"fixed layers stay out of Y Sort")
	for object_name in ["TestBlockA", "TestPillar", "TestTree", "TestBlockB"]:
		_check(_polygons_sit_on_origin(_ysort_root.get_node(object_name)),
			"%s draws above its origin (origin = ground contact)" % object_name)

	# --- Collectibles: existing 梦奁 system, unique ids (§23/§24/§55) ------
	_check(MemoryManager.get_memory_data(COLLECTIBLE_01) != null
			and MemoryManager.get_memory_data(COLLECTIBLE_02) != null,
		"both whitebox keepsakes are registered under unique ids")
	_collectible_01.interact(_p)
	_collectible_02.interact(_p)
	_check(MemoryManager.has_memory(COLLECTIBLE_01) and MemoryManager.has_memory(COLLECTIBLE_02),
		"collecting in 2.5D unlocks both keepsakes")
	_check(not _collectible_01.can_interact(_p), "collectible is one-shot (does not re-trigger)")

	# Round trip through the SAME save payload the real save file carries.
	var payload := MemoryManager.get_save_data()
	MemoryManager.reset()
	_check(not MemoryManager.has_memory(COLLECTIBLE_01), "reset clears runtime state")
	MemoryManager.load_save_data(payload)
	_check(MemoryManager.has_memory(COLLECTIBLE_01) and MemoryManager.has_memory(COLLECTIBLE_02),
		"collected state survives a save/load round trip")
	MemoryManager.reset()

	# --- Save point must not touch real files without an active slot -------
	_save_point.interact(_p)
	_check(SaveManager.current_slot == -1, "save point skips writing without an active slot")

	# --- The world is left clean -------------------------------------------
	_check(WorldTimeManager.current_state == WorldTimeManager.SlowTimeState.READY,
		"DreamGap READY (LevelBase reset ran in a 2.5D level too)")

	print("[TEST:whitebox25d] --- done: %d passed, %d failed ---" % [_pass_count, _fail_count])
	print("[TEST:whitebox25d] MANUAL: 手感、斜向移动、实际遮挡观感、前景遮挡需要真实键盘确认。")
	if DisplayServer.get_name() == "headless":
		get_tree().quit(_fail_count)
