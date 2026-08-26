extends Node
## Autoload "GalleryManager" —— 画廊 CG 收集的运行时状态。
##
## 结构照 `MemoryManager` 的三层分离：
##   静态数据   `resources/cg/*.tres`（CGEntry），启动时扫目录自动注册
##   运行时状态 `_states`：id → {unlocked, seen}，只有 JSON 安全的原始类型
##   落盘       经 `SaveManager.read_global/write_global` 写 `user://gallery.json`
##
## **与三个存档槽完全无关**：CG 收集是跨存档共享的（画廊入口在主菜单，那时
## 没有任何槽位被载入）。所以它不进 `REQUIRED_KEYS`、不参与 `save_version`
## 迁移、删存档也不会丢收集。
##
## 边界：本管理器不推断剧情。**谁来解锁 CG 是 StoryDirector 的事**——
## CG 解锁是剧情后果，和"写 Flag / 推进信物"同一类，写在 Director 的 `_on_*` 里。
## 它也从不持有场景节点，只发信号让 UI 自己反应。

signal cg_unlocked(cg_id: StringName)
signal cg_state_changed(cg_id: StringName)

const CG_DIR := "res://resources/cg/"
## 全局存储名 → user://gallery.json
const STORE_NAME := "gallery"

## String id -> CGEntry，启动时从 CG_DIR 载入一次。
var _entries: Dictionary = {}
## String id -> {"unlocked": bool, "seen": bool}。这个字典就是落盘内容。
var _states: Dictionary = {}
## 排好序的 id 列表，避免每次查询都重排。
var _sorted_ids: Array[StringName] = []


func _ready() -> void:
	_load_entries()
	_load_from_disk()


# --- 静态数据注册 ---------------------------------------------------------------

func _load_entries() -> void:
	var dir := DirAccess.open(CG_DIR)
	if dir == null:
		# 还没有任何 CG 资源是正常状态（画廊会显示空），不该报错。
		return
	for file_name in dir.get_files():
		# 导出版本可能列出 "*.tres.remap"，按原名载入。
		var res_name := file_name.trim_suffix(".remap")
		if not res_name.ends_with(".tres"):
			continue
		var entry := load(CG_DIR + res_name) as CGEntry
		if entry == null or entry.id == &"":
			push_warning("GalleryManager: %s 不是有效的 CGEntry，已跳过。" % res_name)
			continue
		var key := String(entry.id)
		if _entries.has(key):
			push_warning("GalleryManager: CG id 重复 '%s'，保留第一个。" % key)
			continue
		_entries[key] = entry
	_rebuild_sorted()


func _rebuild_sorted() -> void:
	var ids: Array[StringName] = []
	for key: String in _entries.keys():
		ids.append(StringName(key))
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		var ea: CGEntry = _entries[String(a)]
		var eb: CGEntry = _entries[String(b)]
		if ea.sort_order != eb.sort_order:
			return ea.sort_order < eb.sort_order
		return String(a) < String(b))
	_sorted_ids = ids


# --- 公开 API -------------------------------------------------------------------

## 解锁一张 CG 并标记为未看过。**只有真正发生解锁时返回 true**——
## 重复解锁已有的 CG 不会重置 seen、也不会重复提示。
func unlock_cg(cg_id: StringName) -> bool:
	var key := String(cg_id)
	if not _entries.has(key):
		push_warning("GalleryManager: 未知的 CG id '%s'。" % key)
		return false
	if has_cg(cg_id):
		return false
	_states[key] = {"unlocked": true, "seen": false}
	_save_to_disk()
	cg_unlocked.emit(cg_id)
	cg_state_changed.emit(cg_id)
	return true


func has_cg(cg_id: StringName) -> bool:
	return bool(_states.get(String(cg_id), {}).get("unlocked", false))


## 玩家真的看过大图之后清掉 NEW 角标。
func mark_as_seen(cg_id: StringName) -> void:
	var key := String(cg_id)
	if not _states.has(key) or bool(_states[key].get("seen", false)):
		return
	_states[key]["seen"] = true
	_save_to_disk()
	cg_state_changed.emit(cg_id)


func is_unseen(cg_id: StringName) -> bool:
	var state: Dictionary = _states.get(String(cg_id), {})
	return bool(state.get("unlocked", false)) and not bool(state.get("seen", false))


## 静态定义，未知 id 返回 null。
func get_cg_data(cg_id: StringName) -> CGEntry:
	return _entries.get(String(cg_id))


## **含未解锁的**，按 sort_order 排。画廊要给未解锁的画占位格子。
func get_all_cgs() -> Array[StringName]:
	return _sorted_ids.duplicate()


func get_total_count() -> int:
	return _entries.size()


func get_unlocked_count() -> int:
	var n := 0
	for id in _sorted_ids:
		if has_cg(id):
			n += 1
	return n


## 全清。调试和测试用；正常游戏流程**不该**清空跨存档收集
## （新游戏也不清——CG 收集是账号级的）。
func reset() -> void:
	_states.clear()
	_save_to_disk()


# --- 落盘 ----------------------------------------------------------------------

## 所有文件 I/O 都经 SaveManager（项目硬规则），这里只负责数据形状。
func _load_from_disk() -> void:
	var data := SaveManager.read_global(STORE_NAME)
	_states.clear()
	var raw_states: Variant = data.get("cgs", {})
	if typeof(raw_states) != TYPE_DICTIONARY:
		push_warning("GalleryManager: gallery.json 的 cgs 字段格式不对，按空处理。")
		return
	# 宽容读取：未知 id 保留但不显示（可能是回退了版本），字段缺失取安全默认。
	for key: String in (raw_states as Dictionary).keys():
		var raw: Variant = (raw_states as Dictionary)[key]
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		_states[key] = {
			"unlocked": bool((raw as Dictionary).get("unlocked", false)),
			"seen": bool((raw as Dictionary).get("seen", false)),
		}
	for key: String in _states.keys():
		cg_state_changed.emit(StringName(key))


func _save_to_disk() -> void:
	SaveManager.write_global(STORE_NAME, {"cgs": _states.duplicate(true)})
