class_name AnimalState
extends RefCounted
## 单只动物的状态与逻辑（GDD §3.3 好感 / §3.4 产出 / §3.2 成长）
##
## 纯逻辑，不碰节点、不碰渲染。渲染由 AnimalNode 读这里的状态。
## 和 FarmGrid 一样的分层哲学：逻辑可 headless 断言，素材到位只换渲染层。

const HEART_POINTS := 100
const MAX_AFFECTION := 1000
const MAX_HEARTS := 10

const FEED_AFFECTION := 10
const PET_AFFECTION := 5
const BRUSH_AFFECTION := 8
const HUG_AFFECTION := 6
const MISS_FEED_PENALTY := 15        ## 每漏喂一餐

const SICK_HEART_THRESHOLD := 3
const SICK_CHANCE := 0.15
const SICK_DAILY_PENALTY := 20
const LOW_HEART_NO_PRODUCT := 0.10   ## 0–2 心：10% 概率不产出
const HIGH_HEART := 8                ## ≥8 心触发特殊产出

var uid: StringName
var species: StringName
var pos: Vector2 = Vector2.ZERO      ## 世界坐标（脚底），供渲染与交互

var affection: int = 0
var days_old: int = 0
var fed_today: int = 0
var pet_today: int = 0
var brushed_today: bool = false
var hugged_today: bool = false
var days_unfed: int = 0

var product_ready: bool = false
var product_quality: int = 0         ## 0 基础 / 1 银星 / 2 金星
var product_is_high: bool = false    ## 是否走 product_high（大罐牛奶 / 金蛋）
var sick: bool = false

var rng := RandomNumberGenerator.new()

func _init(p_uid: StringName = &"", p_species: StringName = &"", rng_seed: int = 0) -> void:
	uid = p_uid
	species = p_species
	if rng_seed != 0:
		rng.seed = rng_seed
	else:
		rng.randomize()

func data() -> AnimalData:
	return AnimalDB.get_animal(species)

# ---------------- 查询 ----------------

func is_adult() -> bool:
	var d := data()
	return d != null and days_old >= d.mature_days

func hearts() -> int:
	return clampi(affection / HEART_POINTS, 0, MAX_HEARTS)

func heart_label() -> String:
	return "%d 心" % hearts()

func is_hungry() -> bool:
	var d := data()
	return d != null and fed_today < d.feed_freq

## 能产出（成年 + 没病）
func is_producing() -> bool:
	return is_adult() and not sick

# ---------------- 互动 ----------------

## 喂食：每次 +10，按 feed_freq 计次
func feed() -> bool:
	if not is_hungry():
		return false
	affection = mini(affection + FEED_AFFECTION, MAX_AFFECTION)
	fed_today += 1
	return true

## 抚摸：每天最多 2 次
func pet() -> bool:
	if pet_today >= 2:
		return false
	affection = mini(affection + PET_AFFECTION, MAX_AFFECTION)
	pet_today += 1
	return true

## 刷毛：每天 1 次
func brush() -> bool:
	if brushed_today:
		return false
	affection = mini(affection + BRUSH_AFFECTION, MAX_AFFECTION)
	brushed_today = true
	return true

## 抱抱：家禽专属，每天 1 次
func hug() -> bool:
	var d := data()
	if d == null or not d.is_poultry() or hugged_today:
		return false
	affection = mini(affection + HUG_AFFECTION, MAX_AFFECTION)
	hugged_today = true
	return true

## 产出（挤奶 / 捡蛋）。
## in_window = 时间窗口是否允许（奶牛挤奶仅 6:00–9:00）。
## 返回 {id, count, quality}，不满足条件返回 {}。
func produce(in_window: bool = true) -> Dictionary:
	var d := data()
	if d == null or not is_producing() or not product_ready:
		return {}
	if d.timed_product and not in_window:
		return {}
	var pid: StringName = d.product
	if product_is_high and d.product_high != StringName(""):
		pid = d.product_high
	var count := rng.randi_range(d.product_min, d.product_max)
	product_ready = false
	product_is_high = false
	return {"id": pid, "count": count, "quality": product_quality}

# ---------------- 跨日 ----------------

## 跨日结算，返回事件列表 [{uid, type}]，type: product / sick / hungry
func advance_day() -> Array:
	var d := data()
	var events: Array = []
	if d == null:
		return events

	days_old += 1

	# 漏喂惩罚（每漏一餐 -15）
	var missed: int = maxi(0, d.feed_freq - fed_today)
	if missed > 0:
		affection = maxi(0, affection - MISS_FEED_PENALTY * missed)
		events.append({"uid": uid, "type": "hungry"})
	if fed_today == 0:
		days_unfed += 1
	else:
		days_unfed = 0

	# 生病判定：好感 < 3 心 且 连续漏喂 ≥ 2 天
	if not sick and hearts() < SICK_HEART_THRESHOLD and days_unfed >= 2:
		if rng.randf() < SICK_CHANCE:
			sick = true
			events.append({"uid": uid, "type": "sick"})

	if sick:
		affection = maxi(0, affection - SICK_DAILY_PENALTY)

	# 新一天的产出（今晨已喂饱的成年健康动物）
	product_ready = false
	product_is_high = false
	if is_producing() and fed_today >= d.feed_freq:
		var skip := hearts() <= 2 and rng.randf() < LOW_HEART_NO_PRODUCT
		if not skip:
			product_ready = true
			product_quality = _roll_quality()
			if d.product_high != StringName("") and hearts() >= HIGH_HEART:
				if d.high_chance <= 0.0 or rng.randf() < d.high_chance:
					product_is_high = true
			events.append({"uid": uid, "type": "product"})

	# 日终重置
	fed_today = 0
	pet_today = 0
	brushed_today = false
	hugged_today = false
	return events

func _roll_quality() -> int:
	var h := hearts()
	if h >= 9:
		return 2      # 金星
	if h >= 6:
		return 1      # 银星
	return 0

# ---------------- 调试 / 测试辅助 ----------------

func debug_grow_adult() -> void:
	var d := data()
	if d != null:
		days_old = d.mature_days

func debug_feed_full() -> void:
	var d := data()
	if d != null:
		fed_today = d.feed_freq
