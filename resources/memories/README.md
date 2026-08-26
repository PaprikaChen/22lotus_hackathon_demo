# Memory keepsake resources (梦幠信物)

Each `.tres` is a `MemoryEntry` (id, title, icon, ordered `MemoryStage`s).
Registered automatically by `MemoryManager` at startup — drop a new .tres
here and it becomes unlockable by its `id`.

Rules: `id` is persistent (never rename once shipped in a save); text and
icons may change freely; stage additions keep old saves valid (stages are
clamped on load).

`whitebox_25d_collectible_01/02.tres` are **test** keepsakes used by
`tests/whitebox_25d/` to verify collecting + saving in 2.5D. They are
registered like any other entry (so they can appear in the 梦奁 UI once
picked up) and their titles are prefixed 【测试】. Delete both files if the
2.5D whitebox room is ever removed.

`bg_pacing_token_01/02/03.tres` are **test** keepsakes used by
`tests/bg_pacing/` (手感调参台). `..._02` is the one the lab's block door
gates on. Same rules as the whitebox pair: registered like any other entry,
titles prefixed 【测试】, delete all three if the pacing lab is removed.
