class_name Market
extends RefCounted
## 行情系统（模块 7 需求 5）—— 售价随品质 / 季节 / 当日行情波动
##
## 一件东西最终卖多少钱，是**四个因子相乘**：
##
##   单价 = 基础价 × 品质倍率 × 季节倍率 × 当日行情
##          (CSV)   (CropQuality) (本文件)   (本文件)
##
## 为什么把「季节」和「行情」从出货箱里抽出来：
##   出货箱原来自己算 CropQuality × SeasonEffects，是**唯一**的定价入口。
##   模块 7 之后订单奖励、商店回收价也要同一套定价 —— 抄三遍迟早不一致。
##   现在只有 Market.price() 一个入口。
##
## 行情因子是**确定性**的：同一个 (天, 品类) 永远得同一个数。
##   不用 RNG 状态 → 测试能直接断言「第 7 天牛奶价 = 第 7 天牛奶价」，
##   玩家读档（将来做存档）也不会因为多按了一次而变价。
##
## 三个品类各自独立波动，所以「今天该卖奶还是该卖菜」是个真选择：
##   crop    作物      秋 +10%（GDD §2.1 秋收溢价）
##   animal  畜产品    夏 -5% / 冬 +10%（天热出奶多、冬天稀缺）
##   crafted 加工品    全年 ×1.00 —— 稳定是加工的卖点，别让它在行情里晃

## 行情波动幅度：±15%
const VOLATILITY := 0.15

const CAT_CROP := &"crop"
const CAT_ANIMAL := &"animal"
const CAT_CRAFTED := &"crafted"
const CAT_OTHER := &"other"

## 季节倍率（GDD §2.1 + 模块 7 扩充）
const SEASON_MULT := {
	CAT_CROP: [1.0, 1.0, 1.1, 1.0],
	CAT_ANIMAL: [1.0, 0.95, 1.0, 1.10],
	CAT_CRAFTED: [1.0, 1.0, 1.0, 1.0],
	CAT_OTHER: [1.0, 1.0, 1.0, 1.0],
}

## 品类 → 中文名（HUD 行情条用）
const CAT_LABEL := {
	CAT_CROP: "作物",
	CAT_ANIMAL: "畜产",
	CAT_CRAFTED: "加工品",
	CAT_OTHER: "其他",
}

## 当天的行情因子缓存：{day: {cat: float}}
## 纯静态函数也能算，但每帧算几百次 hash 没必要。
static var _cache: Dictionary = {}

# ---------------- 品类 ----------------

static func category_of(item_id: StringName) -> StringName:
	var d := ItemDB.resolve(item_id)
	if d == null:
		return CAT_OTHER
	match d.category:
		ItemDef.Cat.CROP:
			return CAT_CROP
		ItemDef.Cat.PRODUCT:
			return CAT_ANIMAL
		ItemDef.Cat.CRAFTED:
			return CAT_CRAFTED
	return CAT_OTHER

# ---------------- 季节 ----------------

static func season_multiplier(cat: StringName, season: int) -> float:
	var row: Array = SEASON_MULT.get(cat, SEASON_MULT[CAT_OTHER])
	return float(row[clampi(season, 0, 3)])

# ---------------- 当日行情 ----------------

## 确定性伪随机：把 (天, 品类) 搅成一个 [0,1) 的数。
## 用两次乘加打散，避免相邻天数落在同一格 —— 那会让价格看起来卡住了。
static func _noise(day: int, cat: StringName) -> float:
	var h := absi(hash("%d|%s" % [day, str(cat)]))
	var x := float(h % 100003) / 100003.0
	x = fmod(x * 7919.0 + 0.371, 1.0)
	return absf(x)

## 当天某品类的行情因子（作物 / 畜产 ±15%，加工品 ±7.5%）
## 加工品波动减半是刻意的：加工的价值主张就是「价格稳、不赌行情」，
## 让它跟原料一样乱跳，加工坊就只是个更麻烦的出货箱了。
static func daily_factor(day: int, cat: StringName) -> float:
	var bucket: Dictionary = _cache.get(day, {})
	if bucket.has(cat):
		return float(bucket[cat])
	var vol := volatility_of(cat)
	var f := 1.0 + (float(_noise(day, cat)) * 2.0 - 1.0) * vol
	# 保留三位小数：HUD 显示 1.03x 和实际结算必须是同一个数，别让玩家算出对不上的账
	f = roundf(f * 1000.0) / 1000.0
	bucket[cat] = f
	_cache[day] = bucket
	return f

## 某品类的波动幅度
static func volatility_of(cat: StringName) -> float:
	return VOLATILITY * 0.5 if cat == CAT_CRAFTED else VOLATILITY

## 涨跌方向：+1 涨 / 0 平 / -1 跌（相对 1.0，留 2% 死区免得箭头乱跳）
static func trend(day: int, cat: StringName) -> int:
	var f := daily_factor(day, cat)
	if f > 1.02:
		return 1
	if f < 0.98:
		return -1
	return 0

static func trend_arrow(day: int, cat: StringName) -> String:
	match trend(day, cat):
		1:
			return "▲"
		-1:
			return "▼"
	return "—"

## 行情文案：一天换一次，玩家在 HUD 上一眼能看到该卖什么
static func summary(day: int, season: int) -> String:
	var parts: Array[String] = []
	for cat in [CAT_CROP, CAT_ANIMAL, CAT_CRAFTED]:
		parts.append("%s%s%.2fx" % [CAT_LABEL[cat], trend_arrow(day, cat),
			daily_factor(day, cat) * season_multiplier(cat, season)])
	return "行情 " + " ".join(parts)

# ---------------- 定价（唯一入口）----------------

## 出货 / 订单 / 商店回收共用。season / day 由调用方传（本类是 RefCounted，
## 不持有 GameClock 引用，测试里可以随便塞「秋 / 第 40 天」）。
static func price(item_id: StringName, season: int, day: int) -> int:
	var base := ItemDB.price_of(item_id)      # 已含品质倍率
	var cat := category_of(item_id)
	var v := float(base) * season_multiplier(cat, season) * daily_factor(day, cat)
	return maxi(1, int(round(v)))

## 相对「基准价」的涨跌幅百分比，商店回收价 / UI 提示用
static func delta_percent(item_id: StringName, season: int, day: int) -> int:
	var base := ItemDB.price_of(item_id)
	if base <= 0:
		return 0
	return int(round((float(price(item_id, season, day)) / float(base) - 1.0) * 100.0))

## 清缓存（换天时 main 会调；测试之间也调，避免互相污染）
static func clear_cache() -> void:
	_cache.clear()
