class_name RanchStage
extends RefCounted
## 牧场五阶段（模块 9 需求 3）—— **纯逻辑**，不碰节点、不碰 UI、不碰存档
##
## 需求原文：「一块地 → 鸡舍 → 畜棚 → 加工坊 → 农贸市场 → 小镇 → 镇长」，
## 一共 7 个名词但说「五阶段」。这里的口径（已跟玩家确认过）：
##
##   0 一块地 ── 1 鸡舍 ── 2 畜棚 ── 3 加工坊 ── 4 农贸市场 ── 5 小镇 ── 终 镇长
##
##   「一块地」是起点，「镇长」不是第 6 个阶段，是**通关称号**（走 is_mayor）。
##   所以阶段表有 6 项（0..5），第 5 项「小镇」是最后一个可建造阶段。
##
## 为什么阶段要**存**而不是每次现算：
##   门槛里有「金币 ≥ 800」「累计售出 ≥ 100」这类会**倒退**的指标。
##   现算的话，玩家花 800 买只鸡 → 阶段掉回「一块地」→ 刚解锁的鸡舍又没了。
##   所以规则是单调的：`push_stage()` 只升不降，升上去就永久记住。
##
## 门槛数值全是**建议值**，调平衡只用改下面这张表（跟 CSV 一个思路：
## 数值不写死在 main 里，否则每改一次就得重跑全部测试）。

## 指标键（metrics 字典的合法键）—— 用常量而不是裸字符串，拼错会当场报错
const M_COINS := &"coins"        ## 手上现金
const M_ANIMALS := &"animals"    ## 养了几只
const M_ORDERS := &"orders"      ## 完成订单数
const M_CRAFTED := &"crafted"    ## 加工出件数
const M_SOLD := &"sold"          ## 卖出件数

## 阶段表。每项：
##   id / name      标识与显示名
##   building       进入这一阶段盖出来的标志性建筑（&"" = 没有）
##   need           门槛数组 [[指标键, 数量], ...]（空数组 = 开局就给）
##   unlock         这一阶段解锁的建造分类（给 UI 说人话用）
const STAGES: Array = [
	{
		"id": &"land", "name": "一块地", "building": &"",
		"need": [],
		"unlock": "栅栏 · 基础农具",
	},
	{
		"id": &"coop", "name": "鸡舍", "building": &"coop",
		"need": [[M_COINS, 800], [M_ANIMALS, 3]],
		"unlock": "鸡舍 / 蜂箱 · 鸡鸭火鸡",
	},
	{
		"id": &"barn", "name": "畜棚", "building": &"barn",
		"need": [[M_COINS, 2000], [M_ANIMALS, 6], [M_ORDERS, 3]],
		"unlock": "畜棚 · 牛羊",
	},
	{
		"id": &"workshop", "name": "加工坊", "building": &"workshop",
		"need": [[M_COINS, 4000], [M_CRAFTED, 10]],
		"unlock": "加工坊 · 加工品",
	},
	{
		"id": &"market", "name": "农贸市场", "building": &"market",
		"need": [[M_COINS, 8000], [M_SOLD, 100]],
		"unlock": "农贸市场 · 高价出货",
	},
	{
		"id": &"town", "name": "小镇", "building": &"town_square",
		"need": [[M_COINS, 15000], [M_ORDERS, 20], [M_ANIMALS, 10]],
		"unlock": "小镇广场 · 镇长称号",
	},
]

## 镇长（终局称号）的额外门槛：站上小镇之后还要完成这么多订单
const MAYOR_ORDERS := 30

## 最后一级的下标
static func last_stage() -> int:
	return STAGES.size() - 1

## 这个阶段存在吗（存档里读到脏数据时的兜底）
static func valid(stage: int) -> bool:
	return stage >= 0 and stage < STAGES.size()

static func clamp_stage(stage: int) -> int:
	return clampi(stage, 0, last_stage())

static func stage_name(stage: int) -> String:
	if not valid(stage):
		return "？"
	return str(STAGES[stage]["name"])

static func stage_id(stage: int) -> StringName:
	if not valid(stage):
		return &""
	return STAGES[stage]["id"]

## 这一阶段该盖出来的标志性建筑（&"" = 没有，main 用它做「盖出来就算到阶段」的软门禁）
static func landmark_building(stage: int) -> StringName:
	if not valid(stage):
		return &""
	return STAGES[stage]["building"]

## 某一阶段的一句话解锁说明（HUD / 对话用）
static func unlock_text(stage: int) -> String:
	if not valid(stage):
		return ""
	return str(STAGES[stage]["unlock"])

## 门槛表本身（UI 要逐条打勾用它，别自己再写一份）
static func needs_of(stage: int) -> Array:
	if not valid(stage):
		return []
	return STAGES[stage]["need"]

## 指标键 → 中文名（提示条「还差：金币 800（现在 500）」要它）
static func metric_name(key: StringName) -> String:
	match String(key):
		"coins":
			return "金币"
		"animals":
			return "动物"
		"orders":
			return "完成订单"
		"crafted":
			return "加工出件"
		"sold":
			return "售出件数"
	return String(key)

## 当前指标满足某个阶段的门槛了吗（只看这一阶段，不看之前）
static func meets(stage: int, metrics: Dictionary) -> bool:
	for pair in needs_of(stage):
		var key: StringName = pair[0]
		var need := int(pair[1])
		if int(metrics.get(key, 0)) < need:
			return false
	return true

## 从 stage 往上能连续推到哪一级（单调：一次只升一级，所以只往前看一格）
## 返回**新阶段**（没升级就原样返回）
static func next_stage(stage: int, metrics: Dictionary) -> int:
	var cur := clamp_stage(stage)
	# 一次只升一级：门槛是递进的，跳过一级会让中间那句「解锁 XX」永远看不见
	if cur < last_stage() and meets(cur + 1, metrics):
		return cur + 1
	return cur

## 达到 stage 阶段时，还差什么（返回 ["金币 800（现在 500）", ...]；空数组 = 全部达成）
## UI 只负责把它 join 成一行，不自己算数字。
static func missing_of(stage: int, metrics: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for pair in needs_of(stage):
		var key: StringName = pair[0]
		var need := int(pair[1])
		var have := int(metrics.get(key, 0))
		if have < need:
			out.append("%s %d（现在 %d）" % [metric_name(key), need, have])
	return out

## 下一阶段的总进度 0.0~1.0（每一项按「已达/需要」取平均，HUD 画进度条用）
static func progress_to_next(stage: int, metrics: Dictionary) -> float:
	var cur := clamp_stage(stage)
	if cur >= last_stage():
		return 1.0
	var need := needs_of(cur + 1)
	if need.is_empty():
		return 1.0
	var sum := 0.0
	for pair in need:
		var key: StringName = pair[0]
		var n := int(pair[1])
		if n <= 0:
			sum += 1.0
			continue
		sum += clampf(float(metrics.get(key, 0)) / float(n), 0.0, 1.0)
	return sum / float(need.size())

## HUD 那一行："阶段 2/5 畜棚 · 下一个：加工坊 42%（还差 金币 4000（现在 1680））"
static func hud_text(stage: int, metrics: Dictionary) -> String:
	var cur := clamp_stage(stage)
	var head := "阶段 %d/%d %s" % [cur, last_stage(), stage_name(cur)]
	if cur >= last_stage():
		if is_mayor(cur, metrics):
			return head + " · 镇长 ★"
		return head + " · 终局：完成 %d 单（%d/%d）" % [MAYOR_ORDERS,
			int(metrics.get(M_ORDERS, 0)), MAYOR_ORDERS]
	var nxt := cur + 1
	var pct := int(round(progress_to_next(cur, metrics) * 100.0))
	var miss := missing_of(nxt, metrics)
	var tail := "下一个 %s %d%%" % [stage_name(nxt), pct]
	if not miss.is_empty():
		tail += "（还差 " + " · ".join(miss) + "）"
	return head + " · " + tail

## 镇长称号（终局）：站上小镇 + 订单数达标。
## 为什么不是「七阶段」：需求里「镇长」是身份不是地点，做成阶段会让
## 「小镇」变成只有一格的过场阶段。做成称号，终局目标反而更清楚。
static func is_mayor(stage: int, metrics: Dictionary) -> bool:
	return clamp_stage(stage) >= last_stage() and int(metrics.get(M_ORDERS, 0)) >= MAYOR_ORDERS

## 这个阶段能不能盖某一类建筑（BuildingGrid 用；传的是 BuildingDef.stage_required）
static func can_build(stage: int, required: int) -> bool:
	return clamp_stage(stage) >= required

## 阶段达成时的一句话播报（main 的提示条直接用）
static func announce(stage: int) -> String:
	if not valid(stage):
		return ""
	return "牧场扩建 · 第 %d 阶段「%s」达成！解锁：%s" % [
		stage, stage_name(stage), unlock_text(stage)]
