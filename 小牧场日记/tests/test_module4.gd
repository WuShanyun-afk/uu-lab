extends Node
## 模块 4 验收：动物系统（基础）+ 商店 + 挤奶小游戏
##
## 需求对照：
##   ① 至少 8 种动物（奶牛/山羊/绵羊/猪/鸡/鸭/火鸡/羊驼/蜜蜂）
##   ② 每种：购买价 / 产出 / 喂食频率 / 互动方式
##   ③ 好感 0-10 心，获取与衰减规则
##   ④ 挤奶小游戏（节奏条）
##   ⑤ 剪羊毛 / 捡蛋 / 抚摸 / 刷毛
##   ⑥ 与时间系统联动：每天推进时好感度变化
##
## 运行： godot --headless --path <项目> res://tests/test_module4.tscn

var _fails: Array[String] = []
var _n := 0

func _check(cond: bool, label: String) -> void:
	_n += 1
	if not cond:
		_fails.append(label)
	print(("  [OK] " if cond else "  [FAIL] ") + label)

func _ready() -> void:
	print("=== 模块 4 验收：动物系统（基础）===")
	_test_db()
	_test_hearts()
	_test_gain()
	_test_decay()
	_test_produce_period()
	_test_actions()
	_test_rhythm()
	_test_quality_items()
	await _test_shop_widget()
	await _test_main()
	var ok := _fails.is_empty()
	print("=== 结果：%s（共 %d 项）===" % ["全部通过" if ok else "失败 %d 项" % _fails.size(), _n])
	if not ok:
		for f in _fails:
			print("   ! " + f)
	get_tree().quit(0 if ok else 1)

# ---------------- 1. 动物数据表（需求 ① ②）----------------

func _test_db() -> void:
	print("[1] 动物数据表")
	var ids := AnimalDB.all_ids()
	_check(ids.size() >= 8, "动物表 >= 8 种（实际 %d）" % ids.size())
	var need := [&"cow", &"goat", &"sheep", &"pig", &"chicken", &"duck", &"turkey", &"alpaca", &"bee"]
	for id in need:
		_check(AnimalDB.get_animal(id) != null, "有 %s" % String(id))

	# 每种都必须给全「购买价 / 产出 / 喂食频率 / 互动方式」（需求 ②）
	var complete := true
	var missing := ""
	for id in ids:
		var a: AnimalData = AnimalDB.get_animal(id)
		if a.price <= 0 or a.product == StringName("") or a.feed_freq < 1 \
				or a.produce_action == "" or a.mature_days < 1 or a.produce_period < 1:
			complete = false
			missing += String(id) + " "
	_check(complete, "每种都有价格/产出/喂食频率/互动方式（缺：%s）" % missing)

	var cow: AnimalData = AnimalDB.get_animal(&"cow")
	_check(cow.price == 800 and cow.product == &"milk", "奶牛 800G / 产 milk")
	_check(cow.feed_freq == 2 and cow.mature_days == 7, "奶牛每天喂 2 次 / 7 天成年")
	_check(cow.timed_product and cow.produce_window == 180, "奶牛挤奶窗口 180 分钟（6:00–9:00）")
	_check(cow.window_text() == "06:00–09:00", "窗口文本（%s）" % cow.window_text())
	_check(cow.produce_action == "milk" and cow.needs_minigame(), "奶牛走挤奶小游戏")
	_check(cow.brushable and cow.pet_limit == 2, "奶牛可刷毛 / 每天摸 2 次")
	_check(cow.housing_name() == "畜舍", "奶牛住畜舍")

	var sheep: AnimalData = AnimalDB.get_animal(&"sheep")
	_check(sheep.produce_action == "shear" and sheep.produce_period == 3, "绵羊剪毛，3 天一轮")
	_check(sheep.product == &"wool" and sheep.product_high == &"wool_fine", "绵羊产羊毛 / 细羊毛")

	var bee: AnimalData = AnimalDB.get_animal(&"bee")
	_check(bee.kind == "special" and bee.housing == "hive", "蜜蜂是特殊种，住蜂箱")
	_check(bee.produce_action == "honey" and bee.produce_period == 4, "蜜蜂采蜜，4 天一轮")
	_check(bee.pet_limit == 0 and not bee.brushable, "蜜蜂不能摸不能刷")
	_check(not bee.can_be_pampered(), "蜜蜂不会被判「冷落」")
	_check(AnimalDB.get_animal(&"chicken").can_be_pampered(), "鸡可以被冷落（能抱能摸）")

	_check(AnimalDB.of_housing("coop").size() == 3, "禽舍 3 种（鸡/鸭/火鸡）")
	_check(AnimalDB.of_housing("barn").size() == 5, "畜舍 5 种（牛/山羊/绵羊/羊驼/猪）")

	var prices := AnimalDB.ids_by_price()
	var sorted_ok := true
	for i in range(1, prices.size()):
		if AnimalDB.get_animal(prices[i - 1]).price > AnimalDB.get_animal(prices[i]).price:
			sorted_ok = false
	_check(sorted_ok, "商店货架按价格升序")
	_check(prices[0] == &"chicken", "最便宜的是鸡（%s）" % String(prices[0]))

	# 产物表：每种动物的基础 / 高级产物都要在表里
	var products_ok := true
	var lack := ""
	for id in ids:
		var a: AnimalData = AnimalDB.get_animal(id)
		if not ProductDB.has(a.product):
			products_ok = false
			lack += String(a.product) + " "
		if a.product_high != StringName("") and not ProductDB.has(a.product_high):
			products_ok = false
			lack += String(a.product_high) + " "
	_check(products_ok, "每种动物的产物都在 products.csv（缺：%s）" % lack)

# ---------------- 2. 好感 0-10 心（需求 ③）----------------

func _test_hearts() -> void:
	print("[2] 好感 0-10 心")
	var a := AnimalState.new(&"c1", &"cow", 11)
	_check(a.hearts() == 0, "0 好感 = 0 心")
	a.affection = 99
	_check(a.hearts() == 0, "99 好感仍是 0 心")
	a.affection = 100
	_check(a.hearts() == 1, "100 好感 = 1 心")
	a.affection = 950
	_check(a.hearts() == 9, "950 好感 = 9 心")
	a.affection = 1000
	_check(a.hearts() == 10, "1000 好感 = 10 心（封顶）")
	a.affection = 99999
	_check(a.hearts() == 10, "超出也不会超过 10 心")
	_check(AnimalState.MAX_HEARTS == 10 and AnimalState.HEART_POINTS == 100, "1 心 = 100 好感")

# ---------------- 3. 好感获取（需求 ③ ⑤）----------------

func _test_gain() -> void:
	print("[3] 好感获取")
	var cow := AnimalState.new(&"c1", &"cow", 21)
	cow.debug_grow_adult()
	cow.feed()
	_check(cow.affection == AnimalState.FEED_AFFECTION, "喂食 +10（实际 %d）" % cow.affection)
	cow.feed()
	_check(cow.affection == 20, "奶牛喂满 2 次 = +20")
	_check(not cow.feed(), "喂饱后不再接受")

	cow.pet()
	_check(cow.affection == 20 + AnimalState.PET_AFFECTION, "抚摸 +5")
	cow.pet()
	_check(not cow.pet(), "奶牛每天最多摸 2 次")
	_check(cow.pet_left() == 0, "pet_left 归零")

	var cow2 := AnimalState.new(&"c2", &"cow", 22)
	_check(cow2.brush(), "奶牛可以刷毛")
	_check(cow2.affection == AnimalState.BRUSH_AFFECTION, "刷毛 +8")
	_check(not cow2.brush(), "每天只能刷一次")

	var pig := AnimalState.new(&"p1", &"pig", 23)
	_check(not pig.brush(), "猪不能刷毛（brushable = 0）")
	_check(pig.pet(), "猪可以摸")

	var hen := AnimalState.new(&"h1", &"chicken", 24)
	_check(hen.hug(), "鸡可以抱（家禽专属）")
	_check(hen.affection == AnimalState.HUG_AFFECTION, "抱抱 +6")
	_check(not hen.hug(), "每天只能抱一次")

	var bee := AnimalState.new(&"b1", &"bee", 25)
	_check(not bee.pet(), "蜜蜂不能摸")
	_check(not bee.brush(), "蜜蜂不能刷")
	_check(not bee.hug(), "蜜蜂不是家禽，不能抱")

	# 封顶
	var b := AnimalState.new(&"c3", &"cow", 26)
	b.affection = 999
	b.feed()
	_check(b.affection == AnimalState.MAX_AFFECTION, "好感封顶 1000")

# ---------------- 4. 好感衰减（需求 ③ ⑥：跨日联动）----------------

func _test_decay() -> void:
	print("[4] 好感衰减 / 跨日联动")
	var a := AnimalState.new(&"c1", &"cow", 31)
	a.debug_grow_adult()
	a.feed()                     # 2 餐只喂 1 次
	a.affection = 500
	a.advance_day()
	_check(a.affection == 500 - AnimalState.MISS_FEED_PENALTY, "漏 1 餐 -15（实际 %d）" % a.affection)

	var b := AnimalState.new(&"c2", &"cow", 32)
	b.debug_grow_adult()
	b.affection = 500
	b.advance_day()              # 一次都没喂
	_check(b.affection == 500 - AnimalState.MISS_FEED_PENALTY * 2,
		"漏 2 餐 -30（实际 %d）" % b.affection)

	# 冷落：喂饱了但整天没摸没刷没抱
	var c := AnimalState.new(&"c3", &"cow", 33)
	c.debug_grow_adult()
	c.debug_feed_full()
	c.affection = 500
	var ev := c.advance_day()
	_check(c.affection == 500 - AnimalState.NEGLECT_PENALTY,
		"喂饱但被冷落 -2（实际 %d）" % c.affection)
	var saw_neglect := false
	for e in ev:
		if e["type"] == "neglect":
			saw_neglect = true
	_check(saw_neglect, "跨日事件里有 neglect")

	# 冷落不叠加在漏喂上
	var d := AnimalState.new(&"c4", &"cow", 34)
	d.debug_grow_adult()
	d.affection = 500
	d.advance_day()
	_check(d.affection == 500 - AnimalState.MISS_FEED_PENALTY * 2,
		"漏喂当天不再叠冷落（实际 %d）" % d.affection)

	# 摸过就不算冷落
	var e2 := AnimalState.new(&"c5", &"cow", 35)
	e2.debug_grow_adult()
	e2.debug_feed_full()
	e2.affection = 500
	e2.pet()
	e2.advance_day()
	_check(e2.affection == 500 + AnimalState.PET_AFFECTION, "喂饱 + 摸过 = 不掉好感（实际 %d）" % e2.affection)

	# 蜜蜂只喂食就够
	var bee := AnimalState.new(&"b1", &"bee", 36)
	bee.debug_grow_adult()
	bee.debug_feed_full()
	bee.affection = 500
	bee.advance_day()
	_check(bee.affection == 500, "蜜蜂喂饱后不会掉好感（实际 %d）" % bee.affection)

	# 好感不会变负
	var f := AnimalState.new(&"c6", &"cow", 37)
	f.affection = 10
	f.advance_day()
	_check(f.affection == 0, "好感最低为 0")

	# 生病时每天再 -20（先摸一下，把「冷落」这条排除掉，单看生病惩罚）
	var g := AnimalState.new(&"c7", &"cow", 38)
	g.debug_grow_adult()
	g.sick = true
	g.debug_feed_full()
	g.pet()
	g.affection = 500
	g.advance_day()
	_check(g.affection == 500 - AnimalState.SICK_DAILY_PENALTY, "生病 -20/天（实际 %d）" % g.affection)

# ---------------- 5. 产出周期（需求 ② ⑥）----------------

func _test_produce_period() -> void:
	print("[5] 产出周期")
	# 奶牛：每天一轮
	var cow := AnimalState.new(&"c1", &"cow", 41)
	cow.debug_grow_adult()
	cow.debug_feed_full()
	cow.advance_day()
	_check(cow.product_ready, "奶牛喂饱跨日即有产出")

	# 绵羊：3 天一轮
	var sheep := AnimalState.new(&"s1", &"sheep", 42)
	sheep.debug_grow_adult()
	for i in range(2):
		sheep.debug_feed_full()
		sheep.advance_day()
	_check(not sheep.product_ready, "绵羊第 2 天还没到剪毛期")
	sheep.debug_feed_full()
	sheep.advance_day()
	_check(sheep.product_ready, "绵羊第 3 天可剪毛")
	var wool := sheep.produce(true)
	_check(wool.get("id") == "wool", "剪到羊毛（%s）" % str(wool.get("id")))
	_check(sheep.produce_timer == 0, "剪完重新计时")
	sheep.debug_feed_full()
	sheep.advance_day()
	_check(not sheep.product_ready, "剪完第二天不能马上再剪")

	# 蜜蜂：4 天一轮
	var bee := AnimalState.new(&"b1", &"bee", 43)
	bee.debug_grow_adult()
	for i in range(3):
		bee.debug_feed_full()
		bee.advance_day()
	_check(not bee.product_ready, "蜜蜂第 3 天还不能采")
	bee.debug_feed_full()
	bee.advance_day()
	_check(bee.product_ready, "蜜蜂第 4 天可采蜜")
	_check(bee.produce(true).get("id") == "honey", "采到蜂蜜")

	# 挤奶窗口
	var cow2 := AnimalState.new(&"c2", &"cow", 44)
	cow2.debug_grow_adult()
	cow2.debug_feed_full()
	cow2.advance_day()
	_check(cow2.produce(false).is_empty(), "窗口外挤不出奶")
	_check(cow2.product_ready, "窗口外失败不消耗产出")
	_check(not cow2.produce(true).is_empty(), "窗口内挤奶成功")

	# 没喂饱 → 不产出
	var cow3 := AnimalState.new(&"c3", &"cow", 45)
	cow3.debug_grow_adult()
	cow3.advance_day()
	_check(not cow3.product_ready, "没喂食则次日无产出")

# ---------------- 6. 互动方式（需求 ⑤）----------------

func _test_actions() -> void:
	print("[6] 互动方式")
	_check(AnimalDB.get_animal(&"cow").action_name() == "挤奶", "奶牛 = 挤奶")
	_check(AnimalDB.get_animal(&"goat").action_name() == "挤奶", "山羊 = 挤奶")
	_check(AnimalDB.get_animal(&"sheep").action_name() == "剪毛", "绵羊 = 剪毛")
	_check(AnimalDB.get_animal(&"alpaca").action_name() == "剪毛", "羊驼 = 剪毛")
	_check(AnimalDB.get_animal(&"chicken").action_name() == "捡拾", "鸡 = 捡拾")
	_check(AnimalDB.get_animal(&"duck").action_name() == "捡拾", "鸭 = 捡拾")
	_check(AnimalDB.get_animal(&"turkey").action_name() == "捡拾", "火鸡 = 捡拾")
	_check(AnimalDB.get_animal(&"pig").action_name() == "捡拾", "猪 = 捡拾（拱松露）")
	_check(AnimalDB.get_animal(&"bee").action_name() == "采蜜", "蜜蜂 = 采蜜")

	_check(AnimalDB.get_animal(&"alpaca").needs_minigame(), "羊驼剪毛也走节奏条")
	_check(not AnimalDB.get_animal(&"chicken").needs_minigame(), "捡蛋不用小游戏")
	_check(AnimalDB.get_animal(&"sheep").period_text() == "每 3 天", "周期文案")
	_check(AnimalDB.get_animal(&"cow").period_text() == "每天", "周期文案（每天）")
	_check(AnimalDB.get_animal(&"pig").window_text() == "全天", "猪随时能拱松露")

	# 高好感特殊产出（≥8 心）
	var cow := AnimalState.new(&"c1", &"cow", 46)
	cow.debug_grow_adult()
	cow.affection = 850
	cow.debug_feed_full()
	cow.advance_day()
	_check(cow.produce(true).get("id") == "milk_large", "奶牛 8 心产大罐牛奶")

	# 低好感 10% 不产出：统计意义上验证
	var miss := 0
	for i in range(200):
		var t := AnimalState.new(StringName("t%d" % i), &"cow", 1000 + i)
		t.debug_grow_adult()
		t.affection = 100        # 1 心
		t.debug_feed_full()
		t.advance_day()
		if not t.product_ready:
			miss += 1
	_check(miss > 0 and miss < 80, "1 心动物偶尔不产出（200 次里 %d 次）" % miss)

# ---------------- 7. 节奏条（需求 ④）----------------

func _test_rhythm() -> void:
	print("[7] 挤奶小游戏（节奏条）")
	var bar := RhythmBar.new(7)
	_check(not bar.running, "初始没在跑")
	bar.start()
	_check(bar.running, "开一局后 running = true")
	_check(bar.zone_center >= 0.25 and bar.zone_center <= 0.75, "目标区落在中段（%.2f）" % bar.zone_center)
	_check(bar.zone_width > 0.0, "目标区有宽度")

	# 正中 → 完美
	bar.pos = bar.zone_center
	var r := bar.press()
	_check(int(r["grade"]) == RhythmBar.Grade.PERFECT, "正中 → 完美（%s）" % str(r["label"]))
	_check(is_equal_approx(float(r["score"]), 1.0), "正中 score = 1.0")
	_check(not bar.running, "出手后结束")

	# 偏 30% 半宽 → 不错
	var half := bar.zone_width * 0.5
	bar.running = true
	bar.pos = bar.zone_center + half * 0.3
	_check(int(bar.press()["grade"]) == RhythmBar.Grade.GOOD, "偏一点 → 不错")
	bar.running = true
	bar.pos = bar.zone_center - half * 0.8
	_check(int(bar.press()["grade"]) == RhythmBar.Grade.OK, "擦边 → 还行")
	bar.running = true
	bar.pos = bar.zone_center + half + 0.05
	_check(int(bar.press()["grade"]) == RhythmBar.Grade.MISS, "跑出目标区 → 失手")

	# 往返
	bar.start()
	var p0 := bar.pos
	bar.tick(0.1)
	_check(bar.pos > p0, "指针在动")
	bar.pos = 1.0
	bar.dir = 1.0
	bar.tick(0.1)
	_check(bar.dir < 0.0 and bar.pos <= 1.0, "撞到右端会折返")

	# 超时
	bar.start()
	bar.timeout()
	_check(int(bar.grade) == RhythmBar.Grade.MISS and not bar.running, "超时 = 失手")

	# 结果 → 产出
	var perfect := RhythmBar.apply_result(RhythmBar.Grade.PERFECT, 1, 0)
	_check(int(perfect["count"]) == 2 and int(perfect["quality"]) == 1, "完美：产量 +1、品质 +1 档")
	var good := RhythmBar.apply_result(RhythmBar.Grade.GOOD, 1, 0)
	_check(int(good["count"]) == 1 and int(good["quality"]) == 1, "不错：只加品质")
	var ok := RhythmBar.apply_result(RhythmBar.Grade.OK, 2, 1)
	_check(int(ok["count"]) == 2 and int(ok["quality"]) == 1, "还行：无加成")
	var miss := RhythmBar.apply_result(RhythmBar.Grade.MISS, 2, 2)
	_check(int(miss["count"]) == 1 and int(miss["quality"]) == 2, "失手：产量 -1（不会低于 1）")
	var one := RhythmBar.apply_result(RhythmBar.Grade.MISS, 1, 0)
	_check(int(one["count"]) == 1, "失手时产量最少 1")
	var cap := RhythmBar.apply_result(RhythmBar.Grade.PERFECT, 1, 2)
	_check(int(cap["quality"]) == 2, "品质封顶 2（金星）")

# ---------------- 8. 产物品质后缀 ----------------

func _test_quality_items() -> void:
	print("[8] 产物品质（复用作物那一套编码）")
	_check(ProductDB.item_id(&"milk", 0) == &"milk", "普通牛奶 id = milk")
	_check(ProductDB.item_id(&"milk", 1) == &"milk_silver", "银星牛奶 id")
	_check(ProductDB.item_id(&"milk", 2) == &"milk_gold", "金星牛奶 id")
	_check(ProductDB.has(&"milk_gold"), "带品质后缀也能查到产物")
	_check(ProductDB.price(&"milk") == 100, "牛奶 100G")
	_check(ProductDB.price(&"milk_silver") == 150, "银星牛奶 ×1.5 = 150G")
	_check(ProductDB.price(&"milk_gold") == 200, "金星牛奶 ×2 = 200G")
	_check(ProductDB.display_name(&"milk_gold") == "金星牛奶", "显示名带品质前缀")
	_check(ProductDB.kind_of(&"milk_gold") == "animal", "带后缀仍是 animal 类")
	_check(not ProductDB.has(&"unicorn_tear"), "不存在的产物返回 false")

	# 高级产物名不能和品质后缀撞车
	_check(ProductDB.has(&"duck_egg_jumbo"), "大鸭蛋独立 id")
	_check(ProductDB.has(&"wool_fine"), "细羊毛独立 id")
	_check(ProductDB.has(&"gold_egg"), "金蛋独立 id")
	_check(CropQuality.split(&"duck_egg_jumbo")["quality"] == 0, "大鸭蛋不会被误判成金星")

# ---------------- 9. 商店面板本身 ----------------

func _test_shop_widget() -> void:
	print("[9] 商店面板")
	var shop := ShopUI.new()
	add_child(shop)
	await get_tree().process_frame
	_check(not shop.is_open(), "初始是关的")
	_check(not shop.visible, "初始不可见")

	var entries := [
		{"id": &"a", "name": "甲", "price": 10, "note": "x", "enabled": true},
		{"id": &"b", "name": "乙", "price": 20, "note": "y", "enabled": false, "reason": "钱不够"},
	]
	shop.open("测试商店", entries)
	_check(shop.is_open() and shop.visible, "打开后可见")
	_check(EventBus.ui_modal, "打开后 ui_modal = true（玩家会被冻住）")
	_check(shop.current_id() == &"a", "默认选中第一项")

	# 打开那一帧的 E 必须被吞掉
	var ev := InputEventKey.new()
	ev.keycode = KEY_E
	ev.pressed = true
	shop._unhandled_input(ev)
	_check(shop.is_open(), "打开当帧按 E 不会误买/误关")

	await get_tree().process_frame
	await get_tree().process_frame

	var got: Array[StringName] = []
	shop.buy_requested.connect(func(id: StringName) -> void: got.append(id))
	shop._unhandled_input(ev)
	_check(got.size() == 1 and got[0] == &"a", "按 E 买下当前项")

	# 往下选到「买不起」的那项，按 E 不该发信号
	var down := InputEventKey.new()
	down.keycode = KEY_DOWN
	down.pressed = true
	shop._unhandled_input(down)
	_check(shop.current_id() == &"b", "↓ 切到第二项")
	shop._unhandled_input(ev)
	_check(got.size() == 1, "买不起的项按 E 不发信号")

	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	shop._unhandled_input(esc)
	_check(not shop.is_open() and not shop.visible, "Esc 关掉")
	_check(not EventBus.ui_modal, "关掉后 ui_modal = false")

	shop.queue_free()
	await get_tree().process_frame

# ---------------- 10. main 集成 ----------------

func _test_main() -> void:
	print("[10] main.gd 集成")
	GameState.reset()
	EventBus.ui_modal = false
	var ps: PackedScene = load("res://scenes/main.tscn")
	_check(ps != null, "main.tscn 可加载")
	if ps == null:
		return
	var main := ps.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().physics_frame

	# --- UI 字号（用户要求：字幕调小）---
	var hud: Label = main.get_node("UI/HUD")
	var tip: Label = main.get_node("UI/Tip")
	var tb: Label = main.get_node("UI/ToolBar")
	var clock: Label = main.get_node("UI/ClockPanel")
	_check(hud.get_theme_font_size("font_size") <= 11, "HUD 字号 <= 11（%d）" % hud.get_theme_font_size("font_size"))
	_check(tb.get_theme_font_size("font_size") <= 10, "工具条字号 <= 10（%d）" % tb.get_theme_font_size("font_size"))
	_check(tip.get_theme_font_size("font_size") <= 11, "提示字号 <= 11（%d）" % tip.get_theme_font_size("font_size"))
	_check(clock.get_theme_font_size("font_size") <= 11, "时钟字号 <= 11（%d）" % clock.get_theme_font_size("font_size"))
	_check(tip.autowrap_mode != TextServer.AUTOWRAP_OFF, "提示会自动换行")

	# --- 新 UI 节点 ---
	_check(main.get_node_or_null("UI/ShopPanel") is ShopUI, "UI 有商店面板")
	_check(main.get_node_or_null("UI/Minigame") is MinigameUI, "UI 有节奏条面板")
	_check(main.get_node_or_null("World/SeedShop") is SeedShop, "场景里有种子商店")
	_check(main.get_node_or_null("World/AnimalShop") is AnimalShop, "场景里有动物商店")

	# --- 开局牧群 ---
	var herd: Herd = main._herd
	_check(herd.size() >= 5, "开局有动物（%d 只）" % herd.size())
	_check(herd.count_species(&"cow") == 2, "开局 2 头奶牛")
	_check(herd.count_species(&"sheep") == 1 and herd.count_species(&"bee") == 1, "开局有绵羊和蜜蜂")

	# --- 种子商店 ---
	var gold0 := GameState.gold
	EventBus.shop_requested.emit(&"seed")
	await get_tree().process_frame
	var shop: ShopUI = main._shop
	_check(shop.is_open(), "种子商店打开")
	_check(main._shop_kind == &"seed", "货架类型 = seed")
	var spring := CropDB.of_season(GameClock.season)
	_check(spring.size() == 6, "当季 6 种作物")
	var ids: Array = []
	for e in shop._entries:
		ids.append(e["id"])
	_check(ids.size() == spring.size() + 2, "货架 = 当季种子 + 两档肥（%d）" % ids.size())
	_check(ids.has(CropDB.seed_item(spring[0])), "货架有当季种子")
	_check(not ids.has(CropDB.seed_item(&"pumpkin")), "非当季（南瓜）不上架")
	_check(ids.has(Fertilizer.item_id(Fertilizer.Level.BASIC)), "货架有基础肥")

	# 买一颗当季种子
	var buy_id: StringName = CropDB.seed_item(spring[0])
	var crop: CropData = CropDB.get_crop(spring[0])
	var before := GameState.count_item(buy_id)
	main._on_buy(buy_id)
	_check(GameState.count_item(buy_id) == before + 1, "买下种子进背包")
	_check(GameState.gold == gold0 - crop.seed_price, "扣了 %dG" % crop.seed_price)

	# 买不起 → 不能成交
	var gold_backup := GameState.gold
	GameState.gold = 0
	main._refresh_shop()
	var all_disabled := true
	for e in shop._entries:
		if bool(e["enabled"]):
			all_disabled = false
	_check(all_disabled, "没钱时整排灰掉")
	var cnt0 := GameState.count_item(buy_id)
	main._on_buy(buy_id)
	_check(GameState.count_item(buy_id) == cnt0, "没钱时买不动")
	GameState.gold = gold_backup
	main._refresh_shop()

	shop.close()
	await get_tree().process_frame
	_check(not EventBus.ui_modal, "关掉商店后玩家解冻")

	# --- 动物商店 ---
	var chickens := herd.count_species(&"chicken")
	var gold_before := GameState.gold
	EventBus.shop_requested.emit(&"animal")
	await get_tree().process_frame
	_check(shop.is_open(), "动物商店打开")
	_check(shop._entries.size() == AnimalDB.all_ids().size(), "货架 = 全表 %d 种" % shop._entries.size())
	main._on_buy(&"chicken")
	_check(herd.count_species(&"chicken") == chickens + 1, "买下鸡，进牧场")
	_check(GameState.gold == gold_before - 200, "鸡 200G（实际扣 %d）" % (gold_before - GameState.gold))
	var newbie := herd.animals[herd.size() - 1]
	_check(newbie.is_adult(), "买来就是成年")
	_check(newbie.product_ready, "买来就给一次产出（能立刻试挤奶）")
	_check(newbie.pos.x > 512 and newbie.pos.x < 736, "落点在围栏内（x=%.0f）" % newbie.pos.x)
	shop.close()
	await get_tree().process_frame

	# --- ui_modal 冻结玩家 ---
	var p: Player = main.get_node("World/YSortRoot/Player")
	EventBus.set_ui_modal(true)
	p.velocity = Vector2(50, 50)
	p._physics_process(0.016)
	_check(p.velocity == Vector2.ZERO, "模态期间玩家被冻住")
	EventBus.set_ui_modal(false)

	# --- 播种要消耗种子 ---
	var cell := Vector2i(5, 6)
	main._grid.till(cell)
	p.set_seed(&"turnip")
	var seed_before := GameState.count_item(CropDB.seed_item(&"turnip"))
	main._plant(cell)
	_check(main._grid.tile_at(cell).crop_id == &"turnip", "种下了芜菁")
	_check(GameState.count_item(CropDB.seed_item(&"turnip")) == seed_before - 1, "播种消耗 1 颗种子")
	_check(main._tip.text.contains("种子剩"), "提示里有剩余种子数：%s" % main._tip.text)

	# 没种子 → 拒绝，且地块不能被顺手种下
	var cell2 := Vector2i(6, 6)
	main._grid.till(cell2)
	GameState.remove_item(CropDB.seed_item(&"turnip"), GameState.count_item(CropDB.seed_item(&"turnip")))
	main._plant(cell2)
	_check(main._grid.tile_at(cell2).crop_id == StringName(""), "没种子就不种")
	_check(main._tip.text.contains("种子用完了"), "提示去种子商店：%s" % main._tip.text)

	# --- 挤奶：窗口 + 节奏条 + 进背包 ---
	var cow: AnimalState = herd.animals[0]
	GameClock.debug_set_minutes(0)      # 6:00
	cow.debug_feed_full()
	cow.debug_ready_produce()
	_stand_near(p, cow)
	GameState.remove_item(&"milk", GameState.count_item(&"milk"))
	main._handle_animal(Player.Tool.HAND)
	_check(main._minigame.is_active(), "对着奶牛用「手」→ 起节奏条")
	_check(EventBus.ui_modal, "节奏条期间 ui_modal = true")
	_check(main._pending_animal == cow, "记住了是哪只动物")
	var bar: RhythmBar = main._minigame.bar
	bar.pos = bar.zone_center
	bar.press()
	main._minigame._finish(bar.grade, bar.score)
	_check(not EventBus.ui_modal, "结束后解冻")
	_check(GameState.count_item(&"milk") + GameState.count_item(&"milk_silver")
		+ GameState.count_item(&"milk_gold") >= 1, "牛奶进背包")
	_check(not cow.product_ready, "挤完产出清空")

	# 完美 → 金星牛奶（品质 1 档 → 至少银星）
	cow.affection = 950            # 9 心 → 基础品质就是金星
	cow.debug_feed_full()
	cow.debug_ready_produce()
	GameState.remove_item(&"milk_gold", GameState.count_item(&"milk_gold"))
	main._start_minigame(cow, cow.data())
	bar.pos = bar.zone_center
	bar.press()
	main._minigame._finish(bar.grade, bar.score)
	_check(GameState.count_item(&"milk_gold") >= 1,
		"完美 + 9 心 → 金星牛奶（gold=%d silver=%d tip=%s）" % [
			GameState.count_item(&"milk_gold"), GameState.count_item(&"milk_silver"), main._tip.text])

	# 放弃不消耗产出
	cow.debug_feed_full()
	cow.debug_ready_produce()
	main._start_minigame(cow, cow.data())
	main._minigame._cancel()
	_check(cow.product_ready, "Esc 放弃后产出还在")
	_check(main._pending_animal == null, "放弃后清空待处理动物")

	# 窗口外不给挤
	GameClock.debug_set_minutes(300)     # 11:00
	main._handle_animal(Player.Tool.HAND)
	_check(not main._minigame.is_active(), "11:00 不起节奏条")
	_check(main._tip.text.contains("只在"), "提示窗口时间：%s" % main._tip.text)
	GameClock.debug_set_minutes(0)

	# --- 捡蛋（不用小游戏）---
	var hen: AnimalState = herd.animals[2]
	_stand_near(p, hen)
	hen.debug_feed_full()
	hen.debug_ready_produce()
	GameState.remove_item(&"egg", GameState.count_item(&"egg"))
	main._handle_animal(Player.Tool.HAND)
	_check(not main._minigame.is_active(), "捡蛋不起节奏条")
	_check(GameState.count_item(&"egg") >= 1,
		"蛋进背包（egg=%d, ready=%s, tip=%s）" % [
			GameState.count_item(&"egg"), str(hen.product_ready), main._tip.text])

	# --- 剪毛（周期 3 天 + 走节奏条）---
	var sheep: AnimalState = herd.animals[5]
	_check(sheep.species == &"sheep", "第 6 只是绵羊")
	_stand_near(p, sheep)
	sheep.debug_feed_full()
	sheep.debug_ready_produce()
	main._handle_animal(Player.Tool.HAND)
	_check(main._minigame.is_active(), "剪毛走节奏条")
	bar.pos = bar.zone_center
	bar.press()
	main._minigame._finish(bar.grade, bar.score)
	_check(GameState.count_item(&"wool") + GameState.count_item(&"wool_silver")
		+ GameState.count_item(&"wool_gold") >= 1, "羊毛进背包")

	# --- 刷毛 / 抚摸 ---
	var pig_herd := Herd.new(1)
	var pig := pig_herd.add(&"pig", 0, Vector2(0, 0))
	pig.debug_grow_adult()
	_check(pig.brush() == false, "猪刷不了毛")
	main._herd.add(&"pig", 0, Vector2(600, 200))
	var pig2: AnimalState = main._herd.animals[main._herd.size() - 1]
	pig2.debug_grow_adult()
	_stand_near(p, pig2)
	main._handle_animal(Player.Tool.HAND)
	_check(pig2.affection == AnimalState.PET_AFFECTION, "空手靠近猪 → 抚摸 +5（%d）" % pig2.affection)

	# 奶牛有产出时先收，不产出时才刷毛
	var cow2: AnimalState = herd.animals[1]
	_stand_near(p, cow2)
	cow2.product_ready = false
	cow2.brushed_today = false
	cow2.affection = 0
	main._handle_animal(Player.Tool.HAND)
	_check(cow2.affection == AnimalState.BRUSH_AFFECTION, "没产出 → 给奶牛刷毛 +8（%d）" % cow2.affection)
	main._handle_animal(Player.Tool.HAND)
	_check(cow2.affection == AnimalState.BRUSH_AFFECTION + AnimalState.PET_AFFECTION,
		"刷过毛之后才轮到抚摸（%d）" % cow2.affection)

	# --- 蜜蜂：只喂食 ---
	var bee: AnimalState = herd.animals[7]
	_stand_near(p, bee)
	bee.fed_today = 0
	main._handle_animal(Player.Tool.FEED)
	_check(bee.fed_today == 1, "喂了蜜蜂")
	bee.affection = 0
	bee.product_ready = false          # 先把产出收掉，单看「摸不摸得到」
	main._handle_animal(Player.Tool.HAND)
	_check(bee.affection == 0, "蜜蜂摸不到，好感不变")
	_check(main._tip.text.contains("不太亲人"), "提示说明原因：%s" % main._tip.text)

	# --- 跨日：好感衰减 + 事件 ---
	var g2 := AnimalState.new(&"c9", &"cow", 99)
	g2.debug_grow_adult()
	g2.affection = 500
	g2.debug_feed_full()
	var evs := g2.advance_day()
	var types: Array = []
	for e in evs:
		types.append(e["type"])
	_check(types.has("neglect"), "跨日事件包含 neglect")

	# --- HUD 汇总 9 种都能显示 ---
	main._refresh_hud()
	_check(hud.text.contains("奶牛") and hud.text.contains("蜜蜂"), "HUD 列出多种动物：%s" % hud.text.split("\n")[0])

	main.queue_free()
	await get_tree().process_frame

## 把玩家摆到目标动物左侧 30px、面朝右 ——
## 这样 interact_point() 正好落在动物身前 10px，不会被隔壁那只「抢焦点」。
func _stand_near(p: Player, a: AnimalState) -> void:
	p.global_position = a.pos + Vector2(-30, 0)
	p.facing = "right"
	p.facing8 = "right"
