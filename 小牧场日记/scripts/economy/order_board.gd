class_name OrderBoard
extends RefCounted
## 订单板（模块 7 需求 3）—— NPC 委托，限时完成
##
## 规则（GDD §5.5 + 本模块落地口径）：
##   · 每 3 天刷新，同时最多挂着 2 单
##   · 每单给 2 天期限，第 2 天的 14:00 前送达（和 GDD「14:00 前送达」对齐）
##   · 报酬 = 行情价 × 数量 × 1.5，再按 NPC 加一点小费（±10%）
##   · 完成 10 单 → 解锁「村中名人」成就（GameState flag）
##
## 为什么是 RefCounted 而不是 autoload：
##   订单状态要和「这一局」绑定，将来做存档时它是一坨要序列化的数据。
##   autoload 单例会跨场景活着，反而更难存 —— 由 main 持有实例，随存随取。
##
## 为什么 tick() 要传 pool：
##   订单不该自己去翻 ItemDB —— 那样测试要准备整个物品库。
##   传一个「能接单的物品 id 数组」进来，测试就能塞 3 个假 id 断言刷新逻辑。
##
## 时间用**绝对分钟**（day * 1440 + minute）比较，不用 (day, minute) 二元组 ——
## 跨日那一刻的边界条件会少一半。

const REFRESH_DAYS := 3
const MAX_ACTIVE := 2
const DUE_DAYS := 2
const DUE_MINUTE := 8 * 60            ## 14:00（GameClock.minutes 从 6:00 起算，所以是 480）
const REWARD_MULT := 1.5
const FAMOUS_GOAL := 10
const MINUTES_PER_DAY := 1440
## 订单池的价格上限：再贵的就是觉醒专属 / 稀有货，不该被 NPC 随口点单
const POOL_PRICE_CAP := 600
## 每单数量范围
const COUNT_RANGE := [1, 4]

const NPC := [
	{"name": "玛莎", "title": "杂货店老板娘", "color": "#E8A93B"},
	{"name": "老周", "title": "铁匠", "color": "#8C6E5A"},
	{"name": "小葵", "title": "兽医", "color": "#6FBF73"},
	{"name": "阿海", "title": "渔夫", "color": "#4A7BA8"},
	{"name": "林教授", "title": "农学家", "color": "#9B7FC9"},
	{"name": "米娅", "title": "小女孩", "color": "#E27A9B"},
	{"name": "老陈", "title": "牧场前辈", "color": "#B98C6A"},
]

## 订单：{id, npc, title, item, count, reward, due_day, due_minute, status}
## status: "active" / "done" / "expired"
var orders: Array = []
var completed: int = 0
var failed: int = 0
## 上一次刷新的「天」（避免同一天重复刷）
var last_refresh_day: int = -999

var _next_id: int = 1
var _rng := RandomNumberGenerator.new()

func _init(seed_value: int = 20261101) -> void:
	_rng.seed = seed_value

# ---------------- 时间推进 ----------------

## 每天 / 每 tick 调。返回事件列表：
##   [{type: "new", order}, {type: "expired", order}, {type: "all_expired"}]
## main 拿它拼提示文字，本类不弹任何 UI。
func tick(day: int, minute: int, pool: Array, season: int = 0) -> Array:
	var events: Array = []
	events.append_array(_expire(day, minute))
	# 刷新：第 0 天开张就给 2 单，之后每 3 天补
	if day - last_refresh_day >= REFRESH_DAYS and _active().size() < MAX_ACTIVE:
		last_refresh_day = day
		var made := _refill(day, season, pool)
		for o in made:
			events.append({"type": "new", "order": o})
	return events

func _expire(day: int, minute: int) -> Array:
	var out: Array = []
	var now := abs_minute(day, minute)
	for o in orders:
		if o["status"] != "active":
			continue
		if now <= due_abs(o):
			continue
		o["status"] = "expired"
		failed += 1
		out.append({"type": "expired", "order": o})
	return out

static func abs_minute(day: int, minute: int) -> int:
	return day * MINUTES_PER_DAY + minute

static func due_abs(o: Dictionary) -> int:
	return abs_minute(int(o["due_day"]), int(o["due_minute"]))

## 补到 MAX_ACTIVE 单。池子空了就一单都刷不出来（不崩，也不刷假单）。
func _refill(day: int, season: int, pool: Array) -> Array:
	var made: Array = []
	var usable := _filter_pool(pool)
	if usable.is_empty():
		return made
	while _active().size() < MAX_ACTIVE:
		var o := _make_order(day, season, usable)
		if o.is_empty():
			break
		orders.append(o)
		made.append(o)
	return made

## 订单池过滤：只留能卖、且不是稀有货的
func _filter_pool(pool: Array) -> Array:
	var out: Array = []
	for id in pool:
		if not ItemDB.is_sellable(id):
			continue
		if ItemDB.price_of(id) > POOL_PRICE_CAP:
			continue
		out.append(id)
	return out

func _make_order(day: int, season: int, usable: Array) -> Dictionary:
	var item: StringName = usable[_rng.randi() % usable.size()]
	var n := _rng.randi_range(int(COUNT_RANGE[0]), int(COUNT_RANGE[1]))
	var base := Market.price(item, season, day) * n
	# 小费 ±10%，取整到 5G，读起来像个报价而不是随机数
	var tip := float(base) * REWARD_MULT * _rng.randf_range(-0.1, 0.1)
	var reward := int(round((float(base) * REWARD_MULT + tip) / 5.0)) * 5
	var npc: Dictionary = NPC[_rng.randi() % NPC.size()]
	var due_day := day + DUE_DAYS
	var o := {
		"id": _next_id,
		"npc": npc["name"],
		"title": npc["title"],
		"color": Color(npc["color"]),
		"item": item,
		"count": n,
		"reward": maxi(5, reward),
		"due_day": due_day,
		"due_minute": DUE_MINUTE,
		"status": "active",
	}
	_next_id += 1
	return o

# ---------------- 查询 ----------------

func _active() -> Array:
	var out: Array = []
	for o in orders:
		if o["status"] == "active":
			out.append(o)
	return out

func active_orders() -> Array:
	return _active()

func active_count() -> int:
	return _active().size()

## 还剩多少游戏分钟（负数 = 已过期）
func minutes_left(o: Dictionary, day: int, minute: int) -> int:
	return due_abs(o) - abs_minute(day, minute)

## 订单状态文案（货架 / 提示用）
func due_text(o: Dictionary, day: int, minute: int) -> String:
	var left := minutes_left(o, day, minute)
	if left <= 0:
		return "已超时"
	var d := floori(float(left) / float(MINUTES_PER_DAY))
	var m := left % MINUTES_PER_DAY
	var hh := floori(float(m) / 60.0)
	var mm := m % 60
	if d > 0:
		return "剩 %d 天 %d 小时" % [d, hh]
	if hh > 0:
		return "剩 %d 小时 %d 分" % [hh, mm]
	return "剩 %d 分" % mm

## 能不能交付：返回 {ok, need, have, reason}
func can_deliver(o: Dictionary, count_fn: Callable) -> Dictionary:
	if o.get("status", "") != "active":
		return {"ok": false, "reason": "这单已经结束了"}
	var need := int(o["count"])
	var have := int(count_fn.call(o["item"]))
	if have < need:
		return {"ok": false, "need": need, "have": have,
			"reason": "还差 %d 个" % (need - have)}
	return {"ok": true, "need": need, "have": have, "reason": ""}

## 交付。**本类不碰背包也不碰金币** —— 只把状态改成 done 并返回结算信息，
## 扣物品 / 加钱由 main 执行（和商店同一套「规则与副作用分离」的写法）。
func deliver(o: Dictionary) -> Dictionary:
	if o.get("status", "") != "active":
		return {}
	o["status"] = "done"
	completed += 1
	return {
		"order": o,
		"item": o["item"],
		"count": int(o["count"]),
		"reward": int(o["reward"]),
		"npc": o["npc"],
		"famous": completed >= FAMOUS_GOAL,
	}

## 过期 / 已完成的老单攒多了就清掉，只留 active（UI 只显示 active，清不清无所谓，
## 但跨季跑几十天之后 orders 会膨胀，跨日清一次是便宜的保险）
func prune() -> int:
	var before := orders.size()
	var keep: Array = []
	for o in orders:
		if o["status"] == "active":
			keep.append(o)
	orders = keep
	return before - keep.size()

# ---------------- 存档 ----------------

func to_dict() -> Dictionary:
	return {
		"orders": orders.duplicate(true),
		"completed": completed,
		"failed": failed,
		"last_refresh_day": last_refresh_day,
		"next_id": _next_id,
	}

func from_dict(d: Dictionary) -> void:
	orders = (d.get("orders", []) as Array).duplicate(true)
	# ⚠️ JSON 回来之后：color 是 "#RRGGBB" 字符串、item 是 String。
	#    item 不转回 StringName 的话，main 用 GameState.count_item(o["item"]) 会永远查到 0
	#    （inventory 的键是 StringName），订单就变成永远交不了 —— 模块 8 踩过。
	for o in orders:
		if typeof(o.get("color")) == TYPE_STRING:
			o["color"] = Color(str(o["color"]))
		if typeof(o.get("item")) == TYPE_STRING:
			o["item"] = StringName(str(o["item"]))
	completed = int(d.get("completed", 0))
	failed = int(d.get("failed", 0))
	last_refresh_day = int(d.get("last_refresh_day", -999))
	_next_id = int(d.get("next_id", 1))
