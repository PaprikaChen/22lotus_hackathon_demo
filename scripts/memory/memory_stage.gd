class_name MemoryStage
extends Resource
## One stage of a memory keepsake's interpretation. As the story progresses
## the SAME keepsake advances through stages — the text changes, the item
## does not duplicate.

## Optional short heading for this stage ("" = none).
@export var stage_title: String = ""

@export_multiline var description: String = ""
