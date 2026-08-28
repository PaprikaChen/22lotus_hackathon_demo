# AGENTS.md — 《二十二莲境》Agent 开发规范

本文件是所有 Agent 修改本项目前必读的规范。内容基于项目**当前真实状态**编写，
随项目演进保持更新。与 `CLAUDE.md` 冲突时，以本文件中更具体的规则为准。

---

## 0. 项目现状快照（2026-08-26，勿凭猜测推翻）

- 引擎：Godot 4.4.1-stable，Forward Plus。
- 主场景：`res://scenes/ui/MainMenu.tscn`。
- Autoload（除插件外）：
  - `SaveManager` → `scripts/autoload/save_manager.gd`
  - `WorldTimeManager` → `scripts/autoload/world_time_manager.gd`
  - `StoryFlagManager` → `scripts/autoload/story_flag_manager.gd`
  - `MemoryManager` → `scripts/autoload/memory_manager.gd`
  - `GalleryManager` → `scripts/autoload/gallery_manager.gd`（画廊 CG 收集，
    **跨存档槽**，落盘在全局 `user://gallery.json`，不进存档槽格式）
  - `_mcp_game_helper` → godot_ai 插件基础设施，勿动。
- 已实现并可运行的系统：
  - 玩家平台移动：`scenes/player/player.gd`（CharacterBody2D，移动/跳跃/重力
    /出生点/respawn/轻量状态枚举/带来源输入锁/移动模式开关）。子组件：
    `scenes/player/dream_gap_ability.gd`（DreamGap 输入与 UI 信号门面）、
    `scenes/player/interaction_detector.gd`（交互目标选择）。
  - 世界变慢（DreamGap）：`WorldTimeManager`，**方案 A：局部时间倍率**。
    从未使用 `Engine.time_scale`，不要引入它。含 `reset_state()`
    （读档/切场景/死亡时强制恢复，LevelBase 和 SaveManager 会调用）。
  - 存档/读档：`SaveManager`，3 个槽位，JSON 写入 `user://save_slot_%d.json`。
    含 `save_version`（当前 2，旧档读为 0/1 并自动迁移）、临时文件安全写入、
    `story_flags` 汇总。
  - 剧情 Flag：`StoryFlagManager`（persistent/session 两层，接入存档）。
  - 梦奁（记忆信物）：`MemoryManager`（Autoload）管理运行时状态；静态数据为
    `resources/memories/*.tres`（MemoryEntry/MemoryStage Resource，
    `scripts/memory/`）；UI 为 `scenes/ui/memory_box_ui.tscn`（Tab 开关、
    Esc 关闭、开启时暂停世界并锁玩家输入）+ `memory_toast.tscn`（队列提示）。
    存档字段 `memories` 只存 {unlocked, current_stage, unread_state}，
    绝不存文案。信物 id 一经入档不得改名；同一信物剧情推进用
    `advance_memory()` 换阶段，禁止建重复道具。
  - 交互：`scripts/components/interactable.gd`（Interactable 基类：优先级/
    一次性/Flag 门槛/替代反馈）+ 玩家 InteractionDetector。
  - 受减速影响的对象：`scenes/components/moving_platform.gd`（AnimatableBody2D）、
    `scenes/components/test_enemy.gd` —— 均通过主动调用
    `WorldTimeManager.get_scaled_delta(delta)` 接入，**不是 Group、不是遍历场景树**。
    新对象改用 `scripts/components/dream_affected_component.gd` 统一接入。
  - 移动模式：`scripts/globals/movement_mode.gd`（`MovementMode.Mode`：
    `SIDE_SCROLL` / `DEPTH_2_5D`）。**由关卡决定**：LevelBase 的
    `movement_mode` 导出属性在 `_ready` 里下发给玩家，禁止用场景名判断。
    SIDE_SCROLL 是默认值，是原有横版路径，一行未改；DEPTH_2_5D 下 y 变成
    纵深轴、无重力无跳跃、body 切 `MOTION_MODE_FLOATING`、纵深速度
    `depth_move_speed` 远低于 `move_speed`。只有移动代码知道这个枚举，
    存档/信物/交互/对话/切场景一律不许感知。验证房见
    `tests/whitebox_25d/`。
  - 关卡基类：`scenes/levels/level_base.gd`（LevelBase：出生点/存档恢复/
    进关重置 DreamGap 与 session flags/移动模式下发/生命周期钩子）。
  - 章节关卡：`scenes/levels/old_courtyard.tscn/.gd`（旧院灰盒，三个
    **一屏宽（1152px）**探索区域同场景，相机每区固定，走到窗口右缘切换）。
    区域流转由 `scripts/components/area_flow_controller.gd` 管理，**双向**：
    右缘 ExitTrigger 前进（落在下一区左侧 SpawnPoint）、左缘 ExitTriggerLeft
    后退（落在上一区右侧 SpawnPointRight），淡入淡出+传送+相机 limit，
    输入锁来源 "area_switch"；首区无左触发器、末区无右触发器。每个区域挂
    `exploration_area.gd`（局部坐标+相机边界，默认一屏宽，拖动区域节点即可
    整体搬移）；纯文本剧情物用 `text_interactable.gd`（文案存节点导出属性）。
  - 对话/交互文本框：`scenes/ui/dialogue_box.tscn/.gd`（屏幕底部半透明框，
    左侧可选立绘位，**分页显示**：`show_text(text, portrait, speaker)` 按行
    拆成句子，空格/ui_accept 逐句推进，末句后自动关闭并发 `closed` 信号；
    显示期间用 `begin_interaction(&"dialogue_box")` 锁玩家，空格不会触发
    跳跃）。**所有**交互与对话文字统一走这个框，禁止各处自画浮动文字。
    "读完文字后触发某事"（如旧院侧窗进屋）监听 `closed` 信号 + pending 标记。
  - 表现层示例：`scripts/components/slow_time_visual_test.gd`（CanvasModulate，
    纯 Signal 单向监听）、`scripts/components/slow_time_debug_ui.gd`（调试 Label）。
  - 关卡：`scenes/levels/test_level.gd`（存读档测试）、
    `scenes/levels/dream_platforming_test.gd`（平台跳跃测试，含 LevelPhase 枚举、
    出生点、DeathZone）—— 两者为旧结构，暂未迁移到 LevelBase。
  - UI：`scenes/ui/main_menu.gd`、`scenes/ui/save_slot_menu.gd`（所有文件 I/O
    经 SaveManager，UI 不直接碰文件系统）。
  - 测试场景：`tests/`（movement / dream_gap / interaction / save_load 四个
    单项 + integration 综合灰盒关卡 + `whitebox_25d/` 2.5D 白盒验证房；
    自动断言打印 `[TEST:*] PASS/FAIL`，无头模式自动退出）。
    `tests/helpers/` 里的钥匙/门/存档点是新交互物的参考实现。
- 叙事编排：`scripts/narrative/`（`StoryDirector` / `Cutscene` / `StoryNPC`
  三个基类）。每个正式关卡挂一个自己的 Director（普通节点，**不是 Autoload**），
  剧情因果链集中在那里。首个实现：
  `scenes/levels/old_courtyard_story_director.gd`。详见第 5.5 节。
- 正式交互物组件：`scripts/components/` 下的 `story_door.gd`（StoryDoor）、
  `memory_pickup.gd`、`flag_pickup.gd`、`save_point.gd`、`text_interactable.gd`、
  `level_exit.gd`（去下一关）、`follow_camera.gd`（横版跟随相机）。
  门槛（`required_flag` / `required_memory`，两个都填就都要满足）在
  `Interactable` **基类**里，不要在子类里重复实现。
- courtyard_01 尾部小关卡（2026-08-28）：走到场景尾部后回不了头，门上一把
  三重旋锁挡住去 courtyard_02 的路。**全部数值集中在
  `scripts/globals/inner_gate_lock_config.gd`（InnerGateLockConfig）**——
  触发/重置/硬边界/重生 x、22.5° 档位与半档阈值、各段时长、谜底序列、
  解锁 Flag 名，别在别处再抄一份。组成：
  - `scripts/components/backtrack_trap.gd`（BacktrackTrap）：x>=7900 一次性
    激活、x<=7800 黑幕重置回 x=8300、x=7750 硬边界墙（开关 StaticBody2D 的
    碰撞层，**不每帧改玩家坐标**）。输入锁来源 `backtrack_reset`。
    激活时 Director 给相机挂一道**走过就落闸**的左闸门
    （`FollowCamera2D.arm_left_gate_latch(7700)`）：等画面最左侧自己走到 7700
    才落闸，边界正好压在当前画面左缘上，画面不会跳；之后西边的视野也让不回来。
    **它和西侧杂草共用 FollowCamera2D 的同一层闸门**，所以解锁时不能
    `release_left_gate()`，要撤掉待落闸门 + 重跑 `_apply_west_passage()`
    把边界交还给杂草的规则。
    被送回来的那句字幕只出第一次（`reset_text_once`），之后直接黑幕重生；
    首次走进尾部区域不出字幕。
    Director 解锁后调 `disarm()`，旧触发器留在场景里也不再生效。
    门（`Props/ToNextLevel`）的交互点在 x=9000。
  - `scripts/ui/screen_fade.gd` + `scenes/ui/screen_fade.tscn`（ScreenFade，
    layer 95）：**项目唯一可复用的全屏淡入淡出**，`fade_out()` / `fade_in()`
    均可 await，重入自动掐掉上一个 Tween。只管画面黑白，不锁玩家不切场景。
  - `scripts/ui/rotary_lock_ui.gd`（RotaryLockUI）+ `rotary_lock_ring.gd`
    （RotaryLockRing）+ `scenes/ui/rotary_lock.tscn`（layer 70）：三层共用
    同一个 ring 脚本（四叶草 / 圆环 / 瓷瓶三种占位画法），命中按
    内→中→外询问 `contains_point()`，外层花瓣不遮挡里层；判定依据是
    **逐档输入序列**（层 / 方向 / 档数），不是最终角度。换正式美术只需给
    ring 的 `visual_texture` 挂图，旋转逻辑不动；音效是两个独立
    AudioStreamPlayer（`detent_sfx` / `unlock_sfx`，**当前无素材，安全静默**）。
  - 门本身仍是 `LevelExit`：`required_flag` = `courtyard_01.inner_gate_unlocked`，
    锁着时按 E 走基类的 blocked 路径 → Director 接 `interaction_blocked`
    弹锁界面；`solved` → Director 写 Flag（**唯一写它的地方**）→
    `_apply_inner_gate_lock()` 摆终态。读档恢复走同一条路。
  - 回归：`tests/test_courtyard_01.gd`（陷阱 / 档位 / 判定 / 门槛，headless
    可跑）；`tests/test_rotary_lock_view.tscn` 是占位视觉的肉眼检查房。
- 正式关卡：`courtyard_01` / `courtyard_02`（共用关卡脚本
  `scenes/levels/courtyard_level.gd`，各有自己的 StoryDirector）。
  新游戏入口 = `SaveManager.NEW_GAME_SCENE_PATH` → courtyard_01，
  之前先播 `PROLOGUE_SCENE_PATH`（前情提要）。旧院降级为参考实现。
- 玩家表现层：`scenes/player/player_visual.gd`（PlayerVisual）——只听
  `state_changed` / `direction_changed`，把状态映射到动画、朝向映射到 `flip_h`。
  **移动逻辑不得依赖动画资源名**，映射表只存在于这个文件。素材没接上时自动
  退化为灰盒 Polygon2D。
  `tests/helpers/` 只剩纯测试脚本，正式关卡不再从测试目录引用实现。
- 立娘 Sprite（已接上，2026-08-27）：`assets/art/sprites/liniang/` 的
  `liniang_idle.png`（4 帧）/ `liniang_walk.png.png`（6 帧）横向排列的精灵图，
  切分为 `resources/sprite_frames/liniang.tres`（AtlasTexture，idle 3fps /
  walk 6.67fps，都循环）。**素材交付规范**（改素材必须同步这几个数）：
  单帧 512x512、只画朝右一套（朝左由 `flip_h` 镜像）、人物脚线在单帧
  y=484、头顶 y≈15、身体中轴对齐单帧横向中心 x=256。
  player.tscn 里 `PlayerVisual/Sprite` 用 `centered = true` +
  `offset = (0, -228)` 把脚线钉在 Player 原点（原点 = 着地点），
  `scale = 0.36` 得到约 168px 高的人物；碰撞盒 `RectangleShape2D` 44x160、
  `position = (0, -80)`，整体站在原点之上。人物在画面里的大小 = `scale`
  这一个数，调手感只动它 + 碰撞盒高度，别去改 offset。
  INTERACT 目前没有单独素材，player.tscn 里把 `anim_interact` 指回 `idle`。
  验证房：`tests/test_player_visual.tscn`（24 条断言：帧数/图集切分/脚线对位/
  A 左 D 右 → walk、松手 → idle、flip_h）。
- 截图调试工具：`tests/helpers/capture_scene.gd/.tscn` —— 开窗跑任意场景、
  等若干帧、存 PNG 后退出（无头模式不渲染，必须开窗）。用来肉眼检查
  人物大小/脚线/朝向这类断言判断不了的东西：
  `Godot --path . --resolution 1152x648 res://tests/helpers/capture_scene.tscn
  -- --scene=res://scenes/levels/courtyard_01.tscn --out=user://shot.png
  --frames=40 [--hold=move_right]`。
- **尚未实现**（不要假装存在，也不要在没有任务要求时顺手创建）：
  SceneManager（场景切换目前直接使用 `get_tree().change_scene_to_file()`）、
  独立的 PlayerStateMachine 脚本（当前为 player.gd 内的轻量枚举，够用前不拆）、
  暂停菜单、全局 EventBus（**明令禁止**，Signal 直连 Director 已够用）、
  Quest / Narrative Graph / Story DSL 之类的大型叙事框架（**明令禁止**）。
- 输入动作：`move_left`(A/←) `move_right`(D/→) `move_up`(W/↑)
  `move_down`(S/↓) `jump`(空格) `slow_time`(**Shift**) `interact`(E)
  `open_memory_box`(Tab)（见 `project.godot`）。`move_up`/`move_down`
  只有 DEPTH_2_5D 移动模式会读，横版关卡完全无视它们。

## 1. General

- 修改代码前必须先检查相关场景和脚本的**实际内容**，优先通过 Godot AI MCP
  读取真实状态，不要凭文件名或旧上下文推测。
- 不要创建功能重复的 Manager、Autoload 或组件。新建任何 Manager 前，先确认
  `SaveManager`、`WorldTimeManager` 是否已覆盖该职责。
- 不要无理由修改已有公共 API（函数签名、Signal、Autoload 名称）。
- 不要无理由重命名已有文件、节点、Signal、资源路径和存档字段。
- 不要修改与当前任务无关的文件。
- 一个脚本只承担一种主要责任。
- 优先使用组合，不建立过深的继承结构；不要为了使用继承而使用继承。
- 避免硬编码绝对节点路径；优先使用类型明确的 `@export` 变量、`@onready`
  引用和 Signal。
- 所有新增脚本使用 typed GDScript（参数、返回值、变量都带类型标注），
  并在文件头写 `##` 文档注释说明职责边界（沿用现有脚本的风格）。
- 所有持久化 ID（存档字段名、checkpoint_id、未来的 story flag 名）一旦
  写入过存档，不得随意更改。
- 不要编辑 `.godot/` 下的文件；不要修改 `addons/godot_ai/` 内部；
  不要直接修改美术源文件。
- 修改过程中始终保持项目处于可启动状态。

## 2. Player（`scenes/player/player.gd`）

- 玩家基础移动、跳跃、重力、地面检测、移动参数、出生点/respawn 属于玩家
  控制脚本（未来拆分后属于 PlayerController）。
- 玩家**永远使用真实 delta**，绝不调用 `get_scaled_delta()` —— 这就是玩家
  不被世界减速影响的机制，不存在"补偿"代码，不要添加补偿代码。
- 玩家脚本对世界变慢只做一件事：检测 `slow_time` 输入的上升沿并调用
  `WorldTimeManager.request_slow_time()` / `stop_slow_time()`。持续时间、
  冷却、状态机全部在 WorldTimeManager 内，不要搬回玩家脚本。
- 剧情 Flag、对话内容、存档格式、世界减速实现、UI 显示，都不允许写进
  玩家脚本。
- 对话、过场、菜单必须通过玩家的**带来源输入锁**控制玩家：
  `lock_input(&"dialogue")` / `unlock_input(&"dialogue")`，全部锁解除才恢复
  控制。不要让各系统直接翻转 `can_move` 之类的布尔值。交互/对话流程用
  `begin_interaction()` / `end_interaction()` 配对（状态显示 INTERACT）。
  LevelBase 进关时调用 `clear_input_locks()` 兜底，防止锁跨场景残留。
- **原点约定**：玩家节点原点是**脚底（接触地面的那一点）**，不是身体中心。
  横版模式下碰撞盒站在原点之上（`CollisionShape2D` 偏移 -24），2.5D 模式下
  改用居中于原点的浅脚印（`DepthCollisionShape2D`，32×28），两者由
  `_apply_mode_geometry()` 按模式互斥启用；交互范围同理（横版挂在身体中心、
  纵深挂在接触点）。因此出生点 Marker、存档坐标、传送坐标一律表示“角色站的
  那一点”。要读取当前模式下的半高/半宽用 `get_body_half_extents()`，
  **不要硬编码 24**。改动玩家碰撞几何必须同步这条约定和存档迁移。
- 移动模式（`MovementMode.Mode`）只允许由关卡通过
  `player.set_movement_mode()` 设置（LevelBase 已代劳）。玩家脚本内部**不许**
  出现 `if 当前关卡名 == ...` 之类的判断；其他系统（存档、信物、交互、对话、
  切场景）不得读取 `movement_mode`。新增移动手感参数时，横版参数与纵深参数
  分开导出，不要让一套数值同时服务两种模式。
- 状态机为 player.gd 内的轻量枚举 `State { IDLE, RUN, JUMP, FALL, DISABLED,
  INTERACT }` + `signal state_changed(previous_state, current_state)`。
  动画/音效监听该信号；移动逻辑不得依赖具体动画资源名称。在明确需要前
  不拆成独立状态脚本，不建层级状态机。

### 输入检测约定（重要）

玩家侧输入（player.gd 的跳跃、DreamGapAbility 的能力键、
InteractionDetector 的交互键）都用 `Input.is_action_pressed()` + 手动
上升沿追踪，**故意不用** `is_action_just_pressed()`：godot-ai MCP 的输入
注入只能注入按住状态、无法产生 just_pressed 边沿，手动边沿检测让真实键盘和
自动化测试走同一条代码路径。新增"按一下触发"的动作请沿用这个模式。

## 3. DreamGap / 世界变慢（`WorldTimeManager`）

游戏的世界变慢能力统一命名为 **DreamGap**。当前实现载体是 Autoload
`WorldTimeManager`，重命名前需用户明确许可。

**当前架构是方案 A（局部时间倍率），必须保持：**

- `Engine.time_scale` 从未被使用。**不要引入它**，也不存在需要迁移的兼容层。
- 世界对象通过在自己的 `_physics_process` 中调用
  `WorldTimeManager.get_scaled_delta(delta)` 主动拉取缩放后的 delta。
  这是唯一的接入方式，天然保证 UI、存档、暂停菜单、玩家不受影响
  （它们不调用它就不受影响）。
- 状态机：`READY → ACTIVE → COOLDOWN → READY`，持续时间和冷却用真实
  时间在 `_process` 中计算，无额外 Timer 节点。
- 防重复激活已内建：`request_slow_time()` 非 READY 时返回 false。
- 已有 Signal（表现层只允许通过这些监听，禁止反向耦合）：
  `slow_time_started`、`slow_time_ended`、
  `slow_time_state_changed(new_state)`、
  `slow_time_energy_changed(active_remaining, cooldown_remaining)`。

规则：

- 世界减速和视觉显形效果保持可分离（参考 `slow_time_visual_test.gd`：
  纯 Signal 单向监听，Manager 不知道表现节点的存在）。
- 不允许任何脚本逐个查找并控制敌人或平台；不要每帧遍历场景树寻找受影响
  对象。新对象自己拉取 scaled delta，或未来通过统一组件接入。
- 新增的敌人/平台/机关通过 `DreamAffectedComponent`（子节点）统一接入：
  `enum DreamEffectType { TIME_SCALE, VISUAL_REVEAL, BOTH }`、
  `custom_time_scale`（<0 用全局倍率）、`get_scaled_delta(delta)`、
  开启/关闭 Signal 回调、`auto_apply_reveal` 自动切换父 CanvasItem 可见性。
  它内部基于 WorldTimeManager，不是第二套时间系统。旧对象
  （moving_platform / test_enemy）直连 manager，保留不强迁。
- 玩家侧 `DreamGapAbility` 组件只负责输入、激活/提前结束请求和 UI 信号
  （`ability_started/ended`、`cooldown_*`、`duration_changed`）。持续时间
  与冷却的状态机**留在 WorldTimeManager**（充当 DreamGapManager 角色），
  不要把计时逻辑搬进能力组件或玩家脚本。能力 UI 一律监听 DreamGapAbility。
- 场景切换、玩家死亡、读档、返回主菜单时不得残留 ACTIVE 状态：调用
  `WorldTimeManager.reset_state()`。LevelBase `_ready` 和
  `SaveManager.load_game()` 已自动调用；不走 LevelBase 的旧场景或自定义
  流程必须自行调用。
- DreamGap 的临时激活状态不写入存档；读档后应处于未激活状态。

## 4. Save System（`SaveManager`）

- 现有存档/读档功能已测试可用，**必须保持兼容，不要重写**。
- 存档文件：`user://save_slot_%d.json`，槽位 1–3，JSON 格式。
- 现有字段（一个都不许改名）：`save_slot_id`、`created_at`、
  `last_saved_at`、`current_scene`、`checkpoint_id`、`player_position_x`、
  `player_position_y`、`play_time_seconds`。
- 字段 `use_level_spawn`：新档写 `true` 表示"还没有真实坐标，用关卡自己的
  SpawnPoint"，`save_game()` 每次自动清成 `false`。旧档缺字段默认 `false`，
  行为不变。**不在 `REQUIRED_KEYS` 里**，改它不需要升 `save_version`。
- **陷阱警告**：`REQUIRED_KEYS` 校验缺字段即判定存档损坏。因此**新增字段
  绝不能加进 `REQUIRED_KEYS`**（会让所有旧存档失效），读取时一律用
  `data.get("new_field", 安全默认值)`。
- `save_version` 当前为 **2**（`SaveManager.SAVE_VERSION`）。无该字段的旧存档
  读为版本 0，新字段全部走安全默认值，旧存档永远不失效。调整存档格式
  必须递增版本号并附迁移逻辑。已有迁移（都在 `_read_validated()` 内，
  只改值不改盘上的 `save_version`，下次 `save_game()` 才落新版本号）：
  - **< 2**：`player_position_y` 加 `LEGACY_CENTRE_ORIGIN_OFFSET_Y`（24）。
    玩家原点从身体中心改到脚底，旧档存的是中心坐标，不补偿会读档后悬空
    半个身位。
- 写入安全已实现：先写 `.tmp` 再替换正式文件，写入失败不破坏已有存档。
  保持这个路径，不要改回直接写。
- 所有文件 I/O 只在 SaveManager 内进行；UI 和关卡脚本只调用其公共 API
  （`create_new_save` / `save_game` / `load_game` / `delete_save` /
  `save_exists` / `get_save_summary`）。已有 API 名称保留，不要为了对齐
  别的命名习惯而改。
- 只写基础类型（int/float/String/bool）进 JSON，不写节点引用或 Object。
- 需要持久化的系统提供 `get_save_data() -> Dictionary` /
  `load_save_data(data: Dictionary)` 接口，由 SaveManager 在
  save_game/load_game 里汇总（StoryFlagManager 已按此接入，字段
  `story_flags`）；不建自动序列化框架。
- 明确区分关卡临时状态（不入档）与跨存档持久状态（入档）。
- 读档前后：强制恢复正常世界速度、清除 DreamGap 计时、玩家输入状态正常。

## 5. Interaction（已实现）

- 基类 `Interactable extends Area2D`（`scripts/components/interactable.gd`）：
  `can_interact(player)`、`get_interaction_prompt()`、`interact(player)`。
  子类只重写 `_on_interact()` 和可选的 `_on_blocked_interact()`（Flag 条件
  不足时的替代反馈）；一次性消耗、`interact_priority`、`required_flag`
  门槛由基类处理。注意：优先级字段叫 `interact_priority`（Area2D 原生已有
  `priority`，勿撞名）。
- 玩家只挂一个 `InteractionDetector`（player.tscn 已内置，检测半径 56）：
  进出注册候选、按 interact_priority + 距离选目标、`prompt_changed` /
  `target_changed` 信号发提示、E 键调用 `interact()`。输入锁激活期间
  不触发（对话中不会重复交互）。
- 玩家不需要也不允许知道对象是门、记忆物、机关还是剧情道具 —— 具体结果
  由交互对象自身处理，不把这些逻辑硬编码进玩家脚本。
- 新交互物一律继承 Interactable，不建第二套检测系统。回归测试：
  `tests/test_interaction.tscn`。

### 5.5 叙事编排：StoryDirector（已实现）

- 交互物、Cutscene、NPC、DialogueBox 只回答"我怎么工作"；
  **"为什么现在发生这件事"一律归 StoryDirector**。剧情依赖汇聚到 Director，
  不要让演员之间互相操作（NPC 直接开门、Cutscene 直接推信物都是错的）。
- 每个正式关卡一个 `<level>_story_director.gd`，继承 `StoryDirector`，
  作为关卡根的**直接子节点**。**不要做成 Autoload**，也不要做全局
  StoryController。
- 子类实现三个钩子：`_connect_actors()`（只连线，禁止读剧情状态）、
  `_restore_story_state()`（幂等摆终态）、`_on_story_ready()`（可选开场）。
- **时序**：Godot `_ready()` 子先于父，Director `_ready()` 时玩家还没放置、
  `clear_session()` 还没跑。所以恢复挂在 `LevelBase.level_started` 上，
  基类已代劳，**不要把恢复逻辑写进子类的 `_ready()`**。
- **每个剧情节点写成两个函数**（读档不重播的唯一保证）：
  `_on_<事件>()` 现场触发一次（幂等闸门 → 写 Flag/Memory → 触发表现）；
  `_apply_<节点>()` 幂等摆终态、不播表现，现场链路和恢复链路都调它。
  演员配套提供成对方法：`enter_scene()`/`set_present()`、`open()`/`set_unlocked()`。
  **不要为了恢复表现另造 Flag。**
- `Cutscene` 禁止写剧情 Flag、推进信物、解锁门、生成 NPC、决定下一段剧情；
  演完发 `finished`，后果由 Director 决定。它持独立输入锁来源 `cutscene`，
  与 `dialogue_box` / `memory_box` / `area_switch` 并存，只释放自己那一把。
- `StoryNPC` 禁止在 `_process` 里查 StoryFlagManager 决定自己出不出现。
- DialogueBox 不当导演：它只管显示/分页/推进/关闭/玩家锁。
  "读完文字后触发某事"的 pending 标记**放在 Director 里**，不要留在关卡脚本。
- 关卡脚本（`old_courtyard.gd` 一类）只留：相机跟随、提示 Label、
  文本布线、场景切换机制。剧情判断一律不许写进去。

## 6. Narrative / Story Flags（已实现）

- 剧情进度统一由 `StoryFlagManager`（Autoload）管理，接口：
  `set_flag` / `has_flag` / `get_value` / `set_value` / `clear_flag`，
  ID 用 `StringName`。`persistent` 参数区分入档与 session（session 由
  LevelBase 进关时 `clear_session()` 清除）。
- Flag 命名有层级、可读：`chapter_01.intro_finished`、
  `chapter_02.shoe_received`。禁止 `flag_1`、`event_a`、`done_03`。
- 可派生的条件用函数计算，不重复存储。
- 已接入 SaveManager（字段 `story_flags`）；旧存档无该字段时默认空字典。
- 不在各场景散落独立布尔变量；对话文本不硬编码在玩家或关卡脚本中。
- Flag 值只允许 JSON 基础类型（bool/int/float/String）。

## 7. Level（LevelBase 已实现）

- 新关卡和测试房一律继承 `LevelBase`（`scenes/levels/level_base.gd`）：
  `level_id`、`movement_mode`（默认 SIDE_SCROLL）、出生点
  （`spawn_point_path`）、存档位置恢复（仅当存档
  `current_scene` 指向本场景）、进关自动 `WorldTimeManager.reset_state()` +
  `StoryFlagManager.clear_session()` + `clear_input_locks()`、
  `on_level_started()` / `on_level_completed()` 钩子。子类重写 `_ready`
  必须调用 `super._ready()`。
- 旧场景（TestLevel、dream_platforming_test）暂不强制迁移；逐步迁移。
- 基础系统测试放独立测试场景（`res://tests/` 或
  `res://scenes/levels/` 下的 test 场景），不要在正式剧情关卡里测试。

## 8. 目录规范

当前采用"按职责分目录"（见 CLAUDE.md）：`scenes/`（levels / player / ui /
components / props）、`scripts/`（autoload / components / globals）、
`assets/`、`resources/`。

- 新文件放进符合职责的现有目录即可；未来若迁移到 `autoload/`、`core/`、
  `player/`、`gameplay/` 等结构，采用渐进方式：先放新文件，不批量搬旧文件。
- 移动已有文件必须确认所有 `.tscn` / `.gd` 中的 `res://` 路径引用同步更新，
  风险高时保留旧路径。优先保证项目持续可运行。

## 9. 修改流程

每次修改前：

1. 阅读本文件。
2. 通过 Godot AI MCP 检查相关场景、脚本和依赖的实际状态
   （`editor_state`、`scene_get_hierarchy`、读脚本内容）。
3. 复用已有系统（先查第 0 节的清单）。
4. 明确本次会修改的文件；不碰无关功能。

每次修改后：

1. 检查 GDScript parser error（Godot AI `logs_read` / 脚本校验）。
2. 运行相关测试场景，查看 Debugger 和输出日志。
3. 确认存档/读档仍然工作。
4. 确认 DreamGap 仍然工作（激活、结束、冷却、玩家不减速）。
5. 检查节点路径、资源路径、Signal 连接有效；编辑器改动后保存场景。
6. 列出修改文件、说明新增数据流、说明仍存在的风险或技术债务。

### 验证诚实性

- Godot AI 可用时直接运行场景验证；连接失败时明确说明，并区分
  "静态检查结果"和"已在 Godot 中实际运行验证的结果"。
- MCP 无法注入按键边沿（只能注入按住状态），依赖 just_pressed 的行为
  需人工按键测试 —— 本项目玩家输入已按第 2 节的约定规避了这一点。
- 不要声称功能通过测试，除非实际运行过或明确说明了验证方式。

## 10. 后续开发复用指引

| 新增内容 | 复用什么 |
| --- | --- |
| 新移动平台 | AnimatableBody2D + 子节点 `DreamAffectedComponent`，运动用组件的 `get_scaled_delta()`（旧例 `moving_platform.gd` 为直连写法） |
| 新敌人/机关 | 同上：挂 `DreamAffectedComponent`，`_physics_process` 拉取组件 scaled delta，碰撞发 Signal |
| 新 DreamGap 显形物体 | `DreamAffectedComponent` + `effect_type = VISUAL_REVEAL`（或 BOTH）；自定义表现关掉 `auto_apply_reveal` 听 `reveal_changed` |
| 新剧情交互物 | 继承 `Interactable`，重写 `_on_interact()`，不写进玩家脚本 |
| 新记忆收集物 | `MemoryPickup`（`scripts/components/`，`one_shot = true`）；**不要**再配一个 `got_xxx` Flag |
| 新的画廊 CG | `resources/cg/` 加一个 `CGEntry` `.tres`（自动注册）；在 Director 里 `GalleryManager.unlock_cg(id)` |
| 新关卡（横版连续滚动） | 复制 `courtyard_01.tscn`，换背景 / Props / Director；相机用 `FollowCamera2D`，出口用 `LevelExit` |
| 关卡禁跳跃 | 关卡根节点设 `player_can_jump = false`（LevelBase 会下发给玩家），**不要**新增 MovementMode |
| 全屏淡入淡出 | `ScreenFade`（`scenes/ui/screen_fade.tscn`），`await fade_out()` / `await fade_in()`；不要再内联 Tween |
| 单向通路 / 回不了头的区段 | `BacktrackTrap` + 一面 StaticBody2D 硬边界；数值进配置脚本，解锁时 `disarm()` |
| 新的机关谜题 UI | 参照 `RotaryLockUI`：自己 pause + 玩家输入锁，只发 `solved`，Flag 和后果交给 Director |
| 新的门 | `StoryDoor`（`scripts/components/`）：`required_flag` 和 / 或 `required_memory`，两者叠加 |
| 新剧情节点 | 写进该关的 `StoryDirector`：一个 `_on_<事件>()` + 一个 `_apply_<节点>()`，后者进 `_restore_story_state()` |
| 新演出 / 幻觉 | 继承 `Cutscene`，只写 `_perform()`，演完调 `finish()`；剧情后果交给 Director |
| 新剧情 NPC | 继承 `StoryNPC`，实现自己的进出场与台词；入场时机由 Director 决定 |
| 新剧情 Flag | 命名分层：`story.*`（跨关卡持久）/ `<level_id>.*`（本关持久）/ `<level_id>.now.*`（session）/ `test.*`（测试场景，**不许占用正式命名空间**） |
| 新记忆信物 | `resources/memories/` 加一个 MemoryEntry `.tres`（自动注册）；剧情处调 `MemoryManager.unlock_memory()` / `advance_memory()` |
| 信物文案随剧情变化 | `advance_memory(id)` 推进同一信物的阶段，**不要**新建重复道具 |
| 新存档字段 | `data.get("field", 默认值)` 读取；**勿加入 REQUIRED_KEYS**；需要时递增 `save_version` |
| 新正式关卡 | 继承 `LevelBase`，设 `player_path` / `spawn_point_path` / `level_id`；多区域横版探索参照 `old_courtyard.tscn`（AreaFlowController + exploration_area） |
| 新 2.5D 关卡 | LevelBase 的 `movement_mode` 设为 `DEPTH_2_5D`，场景结构（YSortRoot / 固定前后景 / 可行走区边界 / 相机 X 跟随 Y 固定）参照 `tests/whitebox_25d/whitebox_25d.tscn`；参与排序的物件原点放在接触地面的那一点 |
| 新探索区域 | 在关卡 AreaContainer 下复制一个区域节点（exploration_area.gd + SpawnPoint + ExitTrigger），平移到新位置即接入流转 |
| 纯文本调查物 | `text_interactable.gd`，文案写在 `display_text` 导出属性 |
| 能力 UI（冷却条等） | 监听玩家 `DreamGapAbility` 的 `cooldown_changed` / `duration_changed` 等信号 |
| 对话/过场锁玩家 | `player.begin_interaction()` / `lock_input(&"来源")` 配对解锁 |

## 11. 特别限制

- 不要推翻已经可运行的存档系统和世界变慢系统。
- 不要未经检查就新建重复的 SaveManager、DreamGapManager 或第二套时间系统。
- 不要引入 `Engine.time_scale`。
- 不要修改与架构无关的美术资源；不要重写正式关卡。
- 不要一次性把旧脚本拆成大量小文件；不要一次性批量移动已有资源。
- 不要建大型依赖注入框架、巨型 EventBus，或不必要的第三方插件。
- 不要只创建空脚本/空目录而不接入实际功能。
- 修改输入映射、Autoload、渲染或导出设置前必须征得用户同意。
- 关卡最终构成、剧情含义、视觉象征、恐怖节奏、手感终调、美术方向
  由用户决定，Agent 不独立拍板。
- Before making changes, analyze the required modifications. Batch all file edits first. Minimize MCP calls. Only run Godot once after completing the implementation.
