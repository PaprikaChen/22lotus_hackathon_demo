extends Node
## 调试工具：把任意场景跑起来、等若干帧、把画面存成 PNG，然后退出。
##
## 用来肉眼检查表现层（人物大小、脚线、朝向）——这些是自动断言判断不了的。
## 无头模式不渲染，所以必须开窗跑：
##
##   Godot --path D:/22lotus res://tests/helpers/capture_scene.tscn \
##       -- --scene=res://scenes/levels/courtyard_01.tscn \
##          --out=user://shot.png --frames=30 [--hold=move_right]
##
## `--hold` 可选：按住某个输入动作再截图，用来抓 walk 帧。

const DEFAULT_FRAMES: int = 30


func _ready() -> void:
	var args := _parse_args()
	var scene_path: String = args.get("scene", "")
	if scene_path.is_empty():
		push_error("capture_scene: 必须传 --scene=res://...")
		get_tree().quit(1)
		return

	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("capture_scene: 加载不了 %s" % scene_path)
		get_tree().quit(1)
		return
	var level := packed.instantiate()
	add_child(level)

	if args.has("playerx"):
		# 等一帧让 LevelBase 把玩家放到出生点，再覆盖，否则会被出生点冲掉。
		await get_tree().physics_frame
		var player := level.get_node_or_null(^"Player") as Node2D
		if player != null:
			player.global_position.x = float(args["playerx"])
		else:
			push_warning("capture_scene: 场景里没有 Player，--playerx 被忽略")

	var hold := StringName(args.get("hold", ""))
	if hold != &"":
		Input.action_press(hold)

	var frames := int(args.get("frames", DEFAULT_FRAMES))
	for _i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	var out: String = args.get("out", "user://capture.png")
	var err := image.save_png(out)
	print("[CAPTURE] %s -> %s (err=%d, %dx%d)"
		% [scene_path, ProjectSettings.globalize_path(out), err,
			image.get_width(), image.get_height()])

	if hold != &"":
		Input.action_release(hold)
	get_tree().quit(0 if err == OK else 1)


func _parse_args() -> Dictionary:
	var out: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var parts := arg.substr(2).split("=", true, 1)
		out[parts[0]] = parts[1]
	return out
