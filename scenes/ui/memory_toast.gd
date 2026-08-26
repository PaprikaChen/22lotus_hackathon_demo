extends CanvasLayer
## Graybox toast queue for 梦奁 notifications ("梦奁新增：…" / "梦奁更新：…").
## Listens to MemoryManager signals only — it never changes memory state.
## Runs while the tree is paused (the memory box pauses the world), and
## queues messages so rapid unlocks display one after another, in order.

const SHOW_SECONDS := 1.8

@onready var _label: Label = $ToastLabel

var _queue: Array[String] = []
var _showing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label.visible = false
	MemoryManager.memory_unlocked.connect(_on_memory_unlocked)
	MemoryManager.memory_updated.connect(_on_memory_updated)


## Exposed for tests / other systems that want a one-off toast.
func push_message(message: String) -> void:
	_queue.append(message)
	if not _showing:
		_show_next()


func pending_count() -> int:
	return _queue.size() + (1 if _showing else 0)


# --- Internal ---------------------------------------------------------------

func _title_for(memory_id: StringName) -> String:
	var entry := MemoryManager.get_memory_data(memory_id)
	return entry.title if entry != null else String(memory_id)


func _on_memory_unlocked(memory_id: StringName) -> void:
	push_message("梦奁新增：%s" % _title_for(memory_id))


func _on_memory_updated(memory_id: StringName, _old_stage: int, _new_stage: int) -> void:
	push_message("梦奁更新：%s" % _title_for(memory_id))


func _show_next() -> void:
	_showing = true
	while not _queue.is_empty():
		_label.text = _queue.pop_front()
		_label.visible = true
		# process_always = true so the timer ticks while the tree is paused.
		await get_tree().create_timer(SHOW_SECONDS, true).timeout
	_label.visible = false
	_showing = false
