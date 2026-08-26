class_name SavePoint
extends Interactable
## 存档点：把当前场景与玩家位置写进正在使用的存档槽。
##
## 所有文件 I/O 都在 SaveManager 里，这里只负责组装“这一刻的关卡状态”。
## 直接单开场景（F6、没有活动槽位）时只汇报不写盘，测试跑动永远碰不到
## 真实存档文件。

signal save_finished(message: String)


func _on_interact(player: Node) -> void:
	if SaveManager.current_slot == -1:
		save_finished.emit("未选择存档槽——从主菜单开始游戏后此处才会写盘")
		return
	var p2d := player as Node2D
	var pos := p2d.global_position if p2d != null else Vector2.ZERO
	if SaveManager.save_progress(get_tree().current_scene.scene_file_path, pos):
		save_finished.emit("已保存到槽位 %d" % SaveManager.current_slot)
	else:
		save_finished.emit("保存失败（原存档未被破坏）")
