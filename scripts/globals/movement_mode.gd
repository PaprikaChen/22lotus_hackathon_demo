class_name MovementMode
extends RefCounted
## Shared enum: how a level drives the player's body.
##
## Movement style is LEVEL configuration — a level declares it on LevelBase
## and LevelBase hands it to the player. Nothing anywhere is allowed to
## branch on a scene name to decide whether the player may move in depth.
##
## SIDE_SCROLL — classic platforming. x = horizontal, y = height. Gravity
##   and jump are active. This is the default: every existing level keeps
##   behaving exactly as before.
## DEPTH_2_5D — horizontal-first 2.5D. x = horizontal, y = DEPTH (further
##   back = smaller y). No gravity, no jump; depth speed is much slower than
##   horizontal so the level still reads as a side-scroller.
##
## Only the movement code is allowed to know this enum. Save, collectible,
## interaction, dialogue and scene-transition systems must stay unaware.

enum Mode {
	SIDE_SCROLL,
	DEPTH_2_5D,
}


## Human-readable name for debug overlays.
static func get_mode_name(mode: Mode) -> String:
	return "SIDE_SCROLL" if mode == Mode.SIDE_SCROLL else "DEPTH_2_5D"
