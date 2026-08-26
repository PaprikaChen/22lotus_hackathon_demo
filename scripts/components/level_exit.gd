class_name LevelExit
extends Interactable
## 通往下一关的出口。**只管「怎么走」，不判断「能不能走」**——
## 门槛用基类的 `required_flag` / `required_memory`，什么时候放开由
## StoryDirector 决定。真正的场景切换由关卡脚本做（`go_to_next_level()`），
## 因为「切场景」是关卡机制，不是这个道具的事。
##
## 刻意不建 SceneManager：等真需要统一 fade / autosave / loading 时再抽
## （叙事计划书 §14）。

signal exit_reached(target_scene: String)

@export_file("*.tscn") var target_scene: String = ""
## true = 走到就触发；false = 按 E 触发。
@export var trigger_on_touch: bool = false


func _ready() -> void:
	if trigger_on_touch:
		body_entered.connect(_on_body_entered)


## 门槛是否满足（基类逻辑），关卡可以据此决定提示语。
func is_open() -> bool:
	return is_requirement_met()


func _on_interact(_player: Node) -> void:
	_request_exit()


func _on_body_entered(body: Node2D) -> void:
	if not trigger_on_touch or body is not Player:
		return
	# 走到即触发也要过门槛：不满足就走基类的 blocked 反馈路径。
	if not is_requirement_met():
		_on_blocked_interact(body)
		interaction_blocked.emit(body)
		return
	_request_exit()


func _request_exit() -> void:
	if target_scene.is_empty():
		push_warning("LevelExit '%s': 没设 target_scene，什么都不会发生。" % name)
		return
	exit_reached.emit(target_scene)
