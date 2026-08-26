# Tests

Graybox test rooms for the base systems. Run each scene directly from the
editor; automated checks print `[TEST:*] PASS/FAIL` lines to the output.

- `test_player_movement.tscn` — movement, states, input lock.
- `test_dream_gap.tscn` — DreamGap slow-time, reveal, cooldown, reset.
- `test_interaction.tscn` — Interactable / InteractionDetector.
- `test_save_load.tscn` — save versioning, legacy/corrupt saves, flag round trip.
- `test_memory_box.tscn` — 梦奁 memory keepsakes: unlock/advance stages,
  NEW/UPDATED badges, Tab/Esc box UI, save round trip (uses slot 3 with
  automatic backup).
- `test_old_courtyard.tscn` — drives the real 旧院 chapter level
  (`scenes/levels/old_courtyard.tscn`): area switching, camera limits,
  placeholder interactions, and the full StoryDirector narrative chain
  （药圃 + 侧窗 → 母亲幻觉 Cutscene → 丫鬟入场 → 对话 → 侧窗解锁成主屋入口）。
  含两组关键回归：**读档恢复不重播**（重新实例化关卡，验证 Cutscene 不重演、
  丫鬟在场/离场状态正确），以及**新游戏落点**（`use_level_spawn` 让新档用
  关卡自己的 SpawnPoint，真实存档仍用存档坐标）。
- `test_integration.tscn` — all systems together in one level slice
  (save point → moving platform over a pit → enemy → key → locked door →
  goal). Manual playthrough plus a headless smoke test of the wiring.
  `helpers/test_key_pickup.gd`, `test_door.gd`, `test_memory_door.gd` and
  `test_save_point.gd` double as reference implementations for real
  interactables. `test_memory_door.gd` gates on 梦奁 keepsake ownership
  (`MemoryManager.has_memory`) instead of a story flag.

- `whitebox_25d/whitebox_25d.tscn` — 2.5D 白盒验证房（`MovementMode.DEPTH_2_5D`）：
  纵深移动、可行走区边界、Y Sort、固定前/后景、现有信物与存档在 2.5D 下照常
  工作。纯几何素材，不是正式关卡内容。手动：A/D 左右，W/S 前后，E 交互，
  F1 调试叠层，F2 Y Sort 原点标记。

- `bg_pacing/bg_pacing_lab.tscn` — 手感调参台（不是关卡）：一整张长幅背景
  草图 `assets/art/backgrounds/testbg.jpg` + 一条地面碰撞体 + 现有玩家方块。
  运行时可调背景缩放、人物体型、移动速度、相机 zoom、地面线高度，HUD 实时
  给出"走完全程几秒 / 一屏几秒 / 人物占屏高比例 / 一跳能跨多远"，用来判断
  人物速度与场景建筑密度的关系。headless 运行会打印一次 `[LAB:bg_pacing]`
  参数快照后自动退出（注意 headless 是 64×64 假窗口，镜头相关数字不可信），
  同时跑一遍 `[TEST:bg_pacing]` 信物门槛断言。房间里另有 3 个可拾取的信物
  方块（甲/乙/丙）和一扇 `helpers/test_memory_door.gd` 的方块门——门槛是
  “持有信物 乙”，丙在门后，用来验证门真的挡路。

Never test these base systems inside real story levels.
