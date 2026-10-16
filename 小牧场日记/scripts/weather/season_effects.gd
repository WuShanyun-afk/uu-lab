class_name SeasonEffects
extends RefCounted
## 季节效果表（GDD §2.1）—— 纯静态，无状态，随手可断言
##
## 季节不是「一个数字」，而是四条独立规则：
##   1. 外观     草地色 / 地块染色
##   2. 动物     牛奶产量倍率
##   3. 经济     作物售价倍率
##   4. 规则     冬季户外不可种植
## 全部收在这里，改季节 = 改这张表，不碰任何玩法代码。

const NAMES := ["春", "夏", "秋", "冬"]

## GDD §2.1 的草地色 —— 同时作为季节染色着色器的目标色。
const GRASS_COLOR: Array[Color] = [
	Color("#7FC15E"),     # 春 嫩绿
	Color("#5FA83C"),     # 夏 深绿
	Color("#C9A44C"),     # 秋 枯黄
	Color("#E8EDF2"),     # 冬 积雪
]

## 季节染色强度（0 = 原样，1 = 完全变成目标色）。
## 用 assets/shaders/season_tint.gdshader 做 mix —— modulate 只能乘，乘不出雪白。
## 春 = 0，所以地表和美术画的原始草地完全一致。
const GRASS_TINT_AMOUNT: Array[float] = [0.0, 0.30, 0.50, 0.80]

## 牛奶产量倍率（GDD §2.1：夏 +20% / 冬 -15%）
const MILK_MULT: Array[float] = [1.0, 1.2, 1.0, 0.85]

## 作物售价倍率（GDD §2.1：秋 +10%）
const CROP_PRICE_MULT: Array[float] = [1.0, 1.0, 1.1, 1.0]

static func name(s: int) -> String:
	return NAMES[s]

static func grass_color(s: int) -> Color:
	return GRASS_COLOR[s]

## 季节染色强度：0 = 原样（春），1 = 完全变成目标色
static func grass_tint_amount(s: int) -> float:
	return GRASS_TINT_AMOUNT[s]

static func milk_multiplier(s: int) -> float:
	return MILK_MULT[s]

static func crop_price_multiplier(s: int) -> float:
	return CROP_PRICE_MULT[s]

## 普通作物能否户外种植（冬季 false）。
## ⚠️ 模块 3 起，真正的门禁是「作物自己的季节」——FarmGrid.plant_reason 比对
##    CropData.season 与当前季节，所以冬季那 6 种 season=3 的耐寒作物种得下去，
##    普通作物照旧被拒。本函数仍保留为「冬季语义」的唯一出处（main 用它决定提示文案）。
static func can_plant_outdoor(s: int) -> bool:
	return s != 3

## 牛奶产量季节加成。
##
## ⚠️ 奶牛一次只产 1~2 罐，直接 round(1 * 1.2) = 1 —— 加成会被四舍五入吃光。
## 所以用「向下取整 + 小数部分按概率 +1」实现期望值放大：
##   count=1 夏 → 1 罐 + 20% 概率再来 1 罐（期望 1.2）
##   count=2 冬 → 1 罐 + 70% 概率再来 1 罐（期望 1.7）
static func apply_milk_mult(count: int, s: int, rng: RandomNumberGenerator) -> int:
	var exact: float = float(count) * MILK_MULT[s]
	var base := int(floor(exact))
	if rng.randf() < exact - float(base):
		base += 1
	return maxi(1, base)
