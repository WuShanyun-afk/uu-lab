extends Node
## 模块 5 验收：动物系统（进阶）—— 觉醒 / 成长 / 生病 / 繁殖 / 秘密花园
##
## 需求对照：
##   ① 动物觉醒系统：好感满 10 心触发，拟人化对话，产出特殊物品
##   ② 幼年 → 成年成长阶段（奶牛 7 天 / 鸡 3 天 / 羊 5 天）
##   ③ 生病系统：好感 < 3 心 + 漏喂触发，需药物治疗
##   ④ 繁殖系统：建造繁殖棚，消耗资源
##   ⑤ 全部觉醒后解锁「秘密花园」新地图
##
## 运行： godot --headless --path <项目> res://tests/test_module5.tscn

var _fails: Array[String] = []
var _n := 0

func _check(cond: bool, label: String) -> void:
	_n += 1
	if not cond:
		_fails.append(label)
	print(("  [OK] " if cond else "  [FAIL] ") + label)

func _ready() -> void:
	print("=== 模块 5 验收：动物系统（进阶）===")
	_test_awakening_table()
	_test_growth()
	_test_awaken_trigger()
	_test_awaken_effect()
	_test_sick_cure()
	_test_breeding_rules()
	_test_birth()
	_test_garden_geometry()
	_test_garden_unlock()
	await _test_dialogue_ui()
	await _test_shop_widget()
	await _test_main()
	var ok := _fails.is_empty()
	print("=== 结果：%s（共 %d 项）===" % ["全部通过" if ok else "失败 %d 项" % _fails.size(), _n])
	if not ok:
		for f in _fails:
			print("   ! " + f)
	get_tree().quit(0 if ok else 1)

# ---------------- 1. 觉醒事件数据结构（需求 ①）----------------

func _test_awakening_table() -> void:
	print("[1] 觉醒事件数据结构")
	var ids := AnimalDB.all_ids()
	_check(Awakening.count() == ids.size(),
		"觉醒表和动物表一样长（%d vs %d）" % [Awakening.count(), ids.size()])

	var complete := true
	var missing := ""
	var suffix_ok := true
	var bad_gift := ""
	for id in ids:
		if not Awakening.has(id):
			complete = false
			missing += String(id) + " "
			continue
		var ev := Awakening.event(id)
		if str(ev.get("persona", "")) == "" or str(ev.get("title", "")) == "" \
				or Awakening.lines(id).size() < 2:
			complete = false
			missing += String(id) + "(字段) "
		var g := Awakening.gift(id)
		if g == StringName("") or not ProductDB.has(g):
			complete = false
			missing += String(id) + "(产物) "
		# ⚠️ 模块 4 的坑：id 以 _gold / _silver 结尾会被当成品质后缀
		var gs := String(g)
		if gs.ends_with("_gold") or gs.ends_with("_silver"):
			suffix_ok = false
			bad_gift += gs + " "
	_check(complete, "9 种动物都有 拟人名 / 称号 / ≥2 句台词 / 专属产物（缺：%s）" % missing)
	_check(suffix_ok, "觉醒产物 id 不以 _gold/_silver 结尾（违规：%s）" % bad_gift)

	_check(Awakening.persona(&"cow") == "布伦希尔德", "奶牛拟人名 = 布伦希尔德")
	_check(Awakening.speaker(&"cow") == "布伦希尔德 · 牧场之母",
		"对话框标题（%s）" % Awakening.speaker(&"cow"))
	_check(Awakening.gift(&"cow") == &"starlight_milk", "奶牛觉醒产物 = 星光牛奶")
	_check(Awakening.gift_name(&"bee") == "黄金蜜", "蜜蜂觉醒产物名")
	_check(Awakening.portrait(&"cow") is Color, "立绘色块是 Color")
	_check(Awakening.event(&"dragon").is_empty(), "不存在的物种返回空表")
	_check(not Awakening.has(&"dragon"), "has() 对未知物种返回 false")

	# 专属产物是独立物品，不能被出货箱拒收（kind=animal）
	_check(ProductDB.kind_of(&"starlight_milk") == "animal", "觉醒产物可出货（kind=animal）")
	_check(ProductDB.price(&"starlight_milk") == 1200, "星光牛奶 1200G")
	_check(ProductDB.price(&"starlight_milk_gold") == 2400, "金星星光牛奶 ×2 = 2400G")
	_check(CropQuality.split(&"golden_honey")["quality"] == 0, "黄金蜜不会被误判成金星")

	# 解锁对话
	_check(Awakening.GARDEN_UNLOCK["lines"].size() == 3, "花园解锁对话 3 句")
	_check(str(Awakening.GARDEN_UNLOCK["persona"]) == "秘密花园", "解锁对话标题")

	# 新消耗品
	_check(ProductDB.has(&"medicine") and ProductDB.kind_of(&"medicine") == "consumable",
		"药剂在表里且是消耗品")
	_check(ProductDB.has(&"wood") and ProductDB.kind_of(&"wood") == "material",
		"木材在表里且是材料")
	_check(ProductDB.price(&"medicine") == 180, "药剂 180G")
	_check(ProductDB.price(&"wood") == 60, "木材 60G")

# ---------------- 2. 成长阶段（需求 ②）----------------

func _test_growth() -> void:
	print("[2] 幼年 → 成年成长阶段")
	# 需求原文的三条硬数值
	_check(AnimalDB.get_animal(&"cow").mature_days == 7, "奶牛 7 天成年")
	_check(AnimalDB.get_animal(&"chicken").mature_days == 3, "鸡 3 天成年")
	_check(AnimalDB.get_animal(&"sheep").mature_days == 5, "绵羊 5 天成年")

	var a := AnimalState.new(&"t1", &"cow", 501)
	_check(not a.is_adult(), "刚出生不是成年")
	_check(a.growth_stage() == AnimalState.Growth.BABY, "阶段 = BABY")
	_check(a.stage_name() == "幼年", "阶段名 = 幼年")
	_check(a.display_label() == "幼年奶牛", "显示名带幼年前缀（%s）" % a.display_label())
	_check(a.days_to_mature() == 7, "还要 7 天成年")
	_check(is_equal_approx(a.body_scale(), AnimalState.BABY_SCALE), "幼崽缩放 = 0.62")
	_check(not a.is_producing(), "幼年不产出")

	# 长大过程：缩放单调不减，第 7 天长到 1.0
	var prev := a.body_scale()
	var monotonic := true
	for i in range(7):
		a.advance_day()
		if a.body_scale() < prev - 0.0001:
			monotonic = false
		prev = a.body_scale()
	_check(monotonic, "长大过程缩放单调不减")
	_check(a.is_adult() and is_equal_approx(a.body_scale(), 1.0), "第 7 天成年且缩放 1.0")
	_check(a.stage_name() == "成年" and a.display_label() == "奶牛", "成年后显示名不带前缀")
	_check(a.days_to_mature() == 0, "成年后 days_to_mature = 0")

	# mature 事件：只在跨过那一天广播一次
	var b := AnimalState.new(&"t2", &"chicken", 502)
	var mature_days := 0
	for i in range(6):
		for e in b.advance_day():
			if e["type"] == "mature":
				mature_days += 1
	_check(b.is_adult(), "鸡 3 天成年")
	_check(mature_days == 1, "mature 事件只广播一次（实际 %d）" % mature_days)

	# 幼年不产出：喂饱也不会次日有产出
	var c := AnimalState.new(&"t3", &"cow", 503)
	c.debug_feed_full()
	c.advance_day()
	_check(not c.product_ready, "幼年喂饱也不产出")

	# 幼年不能繁殖
	var adult := AnimalState.new(&"t4", &"cow", 504)
	adult.debug_grow_adult()
	adult.affection = 900
	c.affection = 900
	_check(Breeding.can_breed(c, adult, true, 0, 20) == Breeding.Reason.BABY,
		"幼年不能繁殖（返回 BABY）")

	# 牧群生出来的崽默认是幼年
	var h := Herd.new(5)
	var mom := h.add(&"cow", 900, Vector2.ZERO)
	mom.debug_grow_adult()
	mom.debug_pregnant(1)
	h.advance_day()
	_check(h.size() == 2, "生崽后牧群 2 只")
	var baby := h.animals[1]
	_check(not baby.is_adult() and baby.days_old == 0, "新生的是幼年（0 天）")
	_check(baby.pos.distance_to(mom.pos) < 40.0, "幼崽生在母亲附近（%.0f px）" % baby.pos.distance_to(mom.pos))

# ---------------- 3. 觉醒触发（需求 ①）----------------

func _test_awaken_trigger() -> void:
	print("[3] 觉醒触发（好感满 10 心）")
	var a := AnimalState.new(&"a1", &"cow", 601)
	a.debug_grow_adult()
	a.affection = 999
	_check(not a.awakened, "999 好感还没觉醒")
	a.feed()
	_check(a.affection == AnimalState.MAX_AFFECTION, "喂一口到 1000")
	_check(a.awakened, "满 10 心 → awakened")
	_check(a.just_awakened, "挂上 just_awakened 标记（等 main 弹对话）")
	_check(a.hearts() == 10, "10 心")

	# 抚摸 / 刷毛 / 留棚加好感都能触发（所有入口都走 _gain）
	var b := AnimalState.new(&"a2", &"cow", 602)
	b.debug_grow_adult()
	b.affection = 996
	b.pet()
	_check(b.awakened, "抚摸推满也能觉醒")

	var h := Herd.new(7)
	var c := h.add(&"cow", 998, Vector2.ZERO)
	c.debug_grow_adult()
	h.add_affection_all(3)
	_check(c.awakened, "Herd.add_affection_all（雨雪留棚 +3）也能觉醒")
	_check(h.pending_awakenings().size() == 1, "pending_awakenings 列出刚觉醒的")
	_check(h.awakened_species_count() == 1, "觉醒物种数 = 1")
	_check(not h.all_species_awakened(), "只有 1 种，还没全觉醒")

	# 觉醒是永久的
	c.affection = 300
	_check(c.awakened, "好感掉下来也不会「再睡回去」")

# ---------------- 4. 觉醒效果（需求 ①）----------------

func _test_awaken_effect() -> void:
	print("[4] 觉醒效果：免疫生病 / 免疫衰减 / 特殊产出")
	var a := AnimalState.new(&"e1", &"cow", 701)
	a.debug_grow_adult()
	a.debug_awaken()
	_check(a.awakened and a.affection == AnimalState.MAX_AFFECTION, "debug_awaken 直接推满")

	# 免疫生病：好感 0 + 连续漏喂 200 天，一次都不能病
	a.affection = 0
	var got_sick := false
	for i in range(200):
		a.advance_day()
		if a.sick:
			got_sick = true
			break
	_check(not got_sick, "觉醒动物永不生病（200 天漏喂）")

	# 免疫衰减：不喂不摸也不掉好感
	a.affection = 800
	a.advance_day()
	_check(a.affection == 800, "觉醒后漏喂 / 冷落都不掉好感（实际 %d）" % a.affection)
	var types: Array = []
	for e in a.advance_day():
		types.append(e["type"])
	_check(not types.has("neglect"), "觉醒后不再广播 neglect")

	# 特殊产出：统计 240 天，觉醒产物出现的比例应落在 30% 附近
	var cow := AnimalState.new(&"e2", &"cow", 702)
	cow.debug_grow_adult()
	cow.debug_awaken()
	var gifts := 0
	var normal := 0
	for i in range(240):
		cow.debug_feed_full()
		cow.advance_day()
		if not cow.product_ready:
			continue
		if cow.product_awakened:
			gifts += 1
			var out := cow.produce(true)
			if out.get("id") == Awakening.gift(&"cow"):
				pass
			else:
				normal += 1        # 记一笔异常
		else:
			normal += 1
			cow.produce(true)
	var rate := float(gifts) / float(maxi(1, gifts + normal))
	_check(rate > 0.15 and rate < 0.50,
		"觉醒产物出现率 ≈ 30%%（240 天里 %d 次，%.0f%%）" % [gifts, rate * 100.0])
	_check(gifts > 0, "至少产出过一次觉醒产物")
	_check(normal > 0, "也产过普通产出（不是把把都觉醒）")

	# 觉醒产物的 id / 数量 / 品质
	var c2 := AnimalState.new(&"e3", &"cow", 703)
	c2.debug_grow_adult()
	c2.debug_awaken()
	c2.debug_feed_full()
	c2.product_ready = true
	c2.product_awakened = true
	c2.product_quality = 0
	var out2 := c2.produce(true)
	_check(out2.get("id") == &"starlight_milk", "觉醒产物 id = starlight_milk")
	_check(int(out2.get("count")) == 1, "觉醒产物每次 1 件")
	_check(int(out2.get("quality")) == 0, "觉醒产物不叠品质星")
	_check(not c2.product_awakened, "收完清掉觉醒标记")

	# 没觉醒的动物不会产觉醒产物
	var d := AnimalState.new(&"e4", &"cow", 704)
	d.debug_grow_adult()
	d.affection = 950
	for i in range(120):
		d.debug_feed_full()
		d.advance_day()
		if d.product_ready and d.product_awakened:
			break
		d.produce(true)
	_check(not d.product_awakened, "没觉醒的动物不会产觉醒产物")

	# 觉醒产物的出货价（复用 CropQuality 倍率链路）
	_check(ProductDB.price(&"cloud_wool") == 1400, "云绒 1400G")
	_check(ProductDB.display_name(&"dawn_egg") == "黎明蛋", "黎明蛋显示名")

# ---------------- 5. 生病与治疗（需求 ③）----------------

func _test_sick_cure() -> void:
	print("[5] 生病系统 + 药物治疗")
	# 触发条件：好感 < 3 心 + 连续漏喂 ≥ 2 天
	var a := AnimalState.new(&"s1", &"cow", 801)
	a.debug_grow_adult()
	a.affection = 200          # 2 心
	var got_sick := false
	for i in range(200):
		a.advance_day()
		if a.sick:
			got_sick = true
			break
	_check(got_sick, "好感 < 3 心 + 漏喂 → 会生病（200 天内）")
	_check(not a.is_producing(), "生病时不产出")

	# 高好感不会病：把好感钉在 4 心，让漏喂罚掉 -30 之后**还剩 3 心**，
	# 专门验「hearts() < 3」这个门槛 —— 3 心就是安全的，2 心才会掷骰。
	var b := AnimalState.new(&"s2", &"cow", 802)
	b.debug_grow_adult()
	var high_sick := false
	for i in range(200):
		b.affection = 400
		b.advance_day()
		if b.sick:
			high_sick = true
			break
	_check(not high_sick, "罚完仍有 3 心时连续漏喂 200 天也不病")

	# 低好感但没漏喂（天天喂饱）也不会病 —— 验「连续漏喂 ≥ 2 天」那一半条件
	var b2 := AnimalState.new(&"s2b", &"cow", 8022)
	b2.debug_grow_adult()
	b2.affection = 200
	var fed_sick := false
	for i in range(200):
		b2.affection = 200
		b2.debug_feed_full()
		b2.advance_day()
		if b2.sick:
			fed_sick = true
			break
	_check(not fed_sick, "2 心但天天喂饱 → 不病（漏喂 ≥ 2 天才掷骰）")

	# 治疗
	var c := AnimalState.new(&"s3", &"cow", 803)
	c.debug_grow_adult()
	c.affection = 500
	_check(not c.cure(), "没病时用药返回 false（不浪费药）")
	c.sick = true
	c.sick_days = 3
	_check(c.cure(), "有病时用药成功")
	_check(not c.sick and c.sick_days == 0, "康复：sick = false / sick_days 归零")
	_check(c.affection == 500 + AnimalState.CURE_AFFECTION, "康复回补好感 +30（实际 %d）" % c.affection)
	_check(c.is_producing(), "康复后立刻能产出")

	# 恶化：第 5 天告警、第 7 天病逝
	var d := AnimalState.new(&"s4", &"cow", 804)
	d.debug_grow_adult()
	d.sick = true
	var saw_critical := false
	var saw_died := false
	var died_at := -1
	for i in range(AnimalState.SICK_DEATH_DAYS):
		for e in d.advance_day():
			if e["type"] == "critical":
				saw_critical = true
			if e["type"] == "died":
				saw_died = true
				died_at = i + 1
	_check(saw_critical, "第 %d 天起广播 critical 告警" % AnimalState.SICK_CRITICAL_DAYS)
	_check(saw_died and died_at == AnimalState.SICK_DEATH_DAYS,
		"拖满 %d 天广播 died（实际第 %d 天）" % [AnimalState.SICK_DEATH_DAYS, died_at])

	# 病逝 → Herd 把动物移出牧场
	var h := Herd.new(9)
	var e2 := h.add(&"cow", 100, Vector2.ZERO)
	e2.debug_grow_adult()
	e2.sick = true
	for i in range(AnimalState.SICK_DEATH_DAYS):
		h.advance_day()
	_check(h.size() == 0, "病逝的动物被移出牧场（剩 %d 只）" % h.size())

	# 及时用药就不会死
	var h2 := Herd.new(11)
	var f := h2.add(&"cow", 100, Vector2.ZERO)
	f.debug_grow_adult()
	f.affection = 500
	f.sick = true
	h2.advance_day()
	h2.advance_day()
	f.cure()
	_check(h2.size() == 1 and not f.sick, "第 3 天用药 → 立刻康复")
	for i in range(10):
		f.affection = 500          # 维持好感，把「再次生病」这条干扰排除掉
		f.debug_feed_full()
		h2.advance_day()
	_check(h2.size() == 1, "用药后 10 天没有病逝")

# ---------------- 6. 繁殖规则（需求 ④）----------------

func _test_breeding_rules() -> void:
	print("[6] 繁殖系统：建筑表 + 规则")
	var id := &"breeding_shed"
	var b := BuildingDB.get_building(id)
	_check(not b.is_empty(), "buildings.csv 里有繁殖棚")
	_check(BuildingDB.price_of(id) == 1200, "造价 1200G")
	_check(BuildingDB.material_of(id) == &"wood", "材料是木材")
	_check(BuildingDB.material_count_of(id) == 20, "要 20 根木材")
	_check(BuildingDB.gestation_days_of(id) == 3, "妊娠 3 天")
	_check(BuildingDB.name_of(id) == "繁殖棚", "中文名")
	_check(BuildingDB.cost_text(id) == "1200G + 木材×20", "成本文案（%s）" % BuildingDB.cost_text(id))
	_check(BuildingDB.get_building(&"nope").is_empty(), "未知建筑返回空表")

	# 规则：造一对合格的父母
	# ⚠️ uid 必须唯一！第一版按「物种+心数」拼 uid，于是两只 9 心奶牛 uid 撞车，
	#    校验第一关 `a.uid == b.uid` 直接把「未成年 / 生病 / 妊娠」全吞成 SAME。
	var seq := [0]
	var mk := func(species: StringName, hearts: int) -> AnimalState:
		seq[0] += 1
		var a := AnimalState.new(
			StringName("x_%s_%d_%d" % [species, hearts, seq[0]]), species, 900 + hearts)
		a.debug_grow_adult()
		a.affection = hearts * 100
		return a
	var cow_a: AnimalState = mk.call(&"cow", 9)
	var cow_b: AnimalState = mk.call(&"cow", 8)
	var hen: AnimalState = mk.call(&"chicken", 9)
	var calf: AnimalState = mk.call(&"cow", 9)
	calf.days_old = 0
	calf.affection = 900

	_check(Breeding.can_breed(cow_a, cow_b, true, 4, 20) == Breeding.Reason.OK, "同种成年 8 心以上 → OK")
	_check(Breeding.can_breed(cow_a, cow_b, false, 4, 20) == Breeding.Reason.NO_SHED, "没盖棚 → NO_SHED")
	_check(Breeding.can_breed(cow_a, cow_a, true, 4, 20) == Breeding.Reason.SAME, "自己和自己 → SAME")
	_check(Breeding.can_breed(cow_a, hen, true, 4, 20) == Breeding.Reason.SPECIES, "不同种 → SPECIES")
	_check(Breeding.can_breed(cow_a, calf, true, 4, 20) == Breeding.Reason.BABY, "未成年 → BABY")
	_check(Breeding.can_breed(cow_a, cow_b, true, 20, 20) == Breeding.Reason.SPACE, "牧场满 → SPACE")

	var low: AnimalState = mk.call(&"cow", 7)
	_check(Breeding.can_breed(cow_a, low, true, 4, 20) == Breeding.Reason.HEARTS, "7 心 → HEARTS")

	var sickly: AnimalState = mk.call(&"cow", 9)
	sickly.sick = true
	_check(Breeding.can_breed(cow_a, sickly, true, 4, 20) == Breeding.Reason.SICK, "生病 → SICK")

	var preg: AnimalState = mk.call(&"cow", 9)
	preg.debug_pregnant(2)
	_check(Breeding.can_breed(cow_a, preg, true, 4, 20) == Breeding.Reason.PREGNANT, "妊娠中 → PREGNANT")
	_check(Breeding.can_breed(preg, cow_b, true, 4, 20) == Breeding.Reason.PREGNANT,
		"第一只是妊娠中的也要拦（两方都查）")

	# 每种 reason 都要有中文解释，不能返回空串（否则 UI 上是个哑巴）
	var silent := ""
	for r in [Breeding.Reason.NO_SHED, Breeding.Reason.SAME, Breeding.Reason.SPECIES,
			Breeding.Reason.BABY, Breeding.Reason.HEARTS, Breeding.Reason.SICK,
			Breeding.Reason.PREGNANT, Breeding.Reason.SPACE]:
		if Breeding.reason_text(r) == "":
			silent += str(r) + " "
	_check(silent == "", "每个失败原因都有中文说明（哑巴：%s）" % silent)
	_check(Breeding.reason_text(Breeding.Reason.OK) == "", "OK 没有错误文案")
	_check(Breeding.cost_text().contains("100G"), "一次繁殖 100G（%s）" % Breeding.cost_text())

	# 挂妊娠
	_check(Breeding.start(cow_a, cow_b, 3), "start() 成功")
	_check(cow_a.is_pregnant() and cow_a.pregnant_days == 3, "母体妊娠 3 天")
	_check(cow_a.gestation == 3, "记住总天数（进度条用）")
	_check(cow_a.partner_species == &"cow", "记住配偶物种")
	_check(not cow_b.is_pregnant(), "只有母体妊娠")
	_check(not Breeding.start(cow_a, cow_b, 0), "妊娠天数 0 拒绝")

# ---------------- 7. 生崽（需求 ④）----------------

func _test_birth() -> void:
	print("[7] 妊娠倒计时 → 生崽")
	var h := Herd.new(13)
	var mom := h.add(&"goat", 900, Vector2(100, 100))
	var dad := h.add(&"goat", 900, Vector2(140, 100))
	mom.debug_grow_adult()
	dad.debug_grow_adult()
	Breeding.start(mom, dad, 3)

	var born_events := 0
	for i in range(3):
		for e in h.advance_day():
			if e["type"] == "birth":
				born_events += 1
	_check(born_events == 1, "第 3 天广播一次 birth（实际 %d）" % born_events)
	_check(h.size() == 3, "牧群多了一只（%d）" % h.size())
	_check(h.count_species(&"goat") == 3, "3 只山羊")
	var baby: AnimalState = h.animals[2]
	_check(not baby.is_adult() and baby.species == &"goat", "新生幼崽是同种、未成年")
	_check(not mom.is_pregnant() and mom.pregnant_days == 0, "生完不再妊娠")
	_check(baby.awakened == false, "幼崽没觉醒")

	# 牧场上限
	var h2 := Herd.new(17)
	for i in range(Herd.MAX_ANIMALS):
		h2.add(&"chicken", 0, Vector2.ZERO)
	_check(h2.size() == Herd.MAX_ANIMALS, "牧场上限 %d" % Herd.MAX_ANIMALS)
	_check(h2.is_full(), "is_full() = true")
	_check(h2.add(&"chicken", 0, Vector2.ZERO) == null, "满了以后 add 返回 null")

# ---------------- 8. 秘密花园几何（需求 ⑤）----------------

func _test_garden_geometry() -> void:
	print("[8] 秘密花园：地图与几何")
	var r := WorldConfig.garden_rect()
	_check(r.size == Vector2(WorldConfig.GARDEN_TILES * WorldConfig.TILE),
		"花园尺寸 = 格数 × 32（%s）" % str(r.size))
	_check(r.size.x >= 640.0 and r.size.y >= 360.0,
		"花园不小于视口 640×360（%s）" % str(r.size))
	_check(WorldConfig.garden_walls().size() == 4, "花园 4 面围墙")
	_check(WorldConfig.GARDEN_ORIGIN.x >= WorldConfig.MAP_PX.x,
		"花园在主地图右侧，不重叠（%d >= %d）" % [WorldConfig.GARDEN_ORIGIN.x, WorldConfig.MAP_PX.x])
	_check(not WorldConfig.garden_rect().intersects(Rect2(Vector2.ZERO, Vector2(WorldConfig.MAP_PX))),
		"花园矩形和主地图矩形不相交")

	# 主地图那套一点没动（模块 1 的钉子）
	_check(WorldConfig.camera_limits() == [0, 0, 768, 448], "camera_limits() 仍是主地图")
	_check(WorldConfig.camera_limits_for(false) == [0, 0, 768, 448], "camera_limits_for(false)")
	_check(WorldConfig.camera_limits_for(true) == WorldConfig.garden_camera_limits(),
		"camera_limits_for(true) = 花园")
	_check(WorldConfig.garden_camera_limits() == [832, 32, 1472, 416],
		"花园相机范围（%s）" % str(WorldConfig.garden_camera_limits()))

	_check(WorldConfig.in_garden(WorldConfig.GARDEN_ENTRY), "进场落点在花园里")
	_check(WorldConfig.in_garden(WorldConfig.GARDEN_PORTAL_POS), "传送门在花园里")
	_check(not WorldConfig.in_garden(WorldConfig.FARM_ENTRY), "回程落点不在花园里")
	_check(not WorldConfig.in_garden(Vector2(384, 224)), "牧场中央不在花园里")

	# 花园格子不能压到主地图格子
	var go := WorldConfig.garden_cell_origin()
	_check(go.x >= WorldConfig.MAP_TILES.x, "花园格原点 x 在主地图格数之后（%d）" % go.x)

	# 9 座石碑：都在花园里、互不重合
	var ids := AnimalDB.all_ids()
	var ok_in := true
	var min_gap := 9999.0
	for i in range(ids.size()):
		var p := WorldConfig.stele_pos(i, ids.size())
		if not WorldConfig.in_garden(p):
			ok_in = false
		for j in range(i + 1, ids.size()):
			min_gap = minf(min_gap, p.distance_to(WorldConfig.stele_pos(j, ids.size())))
	_check(ok_in, "9 座石碑都在花园范围内")
	_check(min_gap > 20.0, "石碑互不重合（最近 %.0f px）" % min_gap)
	_check(WorldConfig.stele_pos(0, 0) == WorldConfig.GARDEN_FOUNTAIN, "0 座时不崩")

	# 围墙真的围着花园
	var wall_hit := false
	var wall_miss := false
	for w in WorldConfig.garden_walls():
		if w.has_point(WorldConfig.GARDEN_ENTRY + Vector2(0, -1000)):
			wall_hit = true
	_check(not wall_hit, "花园中心不在墙里")
	for w in WorldConfig.garden_walls():
		if w.has_point(Vector2(r.position.x + 3, r.get_center().y)):
			wall_miss = true
	_check(wall_miss, "左墙覆盖花园左边界")

# ---------------- 9. 解锁判定（需求 ⑤）----------------

func _test_garden_unlock() -> void:
	print("[9] 全部觉醒 → 解锁")
	var h := Herd.new(19)
	var ids := AnimalDB.all_ids()
	for i in range(ids.size() - 1):
		var a := h.add(ids[i], 0, Vector2.ZERO)
		a.debug_grow_adult()
		a.debug_awaken()
	_check(h.awakened_species_count() == ids.size() - 1, "觉醒 %d 种" % (ids.size() - 1))
	_check(not h.all_species_awakened(), "还差一种 → 没全觉醒")

	var last := h.add(ids[ids.size() - 1], 0, Vector2.ZERO)
	last.debug_grow_adult()
	last.debug_awaken()
	_check(h.all_species_awakened(), "9 种全觉醒 → all_species_awakened")
	_check(h.awakened_animals().size() == ids.size(), "觉醒个体数 = 9")

	# 同一个物种觉醒两只，也只算一种
	var h2 := Herd.new(23)
	var c1 := h2.add(&"cow", 0, Vector2.ZERO)
	var c2 := h2.add(&"cow", 0, Vector2.ZERO)
	c1.debug_awaken()
	c2.debug_awaken()
	_check(h2.awakened_species_count() == 1, "同种两只只算一种")
	_check(not h2.all_species_awakened(), "只有奶牛一种，不解锁")

# ---------------- 10. 对话框 UI（需求 ①）----------------

func _test_dialogue_ui() -> void:
	print("[10] 对话框（拟人化对话）")
	var d := DialogueUI.new()
	add_child(d)
	await get_tree().process_frame
	_check(not d.is_open(), "初始是关的")
	_check(not d.visible, "初始不可见")

	d.show_dialogue("布伦希尔德 · 牧场之母", ["第一句", "第二句", "第三句"], Color("#F2F0EA"))
	_check(d.is_open() and d.visible, "show_dialogue 后打开")
	_check(EventBus.ui_modal, "对话期间 ui_modal = true（冻住玩家）")
	_check(d.current_line() == "第一句", "从第一句开始（%s）" % d.current_line())
	_check(d.progress() == "1/3", "进度 1/3")

	# 打开那一帧的 E 必须被吞掉
	var ev := InputEventKey.new()
	ev.keycode = KEY_E
	ev.pressed = true
	d._unhandled_input(ev)
	_check(d.current_line() == "第一句", "打开当帧按 E 不会翻页")

	await get_tree().process_frame
	await get_tree().process_frame
	d._unhandled_input(ev)
	_check(d.current_line() == "第二句", "E 翻到第二句")
	d._unhandled_input(ev)
	_check(d.current_line() == "第三句" and d.progress() == "3/3", "翻到第三句")

	var closed := [0]
	d.closed.connect(func() -> void: closed[0] += 1)
	d._unhandled_input(ev)
	_check(not d.is_open() and not d.visible, "最后一句再按一次 → 关掉")
	_check(not EventBus.ui_modal, "关掉后解冻")
	_check(closed[0] == 1, "广播一次 closed")

	# 队列：连发两组不会丢台词
	d.show_dialogue("甲", ["A1", "A2"])
	d.show_dialogue("乙", ["B1"])
	_check(d.current_line() == "A1" and d.pending_count() == 1, "第二组排队等着")
	d.advance()
	d.advance()
	_check(d.current_line() == "B1", "第一组播完自动接上第二组")
	_check(d.pending_count() == 0, "队列清空")

	# Esc 跳过
	d.skip()
	_check(not d.is_open(), "Esc 直接看完")

	# 空台词不弹
	d.show_dialogue("空", [])
	_check(not d.is_open(), "空台词不弹框")

	d.queue_free()
	await get_tree().process_frame

# ---------------- 11. 商店壳的新能力 ----------------

func _test_shop_widget() -> void:
	print("[11] 商店壳：换标题 / 无价格行")
	var shop := ShopUI.new()
	add_child(shop)
	await get_tree().process_frame
	shop.open("繁殖棚 · 选第一只", [
		{"id": &"cow_1", "name": "奶牛", "price": 0, "note": "成年 · 9 心 · 健康", "enabled": true},
	])
	_check(shop.is_open(), "打开")
	_check(not shop._line(0, shop._entries[0]).contains("0G"), "price = 0 不显示价格列")
	shop.update_title("繁殖棚 · 选第二只")
	_check(shop._title == "繁殖棚 · 选第二只", "update_title 改标题")
	shop.update_entries([
		{"id": &"cow_2", "name": "奶牛", "price": 0, "note": "x", "enabled": true},
	])
	_check(shop.current_id() == &"cow_2", "换货架后光标还在")
	shop.close()
	shop.queue_free()
	await get_tree().process_frame

# ---------------- 12. main 集成 ----------------

func _test_main() -> void:
	print("[12] main.gd 集成")
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

	# --- 新节点 ---
	_check(main.get_node_or_null("UI/Dialogue") is DialogueUI, "UI 有对话框")
	_check(main.get_node_or_null("World/SupplyShop") is SupplyShop, "场景里有杂货铺")
	_check(main.get_node_or_null("World/BreedingShed") is BreedingShed, "场景里有繁殖棚")
	_check(main.get_node_or_null("World/GardenGate") is GardenGate, "场景里有藤蔓门")
	_check(main.get_node_or_null("World/GardenPortal") is GardenPortal, "场景里有回程传送门")
	_check(main.get_node_or_null("World/GardenDecor") is GardenDecor, "场景里有花园装饰层")
	_check(main.get_node_or_null("World/GardenCollision") is StaticBody2D, "场景里有花园碰撞层")

	var garden_col := main.get_node("World/GardenCollision")
	_check(garden_col.get_child_count() == 4, "花园碰撞 = 4 面墙（实际 %d）" % garden_col.get_child_count())
	var decor: GardenDecor = main.get_node("World/GardenDecor")
	_check(not decor.visible, "没解锁时花园装饰层不可见")

	# --- 开局牧群：8 只成年 + 1 只幼年火鸡 ---
	var herd: Herd = main._herd
	_check(herd.size() == 9, "开局 9 只（%d）" % herd.size())
	_check(herd.count_species(&"cow") == 2, "开局 2 头奶牛")
	_check(herd.animals[5].species == &"sheep" and herd.animals[7].species == &"bee",
		"索引 5/7 仍是绵羊/蜜蜂（模块 4 测试依赖）")
	var baby_turkey: AnimalState = herd.animals[8]
	_check(baby_turkey.species == &"turkey" and not baby_turkey.is_adult(),
		"第 9 只是幼年火鸡（开局能看见成长）")

	# --- 开局补给含药剂 / 木材 ---
	_check(GameState.count_item(&"medicine") == 3, "开局 3 瓶药剂")
	_check(GameState.count_item(&"wood") == 10, "开局 10 根木材")

	# --- 杂货铺货架 ---
	var shop: ShopUI = main._shop
	EventBus.shop_requested.emit(&"supply")
	await get_tree().process_frame
	_check(shop.is_open(), "杂货铺打开")
	_check(main._shop_kind == &"supply", "货架类型 = supply")
	_check(shop._entries.size() == 3, "货架 3 项（%d）" % shop._entries.size())
	var ids: Array = []
	for e in shop._entries:
		ids.append(e["id"])
	_check(ids.has(&"feed") and ids.has(&"medicine") and ids.has(&"wood"), "有饲料 / 药剂 / 木材")

	# 买药剂
	var med_before := GameState.count_item(&"medicine")
	var gold_before := GameState.gold
	main._on_buy(&"medicine")
	_check(GameState.count_item(&"medicine") == med_before + 1, "买下药剂进背包")
	_check(GameState.gold == gold_before - 180, "扣 180G（实际 %d）" % (gold_before - GameState.gold))

	# 买木材
	var wood_before := GameState.count_item(&"wood")
	main._on_buy(&"wood")
	_check(GameState.count_item(&"wood") == wood_before + 1, "买下木材进背包")
	_check(main._shop_kind == &"supply", "买完货架没串到别的商店")

	# 买饲料（模块 4 的窟窿：饲料以前没地方补）
	var feed_before := GameState.count_item(&"feed")
	main._on_buy(&"feed")
	_check(GameState.count_item(&"feed") == feed_before + 1, "买下饲料进背包")

	shop.close()
	await get_tree().process_frame

	# --- 治病流程 ---
	var cow: AnimalState = herd.animals[0]
	cow.sick = true
	cow.sick_days = 2
	cow.debug_feed_full()
	cow.affection = 500
	var p: Player = main.get_node("World/YSortRoot/Player")
	_stand_near(p, cow)
	var med2 := GameState.count_item(&"medicine")
	main._handle_animal(Player.Tool.HAND)
	_check(not cow.sick, "空手对着生病的牛按 E → 治好了")
	_check(GameState.count_item(&"medicine") == med2 - 1, "消耗 1 瓶药剂")
	_check(cow.affection == 500 + AnimalState.CURE_AFFECTION, "治病回补好感（%d）" % cow.affection)
	_check(main._tip.text.contains("退烧"), "提示文案：%s" % main._tip.text)

	# 没药剂 → 拒绝 + 提示
	cow.sick = true
	GameState.remove_item(&"medicine", GameState.count_item(&"medicine"))
	main._handle_animal(Player.Tool.HAND)
	_check(cow.sick, "没药剂治不了")
	_check(main._tip.text.contains("杂货铺"), "提示去杂货铺：%s" % main._tip.text)
	cow.sick = false
	cow.sick_days = 0

	# --- 繁殖棚：没盖 → 提示造价 ---
	_check(not GameState.has_flag(&"shed_built"), "开局没盖棚")
	GameState.gold = 0
	EventBus.shop_requested.emit(&"breed")
	await get_tree().process_frame
	_check(not shop.is_open(), "钱不够时不弹选父母的界面")
	_check(main._tip.text.contains("还差"), "提示差多少钱：%s" % main._tip.text)

	GameState.gold = 5000
	GameState.remove_item(&"wood", GameState.count_item(&"wood"))
	EventBus.shop_requested.emit(&"breed")
	await get_tree().process_frame
	_check(not GameState.has_flag(&"shed_built"), "木材不够也盖不起来")
	_check(main._tip.text.contains("木材"), "提示缺木材：%s" % main._tip.text)

	# 够了 → 盖起来
	GameState.add_item(&"wood", 30)
	var gold_build := GameState.gold
	var wood_build := GameState.count_item(&"wood")
	EventBus.shop_requested.emit(&"breed")
	await get_tree().process_frame
	_check(GameState.has_flag(&"shed_built"), "繁殖棚盖好了")
	_check(GameState.gold == gold_build - 1200, "扣 1200G")
	_check(GameState.count_item(&"wood") == wood_build - 20, "扣 20 根木材")
	_check(not shop.is_open(), "盖房不弹商店")
	_check(main._tip.text.contains("盖好了"), "提示盖好了：%s" % main._tip.text)

	# --- 选父母：两只不同种的 → 拒绝 ---
	var hen: AnimalState = herd.animals[2]
	cow.affection = 900
	hen.affection = 900
	EventBus.shop_requested.emit(&"breed")
	await get_tree().process_frame
	_check(shop.is_open() and main._shop_kind == &"breed", "繁殖棚打开选父母界面")
	_check(shop._entries.size() == herd.size(), "货架列出全部 %d 只" % herd.size())
	main._on_buy(cow.uid)
	_check(main._breed_picks.size() == 1, "选中第一只")
	_check(shop._title.contains("第二只"), "标题切换成选第二只：%s" % shop._title)
	main._on_buy(hen.uid)
	_check(main._breed_picks.is_empty(), "配不上就清空选择")
	_check(not cow.is_pregnant(), "跨物种没配上")
	_check(main._tip.text.contains("同种"), "提示要同种：%s" % main._tip.text)
	_check(shop.is_open(), "失败后界面还开着，可以重选")

	# --- 选父母：两只奶牛 → 成功 ---
	var cow2: AnimalState = herd.animals[1]
	cow2.debug_grow_adult()
	cow2.affection = 900
	cow2.sick = false
	var gold_breed := GameState.gold
	var feed_breed := GameState.count_item(&"feed")
	main._on_buy(cow.uid)
	main._on_buy(cow2.uid)
	_check(cow.is_pregnant() and cow.pregnant_days == 3, "配上：妊娠 3 天")
	_check(GameState.gold == gold_breed - Breeding.GOLD_COST, "扣手续费 %dG" % Breeding.GOLD_COST)
	_check(GameState.count_item(&"feed") == feed_breed - Breeding.FEED_COST,
		"扣饲料 ×%d" % Breeding.FEED_COST)
	_check(not shop.is_open(), "成功后关掉界面")
	_check(main._tip.text.contains("配上了"), "提示：%s" % main._tip.text)

	# --- 全部觉醒 → 解锁花园 ---
	_check(not GameState.garden_unlocked, "开局花园是锁的")
	var gate: GardenGate = main.get_node("World/GardenGate")
	_check(gate.prompt().contains("沉睡"), "藤蔓门提示沉睡：%s" % gate.prompt())
	# ⚠️ 开局只有 6 个物种（牛/鸡/绵羊/鸭/蜜蜂/火鸡），缺的 3 种要先去动物商店买。
	#    解锁按**物种**算，所以这里必须补全 9 种。
	for sp in [&"goat", &"pig", &"alpaca"]:
		var bought := herd.add(sp, 0, main._free_spawn_pos())
		if bought != null:
			bought.debug_grow_adult()
	main._animal_layer.rebuild()
	_check(herd.awakened_species_count() == 0, "还没觉醒任何一种")
	for a in herd.animals:
		a.debug_grow_adult()
		a.debug_awaken()
		a.just_awakened = false        # 手动清掉，免得弹出 9 个对话框
	_check(herd.awakened_species_count() == AnimalDB.all_ids().size(),
		"9 种全觉醒（%d）" % herd.awakened_species_count())
	main._sync_garden()
	_check(GameState.garden_unlocked, "9 种全觉醒 → garden_unlocked")
	_check(decor.visible, "花园装饰层可见")
	_check(decor.is_species_awakened(&"cow"), "奶牛石碑点亮")
	_check(not gate.prompt().contains("沉睡"), "藤蔓门提示可进入：%s" % gate.prompt())
	_check(main._tip.text.contains("藤蔓门开了"), "提示解锁：%s" % main._tip.text)
	# 解锁那一刻会弹对话，先看完再往下走（不然会盖住后面要断言的对话）
	while main._dialogue.is_open():
		main._dialogue.skip()

	# --- 传送 ---
	var cam: Camera2D = p.get_node("Camera2D")
	main._on_portal(&"garden")
	_check(p.global_position == WorldConfig.GARDEN_ENTRY, "落到花园入口")
	_check(WorldConfig.in_garden(p.global_position), "人在花园里")
	_check(main._zone_garden, "_zone_garden = true")
	_check(cam.limit_left == WorldConfig.GARDEN_ORIGIN.x, "相机 limit 换成花园（left=%d）" % cam.limit_left)
	main._update_zone()
	_check(main._zone_garden, "已经在花园里不会来回切")

	main._on_portal(&"farm")
	_check(p.global_position == WorldConfig.FARM_ENTRY, "回到牧场落点")
	_check(not main._zone_garden, "_zone_garden = false")
	_check(cam.limit_right == WorldConfig.MAP_PX.x, "相机 limit 换回主地图")

	# 没解锁时传送门不给过
	GameState.set_flag(&"garden_unlocked", false)
	main._on_portal(&"garden")
	_check(not WorldConfig.in_garden(p.global_position), "锁着的时候进不去")
	_check(main._tip.text.contains("锁着"), "提示还锁着：%s" % main._tip.text)
	GameState.set_flag(&"garden_unlocked", true)

	# --- 觉醒会弹对话 ---
	var target: AnimalState = herd.animals[3]
	target.affection = 999
	target.awakened = false
	target.just_awakened = false
	target.fed_today = 0          # ⚠️ 别用 debug_feed_full()：那样它会「已经吃饱」，喂不进去
	_stand_near(p, target)
	main._handle_animal(Player.Tool.FEED)
	_check(target.awakened, "喂到 10 心 → 觉醒")
	_check(main._dialogue.is_open(), "立刻弹出拟人化对话")
	_check(main._dialogue._speaker.contains(Awakening.persona(&"chicken")),
		"标题是这只动物的拟人名（%s）" % main._dialogue._speaker)
	_check(main._dialogue._lines.size() >= 2, "对话有多句台词")
	_check(not target.just_awakened, "弹完清掉 just_awakened（不会重复弹）")
	main._dialogue.skip()
	await get_tree().process_frame

	# --- HUD 有觉醒进度 ---
	main._refresh_hud()
	var hud: Label = main.get_node("UI/HUD")
	_check(hud.text.contains("觉醒"), "HUD 显示觉醒进度：%s" % hud.text.split("\n")[0])
	_check(hud.text.contains("秘密花园"), "解锁后 HUD 显示花园标记")
	main._refresh_toolbar()
	var tb: Label = main.get_node("UI/ToolBar")
	_check(tb.text.contains("药剂") and tb.text.contains("木材"), "工具条显示药剂 / 木材")

	# --- 跨日：事件汇总不崩，且生崽后动物层会重建 ---
	EventBus.day_advanced.emit(2, 0, 1)
	await get_tree().process_frame
	var layer: AnimalLayer = main.get_node("World/YSortRoot/AnimalLayer")
	_check(layer.get_child_count() == main._herd.size(),
		"动物层节点数 == 牧群数（%d vs %d）" % [layer.get_child_count(), main._herd.size()])

	main.queue_free()
	await get_tree().process_frame

## 把玩家摆到目标动物左侧 30px、面朝右 ——
## 这样 interact_point() 正好落在动物身前 10px，不会被隔壁那只「抢焦点」。
func _stand_near(p: Player, a: AnimalState) -> void:
	p.global_position = a.pos + Vector2(-30, 0)
	p.facing = "right"
	p.facing8 = "right"
