extends StoryDirector
## courtyard_04 的剧情编排骨架。结构和 courtyard_02 / 03 一致。
##
## 目前只做一件事：进关自动存档。调查点、灯笼、演出等到叙事定稿再往里加——
## 「什么时候发生什么」一律写在这里，不要下放到关卡脚本（AGENTS.md §5.5）。

@onready var _courtyard: CourtyardLevel = get_node(level_path) as CourtyardLevel


func _on_story_ready() -> void:
	if _courtyard != null:
		_courtyard.autosave()
