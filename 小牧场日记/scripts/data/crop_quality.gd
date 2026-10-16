class_name CropQuality
extends RefCounted
## 品质分级（模块 3 需求 4）—— 普通 / 银星 / 金星
##
## 品质不只是一个数字，它有三处作用：
##   1. 售价     普通 ×1.00 / 银星 ×1.50 / 金星 ×2.00（GDD §3.3 §4.1）
##   2. 背包键   不同品质是**不同的物品**（turnip / turnip_silver / turnip_gold）
##   3. 显示     前缀星标 + 颜色
##
## 「不同品质 = 不同 item id」这个选择的原因：
##   GameState.inventory 是 Dictionary[StringName]int，改成 [id,quality] 复合键要动背包、
##   出货箱、HUD 三处；编码进 id 只动一个 resolve 函数，且天然支持「金星番茄 ×3」这种堆叠。
##   代价：任何拿到 item id 的地方都必须先 split() 拆回 base + quality。

enum Level { NORMAL, SILVER, GOLD }

const NAME := ["普通", "银星", "金星"]
const SUFFIX := ["", "_silver", "_gold"]
const PRICE_MULT := [1.0, 1.5, 2.0]

## 星标颜色（画在作物头顶 / HUD 文本用）
const STAR_COLOR: Array[Color] = [
	Color("#FFFFFF"),   # 普通无星
	Color("#C8D6E5"),   # 银星
	Color("#F2C14E"),   # 金星
]

## 品质 → 售价倍率
static func price_mult(q: int) -> float:
	return PRICE_MULT[clampi(q, 0, 2)]

## 品质 → 中文名
static func name(q: int) -> String:
	return NAME[clampi(q, 0, 2)]

## 品质 → 带星标的显示文本（"芜菁" / "银星芜菁" / "金星芜菁"）
static func label(base_name: String, q: int) -> String:
	var q2 := clampi(q, 0, 2)
	return base_name if q2 == 0 else "%s%s" % [NAME[q2], base_name]

## 基础 id + 品质 → 背包 item id
static func item_id(base: StringName, q: int) -> StringName:
	var q2 := clampi(q, 0, 2)
	return base if q2 == 0 else StringName(str(base) + SUFFIX[q2])

## 背包 item id → {id: 基础 id, quality: int}
## 不认识的后缀原样返回 quality = 0，所以畜产品 id（milk / egg）走这里也安全。
static func split(item: StringName) -> Dictionary:
	var s := str(item)
	for q in [2, 1]:
		var suf: String = SUFFIX[q]
		if s.ends_with(suf):
			return {"id": StringName(s.substr(0, s.length() - suf.length())), "quality": q}
	return {"id": item, "quality": 0}
