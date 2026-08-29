class_name Interior02Level
extends LevelBase
## Interior_02 皮影戏舞台：按集中配置逐幕加载/释放视觉资源并编排黑幕切换。
##
## 公共 Player 不感知皮影素材；十幕纹理使用 CACHE_MODE_IGNORE 动态加载，
## 换幕时先清空所有旧 Texture 引用，再加载下一幕。

const TRANSITION_LOCK: StringName = &"shadow_play_transition"
const FINALE_LOCK: StringName = &"shadow_play_finale"

@export_range(1, 10, 1) var starting_stage: int = 1
@export_range(0.0, 2.0, 0.05) var fade_duration: float = 0.45
@export var stage_visual_path: NodePath
@export var background_path: NodePath
@export var middle_path: NodePath
@export var front_path: NodePath
@export var puppet_actor_path: NodePath
@export var original_player_visual_path: NodePath
@export var dad_pivot_path: NodePath
@export var dad_actor_path: NodePath
@export var dad_sprite_path: NodePath
@export var boat_sprite_path: NodePath
@export var ground_path: NodePath
@export var left_wall_path: NodePath
@export var exit_trigger_path: NodePath
@export var caption_path: NodePath
@export var finale_path: NodePath
@export var fade_path: NodePath
@export var dream_gap_path: NodePath
@export var interaction_detector_path: NodePath

var _stage_visual: Node2D = null
var _background: Sprite2D = null
var _middle: Sprite2D = null
var _front: Sprite2D = null
var _puppet_actor: ShadowPuppetActor = null
var _dad_pivot: Node2D = null
var _dad_actor: ShadowPuppetActor = null
var _dad_sprite: Sprite2D = null
var _boat_sprite: Sprite2D = null
var _ground: StaticBody2D = null
var _left_wall: StaticBody2D = null
var _exit_trigger: Area2D = null
var _caption: Label = null
var _finale: CanvasLayer = null
var _fade: ScreenFade = null
var _current_stage: int = -1
var _dad_distance: float = 0.0
var _art_scale: float = 1.0
var _actor_scale: float = 0.70
var _transitioning: bool = false
var _exit_armed: bool = false
var _exit_arm_generation: int = 0
var _finale_space_held: bool = false
var _finale_started: bool = false


func _ready() -> void:
	super._ready()
	_resolve_nodes()
	_disable_non_movement_actions()
	_connect_exit_once()
	_begin_initial_stage()


func _physics_process(_delta: float) -> void:
	var player: Player = _player as Player
	if player == null or _dad_pivot == null or not _dad_pivot.visible:
		return
	# 十幕都从左向右推进；dad 始终锁在玩家左后方，绝不会越到前面。
	_dad_pivot.global_position = Vector2(
		player.global_position.x - _dad_distance,
		player.global_position.y)


func _process(_delta: float) -> void:
	var space_pressed: bool = Input.is_action_pressed("jump")
	var on_final_stage: bool = _current_stage == ShadowPlayConfig.get_stage_count() - 1
	if on_final_stage and not _transitioning and not _finale_started \
			and space_pressed and not _finale_space_held:
		_finale_started = true
		if _finale != null:
			_finale.call(&"play")
	_finale_space_held = space_pressed


func _exit_tree() -> void:
	_clear_stage_visuals()


## 公共入口也供自动化验证使用；正常游玩由右侧 ExitTrigger 调用。
func advance_stage() -> void:
	if _current_stage < 0 or _current_stage >= ShadowPlayConfig.get_stage_count() - 1:
		return
	await _transition_to_stage(_current_stage + 1)


func get_current_stage_number() -> int:
	return _current_stage + 1


func is_transitioning() -> bool:
	return _transitioning


func is_dad_visible() -> bool:
	return _dad_pivot != null and _dad_pivot.visible


func is_boat_visible() -> bool:
	return _boat_sprite != null and _boat_sprite.visible


func is_exit_enabled() -> bool:
	return _exit_armed and _exit_trigger != null and _exit_trigger.monitoring


func get_player_texture_path() -> String:
	return _puppet_actor.get_texture_path() if _puppet_actor != null else ""


func get_loaded_stage_texture_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	for sprite: Sprite2D in [_background, _middle, _front]:
		if sprite != null and sprite.texture != null:
			paths.append(sprite.texture.resource_path)
	return paths


func _resolve_nodes() -> void:
	_stage_visual = get_node_or_null(stage_visual_path) as Node2D
	_background = get_node_or_null(background_path) as Sprite2D
	_middle = get_node_or_null(middle_path) as Sprite2D
	_front = get_node_or_null(front_path) as Sprite2D
	_puppet_actor = get_node_or_null(puppet_actor_path) as ShadowPuppetActor
	_dad_pivot = get_node_or_null(dad_pivot_path) as Node2D
	_dad_actor = get_node_or_null(dad_actor_path) as ShadowPuppetActor
	_dad_sprite = get_node_or_null(dad_sprite_path) as Sprite2D
	_boat_sprite = get_node_or_null(boat_sprite_path) as Sprite2D
	_ground = get_node_or_null(ground_path) as StaticBody2D
	_left_wall = get_node_or_null(left_wall_path) as StaticBody2D
	_exit_trigger = get_node_or_null(exit_trigger_path) as Area2D
	_caption = get_node_or_null(caption_path) as Label
	_finale = get_node_or_null(finale_path) as CanvasLayer
	_fade = get_node_or_null(fade_path) as ScreenFade
	var original_visual: CanvasItem = get_node_or_null(original_player_visual_path) as CanvasItem
	if original_visual != null:
		original_visual.visible = false


func _disable_non_movement_actions() -> void:
	# SIDE_SCROLL 已天然忽略上下；LevelBase 的 player_can_jump=false 禁跳。
	# 本关再局部停掉 DreamGap 与交互检测，不影响其他关卡的 Player 实例。
	var dream_gap: Node = get_node_or_null(dream_gap_path)
	if dream_gap != null:
		dream_gap.process_mode = Node.PROCESS_MODE_DISABLED
	var detector: Area2D = get_node_or_null(interaction_detector_path) as Area2D
	if detector != null:
		detector.monitoring = false
		detector.monitorable = false
		detector.process_mode = Node.PROCESS_MODE_DISABLED


func _connect_exit_once() -> void:
	if _exit_trigger != null and not _exit_trigger.body_entered.is_connected(_on_exit_body_entered):
		_exit_trigger.body_entered.connect(_on_exit_body_entered)


func _begin_initial_stage() -> void:
	var player: Player = _player as Player
	if player == null:
		push_error("Interior02Level: 未找到 Player。")
		return
	_transitioning = true
	player.lock_input(TRANSITION_LOCK)
	if _fade != null:
		_fade.set_opaque(true)
	_apply_stage(clampi(starting_stage - 1, 0, ShadowPlayConfig.get_stage_count() - 1))
	if fade_duration <= 0.0:
		if _fade != null:
			_fade.set_opaque(false)
		player.unlock_input(TRANSITION_LOCK)
		_transitioning = false
		return
	if _fade != null:
		await _fade.fade_in(fade_duration)
	player.unlock_input(TRANSITION_LOCK)
	_transitioning = false


func _on_exit_body_entered(body: Node2D) -> void:
	if body != _player or _transitioning or not is_exit_enabled():
		return
	_exit_armed = false
	advance_stage()


func _transition_to_stage(next_stage: int) -> void:
	if _transitioning or next_stage < 0 or next_stage >= ShadowPlayConfig.get_stage_count():
		return
	var player: Player = _player as Player
	if player == null:
		return
	_transitioning = true
	player.lock_input(TRANSITION_LOCK)
	if fade_duration <= 0.0:
		if _fade != null:
			_fade.set_opaque(true)
		_clear_stage_visuals()
		_apply_stage(next_stage)
		if _fade != null:
			_fade.set_opaque(false)
		player.unlock_input(TRANSITION_LOCK)
		_transitioning = false
		return
	if _fade != null:
		await _fade.fade_out(fade_duration)
	_clear_stage_visuals()
	_apply_stage(next_stage)
	if _fade != null:
		await _fade.fade_in(fade_duration)
	player.unlock_input(TRANSITION_LOCK)
	_transitioning = false


func _apply_stage(index: int) -> void:
	var data: Dictionary = ShadowPlayConfig.get_stage(index)
	if data.is_empty():
		push_error("Interior02Level: 幕编号无效：%d" % index)
		return
	_current_stage = index
	_update_art_transform()
	_assign_full_canvas_texture(_background, String(data.get("background", "")))
	_assign_full_canvas_texture(_middle, String(data.get("middle", "")))
	_assign_full_canvas_texture(_front, String(data.get("front", "")))
	_apply_player_art(data)
	_apply_boat(data)
	_apply_dad(data)
	_apply_stage_geometry(data)
	_apply_caption(data)


func _update_art_transform() -> void:
	if _stage_visual == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_art_scale = minf(
		viewport_size.x / ShadowPlayConfig.CANVAS_SIZE.x,
		viewport_size.y / ShadowPlayConfig.CANVAS_SIZE.y)
	var fitted_size: Vector2 = ShadowPlayConfig.CANVAS_SIZE * _art_scale
	_stage_visual.scale = Vector2.ONE * _art_scale
	_stage_visual.position = (viewport_size - fitted_size) * 0.5


func _assign_full_canvas_texture(sprite: Sprite2D, path: String) -> void:
	if sprite == null:
		return
	sprite.texture = _load_texture(path)
	sprite.visible = sprite.texture != null


func _apply_player_art(data: Dictionary) -> void:
	if _puppet_actor == null:
		return
	var texture: Texture2D = _load_texture(String(data.get("player_texture", "")))
	var anchor: Vector2 = data.get("player_anchor", Vector2.ZERO)
	_actor_scale = float(data.get("player_scale", 0.70))
	_puppet_actor.set_art(texture, anchor, _actor_scale)


func _apply_boat(data: Dictionary) -> void:
	if _boat_sprite == null:
		return
	var texture: Texture2D = _load_texture(String(data.get("boat_texture", "")))
	_boat_sprite.texture = texture
	_boat_sprite.visible = texture != null
	_boat_sprite.centered = false
	_boat_sprite.scale = Vector2.ONE * _art_scale
	_boat_sprite.position = -ShadowPlayConfig.BOAT_DECK_ANCHOR * _art_scale


func _apply_dad(data: Dictionary) -> void:
	if _dad_pivot == null or _dad_actor == null:
		return
	var show_dad: bool = bool(data.get("show_dad", false))
	_dad_distance = float(data.get("dad_distance", 0.0))
	var texture: Texture2D = _load_texture(ShadowPlayConfig.DAD_PATH) if show_dad else null
	_dad_actor.set_art(texture, ShadowPlayConfig.DAD_ANCHOR, _actor_scale)
	_dad_pivot.visible = show_dad and texture != null


func _apply_stage_geometry(data: Dictionary) -> void:
	var player: Player = _player as Player
	if player == null:
		return
	var ground_y: float = float(data.get("ground_y", 700.0))
	var spawn: Vector2 = Vector2(float(data.get("spawn_x", 0.0)), ground_y)
	var exit: Vector2 = Vector2(float(data.get("exit_x", 0.0)), ground_y)
	var left_bound: float = float(data.get("left_bound", 0.0))
	var has_exit: bool = bool(data.get("has_exit", true))
	player.unlock_input(FINALE_LOCK)
	player.global_position = spawn
	player.velocity = Vector2.ZERO
	player.set_spawn_point(spawn)
	if _ground != null:
		_ground.position.y = spawn.y + 100.0
	if _left_wall != null:
		_left_wall.position = Vector2(left_bound - 32.0, ShadowPlayConfig.CANVAS_SIZE.y * 0.5)
	if _exit_trigger != null:
		_exit_trigger.position = exit
		_exit_arm_generation += 1
		_exit_armed = false
		_exit_trigger.set_deferred("monitoring", false)
		if has_exit:
			_arm_exit_after_physics(_exit_arm_generation)
	if not has_exit:
		player.lock_input(FINALE_LOCK)


func _arm_exit_after_physics(generation: int) -> void:
	# 等 CharacterBody/Area 的服务端 Transform 都同步到新幕，避免旧重叠状态
	# 在同一物理帧里再发一次 body_entered，造成快速连跳两幕。
	await get_tree().physics_frame
	await get_tree().physics_frame
	if generation != _exit_arm_generation or _current_stage >= ShadowPlayConfig.get_stage_count() - 1:
		return
	if _exit_trigger != null:
		_exit_trigger.monitoring = true
		_exit_armed = true


func _apply_caption(data: Dictionary) -> void:
	if _caption == null:
		return
	var text: String = String(data.get("caption", ""))
	_caption.text = text
	_caption.position = data.get("caption_position", Vector2.ZERO)
	_caption.size = data.get("caption_size", Vector2.ZERO)
	_caption.horizontal_alignment = int(data.get(
		"caption_alignment", HORIZONTAL_ALIGNMENT_LEFT)) as HorizontalAlignment
	_caption.visible = not text.is_empty()


func _clear_stage_visuals() -> void:
	# 当前幕 Texture 使用 CACHE_MODE_IGNORE 加载，引用归零后不会因为下一幕配置常驻。
	for sprite: Sprite2D in [_background, _middle, _front]:
		if sprite != null:
			sprite.texture = null
			sprite.visible = false
	if _puppet_actor != null:
		_puppet_actor.clear_art()
	if _dad_actor != null:
		_dad_actor.clear_art()
	if _dad_pivot != null:
		_dad_pivot.visible = false
	if _boat_sprite != null:
		_boat_sprite.texture = null
		_boat_sprite.visible = false
	if _exit_trigger != null:
		_exit_arm_generation += 1
		_exit_armed = false
		_exit_trigger.set_deferred("monitoring", false)
	if _caption != null:
		_caption.text = ""
		_caption.visible = false


func _load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path, "Texture2D"):
		push_error("Interior02Level: 皮影资源不存在：%s" % path)
		return null
	return ResourceLoader.load(
		path,
		"Texture2D",
		ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
