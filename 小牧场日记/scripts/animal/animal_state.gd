class_name AnimalState
extends RefCounted
## 单只动物的状态与逻辑（GDD §3.3 好感 / §3.4 产出 / §3.2 成长 / 模块 4 + 模块 5）
##
## 纯逻辑，不碰节点、不碰渲染。渲染由 AnimalNode 读这里的状态。
## 和 FarmGrid 一样的分层哲学：逻辑可 headless 断言，素材到位只换渲染层。
##
## ── 模块 4 的好感规则（0–10 心，获取与衰减）──
##
##   获取                                   衰减
##   喂食        +10 / 餐                    漏喂          -15 / 餐
##   抚摸        +5 / 次（上限 pet_limit）    喂饱但被冷落   -2 / 天
##   刷毛        +8 / 天（仅 brushable）      生病          -20 / 天
##   抱抱（家禽）+6 / 天                      （雨雪留棚：WeatherSystem 给 +3，不在这里）
##
## 「冷落」的定义是**该物种所有能做的互动一个都没做**：
##   蜜蜂不能摸、不能刷、不是家禽 → 只喂食就够，永远不会被判冷落。
##   而且漏喂当天不叠加冷落（避免同一件事罚两次）。
##
## 1 心 = 100 好感，封顶 1000（= 10 心）。低于 3 心 + 连续漏喂 ≥ 2 天 → 掷骰生病。
##
## ── 模块 5 往这个类里塞了三件新东西 ──
##
## ① **成长阶段**：BABY → ADULT。`body_scale()` 让渲染层能把幼崽画小一点，
##    幼年不产出、不能刷毛、不能繁殖。跨过 mature_days 那天广播 `mature` 事件。
## ② **觉醒**：好感**到达** 1000 那一刻置 `awakened`（永久），并挂 `just_awakened`
##    标记等 main 弹对话。觉醒后免疫生病、漏喂不掉好感，每日产出 30% 变觉醒产物。
## ③ **生病 / 妊娠**：生病多了 `sick_days` 计数（可被药剂 cure()，拖 7 天会病逝）；
##    妊娠多了 `pregnant_days` 倒计时（归零时广播 `born`，由 Herd 生崽）。
##
## ⚠️ `advance_day()` 是**全局语义**（一天过一次），写测试/工具脚本时必须记住。

const HEART_POINTS := 100
const MAX_AFFECTION := 1000
const MAX_HEARTS := 10

const FEED_AFFECTION := 10
const PET_AFFECTION := 5
const BRUSH_AFFECTION := 8
const HUG_AFFECTION := 6
const MISS_FEED_PENALTY := 15        ## 每漏喂一餐
const NEGLECT_PENALTY := 2           ## 喂饱了但一整天没被摸/刷/抱

const SICK_HEART_THRESHOLD := 3
const SICK_CHANCE := 0.15
const SICK_DAILY_PENALTY := 20
const LOW_HEART_NO_PRODUCT := 0.10   ## 0–2 心：10% 概率不产出
const HIGH_HEART := 8                ## ≥8 心触发特殊产出

## ── 模块 5 ──
const AWAKENING_CHANCE := 0.30       ## 觉醒动物每天有 30% 把产出换成觉醒产物
const CURE_AFFECTION := 30           ## 用药康复后回补的好感（治病不是惩罚玩家）
const SICK_DEATH_DAYS := 7           ## 连续生病 7 天不治 → 病逝（会被 Herd 移出牧场）
const SICK_CRITICAL_DAYS := 5        ## 第 5 天起每天广播 critical 告警
const BABY_SCALE := 0.62             ## 幼崽渲染缩放下限

enum Growth { BABY, ADULT }

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
var product_is_high: bool = false    ## 是否走 product_high（大罐牛奶 / 细羊毛 / 蜂王浆）
var product_awakened: bool = false   ## 模块 5：本次产出是不是觉醒产物
var produce_timer: int = 0           ## 距上次产出的天数（绵羊 3 天 / 羊驼 4 天 / 蜜蜂 4 天）
var sick: bool = false

## ── 模块 5 新增状态 ──
var awakened: bool = false           ## 已觉醒（永久，一旦置位不会掉）
var just_awakened: bool = false      ## 刚觉醒（main 弹完对话后清掉，避免重复弹）
var sick_days: int = 0               ## 连续生病天数
var pregnant_days: int = 0           ## 妊娠剩余天数（> 0 = 妊娠中）
var gestation: int = 0               ## 本次妊娠总天数（显示用）
var partner_species: StringName = &"" ## 配偶物种（生崽时的物种来源，正常 == species）

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

## 成长阶段（模块 5 需求 2）
func growth_stage() -> int:
	return Growth.ADULT if is_adult() else Growth.BABY

func stage_name() -> String:
	return "成年" if is_adult() else "幼年"

## "幼年奶牛" / "奶牛" —— HUD 与提示条用
func display_label() -> String:
	var d := data()
	if d == null:
		return str(species)
	return d.display_name if is_adult() else "幼年%s" % d.display_name

## 还要几天成年（已成年 = 0）
func days_to_mature() -> int:
	var d := data()
	return 0 if d == null else maxi(0, d.mature_days - days_old)

## 渲染缩放：幼崽 0.62 → 成年 1.0 线性长大（AnimalNode 读它）
func body_scale() -> float:
	var d := data()
	if d == null or d.mature_days <= 0 or days_old >= d.mature_days:
		return 1.0
	return lerpf(BABY_SCALE, 1.0, float(days_old) / float(d.mature_days))

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

## 妊娠中？
func is_pregnant() -> bool:
	return pregnant_days > 0

## 今天还能摸几次
func pet_left() -> int:
	var d := data()
	return 0 if d == null else maxi(0, d.pet_limit - pet_today)

## 产出口令（"挤奶" / "剪毛" / "捡拾" / "采蜜"）
func action_name() -> String:
	var d := data()
	return d.action_name() if d != null else "互动"

# ---------------- 好感（唯一的加好感入口）----------------

## 加好感 + 检查觉醒。所有好感获取都必须走这里，否则会漏掉觉醒判定。
func _gain(points: int) -> void:
	affection = mini(affection + points, MAX_AFFECTION)
	if affection >= MAX_AFFECTION and not awakened:
		awakened = true
		just_awakened = true

## 给 Herd / 天气系统用的公开入口（雨雪留棚 +3）
func gain_affection(n: int) -> void:
	if n > 0:
		_gain(n)

# ---------------- 互动 ----------------

## 喂食：每次 +10，按 feed_freq 计次
func feed() -> bool:
	if not is_hungry():
		return false
	_gain(FEED_AFFECTION)
	fed_today += 1
	return true

## 抚摸：每天上限来自数据表（蜜蜂 = 0 → 永远摸不到）
func pet() -> bool:
	var d := data()
	if d == null or pet_today >= d.pet_limit:
		return false
	_gain(PET_AFFECTION)
	pet_today += 1
	return true

## 刷毛：每天 1 次，且只有 brushable 的物种能做（牛/羊/山羊/羊驼）。
## ⚠️ 幼崽也能刷毛（当抚摸用）—— 拦住幼年的是**剪毛产出**（is_producing 要求成年），
##    不是刷毛本身。别在这里加 is_adult() 门禁，模块 4 的测试就是拿幼崽刷的。
func brush() -> bool:
	var d := data()
	if d == null or not d.brushable or brushed_today:
		return false
	_gain(BRUSH_AFFECTION)
	brushed_today = true
	return true

## 抱抱：家禽专属，每天 1 次
func hug() -> bool:
	var d := data()
	if d == null or not d.is_poultry() or hugged_today:
		return false
	_gain(HUG_AFFECTION)
	hugged_today = true
	return true

## 用药治疗（模块 5 需求 3）。没病返回 false，不浪费药。
func cure() -> bool:
	if not sick:
		return false
	sick = false
	sick_days = 0
	_gain(CURE_AFFECTION)
	return true

## 今天有没有被「好好对待」过（摸 / 刷 / 抱 任意一次）
func was_pampered() -> bool:
	return pet_today > 0 or brushed_today or hugged_today

## 产出（挤奶 / 剪毛 / 捡蛋 / 采蜜 / 觉醒产物）。
## in_window = 时间窗口是否允许（奶牛挤奶仅 6:00–9:00；0 表示全天可产）。
## 返回 {id, count, quality}，不满足条件返回 {}。
func produce(in_window: bool = true) -> Dictionary:
	var d := data()
	if d == null or not is_producing() or not product_ready:
		return {}
	if d.timed_product and not in_window:
		return {}
	var pid: StringName = d.product
	var count := rng.randi_range(d.product_min, d.product_max)
	if product_awakened and Awakening.has(species):
		pid = Awakening.gift(species)
		count = 1
	elif product_is_high and d.product_high != StringName(""):
		pid = d.product_high
	product_ready = false
	product_is_high = false
	product_awakened = false
	produce_timer = 0        # 周期重新计时（绵羊剪完毛要等 3 天）
	return {"id": pid, "count": count, "quality": product_quality}

# ---------------- 跨日 ----------------

## 跨日结算，返回事件列表 [{uid, type, ...}]
## type: mature / born / hungry / neglect / sick / critical / died / product
func advance_day() -> Array:
	var d := data()
	var events: Array = []
	if d == null:
		return events

	var was_adult := is_adult()
	days_old += 1
	produce_timer += 1

	# ① 成长里程碑（模块 5 需求 2）
	if not was_adult and is_adult():
		events.append({"uid": uid, "type": "mature", "species": species})

	# ② 妊娠倒计时（模块 5 需求 4）：归零就广播 born，生崽交给 Herd
	if pregnant_days > 0:
		pregnant_days -= 1
		if pregnant_days == 0:
			events.append({"uid": uid, "type": "born", "species": species})

	# ③ 漏喂惩罚（每漏一餐 -15）+ ④ 冷落衰减（喂饱但整天没被摸/刷/抱）
	# ⚠️ 觉醒动物**两条都免疫**：它有灵性，自己觅食、自己找乐子。
	#    不豁免的话，10 心会掉成 9 心，「觉醒」这个永久状态跟心数就脱节了。
	var missed: int = maxi(0, d.feed_freq - fed_today)
	if missed > 0:
		if not awakened:
			affection = maxi(0, affection - MISS_FEED_PENALTY * missed)
		events.append({"uid": uid, "type": "hungry"})
	if fed_today == 0:
		days_unfed += 1
	else:
		days_unfed = 0

	if not awakened and missed == 0 and d.can_be_pampered() and not was_pampered():
		affection = maxi(0, affection - NEGLECT_PENALTY)
		events.append({"uid": uid, "type": "neglect"})

	# ⑤ 生病判定：好感 < 3 心 且 连续漏喂 ≥ 2 天（觉醒动物免疫）
	if not awakened and not sick and hearts() < SICK_HEART_THRESHOLD and days_unfed >= 2:
		if rng.randf() < SICK_CHANCE:
			sick = true
			sick_days = 0
			events.append({"uid": uid, "type": "sick"})

	# ⑥ 生病持续伤害 + 恶化（模块 5 需求 3：拖久了要用药，再拖就没了）
	if sick:
		sick_days += 1
		affection = maxi(0, affection - SICK_DAILY_PENALTY)
		if sick_days >= SICK_DEATH_DAYS:
			events.append({"uid": uid, "type": "died", "species": species})
		elif sick_days >= SICK_CRITICAL_DAYS:
			events.append({"uid": uid, "type": "critical", "species": species})

	# ⑦ 新一天的产出（今晨已喂饱的成年健康动物 + 产出周期到了）
	product_ready = false
	product_is_high = false
	product_awakened = false
	if is_producing() and fed_today >= d.feed_freq and produce_timer >= d.produce_period:
		var skip := hearts() <= 2 and rng.randf() < LOW_HEART_NO_PRODUCT
		if not skip:
			product_ready = true
			product_quality = _roll_quality()
			if awakened and Awakening.has(species) and rng.randf() < AWAKENING_CHANCE:
				product_awakened = true          # 觉醒产物优先（10 心必然 ≥8 心）
				product_quality = 0              # 觉醒产物本身已是天价，不再叠品质星
			elif d.product_high != StringName("") and hearts() >= HIGH_HEART:
				if d.high_chance <= 0.0 or rng.randf() < d.high_chance:
					product_is_high = true
			events.append({"uid": uid, "type": "product"})

	# ⑧ 日终重置
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

## 让产出立刻就绪（新买的成年动物开局就能挤一次，方便试玩 / 截图）
func debug_ready_produce() -> void:
	var d := data()
	if d == null:
		return
	produce_timer = d.produce_period
	product_ready = true
	product_quality = _roll_quality()

## 直接推到觉醒（截图 / 试玩用，正常玩法靠喂到 10 心）
func debug_awaken() -> void:
	_gain(MAX_AFFECTION)

## 直接挂上妊娠（截图 / 测试用）
func debug_pregnant(days: int = 1) -> void:
	pregnant_days = maxi(1, days)
	gestation = pregnant_days

# ---------------- 存档（模块 8）----------------
#
# ⚠️ just_awakened **不存**：它只是「main 还没弹觉醒对话」的临时标记，
#    存了的话读档会重新弹一遍觉醒演出 —— 玩家会以为出了 bug。
# ⚠️ rng.state 存字符串：64 位整数过 JSON 的 double 会掉精度。

func to_dict() -> Dictionary:
	return {
		"uid": String(uid),
		"species": String(species),
		"x": pos.x,
		"y": pos.y,
		"affection": affection,
		"days_old": days_old,
		"fed_today": fed_today,
		"pet_today": pet_today,
		"brushed_today": brushed_today,
		"hugged_today": hugged_today,
		"days_unfed": days_unfed,
		"product_ready": product_ready,
		"product_quality": product_quality,
		"product_is_high": product_is_high,
		"product_awakened": product_awakened,
		"produce_timer": produce_timer,
		"sick": sick,
		"sick_days": sick_days,
		"awakened": awakened,
		"pregnant_days": pregnant_days,
		"gestation": gestation,
		"partner": String(partner_species),
		"rng_state": str(rng.state),
	}

func from_dict(d: Dictionary) -> void:
	uid = StringName(str(d.get("uid", uid)))
	species = StringName(str(d.get("species", species)))
	pos = Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
	affection = clampi(int(d.get("affection", 0)), 0, MAX_AFFECTION)
	days_old = maxi(0, int(d.get("days_old", 0)))
	fed_today = maxi(0, int(d.get("fed_today", 0)))
	pet_today = maxi(0, int(d.get("pet_today", 0)))
	brushed_today = bool(d.get("brushed_today", false))
	hugged_today = bool(d.get("hugged_today", false))
	days_unfed = maxi(0, int(d.get("days_unfed", 0)))
	product_ready = bool(d.get("product_ready", false))
	product_quality = clampi(int(d.get("product_quality", 0)), 0, 2)
	product_is_high = bool(d.get("product_is_high", false))
	product_awakened = bool(d.get("product_awakened", false))
	produce_timer = maxi(0, int(d.get("produce_timer", 0)))
	sick = bool(d.get("sick", false))
	sick_days = maxi(0, int(d.get("sick_days", 0)))
	awakened = bool(d.get("awakened", false))
	pregnant_days = maxi(0, int(d.get("pregnant_days", 0)))
	gestation = maxi(0, int(d.get("gestation", 0)))
	partner_species = StringName(str(d.get("partner", "")))
	just_awakened = false
	var st := int(str(d.get("rng_state", "0")))
	if st != 0:
		rng.state = st
