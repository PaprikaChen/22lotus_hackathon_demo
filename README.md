# 《二十二莲境》Demo 开发说明

Godot 4.4（Forward Plus）2.5D 中式心理恐怖 / 叙事探索游戏，当前处于 **Demo 原型**阶段。
本文件是上手与现状说明：**已实现什么、核心玩法是什么、亮点在哪**。

| 想知道 | 看哪份文档 |
| --- | --- |
| 项目是什么、目录约定、Agent 能独立决定什么 | [CLAUDE.md](CLAUDE.md) |
| 改代码时**不许**做什么（约束清单、复用指引） | [AGENTS.md](AGENTS.md) |
| 系统之间**如何咬合**、状态归谁、数据怎么流 | [ARCHITECTURE.md](ARCHITECTURE.md) |
| 叙事层（StoryDirector / Cutscene / Flag）设计 | [NARRATIVE_LAYER_DESIGN.md](NARRATIVE_LAYER_DESIGN.md) |
| 第一关的关卡设计文档 | [COURTYARD_01_DESIGN.md](COURTYARD_01_DESIGN.md) |

---

## 一、如何运行

- 直接运行项目（`F5`）：主菜单 → `新游戏` / `读取存档` / `画廊`。
  - 新游戏 → 前情提要（黑幕逐段文字，Space 推进）→ `courtyard_01`。
  - 读取存档 → 直接进存档记录的场景与坐标。
- 单关调试：在编辑器里打开 `res://scenes/levels/<关卡>.tscn`，`F6` 运行当前场景。
- 灰盒 / 回归测试房在 `tests/`（见 [tests/README.md](tests/README.md)），
  各测试场景自报 PASS / FAIL。**不要在正式关卡里测基础系统。**

操作：移动 `A/D` 或 `←/→`，跳跃 `Space`，梦境减速 `Shift`，交互 `E`，
梦奁 `Tab`，暂停 `Esc`。2.5D 深度关卡额外用 `W/S`（横版关卡忽略）。

---

## 二、核心玩法

Demo 的玩法由**四条线**交织，不是单纯的平台跳跃：

1. **横版探索 + 调查**
   长卷背景的院落一路向前走，`E` 调查场景中的物件。文字统一走底部共用对话框
   （分页、Space 推进、显示期间锁玩家输入），部分调查点带**分支选项**
   （偷听 / 不偷听、翻窗 / 不翻窗），选择只影响演出与阅读分支，不做失败惩罚。

2. **梦境减速（DreamGap）**
   `Shift` 开启：**世界慢到 25%，玩家仍是 100%**，持续 3 秒、冷却 2 秒。
   全程不使用 `Engine.time_scale`——世界对象自己按帧来取被缩放的 delta，
   所以 UI、存档、玩家手感天然不受影响。

3. **环境解谜**
   - 三重旋锁（`courtyard_01` 尾）：鼠标拖动内 / 中 / 外三层转盘拨档，
     点「解锁」才结算；配合「走进去就回不了头」的返回封锁 + 黑幕重置机关。
   - 顺序解谜（`interior_01`）：按正确顺序点击物品，答案是编辑器里的数组顺序。
   - 障碍清理（拔草、瓦砾）与门槛门（需要某个剧情 Flag 或某件信物才开）。

4. **记忆收集：梦奁**
   `Tab` 打开梦奁抽屉，查看已获得的信物。同一件信物可以被剧情**推进阶段**
   （描述随故事改变），而不是塞进一堆重复道具。另有跨存档共享的 **CG 画廊**
   （从主菜单直接进，未解锁只显示 `？？？`，不剧透标题）。

---

## 三、已实现的部分

### 1. 流程与关卡

```
MainMenu ──新游戏──▶ SaveSlotMenu ──▶ Prologue ──▶ courtyard_01
   │                                                   │
   ├──读取存档──▶ 存档记录的场景                        ▼
   └──画廊──────▶ GalleryScreen              courtyard_02 ─▶ courtyard_03 ─▶ courtyard_04
                                                     │(香炉记忆)          │(翻窗)
                                             incense_memory        interior_01 ─▶ interior_02
```

- `courtyard_01`（前院）：调查点、拔草放开西侧镜头、西窗偷听分支、
  尾部三重旋锁小关卡（含返回封锁 + 相机待落闸门）。
- `courtyard_02`（里院）：屏风与信笺调查、纸面叠层演出。
- `courtyard_03`：三处调查对白；灯笼区触发**香炉记忆**子关卡
  （香炉 → 木马 → 岁安绦依次开放，白幕居中文字演出），回来后镜头右闸门撤除、
  玩家落回指定坐标继续前行。
- `courtyard_04`：首次靠近花圃触发甜香 + 短暂失焦，之后开放花圃调查；
  破窗处二选一进入室内。
- `interior_01`：药碗调查 → 失焦 → 黑幕 → 定格 CG 回忆 → 黑底解说；
  架子顺序解谜解开后露出未寄出的信；按世界 X 分段的**去色 / 上色**表现。
- `interior_02`：**十幕皮影戏舞台**。每幕贴图动态加载 / 释放
  （`CACHE_MODE_IGNORE`，不让十幕常驻），玩家换成皮影表现件，黑幕换幕。
- 早期关卡 `old_courtyard` / `main_house_interior` 仍在库内，作为多区域流转
  （一个场景内多屏、不切场景）的参考实现。

### 2. 全局系统（Autoload）

| Autoload | 拥有 | 落盘 |
| --- | --- | --- |
| `SaveManager` | 全部 `user://` 文件 I/O、3 个槽位、版本迁移（`SAVE_VERSION = 2`）、跨槽全局存储 | 整个存档文件 |
| `WorldTimeManager` | DreamGap 状态机（`READY/ACTIVE/COOLDOWN`）与 `world_time_scale` | 不入档 |
| `StoryFlagManager` | 剧情 Flag（persistent / session 两层） | 槽位字段 `story_flags` |
| `MemoryManager` | 梦奁信物运行时状态 + `.tres` 静态注册表 | 槽位字段 `memories` |
| `GalleryManager` | CG 解锁 / NEW 角标 | **全局** `user://gallery.json`（跨槽共享） |

存档写盘走 `.tmp` → 删旧 → rename 三步，中断不毁档；缺字段 / 坏 JSON 不崩溃。

### 3. 角色与关卡框架

- `Player`（`CharacterBody2D`）+ `DreamGapAbility` + `InteractionDetector` 三件分离；
  **原点在脚底**；输入锁**带来源**（对话 / 梦奁 / 暂停 / 演出各持一把，互不干扰）。
- 两种移动模式由关卡声明：`SIDE_SCROLL`（重力 + 跳跃）与 `DEPTH_2_5D`
  （无重力、y 表示纵深）。玩家脚本里没有任何 `if 场景名 == ...`。
- `LevelBase` 统一进关生命周期：重置 DreamGap → 清 session flag → 下发移动模式 →
  放置玩家（存档位置优先，否则 SpawnPoint）→ 发 `level_started`。

### 4. 交互与叙事层

- `Interactable` 基类（`one_shot`、优先级、`required_flag` / `required_memory` 门槛）
  与一整套子类：文本调查、分支调查、拾取、信物拾取、门、出口、存档点、
  障碍清理、顺序解谜。
- 每个正式关卡挂一个自己的 **StoryDirector**（不是 Autoload），
  剧情因果全部汇聚在这里；每个剧情节点写成
  `_on_<事件>()`（现场、一次性）+ `_apply_<节点>()`（幂等摆终态、无表现）两个函数，
  **保证读档不重播演出**。

### 5. UI 与表现件

主菜单 / 存档槽 / 前情提要 / 暂停菜单 / 共用对话框（带立绘与旁白两种版式）/
梦奁 UI / 信物 Toast / 交互提示 / 画廊 / 三重旋锁界面 /
影院黑边 `FrameBars` / 屏幕淡入淡出 `ScreenFade` / 白幕居中文字 `NarrationOverlay` /
定格 CG `CGSequence` / 全屏失焦 `FocusBlur`；
Shader：饱和度着色、发光描边、失焦模糊。
世界件：长卷背景 `Backdrop`（按世界高度反推 scale）、跟随相机（内建 limit 贴边）、
拱桥地形、眼神跟随、花枝摇曳、皮影表现件、移动平台与巡逻危险物。

---

## 四、亮点

- **一条纪律贯穿全项目：拉取，不推送。** 没有任何管理器遍历场景树去控制对象；
  时间倍率、存档数据、信物状态都由需要的对象自己来取。
  删掉任何一个关卡，全局层不需要改一行代码。
- **信号单向出、调用单向入。** 表现层只监听信号，管理器永远不知道表现节点存在——
  所以「减速时整屏变蓝」这类美术接法可以随时加删，时间管理器不动。
- **静态数据 / 运行时状态 / 存档三分。** 文案与资源在 `.tres`，运行状态在 Autoload
  内存，落盘只有一小撮原始类型。信物文案改多少次都不影响旧存档。
- **读档不重播演出。** 叙事层强制「现场链路」与「恢复链路」分成两个函数，
  恢复只摆终态。这是叙事驱动游戏最容易出错的地方，在架构层面被消除了。
- **减速不动 `Engine.time_scale`。** 局部时间倍率让「世界慢、玩家不慢」成为
  机制本身，而不是靠一堆补偿代码。
- **数值集中化。** 旋锁小关卡、皮影十幕这类机关的全部数值收在
  `scripts/globals/*_config.gd` 里，场景与组件都从这里读，避免「改一处忘一处」。
- **演出件各司其职。** `FocusBlur` / `ScreenFade` / `CGSequence` / `NarrationOverlay`
  只管画面，不锁玩家、不写 Flag、不切场景——编排权始终在 StoryDirector。
- **可测。** `tests/` 下有 13 个灰盒 / 回归测试房，覆盖移动、减速、交互、梦奁、
  存档读写、`courtyard_01`、`interior_02` 等，自报 PASS / FAIL，可 headless 运行。
- **编辑器友好。** 手感与节奏参数全部 `@export`；`ArchBridge`、`Backdrop`、
  `FrameBars` 带 `@tool`，在编辑器里拖参数即时看到结果。

---

## 五、目录结构

```
res://
├── scenes/
│   ├── ui/            主菜单 / 存档槽 / 前情提要 / 暂停 / 对话框 / 梦奁 / 画廊 /
│   │                  旋锁 / 黑边 / 淡入淡出 / 白幕 / 失焦
│   ├── player/        player.tscn + DreamGapAbility + InteractionDetector + 表现
│   ├── levels/        LevelBase + courtyard_01..04 + 香炉记忆 + interior_01/02
│   │                  （每关一个 *_story_director.gd）
│   ├── components/    世界对象（移动平台 / 巡逻危险物）
│   └── props/         环境装饰
├── scripts/
│   ├── autoload/      5 个全局管理器（常驻，不持有节点引用）
│   ├── components/    跨关卡复用组件（Interactable 子类、相机、背景、机关、表现件）
│   ├── narrative/     StoryDirector / Cutscene / StoryNPC
│   ├── ui/            UI 与演出件脚本
│   ├── memory/        MemoryEntry / MemoryStage（Resource 定义）
│   ├── gallery/       CGEntry
│   └── globals/       纯数据与枚举（MovementMode / 旋锁配置 / 皮影配置）
├── resources/         memories/*.tres（自动注册）、cg/*.tres、sprite_frames/
├── shaders/           effects/（饱和度、描边）、ui/（失焦模糊）
├── assets/            art/（backgrounds / sprites / cg / tilesets）、audio/、fonts/
├── tests/             灰盒测试房 + helpers/
├── addons/godot_ai/, addons/godot_mcp_toolkit/   编辑器 MCP 插件（第三方，勿改）
└── project.godot      autoload / input map / main_scene
```

**新文件放哪**：两个以上关卡会用 → `scripts/components/`；只服务一个关卡 →
和关卡放一起；只服务测试 → `tests/`。

---

## 六、Input Map

| Action | 默认按键 | 说明 |
| --- | --- | --- |
| `move_left` / `move_right` | A/← 、D/→ | 横向移动 |
| `move_up` / `move_down` | W/↑ 、S/↓ | 仅 `DEPTH_2_5D` 关卡读取 |
| `jump` | Space | 仅 `SIDE_SCROLL` |
| `slow_time` | Shift | DreamGap，再按一次提前结束 |
| `interact` | E | 交互 |
| `open_memory_box` | Tab | 梦奁 |
| 暂停 / 关闭 | Esc（`ui_cancel`） | 暂停菜单、关闭叠层 |
| 推进文字 | Space（`ui_accept`） | 对话框 / 前情提要 / 白幕 / CG |

> 修改 Input Map、Autoload、渲染或导出设置前**必须先问**（见 CLAUDE.md 安全规则）。

---

## 七、已知缺口与技术债

- 美术仍有占位（部分灰盒 ColorRect / Polygon2D、placeholder 贴图）。
- `resources/memories/` 下混有 5 个测试信物（`whitebox_25d_*`、`bg_pacing_token_*`），
  会出现在梦奁 UI 里，正式发布前要清。
- `test_level.gd` / `dream_platforming_test.gd` 仍是裸 `Node2D`，未迁到 LevelBase，
  且已无处引用，待决定迁移还是删除。
- `play_time_seconds` 只在 `test_level.gd` 里累计，正式关卡存档时长不增长。
- 场景切换散落在多处 `change_scene_to_file()`，尚未抽 SceneManager
  （有明确需求前不提前造）。
- 音频接入尚浅：SFX / BGM 目录已建，旋锁档位音等少量事件已接。
- Player 进阶能力（二段跳、冲刺、攀墙）未实现，接口已留。
