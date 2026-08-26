# Project Overview

This is a Godot 4.x 2.5D Chinese psychological horror game named
《二十二莲境》.

The game combines:

- platforming
- light environmental puzzles
- narrative exploration
- Chinese retro visual elements
- dreamcore imagery
- themes of female growth

The project is currently in the demo development stage.

# Technical Rules

- Use Godot 4.x APIs only.
- Use GDScript unless explicitly instructed otherwise.
- Prefer typed GDScript.
- Do not edit imported files under `.godot/`.
- Do not directly modify source image assets.
- Do not rename or move existing assets without explicit permission.
- Do not delete scenes or scripts unless explicitly requested.
- Reuse existing components before creating new systems.
- Keep scripts focused and reasonably small.
- Use signals to reduce unnecessary coupling.
- Save scenes after editor modifications.

# Scene Editing Rules

Before editing a scene:

1. Inspect the current scene tree.
2. Identify inherited scenes and instanced scenes.
3. Explain the intended change briefly.
4. Make only the requested changes.
5. Run the affected scene after editing.
6. Report any editor or runtime errors.

# Safety Rules

- Before a large change, check Git status.
- Do not overwrite uncommitted work unrelated to the task.
- Do not perform project-wide refactors without permission.
- Do not change project settings unless required.
- Ask before modifying input mappings, autoloads, render settings,
  or export settings.

# Design Responsibilities

Claude may independently implement:

- reusable gameplay components
- player movement logic
- interaction systems
- save systems
- dialogue plumbing
- UI infrastructure
- debugging tools

Claude should not independently decide:

- final level composition
- narrative meaning
- visual symbolism
- horror pacing
- final platforming feel
- art direction

# Project Reference

Concrete facts about the current repository state (keep updated as the
project grows).

## Engine & Config

- Engine: Godot 4.4 (Forward Plus renderer).
- Project name in `project.godot`: `22lotus`.
- Main scene: `res://scenes/ui/MainMenu.tscn`.
- Input actions: `move_left` (A/←), `move_right` (D/→), `move_up` (W/↑),
  `move_down` (S/↓), `jump` (Space), `slow_time` (Shift), `interact` (E),
  `open_memory_box` (Tab). `move_up`/`move_down` are only read by the
  2.5D depth movement mode; side-scrolling levels ignore them.
- Base systems are implemented: player movement + input lock, DreamGap
  slow-time, versioned save system, story flags, interaction, LevelBase
  and test rooms under `tests/`. `AGENTS.md` holds the authoritative
  architecture snapshot and modification rules — read it before
  changing code.

## Directory Layout

Scenes, scripts, and assets are separated by responsibility (demo-stage
convention; revisit if feature-based co-location becomes preferable).

- `scenes/` — scene files (`.tscn`).
  - `levels/` — playable levels / rooms.
  - `player/` — player character scene(s).
  - `ui/` — menus, HUD, dialogue boxes.
  - `components/` — reusable scene fragments (interactables, triggers).
  - `props/` — environmental objects and decorations.
- `scripts/` — standalone GDScript not co-located with a scene.
  - `autoload/` — singleton scripts registered as autoloads.
  - `components/` — reusable component scripts.
  - `globals/` — shared constants, enums, helper libraries.
- `assets/` — source/imported content.
  - `art/` — `sprites/`, `backgrounds/`, `tilesets/`.
  - `audio/` — `music/`, `sfx/`.
  - `fonts/`, `shaders/`.
- `resources/` — saved Godot resources: `themes/`, `materials/`.
- `tests/` — graybox test rooms for base systems (`tests/README.md`);
  `helpers/` holds test-only scripts. Never test base systems inside
  real story levels.
- `addons/godot_ai/` — Godot AI MCP plugin (third party; see
  `godot-ai-LICENSE.txt`). Do not modify its internals.
- `icon.svg` — project icon.
- `project.godot` — project configuration. Prefer editing via the
  Godot editor UI rather than by hand.
- `.godot/` — engine-generated cache. Git-ignored; never commit.

Each leaf folder holds a `.gitkeep` placeholder so the empty structure
is tracked by git; remove these once real content lands.

## Autoloads

- `SaveManager` → `res://scripts/autoload/save_manager.gd` — slots,
  versioned JSON saves, temp-file safe writes, story-flag aggregation.
- `WorldTimeManager` → `res://scripts/autoload/world_time_manager.gd` —
  DreamGap slow-time authority (local time-scale pull model; never
  touches `Engine.time_scale`).
- `StoryFlagManager` → `res://scripts/autoload/story_flag_manager.gd` —
  persistent/session story flags.
- `_mcp_game_helper` → `res://addons/godot_ai/runtime/game_helper.gd`
  (provided by the godot_ai plugin). Treat as plugin infrastructure.
- Ask before changing autoloads (see Safety Rules).

## Editor via MCP

The `godot-ai` MCP server can read/write scenes, nodes, and scripts
while the Godot editor is running. Common read-only operations:

- `editor_state` — editor readiness, version, current scene.
- `scene_get_hierarchy` — current scene node tree.

Confirm the target scene is open in the editor before editing it.

## Conventions

- Line endings: LF for all text files (`.gitattributes`).
- Encoding: UTF-8 (`.editorconfig`).
- Git-ignored: `.godot/` and `/android/` (`.gitignore`).
