# ARCHITECTURE.md — 《二十二莲境》架构说明

本文件描述项目**当前实际是怎么搭起来的**：有哪些层、谁拥有什么状态、
数据往哪个方向流、以及为什么这么分。核对时间 **2026-08-26**，依据是
仓库里全部 46 个 `.gd` 与 21 个 `.tscn` 的真实内容，不是设计意图。

与其他三份文档的分工：

| 文件 | 回答的问题 |
| --- | --- |
| `CLAUDE.md` | 项目是什么、目录约定、Agent 能独立决定什么 |
| `AGENTS.md` | 改代码时**不许**做什么（约束清单、复用指引） |
| **`ARCHITECTURE.md`（本文）** | 系统之间**如何咬合**、状态归谁、数据怎么流 |
| `README.md` | 上手与运行方式（**已严重过时，见第 10 节**） |

---

## 0. 一分钟概览

一个 Godot 4.4 的 2D 横版游戏，核心是**四个互不知道对方存在的全局系统**
（时间 / 存档 / 剧情 Flag / 记忆信物），加上**一条关卡生命周期**
（LevelBase）和**一套交互总线**（Interactable + InteractionDetector）。

三个反复出现的设计手法贯穿全项目：

1. **拉取，不推送** —— 没有任何管理器去遍历场景树控制对象；需要被影响的
   对象自己来取（时间倍率、存档数据、信物状态都是这个模式）。
2. **信号单向出，调用单向入** —— 表现层（UI、美术）只监听信号，管理器
   永远不知道表现节点存在。
3. **静态数据、运行时状态、存档三分** —— 文案与资源在 `.tres`，运行状态在
   Autoload 内存，落盘的只有一小撮原始类型。

---

## 1. 分层与依赖方向

```
┌─────────────────────────────────────────────────────────────┐
│ 全局层 Autoload（常驻，不随场景销毁）                        │
│   SaveManager   WorldTimeManager   StoryFlagManager          │
│                 MemoryManager                                │
└─────────────────────────────────────────────────────────────┘
        ▲ 调用 API                    │ 发 Signal
        │                             ▼
┌─────────────────────────────────────────────────────────────┐
│ 场景层 LevelBase 子类（关卡 / 测试房，一次一个）             │
│   old_courtyard  main_house_interior  tests/*                │
│   持有：Player、Camera2D、UI、Props、AreaFlowController      │
└─────────────────────────────────────────────────────────────┘
        │ 组合                          ▲ Signal
        ▼                               │
┌─────────────────────────────────────────────────────────────┐
│ 组件层（挂在节点上的可复用零件）                             │
│   Player + DreamGapAbility + InteractionDetector             │
│   Interactable 子类   DreamAffectedComponent                 │
│   ExplorationArea     MovingPlatform                         │
└─────────────────────────────────────────────────────────────┘
```

**依赖方向是严格单向的**：组件和关卡可以调 Autoload，Autoload 绝不反向
持有节点引用。唯一的反向通道是 Signal。这条规则是整个架构能保持简单的
根本原因——任何一个关卡被删掉，全局层不会有一行代码需要改。

---

## 2. 全局层：四个 Autoload

注册顺序（`project.godot`）：`SaveManager` → `WorldTimeManager` →
`StoryFlagManager` → `_mcp_game_helper`（插件） → `MemoryManager`。

| Autoload | 拥有 | **不**拥有 | 落盘字段 |
| --- | --- | --- | --- |
| `SaveManager` | 全部 `user://` 文件 I/O、槽位、版本迁移、当前存档内存副本 | 任何游戏逻辑 | 整个文件 |
| `WorldTimeManager` | DreamGap 状态机、`world_time_scale` | 表现、玩家、对象列表 | 无（临时状态不入档） |
| `StoryFlagManager` | 剧情 Flag（persistent / session 两层） | 文案、条件判断 | `story_flags` |
| `MemoryManager` | 信物运行时状态 + 静态资源注册表 | 文案（在 `.tres`）、UI | `memories` |

### 汇总关系

`SaveManager` 是唯一的落盘出口，它在 `save_game()` / `load_game()` 里
主动向另外两个持久化系统取数、还数：

```gdscript
# save_game()
data["story_flags"] = StoryFlagManager.get_save_data()
data["memories"]    = MemoryManager.get_save_data()

# load_game()
StoryFlagManager.load_save_data(data.get("story_flags", {}))
MemoryManager.load_save_data(data.get("memories", {}))
WorldTimeManager.reset_state()   # 读档绝不带入 ACTIVE 的 DreamGap
```

所以**新增一个需要落盘的系统**，只要实现 `get_save_data()` /
`load_save_data()` 这一对方法并在 SaveManager 里接两行，不需要序列化框架。

### 存档格式的两条硬约束

- `REQUIRED_KEYS`（8 个字段）缺一即判定存档损坏。**新字段绝不能加进去**，
  一律用 `data.get("field", 默认值)` 读。
- `SAVE_VERSION = 2`。无版本字段的旧档读为 0。已有一条迁移：版本 < 2 的
  `player_position_y` 加 24，因为玩家原点从身体中心改到了脚底（见第 4 节）。
  迁移只改内存里的值，盘上的版本号要等下一次 `save_game()` 才更新。
- 写盘走 `.tmp` → 删旧 → rename 三步，中断不会毁掉已有存档。

---

## 3. 场景层：关卡生命周期

`LevelBase`（`scenes/levels/level_base.gd`，95 行）是所有关卡和测试房的
根脚本。它的 `_ready()` 固定做五件事，顺序不能换：

```
1. WorldTimeManager.reset_state()      清掉跨场景残留的 DreamGap
2. StoryFlagManager.clear_session()    清掉关卡局部 Flag
3. 解析 player_path
4. _apply_movement_mode()              把关卡声明的移动模式下发给玩家
5. _place_player()                     存档位置优先，否则用 SpawnPoint
   └─ 顺带 clear_input_locks()         防止输入锁跨场景残留
```

第 4 步是关键设计：**移动风格是关卡配置，不是玩家属性**。关卡在
`movement_mode` 导出属性里声明 `SIDE_SCROLL` 或 `DEPTH_2_5D`，LevelBase 在
放人之前告诉玩家。玩家脚本里没有、也不允许有 `if 场景名 == ...`。

第 5 步的存档恢复有个条件：只有当存档的 `current_scene` 正好指向本场景时
才用存档坐标，否则用关卡自己的出生点。这样从 A 关的存档进 B 关不会把人
放到 A 关的坐标上。

**子类必须调 `super._ready()`。** 目前 9 个脚本继承了 LevelBase：

- 正式关卡：`old_courtyard`、`main_house_interior`
- 测试房：`test_player_movement`、`test_dream_gap`、`test_interaction`、
  `test_memory_box`、`test_integration`、`whitebox_25d`、`bg_pacing_lab`

**两个旧关卡没有迁移**：`test_level.gd`、`dream_platforming_test.gd` 仍是
裸 `Node2D`，因此不会重置 DreamGap、不清 session flag、不清输入锁。
（见第 10 节技术债。）

### 关卡内的多区域流转

`old_courtyard` 演示了"一个场景内多屏探索"的做法，**不切场景**：

```
ExplorationArea（局部坐标 + 相机边界，默认一屏 1152px）
  ├─ SpawnPoint / SpawnPointRight
  └─ ExitTrigger（右缘）/ ExitTriggerLeft（左缘）
                    ↓ body_entered
AreaFlowController：锁输入(source="area_switch") → 淡黑 → 传送 →
                    移动相机 limit → 淡回 → 解锁
```

区域是 `AreaContainer` 的有序子节点，加一屏就是复制一个区域节点平移过去。
首区无左触发器、末区无右触发器，序列跑不出界；`is_switching` 挡重入。

---

## 4. 角色层：Player 与它的两个组件

`player.tscn` 是一个 `CharacterBody2D`，职责被切成三份：

| 节点 | 负责 |
| --- | --- |
| `Player`（player.gd, 267 行） | 移动、跳跃、重力、状态枚举、出生点、**输入锁** |
| `DreamGapAbility` | 只读 DreamGap 输入 + 转发 UI 信号，**不含计时逻辑** |
| `InteractionDetector` | 候选收集、目标选择、发提示、按 E 调 `interact()` |

### 脚下原点约定（改碰撞几何前必读）

玩家节点的原点是**脚底接触点**，不是身体中心。因此出生点 Marker、存档
坐标、传送坐标表达的都是"角色站的那一点"。横版模式下碰撞盒站在原点之上
（偏移 -24），2.5D 模式换成居中于原点的浅脚印（32×28），由
`_apply_mode_geometry()` 按模式互斥启用。

要取当前模式下的半高半宽用 `get_body_half_extents()`，**不要硬编码 24**。
这条约定是存档 version 2 迁移的成因。

### 输入锁是带来源的

```gdscript
player.lock_input(&"dialogue")     # 或 begin_interaction(&"...")
player.unlock_input(&"dialogue")   # 全部来源解除后才恢复控制
```

对话框、梦奁 UI、区域切换各持一把锁，互不干扰——梦奁关闭时只释放自己
那把 `"memory_box"`，对话持有的锁原样保留。**禁止**任何系统直接翻一个
`can_move` 布尔值。

---

## 5. 交互与叙事链路

```
Interactable (Area2D 基类)
   │  can_interact / get_interaction_prompt / interact
   │  基类已处理：one_shot 消耗、interact_priority、required_flag 门槛
   ↓ 子类只重写
   _on_interact(player) / _on_blocked_interact(player)
```

玩家侧只有一个 `InteractionDetector`（半径 56 的 Area2D）：进出注册候选，
按 `interact_priority` → 距离选目标，发 `prompt_changed` / `target_changed`，
E 键调 `interact()`。输入锁激活期间不触发。

**玩家不知道对象是门还是信物**——结果由交互物自己决定。目前的子类：

| 脚本 | 作用 | 位置 |
| --- | --- | --- |
| `text_interactable.gd` | 纯文本调查物，发 `text_requested` | `scripts/components/` |
| `flag_pickup.gd` | 拾取 → 写 StoryFlag | `scripts/components/` |
| `story_door.gd` | 门：Flag 门槛 + 信物门槛，可被 Director 直接开关 | `scripts/components/` |
| `memory_pickup.gd` | 拾取 / 推进梦奁信物 | `scripts/components/` |
| `save_point.gd` | 存档点 | `scripts/components/` |
| `test_interactable.gd` | 交互测试用计数器（仅测试） | `tests/helpers/` |

正式关卡用的交互物一律住在 `scripts/components/`；`tests/helpers/` 只剩
纯测试用的东西，测试场景反过来引用正式组件。

三种门槛写法，按"条件本身是什么"选：

- `required_flag` —— 条件是**剧情进度**（`Interactable` 基类内建）。
- `required_memory` —— 条件是**持有某件信物**（`StoryDoor` 重写
  `is_requirement_met()`）。不要用"拾取时顺手写个 Flag"代替，那会让同一件事
  变成两份各自持久化的状态。
- 两者都填 = 都要满足。

文本统一走底部 `dialogue_box.tscn`（分页、空格推进、显示期间锁玩家）。
**禁止各处自画浮动文字**。

### 叙事编排层：StoryDirector

交互物只回答"我怎么工作"，**"为什么现在发生这件事"归 StoryDirector**。
每个正式关卡挂一个自己的 Director，是关卡根的普通子节点，**不是 Autoload**。

```
Interactable / Cutscene / StoryNPC / DialogueBox
        │ signal
        ↓
   StoryDirector          ← 剧情依赖全部汇聚到这里
        │ 调用
        ↓
   写 Flag / 推信物 / 播演出 / NPC 入场 / 解锁门
```

| 基类 | 位置 | 职责 |
| --- | --- | --- |
| `StoryDirector` | `scripts/narrative/story_director.gd` | 关卡剧情编排 + 读档恢复契约 |
| `Cutscene` | `scripts/narrative/cutscene.gd` | 只管表现，演完发 `finished`；持 `cutscene` 输入锁 |
| `StoryNPC` | `scripts/narrative/story_npc.gd` | 进出场 + 对话；**不轮询剧情状态** |

**恢复时机（关键）**：Godot 的 `_ready()` 子先于父，Director 的 `_ready()` 跑时
玩家还没放置、`clear_session()` 还没执行。所以 Director 连
`LevelBase.level_started`（LevelBase `_ready()` 末尾发），在那之后才恢复。
子节点 `_ready()` 先跑，一定来得及连上——比 `call_deferred` 猜时序更确定。

**每个剧情节点写成两个函数**，这是"读档不重播"的唯一保证：

| 函数 | 何时跑 | 做什么 |
| --- | --- | --- |
| `_on_<事件>()` | 现场触发，一次性 | 幂等闸门 → 写 Flag / Memory → 触发表现 |
| `_apply_<节点>()` | 现场链路和恢复链路**都**调 | 幂等地把场景摆成终态，**不播任何表现** |

`_restore_story_state()` 就是把所有 `_apply_*` 跑一遍。演员层配套提供
"带表现 / 静默"成对方法：`enter_scene()` / `set_present()`、
`open()` / `set_unlocked()`。**不要为了恢复表现另造 Flag。**

范例：`scenes/levels/old_courtyard_story_director.gd`（药圃 + 侧窗 →
母亲幻觉 → 丫鬟入场 → 对话 → 侧窗解锁成主屋入口）。"读完文字后再做某事"
的 pending 标记统一收在 Director 里，关卡脚本不再持有剧情判断。

### Flag 命名与分层

| 前缀 | 层级 | 含义 | 例 |
| --- | --- | --- | --- |
| `story.*` | persistent | 跨关卡的世界真相 | `story.minghun_truth_known` |
| `<level_id>.*` | persistent | 本关剧情节点（过去式） | `old_courtyard.poison_discovered` |
| `<level_id>.now.*` | **session** | 本关运行时状态 | `old_courtyard.now.maid_present` |
| `test.*` | 任意 | 全部测试场景 | `test.integration.key_found` |

`.now.` 中缀是刻意的：session 会遮蔽同名 persistent 值，需要一个肉眼可见的
防撞标记。**优先不写 session flag**——本关运行时状态放 Director 的成员变量，
只有需要被其他节点读到时才升级成 flag。

边界：「玩家拥有什么」→ MemoryManager；「故事进行到哪里」→ StoryFlagManager。
同一份事实不要同时存在于两边。

---

## 6. 梦奁信物：三层分离

这是全项目最能体现"静态数据 / 运行时状态 / 存档"三分的系统：

```
静态定义        resources/memories/*.tres  (MemoryEntry + MemoryStage)
                id / title / icon / stages[]   ← 文案改多少次都不影响存档
     ↓ 启动时 MemoryManager._load_entries() 扫目录自动注册
运行时状态      MemoryManager._states
                { id: {unlocked, current_stage, unread_state} }
     ↓ get_save_data() 原样交给 SaveManager
存档            "memories" 字段，只有上面三个原始类型
```

- **`id` 一经入档不得改名**；title / description 随便改。
- 剧情推进同一件信物用 `advance_memory(id)` 换阶段，**不要新建重复道具**。
- 读档容错：未知 id 保留但不显示，越界 stage 自动 clamp，坏的 unread 值
  归零 —— 所以 `.tres` 增删阶段不会让旧档失效。
- UI 两块，都只监听信号、从不写状态：`memory_box_ui.tscn`（Tab 开关，
  开启时 `get_tree().paused = true` 并锁玩家；会尊重并恢复既有的 pause
  状态）、`memory_toast.tscn`（队列提示）。
- 注意：梦奁打开时整树暂停，`WorldTimeManager._process` 也随之冻结，
  DreamGap 的倒计时会停在原地、关闭后继续。这是有意的。

---

## 7. DreamGap：拉取式时间

**从未使用 `Engine.time_scale`**（全项目仅在两处注释里被提到，用于说明
"绝不使用"）。世界变慢的实现是局部时间倍率：

```
WorldTimeManager  READY → ACTIVE → COOLDOWN → READY
     持续 3s / 冷却 2s，都用真实 delta 在 _process 里算，无 Timer 节点
        │
        │  世界对象每帧自己来拿：
        └── platform/enemy: WorldTimeManager.get_scaled_delta(delta)
        └── 新对象: 挂 DreamAffectedComponent 子节点，拿组件的 scaled delta
```

**玩家永远用真实 delta**，从不调 `get_scaled_delta()`。这就是"玩家不被
减速影响"的全部机制——不存在补偿代码，也不要加。UI、存档、暂停同理：
它们不调这个函数，所以天然不受影响。

`DreamAffectedComponent` 是新对象的统一接入口，支持三种效果
（`TIME_SCALE` / `VISUAL_REVEAL` / `BOTH`）、每对象自定义倍率
（`custom_time_scale`，0 = 完全冻结）、以及自动切换父节点可见性。
旧的 `moving_platform.gd` / `test_enemy.gd` 是直连写法，保留不强迁。

表现层接法见 `slow_time_visual_test.gd`：纯 Signal 单向监听，
WorldTimeManager 不知道它存在。

---

## 8. 关键数据流

### 启动 → 新游戏

```
MainMenu ──"Start New Game"──▶ SaveSlotMenu(mode="new")
   └─ create_new_save(slot) → 写盘 + StoryFlagManager.reset()
                                   + MemoryManager.reset()
                                   + WorldTimeManager.reset_state()
   └─ change_scene_to_file(SaveManager.TEST_SCENE_PATH)
                              └─ 当前 = res://tests/test_integration.tscn ⚠
```

### 读档

```
SaveSlotMenu(mode="load") → load_game(slot)
   ├─ _read_validated：JSON → 校验 8 个必需字段 → 版本迁移
   ├─ StoryFlagManager.load_save_data(story_flags)
   ├─ MemoryManager.load_save_data(memories)
   └─ WorldTimeManager.reset_state()
   → change_scene_to_file(data["current_scene"])
      → LevelBase._ready() 发现 current_scene == 本场景 → 用存档坐标放人
```

### 拾取一件信物

```
玩家按 E → InteractionDetector.interact(player)
   → test_memory_pickup._on_interact()
      → MemoryManager.unlock_memory(id)
         ├─ signal memory_unlocked   → MemoryToast 弹「梦奁新增：…」
         └─ signal memory_state_changed → MemoryBoxUI 若开着则刷新格子
   → 拾取物隐藏 Visual，one_shot 消耗
（此时状态只在内存；下一次 save_game() 才落盘）
```

### 一次完整的 DreamGap

```
按 Shift → DreamGapAbility 检出上升沿 → WorldTimeManager.request_slow_time()
   ├─ world_time_scale = 0.25，state = ACTIVE
   ├─ signal slow_time_started → CanvasModulate 变蓝 / 各 DreamAffectedComponent
   └─ 平台与敌人下一帧拉到的 scaled delta 变成 1/4，玩家不变
3 秒后（或再按一次）→ _enter_cooldown() → 倍率回 1.0，state = COOLDOWN
2 秒后 → READY
```

---

## 9. 目录归位速查

```
scripts/autoload/   4 个全局管理器            ← 常驻，不持有节点
scripts/components/ 跨关卡复用的组件与基类     ← Interactable / DreamAffected /
                                                ExplorationArea / AreaFlowController
scripts/globals/    纯数据与枚举              ← MovementMode
scripts/memory/     Resource 定义             ← MemoryEntry / MemoryStage
scenes/player/      玩家及其组件
scenes/ui/          主菜单 / 存档槽 / 对话框 / 梦奁 / Toast
scenes/levels/      LevelBase + 正式关卡
scenes/components/  世界对象（平台 / 敌人）
resources/memories/ 信物静态数据 .tres（自动注册）
tests/              灰盒测试房 + helpers/（交互物参考实现）
```

**判断新文件放哪**：会被两个以上关卡用到 → `scripts/components/`；
只服务一个关卡 → 和关卡放一起；只服务测试 → `tests/`。

---

## 10. 现状缺口与技术债

按需要处理的紧迫程度排序。这些都是核对代码时发现的**事实**，不是猜测。

### 10.1 版本控制（已完成 2026-08-26）

项目已进入 Git 管理，baseline commit 记录了本次架构调整后的完整可运行状态。
远端：`PaprikaChen/22lotus_hackathon_demo`（**private**），默认分支 `main`。

`.gitignore` 排除：`.godot/` 引擎缓存、`/android/`、`录屏/`（42MB 屏幕录制
素材）、`.claude/settings.local.json`（个人权限设置）。入库 387 个文件、3.0MB，
其中 227 个是 `addons/godot_ai/` 第三方插件——它在 `project.godot` 里是启用
状态，不入库的话别人 clone 下来打不开工程。

`CLAUDE.md` 里"大改动前检查 git status"这条安全规则现在可以执行了。

### 10.2 新游戏入口（已修复 2026-08-26）

`SaveManager.NEW_GAME_SCENE_PATH` 现在指向
`res://scenes/levels/old_courtyard.tscn`，新建游戏直接进正式第一关。

同时修掉了一个连带的落点 bug：`create_new_save()` 会写死一份占位坐标，
而 `LevelBase._place_player()` 只要看到 `current_scene` 对得上就用存档坐标，
于是**新游戏永远用不到关卡自己的 SpawnPoint**。解法是新增存档字段
`use_level_spawn`（新档写 `true`，任何一次 `save_game()` 自动清成 `false`，
旧档缺字段默认 `false` 行为不变，不进 `REQUIRED_KEYS`、无需升版本）。
回归断言在 `tests/test_old_courtyard.tscn`。

### 10.3 两个旧关卡未迁移 LevelBase

`test_level.gd` 与 `dream_platforming_test.gd` 是裸 `Node2D`，不走
LevelBase 的进关重置，且现在没有任何地方引用，属于既没迁移也没删的中间态。
不阻塞正式剧情实现，可最后决定迁移还是删除。

### 10.4 正式交互物已提升（已完成 2026-08-26）

门、钥匙、存档点、信物拾取五个脚本已从 `tests/helpers/` 提升到
`scripts/components/`，并改名为 `StoryDoor` / `FlagPickup` / `SavePoint` /
`MemoryPickup`（信物门槛合并进 `StoryDoor`，不再有独立子类）。
`tests/helpers/` 只剩 `test_interactable.gd` 和 `dream_test_spinner.gd`
两个纯测试脚本。

### 10.5 测试信物混在正式信物目录

`resources/memories/` 下 8 个 `.tres` 里有 5 个是测试用
（`whitebox_25d_collectible_01/02`、`bg_pacing_token_01/02/03`），都会
注册进梦奁 UI。README 已注明来源与删除条件，正式发布前要清。

### 10.6 `play_time_seconds` 只有一个地方在累计

只有 `test_level.gd` 维护游玩时长。`test_save_point.gd` 存档时沿用
`current_save` 里的旧值，所以在正式关卡里存档，时长不会增长。

### 10.7 场景切换没有统一出口

8 处散落的 `change_scene_to_file()`。目前规模可控，但淡入淡出、存档写入、
跨场景状态清理各写各的。`AGENTS.md` 已把 SceneManager 列为"尚未实现"，
在有明确需求前不建议提前造。

### 10.8 两份文档已经漂移

**`README.md` 严重过时**——它停留在只有 2 个 Autoload 的阶段：没有
StoryFlagManager、MemoryManager、Interaction、Dialogue、LevelBase、
2.5D 模式、旧院关卡；Input Map 表缺 `interact` / `open_memory_box` /
`move_up` / `move_down`。建议削减为纯"上手与运行"指南，架构内容指向本文件。

**`AGENTS.md` 局部漂移**（整体仍准确，以下三处需修）：

- 第 0 节"尚未实现"里仍列着"对话系统、记忆收集系统"，但两者都已实现，
  且在同一节上文有详细描述——自相矛盾。
- 第 0 节 Autoload 清单漏了 `MemoryManager`。
- 第 10 节表格"新记忆收集物 = Interactable + StoryFlagManager 记录"是旧
  写法，实际应走 `MemoryManager.unlock_memory()`；表格也缺"信物门槛的门"
  这一行。
- 测试场景清单缺 `test_memory_box`、`test_old_courtyard`、`bg_pacing`。

---

## 11. 维护本文件

改动**架构**时同步本文件；改动**规则**时改 `AGENTS.md`。两者的分界是：
本文描述"是什么"，AGENTS.md 规定"不许怎样"。

具体触发条件：新增或删除 Autoload、改变存档格式版本、新增一层
（如真的引入 SceneManager）、改变 LevelBase 生命周期步骤、改变输入锁或
原点约定 —— 这五类改动必须回来更新对应章节，并更新文首的核对日期。
