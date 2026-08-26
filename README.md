# 《二十二莲境》开发说明（Demo 阶段）

Godot 4.4（Forward Plus）2.5D 中式心理恐怖游戏，当前处于 Demo 原型开发阶段。
本文件记录已实现的系统、目录结构与重要文件，便于后续接手与扩展。

> 约定与规则见 [CLAUDE.md](CLAUDE.md)。引擎设置优先用 Godot 编辑器 / godot-ai MCP 修改，
> 不要手改 `.godot/`。

---

## 一、已实现的系统

### 1. 存档系统 + 主菜单（UI 原型）

- 主菜单：`Start New Game` / `Load Game` / `Exit`。
- 3 个独立存档槽，写入 `user://save_slot_{1,2,3}.json`（纯 JSON，仅原始类型，
  不写节点 / Object）。
- 字段：`save_slot_id`、`created_at`、`last_saved_at`、`current_scene`、
  `checkpoint_id`、`player_position_x/y`、`play_time_seconds`。
- `Start New Game`：空槽直接建档；已有槽弹出覆盖确认后再覆盖。
- `Load Game`：空/损坏槽显示 Empty 且不可读；已有槽显示最后保存时间 / 场景 / 游玩时长，
  读取后进入存档记录的场景与坐标。
- 健壮性：文件不存在 / JSON 解析失败 / 字段缺失都不崩溃，`push_error` 后回菜单。
- 所有文件读写集中在 **`SaveManager`（Autoload）**，UI 不直接碰文件系统。

启动场景 `run/main_scene` = `res://scenes/ui/MainMenu.tscn`。

### 2. 平台跳跃核心玩法原型 + 世界减速能力（灰盒）

- **Player**（`CharacterBody2D`）：左右移动、跳跃、重力、地面检测、加速/摩擦、
  朝向更新、掉出关卡回出生点。手感参数全部 `@export`。仅做基础移动，
  预留了二段跳 / 冲刺 / 攀墙等后续扩展空间。
- **世界减速能力**：按 `slow_time` 开启，再按一次提前结束；最多持续 3 秒后自动结束；
  结束后进入 2 秒冷却。**世界对象变慢（25%），Player 保持 100% 正常速度。**
  时长与冷却使用真实时间，不受减速影响。
- **不使用 `Engine.time_scale`**。统一由 **`WorldTimeManager`（Autoload）** 维护
  状态机（`READY / ACTIVE / COOLDOWN`）与 `world_time_scale`。世界对象自取
  `get_scaled_delta(delta)` 移动；Player 用普通 `delta`。
- **状态与 Signal 解耦美术**：`WorldTimeManager` 发出
  `slow_time_started / slow_time_ended / slow_time_state_changed / slow_time_energy_changed`，
  未来的睁眼 / 变色 / 后处理 / 粒子 / 音效 / 动画都通过监听这些信号接入，
  无需改动时间管理器。`SlowTimeVisualTest` 是这种接法的活样例（减速时整屏变蓝）。
- **移动平台**（`AnimatableBody2D`）：两 Marker2D 间往返，可载着 Player 一起移动，
  用 scaled delta，减速时明显变慢。
- **测试敌人 / 危险物**：左右巡逻，用 scaled delta；接触 Player → 回出生点并打印测试信息。
- **Debug UI**：实时显示状态 / 剩余时长 / 冷却 / world_time_scale（仅开发用，
  只读公开接口）。
- **关卡阶段扩展入口**：`LevelPhase { INTRO, PLATFORMING, COMPLETE }`，
  当前直接从 `PLATFORMING` 开始，Intro 预留未实现。

---

## 二、目录结构（重要文件）

```
res://
├── scenes/
│   ├── ui/
│   │   ├── MainMenu.tscn / main_menu.gd          # 主菜单
│   │   └── SaveSlotMenu.tscn / save_slot_menu.gd # 存档槽选择（new/load 复用 + 覆盖确认）
│   ├── player/
│   │   └── player.tscn / player.gd               # CharacterBody2D 平台跳跃 Player
│   ├── components/                               # 可复用世界对象
│   │   ├── moving_platform.tscn / moving_platform.gd  # 载人移动平台
│   │   └── test_enemy.tscn / test_enemy.gd            # 巡逻测试敌人/危险物
│   └── levels/
│       ├── Main... (TestLevel.tscn / test_level.gd)   # 存档系统的最小测试场景
│       └── dream_platforming_test.tscn / .gd          # ★ 平台跳跃灰盒测试关卡
├── scripts/
│   ├── autoload/
│   │   ├── save_manager.gd            # ★ Autoload: 存档读写（user://）
│   │   └── world_time_manager.gd      # ★ Autoload: 世界减速状态机 + Signal
│   └── components/
│       ├── slow_time_visual_test.gd   # 监听信号的减速视觉演示（CanvasModulate）
│       └── slow_time_debug_ui.gd      # 减速能力 Debug UI（Label）
├── assets/   (art / audio / fonts / shaders 占位)
├── resources/(themes / materials 占位)
├── addons/godot_ai/                   # godot-ai MCP 插件（第三方，勿改内部）
├── project.godot                      # autoload / input map / main_scene
└── CLAUDE.md                          # 项目规则与约定
```

★ = 本次重点新增 / 核心文件。

---

## 三、Autoload（`project.godot`）

| 名称 | 脚本 | 作用 |
|------|------|------|
| `_mcp_game_helper` | `addons/godot_ai/runtime/game_helper.gd` | godot-ai 插件基础设施 |
| `SaveManager` | `scripts/autoload/save_manager.gd` | 存档读写 |
| `WorldTimeManager` | `scripts/autoload/world_time_manager.gd` | 世界减速状态与信号 |

## 四、Input Map（`project.godot`）

| Action | 默认按键 |
|--------|----------|
| `move_left` | A / ← |
| `move_right` | D / → |
| `jump` | Space |
| `slow_time` | Shift |

> 说明：`player.gd` 用 `is_action_pressed` 的上升沿手动检测 `jump` / `slow_time`，
> 在真实键盘上等价于 `is_action_just_pressed`。

---

## 五、运行与测试

- **完整流程**：直接运行项目（`F5`），从主菜单 → 新建/读取存档 → 进入 `TestLevel`。
- **平台跳跃关卡**：在编辑器打开
  `res://scenes/levels/dream_platforming_test.tscn` 并运行当前场景（`F6`）。
  - 移动：A/D 或 ←/→；跳跃：Space；世界减速：Shift（再按一次提前结束）。
  - 减速开启时：敌人/移动平台明显变慢、整屏变蓝、Debug UI 显示 `ACTIVE` 与倒计时；
    Player 移动手感不变。
  - 跳上高台、站上移动平台随其移动、碰敌人/掉落 → 回出生点。

> 已知：通过 godot-ai MCP 自动注入按键只能模拟"持续按住"，无法模拟单帧"按下边沿"，
> 因此技能/跳跃需真人按键测试（已手动验证通过）。

---

## 六、SaveManager / WorldTimeManager 公开接口

```gdscript
# SaveManager
func create_new_save(slot_id: int) -> bool
func save_game(slot_id: int, save_data: Dictionary) -> bool
func load_game(slot_id: int) -> Dictionary
func delete_save(slot_id: int) -> bool
func save_exists(slot_id: int) -> bool
func get_save_summary(slot_id: int) -> Dictionary

# WorldTimeManager
func request_slow_time() -> bool        # 仅 READY 时成功，连按安全
func stop_slow_time() -> void           # 仅 ACTIVE 时生效
func is_slow_time_active() -> bool
func is_slow_time_ready() -> bool
func get_scaled_delta(delta: float) -> float   # 世界对象用这个
func get_active_time_remaining() -> float
func get_cooldown_time_remaining() -> float
signal slow_time_started
signal slow_time_ended
signal slow_time_state_changed(new_state)
signal slow_time_energy_changed(active_remaining, cooldown_remaining)
```

---

## 七、后续可扩展方向（未实现）

- 关卡 Intro 阶段（走动探索 / 剧情触发 / 镜头演出）。
- 美术接入：监听 `WorldTimeManager` 信号实现睁眼 / 变色 / 后处理 / 粒子 / 音效。
- Player 进阶能力：二段跳、冲刺、攀墙、蹬墙跳、攻击、正式动画。
- 正式美术资源替换当前 ColorRect / Polygon2D 灰盒占位。
