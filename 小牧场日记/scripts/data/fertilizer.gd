class_name Fertilizer
extends RefCounted
## 肥料系统（模块 3 需求 5）—— 纯静态表 + 纯函数，随手可断言
##
## 数值严格对齐 GDD §4.1：
##   基础肥料 100G（品质概率 +10%）· 高级肥料 300G（+25%，但生长 +1 天）
##
## 在此基础上用 crops.csv 的 fertilize 列（**施肥需求** 低/中/高）做分化：
##
##   需求  基础肥 100G          高级肥 300G              高级肥生长代价
##   低    银 +5%               银 +12%  金 +3%           +1 天
##   中    银 +10%（GDD 基准）   银 +20%  金 +5%           +1 天
##   高    银 +15%              银 +28%  金 +8%           **+0 天**（吸收好，副作用抵消）
##
## 于是「高级肥」不是无脑堆：
##   · 高需求的长周期作物（草莓 / 花椰菜 / 南瓜 / 甜瓜）值得上高级肥 —— 加成最高且不加天
##   · 低需求的快熟作物（芜菁 / 小麦 / 冬葱）上高级肥等于白搭一天，只该用基础肥
##
## 不施肥的底子：银星 5% / 金星 0%。

enum Level { NONE, BASIC, HIGH }

const MAX_LEVEL := 2

## 等级 → 背包 item id（NONE 没有物品）
const ITEM_ID: Array[StringName] = [&"", &"fertilizer", &"fertilizer_high"]
const NAME := ["未施肥", "基础肥", "高级肥"]
const PRICE := [0, 100, 300]      ## GDD §4.1

## 不施肥的底子 [银星, 金星]
const BASE_CHANCE := [0.05, 0.00]

## 施肥需求(0低/1中/2高) → [基础肥加成, 高级肥加成]，每个加成是 [银星, 金星]
const QUALITY_BONUS: Array = [
	[[0.05, 0.00], [0.12, 0.03]],   # 需求低
	[[0.10, 0.00], [0.20, 0.05]],   # 需求中（= GDD 的 +10% / +25%）
	[[0.15, 0.00], [0.28, 0.08]],   # 需求高
]

## 等级 → 每格土壤的绘制色（CropLayer 画肥力标记）
const SOIL_MARK: Array[Color] = [
	Color(0, 0, 0, 0),
	Color("#7A5A2E"),
	Color("#4E7C3A"),
]

static func level_name(lv: int) -> String:
	return NAME[clampi(lv, 0, MAX_LEVEL)]

static func item_id(lv: int) -> StringName:
	return ITEM_ID[clampi(lv, 0, MAX_LEVEL)]

## 背包 item id → 肥料名（不是肥料返回 ""）
static func name_of_item(item: StringName) -> String:
	for lv in range(1, MAX_LEVEL + 1):
		if ITEM_ID[lv] == item:
			return NAME[lv]
	return ""

## 背包 item id → 等级（不是肥料返回 0 = NONE）
static func level_of_item(item: StringName) -> int:
	for lv in range(1, MAX_LEVEL + 1):
		if ITEM_ID[lv] == item:
			return lv
	return 0

static func price(lv: int) -> int:
	return PRICE[clampi(lv, 0, MAX_LEVEL)]

## [银星概率, 金星概率] = 底子 + 该需求等级在该肥料下的加成
static func quality_chance(affinity: int, lv: int) -> Array:
	var a := clampi(affinity, 0, 2)
	var l := clampi(lv, 0, MAX_LEVEL)
	if l == 0:
		return [BASE_CHANCE[0], BASE_CHANCE[1]]
	var bonus: Array = QUALITY_BONUS[a][l - 1]
	return [BASE_CHANCE[0] + float(bonus[0]), BASE_CHANCE[1] + float(bonus[1])]

## 优质总概率（银星 + 金星），UI 显示用
static func quality_total(affinity: int, lv: int) -> float:
	var ch := quality_chance(affinity, lv)
	return float(ch[0]) + float(ch[1])

## 施肥对生长天数的影响（正数 = 更慢）。
## 基础肥不改变天数；高级肥 +1 天，但「施肥需求 高」的作物能完全吸收，不加天。
static func growth_delta(affinity: int, lv: int) -> int:
	if lv < MAX_LEVEL:
		return 0
	return 0 if affinity >= 2 else 1

## 掷一次品质骰。返回 CropQuality.Level
static func roll_quality(affinity: int, lv: int, rng: RandomNumberGenerator) -> int:
	var ch := quality_chance(affinity, lv)
	var r := rng.randf()
	if r < float(ch[1]):
		return CropQuality.Level.GOLD
	if r < float(ch[1]) + float(ch[0]):
		return CropQuality.Level.SILVER
	return CropQuality.Level.NORMAL
