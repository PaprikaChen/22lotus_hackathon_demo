class_name InnerGateLockConfig
extends RefCounted
## courtyard_01 尾部「三重旋锁」小关卡的**唯一**数值来源。
##
## 关卡触发区间、黑幕重置、档位手感、谜底顺序全部集中在这里，
## 场景和各组件脚本都从这里读，禁止在别处再抄一份数字
## （改一处忘一处是这类机关最容易出的 bug）。
##
## 只放数据，不放行为——想知道"谁来执行"看：
##   · `scripts/components/backtrack_trap.gd`  返回封锁 + 黑幕重置
##   · `scripts/ui/rotary_lock_ui.gd`          锁界面 + 判定
##   · `scripts/ui/rotary_lock_ring.gd`        单层拖拽 + 档位
##   · `scenes/levels/courtyard_01_story_director.gd`  什么时候发生

# --- 关卡坐标（世界 x，courtyard_01 场景坐标系）-------------------------------

## 玩家第一次到达这里 → 陷阱激活（一次性）。
const TRAP_ACTIVATE_X := 7900.0
## 激活后往西回到这里 → 黑幕重置。
const TRAP_RESET_X := 7800.0
## 兜底硬边界：锁没开之前走不过去（正常情况先在 RESET_X 被送回）。
const TRAP_WALL_X := 7750.0
## 黑幕里把玩家放回这里。
const TRAP_RESPAWN_X := 8300.0
## 画面最左侧自己走到这里时才落闸（`FollowCamera2D.arm_left_gate_latch()`），
## 之后画面再也让不回西边。**不是玩家坐标的触发线**——按玩家坐标落闸会让
## 画面在那一瞬间跳一下，按画面左缘落闸则正好压在当前画面边上，观感连续。
const TRAP_CAMERA_GATE_X := 7700.0

# --- 黑幕过渡时长（秒）---------------------------------------------------------

const FADE_OUT_SECONDS := 0.45
const FADE_IN_SECONDS := 0.45
## 全黑之后停一下再淡出，让"被送回来"这件事有重量。
const FADE_HOLD_SECONDS := 0.25

# --- 旋锁手感 -----------------------------------------------------------------

## 一个机械档位的角度（度）。360 / 45 = 8 档一圈。
## 谜底的 steps 保持不变：每层仍须转相同格数，只是每格转得更远。
const DETENT_DEGREES := 45.0
## 半档阈值（度）：松手时未达到它就回弹，达到就吸附到下一档。
const HALF_DETENT_DEGREES := DETENT_DEGREES * 0.5
## 档位上限：原点（0 档）不许再往**顺时针**方向扭，只能逆时针。
## 这是给玩家的方向暗示——省得他不知道该往哪边拨。
## 顺时针 = 角度增大 = 档位下标变大，所以上限设成 0 就等于"原点是硬停点"。
## 逆时针没有下限（想拨几圈都行）。
const MAX_DETENT_INDEX := 0
## 吸附到下一档的时长（短促，做"咔"的手感）。
const SNAP_SECONDS := 0.08
## 回弹到上一档的时长。
const RECOIL_SECONDS := 0.12
## 开锁成功后三层对齐演出的时长。
const SUCCESS_SECONDS := 0.45
## 错误反馈（轻微抖动）时长。
const FAILURE_SECONDS := 0.22

# --- 三层标识 -----------------------------------------------------------------

const LAYER_OUTER := &"outer"
const LAYER_MIDDLE := &"middle"
const LAYER_INNER := &"inner"

const DIRECTION_CW := 1   ## 顺时针（屏幕坐标下角度增大）
const DIRECTION_CCW := -1 ## 逆时针
const DIRECTION_ANY := 0  ## 不限方向，只数转动次数

# --- 谜底（改谜题只改这一处）--------------------------------------------------
#
# 瓶子（内层）×4 → 梅花（外层）×5 → 圆形机关（中层）×2。
#
# 判定依据是「逐档输入序列」：玩家按顺序拨了哪些层、每层拨了几档。
# 连续拨同一层算**同一个阶段**；换到下一层之后又回头拨之前那层 = 顺序错。
# 判定时机是玩家点「解锁」按钮，不是转到位就结算（见 rotary_lock_ui.gd）。
# 未达半档回弹的拖动不产生档位输入，既不计数也不进序列。
#
# `direction` 留 `DIRECTION_ANY` = 不看方向，只数次数。要求某层必须朝某个
# 方向拨时改成 `DIRECTION_CW` / `DIRECTION_CCW` 即可，判定逻辑已经支持。
const SOLUTION: Array[Dictionary] = [
	{"layer": LAYER_INNER, "direction": DIRECTION_ANY, "steps": 4},
	{"layer": LAYER_OUTER, "direction": DIRECTION_ANY, "steps": 5},
	{"layer": LAYER_MIDDLE, "direction": DIRECTION_ANY, "steps": 2},
]

# --- 剧情 Flag ----------------------------------------------------------------

## 锁已打开。持久 Flag（进存档），读档 / 重进关卡后不需要重解。
const FLAG_DOOR_UNLOCKED := &"courtyard_01.inner_gate_unlocked"


## 开发期状态日志的统一开关。**正式运行保持 false**——
## 这个机关每跨一档就会打一行，开着会刷屏。调试时手动改成 true。
const DEBUG_LOG := false


## 只在开发构建 + 显式打开开关时打印。没有每帧日志，只在档位/判定事件上打。
static func log_debug(message: String) -> void:
	if DEBUG_LOG and OS.is_debug_build():
		print("[InnerGateLock] %s" % message)
