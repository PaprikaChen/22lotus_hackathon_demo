extends LevelBase
## 手感实验房：一整张长幅背景草图 + 一条地面碰撞体。
##
## 目的：让真实的玩家移动脚本跑在真实比例的背景草图上，感受“人物速度 ×
## 场景建筑密度”的关系。房间里除了背景、地面、玩家、相机和 HUD 之外
## 什么都没有——这是调参台，不是关卡，不要往这里加关卡内容。
##
## 所有影响手感的量都能在运行时改，HUD 实时算出派生指标（走完全程几秒、
## 一屏几秒、人物占屏多高、一跳能跨多远），调到舒服为止再把数字抄进
## 正式关卡与 player.tscn。
##
## 运行时按键（避开 project.godot 已有的输入动作）：
##   A / D      左右走          Space 跳
##   [ / ]      移动速度 ∓25 px/s
##   - / =      背景缩放 ∓0.05
##   9 / 0      人物体型 ∓0.1
##   , / .      相机拉远 / 拉近
##   /          相机复位到“整张图高刚好占满屏幕”
##   ; / 单引号 地面线 上 / 下 1% 图高
##   1          全部参数复位到 Inspector 里的值
##   2 / 3 / 4  传送到全程 5% / 50% / 95%
##   T          秒表 开始 / 停止（实测走一段要多久）
##   H          显示 / 隐藏 HUD

## 地面碰撞体的厚度与左右各自多出的余量。够厚就不会被高速穿透。
const GROUND_THICKNESS: float = 400.0
const GROUND_EDGE_MARGIN: float = 600.0
## 出生点在全程宽度上的位置。
const SPAWN_X_RATIO: float = 0.02
## 掉出地面这么远就自动回出生点，省得手动传送。
const FALL_RESCUE_DEPTH: float = 900.0

@export_group("Layout")
## 背景整体缩放。1.0 = 1 张图的像素 ↔ 1 个世界单位。
@export_range(0.2, 3.0, 0.01) var background_scale: float = 1.0
## 地面线高度，按缩放后的图高比例算（0 = 图顶，1 = 图底）。
@export_range(0.0, 1.0, 0.01) var ground_line_ratio: float = 0.90

@export_group("Feel")
## 人物整体体型倍率（外观和碰撞盒一起缩放）。
@export_range(0.2, 5.0, 0.05) var player_scale: float = 1.0
## true = 开局自动把 zoom 设成“整张图高正好占满视口”。
@export var fit_background_height: bool = true
## fit_background_height 为 false 时使用的 zoom。
@export_range(0.15, 3.0, 0.01) var camera_zoom: float = 1.0

## 传送到某个物件时停在它左边这么远，免得直接卡进门里。
const APPROACH_OFFSET: float = 110.0

@onready var _background: Sprite2D = $Background
@onready var _ground_shape: CollisionShape2D = $Ground/GroundShape
@onready var _spawn: Marker2D = $SpawnPoint
@onready var _camera: Camera2D = $Camera2D
@onready var _hud: PanelContainer = $UI/HudPanel
@onready var _info: Label = $UI/HudPanel/Rows/InfoLabel
@onready var _prompt: Label = $UI/MsgPanel/Rows/PromptLabel
@onready var _event: Label = $UI/MsgPanel/Rows/EventLabel

## 可交互物都挂在 Props 下，按“图片像素”坐标摆放（y=0 就是地面线）。
## Props 整体跟着背景缩放和地面线走，所以调参时物件一直钉在画上同一处。
@onready var _props: Node2D = $Props
@onready var _tokens: Array[Interactable] = [
	$Props/Token01, $Props/Token02, $Props/Token03,
]
@onready var _door: Interactable = $Props/MemoryDoor

var _body: CharacterBody2D
var _detector: InteractionDetector
var _zoom: float = 1.0
## Inspector 里的初始值，按 1 复位时用。
var _defaults: Dictionary = {}
var _stopwatch_running: bool = false
var _stopwatch_time: float = 0.0
var _stopwatch_start_x: float = 0.0


func _ready() -> void:
	_body = get_node(player_path) as CharacterBody2D
	_defaults = {
		"background_scale": background_scale,
		"ground_line_ratio": ground_line_ratio,
		"player_scale": player_scale,
		"camera_zoom": camera_zoom,
		"move_speed": _body.move_speed,
	}
	# 布局必须先算好：LevelBase._ready() 会按 SpawnPoint 的位置放人。
	_apply_layout()
	super._ready()
	_apply_player_scale()
	_set_zoom(_fit_zoom() if fit_background_height else camera_zoom)
	_camera.make_current()
	_stopwatch_start_x = _body.global_position.x
	_wire_interactions()
	if DisplayServer.get_name() == "headless":
		_report_headless.call_deferred()


## 交互反馈全靠现成的信号：提示来自玩家身上的 InteractionDetector，
## 拾取/开门/被拦来自各个 Interactable 自己。调参台不碰它们的内部逻辑。
func _wire_interactions() -> void:
	_detector = _body.get_node("InteractionDetector") as InteractionDetector
	_detector.prompt_changed.connect(_on_prompt_changed)
	for token in _tokens:
		token.interacted.connect(_on_token_taken.bind(token))
	_door.interacted.connect(_on_door_opened)
	_door.interaction_blocked.connect(_on_door_blocked)


func _process(delta: float) -> void:
	_update_camera()
	if _stopwatch_running:
		_stopwatch_time += delta
	if _body.global_position.y > _ground_y() + FALL_RESCUE_DEPTH:
		_body.respawn()
	if _hud.visible:
		_update_hud()


# --- 布局 ---------------------------------------------------------------------

## 缩放后整张图占据的世界尺寸。原点在图的左上角。
func _world_size() -> Vector2:
	return _background.texture.get_size() * background_scale


func _ground_y() -> float:
	return _world_size().y * ground_line_ratio


## 背景缩放 / 地面线一改就重算：图的缩放、那一条地面碰撞体、出生点。
func _apply_layout() -> void:
	_background.scale = Vector2(background_scale, background_scale)
	var world := _world_size()
	var ground_y := world.y * ground_line_ratio
	var rect := _ground_shape.shape as RectangleShape2D
	rect.size = Vector2(world.x + GROUND_EDGE_MARGIN * 2.0, GROUND_THICKNESS)
	_ground_shape.position = Vector2(world.x * 0.5, ground_y + GROUND_THICKNESS * 0.5)
	_spawn.position = Vector2(world.x * SPAWN_X_RATIO, ground_y)
	# 先平移到地面线再整体缩放，子节点就能按图片像素坐标 + y=0 贴地来摆。
	_props.position = Vector2(0.0, ground_y)
	_props.scale = Vector2(background_scale, background_scale)


## 玩家原点就是脚底，所以整体缩放只会往上长，脚一直贴着地面线。
func _apply_player_scale() -> void:
	_body.scale = Vector2(player_scale, player_scale)


func _player_height() -> float:
	return _body.get_body_half_extents().y * 2.0 * player_scale


# --- 相机 ---------------------------------------------------------------------

## 让整张图的高刚好占满视口的 zoom。
func _fit_zoom() -> float:
	return get_viewport_rect().size.y / _world_size().y


func _set_zoom(value: float) -> void:
	_zoom = clampf(value, 0.15, 3.0)
	camera_zoom = _zoom
	_camera.zoom = Vector2(_zoom, _zoom)


## 只横向跟人，纵向固定在图的正中——跳跃时画面不晃，才看得准密度。
func _update_camera() -> void:
	var world := _world_size()
	var view := get_viewport_rect().size / _zoom
	var cam_x := _body.global_position.x
	if world.x > view.x:
		cam_x = clampf(cam_x, view.x * 0.5, world.x - view.x * 0.5)
	else:
		cam_x = world.x * 0.5
	_camera.global_position = Vector2(cam_x, world.y * 0.5)


# --- HUD ----------------------------------------------------------------------

func _update_hud() -> void:
	_info.text = "\n".join(_hud_rows())


## 启动参数的一次性快照。headless 下没有窗口可看，就靠它核对几何。
func _report_headless() -> void:
	for row in _hud_rows():
		print("[LAB:bg_pacing] ", row)
	print("[LAB:bg_pacing] 出生点 ", _spawn.position, "  玩家 ", _body.global_position)
	get_tree().quit(_run_gate_self_test())


## 顺手验一遍“信物开门”这道门槛本身，改 test_memory_door.gd 时能立刻发现回归。
## 只碰 MemoryManager，不模拟按键（MCP 注入不了按键边沿）。
func _run_gate_self_test() -> int:
	var door_memory := _door_memory()
	var fails := 0
	fails += _check(MemoryManager.get_memory_data(door_memory) != null,
		"门槛信物已注册：%s" % door_memory)
	fails += _check(not MemoryManager.has_memory(door_memory), "开局未持有门槛信物")
	fails += _check(not _door.is_requirement_met(), "未持有时门槛不满足")
	fails += _check(_door.get_interaction_prompt() == _door.blocked_prompt_text,
		"未持有时显示锁着提示")
	MemoryManager.unlock_memory(_token_memory(_tokens[0]))
	fails += _check(not _door.is_requirement_met(), "拾取无关信物后门仍然锁着")
	MemoryManager.unlock_memory(door_memory)
	fails += _check(_door.is_requirement_met(), "拾取门槛信物后门槛满足")
	fails += _check(_door.get_interaction_prompt() == _door.prompt_text,
		"门槛满足后提示语切回开门")
	MemoryManager.reset()
	return fails


func _check(condition: bool, label: String) -> int:
	print("[TEST:bg_pacing] %s %s" % ["PASS" if condition else "FAIL", label])
	return 0 if condition else 1


func _hud_rows() -> PackedStringArray:
	var tex := _background.texture.get_size()
	var world := _world_size()
	var view := get_viewport_rect().size / _zoom
	var speed: float = _body.move_speed
	var body_h := _player_height()
	var x := _body.global_position.x

	# 跳跃包围盒：给“这个密度下一跳能不能过去”一个数字。
	var jump_v: float = _body.jump_velocity
	var grav: float = _body.gravity
	var apex: float = (jump_v * jump_v) / (2.0 * grav)
	var air_time: float = 2.0 * absf(jump_v) / grav
	var reach: float = speed * air_time

	var rows := PackedStringArray()
	rows.append("背景  %d×%d  ×%.2f  →  世界 %d×%d px" % [
		int(tex.x), int(tex.y), background_scale, int(world.x), int(world.y)])
	rows.append("地面  y=%d（图高 %d%%）" % [int(_ground_y()), roundi(ground_line_ratio * 100.0)])
	rows.append("人物  速度 %d px/s   体型 ×%.2f   高 %d px = 屏高 %d%%" % [
		int(speed), player_scale, int(body_h), roundi(body_h / view.y * 100.0)])
	rows.append("跳跃  高 %d px（%.1f 个身位）   远 %d px   滞空 %.2f s" % [
		int(apex), apex / maxf(body_h, 1.0), int(reach), air_time])
	# 视口尺寸一起报出来：headless 下是 64×64 的假窗口，派生指标不可信。
	rows.append("镜头  zoom %.2f   视野 %d×%d px   视口 %d×%d" % [
		_zoom, int(view.x), int(view.y),
		int(get_viewport_rect().size.x), int(get_viewport_rect().size.y)])
	rows.append("节奏  一屏 %.1f s   全程 %.1f s   全图 = %.1f 屏" % [
		view.x / speed, world.x / speed, world.x / view.x])
	rows.append("位置  x=%d   进度 %d%%" % [int(x), roundi(x / maxf(world.x, 1.0) * 100.0)])
	rows.append("信物  %s" % _tokens_status())
	rows.append("方块门  x=%d   %s" % [int(_door.global_position.x), _door_status()])

	var moved := absf(x - _stopwatch_start_x)
	var avg := "—" if _stopwatch_time <= 0.0 else "%d px/s" % int(moved / _stopwatch_time)
	rows.append("秒表  %.2f s   走了 %d px   实测均速 %s%s" % [
		_stopwatch_time, int(moved), avg, "  ▶ 计时中" if _stopwatch_running else ""])
	return rows


# --- 信物 / 门的状态与反馈 ---------------------------------------------------------

## 甲乙丙对应 _tokens 里的顺序，和场景里 Token01/02/03 的排列一致。
const TOKEN_LABELS: Array[String] = ["甲", "乙", "丙"]


func _token_memory(token: Interactable) -> StringName:
	return StringName(token.get("memory_id"))


## 门的门槛信物直接问节点，不在脚本里再抄一份 id。
func _door_memory() -> StringName:
	return StringName(_door.get("required_memory"))


func _memory_title(memory_id: StringName) -> String:
	var entry := MemoryManager.get_memory_data(memory_id)
	return entry.title if entry != null else String(memory_id)


func _tokens_status() -> String:
	var parts := PackedStringArray()
	for i in _tokens.size():
		var owned := MemoryManager.has_memory(_token_memory(_tokens[i]))
		parts.append("%s %s" % [TOKEN_LABELS[i], "✔" if owned else "✘"])
	return "   ".join(parts)


func _door_status() -> String:
	# one_shot 的门开过一次就消耗掉了，can_interact 变 false。
	if not _door.can_interact(_body):
		return "已开"
	if _door.is_requirement_met():
		return "可开（按 E）"
	return "锁着 — 需要《%s》" % _memory_title(_door_memory())


func _on_prompt_changed(text: String) -> void:
	_prompt.text = "[E] %s" % text if not text.is_empty() else " "


func _on_token_taken(_player: Node, token: Interactable) -> void:
	_show("拾取了《%s》 — 按 Tab 打开梦奁查看" % _memory_title(_token_memory(token)))


func _on_door_opened(_player: Node) -> void:
	_show("方块门开了")


func _on_door_blocked(_player: Node) -> void:
	_show("方块门锁着 — 需要先拾取《%s》" % _memory_title(_door_memory()))


func _show(message: String) -> void:
	_event.text = message
	print("[LAB:bg_pacing] ", message)


# --- 调参按键 -------------------------------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_BRACKETLEFT:
			_body.move_speed = maxf(25.0, _body.move_speed - 25.0)
		KEY_BRACKETRIGHT:
			_body.move_speed += 25.0
		KEY_MINUS:
			_nudge_background(-0.05)
		KEY_EQUAL:
			_nudge_background(0.05)
		KEY_9:
			_nudge_player_scale(-0.1)
		KEY_0:
			_nudge_player_scale(0.1)
		KEY_COMMA:
			_set_zoom(_zoom * 0.9)
		KEY_PERIOD:
			_set_zoom(_zoom * 1.1)
		KEY_SLASH:
			_set_zoom(_fit_zoom())
		KEY_SEMICOLON:
			_nudge_ground(-0.01)
		KEY_APOSTROPHE:
			_nudge_ground(0.01)
		KEY_1:
			_reset_all()
		KEY_2:
			_teleport(0.05)
		KEY_3:
			_teleport(0.5)
		KEY_4:
			_teleport(0.95)
		KEY_5:
			_teleport_to(_tokens[0])
		KEY_6:
			_teleport_to(_tokens[1])
		KEY_7:
			_teleport_to(_door)
		KEY_8:
			_teleport_to(_tokens[2])
		KEY_R:
			# 拾取物是 one_shot，重来必须连场景一起重载才能再试一遍。
			MemoryManager.reset()
			get_tree().reload_current_scene()
		KEY_T:
			_toggle_stopwatch()
		KEY_H:
			_hud.visible = not _hud.visible
		_:
			return
	get_viewport().set_input_as_handled()


## 缩放背景时保持人物在全程的相对进度不变，视觉对比才有意义。
func _nudge_background(amount: float) -> void:
	var progress := _body.global_position.x / maxf(_world_size().x, 1.0)
	background_scale = clampf(background_scale + amount, 0.2, 3.0)
	_apply_layout()
	if fit_background_height:
		_set_zoom(_fit_zoom())
	_teleport(progress)


func _nudge_player_scale(amount: float) -> void:
	player_scale = clampf(player_scale + amount, 0.2, 5.0)
	_apply_player_scale()


func _nudge_ground(amount: float) -> void:
	ground_line_ratio = clampf(ground_line_ratio + amount, 0.0, 1.0)
	_apply_layout()
	# 地面线上移会把人埋进碰撞体，直接把人放回新的地面上。
	_body.global_position.y = _ground_y() - 2.0
	_body.velocity = Vector2.ZERO


func _teleport(progress: float) -> void:
	_body.global_position = Vector2(_world_size().x * clampf(progress, 0.0, 1.0), _ground_y() - 2.0)
	_body.velocity = Vector2.ZERO
	_stopwatch_start_x = _body.global_position.x
	_stopwatch_time = 0.0


## 停在物件左侧一点，别把人直接塞进门的碰撞体里。
func _teleport_to(node: Node2D) -> void:
	_teleport((node.global_position.x - APPROACH_OFFSET) / maxf(_world_size().x, 1.0))


func _reset_all() -> void:
	background_scale = _defaults["background_scale"]
	ground_line_ratio = _defaults["ground_line_ratio"]
	player_scale = _defaults["player_scale"]
	_body.move_speed = _defaults["move_speed"]
	_apply_layout()
	_apply_player_scale()
	_set_zoom(_fit_zoom() if fit_background_height else _defaults["camera_zoom"])
	_teleport(SPAWN_X_RATIO)


func _toggle_stopwatch() -> void:
	_stopwatch_running = not _stopwatch_running
	if _stopwatch_running:
		_stopwatch_time = 0.0
		_stopwatch_start_x = _body.global_position.x
