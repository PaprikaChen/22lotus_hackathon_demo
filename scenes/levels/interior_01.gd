class_name Interior01Level
extends LevelBase
## interior_01 的关卡机制：接入统一调查字幕，并提供进关自动存档入口。
## 剧情因果归本关 StoryDirector；本脚本不判断剧情状态。

@export var dialogue_box_path: NodePath

var _dialogue: CanvasLayer = null
## 去下一关只会成功一次。
var _leaving: bool = false


func _ready() -> void:
	super._ready()
	_dialogue = get_node_or_null(dialogue_box_path) as CanvasLayer
	for prop in _collect_props_with_signal(self, &"text_requested"):
		prop.text_requested.connect(_show_text)
	for prop in _collect_props_with_signal(self, &"choice_requested"):
		prop.choice_requested.connect(_ask_choice)
	for prop in _collect_props_with_signal(self, &"text_dismiss_requested"):
		prop.text_dismiss_requested.connect(_hide_text)
	for prop in _collect_props_with_signal(self, &"exit_reached"):
		prop.exit_reached.connect(go_to_next_level)


func autosave() -> bool:
	if _player == null:
		return false
	return SaveManager.save_progress(scene_file_path, _player.global_position)


## 幂等：只会成功一次。**只管怎么走**，门槛由 LevelExit / StoryDirector 把关。
## 与 courtyard_level.gd 同一套做法（离关先存档、坐标交给下一关的 SpawnPoint）。
func go_to_next_level(target_scene: String) -> void:
	if _leaving or target_scene.is_empty():
		return
	if not ResourceLoader.exists(target_scene):
		push_error("Interior01Level: 下一关场景不存在：%s" % target_scene)
		return
	_leaving = true
	SaveManager.save_progress(target_scene, Vector2.ZERO, true)
	complete_level()
	# 只在独立运行时真的切场景（被测试当子场景实例化时不切）。
	if get_tree().current_scene == self:
		get_tree().change_scene_to_file.call_deferred(target_scene)


func _show_text(text: String) -> void:
	if _dialogue != null:
		_dialogue.show_text(text)


## 道具请关卡收掉对话框（提示已经过期，不该等玩家再按一次空格）。
func _hide_text() -> void:
	if _dialogue != null and _dialogue.has_method("hide_box"):
		_dialogue.call("hide_box")


## 道具请关卡问一句选择。**所有**选择也只走这一个对话框，不许各处自弹 UI。
## 选完把下标交回给道具，怎么处理是它自己的事。
func _ask_choice(text: String, options: PackedStringArray, on_choice: Callable) -> void:
	if _dialogue == null or not _dialogue.has_method("ask"):
		return
	var index: int = await _dialogue.ask(text, options)
	if on_choice.is_valid():
		on_choice.call(index)


func _collect_props_with_signal(node: Node, signal_name: StringName, found: Array = []) -> Array:
	for child in node.get_children():
		if child.has_signal(signal_name):
			found.append(child)
		_collect_props_with_signal(child, signal_name, found)
	return found
