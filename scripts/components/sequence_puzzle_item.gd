class_name SequencePuzzleItem
extends Area2D
## 顺序解谜里的一件物品：只管自己的表现（闪烁、颤抖）和「现在能不能点」。
## 顺序对不对由 SequencePuzzle 判断——物品不知道自己是第几个。
##
## 选中方式是**鼠标点击**，不是走近按 E：架子上的物品在垂直方向上叠着
## （最上和最下差近 300 世界像素），走近判定没法把它们区分开。所以本类刻意
## **不是** Interactable——InteractionDetector 只收 Interactable，这些小物件
## 不会去抢「靠近书架」那个提示。
##
## 美术是满画布贴图（和背景同一套对位方式），原点在世界 (0, 0)，所以**不能**
## 直接旋转它——绕原点转会整屏歪掉。场景里给每件物品套了一层 Pivot：
## Pivot 在物品中心，美术作为它的子节点反向偏移回 (0, 0)。旋转和调亮都作用在
## Pivot 上，看起来就是物品绕自己晃。

signal selected(item: SequencePuzzleItem)

## 物品的 Pivot（在物品中心，美术挂在它下面）。旋转和提亮都作用在它身上。
@export var art_path: NodePath
## Pivot 底下的美术精灵。外发光是它的材质，所以要单独指一次。
@export var sprite_path: NodePath = ^"Pivot/Art"

@export_group("Highlight")
## 待选时的常亮亮度。1.0 = 原样，>1 提亮（乘在 modulate 上，超过 1 会往白里压）。
## 解谜期间要一眼看出「这几件能点」，所以给得很足。
@export_range(0.5, 4.0, 0.01) var highlight_brightness: float = 2.2
@export_range(0.0, 2.0, 0.01, "suffix:s") var highlight_fade_duration: float = 0.3

@export_group("Glow")
@export var glow_color: Color = Color(1.0, 0.93, 0.72, 1.0)
## 发光扩散半径（贴图像素）。世界像素 = 这个值 × 精灵 scale（本关 0.6）。
@export_range(0.0, 64.0, 0.5) var glow_radius: float = 18.0
## 脉动的下限 / 上限。发光在两者之间来回呼吸，所以物品是「一直亮着 + 光在闪」。
@export_range(0.0, 4.0, 0.01) var glow_strength_min: float = 0.45
@export_range(0.0, 4.0, 0.01) var glow_strength_max: float = 1.6
@export_range(0.1, 5.0, 0.05, "suffix:s") var glow_pulse_period: float = 1.1

@export_group("Nudge")
## 点中时的旋转晃动幅度。
@export_range(0.0, 30.0, 0.5, "suffix:°") var nudge_degrees: float = 4.0
@export_range(0.05, 2.0, 0.01, "suffix:s") var nudge_duration: float = 0.28

const GLOW_SHADER: Shader = preload("res://shaders/effects/glow_outline.gdshader")

var _art: Node2D = null
var _sprite: CanvasItem = null
## 每件物品一份自己的材质：共用一份会让脉动的 uniform 互相覆盖。
var _glow_material: ShaderMaterial = null
var _glow_tween: Tween = null
var _base_rotation: float = 0.0
var _armed: bool = false
var _locked_in: bool = false
var _highlight_tween: Tween = null
var _nudge_tween: Tween = null


func _ready() -> void:
	_art = get_node_or_null(art_path) as Node2D
	if _art == null:
		push_warning("SequencePuzzleItem: 没接上 art，高亮和晃动不会播放。")
	else:
		_base_rotation = _art.rotation
	_sprite = get_node_or_null(sprite_path) as CanvasItem
	if _sprite == null:
		push_warning("SequencePuzzleItem: 没接上 sprite，外发光不会生效。")
	input_event.connect(_on_input_event)


## 发光材质按需挂上。解谜之前物品身上**没有任何材质**——不挂就绝不会有
## 边缘染色、混色模式变化之类的意外，这是「交互前不做任何处理」最省心的保证。
func _ensure_glow_material() -> void:
	if _sprite == null or _glow_material != null:
		return
	_glow_material = ShaderMaterial.new()
	_glow_material.shader = GLOW_SHADER
	_glow_material.set_shader_parameter(&"glow_color", glow_color)
	_glow_material.set_shader_parameter(&"glow_radius", glow_radius)
	_glow_material.set_shader_parameter(&"glow_strength", 0.0)
	_sprite.material = _glow_material


## 光灭了就把材质摘掉，物品回到完全未经处理的状态。
func _clear_glow_material() -> void:
	if _sprite != null and _sprite.material == _glow_material:
		_sprite.material = null
	_glow_material = null


# --- 由 SequencePuzzle 调用 ------------------------------------------------------

func is_armed() -> bool:
	return _armed


func is_locked_in() -> bool:
	return _locked_in


## 解谜启动 / 结束。关掉时顺带熄灯、复位。
func set_armed(armed: bool) -> void:
	_armed = armed
	if not armed:
		_locked_in = false
		set_highlight(false)


## 按正确顺序选中：熄掉高亮（表示这件已经用过），不再接受点击。
func lock_in() -> void:
	_locked_in = true
	set_highlight(false)


## 顺序错误后回到「待选」：可以再点，重新亮起来。
func reset_selection() -> void:
	_locked_in = false
	if _armed:
		set_highlight(true)


## 待选表现：本体常亮（modulate，>1 往白里压）+ 一圈脉动的外发光。
## 用 modulate 而不是 self_modulate——要连 Pivot 底下的美术一起提亮。
func set_highlight(highlighted: bool) -> void:
	_kill(_highlight_tween)
	_highlight_tween = null
	if _art == null:
		return
	var b: float = highlight_brightness if highlighted else 1.0
	var target := Color(b, b, b, _art.modulate.a)
	if highlight_fade_duration <= 0.0:
		_art.modulate = target
		_set_glow_pulsing(highlighted)
		return
	_set_glow_pulsing(highlighted)
	_highlight_tween = create_tween()
	_highlight_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_highlight_tween.tween_property(_art, ^"modulate", target, highlight_fade_duration).set_trans(Tween.TRANS_SINE)


## 外发光的脉动。亮度（modulate）保持常亮，**闪的是这圈光**——本体跟着一起
## 忽明忽暗会让物品看着像要消失，而光在呼吸只是在喊「点我」。
func _set_glow_pulsing(pulsing: bool) -> void:
	_kill(_glow_tween)
	_glow_tween = null
	if not pulsing:
		if _glow_material == null:
			return
		if highlight_fade_duration <= 0.0:
			_clear_glow_material()
			return
		_glow_tween = create_tween()
		_glow_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_glow_tween.tween_property(_glow_material, ^"shader_parameter/glow_strength",
			0.0, highlight_fade_duration).set_trans(Tween.TRANS_SINE)
		_glow_tween.tween_callback(_clear_glow_material)
		return
	_ensure_glow_material()
	if _glow_material == null:
		return
	_glow_material.set_shader_parameter(&"glow_strength", glow_strength_min)
	var half: float = maxf(glow_pulse_period, 0.1) * 0.5
	_glow_tween = create_tween().set_loops()
	_glow_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_glow_tween.tween_property(_glow_material, ^"shader_parameter/glow_strength",
		glow_strength_max, half).set_trans(Tween.TRANS_SINE)
	_glow_tween.tween_property(_glow_material, ^"shader_parameter/glow_strength",
		glow_strength_min, half).set_trans(Tween.TRANS_SINE)


## 被点中时晃一下：绕自己的 Pivot **旋转**摆动，来回衰减着收住。
## `strength_scale` 让「集体颤动」可以比单点更明显。
func nudge(strength_scale: float = 1.0) -> void:
	if _art == null:
		return
	_kill(_nudge_tween)
	var amount: float = deg_to_rad(nudge_degrees) * strength_scale
	_art.rotation = _base_rotation
	_nudge_tween = create_tween()
	_nudge_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var beat: float = nudge_duration / 4.0
	for offset in [amount, -amount * 0.7, amount * 0.4]:
		_nudge_tween.tween_property(_art, ^"rotation", _base_rotation + offset, beat).set_trans(Tween.TRANS_SINE)
	_nudge_tween.tween_property(_art, ^"rotation", _base_rotation, beat).set_trans(Tween.TRANS_SINE)


## 测试 / 无鼠标环境用：不依赖点击也能选中。
func select() -> void:
	if not _armed or _locked_in:
		return
	selected.emit(self)


# --- 内部 ----------------------------------------------------------------------

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not _armed or _locked_in:
		return
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
		return
	select()


func _kill(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()


func _exit_tree() -> void:
	_kill(_highlight_tween)
	_kill(_nudge_tween)
	_kill(_glow_tween)
