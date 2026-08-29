# ARCHITECTURE.md — 《二十二莲境》架构说明

本文件描述项目**当前实际是怎么搭起来的**：有哪些层、谁拥有什么状态、
数据往哪个方向流、以及为什么这么分。核对时间 **2026-08-30**，依据是
仓库里全部 96 个 `.gd` 与 42 个 `.tscn`（不含 `addons/`）的真实内容，
不是设计意图。

与其他三份文档的分工：

| 文件 | 回答的问题 |
| --- | --- |
| `CLAUDE.md` | 项目是什么、目录约定、Agent 能独立决定什么 |
| `AGENTS.md` | 改代码时**不许**做什么（约束清单、复用指引） |
| **`ARCHITECTURE.md`（本文）** | 系统之间**如何咬合**、状态归谁、数据怎么流 |
| `README.md` | 上手与运行、已实现内容与亮点（2026-08-30 已重写） |
| `NARRATIVE_LAYER_DESIGN.md` | 叙事层怎么写（Director / Cutscene / Flag 模板） |

---

## 0. 一分钟概览

一个 Godot 4.4 的 2D 横版游戏，由六块拼起来：

1. **五个互不知道对方存在的全局系统**（存档 / 时间 / 剧情 Flag / 记忆信物 /
   CG 画廊），全是 Autoload。
2. **一条关卡生命周期**（`LevelBase`：重置 → 清 flag → 下发关卡配置 → 放人 →
   挂暂停菜单 → 发 `level_started`）。
3. **一套交互总线**（`Interactable` + 玩家身上唯一的 `InteractionDetector`）。
4. **一层叙事编排**（每关一个 `StoryDirector`，剧情因果全部汇聚在那里）。
5. **一套演出件**（黑边 / 淡入淡出 / 白幕文字 / 定格 CG / 失焦，只管画面）。
6. **两套集中配置的机关**（三重旋锁、十幕皮影），数值全在
   `scripts/globals/*_config.gd`。

一个容易误判的现状：**目前所有正式关卡都写着 `player_can_jump = false`**，
玩法是行走探索 + 调查 + 机关，不是平台跳跃。跳跃与 DreamGap 的代码都还在，
由关卡按需开启（见第 3 节的关卡配置下发）。

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
│   MemoryManager GalleryManager                               │
└─────────────────────────────────────────────────────────────┘
        ▲ 调用 API                    │ 发 Signal
        │                             ▼
┌─────────────────────────────────────────────────────────────┐
│ 场景层 LevelBase 子类（关卡 / 测试房，一次一个）             │
│   courtyard_01..04   courtyard_03_incense_memory             │
│   interior_01   interior_02   old_courtyard   tests/*        │
│   持有：Player、FollowCamera2D、Backdrop、UI、Props          │
└─────────────────────────────────────────────────────────────┘
        │ 每关一个                      ▲ Signal
        ▼                               │
┌─────────────────────────────────────────────────────────────┐
│ 叙事编排层 StoryDirector 子类（关卡根的普通子节点）          │
│   <level>_story_director.gd  ← 剧情因果只写在这里            │
└─────────────────────────────────────────────────────────────┘
        │ 组合 / 调用                   ▲ Signal
        ▼                               │
┌─────────────────────────────────────────────────────────────┐
│ 组件层（挂在节点上的可复用零件）                             │
│   Player + DreamGapAbility + InteractionDetector             │
│   Interactable 子类   DreamAffectedComponent                 │
│   Backdrop / FollowCamera2D / ArchBridge / ColorZoneX        │
│   ExplorationArea     MovingPlatform                         │
└─────────────────────────────────────────────────────────────┘
        │ 只被 Director 驱动            ▲ signal finished
        ▼                               │
┌─────────────────────────────────────────────────────────────┐
│ 演出件层（CanvasLayer，只管画面）                            │
│   FrameBars(50)  DialogueBox(60)  RotaryLockUI(70)           │
│   NarrationOverlay(80)  CGSequence  FocusBlur                │
│   ScreenFade(95)                                             │
└─────────────────────────────────────────────────────────────┘
```

**依赖方向是严格单向的**：下面每一层都可以调 Autoload，Autoload 绝不反向
持有节点引用；演出件与组件也不许反过来读剧情状态。唯一的反向通道是 Signal。这条规则是整个架构能保持简单的
根本原因——任何一个关卡被删掉，全局层不会有一行代码需要改。

---

## 2. 全局层：五个 Autoload

注册顺序（`project.godot`）：`SaveManager` → `WorldTimeManager` →
`StoryFlagManager` → `_mcp_game_helper`（插件） → `MemoryManager` →
`GalleryManager` → `MCPRuntimeServer`（插件）。两个插件 Autoload 属于编辑器
MCP 基础设施，不参与游戏逻辑。

| Autoload | 拥有 | **不**拥有 | 落盘位置 |
| --- | --- | --- | --- |
| `SaveManager` | 全部 `user://` 文件 I/O、槽位、版本迁移、当前存档内存副本、跨槽全局存储 | 任何游戏逻辑 | 整个文件 |
| `WorldTimeManager` | DreamGap 状态机、`world_time_scale` | 表现、玩家、对象列表 | 无（临时状态不入档） |
| `StoryFlagManager` | 剧情 Flag（persistent / session 两层） | 文案、条件判断 | 槽位字段 `story_flags` |
| `MemoryManager` | 梦奁信物运行时状态 + 静态资源注册表 | 文案（在 `.tres`）、UI | 槽位字段 `memories` |
| `GalleryManager` | 画廊 CG 解锁 / NEW 角标 + 静态资源注册表 | 文案与图（在 `.tres`）、UI、剧情判断 | **全局** `user://gallery.json` |

### 为什么画廊不进存档槽

画廊入口在**主菜单**，那时没有任何槽位被载入——CG 状态若在槽里，从主菜单
进画廊只能是空的。所以 CG 收集是**跨三个槽共享**的账号级数据，存在独立的
全局文件里：不进 `REQUIRED_KEYS`、不参与 `save_version` 迁移、删存档不丢收集。

`GalleryManager` 自己不碰文件（项目硬规则），走 `SaveManager` 的一组通用
全局存储 API：

```gdscript
SaveManager.read_global("gallery")        # → Dictionary，坏文件返回 {}
SaveManager.write_global("gallery", data) # 与槽位共用 .tmp → 替换的安全写入
```

**谁解锁 CG：StoryDirector。** CG 解锁是剧情后果，和「写 Flag / 推进信物」
同一类，写在 Director 的 `_on_*` 里。不要让 Cutscene 或 UI 自己解锁。

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

`LevelBase`（`scenes/levels/level_base.gd`，127 行）是所有关卡和测试房的
根脚本。它的 `_ready()` 固定做这几件事，顺序不能换：

```
1. WorldTimeManager.reset_state()      清掉跨场景残留的 DreamGap
2. StoryFlagManager.clear_session()    清掉关卡局部 Flag
3. 解析 player_path
4. _apply_movement_mode()              把关卡声明的移动模式下发给玩家
5. _apply_player_abilities()           把 player_can_jump 下发给玩家
6. _place_player()                     存档位置优先，否则用 SpawnPoint
   └─ 顺带 clear_input_locks()         防止输入锁跨场景残留
7. _install_pause_menu()               仅当自己就是 current_scene 时才挂
8. on_level_started() → level_started.emit()
```

第 4、5 步是关键设计：**移动风格与能力开关都是关卡配置，不是玩家属性**。
关卡在 `movement_mode` 里声明 `SIDE_SCROLL` 或 `DEPTH_2_5D`，在
`player_can_jump` 里声明本关能不能跳，LevelBase 在放人之前告诉玩家。
玩家脚本里没有、也不允许有 `if 场景名 == ...`。目前所有正式关卡
`player_can_jump = false`。

第 7 步的条件判断是刻意的：测试常把关卡当子场景实例化，那里不应额外生成
全屏 UI 或接管 Esc，所以只有作为 `current_scene` 运行的关卡才挂暂停菜单。

第 5 步的存档恢复有个条件：只有当存档的 `current_scene` 正好指向本场景时
才用存档坐标，否则用关卡自己的出生点。这样从 A 关的存档进 B 关不会把人
放到 A 关的坐标上。

**子类必须调 `super._ready()`。** 继承 LevelBase 的脚本：

- 正式关卡：`courtyard_level`（`courtyard_01` / `02` / `03` / `04` 共用一份）、
  `courtyard_03_incense_memory_level`、`interior_01`、`interior_02`、
  `old_courtyard`、`main_house_interior`
- 测试房：`test_player_movement`、`test_player_visual`、`test_dream_gap`、
  `test_interaction`、`test_memory_box`、`test_integration`、`test_courtyard_01`、
  `test_interior_02`、`whitebox_25d`、`bg_pacing_lab`

**关卡脚本共用的判据**：关卡侧机制一样、只有背景 / Props / Director 不同的关，
共用一个关卡脚本（四个 courtyard 就是这样，见 `courtyard_level.gd`）；
机制本身不同的关（`interior_02` 的换幕流程）才写自己的脚本。

**两个旧关卡没有迁移**：`test_level.gd`、`dream_platforming_test.gd` 仍是
裸 `Node2D`，因此不会重置 DreamGap、不清 session flag、不清输入锁。
（见第 10 节技术债。）

### 关卡内的横向推进：两种做法

**当前正式关卡（courtyard_01..04 / interior_01）用的是长卷 + 相机闸门**，
一个场景就是一整条横向长卷，不分屏、不传送：

```
Backdrop（@tool）        按「世界高度」反推 scale，长卷有多宽就多宽
   │ texture.get_size() * scale
   ▼
FollowCamera2D          bounds_source_path 读上面的尺寸当关卡边界
   ├─ left_gate_x / right_gate_x      临时把可视范围掐在某个 x（剧情闸门）
   ├─ arm_left_gate_latch(x)          「待落闸门」：玩家走过去之后才落
   └─ slide_left_gate_open(duration)  解锁时把闸门滑开（有过渡，不是瞬移）
```

为什么背景要声明世界高度而不是写死 scale：Godot 的导入器会把超大图按比例
缩掉以适应上限，所以「贴图像素 → 世界像素」的倍率取决于导入结果。写死
scale 会在换图或改导入设置时**静默错位**。

配套的挡路手段有三类，各有分工：`PassageGate`（交互一次清掉的障碍）、
`BacktrackTrap`（走进去就回不了头，往西越界就黑幕送回）、
`StoryDoor`（Flag / 信物门槛）。相机闸门永远由 Director 控制——
"镜头能看多远"是关卡编排的事，组件不自己决定。

**另一种做法：一个场景内多屏流转（`old_courtyard`，早期实现，仍可参考）**，
同样不切场景：

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

| 脚本（均在 `scripts/components/`） | 作用 |
| --- | --- |
| `text_interactable.gd` | 纯文本调查物，发 `text_requested` |
| `animated_text_interactable.gd` | 上面那个 + 交互时的局部表现（摇摆 / 附图），仍不碰剧情 |
| `choice_text_interactable.gd` | 多选调查点：放文字 → 让玩家选 → 放对应文字，纯阅读分支 |
| `passage_gate.gd` | 挡路障碍（杂草 / 瓦砾）：交互一次清掉，发 `cleared` |
| `sequence_puzzle.gd` + `_item.gd` | 「按正确顺序点物品」的裁判；答案 = Inspector 里的数组顺序 |
| `flag_pickup.gd` | 拾取 → 写 StoryFlag |
| `memory_pickup.gd` | 拾取 / 推进梦奁信物 |
| `story_door.gd` | 门：Flag 门槛 + 信物门槛，可被 Director 直接开关 |
| `level_exit.gd` | 通往下一关的出口（门槛同上；切场景由关卡做） |
| `save_point.gd` | 存档点 |
| `backtrack_trap.gd` | 返回封锁 + 黑幕重置（不是 Interactable，靠世界 x 触发） |
| `follow_camera.gd` | 横版跟随相机 + 左右闸门，靠 Camera2D 内建 limit 实现"贴边停住" |
| `tests/helpers/test_interactable.gd` | 交互测试用计数器（仅测试） |

除交互物之外，组件层还有一批**纯表现件**，它们只改自己的变换或材质，
不读输入、不碰剧情、不碰碰撞：`floating_visual`（上下漂浮）、
`brightness_pulse`（双正弦亮度脉冲）、`eye_follow_visual`（眼神跟随）、
`flower_rig`（Skeleton2D 花枝摇曳）、`shadow_puppet_actor`（皮影玩家表现）、
`color_zone_x`（按世界 X 分段去色 / 上色）、`arch_bridge`（@tool 拱桥地形，
运行时按跨度与拱高生成弧面碰撞）。

正式关卡用的交互物一律住在 `scripts/components/`；`tests/helpers/` 只剩
纯测试用的东西，测试场景反过来引用正式组件。

三种门槛写法，按"条件本身是什么"选：

- `required_flag` —— 条件是**剧情进度**（`Interactable` 基类内建）。
- `required_memory` —— 条件是**持有某件信物**（`StoryDoor` 重写
  `is_requirement_met()`）。不要用"拾取时顺手写个 Flag"代替，那会让同一件事
  变成两份各自持久化的状态。
- 两者都填 = 都要满足。

文本统一走底部 `dialogue_box.tscn`（分页、空格推进、显示期间锁玩家，
有名字的说话人走带立绘的对话框版式，旁白走下边框字幕版式；还负责
`choice_requested` 的选项）。**禁止各处自画浮动文字**。组件只发信号，
关卡脚本把信号接到那唯一一个对话框上。

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

### 演出件：只管画面

叙事关卡的"演出"被切成一组各自独立的 `CanvasLayer`，**全部只管画面**：
不锁玩家、不写 Flag、不切场景、不判断剧情。编排权在 Director。

| 演出件 | 层号 | 画什么 | 用在哪 |
| --- | --- | --- | --- |
| `FrameBars`（@tool） | 50 | 影院黑边。设计分辨率高度从 648 提到 828，多出的上下各 90px 填黑；游戏画面一寸没动 | 全部叙事关卡 |
| `DialogueBox` | 60 | 底部字幕 / 立绘对话框 / 选项 | 全部 |
| `RotaryLockUI` | 70 | 三重旋锁界面 + 判定 | courtyard_01 |
| `NarrationOverlay` | 80 | 白幕居中逐句文字 | 香炉记忆、interior_01 |
| `CGSequence` | 默认(1) | 定格 CG + 下方字幕，空格推进；靠 ScreenFade 先遮黑再淡回来露出 | interior_01 |
| `FocusBlur` | 49 | 全屏短暂失焦（shader 模糊）；刻意压在黑边之下，只糊游戏画面 | courtyard_04、interior_01 |
| `ScreenFade` | 95 | 淡入淡出（黑幕 / 白幕），必须能盖住上面所有 | 全部 |

层号顺序是硬约定：切场景的幕布永远要能盖住白幕文字，白幕文字要能盖住
对话框和锁界面。**新增演出件时先想清楚它该压在谁上面。**

为什么不让 `NarrationOverlay` 复用 `DialogueBox`：一个是「白底、居中、
一句一换」的记忆关演出，一个是「下边框字幕 + 立绘」的正常关卡对话。
两者是并列的两种表现件，不该互相迁就。`CGSequence` 同理——那是图为主。

### 机关的数值集中化

两套多组件协作的机关，全部数值收在一个 `RefCounted` 常量类里，
场景与各组件都从那里读，**禁止在别处再抄一份数字**：

| 配置类 | 覆盖 | 谁来执行 |
| --- | --- | --- |
| `InnerGateLockConfig` | courtyard_01 尾部三重旋锁：触发区间、黑幕重置坐标、档位手感、谜底顺序、解锁 Flag | `backtrack_trap.gd` / `rotary_lock_ui.gd` / `rotary_lock_ring.gd` / `courtyard_01_story_director.gd` |
| `ShadowPlayConfig` | interior_02 十幕皮影：每幕贴图路径、舞台尺寸、出口位置、逐幕参数 | `interior_02.gd` |

`ShadowPlayConfig` 刻意用 `String` 路径而不是 `preload`：十幕贴图不该在进关时
同时常驻。`interior_02.gd` 换幕时先清空所有旧 `Texture` 引用，再用
`CACHE_MODE_IGNORE` 加载下一幕。

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

### 启动 → 新游戏（含前情提要）

```
MainMenu ─[新游戏]→ SaveSlotMenu(new) → create_new_save()
                                          │  current_scene 写的是关卡
                                          ▼
                                    PrologueScreen  ← 黑屏+居中文字，Space 逐段
                                          │
                                          ▼
                                     courtyard_01
MainMenu ─[读取存档]→ SaveSlotMenu(load) → load_game() → 存档里的 current_scene
MainMenu ─[画廊]────→ GalleryScreen（不需要任何槽位）
```

### 当前关卡链

```
courtyard_01 ─LevelExit→ courtyard_02 ─LevelExit→ courtyard_03 ─LevelExit→ courtyard_04
                                            │                                  │
                                  (灯笼区触发)│                          (破窗二选一)│
                                            ▼                                  ▼
                            courtyard_03_incense_memory            interior_01 ─→ interior_02
                              └─ 做完写 Flag + 挂起返回对白 ─→ 白幕回 courtyard_03
                                 （落回 RETURN_POSITION_X，右侧闸门撤除）
```

两个值得注意的编排细节：

- **子关卡往返靠「挂起标记 + Flag」，不靠特殊存档字段。**
  香炉记忆做完时写 `courtyard_03.incense_memory_finished` 和
  `...return_pending`，回到主庭院的 Director 看到 pending 就播那句返回对白
  并清掉标记。落点坐标写在 Director 的常量里，因为回忆是在灯笼区触发的，
  回来后要站到能继续往前的位置，不能沿用进入时的存档坐标。
- **`interior_02` 是唯一一个自己写关卡脚本的关**：十幕换幕要逐幕加载 / 释放
  贴图、换玩家表现件、走黑幕过渡，这些是**关卡机制**而非剧情，所以在关卡
  脚本里而不是 Director 里。

**「前情提要只在新游戏播一次」是流程保证的，不靠 Flag。** 读档分支直接跳
`current_scene`，而新档里写的是关卡而不是前情提要——所以在前情提要期间退出
再读档会直接进关卡。

### 旧的启动 → 新游戏

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
scripts/autoload/   5 个全局管理器            ← 常驻，不持有节点
scripts/components/ 跨关卡复用的组件与基类     ← Interactable 子类 / DreamAffected /
                                                Backdrop / FollowCamera2D / 纯表现件
scripts/narrative/  叙事层基类                ← StoryDirector / Cutscene / StoryNPC
scripts/ui/         UI 与演出件脚本            ← FrameBars / ScreenFade /
                                                NarrationOverlay / CGSequence /
                                                FocusBlur / RotaryLockUI / Gallery
scripts/globals/    纯数据与枚举              ← MovementMode / InnerGateLockConfig /
                                                ShadowPlayConfig
scripts/memory/     Resource 定义             ← MemoryEntry / MemoryStage
scripts/gallery/    Resource 定义             ← CGEntry
scenes/player/      玩家及其组件
scenes/ui/          主菜单 / 存档槽 / 前情提要 / 暂停 / 对话框 / 梦奁 / Toast /
                    画廊 / 旋锁 / 黑边 / 淡入淡出 / 白幕 / 失焦
scenes/levels/      LevelBase + 正式关卡 + 每关一个 *_story_director.gd
scenes/components/  世界对象（平台 / 敌人）
resources/memories/ 信物静态数据 .tres（自动注册）
resources/cg/       画廊 CG 静态数据 .tres（自动注册）
shaders/            effects/（饱和度着色、发光描边）、ui/（失焦模糊）
tests/              灰盒测试房 + helpers/（交互物参考实现）
```

**判断新文件放哪**：会被两个以上关卡用到 → `scripts/components/`；
只服务一个关卡 → 和关卡放一起；只服务测试 → `tests/`。
**是画面还是逻辑**：只画东西的 `CanvasLayer` → `scripts/ui/`；
挂在世界节点上的零件 → `scripts/components/`；
只是一堆常量 → `scripts/globals/`。

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
`res://scenes/levels/courtyard_01.tscn`，新建游戏先播 `PROLOGUE_SCENE_PATH`
（前情提要）再进正式第一关。

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

十余处散落的 `change_scene_to_file()`（关卡出口、子关卡往返、主菜单、画廊）。
目前规模仍可控，但淡入淡出、存档写入、跨场景状态清理各写各的。
`AGENTS.md` 已把 SceneManager 列为"尚未实现"，在有明确需求前不建议提前造。
**如果子关卡往返再多两处，就该造了**——这是最接近临界点的一项技术债。

### 10.8 文档漂移（本轮已处理）

`README.md` 已于 2026-08-30 重写：现在是"上手 + 已实现 + 核心玩法 + 亮点"，
架构内容指向本文件。本文件同日核对到 courtyard_01..04 / interior_01..02。
`AGENTS.md` 的 §0 快照同步更新。

后续维护纪律不变：**新增关卡不需要动本文件**（那只是 §8 的关卡链），
只有第 11 节列出的五类改动才必须回来改架构文档。

### 10.9 音频接入尚浅

`assets/audio/` 目录已建，旋锁档位 / 开锁是目前唯一接上的 SFX 事件
（`rotary_lock_ui.gd` 里两个独立的 `AudioStreamPlayer`，无素材时安全静默）。
BGM、环境音、脚步都还没有接入点，也还没有音频总线规划。

### 10.10 关卡侧脚本开始重复

`courtyard_level.gd` 已被四关共用（正确做法），但 `interior_01.gd` 的
"把 `text_requested` / `choice_requested` / `text_dismiss_requested` 接到共用
对话框"这段循环和 `courtyard_level.gd` 里的是同一份逻辑。
再出现第三份就应该抽成一个"叙事关卡"基类或一个挂在关卡上的组件，
而不是继续复制。

---

## 11. 维护本文件

改动**架构**时同步本文件；改动**规则**时改 `AGENTS.md`。两者的分界是：
本文描述"是什么"，AGENTS.md 规定"不许怎样"。

具体触发条件：新增或删除 Autoload、改变存档格式版本、新增一层
（如真的引入 SceneManager）、改变 LevelBase 生命周期步骤、改变输入锁或
原点约定 —— 这五类改动必须回来更新对应章节，并更新文首的核对日期。
