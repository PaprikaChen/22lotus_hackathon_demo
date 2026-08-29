class_name ShadowPlayConfig
extends RefCounted
## Interior_02 十幕皮影戏的集中配置。
##
## 这里只保存资源路径和舞台数据，不加载资源、不操作节点。资源路径刻意使用
## String 而不是 preload，确保进入关卡时不会让十幕贴图同时常驻。

const ART_DIR: String = "res://assets/art/backgrounds/drama/"
const CANVAS_SIZE: Vector2 = Vector2(1920.0, 972.0)

const MOM1_PATH: String = ART_DIR + "mom1.png"
const MOM2_PATH: String = ART_DIR + "mom2.png"
const DAD_PATH: String = ART_DIR + "dad.png"
const BOAT_PATH: String = ART_DIR + "py_01_boat.png"

const MOM1_ANCHOR: Vector2 = Vector2(628.0, 824.0)
const MOM2_ANCHOR: Vector2 = Vector2(533.0, 726.0)
const DAD_ANCHOR: Vector2 = Vector2(453.0, 820.0)
## 船的锚点取甲板中央，Player 原点会落在甲板上而不是船底。
const BOAT_DECK_ANCHOR: Vector2 = Vector2(684.0, 756.0)

## 最常调整的四项放在每幕开头：
##   spawn_x / exit_x / ground_y / player_scale。
## player_scale 是相对人物原始 1920×972 全画布素材的倍率（0.70 = 70%）。
## 第十幕 has_exit=false，exit_x 不生效；dad_distance 也是逐幕配置。
const STAGES: Array[Dictionary] = [
	{
		"spawn_x": 190.0, "exit_x": 1370.0, "ground_y": 700.0, "player_scale": 0.70,
		"caption": "姑娘只身千里,岂不惧乎?", "caption_position": Vector2(800.0, 150.0),
		"caption_size": Vector2(400.0, 80.0), "caption_alignment": HORIZONTAL_ALIGNMENT_RIGHT,
		"left_bound": 70.0, "background": ART_DIR + "bg.png",
		"middle": ART_DIR + "py_01_middle.png", "front": ART_DIR + "py_01_front.png",
		"player_texture": MOM1_PATH, "player_anchor": MOM1_ANCHOR,
		"show_dad": false, "dad_distance": 0.0, "boat_texture": BOAT_PATH,
	},
	{
		"spawn_x": 165.0, "exit_x": 1325.0, "ground_y": 704.0, "player_scale": 0.70,
		"caption": "怎会不怕，只是心向往之。", "caption_position": Vector2(200.0, 270.0),
		"caption_size": Vector2(460.0, 90.0), "caption_alignment": HORIZONTAL_ALIGNMENT_RIGHT,
		"left_bound": 62.0, "background": ART_DIR + "bg.png",
		"middle": ART_DIR + "py_02_middle.png", "front": ART_DIR + "py_02_front.png",
		"player_texture": MOM1_PATH, "player_anchor": MOM1_ANCHOR,
		"show_dad": false, "dad_distance": 0.0, "boat_texture": "",
	},
	{
		"spawn_x": 100.0, "exit_x": 1000.0, "ground_y": 700.0, "player_scale": 0.70,
		"left_bound": 78.0, "background": ART_DIR + "bg.png",
		"middle": ART_DIR + "py_03_middle.png", "front": ART_DIR + "py_03_front.png",
		"player_texture": MOM1_PATH, "player_anchor": MOM1_ANCHOR,
		"show_dad": false, "dad_distance": 0.0, "boat_texture": "",
	},
	{
		"spawn_x": 180.0, "exit_x": 1340.0, "ground_y": 650.0, "player_scale": 0.70,
		"left_bound": 68.0, "background": ART_DIR + "bg.png",
		"middle": ART_DIR + "py_04_middle.png", "front": ART_DIR + "py_04_front.png",
		"player_texture": MOM1_PATH, "player_anchor": MOM1_ANCHOR,
		"show_dad": true, "dad_distance": 142.0, "boat_texture": "",
	},
	{
		"spawn_x": 205.0, "exit_x": 1360.0, "ground_y": 580.0, "player_scale": 0.50,
		"caption": "今日风大，改日再出去。", "caption_position": Vector2(500,550),
		"caption_size": Vector2(540.0, 90.0), "caption_alignment": HORIZONTAL_ALIGNMENT_LEFT,
		"left_bound": 72.0, "background": ART_DIR + "bg.png",
		"middle": ART_DIR + "py_05_middle.png", "front": ART_DIR + "py_05_front.png",
		"player_texture": MOM2_PATH, "player_anchor": MOM2_ANCHOR,
		"show_dad": true, "dad_distance": 150.0, "boat_texture": "",
	},
	{
		"spawn_x": 230.0, "exit_x": 1315.0, "ground_y": 550.0, "player_scale": 0.40,
		"caption": "你如今是杜家夫人，总不能还像从前一样。",
		"caption_position": Vector2(286.0, 650.0), "caption_size": Vector2(900.0, 100.0),
		"caption_alignment": HORIZONTAL_ALIGNMENT_CENTER,
		"left_bound": 64.0, "background": ART_DIR + "bg.png",
		"middle": ART_DIR + "py_06_middle.png", "front": ART_DIR + "py_06_front.png",
		"player_texture": MOM2_PATH, "player_anchor": MOM2_ANCHOR,
		"show_dad": true, "dad_distance": 138.0, "boat_texture": "",
	},
	{
		"spawn_x": 400.0, "exit_x": 1100.0, "ground_y": 550.0, "player_scale": 0.350,
		"caption": "丽娘还小，离不得娘。", "caption_position": Vector2(386.0, 650.0),
		"caption_size": Vector2(700.0, 100.0), "caption_alignment": HORIZONTAL_ALIGNMENT_CENTER,
		"left_bound": 82.0, "background": ART_DIR + "bg.png",
		"middle": ART_DIR + "py_07_middle.png", "front": ART_DIR + "py_07_front.png",
		"player_texture": MOM2_PATH, "player_anchor": MOM2_ANCHOR,
		"show_dad": true, "dad_distance": 146.0, "boat_texture": "",
	},
	{
		"spawn_x": 500.0, "exit_x": 1000.0, "ground_y": 550.0, "player_scale": 0.30,
		"left_bound": 66.0, "background": ART_DIR + "bg.png",
		"middle": ART_DIR + "py_08_middle.png", "front": ART_DIR + "py_08_front.png",
		"player_texture": MOM2_PATH, "player_anchor": MOM2_ANCHOR,
		"show_dad": false, "dad_distance": 0.0, "boat_texture": "",
	},
	{
		"spawn_x": 600.0, "exit_x": 900.0, "ground_y": 550.0, "player_scale": 0.250,
		"left_bound": 74.0, "background": ART_DIR + "bg.png",
		"middle": ART_DIR + "py_09_middle.png", "front": ART_DIR + "py_09_front.png",
		"player_texture": MOM2_PATH, "player_anchor": MOM2_ANCHOR,
		"show_dad": false, "dad_distance": 0.0, "boat_texture": "",
	},
	{
		"spawn_x": 700.0, "exit_x": 0.0, "ground_y": 550.0, "player_scale": 0.350,
		"left_bound": 70.0, "background": ART_DIR + "bg.png",
		"middle": ART_DIR + "py_10.png", "front": "",
		"player_texture": MOM2_PATH, "player_anchor": MOM2_ANCHOR,
		"show_dad": false, "dad_distance": 0.0, "boat_texture": "", "has_exit": false,
	},
]


static func get_stage_count() -> int:
	return STAGES.size()


static func get_stage(index: int) -> Dictionary:
	if index < 0 or index >= STAGES.size():
		return {}
	return STAGES[index]
