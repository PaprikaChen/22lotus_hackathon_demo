extends Cutscene
## 母亲幻觉——**灰盒表现**：屏幕染色 → 一段文字 → 复原。
##
## 这里只有表现。等美术/演出方案定稿，整个 `_perform()` 可以直接换掉，
## 上下游不受影响：Director 仍然只看 `finished`。
##
## 严格不做：写剧情 Flag、推进信物、解锁门、决定下一段剧情——
## 那些全在 old_courtyard_story_director.gd 里。

@export var dialogue_box_path: NodePath
@export var tint_path: NodePath
@export var fade_duration: float = 0.6
## 占位文案，等叙事定稿替换。
@export_multiline var lines: String = ""


func _perform() -> void:
	var tint := get_node_or_null(tint_path) as CanvasItem
	var box := get_node_or_null(dialogue_box_path)
	if tint == null or box == null or not box.has_method("show_text"):
		push_warning("MotherMemoryCutscene: 缺少 tint 或 DialogueBox，直接结束。")
		finish()
		return
	tint.visible = true
	tint.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(tint, ^"modulate:a", 1.0, fade_duration)
	tween.tween_callback(func() -> void:
		box.closed.connect(_on_text_closed, CONNECT_ONE_SHOT)
		box.show_text(lines))


func _on_text_closed() -> void:
	var tint := get_node_or_null(tint_path) as CanvasItem
	if tint == null:
		finish()
		return
	var tween := create_tween()
	tween.tween_property(tint, ^"modulate:a", 0.0, fade_duration)
	tween.tween_callback(func() -> void:
		tint.visible = false
		finish())
