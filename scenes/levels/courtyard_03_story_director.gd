extends StoryDirector
## courtyard_03 的剧情编排骨架。
##
## 当前只在关卡状态恢复完成后自动存档；后续剧情因果统一加在这里，
## 不放进 CourtyardLevel 或交互物自身。

@onready var _courtyard: CourtyardLevel = get_node(level_path) as CourtyardLevel


func _connect_actors() -> void:
	pass


func _restore_story_state() -> void:
	pass


func _on_story_ready() -> void:
	if _courtyard != null:
		_courtyard.autosave()
