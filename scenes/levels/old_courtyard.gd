class_name OldCourtyard
extends LevelBase
## 旧院 chapter — graybox side-scrolling exploration level.
##
## Three areas in ONE scene (落地点/院门 → 枯海棠树 → 主屋前/侧窗), linked by
## AreaFlowController (right-edge trigger → fade → teleport → camera limits).
##
## 本脚本只管**关卡侧的机制**：相机跟随、交互提示、把 text_requested 接到
## 共用对话框、以及“进主屋”这一次场景切换怎么做。
##
## **什么时候**进主屋、剧情按什么顺序发生、丫鬟什么时候出现——全部在
## `old_courtyard_story_director.gd`。不要往这里加剧情判断（见
## NARRATIVE_LAYER_DESIGN.md §8）。

signal entered_main_house

const CAMERA_Y := 324.0
const INTERIOR_SCENE := "res://scenes/levels/main_house_interior.tscn"

@onready var _p: CharacterBody2D = get_node(player_path)
@onready var _detector: InteractionDetector = _p.get_node("InteractionDetector")
@onready var _camera: Camera2D = $Camera2D
@onready var _prompt_label: Label = $UI/PromptLabel
@onready var _dialogue: CanvasLayer = $DialogueBox

var _entered_house: bool = false


func _ready() -> void:
	super._ready()
	_detector.prompt_changed.connect(_on_prompt_changed)
	for prop in _collect_text_props(self):
		prop.text_requested.connect(_show_text)
	# Leftover interaction text has no business surviving an area change.
	$AreaFlowController.area_changed.connect(
		func(_index: int) -> void: _dialogue.hide_box())


func _process(_delta: float) -> void:
	# Existing per-level follow pattern; area limits on the camera do the
	# clamping, so nothing else is needed here.
	_camera.global_position = Vector2(_p.global_position.x, CAMERA_Y)


# --- UI wiring --------------------------------------------------------------

func _on_prompt_changed(text: String) -> void:
	_prompt_label.text = "[E] %s" % text if not text.is_empty() else ""


func _show_text(text: String) -> void:
	# All interaction/dialogue text goes through the shared bottom box.
	_dialogue.show_text(text)


func _collect_text_props(node: Node, found: Array = []) -> Array:
	for child in node.get_children():
		if child.has_signal("text_requested"):
			found.append(child)
		_collect_text_props(child, found)
	return found


# --- 场景切换机制（由 StoryDirector 决定什么时候调）---------------------------

## 进主屋。**只管怎么进**，不判断能不能进——门槛在 StoryDirector 里。
## 幂等：只会成功一次。
func enter_main_house() -> void:
	if _entered_house:
		return
	_entered_house = true
	entered_main_house.emit()
	complete_level()
	# Only change scenes when running standalone (not instanced inside a test).
	if get_tree().current_scene == self:
		get_tree().change_scene_to_file.call_deferred(INTERIOR_SCENE)
