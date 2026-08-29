class_name Courtyard03IncenseMemoryLevel
extends LevelBase
## 香炉记忆小关卡的关卡侧机制：只负责返回 courtyard_03。
##
## 本关是临时演出空间，不写入存档 current_scene；对白顺序、完成条件和白幕
## 时机全部由本关 StoryDirector 决定。

const RETURN_SCENE := "res://scenes/levels/courtyard_03.tscn"

var _returning: bool = false


func return_to_courtyard() -> bool:
	if _returning or not ResourceLoader.exists(RETURN_SCENE):
		return false
	_returning = true
	complete_level()
	if get_tree().current_scene == self:
		get_tree().change_scene_to_file.call_deferred(RETURN_SCENE)
	return true
