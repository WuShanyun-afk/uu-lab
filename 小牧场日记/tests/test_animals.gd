extends Node
## 动物系统验收（GDD §11 里程碑 3）
## 验收标准：喂食好感 +10；挤奶在 6:00–9:00 产出牛奶；捡蛋进背包
## 运行： godot --headless --path <项目> res://tests/test_animals.tscn

var _fails: Array[String] = []
var _n := 0

func _check(cond: bool, label: String) -> void:
	_n += 1
	if not cond:
		_fails.append(label)
	print(("  [OK] " if cond else "  [FAIL] ") + label)

func _ready() -> void:
	print("=== 动物系统验收（里程碑 3）===")

	_test_db()
	_test_basic()
	_test_interactions()
	_test_growth()
	_test_product()
	_test_quality()
	_test_high_product()
	_test_penalty()
	_test_sick()
	_test_herd()
	_test_acceptance()

	var ok := _fails.is_empty()
	print("=== 结果：%s（共 %d 项）===" % ["全部通过" if ok else "失败 %d 项" % _fails.size(), _n])
	if not ok:
		for f in _fails:
			print("   ! " + f)
	get_tree().quit(0 if ok else 1)

# ---------------- 1. 数据表 ----------------

func _test_db() -> void:
	var cow: AnimalData = AnimalDB.get_animal(&"cow")
	_check(cow != null, "能查到奶牛")
	if cow:
		_check(cow.display_name == "奶牛", "奶牛中文名")
		_check(cow.price == 800, "奶牛售价 800G")
		_check(cow.product == &"milk", "奶牛产出 milk")
		_check(cow.product_min == 1 and cow.product_max == 2, "奶牛产奶 1–2")
		_check(cow.product_high == &"milk_large", "奶牛高好感产大罐牛奶")
		_check(cow.feed_freq == 2, "奶牛每天喂 2 次")
		_check(cow.mature_days == 7, "奶牛 7 天成年")
		_check(cow.timed_product, "奶牛产出需时间窗口（挤奶）")
		_check(not cow.is_poultry(), "奶牛是家畜")

	var chick: AnimalData = AnimalDB.get_animal(&"chicken")
	_check(chick != null, "能查到鸡")
	if chick:
		_check(chick.display_name == "鸡", "鸡中文名")
		_check(chick.price == 200, "鸡售价 200G")
		_check(chick.product == &"egg", "鸡产出 egg")
		_check(chick.feed_freq == 1, "鸡每天喂 1 次")
		_check(chick.mature_days == 3, "鸡 3 天成年")
		_check(not chick.timed_product, "鸡蛋随时可捡")
		_check(chick.is_poultry(), "鸡是家禽")
		_check(is_equal_approx(chick.high_chance, 0.15), "鸡高好感金蛋概率 0.15")

	_check(AnimalDB.all_ids().size() >= 2, "动物表 >= 2 种")
	_check(ProductDB.has(&"milk"), "产物表有牛奶")
	_check(ProductDB.has(&"egg"), "产物表有鸡蛋")
	_check(ProductDB.has(&"feed"), "产物表有饲料")
	_check(ProductDB.display_name(&"milk") == "牛奶", "牛奶显示名")
	_check(ProductDB.price(&"milk_large") == 200, "大罐牛奶 200G")
	_check(ProductDB.price(&"feed") == 20, "饲料 20G")

# ---------------- 2. 初始状态 ----------------

func _test_basic() -> void:
	var a := AnimalState.new(&"c1", &"cow", 111)
	_check(a.hearts() == 0, "初始 0 心")
	_check(not a.is_adult(), "初始未成年")
	_check(a.is_hungry(), "初始饿")
	_check(not a.is_producing(), "未成年不产出")
	_check(a.data() != null, "能拿到静态数据")
	_check(a.produce(true).is_empty(), "没产出时挤奶失败")

# ---------------- 3. 互动 ----------------

func _test_interactions() -> void:
	var a := AnimalState.new(&"c1", &"cow", 222)
	a.debug_grow_adult()

	_check(a.feed(), "第一次喂食成功")
	_check(a.affection == AnimalState.FEED_AFFECTION, "喂食好感 +10（实际 %d）" % a.affection)
	_check(a.fed_today == 1, "fed_today = 1")
	_check(a.feed(), "第二次喂食成功（奶牛需 2 次）")
	_check(a.affection == 20, "两次喂食好感 20")
	_check(not a.feed(), "喂满后不再接受喂食")
	_check(not a.is_hungry(), "喂饱后不饿")

	_check(a.pet(), "抚摸成功")
	_check(a.affection == 20 + AnimalState.PET_AFFECTION, "抚摸好感 +5")
	_check(a.pet(), "第二次抚摸成功")
	_check(not a.pet(), "每天最多摸 2 次")

	_check(a.brush(), "刷毛成功")
	_check(not a.brush(), "每天只能刷一次")

	_check(not a.hug(), "奶牛不能抱（家禽专属）")
	var chick := AnimalState.new(&"h1", &"chicken", 333)
	_check(chick.hug(), "鸡可以抱")
	_check(not chick.hug(), "每天只能抱一次")

	# 好感上限
	var b := AnimalState.new(&"c2", &"cow", 444)
	b.affection = 999
	b.feed()
	_check(b.affection == AnimalState.MAX_AFFECTION, "好感封顶 1000")

# ---------------- 4. 成长 ----------------

func _test_growth() -> void:
	var a := AnimalState.new(&"c1", &"chicken", 555)
	_check(not a.is_adult(), "小鸡未成年")
	a.advance_day()
	_check(a.days_old == 1, "跨日 days_old = 1")
	_check(not a.is_adult(), "1 天还没成年（鸡需 3 天）")
	a.advance_day()
	a.advance_day()
	_check(a.days_old == 3, "3 天")
	_check(a.is_adult(), "鸡 3 天成年")

# ---------------- 5. 产出 ----------------

func _test_product() -> void:
	# 成年 + 喂饱 → 次日有产出
	var cow := AnimalState.new(&"c1", &"cow", 666)
	cow.debug_grow_adult()
	_check(not cow.product_ready, "未跨日时无产出")
	cow.feed()
	cow.feed()
	cow.advance_day()
	_check(cow.product_ready, "喂饱跨日后有产出")

	# 挤奶窗口
	var out_window := cow.produce(false)
	_check(out_window.is_empty(), "非 6:00–9:00 挤不出奶")
	_check(cow.product_ready, "窗口外失败不消耗产出")
	var out := cow.produce(true)
	_check(not out.is_empty(), "6:00–9:00 挤奶成功")
	_check(out.get("id") == "milk", "产出 id = milk")
	_check(int(out.get("count")) >= 1 and int(out.get("count")) <= 2, "奶量 1–2（实际 %s）" % str(out.get("count")))
	_check(not cow.product_ready, "挤奶后产出清空")

	# 鸡：随时可捡
	var chick := AnimalState.new(&"h1", &"chicken", 777)
	chick.debug_grow_adult()
	chick.feed()
	chick.advance_day()
	_check(chick.product_ready, "鸡喂饱跨日后有蛋")
	var e := chick.produce(false)
	_check(not e.is_empty(), "鸡蛋不挑时间，随时可捡")
	_check(e.get("id") == "egg", "产出 id = egg")

	# 漏喂 → 不产出
	var c2 := AnimalState.new(&"c3", &"cow", 888)
	c2.debug_grow_adult()
	c2.advance_day()
	_check(not c2.product_ready, "没喂食则次日无产出")

# ---------------- 6. 品质分级 ----------------

func _test_quality() -> void:
	var a := AnimalState.new(&"c1", &"cow", 999)
	a.debug_grow_adult()
	a.affection = 300
	_check(a.hearts() == 3, "300 好感 = 3 心")
	_check(a._roll_quality() == 0, "3 心 → 基础品质")
	a.affection = 650
	_check(a.hearts() == 6, "650 好感 = 6 心")
	_check(a._roll_quality() == 1, "6 心 → 银星")
	a.affection = 950
	_check(a.hearts() == 9, "950 好感 = 9 心")
	_check(a._roll_quality() == 2, "9 心 → 金星")

# ---------------- 7. 高好感特殊产出 ----------------

func _test_high_product() -> void:
	var cow := AnimalState.new(&"c1", &"cow", 1234)
	cow.debug_grow_adult()
	cow.affection = 850      # 8 心
	cow.feed()
	cow.feed()
	cow.advance_day()
	var out := cow.produce(true)
	_check(out.get("id") == "milk_large", "奶牛 8 心产大罐牛奶（实际 %s）" % str(out.get("id")))

	# 鸡 ≥8 心：蛋 or 金蛋
	var chick := AnimalState.new(&"h1", &"chicken", 4321)
	chick.debug_grow_adult()
	chick.affection = 900
	var saw_gold := false
	for i in range(60):
		chick.feed()
		chick.advance_day()
		if chick.product_ready and chick.product_is_high:
			saw_gold = true
			break
	_check(saw_gold, "鸡 8 心+ 会产出金蛋（60 次内出现）")

# ---------------- 8. 漏喂惩罚 ----------------

func _test_penalty() -> void:
	var a := AnimalState.new(&"c1", &"cow", 1111)
	a.debug_grow_adult()
	a.feed()                     # 2 次里只喂了 1 次
	a.affection = 500            # 喂食的 +10 先归零基准，单看漏喂惩罚
	a.advance_day()
	_check(a.affection == 500 - AnimalState.MISS_FEED_PENALTY, "漏 1 餐 -15（实际 %d）" % a.affection)

	var b := AnimalState.new(&"c2", &"cow", 2222)
	b.debug_grow_adult()
	b.affection = 500
	b.advance_day()              # 一次没喂
	_check(b.affection == 500 - AnimalState.MISS_FEED_PENALTY * 2, "漏 2 餐 -30（实际 %d）" % b.affection)

	# 好感不会变负
	var c := AnimalState.new(&"c3", &"cow", 3333)
	c.affection = 10
	c.advance_day()
	_check(c.affection == 0, "好感最低为 0")

# ---------------- 9. 生病 ----------------

func _test_sick() -> void:
	var a := AnimalState.new(&"c1", &"cow", 424242)
	a.debug_grow_adult()
	a.affection = 0
	var got_sick := false
	for i in range(200):
		a.advance_day()
		if a.sick:
			got_sick = true
			break
	_check(got_sick, "低好感 + 连续漏喂 → 会生病（200 次内）")
	if got_sick:
		_check(not a.is_producing(), "生病时不产出")

# ---------------- 10. 牧群 ----------------

func _test_herd() -> void:
	var h := Herd.new(20261015)
	var c1 := h.add(&"cow", 300, Vector2(100, 100))
	var c2 := h.add(&"cow", 0, Vector2(300, 300))
	var k1 := h.add(&"chicken", 0, Vector2(120, 100))
	_check(h.size() == 3, "牧群 3 只")
	_check(c1 != null and k1 != null, "添加成功返回实例")
	_check(h.count_species(&"cow") == 2, "奶牛 2 头")
	_check(h.count_species(&"chicken") == 1, "鸡 1 只")
	_check(h.add(&"dragon", 0) == null, "未知物种拒绝")
	_check(c1.uid != c2.uid, "uid 唯一")
	_check(h.total_hearts() == 3, "总心数 = 3")

	var near := h.nearest(Vector2(105, 100), 40.0)
	_check(near == c1, "nearest 命中奶牛 1")
	_check(h.nearest(Vector2(1000, 1000), 40.0) == null, "远处找不到动物")

	for a in h.animals:
		a.debug_grow_adult()
		a.debug_feed_full()
		a.affection = 500        # 高好感，避免「低好感 10% 不产出」干扰计数
	var ev := h.advance_day()
	_check(ev.size() >= 3, "跨日事件 >= 3（实际 %d）" % ev.size())
	var products := 0
	for e in ev:
		if e["type"] == "product":
			products += 1
	_check(products == 3, "3 只动物都产出")

	_check(h.remove(c1.uid), "移除成功")
	_check(h.size() == 2, "移除后 2 只")
	_check(not h.remove(&"nope"), "移除不存在的返回 false")

# ---------------- 11. 里程碑验收综合 ----------------

func _test_acceptance() -> void:
	GameState.reset()
	_check(GameState.count_item(&"milk") == 0, "背包初始无牛奶")

	# ① 喂食好感 +10
	var cow := AnimalState.new(&"c1", &"cow", 5150)
	cow.debug_grow_adult()
	cow.feed()
	_check(cow.affection == 10, "【验收①】喂食好感 +10")

	# ② 挤奶在 6:00–9:00 产出牛奶
	GameClock.debug_set_minutes(0)          # 6:00
	_check(GameClock.minutes < 180, "6:00 在挤奶窗口内")
	GameClock.debug_set_minutes(300)        # 11:00
	_check(GameClock.minutes >= 180, "11:00 已出挤奶窗口")

	cow.debug_feed_full()
	cow.advance_day()
	var in_window := GameClock.minutes < 180
	_check(not in_window, "11:00 时窗口判定为假")
	_check(cow.produce(in_window).is_empty(), "【验收②】非窗口挤不出奶")
	GameClock.debug_set_minutes(0)
	var milk := cow.produce(GameClock.minutes < 180)
	_check(not milk.is_empty() and milk["id"] == "milk", "【验收②】6:00–9:00 产出牛奶")
	if not milk.is_empty():
		GameState.add_item(milk["id"], milk["count"])
	_check(GameState.count_item(&"milk") >= 1, "牛奶进了背包")

	# ③ 捡蛋进背包
	var chick := AnimalState.new(&"h1", &"chicken", 6161)
	chick.debug_grow_adult()
	chick.debug_feed_full()
	chick.advance_day()
	var egg := chick.produce(true)
	_check(not egg.is_empty() and egg["id"] == "egg", "【验收③】捡到鸡蛋")
	if not egg.is_empty():
		GameState.add_item(egg["id"], egg["count"])
	_check(GameState.count_item(&"egg") == 1, "【验收③】鸡蛋进了背包")

	# 饲料消耗
	GameState.add_item(&"feed", 5)
	_check(GameState.count_item(&"feed") == 5, "拿到 5 份饲料")
	_check(GameState.remove_item(&"feed", 1), "消耗 1 份饲料")
	_check(GameState.count_item(&"feed") == 4, "饲料剩 4")
	_check(not GameState.remove_item(&"feed", 99), "饲料不够时拒绝消耗")
