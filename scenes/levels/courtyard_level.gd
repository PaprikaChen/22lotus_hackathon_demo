class_name CourtyardLevel
extends LevelBase
## 别院关卡的公共关卡脚本（courtyard_01 / courtyard_02 共用一份）。
##
## **只负责关卡侧机制**：
##   · 相机由 FollowCamera2D 自己管，这里不碰；
##   · 把各个 `text_requested` 接到共用 DialogueBox；
##   · 交互提示由场景里的 InteractionPrompt 自己监听玩家检测器；
##   · 「去下一关」这一次场景切换怎么做；
##   · 自动存档怎么写。
##
## **什么时候**发生什么——剧情因果、NPC 入场、CG 解锁——全部在本关自己的
## StoryDirector 里。不要往这里加剧情判断（AGENTS.md §5.5）。
##
## 为什么两关共用一个脚本：courtyard_02 的关卡侧机制和 01 完全一样，
## 区别只在背景、Props 和 Director。共用一份省得改一处忘一处。

signal level_left(target_scene: String)

@export var dialogue_box_path: NodePath
@export var level_exit_path: NodePath

var _dialogue: CanvasLayer = null
var _leaving: bool = false


func _ready() -> void:
	super._ready()
	_dialogue = get_node_or_null(dialogue_box_path) as CanvasLayer
	for prop in _collect_props_with_signal(self, &"text_requested"):
		prop.text_requested.connect(_show_text)
	for prop in _collect_props_with_signal(self, &"choice_requested"):
		prop.choice_requested.connect(_ask_choice)
	var exit_node := get_node_or_null(level_exit_path) as LevelExit
	if exit_node != null:
		exit_node.exit_reached.connect(go_to_next_level)


# --- UI 布线 -------------------------------------------------------------------

func _show_text(text: String) -> void:
	# 所有调查 / 对话文字统一走底部对话框，禁止各处自画浮动文字。
	if _dialogue != null:
		_dialogue.show_text(text)


## 道具请关卡问一句「是 / 否」。**所有**选择也只走这一个对话框，
## 不许各处自弹 UI。选完把下标交回给道具，怎么处理是它自己的事。
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


# --- 存档 ----------------------------------------------------------------------

## 进关自动存一次。由 StoryDirector 在剧情状态恢复完成之后调用——
## **刻意不放 LevelBase._ready()**：那里跑的都是无副作用的初始化，而写盘是
## 副作用，而且测试会反复实例化关卡（test_old_courtyard 就连开四份来验证
## 读档恢复），放进去每跑一次测试都会污染真实存档。
##
## 没有活动槽位时 SaveManager.save_progress() 直接返回 false 不写盘，
## 所以 F6 单开和 headless 测试永远碰不到真实存档文件。
func autosave() -> bool:
	if _player == null:
		return false
	return SaveManager.save_progress(scene_file_path, _player.global_position)


# --- 去下一关 -------------------------------------------------------------------

## 幂等：只会成功一次。**只管怎么走**，门槛由 LevelExit / StoryDirector 把关。
func go_to_next_level(target_scene: String) -> void:
	if _leaving or target_scene.is_empty():
		return
	if not ResourceLoader.exists(target_scene):
		push_error("CourtyardLevel: 下一关场景不存在：%s" % target_scene)
		return
	_leaving = true
	# 离关先存一次。坐标传 use_level_spawn=true —— 我们不知道下一关的入口在
	# 哪，让它用自己的 SpawnPoint，别把 (0,0) 当成真坐标钉进存档。
	SaveManager.save_progress(target_scene, Vector2.ZERO, true)
	complete_level()
	level_left.emit(target_scene)
	# 只在独立运行时真的切场景（被测试当子场景实例化时不切）。
	if get_tree().current_scene == self:
		get_tree().change_scene_to_file.call_deferred(target_scene)
