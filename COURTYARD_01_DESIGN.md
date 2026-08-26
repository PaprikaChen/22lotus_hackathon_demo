# COURTYARD_01_DESIGN.md — 第一个正式关卡的设计

针对 `courtyard_01`（以及将来的 `courtyard_02`）本轮要做的五块内容做的落地设计。
核对于 2026-08-26 的仓库真实状态。

> **状态：已实施（2026-08-26）。** 五块内容全部落地，`tests/test_courtyard_01.tscn`
> 60 条断言通过；全项目 9 个测试场景合计 **275 条断言、0 失败**。
> 左眼金纹按你的指示**不做**——`PlayerVisual` 只做 `flip_h`，不含金纹图层。
> 其余待定项已填入下方 §10 的占位数值，后期在长卷调参台里改。

**本轮范围**：设计 + 实施。

> **已拍板（2026-08-26）**
> 1. CG 解锁状态存**全局** `user://gallery.json`，跨三个存档槽共享；
>    **批准新增 `GalleryManager` autoload**。存档槽格式完全不动。
> 2. `courtyard_01` 存档策略：**进关卡自动存一次 + 关卡里放手动存档点**。
> 3. 前情提要：**分段，每段 Space 推进**，最后一段之后进关卡。
>
> 仍待你定：前情提要文案与段数、CG 数量与解锁节点、courtyard_01 的美术尺寸
> （背景宽度 / 地面线高度 / 人物显示高度）、左眼金纹的两个朝向偏移。
> 这些都不阻塞动工——架构骨架和灰盒关卡可以先落地，占位替换即可。

**要设计的五块**
1. 存档系统：主菜单三个入口（新游戏 / 读取存档 / 画廊 CG 收集）
2. 前情提要：只在新游戏时播放，黑屏 + 中心文字，Space 进入
3. 进游戏后玩家控制权：A 左移 / D 右移 / E 调查
4. 相机：跟随人物居中，到场景左右边缘则相机停住、人物继续走
5. 人物：无跳跃，只有待机 / 行走两态，按左右键行走并按方向翻转

**梦奁信物系统保持不动**：`MemoryManager`、`memory_box_ui.tscn`、
`memory_toast.tscn`、`MemoryPickup`、`StoryDoor` 的 `required_memory` 全部照旧，
`courtyard_01` 直接用现成的。CG 画廊是**另一套**收集品，不动信物（见 §3.3）。

---

## 1. 核心决策一览

| # | 决策点 | 选择 | 理由 |
| --- | --- | --- | --- |
| 1 | CG 解锁状态存哪 | **全局文件 `user://gallery.json`**，不进存档槽 | 画廊要从主菜单进（那时没有任何槽位被载入）。同类游戏也都是跨存档的账号级收集 |
| 2 | 谁写这个文件 | **`SaveManager` 加一组通用 global store API** | AGENTS.md 硬规则：所有文件 I/O 只在 SaveManager 内。顺带复用它的临时文件安全写入 |
| 3 | CG 数据结构 | 照抄 `MemoryEntry` 的三层分离 | 已验证过的架构，不发明新写法 |
| 4 | 前情提要放哪 | **独立场景**，插在 SaveSlotMenu 和关卡之间 | 放关卡里就得判断"是不是新游戏"，等于给关卡加剧情状态；放流程里天然只在新游戏走一次 |
| 5 | 前情提要用什么键 | `ui_accept`（引擎内建，含 Space） | 不用改 input map。`jump` 也是 Space，但语义是跳跃，不该复用 |
| 6 | 禁跳跃怎么实现 | Player 加 `jump_enabled` 布尔，由 LevelBase 下发 | 比新增一个 `MovementMode` 轻，而且和移动模式正交（2.5D 也可能要禁跳） |
| 7 | 相机边缘停住 | **Camera2D 内建 `limit_*`**，不自己 clamp | 引擎行为就是"到边缘视图停住、人物继续走"，正是需求原文 |
| 8 | 动画怎么接 | 新增 `PlayerVisual` 表现层组件，只听信号 | AGENTS.md：移动逻辑不得依赖动画资源名。`player.gd` 一行不改 |
| 9 | 场景结构 | **单张长背景 + 相机 limits**，不用旧院的分屏区域 | 需求 4 描述的是连续滚动。`AreaFlowController` 是给"一屏一屏切"用的，这里不适用 |

---

## 2. 整体流程

```
MainMenu
 ├─[新游戏]→ SaveSlotMenu(new) → create_new_save() → PrologueScreen ─┐
 │                                                                    │ ui_accept
 ├─[读取存档]→ SaveSlotMenu(load) → load_game() ──────────────────────┤
 │                                        (跳过前情提要，直接去存档里的 current_scene)
 ├─[画廊]───→ GalleryScreen → 返回 MainMenu
 └─[退出]
                                                                      ▼
                                                             courtyard_01
                                                                  │ LevelExit
                                                                  ▼
                                                             courtyard_02
```

**"只在新游戏时播放前情提要"是流程保证的，不是靠 Flag 判断的。** 读档分支直接
跳到 `current_scene`，而 `create_new_save()` 写进存档的 `current_scene` 是
`courtyard_01`（**不是**前情提要场景）——所以玩家如果在前情提要期间退出再读档，
会直接进关卡而不是重看一遍。

---

## 3. 存档系统

### 3.1 主菜单：加第三个入口

`MainMenu.tscn` 现在是 Start New Game / Load Game / Exit 三个按钮，加一个
**画廊**。同时建议把英文按钮文案换成中文（这是正式关卡了，不再是 prototype）。

```
二十二莲境
  ├── 新游戏      → SaveSlotMenu(mode="new")
  ├── 读取存档    → SaveSlotMenu(mode="load")      ← 没有任何存档时置灰
  ├── 画廊        → GalleryScreen
  └── 退出
```

"读取存档"在三个槽位全空时置灰：`SaveManager.save_exists()` 已有，
主菜单 `_ready` 里查一遍即可。

### 3.2 前情提要的插入点

只改 `save_slot_menu.gd` 的一行——新游戏分支的目标场景：

```gdscript
func _start_new_game(slot_id: int) -> void:
	if not SaveManager.create_new_save(slot_id):
		push_error(...)
		return
	get_tree().change_scene_to_file(SaveManager.PROLOGUE_SCENE_PATH)   # 原来是 NEW_GAME_SCENE_PATH
```

`SaveManager` 加一个常量，和现有的 `NEW_GAME_SCENE_PATH` 并列：

```gdscript
## 新游戏先播前情提要，播完再进 NEW_GAME_SCENE_PATH。
## 注意：存档里的 current_scene 写的是 NEW_GAME_SCENE_PATH，不是这个——
## 前情提要不是一个"可以存档的地方"。
const PROLOGUE_SCENE_PATH: String = "res://scenes/ui/prologue.tscn"
```

`NEW_GAME_SCENE_PATH` 改指向 `res://scenes/levels/courtyard_01.tscn`。
（现在指向 `old_courtyard.tscn`——旧院降级为参考实现，见 §7.4。）

### 3.3 CG 画廊

**先说边界**：CG 画廊和梦奁信物是两套东西，不要互相污染。

| | 梦奁信物 | CG 画廊 |
| --- | --- | --- |
| 是什么 | 玩家**拥有**的物件，有多段解读阶段 | 剧情节点解锁的**插画** |
| 谁管 | `MemoryManager` | 新增 `GalleryManager` |
| 存哪 | 存档槽字段 `memories`（每档独立） | 全局 `user://gallery.json`（跨档共享） |
| 从哪看 | 游戏内按 Tab | 主菜单（也可以在游戏内加入口） |

**为什么 CG 是跨存档的**：画廊入口在主菜单，那时没有任何槽位被载入。如果 CG 状态
在存档槽里，从主菜单进画廊就只能是空的。同类叙事游戏的 CG 收集也都是账号级的。

**静态数据**（照抄 `MemoryEntry` 的写法）：

```gdscript
class_name CGEntry
extends Resource
## 一张画廊 CG 的静态定义。运行时状态不在这里（见 GalleryManager）。
## id 一经写入 gallery.json 不得改名；标题和图可以随时换。

@export var id: StringName = &""
@export var title: String = ""
@export var image: Texture2D            ## 全尺寸
@export var thumbnail: Texture2D        ## 缩略图；留空则用 image 缩放
@export_multiline var caption: String = ""
@export var sort_order: int = 0         ## 画廊里的固定排序，不依赖文件名
```

资源放 `resources/cg/*.tres`，`GalleryManager` 启动时扫目录自动注册——和
`MemoryManager._load_entries()` 完全同一套做法。

**运行时状态**：

```gdscript
# scripts/autoload/gallery_manager.gd  →  Autoload "GalleryManager"
signal cg_unlocked(cg_id: StringName)
signal cg_state_changed(cg_id: StringName)

func unlock_cg(cg_id: StringName) -> bool     ## 首次解锁返回 true，重复解锁不重复提示
func has_cg(cg_id: StringName) -> bool
func mark_as_seen(cg_id: StringName) -> void  ## 清掉 NEW 角标
func is_unseen(cg_id: StringName) -> bool
func get_all_cgs() -> Array[StringName]       ## 按 sort_order，含未解锁的（画廊要显示占位）
func get_unlocked_count() -> int
func reset() -> void                          ## 调试用；正常流程不清空跨档收集
```

`_states` 只存 `{unlocked: bool, seen: bool}`，**绝不存文案或图**——和
`MemoryManager` 同一条纪律。

**谁调 `unlock_cg()`**：`StoryDirector`。CG 解锁是剧情后果，
和"写 Flag / 推进信物"是同一类事，写在 Director 的 `_on_*` 里：

```gdscript
func _on_screen_examined(_player: Node) -> void:
	if StoryFlagManager.has_flag(FLAG_SCREEN_SEEN):
		return
	StoryFlagManager.set_flag(FLAG_SCREEN_SEEN)
	GalleryManager.unlock_cg(&"cg_01_screen")
	MemoryManager.unlock_memory(&"...")
	_cutscene.play()
```

### 3.4 SaveManager 加一组 global store

`GalleryManager` 不能自己读写文件（AGENTS.md：所有文件 I/O 只在 SaveManager 内）。
所以 `SaveManager` 加一组**通用**的全局存储 API，复用它已有的临时文件安全写入：

```gdscript
## 跨存档槽的全局数据（画廊收集、将来的设置 / 成就）。
## 与三个存档槽完全无关：不进 REQUIRED_KEYS、不参与 save_version 迁移、
## 删存档不影响它。
func read_global(store_name: String) -> Dictionary
func write_global(store_name: String, data: Dictionary) -> bool
```

落盘为 `user://<store_name>.json`，写入走和存档槽同一条 `.tmp` → 替换的路径。

**存档槽格式完全不动**：`REQUIRED_KEYS` 不加字段、`save_version` 不升、
旧档不需要迁移。这是选全局文件方案的额外好处。

### 3.5 画廊 UI

`scenes/ui/gallery.tscn`，结构照 `memory_box_ui.tscn`（那套网格 + 详情面板已经
跑通过，含 NEW 角标逻辑），差别：

- 它是**独立场景**而不是游戏内叠层，所以不需要暂停世界、不需要锁玩家输入；
- 未解锁的格子显示占位（锁形图标 + `？？？`），**不显示标题**，避免剧透；
- 点开是全屏看图，Esc / 返回按钮回网格，再按一次回主菜单；
- 顶部显示 `已收集 3 / 12`。

---

## 4. 前情提要 PrologueScreen

`scenes/ui/prologue.tscn` + `scripts/ui/prologue_screen.gd`。

```
PrologueScreen (Control, 全屏)
├── Backdrop (ColorRect)        纯黑
├── CenterContainer
│   └── TextLabel (Label)       居中，autowrap，逐段显示
└── ContinueHint (Label)        底部，"空格 继续"，缓慢闪烁
```

```gdscript
extends Control
## 前情提要：黑屏 + 居中文字，ui_accept 逐段推进，最后一段之后进入正式关卡。
##
## 只在新游戏流程里出现（SaveSlotMenu 的新游戏分支跳到这里）。它不是一个
## 可以存档的地方——存档里的 current_scene 直接写的是关卡。
##
## 表现刻意做得极简：黑底白字 + 淡入淡出。真正的美术方案定稿后换掉
## _show_segment() 的实现即可，流程不用动。

## 每一段一条。用 ui_accept 推进（引擎内建，含 Space 和 Enter）。
@export var segments: PackedStringArray = []
@export var fade_duration: float = 0.8
## 每段至少停留这么久才接受输入，防止连按一路跳过。
@export var min_segment_time: float = 0.4
@export var allow_skip_all: bool = true   ## Esc 整段跳过

func _ready() -> void
func _unhandled_input(event: InputEvent) -> void   ## ui_accept → 下一段 / Esc → 跳过
func _show_segment(index: int) -> void             ## 淡出旧的、淡入新的
func _finish() -> void                             ## → SaveManager.NEW_GAME_SCENE_PATH
```

文案由 `segments` 导出属性承载（**存在场景里，不写死在脚本里**——和
`text_interactable.gd` 的 `display_text` 同一条纪律，方便你直接在编辑器里改）。

**为什么用 `ui_accept` 而不是 `jump`**：`jump` 绑的也是 Space，但语义是跳跃。
`ui_accept` 是引擎内建（Space + Enter），`dialogue_box.gd` 已经在用它推进文字，
沿用同一个键位约定。**不需要改 input map**，也就不需要动 `project.godot`。

---

## 5. 人物：无跳跃 + 待机 / 行走 + 翻转

### 5.1 禁跳跃：加布尔，不加 MovementMode

`player.gd` 加一个导出属性，跳跃判定多一个与项：

```gdscript
## 本关是否允许跳跃。由关卡通过 LevelBase 下发（courtyard_01 是纯步行探索）。
## 刻意做成独立布尔而不是新的 MovementMode：它和移动模式正交，
## 2.5D 关卡将来也可能要禁跳。
@export var jump_enabled: bool = true
```

```gdscript
# _process_side_scroll() 里
if input_allowed and jump_enabled and jump_pressed and not _jump_held and is_on_floor():
	velocity.y = jump_velocity
_jump_held = jump_pressed      # 边沿仍然要追踪，禁跳期间按住不会留下脏状态
```

`LevelBase` 加一个导出属性并在 `_ready` 里下发（紧挨现有的
`_apply_movement_mode()`，不改它的签名）：

```gdscript
## 本关是否允许跳跃。移动风格属于关卡配置，和 movement_mode 一样由关卡声明。
@export var player_can_jump: bool = true

func _apply_player_abilities() -> void:
	if _player != null and &"jump_enabled" in _player:
		_player.jump_enabled = player_can_jump
```

`courtyard_01` 的根节点设 `player_can_jump = false`。
**其他所有现有关卡默认 true，行为一行不变。**

> 顺带一个既存事实：重力和 `max_fall_speed` 仍然生效，这是对的——没有跳跃
> 但仍然需要贴地和走下坡。`courtyard_01` 只要保证地面连续、没有需要跳的落差。

### 5.2 表现层：`PlayerVisual` 组件

**`player.gd` 一行不改。** 新增一个挂在 Player 下的表现层子节点，只听信号：

```gdscript
class_name PlayerVisual
extends Node2D
## 玩家表现层：把 Player 的状态和朝向映射到动画与翻转。
##
## 单向依赖：只监听 player 的 state_changed / direction_changed，
## **绝不**反向驱动移动。AGENTS.md 硬规则：移动逻辑不得依赖动画资源名，
## 所以这份映射表只存在于这里。
##
## 素材没接上时自动退化为现有灰盒 Polygon2D，所以这个组件可以先落地、
## 等美术交付了再填 SpriteFrames。

@export var player_path: NodePath = ^".."
@export var sprite_path: NodePath        ## AnimatedSprite2D；留空 = 用灰盒
@export var graybox_path: NodePath       ## 现有的 Polygon2D，接上 sprite 后隐藏

## 状态 → 动画名。改动画名只改这里。
@export var anim_idle: StringName = &"idle"
@export var anim_walk: StringName = &"walk"
@export var anim_interact: StringName = &"interact"
```

映射（对应你需求里的"只有待机和行走两种状态"）：

| Player.State | 动画 | 说明 |
| --- | --- | --- |
| `IDLE` | `idle` | 不按左右键 |
| `RUN` | `walk` | 按住 A 或 D。`player.gd` 里 RUN 的判据是 `abs(velocity.x) > 5`，减速滑行的尾巴也算行走，视觉上是对的 |
| `INTERACT` | `interact` | 调查 / 对话中 |
| `JUMP` / `FALL` | `idle` | 禁跳关卡里正常走不到；只有踩空的一两帧会命中，回落 idle 最安全 |
| `DISABLED` | 保持当前 | 过场 / 区域切换期间不换动画 |

翻转由 `direction_changed(facing)` 驱动：`sprite.flip_h = facing < 0`。
你的 sprite 规范里"只画朝右的一套、向左由程序镜像"正好对应。

> 需要 `player.gd` 加 `class_name Player`，否则 `PlayerVisual` 里无法静态引用
> `Player.State` 枚举，只能拿裸 int 硬编码。加 class_name 是纯增量，不改任何
> 现有引用（所有 .tscn 都是按脚本路径引用的）。

### 5.3 左眼金纹的翻转陷阱（从你的 sprite 规范里读出来的）

你的规范第 11 节明确要求金纹单独导出 `liniang_eye_glow.png`，理由是
"人物镜像时程序可以单独调整金纹位置，不会让左眼能力错误地变成右眼能力"。

**这条不能靠 `flip_h` 自动满足。** 如果金纹是 Player 的子节点、跟着一起镜像，
它会精确地跑到另一只眼睛上——这正是规范要避免的事。所以 `PlayerVisual` 必须
把**两个朝向的偏移分开配**，而不是数学取反：

```gdscript
@export_group("Eye Glow")
@export var eye_glow_path: NodePath
## 朝右和朝左各自的位置，分开配而不是 x 取反——
## 侧脸镜像后金纹该落在哪，是美术判断，不是数学。
@export var eye_glow_offset_right: Vector2 = Vector2.ZERO
@export var eye_glow_offset_left: Vector2 = Vector2.ZERO
## 朝左时那只眼可能被侧脸挡住。挡住就设 false。
@export var eye_glow_visible_when_facing_left: bool = true
@export var eye_glow_flip_when_facing_left: bool = true
```

**这两个偏移值和"朝左时是否可见"是需要你（或美术）拍板的**，我给不出正确数值，
只能把口子留好。素材到位后在编辑器里拖两下就能定。

### 5.4 素材接入（对齐你的交付规范）

按你规范第 21 节的目录结构落地：

```
assets/art/characters/liniang/
├── ingame/
│   ├── liniang_idle.png       1024 × 256  （4 帧 × 256）
│   ├── liniang_walk.png       1536 × 256  （6 帧 × 256）
│   └── liniang_interact.png   ~768 × 256  （2–3 帧）
├── portraits/
│   ├── liniang_normal.png     对话立绘，接 DialogueBox 的 portrait 位
│   ├── liniang_confused.png
│   └── liniang_uneasy.png
└── fx/
    └── liniang_eye_glow.png
```

（`source/` 里的 PSD / Procreate 源文件**不要**进这个仓库——几百 MB 级的美术源
文件应该单独放网盘或 Git LFS。需要的话我可以加进 `.gitignore` 并在
`assets/art/characters/README.md` 里写清源文件放哪。）

**导入设置**：这是手绘风格不是像素画，所以纹理过滤保持默认的**线性**，
不要设 Nearest。`AnimatedSprite2D` 的 `SpriteFrames` 用编辑器的
"Add frames from sprite sheet"，横向 6 格 / 4 格切。

**帧率**：`walk` 建议先设 10 FPS（6 帧 = 0.6 秒一个循环），配合
`move_speed`。这个数值和 `move_speed` 是一对——步频和位移不匹配会有"滑步"
感。你之前那个长卷调参台（`tests/bg_pacing/`）正好可以用来对这两个值，
建议素材到了以后在那里调，定下来再抄进 `player.tscn`。

**人物显示高度**：规范说单帧 256px，但游戏里实际显示多高由 `scale` 决定。
现有灰盒是 48px 高。这个比例关系是你在长卷调参台里没定下来的那件事
（当时算出草图里画的人约 230–250px 高）。素材到位后需要定：
`AnimatedSprite2D.scale` + Player 碰撞盒高度 + `move_speed` 三者要一起定。

---

## 6. 相机：`FollowCamera2D`

需求原文："摄像头跟着人物走，人物始终处在画面中心。但如果到达场景左右的边缘，
则场景不动而人物动。"

**这就是 Camera2D 内建 `limit_left/right/top/bottom` 的行为，不要自己写 clamp。**
Camera2D 的 limit 钳制的是相机的**渲染中心**——相机节点位置可以继续跟着人走，
但画面到边界就停住，人物于是自然地偏离屏幕中心向边缘走过去。

```gdscript
class_name FollowCamera2D
extends Camera2D
## 横版关卡相机：横向跟人、纵向锁死；走到场景左右边缘时画面停住、人物继续走。
##
## 边缘停住这件事由 Camera2D 内建的 limit_* 完成，本脚本只负责
## 每帧把位置放到目标身上，以及从背景尺寸算出 limit 值。
## 读"画面实际中心"用 get_screen_center_position()，不要读 position
## （limit 生效时两者不同）。

@export var target_path: NodePath
## 世界可见范围。留空则从 bounds_source_path 那张背景 Sprite2D 推算。
@export var world_bounds: Rect2 = Rect2()
@export var bounds_source_path: NodePath
## 横版关卡通常锁死纵向，避免走坡时画面上下晃。
@export var follow_y: bool = false
@export var fixed_y: float = 0.0
## 0 = 硬跟随。轻微平滑（0.1 秒左右）会让走动更舒服，但会让"贴边"多半帧才停。
@export var smoothing_seconds: float = 0.0
```

要点：

- `_ready()`：算出 bounds → 写 `limit_left/right/top/bottom`；把
  `position_smoothing_enabled` / `position_smoothing_speed` 按
  `smoothing_seconds` 设好。
- `_process()`：`position.x = target.global_position.x`；
  `position.y = fixed_y`（或跟随）。**没有任何 clamp 代码**。
- **硬约束：场景宽度必须 ≥ 视口宽度。** 否则左右 limit 互相冲突，Godot 会先
  钳左再钳右，画面会抖。`_ready()` 里加一条 `push_warning` 提示。
- 视口是 1152 × 648（`project.godot` 没覆盖 display 设置，用的是引擎默认）。
  所以 `courtyard_01` 的背景至少 1152px 宽——实际会远宽于此。

> 现有 `tests/bg_pacing/bg_pacing_lab.gd` 里有一份手写的 clamp 逻辑。那是调参台
> 的自留地（它要按缩放实时重算），**不迁**；正式关卡一律用这个组件。

---

## 7. 场景结构

### 7.1 `courtyard_01.tscn`

```
Courtyard01 (LevelBase)
  level_id = &"courtyard_01"
  movement_mode = SIDE_SCROLL
  player_can_jump = false          ← §5.1 新增
  player_path / spawn_point_path
├── Background (Node2D)
│   ├── Far (Sprite2D)             远景，可选视差
│   ├── Mid (Sprite2D)             主背景长图，centered = false（原点左上）
│   └── Near (Sprite2D)            近景遮挡，z_index 高于 Player
├── Ground (StaticBody2D)          沿地面轮廓的碰撞体（可多段拼高低差）
├── Bounds (Node2D)
│   ├── WallLeft / WallRight       StaticBody2D，防止走出图外
├── SpawnPoint (Marker2D)
├── Props (Node2D)                 TextInteractable / MemoryPickup / StoryDoor
├── NPCs (Node2D)                  StoryNPC
├── Cutscenes (Node)               Cutscene 子类
├── Player                         instance player.tscn（内含 PlayerVisual）
├── FollowCamera2D                 target = Player, bounds_source = Background/Mid
├── DialogueBox                    instance（对话 / 调查文字统一走它）
├── MemoryBoxUI                    instance（Tab 开梦奁）
├── MemoryToast                    instance（获得信物提示）
├── UI (CanvasLayer)
│   └── PromptLabel                "[E] 调查xxx"
├── LevelExit                      → courtyard_02
└── StoryDirector                  courtyard_01_story_director.gd
```

`courtyard_02` 是这棵树的**复制品**，换背景、换 Props、换 Director。
所以建议第一版就把 `courtyard_01.tscn` 做干净，直接当模板用。

### 7.2 关卡脚本的职责边界

`courtyard_01.gd`（继承 `LevelBase`）**只**负责：把各个 `text_requested` 接到
DialogueBox、把 `prompt_changed` 接到 PromptLabel、以及"去下一关"这一次场景切换
怎么做（一个幂等的 `go_to_next_level()`）。

**剧情判断一律在 `courtyard_01_story_director.gd` 里。** 这条已经在
`AGENTS.md` §5.5 立好了规矩，旧院是范例。

### 7.3 `LevelExit` 组件

`scripts/components/level_exit.gd`，`extends Interactable`：

```gdscript
class_name LevelExit
extends Interactable
## 通往下一关的出口。**只管"怎么走"**，不判断"能不能走"——
## 门槛用基类的 required_flag / required_memory，时机由 StoryDirector 决定。
signal exit_reached(target_scene: String)

@export_file("*.tscn") var target_scene: String = ""
## true = 走到就触发（body_entered），false = 按 E 触发
@export var trigger_on_touch: bool = false
```

真正的 `change_scene_to_file` 由关卡脚本做（和旧院的 `enter_main_house()`
一个写法）。**不建 SceneManager**——叙事计划书 §14 明确说等真的需要统一
fade / autosave / loading 时再抽。

### 7.4 旧院怎么办

`old_courtyard` / `main_house_interior` 从"新游戏入口"降级为**参考实现**：
分屏区域流转、AreaFlowController、StoryDirector 范例都还在，测试房
`tests/test_old_courtyard.tscn` 的 67 条断言继续跑，不删不动。

只有一处要改：`NEW_GAME_SCENE_PATH` 从旧院改指 `courtyard_01`。
`tests/test_old_courtyard.gd` 里那条"New Game 入口指向正式关卡"的断言要跟着
更新成新路径。

### 7.5 存档点

需求里"可读取存档"要求关卡里得有地方能存。现成的 `SavePoint` 组件直接用。
**但要定一个策略**（见 §9 决策 3）：是只放手动存档点，还是进关卡时自动存一次。

---

## 8. 文件清单与改动量

### 新增

```
scripts/autoload/gallery_manager.gd          ~110 行  照抄 MemoryManager 结构
scripts/gallery/cg_entry.gd                  ~20 行   CGEntry 资源
scripts/components/follow_camera.gd          ~60 行   FollowCamera2D
scripts/components/level_exit.gd             ~30 行   LevelExit
scenes/player/player_visual.gd               ~90 行   表现层，含金纹翻转
scenes/ui/prologue.tscn / prologue_screen.gd ~80 行   前情提要
scenes/ui/gallery.tscn / gallery_screen.gd   ~150 行  画廊，照 memory_box_ui
scenes/levels/courtyard_01.tscn              灰盒关卡
scenes/levels/courtyard_01.gd                ~60 行   只有 UI 布线 + 切场景
scenes/levels/courtyard_01_story_director.gd 剧情待定
resources/cg/*.tres                          CG 条目（数量待定）
tests/test_courtyard_01.tscn / .gd           关卡回归
tests/test_gallery.tscn / .gd                画廊 + 全局存储回归
```

### 修改

| 文件 | 改动 | 行数 |
| --- | --- | --- |
| `scripts/autoload/save_manager.gd` | `PROLOGUE_SCENE_PATH` 常量、`NEW_GAME_SCENE_PATH` 改指向、`read_global` / `write_global` | ~30 |
| `scenes/levels/level_base.gd` | `player_can_jump` 导出 + `_apply_player_abilities()` | ~6 |
| `scenes/player/player.gd` | `class_name Player`、`jump_enabled` 导出、跳跃判定加一个与项 | ~4 |
| `scenes/player/player.tscn` | 加 `PlayerVisual` 子节点（含 AnimatedSprite2D 占位） | 场景 |
| `scenes/ui/MainMenu.tscn` / `main_menu.gd` | 加画廊按钮、无存档时置灰读档、中文化 | ~15 |
| `scenes/ui/save_slot_menu.gd` | 新游戏分支改跳前情提要 | 1 |
| `project.godot` | **注册 `GalleryManager` autoload** ← 需要你许可 | 1 |
| `tests/test_old_courtyard.gd` | 入口断言跟着改路径 | 1 |
| `AGENTS.md` / `ARCHITECTURE.md` | 补画廊层、相机组件、表现层规则 | 文档 |

`MemoryManager` / `WorldTimeManager` / `StoryFlagManager` / `InteractionDetector` /
`DialogueBox` / `Interactable`：**零改动**。梦奁系统完全不受影响。

### 实施顺序（每步可单独验证）

1. `FollowCamera2D` + `jump_enabled` + `PlayerVisual`（灰盒退化路径）
   → 拿现有长卷调参台或一个临时灰盒场景验证走动和相机贴边。
2. `courtyard_01.tscn` 灰盒骨架（纯色块背景 + 地面 + 出生点 + 相机）
   → 能从左走到右、贴边正确、不能跳。
3. 前情提要 + 主菜单三入口 + slot menu 改跳
   → 新游戏走一遍完整流程，读档跳过前情提要。
4. `SaveManager` global store + `GalleryManager` + 画廊 UI
   → 用测试解锁两张占位 CG，验证跨档保留、删存档不影响。
5. Props / 信物 / StoryDirector / `LevelExit` → `courtyard_02` 灰盒。
6. 美术素材到位后：填 SpriteFrames、定金纹偏移、对 walk 帧率与 move_speed。

---

## 9. 决策状态

### 已拍板

| # | 决策 | 结论 | 影响 |
| --- | --- | --- | --- |
| 1 | CG 归属 | 全局 `user://gallery.json`，跨档共享 | 存档槽零改动，画廊可从主菜单直接进 |
| 2 | `GalleryManager` autoload | **已批准** | `project.godot` 加一行 autoload 注册 |
| 3 | `courtyard_01` 存档 | 进关自动存 + 关卡内手动存档点 | 见下方 9.1 |
| 4 | 前情提要翻页 | 分段，每段 Space 推进 | `segments: PackedStringArray` 逐条推进，已是 §4 的设计 |

### 9.1 自动存档的落点（决策 3 的展开）

"进关卡自动存一次"要落在 `LevelBase` 还是关卡里？**放关卡里**，不放 `LevelBase`。

理由：`LevelBase` 目前五件事（DreamGap reset / session reset / MovementMode /
出生位置 / 输入锁清理）都是**不产生副作用**的初始化。写盘是副作用，而且测试房
会反复实例化关卡（`tests/test_old_courtyard.gd` 就连续实例化了四次来验证读档
恢复）——如果 `LevelBase._ready()` 会写盘，每跑一次测试都会污染真实存档。

所以设计成：`courtyard_01.gd` 里一个显式的 `autosave()`，由 `StoryDirector` 在
`_on_story_ready()`（也就是恢复完成之后）调一次，并且沿用 `SavePoint` 已有的
保护——`SaveManager.current_slot == -1` 时只汇报不写盘，测试和 F6 单开永远碰不到
真实存档。

### 9.2 仍待你定（不阻塞动工）

| # | 待定 | 我会先怎么做 |
| --- | --- | --- |
| 1 | 前情提要文案、分几段 | 填 3 段占位文字 |
| 2 | CG 一共几张、在哪些节点解锁 | 建 2 张占位（用 `icon.svg`），把管线跑通 |
| 3 | 背景宽度 / 地面线高度 / 人物显示高度 | 灰盒用纯色块，尺寸随手定；素材到了在长卷调参台对 |
| 4 | 左眼金纹两个朝向的偏移、朝左是否可见 | 导出属性留空，等素材到位在编辑器里拖 |
| 5 | `courtyard_01` 的剧情链 | Director 先只挂占位调查物，不写因果 |

---

## 10. 下一步

按 §8 的六步顺序动工。前三步（相机 + 禁跳 + 表现层退化路径、灰盒关卡骨架、
前情提要与主菜单三入口）不依赖任何待定项，可以一口气做完并验证。

第四步（global store + GalleryManager + 画廊 UI）也不依赖待定项——用占位 CG
就能验证跨档保留和"删存档不影响画廊"。

第五步开始才需要你的剧情与美术输入。

---

## 10. 实施记录与占位数值（2026-08-26）

### 占位数值（后期改这里）

| 项 | 占位值 | 定在哪 | 备注 |
| --- | --- | --- | --- |
| courtyard_01 世界 | 4608 × 648（正好 4 屏宽） | `courtyard_01.tscn` 的 Background 与相机 `world_bounds` | 220 px/s 走完约 21 秒 |
| courtyard_02 世界 | 3456 × 648（3 屏） | 同上 | |
| 地面线 | y = 560 | 两关的 Ground 碰撞体 | |
| 出生点 | x = 200 | SpawnPoint | |
| `move_speed` | 220 | 关卡里 Player 实例的覆盖值 | 平台跳跃默认是 300，这里按"缓行"调慢 |
| 玩家碰撞盒 | **保持 32 × 48 不动** | `player.tscn` | 改它会牵动脚底原点约定与存档迁移，等美术素材到位后连同显示高度一起定 |
| 前情提要 | 3 段占位文案 | `prologue.tscn` 的 `segments` 导出属性 | 直接在编辑器里改 |
| CG | 2 张占位（用 `icon.svg`） | `resources/cg/cg_placeholder_0*.tres` | id 还没进过玩家存档，可自由改名 |
| 出口门槛 | 占位：拿到山鸟簪才能进里院 | `courtyard_01_story_director.gd` | 剧情定稿后换真条件 |

### 与设计的偏差

1. **`required_memory` 下沉到 `Interactable` 基类。** 设计里它在 `StoryDoor` 上，
   但 `LevelExit` 也要用信物门槛——出现第二个消费者，这个抽象就该在基类。
   纯增量（默认空值），`StoryDoor` 反而变简单了。
2. **关卡脚本合并成一个 `CourtyardLevel`（`courtyard_level.gd`）。**
   courtyard_02 的关卡侧机制和 01 完全一样，共用一份省得改一处忘一处。
3. **`SaveManager.save_progress()` 多了 `use_level_spawn` 参数。** 跨关卡切换时
   我们不知道下一关的入口在哪，必须让它用自己的 SpawnPoint，否则会把 `(0,0)`
   当真坐标钉进存档——这正是之前修过的那个 bug 的翻版。
4. **`Player` 加了 `class_name` 和 `get_facing()`。** 前者让 `PlayerVisual` 能
   静态引用 `Player.State`，后者让表现层进场时能先对齐一次朝向
   （`direction_changed` 只在变化时发）。
5. **顺手修掉一处既存的测试不确定性。** `test_old_courtyard.gd` 的落点断言原来用
   `is_equal_approx`，而玩家是受重力的 CharacterBody2D，放置到断言之间跑几个
   物理帧不固定、每帧下坠约 0.4px。改成距离判定，连跑 4 次稳定通过。

### 素材接入点（美术到位后动这三处）

- `player.tscn` → `PlayerVisual/Sprite`（AnimatedSprite2D）填 SpriteFrames：
  `liniang_idle.png` 4 帧、`liniang_walk.png` 6 帧，按你的交付规范横向切。
  填上之后灰盒 Polygon2D 会自动隐藏，不用改代码。
- `walk` 帧率与 `move_speed` 是一对，步频和位移不匹配会有滑步感——
  建议在 `tests/bg_pacing/` 那个调参台里对，定下来再抄回场景。
- 人物显示高度 + 碰撞盒高度 + `move_speed` 三者要一起定，同上。
