# NARRATIVE_LAYER_DESIGN.md — 叙事编排层设计

依据 `NARRATIVE_ARCHITECTURE_IMPLEMENTATION_PLAN.md` 的要求，针对本仓库
**当前真实代码**（核对于 2026-08-26）做的落地设计。

> **状态：已实施（2026-08-26）。** 六步全部落地并通过回归。
> Git 初始化（原计划 13.1 / 完成标准第 1 条）按指示跳过，其余 P0/P1 全部完成。
> 架构结论已并入 `ARCHITECTURE.md` 第 5 节与 `AGENTS.md` 第 5.5 节；
> 本文件保留为**决策记录**（为什么这样设计、代价是什么），实施细节以那两份为准。

**本轮范围**：设计 + 施工方案。Git 初始化（原计划 13.1 / 完成标准第 1 条）
按你的指示跳过，其余 P0/P1 全部覆盖。

**实施基调**（原计划 §20）：这不是重写。全部改动集中在**新增文件**上，
对 `SaveManager` / `MemoryManager` / `WorldTimeManager` / `Player` /
`InteractionDetector` 的改动合计 **6 行**（只有一处，见 §5.2），
`LevelBase` **一行不改**。

---

## 1. 核心决策一览

| # | 决策点 | 选择 | 理由 | 代价 |
| --- | --- | --- | --- | --- |
| 1 | Director 是否要基类 | **要，但只有约 60 行** | §16 的"读档恢复"是每个 Director 都必须履行的契约，且存在一个真实的时序陷阱（§3.2）。让每个 Director 各自重新踩一遍不划算 | 一个薄基类 |
| 2 | 恢复时机怎么定 | **连 `LevelBase.level_started` 信号** | 已有的现成缝，不用 `call_deferred` 猜时序，`LevelBase` 零改动 | 无 |
| 3 | 剧情节点怎么写 | **`_on_*` / `_apply_*` 双函数**（§4） | 唯一能同时满足"现场播一次"和"读档不重播"的写法，且不需要额外 Flag | 每个节点多一个短函数 |
| 4 | 关卡运行时状态存哪 | **Director 的成员变量**，只有需要被别的节点读到时才写 session flag | 避免 Flag 泛滥 | 无 |
| 5 | 信物门的门 | **合并进 `StoryDoor`**，不留独立子类 | 门槛只有 6 行，独立子类是无谓层级 | 无 |
| 6 | 新游戏出生点 | **加 `use_level_spawn` 存档字段** | 现有 `create_new_save` 写死坐标，会盖掉关卡自己的 SpawnPoint（§5.2 有实证） | SaveManager +4 行、LevelBase +1 行 |
| 7 | Cutscene 的 await | **子类演完自己调 `finish()`**，基类不 `await` | 避免 `REDUNDANT_AWAIT` 与协程语义坑 | 无 |

原计划明令禁止的东西一个都没引入：无 EventBus、无 Quest System、
无 Narrative Graph、无 Story DSL、无状态机框架、Director 不是 Autoload。

---

## 2. 分层落位

叙事层插在**场景层和组件层之间**，不碰全局层：

```
全局层 Autoload      SaveManager  WorldTimeManager  StoryFlagManager  MemoryManager
                          ▲ 只被调用，从不持有节点
                          │
场景层               LevelBase 子类（生命周期：DreamGap reset / session reset /
                                     MovementMode / 出生位置 / 输入锁清理）
                          │ level_started
                          ▼
【新】叙事编排层      StoryDirector   ← 本轮新增，每关一个，普通节点
                          │ 调用                    ▲ Signal
                          ▼                         │
组件层（演员）        Interactable   Cutscene   StoryNPC   StoryDoor   DialogueBox
                     「我怎么工作」               ——从不决定「为什么现在发生」
```

关卡场景结构（`old_courtyard.tscn` 只需要**加两个节点**，现有结构不动）：

```
OldCourtyard (LevelBase)
├── AreaContainer/          现有，三个 ExplorationArea
├── Player                  现有
├── Camera2D                现有
├── AreaFlowController      现有
├── DialogueBox             现有
├── UI                      现有
├── Cutscenes               【新】演出容器
│   └── MotherMemoryCutscene
├── NPCs                    【新】演员容器
│   └── Maid
└── StoryDirector           【新】old_courtyard_story_director.gd
```

---

## 3. StoryDirector 基类

`scripts/narrative/story_director.gd`

### 3.1 接口

```gdscript
class_name StoryDirector
extends Node
## 关卡剧情编排层：只回答“什么时候发生什么”，不实现任何具体行为。
##
## 子类实现三个钩子，顺序固定：
##   _connect_actors()      连信号。此时禁止读剧情状态（见 3.2 时序）。
##   _restore_story_state() 幂等：按现有 Flag / Memory 把场景摆成应有的终态。
##   _on_story_ready()      恢复完成后的一次性开场（可选）。

## 宿主关卡。默认取父节点——Director 必须是关卡根的直接子节点。
@export var level_path: NodePath = ^".."

var _level: LevelBase = null


func _ready() -> void:
	_level = get_node_or_null(level_path) as LevelBase
	_connect_actors()
	if _level != null:
		# 一次性：关卡生命周期跑完后才恢复剧情状态。
		_level.level_started.connect(_on_level_started, CONNECT_ONE_SHOT)
	else:
		# 非 LevelBase 宿主（临时测试壳）退化为延迟一帧。
		push_warning("StoryDirector: 宿主不是 LevelBase，退化为 call_deferred 恢复。")
		_on_level_started.call_deferred()


func _on_level_started() -> void:
	_restore_story_state()
	_on_story_ready()


# --- 子类实现 ---------------------------------------------------------------

func _connect_actors() -> void:
	pass


func _restore_story_state() -> void:
	pass


func _on_story_ready() -> void:
	pass
```

### 3.2 为什么必须挂 `level_started`（一个真实陷阱）

Godot 的 `_ready()` 是**子节点先于父节点**。StoryDirector 是关卡根的子节点，
所以 `StoryDirector._ready()` 跑的时候：

- 玩家**还没**被 `LevelBase._place_player()` 放置；
- `StoryFlagManager.clear_session()` **还没**执行 —— 此刻读到的 session flag
  是上一关的残留，而且马上会被清掉；
- `WorldTimeManager.reset_state()` 还没执行；
- MovementMode 还没下发。

在 `_ready()` 里直接恢复剧情状态会静默读到错误数据。项目里
`AreaFlowController` 已经踩过同一个坑，它的解法是 `call_deferred`
（`area_flow_controller.gd:76`）。

`LevelBase` 在 `_ready()` 末尾发 `level_started`，而子节点的 `_ready()` 先跑，
**因此 Director 一定来得及连上这个信号**。这比 `call_deferred` 更确定，
且不需要改 `LevelBase` 一个字。

---

## 4. 剧情节点的写法：`_on_*` / `_apply_*` 双函数

这是满足原计划 §16（读档恢复且不重播）的核心约定。

> **规则：场景的"终态"只由 `_apply_*` 函数设置。现场链路和恢复链路都调它们。**

- `_on_<事件>()` —— 事件入口。幂等闸门 → 写 Flag / Memory → **触发表现**。
- `_apply_<节点>()` —— 纯粹读当前状态，把场景对象摆成终态。**无表现、可重复调用。**
- `_restore_story_state()` —— 把所有 `_apply_*` 按依赖顺序跑一遍。

```gdscript
# --- 现场链路：一次性，带表现 ---

func _on_herb_bed_examined(_player: Node) -> void:
	if StoryFlagManager.has_flag(FLAG_POISON_FOUND):
		return                                    # 幂等闸门
	StoryFlagManager.set_flag(FLAG_POISON_FOUND)
	_mother_cutscene.play()                       # 表现交给演员


func _on_mother_cutscene_finished() -> void:
	StoryFlagManager.set_flag(FLAG_MOTHER_MEMORY_SEEN)
	MemoryManager.advance_memory(&"mountain_bird_hairpin")
	_maid.enter_scene()                           # 带入场动画


func _on_maid_dialogue_finished() -> void:
	StoryFlagManager.set_flag(FLAG_MAID_TALKED)
	_apply_side_window_state()                    # 复用终态函数


# --- 恢复链路：幂等，无表现 ---

func _restore_story_state() -> void:
	_apply_maid_state()
	_apply_side_window_state()


func _apply_maid_state() -> void:
	if StoryFlagManager.has_flag(FLAG_MAID_TALKED):
		_maid.set_present(false)                  # 谈完了，人已离场
	else:
		_maid.set_present(StoryFlagManager.has_flag(FLAG_MOTHER_MEMORY_SEEN))


func _apply_side_window_state() -> void:
	_side_window.set_unlocked(StoryFlagManager.has_flag(FLAG_MAID_TALKED))
```

注意 `set_present()` 与 `enter_scene()` 的分工：前者是后者的**静默版**。
每个演员都要提供这一对，这样 Director 不需要为了"恢复表现"去造重复 Flag
（原计划 §16 最后一句的要求）。

---

## 5. 演员契约

### 5.1 Cutscene 基类 — `scripts/narrative/cutscene.gd`

```gdscript
class_name Cutscene
extends Node
## 演出单元：只管相机 / 动画 / 音频 / 淡入淡出 / 输入锁。
## 演完发 finished，剧情后果一律由 StoryDirector 决定——
## 这里禁止写 StoryFlag、推进 Memory、解锁门、决定下一段剧情、生成 NPC。

signal finished

const LOCK_SOURCE := &"cutscene"      # 只释放自己这把（原计划 §9）

@export var player_path: NodePath
@export var lock_player: bool = true

var _playing: bool = false


func play() -> void:
	if _playing:
		return
	_playing = true
	if lock_player:
		_lock()
	_perform()            # 子类演完后自己调 finish()


func skip() -> void:
	if _playing:
		finish()


func is_playing() -> bool:
	return _playing


func finish() -> void:
	if not _playing:
		return
	_playing = false
	if lock_player:
		_unlock()
	finished.emit()


## 子类实现：相机推移、AnimationPlayer、淡入淡出、音频。完成后调 finish()。
func _perform() -> void:
	finish()
```

`cutscene` 锁与 `dialogue_box` / `memory_box` / `area_switch` 四把锁并存，
互不误放——这正是 Player 现有 source-based lock 的设计意图。

### 5.2 StoryNPC 基类 — `scripts/narrative/story_npc.gd`

```gdscript
class_name StoryNPC
extends Node2D
## 剧情 NPC：只负责“我怎么进场、怎么说话”，绝不轮询剧情状态。
## 禁止在 _process 里查 StoryFlagManager 决定自己出不出现（原计划 §7）。

signal entered
signal left
signal dialogue_finished

@export var dialogue_box_path: NodePath
@export var speaker_name: String = ""
@export_multiline var lines: String = ""

var _present: bool = false


func enter_scene() -> void      ## 带表现地入场（走位 / 淡入 / 动画）
func leave_scene() -> void      ## 带表现地离场
func set_present(present: bool) -> void   ## 静默设终态，读档恢复专用
func is_present() -> bool
func start_dialogue() -> void   ## 走 DialogueBox，closed → dialogue_finished
```

`start_dialogue()` 内部连 `DialogueBox.closed` 并转发成 `dialogue_finished`。
DialogueBox 本身只管显示 / 分页 / 推进 / 关闭 / 玩家锁，**不承担导演职责**
（原计划 §4）——它现在就是这样，不需要改。

### 5.3 Dialogue 现状：不改，但要搬走两处 pending

`old_courtyard.gd` 与 `main_house_interior.gd` 目前各有一个
`_pending_enter` / `_pending_exit` + `dialogue.closed` 的写法。原计划 §8
点名这就是要迁走的模式。它们迁进 Director 后，关卡脚本只剩：相机跟随、
提示 Label、把 `text_requested` 接到 DialogueBox —— 即纯粹的关卡 UI 布线。

---

## 6. Flag 命名与分层

### 6.1 方案

| 前缀 | 层级 | 含义 | 例 |
| --- | --- | --- | --- |
| `story.*` | persistent | 跨关卡的世界真相 | `story.minghun_truth_known` |
| `<level_id>.*` | persistent | 本关剧情节点（过去式） | `old_courtyard.poison_discovered` |
| `<level_id>.now.*` | **session** | 本关运行时状态 | `old_courtyard.now.maid_present` |
| `test.*` | 任意 | 全部测试场景 | `test.integration.key_found` |

`.now.` 这个中缀是刻意的：`StoryFlagManager` 里 session 会**遮蔽**同名的
persistent 值，一个肉眼可见的标记能防止两层撞名，也方便全局搜索。

**但优先不写 session flag**：本关运行时状态放 Director 的成员变量即可，
只有需要被**其他节点**读到时才升级成 session flag。

### 6.2 边界判定（原计划 §5）

- 「玩家拥有什么 / 信物什么状态」→ **MemoryManager**，不要再配一个
  `got_xxx` Flag。
- 「故事进行到哪里」→ **StoryFlagManager**。

例：是否持有山鸟簪 = `MemoryManager.has_memory(&"mountain_bird_hairpin")`；
是否已经因它触发过母亲幻觉 = `old_courtyard.mother_memory_seen`。

### 6.3 P0 13.3 迁移清单（测试 Flag 撤出正式命名空间）

| 现名 | 改为 | 出现处 |
| --- | --- | --- |
| `old_courtyard.stone_checked` | `test.integration.stone_checked` | `tests/test_integration.tscn:107`、`tests/test_integration.gd:125` |
| `test_integration.key_found` | `test.integration.key_found` | `tests/test_integration.tscn`、`tests/test_integration.gd` |
| `chapter_01.test_key` | `test.interaction.locked_door_key` | `tests/test_interaction.tscn:80`、`tests/test_interaction.gd:98,103` |
| `chapter_01.test_flag` | `test.save_load.round_trip_flag` | `tests/test_save_load.gd:53,62,84` |

`old_courtyard.stone_checked` 尤其该改：正式的旧院里**根本没有"石头"这个
交互物**（现有的是院门 / 刻痕 / 布条 / 正门 / 木马 / 药圃 / 侧窗），测试场景
凭空占用了正式章节的命名空间，而且写的是持久 Flag，会进真实存档。

这些 Flag 都没有真实存档依赖（都是测试产生的），可以直接改名。

---

## 7. P0：正式游戏入口（13.2）

### 7.1 改什么

`scripts/autoload/save_manager.gd:12`

```gdscript
# 现在
const TEST_SCENE_PATH: String = "res://tests/test_integration.tscn"
# 改为
const NEW_GAME_SCENE_PATH: String = "res://scenes/levels/old_courtyard.tscn"
```

引用点只有两处：`save_slot_menu.gd:85`、`ARCHITECTURE.md`。

### 7.2 附带的出生点陷阱（必须一起修，否则入口是坏的）

`create_new_save()` 会写死 `current_scene = <新游戏场景>` +
`player_position = DEFAULT_SPAWN (320, 320)`。而 `LevelBase._place_player()`
的判断是：

```gdscript
if String(save.get("current_scene", "")) == scene_file_path:
    pos = 存档里的坐标        # ← 新档也命中这一条
```

于是**新游戏会用 (320, 320)，而不是关卡自己的 SpawnPoint**。这不是理论问题：
`test_integration.tscn` 的 SpawnPoint 在 `(120, 480)`，今天新开一局落点就是错的，
只是那张灰盒图恰好摔不死。换成旧院之后落点会明显不对。

**方案**（新增字段，走既有的"新字段用 `data.get()` 读、不进 `REQUIRED_KEYS`"
惯例，不需要升 `save_version`）：

```gdscript
# save_manager.gd  create_new_save() 的 data 字典里 +1 行
"use_level_spawn": true,

# save_manager.gd  save_game() 里 +1 行（任何一次真实存档都有真坐标）
data["use_level_spawn"] = false

# save_manager.gd  _read_validated() 里 +1 行（旧档安全默认）
data["use_level_spawn"] = bool(data.get("use_level_spawn", false))

# level_base.gd  _place_player() 的条件 +1 个与项
if not save.is_empty() \
        and String(save.get("current_scene", "")) == scene_file_path \
        and not bool(save.get("use_level_spawn", false)):
```

合计 4 行。放在 `save_game()` 里自动清零，比要求每个存档点记得清更不容易漏。
旧存档没有这个字段 → 默认 `false` → 行为与今天完全一致，无需迁移。

> 这是本轮**唯一**需要动全局系统的地方。原计划 §20 说"正常情况下这些系统
> 应该基本不需要改变"——这 4 行是为了让 13.2 真的可用而必须付的代价，
> 如果你更想零改动，替代方案是把 `DEFAULT_SPAWN` 改成旧院 SpawnPoint 的
> 坐标，但那等于把关卡几何写进 SaveManager，关卡一挪就再次失效。

---

## 8. P1：交互物从 `tests/helpers/` 提升（13.4）

新目录 `scripts/components/`（沿用现有职责目录，不新建 gameplay/）：

| 现在 | 提升为 | class_name |
| --- | --- | --- |
| `tests/helpers/test_door.gd` + `test_memory_door.gd` | `scripts/components/story_door.gd`（**合并**） | `StoryDoor` |
| `tests/helpers/test_memory_pickup.gd` | `scripts/components/memory_pickup.gd` | `MemoryPickup` |
| `tests/helpers/test_key_pickup.gd` | `scripts/components/flag_pickup.gd` | `FlagPickup` |
| `tests/helpers/test_save_point.gd` | `scripts/components/save_point.gd` | `SavePoint` |
| `tests/helpers/test_interactable.gd` | **留在 tests/**（纯测试计数器） | — |
| `tests/helpers/dream_test_spinner.gd` | **留在 tests/** | — |

`StoryDoor` 合并后同时支持两种门槛，并补一个 Director 用的静默终态方法：

```gdscript
class_name StoryDoor
extends Interactable

@export var required_memory: StringName = &""   # 与基类 required_flag 叠加

signal opened

func is_requirement_met() -> bool:
	if not super():
		return false
	return required_memory == &"" or MemoryManager.has_memory(required_memory)

func set_unlocked(unlocked: bool) -> void   ## 静默终态，读档恢复用
func open() -> void                          ## 带表现地开门，发 opened
```

**移动脚本会打断 `.tscn` 的 `ext_resource` 路径**（AGENTS.md §8 的警告）。
需要同步更新的场景，已核对：

| 场景 | 引用的 helper |
| --- | --- |
| `tests/test_integration.tscn` | test_door / test_key_pickup / test_memory_pickup / test_save_point |
| `tests/whitebox_25d/whitebox_25d.tscn` | test_memory_pickup / test_save_point |
| `tests/bg_pacing/bg_pacing_lab.tscn` | test_memory_door / test_memory_pickup |

三个场景改路径 + 门的两个类合并成一个（`bg_pacing_lab.tscn` 的
`MemoryDoor` 节点脚本换成 `story_door.gd`，导出属性名不变，无需改值）。
测试场景反过来用正式组件——正是原计划 13.4 期望的方向。

---

## 9. Vertical Slice 提案（§12）

原计划要求先跑通**一条完整剧情链**验证 Director 能否干净串起所有系统。
下面这条**完全基于旧院现有素材**，不需要新美术、不需要新信物资源：

```
进入旧院（Area01 落地点）
   ↓ 自由探索：院门 / 身高刻痕 / 树上布条        ← 现有 text_interactable
调查【药圃】——"枝叶散发着熟悉的苦味"            ← 现有 HerbBedSpot
   ↓ Director: 写 old_courtyard.poison_discovered
调查【侧窗】——"到处都是相同的山鸟纹"            ← 现有 SideWindow
   ↓ Director: 两个条件都满足 → 播幻觉
【母亲幻觉 Cutscene】                            ← 新增，灰盒即可（变色+相机+文字）
   ↓ finished → Director: 推进信物「山鸟簪」      ← 现有 mountain_bird_hairpin.tres
                写 old_courtyard.mother_memory_seen
【丫鬟入场】                                     ← 新增 StoryNPC，灰盒方块
   ↓ 对话 → dialogue_finished
   ↓ Director: 写 old_courtyard.maid_talked
【侧窗解锁】→ 可进主屋                           ← 现有跳转，改由 Director 决定
```

这条链覆盖了原计划 §12 要求的全部环节，并且**顺手消化了 §8 点名的
`_pending_enter` 反模式**：现在侧窗是"读完文字就进屋"，改造后变成
"剧情条件满足才开放进屋"，`old_courtyard.gd` 里的 pending 标记整段删掉。

**双条件入场**（药圃 + 侧窗，缺一不可）是刻意的：它正好验证原计划 §7 的
"NPC 为什么在这里出现，答案能在 Director 里找到"——Director 里会有一个
显式的 `_try_trigger_mother_memory()` 检查两个 Flag，而不是任何 NPC 自己轮询。

### 需要你拍板的（CLAUDE.md：叙事含义、关卡构成不由我独立决定）

1. 这条链的**剧情内容**是否成立：药圃苦味 + 侧窗山鸟纹 → 母亲幻觉 → 丫鬟。
   我是从现有占位文案里读出的关联（侧窗写着"更像属于某一个人的记号"，
   信物里正好有「山鸟簪」），但这属于叙事含义，得你确认。
2. 丫鬟这个 NPC 是否存在、叫什么、说什么。
3. 母亲幻觉的表现方向（我只会做灰盒：变色 + 相机推近 + 一段文字）。

上面三条没定之前，我可以先把**架构骨架**（基类 + Director + 空演员 + 入口修复
+ Flag 迁移 + 组件提升）全部落地，剧情内容用占位文案，等你定了再替换。

---

## 10. 新增文件清单与改动量

### 新增（7 个文件）

```
scripts/narrative/story_director.gd            ~60 行   基类
scripts/narrative/cutscene.gd                  ~55 行   演出基类
scripts/narrative/story_npc.gd                 ~70 行   NPC 基类
scripts/components/story_door.gd               ~45 行   门（合并信物门槛）
scripts/components/memory_pickup.gd            ~30 行   由 helper 提升
scripts/components/flag_pickup.gd              ~15 行   由 helper 提升
scripts/components/save_point.gd               ~25 行   由 helper 提升
scenes/levels/old_courtyard_story_director.gd  ~150 行  第一个 Director
```

### 修改

| 文件 | 改动 |
| --- | --- |
| `scripts/autoload/save_manager.gd` | 常量改名 + `use_level_spawn` 共 **5 行** |
| `scenes/levels/level_base.gd` | `_place_player()` 条件加一项，**1 行** |
| `scenes/levels/old_courtyard.gd` | **删**掉 pending / 侧窗 / 切场景逻辑，只留相机与 UI 布线 |
| `scenes/levels/old_courtyard.tscn` | 加 `Cutscenes` / `NPCs` / `StoryDirector` 三个节点 |
| `scenes/ui/save_slot_menu.gd` | 跟随常量改名，1 行 |
| 4 个测试 `.tscn` + 3 个测试 `.gd` | Flag 改名 + 脚本路径改名 |
| `ARCHITECTURE.md` | 新增叙事层章节，更新技术债 |

`MemoryManager` / `WorldTimeManager` / `Player` / `InteractionDetector` /
`DialogueBox`：**零改动**。

### 施工顺序（每步都可单独验证）

1. Flag 改名（13.3）—— 纯改名，跑一遍现有测试房确认全 PASS。
2. 组件提升（13.4）—— 改脚本路径，再跑一遍测试房。
3. `use_level_spawn` + 入口切换（13.2）—— 新建存档验证落点在 SpawnPoint。
4. 三个基类落地 —— 无行为，只有编译通过。
5. `OldCourtyardStoryDirector` + 占位演员 —— 跑通链路。
6. 存读档验证：链路中途存档 → 重进 → 不重播、状态正确。

---

## 11. 对照原计划 §19 完成标准

| 标准 | 本设计如何满足 |
| --- | --- |
| Git baseline | **本轮跳过**（按你的指示） |
| New Game 不进 test_integration | §7，含出生点修复 |
| 测试不写正式 Flag namespace | §6.3，4 个 Flag 改名 |
| old_courtyard 有独立 StoryDirector | §3 + §9 |
| LevelBase 职责没膨胀 | 只加 1 行条件判断，五步流程不变 |
| StoryFlagManager / MemoryManager 职责不变 | 零改动 |
| 无 Global EventBus | 全部走 Signal 直连 Director |
| 无大型 Quest / Narrative Framework | 三个基类合计约 185 行，无图无 DSL 无状态机 |
| NPC 入场由 Director 决定 | §5.2 禁止轮询，§9 双条件在 Director 里判 |
| Cutscene 只管表现 | §5.1 契约明确禁止写 Flag / 推信物 / 解锁门 |
| Dialogue 不当导演 | §5.3，两处 pending 迁进 Director |
| 正式关卡不依赖 tests/helpers | §8 提升清单 |
| 一条完整 Vertical Slice | §9（内容待你确认） |
| 存读档不重复触发 | §4 的 `_on_*` / `_apply_*` 双函数 + §3.2 的恢复时机 |
| DreamGap 架构不变 | 零改动 |
| Player 只用 source-based lock | Cutscene 用 `cutscene` 锁，与现有四把并存 |

---

## 12. 本文件的归宿

这是**过渡性设计文档**。叙事层实施完成后：

- §2–§6 的内容并入 `ARCHITECTURE.md` 成为正式章节；
- §7、§8 的技术债从 `ARCHITECTURE.md` 第 10 节划掉；
- §5 的三条演员契约补进 `AGENTS.md` 第 10 节复用指引表；
- 本文件可删除。

---

## 13. 实施与本设计的差异（2026-08-26 补记）

施工过程中发现的、与 §10 估算不同的地方：

1. **`test_integration.gd` 需要跟着改。** `StoryDoor` 把 `is_open` 从公开
   变量改成了方法，测试原本用 `_door.get("is_open")` 读，会报
   "Nonexistent 'bool' constructor"。已把测试里的引用改成类型化的
   `StoryDoor` / `SavePoint` 并直接调方法——比为兼容保留一个冗余公开变量干净。
2. **`old_courtyard.gd` 加了 `class_name OldCourtyard`。** Director 需要调
   `enter_main_house()`，没有 class_name 就只能 `call()` 动态派发、丢掉静态检查。
3. **丫鬟挂在 `Area03_MainHouse` 下，不在关卡根的 `NPCs` 容器里。**
   原计划的树形图把 NPCs 放根节点，但 `exploration_area` 承诺"拖动区域节点即可
   整体搬移"，NPC 放根节点会破坏这个性质。区域内的演员就该住在区域里。
4. **`test_old_courtyard.tscn` 的侧窗断言必须重写。** 侧窗行为从"读完文字就进屋"
   变成"剧情条件满足才是入口"，旧断言必然失败。重写后该测试房从 44 条涨到
   67 条，新增的覆盖了整条剧情链、读档恢复、新游戏落点。
5. **新 `class_name` 需要刷新全局类表。** 直接跑 headless 会报
   "Could not find type"，得先让编辑器扫一次文件系统（MCP `filesystem_manage
   scan`）重建 `.godot/global_script_class_cache.cfg`。

未偏离的部分：`MemoryManager` / `WorldTimeManager` / `Player` /
`InteractionDetector` / `DialogueBox` 确实**零改动**；`SaveManager` 5 行、
`LevelBase` 1 行，与 §10 估算一致。
