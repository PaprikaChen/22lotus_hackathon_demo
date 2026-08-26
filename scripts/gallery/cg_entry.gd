class_name CGEntry
extends Resource
## 一张画廊 CG 的静态定义：身份、标题、图、排序。
##
## **绝不写进任何存档文件**——落盘的只有按 `id` 索引的运行时状态
## （见 `GalleryManager`）。和 `MemoryEntry` 同一条纪律。
##
## `id` 是持久标识：一旦写进 `user://gallery.json` 就不得改名。
## 标题、图、说明文字随时可以换。

@export var id: StringName = &""
@export var title: String = ""
## 全尺寸图，点开时显示。
@export var image: Texture2D
## 网格里的缩略图。留空则直接用 image（由 UI 缩放）。
@export var thumbnail: Texture2D
@export_multiline var caption: String = ""
## 画廊里的固定排序。不依赖文件名，也不依赖解锁顺序。
@export var sort_order: int = 0


## 缩略图缺省回退到全图，UI 不用各处判空。
func get_thumbnail() -> Texture2D:
	return thumbnail if thumbnail != null else image
