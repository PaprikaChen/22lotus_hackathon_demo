extends Node
## Interior_02 十幕皮影戏自动回归；输出 `[TEST:interior_02] PASS/FAIL`。
##
## 覆盖自动出口、十幕资源映射、旧幕引用清理、层级、人物切换、dad、boat、
## 禁用额外能力，以及第十幕居中锁定。

const LEVEL_PATH: String = "res://scenes/levels/interior_02.tscn"

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		_run_self_test.call_deferred()


func _check(condition: bool, label: String) -> void:
	if condition:
		_pass_count += 1
		print("[TEST:interior_02] PASS  %s" % label)
	else:
		_fail_count += 1
		print("[TEST:interior_02] FAIL  %s" % label)


func _run_self_test() -> void:
	print("[TEST:interior_02] --- start ---")
	var packed: PackedScene = load(LEVEL_PATH) as PackedScene
	var level: Interior02Level = packed.instantiate() as Interior02Level
	level.fade_duration = 0.0
	add_child(level)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var player: Player = level.get_node("Player") as Player
	var exit_trigger: Area2D = level.get_node("ExitTrigger") as Area2D
	var puppet: ShadowPuppetActor = level.get_node("Player/PuppetVisual") as ShadowPuppetActor
	var middle: Sprite2D = level.get_node("StageVisual/Middle") as Sprite2D
	var front: Sprite2D = level.get_node("StageVisual/Front") as Sprite2D
	var boat: Sprite2D = level.get_node("Player/Boat") as Sprite2D
	var dream_gap: Node = level.get_node("Player/DreamGapAbility")
	var detector: Area2D = level.get_node("Player/InteractionDetector") as Area2D
	var caption: Label = level.get_node("CaptionLayer/Caption") as Label
	var finale: Node = level.get_node("FinaleLayer")
	finale.set("title_hold_duration", 0.0)
	finale.set("credit_hold_duration", 0.0)
	finale.set("text_fade_duration", 0.0)

	_check(ShadowPlayConfig.get_stage_count() == 10, "集中配置恰好有 10 幕")
	_check(level.get_current_stage_number() == 1, "从第 1 幕开始")
	_check(not player.jump_enabled, "本关禁跳")
	_check(dream_gap.process_mode == Node.PROCESS_MODE_DISABLED, "本关禁用 DreamGap")
	_check(detector.process_mode == Node.PROCESS_MODE_DISABLED and not detector.monitoring,
		"本关禁用交互检测")
	_check(middle.z_index < player.z_index and player.z_index < front.z_index,
		"middle < Player < front")
	_check(boat.z_index < puppet.z_index, "boat 位于 Player 脚下层")
	_check(level.is_boat_visible(), "第 1 幕显示 boat")
	_check(not level.is_dad_visible(), "第 1 幕不显示 dad")
	_check(level.get_player_texture_path().ends_with("mom1.png"), "第 1 幕使用 mom1")
	_check(is_equal_approx(absf((puppet.get_node("Sprite") as Sprite2D).scale.x), 0.70),
		"第 1 幕 player_scale=0.70")
	_check(caption.text == "姑娘只身千里,岂不惧乎?" and caption.visible,
		"第 1 幕右上字幕正确")

	# 用真实 Area2D 触发第 1→2 幕，后续再用公共换幕入口快速遍历。
	player.global_position = exit_trigger.global_position
	for _frame: int in 10:
		await get_tree().physics_frame
		if level.get_current_stage_number() == 2:
			break
	while level.is_transitioning():
		await get_tree().process_frame
	_check(level.get_current_stage_number() == 2,
		"进入右侧出口自动且只切到第 2 幕（实际 %d）" % level.get_current_stage_number())
	_check(not level.is_boat_visible(), "离开第 1 幕后 boat 已清理")

	for target_stage: int in range(2, ShadowPlayConfig.get_stage_count()):
		if level.get_current_stage_number() != target_stage + 1:
			await level.advance_stage()
			await get_tree().process_frame
			await get_tree().physics_frame
		var number: int = level.get_current_stage_number()
		var data: Dictionary = ShadowPlayConfig.get_stage(number - 1)
		var expected_player: String = String(data.get("player_texture", ""))
		var loaded: PackedStringArray = level.get_loaded_stage_texture_paths()
		_check(level.get_player_texture_path() == expected_player,
			"第 %d 幕 Player 素材正确" % number)
		_check(level.is_dad_visible() == (number >= 4 and number <= 7),
			"第 %d 幕 dad 显示规则正确" % number)
		_check(caption.text == String(data.get("caption", "")),
			"第 %d 幕字幕随配置切换" % number)
		_check(loaded.has(String(data.get("middle", ""))),
			"第 %d 幕只引用当前 middle" % number)
		var previous: Dictionary = ShadowPlayConfig.get_stage(number - 2)
		if String(previous.get("middle", "")) != String(data.get("middle", "")):
			_check(not loaded.has(String(previous.get("middle", ""))),
				"第 %d 幕不再引用上一幕 middle" % number)
		if number == 4:
			var dad_actor: Node2D = level.get_node("DadPivot/PuppetVisual") as Node2D
			Input.action_press("move_left")
			for _frame: int in 6:
				await get_tree().physics_frame
			Input.action_release("move_left")
			_check(dad_actor.scale.x < 0.0, "Player 向左转身时 dad 同步转身")
			_check(absf(dad_actor.rotation) > 0.0001 or absf(dad_actor.position.y) > 0.1,
				"Player 移动时 dad 同步摇晃")
			Input.action_press("move_right")
			for _frame: int in 6:
				await get_tree().physics_frame
			Input.action_release("move_right")
			_check(dad_actor.scale.x > 0.0, "Player 向右转身时 dad 同步转身")

	_check(level.get_current_stage_number() == 10, "可连续推进到第 10 幕")
	_check(level.get_player_texture_path().ends_with("mom2.png"), "第 10 幕使用 mom2")
	var final_data: Dictionary = ShadowPlayConfig.get_stage(9)
	var final_spawn := Vector2(
		float(final_data.get("spawn_x", 0.0)),
		float(final_data.get("ground_y", 0.0)))
	_check(player.global_position.distance_to(final_spawn) < 1.0,
		"第 10 幕出生在画面中央")
	_check(not level.is_exit_enabled(), "第 10 幕没有下一幕出口")
	_check(player.get_input_lock_sources().has(Interior02Level.FINALE_LOCK),
		"第 10 幕用独立来源锁住 Player")
	var final_position: Vector2 = player.global_position
	Input.action_press("move_right")
	for _frame: int in 8:
		await get_tree().physics_frame
	Input.action_release("move_right")
	_check(player.global_position.distance_to(final_position) < 0.1,
		"第 10 幕按移动键也完全不动")

	# 第十幕 Space：章节标题 → 三条名单 → 谢谢体验。测试把时长压成 0。
	Input.action_press("jump")
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release("jump")
	for _frame: int in 30:
		if bool(finale.call("is_complete")):
			break
		await get_tree().process_frame
	_check(bool(finale.call("is_complete")), "第 10 幕按 Space 会完整播放终幕名单")
	_check(String(finale.call("get_visible_text")) == "谢谢体验！",
		"名单结束后显示“谢谢体验！”")

	print("[TEST:interior_02] --- done: %d passed, %d failed ---"
		% [_pass_count, _fail_count])
	get_tree().quit(_fail_count)
