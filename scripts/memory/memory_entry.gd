class_name MemoryEntry
extends Resource
## Static definition of a memory keepsake (梦奁信物): identity, title, icon
## and the ordered interpretation stages. NEVER stored in save files — saves
## hold only runtime state keyed by `id` (see MemoryManager).
##
## `id` is a persistent identifier: once it has shipped in a save file it
## must never be renamed. Titles/descriptions may change freely.

@export var id: StringName = &""
@export var title: String = ""
@export var icon: Texture2D
@export var stages: Array[MemoryStage] = []


func get_stage_count() -> int:
	return stages.size()


func get_last_stage_index() -> int:
	return maxi(0, stages.size() - 1)


## Safe accessor: out-of-range indices clamp instead of erroring, so old
## saves keep working when stages are added or removed later.
func get_stage(stage_index: int) -> MemoryStage:
	if stages.is_empty():
		return null
	return stages[clampi(stage_index, 0, stages.size() - 1)]


func get_stage_description(stage_index: int) -> String:
	var stage := get_stage(stage_index)
	return stage.description if stage != null else ""
