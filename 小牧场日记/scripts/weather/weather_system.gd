extends Node
## 天气系统（autoload: WeatherSystem）—— GDD §2.2
##
## 职责只有两件：
##   1. 每天掷一次骰子决定「明天」的天气（今天 = 昨天掷出来的那个）
##   2. 把「天气 × 季节」翻译成一张纯数据的效果表
##
## 本文件**不认识** FarmGrid、**不认识** Herd、也不认识任何节点。
## 它只负责广播 EventBus.weather_changed / weather_effects_applied，
## 谁来消费（农场自动浇水 / 动物留棚 / 栅栏损坏 / 光照 / 音效）由订阅方自己决定。
##
## ⚠️ 顺序很重要：WeatherSystem 是 autoload，_ready 比主场景早，
##    所以同一帧的 day_advanced 里，天气已经先算好，main.gd 再读到的一定是「今天的」。

enum Weather { CLEAR, CLOUDY, RAIN, STORM, SNOW }

const NAME := {
	Weather.CLEAR: "晴",
	Weather.CLOUDY: "阴",
	Weather.RAIN: "雨",
	Weather.STORM: "暴风雨",
	Weather.SNOW: "雪",
}

const ICON := {
	Weather.CLEAR: "☀",
	Weather.CLOUDY: "☁",
	Weather.RAIN: "🌧",
	Weather.STORM: "⛈",
	Weather.SNOW: "❄",
}

## 概率表（GDD §2.2）：行 = 天气，列 = 春 / 夏 / 秋 / 冬。每列之和必须 = 1.00。
const TABLE := {
	Weather.CLEAR:  [0.35, 0.55, 0.35, 0.30],
	Weather.CLOUDY: [0.25, 0.15, 0.30, 0.30],
	Weather.RAIN:   [0.30, 0.20, 0.30, 0.00],
	Weather.STORM:  [0.10, 0.10, 0.05, 0.00],
	Weather.SNOW:   [0.00, 0.00, 0.00, 0.40],
}

## 掷骰顺序（决定累计区间的归属，改表时别乱动）
const ORDER := [Weather.CLEAR, Weather.CLOUDY, Weather.RAIN, Weather.STORM, Weather.SNOW]

const FORECAST_MINUTES := 840        ## 前一日 20:00 起电视/收音机可看预报
const FORECAST_ACCURACY := 0.85      ## 预报准确率（升级后可到 100%）
const BLIZZARD_CHANCE := 0.15        ## 雪天的暴风雪子概率（GDD §2.2）

var today: int = Weather.CLEAR
var tomorrow: int = Weather.CLEAR
var forecast: int = Weather.CLEAR    ## 预报里显示的那个（85% 准）
var blizzard: bool = false           ## 今天是暴风雪？
var light_mult: float = 1.0          ## 缓存的今日光照倍率（每帧要读，别每帧重建字典）
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 20261020
	today = roll(GameClock.season, rng)
	tomorrow = roll(GameClock.season, rng)
	forecast = make_forecast(tomorrow, rng)
	blizzard = today == Weather.SNOW and rng.randf() < BLIZZARD_CHANCE
	_refresh_cache(GameClock.season)
	EventBus.day_advanced.connect(_on_day)

func _on_day(day: int, season: int, _year: int) -> void:
	var old := today
	if day == GameClock.DAYS_PER_SEASON:
		# 第 28 天是过渡日：不刷天气事件（GDD §2.1）
		today = Weather.CLEAR
		tomorrow = roll((season + 1) % 4, rng)
	else:
		today = tomorrow
		tomorrow = roll(season, rng)
	forecast = make_forecast(tomorrow, rng)
	blizzard = today == Weather.SNOW and rng.randf() < BLIZZARD_CHANCE
	_refresh_cache(season)
	EventBus.weather_changed.emit(today, old)
	EventBus.weather_effects_applied.emit(today, effects(today, season))

# ---------------- 纯函数：掷骰 + 效果表 ----------------

## 按当季概率表挑一个天气。注入 rng 是为了让测试可复现。
static func roll(season: int, r: RandomNumberGenerator) -> int:
	var v := r.randf()
	var acc := 0.0
	for w in ORDER:
		acc += float(TABLE[w][season])
		if v < acc:
			return w
	return Weather.CLEAR

## 「天气 × 季节」效果表（纯函数，无副作用）。
## 所有消费方都读这张表，不要在别处再写一遍「雨天会怎样」。
static func effects(w: int, season: int) -> Dictionary:
	var e := {
		"auto_water": false,          # 雨天自动浇水
		"graze": true,                # 今天能否放牧
		"affection_bonus": 0,         # 留棚好感 / 天
		"feed_mult": 1,               # 饲料消耗倍率
		"fence_risk": 0.0,            # 栅栏损坏概率
		"crop_burn_risk": 0.0,        # 雷击烧毁单格作物的概率
		"light_mult": 1.0,            # 环境光倍率
		"stamina_mult": 1.0,          # 室外活动体力倍率
		"milk_mult": SeasonEffects.milk_multiplier(season),
		"crop_price_mult": SeasonEffects.crop_price_multiplier(season),
	}
	match w:
		Weather.CLOUDY:
			e["light_mult"] = 0.9
		Weather.RAIN:
			e["auto_water"] = true
			e["graze"] = false
			e["affection_bonus"] = 3
		Weather.STORM:
			e["auto_water"] = true
			e["graze"] = false
			e["affection_bonus"] = 3
			e["fence_risk"] = 0.05
			e["crop_burn_risk"] = 0.03
		Weather.SNOW:
			e["graze"] = false
			e["affection_bonus"] = 3
			e["feed_mult"] = 2
	return e

## 今天的效果表（含暴风雪的体力惩罚）
func today_effects() -> Dictionary:
	var e := effects(today, GameClock.season)
	if blizzard:
		e["stamina_mult"] = 2.0
	return e

## 85% 准的预报：15% 概率报一个别的天气（一定不是真的那个）
static func make_forecast(actual: int, r: RandomNumberGenerator) -> int:
	if r.randf() < FORECAST_ACCURACY:
		return actual
	var pool: Array = ORDER.duplicate()
	pool.erase(actual)
	return pool[r.randi() % pool.size()]

# ---------------- 查询 ----------------

## 今天湿不湿（下雨 / 暴风雨）—— 农场拿它决定要不要自动浇水
func is_wet() -> bool:
	return today == Weather.RAIN or today == Weather.STORM

## 预报要到前一日 20:00 才可看
func has_forecast() -> bool:
	return GameClock.minutes >= FORECAST_MINUTES

func weather_name(w: int = -1) -> String:
	var x := today if w < 0 else w
	if blizzard and x == Weather.SNOW:
		return "暴风雪"
	return NAME[x]

func weather_icon(w: int = -1) -> String:
	return ICON[today if w < 0 else w]

# ---------------- 内部 ----------------

## 每帧要读光照倍率，缓存起来，别每帧重建一次效果表
func _refresh_cache(season: int) -> void:
	light_mult = float(effects(today, season)["light_mult"])

## 调试 / 测试：直接指定今天与明天的天气
## ⚠️ 只要「天气或暴风雪标记」变了就广播，否则订阅方（ClockHUD）会显示过期文字
func debug_set(w: int, bliz: bool = false) -> void:
	var old := today
	var old_bliz := blizzard
	today = w
	blizzard = bliz
	_refresh_cache(GameClock.season)
	if w != old or bliz != old_bliz:
		EventBus.weather_changed.emit(today, old)

# ---------------- 存档（模块 8）----------------

## rng.state 是 64 位整数，JSON 数字过一遍 double 会掉精度 —— 一律存成字符串。
func to_dict() -> Dictionary:
	return {
		"today": today,
		"tomorrow": tomorrow,
		"forecast": forecast,
		"blizzard": blizzard,
		"rng_state": str(rng.state),
	}

func from_dict(d: Dictionary) -> void:
	today = clampi(int(d.get("today", 0)), 0, Weather.SNOW)
	tomorrow = clampi(int(d.get("tomorrow", 0)), 0, Weather.SNOW)
	forecast = clampi(int(d.get("forecast", 0)), 0, Weather.SNOW)
	blizzard = bool(d.get("blizzard", false))
	var st := int(str(d.get("rng_state", "0")))
	if st != 0:
		rng.state = st
	_refresh_cache(GameClock.season)
