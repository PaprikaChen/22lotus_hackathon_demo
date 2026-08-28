extends StoryDirector
## courtyard_02（里院）的剧情编排。目前是占位骨架，结构和 courtyard_01 一致。
##
## 因果链待叙事定稿。现在只做：进关自动存档、调查过的物件记 Flag。

const FLAG_SCREEN_EXAMINED := &"courtyard_02.screen_examined"

@export var dialogue_box_path: NodePath

@onready var _courtyard: CourtyardLevel = get_node(level_path) as CourtyardLevel
@onready var _screen: Interactable = get_node_or_null(^"../Props/ScreenSpot")
@onready var _flower_side: Interactable = get_node_or_null(^"../Props/notebook")
@onready var _dialogue: Node = get_node_or_null(dialogue_box_path)
@onready var _paper_overlay: Control = get_node_or_null(^"../PaperOverlay/Root") as Control


func _connect_actors() -> void:
	if _screen != null:
		_screen.interacted.connect(_on_screen_examined)
	if _flower_side != null:
		_flower_side.interacted.connect(_on_flower_side_examined)


func _restore_story_state() -> void:
	_hide_paper_overlay()


func _on_story_ready() -> void:
	if _courtyard != null:
		_courtyard.autosave()


func _on_screen_examined(_player: Node) -> void:
	if StoryFlagManager.has_flag(FLAG_SCREEN_EXAMINED):
		return
	StoryFlagManager.set_flag(FLAG_SCREEN_EXAMINED)
	# 占位接线，同 courtyard_01。剧情定稿后换成真正的 CG id。
	GalleryManager.unlock_cg(&"cg_placeholder_02")


## 花旁纸片沿用香炉的图示流程：字幕关闭时一并收起黑幕与图片。
func _on_flower_side_examined(_player: Node) -> void:
	if _paper_overlay == null:
		return
	_paper_overlay.visible = true
	if _dialogue != null and _dialogue.has_signal(&"closed"):
		_dialogue.connect(&"closed", _hide_paper_overlay, CONNECT_ONE_SHOT)


func _hide_paper_overlay() -> void:
	if _paper_overlay != null:
		_paper_overlay.visible = false
