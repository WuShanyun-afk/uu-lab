extends Node
## 模块 3 验收：种植系统（锄地 → 播种 → 浇水 → 施肥 → 生长 → 收获 → 品质 → 出货）
##
## 覆盖需求：
##   1. 完整种植循环
##   2. 每季 6-8 种作物 + 生长天数 / 售价
##   3. 季节限制（春天不能种南瓜）
##   4. 品质分级（普通 / 银星 / 金星）
##   5. 肥料系统（两档 · 品质 · 生长代价）
##   6. 与时间系统联动（每天推进时作物生长）
##
## 运行： godot --headless --path <项目> res://tests/test_module3.tscn

var _fails: Array[String] = []

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails.append(label)
	print(("  [OK] " if cond else "  [FAIL] ") + label)

## 概率表断言（避开 0.05+0.10 = 0.15000000000000002 的浮点坑）
func _chance_is(aff: int, lv: int, silver: float, gold: float) -> bool:
	var ch := Fertilizer.quality_chance(aff, lv)
	return absf(float(ch[0]) - silver) < 0.0001 and absf(float(ch[1]) - gold) < 0.0001

func _ready() -> void:
	print("=== 模块 3 验收：种植系统 ===")
	_test_crop_table()
	_test_season_gate()
	_test_quality()
	_test_fertilizer()
	_test_growth_over_time()
	_test_tile_hygiene()
	_test_loop_end_to_end()
	await _test_main_integration()

	var ok := _fails.is_empty()
	print("=== 结果：%s ===" % ("全部通过" if ok else "失败 %d 项" % _fails.size()))
	if not ok:
		for f in _fails:
			print("   ! " + f)
	get_tree().quit(0 if ok else 1)

# ---------------- 1. 作物数据表（需求 2）----------------

func _test_crop_table() -> void:
	print("[1] 作物数据表：每季 6-8 种 · 天数 / 售价齐全")
	_check(CropDB.crops.size() == 24, "作物共 24 种（实际 %d）" % CropDB.crops.size())
	for s in range(4):
		var n: int = CropDB.of_season(s).size()
		_check(n >= 6 and n <= 8, "%s季 %d 种（要求 6-8）" % [CropDB.SEASON_NAME[s], n])
	_check(CropDB.ordered_ids().size() == CropDB.crops.size(), "ordered_ids 覆盖全表")

	var bad_days := 0
	var bad_price := 0
	var bad_season := 0
	var bad_color := 0
	var unprofitable := 0
	for id in CropDB.all_ids():
		var c: CropData = CropDB.get_crop(id)
		if c.grow_days < 1 or c.grow_days > 28:
			bad_days += 1
		if c.seed_price <= 0 or c.sell_price <= 0:
			bad_price += 1
		if c.season < 0 or c.season > 3:
			bad_season += 1
		if not Color.html_is_valid(c.color):
			bad_color += 1
		# 回本校验：单次收获看一株；再生作物看一季 28 天内能收几茬
		var harvests := 1
		if c.regrow_days > 0:
			harvests = 1 + int(floor(float(maxi(0, 28 - c.grow_days)) / float(c.regrow_days)))
		if c.sell_price * harvests <= c.seed_price:
			unprofitable += 1
	_check(bad_days == 0, "全部作物生长天数在 1-28 天（异常 %d）" % bad_days)
	_check(bad_price == 0, "全部作物种子价/售价 > 0（异常 %d）" % bad_price)
	_check(bad_season == 0, "全部作物季节在 0-3（异常 %d）" % bad_season)
	_check(bad_color == 0, "全部作物颜色是合法 hex（异常 %d）" % bad_color)
	_check(unprofitable == 0, "一季内每株作物都能回本（亏本 %d 种）" % unprofitable)

	var t: CropData = CropDB.get_crop(&"turnip")
	_check(t != null and t.grow_days == 4 and t.sell_price == 35, "芜菁：4 天 / 35G")
	_check(t != null and t.season_name() == "春", "芜菁是春季作物")
	_check(t != null and t.fertilize == 0, "芜菁施肥需求 = 低")
	var p: CropData = CropDB.get_crop(&"pumpkin")
	_check(p != null and p.season_name() == "秋", "南瓜是秋季作物")
	_check(p != null and p.grow_days == 13 and p.sell_price == 320, "南瓜：13 天 / 320G")
	_check(p != null and p.fertilize == 2, "南瓜施肥需求 = 高")
	var w: CropData = CropDB.get_crop(&"winter_wheat")
	_check(w != null and w.season == 3, "冬小麦是冬季耐寒作物")
	_check(CropDB.season_of(&"nope") == -1, "未知作物 season_of = -1")

# ---------------- 2. 季节限制（需求 3）----------------

func _test_season_gate() -> void:
	print("[2] 季节限制")
	var spring := FarmGrid.new(1001)
	spring.season = 0
	spring.till(Vector2i(1, 1))
	_check(spring.plant(Vector2i(1, 1), &"pumpkin") == false, "春天种不了南瓜")
	_check(spring.plant_reason(Vector2i(1, 1), &"pumpkin") == FarmGrid.WRONG_SEASON,
		"失败原因 = WRONG_SEASON")
	_check(spring.plant(Vector2i(1, 1), &"turnip"), "春天能种芜菁")
	_check(not spring.can_plant(&"pumpkin"), "can_plant(南瓜) = false")
	_check(spring.can_plant(&"turnip"), "can_plant(芜菁) = true")

	spring.till(Vector2i(2, 2))
	_check(spring.plant_reason(Vector2i(2, 2), &"tomato") == FarmGrid.WRONG_SEASON,
		"春天种不了夏季番茄")
	_check(spring.plant_reason(Vector2i(2, 2), &"cranberry") == FarmGrid.WRONG_SEASON,
		"春天种不了秋季蔓越莓")

	var summer := FarmGrid.new(1002)
	summer.season = 1
	summer.till(Vector2i(1, 1))
	_check(summer.plant(Vector2i(1, 1), &"tomato"), "夏天能种番茄")
	summer.till(Vector2i(2, 2))
	_check(not summer.plant(Vector2i(2, 2), &"turnip"), "夏天种不了春季芜菁")

	var winter := FarmGrid.new(1003)
	winter.season = 3
	winter.till(Vector2i(1, 1))
	_check(winter.plant(Vector2i(1, 1), &"winter_wheat"), "冬天能种耐寒的冬小麦")
	winter.till(Vector2i(2, 2))
	_check(not winter.plant(Vector2i(2, 2), &"turnip"), "冬天种不了普通芜菁")
	_check(not SeasonEffects.can_plant_outdoor(3), "普通作物冬季户外禁种（模块 2 语义保留）")

	var sandbox := FarmGrid.new(1004)
	sandbox.season = -1
	sandbox.till(Vector2i(1, 1))
	_check(sandbox.plant(Vector2i(1, 1), &"pumpkin"), "season = -1 时不做季节门禁（沙盒）")

# ---------------- 3. 品质分级（需求 4）----------------

func _test_quality() -> void:
	print("[3] 品质分级：普通 / 银星 / 金星")
	_check(CropQuality.NAME.size() == 3 and CropQuality.NAME[1] == "银星", "三档品质名")
	_check(is_equal_approx(CropQuality.price_mult(0), 1.0), "普通 ×1.00")
	_check(is_equal_approx(CropQuality.price_mult(1), 1.5), "银星 ×1.5（GDD §3.3）")
	_check(is_equal_approx(CropQuality.price_mult(2), 2.0), "金星 ×2.0（GDD §3.3）")

	_check(CropQuality.item_id(&"turnip", 0) == &"turnip", "普通 → turnip")
	_check(CropQuality.item_id(&"turnip", 1) == &"turnip_silver", "银星 → turnip_silver")
	_check(CropQuality.item_id(&"turnip", 2) == &"turnip_gold", "金星 → turnip_gold")

	var s1 := CropQuality.split(&"turnip_silver")
	_check(s1["id"] == &"turnip" and int(s1["quality"]) == 1, "split 还原银星")
	var s2 := CropQuality.split(&"turnip_gold")
	_check(s2["id"] == &"turnip" and int(s2["quality"]) == 2, "split 还原金星")
	var s0 := CropQuality.split(&"turnip")
	_check(s0["id"] == &"turnip" and int(s0["quality"]) == 0, "split 无后缀 = 普通")
	var sm := CropQuality.split(&"milk")
	_check(sm["id"] == &"milk" and int(sm["quality"]) == 0, "畜产品 milk 不被误判")
	var sml := CropQuality.split(&"milk_large")
	_check(sml["id"] == &"milk_large" and int(sml["quality"]) == 0, "milk_large 不被误判成金星")

	_check(CropQuality.label("芜菁", 0) == "芜菁", "普通名不带前缀")
	_check(CropQuality.label("芜菁", 1) == "银星芜菁", "银星名带前缀")
	_check(CropQuality.label("芜菁", 2) == "金星芜菁", "金星名带前缀")

	_check(CropDB.quality_price(&"turnip", 0) == 35, "芜菁普通 35G")
	_check(CropDB.quality_price(&"turnip", 1) == 53, "芜菁银星 53G（35×1.5）")
	_check(CropDB.quality_price(&"turnip", 2) == 70, "芜菁金星 70G（35×2.0）")
	_check(CropDB.crop_of_item(&"turnip_gold") != null, "crop_of_item 认得出金星芜菁")
	_check(CropDB.crop_of_item(&"milk") == null, "crop_of_item 认不出牛奶")

	# 品质概率表（底子 + 施肥需求加成）
	_check(_chance_is(0, 0, 0.05, 0.0), "不施肥：5% 银 / 0% 金")
	_check(_chance_is(1, 0, 0.05, 0.0), "需求中不施肥也是 5%")
	_check(_chance_is(1, 1, 0.15, 0.0), "需求中 + 基础肥：+10% → 15% 银")
	_check(_chance_is(1, 2, 0.25, 0.05), "需求中 + 高级肥：+25% → 25% 银 / 5% 金")
	_check(_chance_is(0, 2, 0.17, 0.03), "需求低 + 高级肥：加成打折")
	_check(_chance_is(2, 2, 0.33, 0.08), "需求高 + 高级肥：加成最高")
	_check(Fertilizer.quality_total(2, 2) > Fertilizer.quality_total(1, 2), "需求越高加成越大")

	# 统计验证（固定种子，可复现）
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var n := 8000
	var cases := [
		[1, 0, 0.05],   # 需求中 · 不施肥
		[1, 1, 0.15],   # 需求中 · 基础肥
		[1, 2, 0.30],   # 需求中 · 高级肥（GDD 的 +25%）
		[2, 2, 0.41],   # 需求高 · 高级肥
		[0, 2, 0.20],   # 需求低 · 高级肥
	]
	for case in cases:
		var aff: int = case[0]
		var lv: int = case[1]
		var expect: float = case[2]
		var hit := 0
		var gold := 0
		for i in range(n):
			var q := Fertilizer.roll_quality(aff, lv, rng)
			if q >= CropQuality.Level.SILVER:
				hit += 1
			if q == CropQuality.Level.GOLD:
				gold += 1
		var rate := float(hit) / n
		_check(absf(rate - expect) < 0.025,
			"需求%d + %s 优质率 ≈%.0f%%（实测 %.3f）" % [aff, Fertilizer.level_name(lv), expect * 100.0, rate])
		if aff == 2 and lv == 2:
			_check(absf(float(gold) / n - 0.08) < 0.015, "需求高 + 高级肥 金星率 ≈8%%（实测 %.3f）" % (float(gold) / n))

# ---------------- 4. 肥料系统（需求 5）----------------

func _test_fertilizer() -> void:
	print("[4] 肥料系统")
	_check(Fertilizer.NAME.size() == 3 and Fertilizer.NAME[2] == "高级肥", "两档肥料名")
	_check(Fertilizer.item_id(1) == &"fertilizer", "基础肥 item id")
	_check(Fertilizer.item_id(2) == &"fertilizer_high", "高级肥 item id")
	_check(Fertilizer.item_id(0) == &"", "未施肥没有物品")
	_check(Fertilizer.name_of_item(&"fertilizer") == "基础肥", "反查物品名")
	_check(Fertilizer.name_of_item(&"turnip") == "", "非肥料反查为空")
	_check(Fertilizer.price(1) == 100, "基础肥 100G（GDD §4.1）")
	_check(Fertilizer.price(2) == 300, "高级肥 300G（GDD §4.1）")

	# 生长代价：高级肥 +1 天，但需求「高」的作物吸收好、不加天
	_check(Fertilizer.growth_delta(0, 0) == 0, "不施肥不改变天数")
	_check(Fertilizer.growth_delta(1, 1) == 0, "基础肥不改变天数")
	_check(Fertilizer.growth_delta(0, 2) == 1, "需求低 + 高级肥 → +1 天")
	_check(Fertilizer.growth_delta(1, 2) == 1, "需求中 + 高级肥 → +1 天")
	_check(Fertilizer.growth_delta(2, 2) == 0, "需求高 + 高级肥 → 不加天")

	var g := FarmGrid.new(2001)
	g.season = 0
	var bare := Vector2i(3, 3)

	_check(g.fertilize_reason(bare, 1) == FarmGrid.NOT_TILLED, "未耕地不能施肥")
	_check(not g.fertilize(bare, 1), "未耕地施肥失败")
	g.till(bare)
	_check(g.fertilize(bare, 1), "耕地施肥成功")
	_check(g.tile_at(bare).fertilized == 1, "fertilized = 基础肥")
	_check(g.fertilize_reason(bare, 1) == FarmGrid.ALREADY_BETTER, "同级肥不能重复施")
	_check(g.fertilize(bare, 2), "基础肥可以升级成高级肥")
	_check(g.tile_at(bare).fertilized == 2, "fertilized = 高级肥")
	_check(g.fertilize_reason(bare, 1) == FarmGrid.ALREADY_BETTER, "高级肥不会被基础肥降级")
	_check(g.tile_at(bare).fertilized == 2, "降级失败后仍是高级肥")

	# 成熟天数：土豆需求中(6天) · 草莓需求高(8天) · 芜菁需求低(4天)
	var cp := Vector2i(5, 5)      # 土豆 + 基础肥 → 6
	var cph := Vector2i(6, 6)     # 土豆 + 高级肥 → 7
	var cs := Vector2i(7, 7)      # 草莓 + 高级肥 → 8（需求高，不加天）
	var ct := Vector2i(8, 8)      # 芜菁 + 高级肥 → 5（需求低，+1 天）
	var cp2 := Vector2i(9, 9)     # 土豆 不施肥 → 6
	g.till(cp); g.fertilize(cp, 1); g.plant(cp, &"potato")
	g.till(cph); g.fertilize(cph, 2); g.plant(cph, &"potato")
	g.till(cs); g.fertilize(cs, 2); g.plant(cs, &"strawberry")
	g.till(ct); g.fertilize(ct, 2); g.plant(ct, &"turnip")
	g.till(cp2); g.plant(cp2, &"potato")

	_check(g.effective_grow_days(cp) == 6, "土豆+基础肥 → 6 天")
	_check(g.effective_grow_days(cph) == 7, "土豆+高级肥 → 7 天")
	_check(g.effective_grow_days(cs) == 8, "草莓+高级肥 → 8 天（需求高不加天）")
	_check(g.effective_grow_days(ct) == 5, "芜菁+高级肥 → 5 天（需求低 +1 天）")
	_check(g.effective_grow_days(cp2) == 6, "土豆不施肥 → 6 天")

	# 五格一起浇水 7 天（advance_day 是全局的，必须一起喂水，否则会渴死）
	var all := [cp, cph, cs, ct, cp2]
	for i in range(7):
		for k in all:
			g.water(k)
		g.advance_day()
	_check(g.is_mature(cp), "第 6 天 土豆+基础肥 成熟")
	_check(g.is_mature(cp2), "第 6 天 土豆不施肥 成熟")
	_check(g.is_mature(cph), "第 7 天 土豆+高级肥 成熟（晚 1 天）")
	_check(g.is_mature(ct), "芜菁+高级肥 5 天就熟了")
	_check(not g.is_mature(cs), "第 7 天 草莓还差 1 天")
	g.water(cs)
	g.advance_day()
	_check(g.is_mature(cs), "第 8 天 草莓成熟")

	# 一次性作物收获后肥料被吃掉；再生作物保留
	var ot := g.harvest(ct)
	_check(not ot.is_empty(), "芜菁收获成功")
	_check(g.tile_at(ct).fertilized == 0, "一次性作物收获后肥料归零")
	_check(g.tile_at(ct).crop_id == StringName(""), "一次性作物收获后地块清空")
	var os := g.harvest(cs)
	_check(not os.is_empty(), "草莓收获成功")
	_check(g.tile_at(cs).fertilized == 2, "再生作物收获后肥料保留")
	_check(g.tile_at(cs).crop_id == &"strawberry", "再生作物留在地里")
	_check(g.days_left(cs) == 4, "草莓收获后还要 4 天再生")
	for i in range(4):
		g.water(cs)
		g.advance_day()
	_check(g.is_mature(cs), "4 天后草莓再生成熟")

# ---------------- 5. 生长 / 时间联动（需求 6）----------------

func _test_growth_over_time() -> void:
	print("[5] 与时间系统联动")
	var g := FarmGrid.new(3001)
	g.season = 0
	var wet := Vector2i(1, 1)
	var dry := Vector2i(2, 2)
	g.till(wet)
	g.till(dry)
	g.plant(wet, &"potato")
	g.plant(dry, &"potato")

	g.water(wet)
	var ev := g.advance_day()
	_check(g.tile_at(wet).days_grown == 1, "浇过水的作物 +1 天")
	_check(g.tile_at(dry).days_grown == 0, "没浇水的作物不长")
	_check(g.tile_at(wet).watered == false, "跨日后 watered 重置")
	_check(g.tile_at(dry).dry_days == 1, "没浇水 dry_days = 1")
	_check(ev.size() == 0, "第 1 天没有灾害事件")

	_check(g.growth_ratio(wet) > 0.0 and g.growth_ratio(wet) < 1.0, "生长进度在 (0,1)")
	_check(g.days_left(wet) == 5, "土豆还差 5 天（6 天成熟）")

	# 成熟事件
	var g2 := FarmGrid.new(3002)
	g2.season = 0
	var c := Vector2i(0, 0)
	g2.till(c)
	g2.plant(c, &"turnip")
	var last: Array = []
	for i in range(4):
		g2.water(c)
		last = g2.advance_day()
	var types: Array = []
	for e in last:
		types.append(e["type"])
	_check(types.has("mature"), "成熟当天广播 mature 事件")
	_check(g2.is_mature(c) and g2.days_left(c) == 0, "成熟后 days_left = 0")

	# 枯萎 → 枯死
	var g3 := FarmGrid.new(3003)
	g3.season = 0
	var w := Vector2i(0, 0)
	g3.till(w)
	g3.plant(w, &"potato")
	g3.advance_day()
	g3.advance_day()
	_check(g3.tile_at(w).dry_days == 2 and not g3.tile_at(w).dead, "2 天没浇 = 枯萎未死")
	g3.advance_day()
	g3.advance_day()
	_check(g3.tile_at(w).dead, "4 天没浇 = 枯死")

# ---------------- 6. 地块卫生（锄地清理枯死作物）----------------

func _test_tile_hygiene() -> void:
	print("[6] 枯死作物清理")
	var g := FarmGrid.new(4001)
	g.season = 0
	var c := Vector2i(4, 4)
	g.till(c)
	g.plant(c, &"turnip")
	for i in range(4):
		g.advance_day()
	_check(g.tile_at(c).dead, "4 天不浇 → 枯死")
	_check(not g.plant(c, &"turnip"), "枯死地块不能直接播种")
	_check(g.till(c), "锄头能清理枯死作物")
	_check(g.tile_at(c).crop_id == StringName("") and not g.tile_at(c).dead, "清理后地块干净")
	_check(g.tile_at(c).tilled, "清理后仍是耕地")
	_check(g.plant(c, &"turnip"), "清理后能重新播种")

	var g2 := FarmGrid.new(4002)
	g2.till(Vector2i(0, 0))
	g2.plant(Vector2i(0, 0), &"turnip")
	_check(not g2.till(Vector2i(0, 0)), "有活作物的地块不能锄")
	_check(g2.clear_crop(Vector2i(0, 0)), "clear_crop 能强制铲掉")
	_check(g2.tile_at(Vector2i(0, 0)).crop_id == StringName(""), "铲掉后地块空")

# ---------------- 7. 完整循环 + 出货箱（需求 1 / 4）----------------

func _test_loop_end_to_end() -> void:
	print("[7] 完整循环：锄地 → 施肥 → 播种 → 浇水 → 生长 → 收获 → 出货")
	GameState.reset()
	var bin := ShippingBin.new()
	add_child(bin)

	# 出货箱只卖能卖的
	_check(bin.is_sellable(&"turnip"), "作物可卖")
	_check(bin.is_sellable(&"turnip_gold"), "金星作物可卖")
	_check(bin.is_sellable(&"milk"), "畜产品可卖")
	_check(not bin.is_sellable(&"feed"), "饲料不可卖")
	_check(not bin.is_sellable(Fertilizer.item_id(1)), "肥料不可卖")

	# 模块 7：unit_price 现在含「当日行情」（Market），标价改看 base_price。
	# 断言标价钉死 35/53/70，再断言实收落在行情 ±15% 区间内。
	_check(bin.base_price(&"turnip") == 35, "出货箱标价：芜菁 35G")
	_check(bin.base_price(&"turnip_silver") == 53, "出货箱标价：银星芜菁 53G")
	_check(bin.base_price(&"turnip_gold") == 70, "出货箱标价：金星芜菁 70G")
	_check(bin.unit_price(&"turnip_gold") > bin.unit_price(&"turnip"), "金星比普通值钱")
	_check(bin.unit_price(&"turnip") >= 29 and bin.unit_price(&"turnip") <= 41,
		"实收在行情 ±15% 内（%dG）" % bin.unit_price(&"turnip"))

	var season_backup := GameClock.season
	GameClock.season = 2
	_check(bin.base_price(&"pumpkin") == 352, "秋季：南瓜 320 × 1.1 = 352G")
	GameClock.season = season_backup

	var g := FarmGrid.new(5001)
	g.season = 0
	var cell := Vector2i(2, 2)
	_check(g.till(cell), "① 锄地")
	_check(g.fertilize(cell, 2), "② 施高级肥")
	_check(g.plant(cell, &"turnip"), "③ 播种")
	_check(g.water(cell), "④ 浇水")
	for i in range(5):
		g.water(cell)
		g.advance_day()
	_check(g.is_mature(cell), "⑤ 5 天后成熟（需求低 +1 天）")
	var out := g.harvest(cell)
	_check(not out.is_empty(), "⑥ 收获")
	_check(out["id"] == &"turnip", "产出基础 id = turnip")
	_check(int(out["quality"]) >= 0 and int(out["quality"]) <= 2, "品质在 0-2")
	_check(out["item"] == CropQuality.item_id(out["id"], int(out["quality"])), "item 带品质后缀")
	GameState.add_item(out["item"], int(out["count"]))
	_check(GameState.count_item(out["item"]) == 1, "⑦ 进背包")

	# 非卖品留在背包里
	GameState.add_item(&"feed", 3)
	GameState.add_item(Fertilizer.item_id(1), 2)
	_check(bin.sellable_count() == 1, "只有 1 件可卖（饲料/肥料不算）")
	var before := GameState.gold
	bin.interact(null)
	_check(GameState.gold > before, "⑧ 出货换到金币（+%dG）" % (GameState.gold - before))
	_check(GameState.count_item(out["item"]) == 0, "作物被卖掉")
	_check(GameState.count_item(&"feed") == 3, "饲料留在背包")
	_check(GameState.count_item(Fertilizer.item_id(1)) == 2, "肥料留在背包")

	# 品质确实会影响收入：60 株施肥作物里必须出现银星/金星
	GameState.reset()
	var g2 := FarmGrid.new(5002)
	for k in range(60):
		var ck := Vector2i(k % 12, k / 12)
		g2.till(ck)
		g2.fertilize(ck, 2)
		g2.plant(ck, &"turnip")
	for i in range(5):
		for k in range(60):
			g2.water(Vector2i(k % 12, k / 12))
		g2.advance_day()
	var shiny := 0
	for k in range(60):
		var o := g2.harvest(Vector2i(k % 12, k / 12))
		if not o.is_empty() and int(o["quality"]) > 0:
			shiny += 1
	_check(shiny >= 5, "高级肥 60 株里出现 %d 株银星/金星（期望 ~12）" % shiny)

	bin.queue_free()

# ---------------- 8. main.gd 集成 ----------------

func _test_main_integration() -> void:
	print("[8] main.gd 集成")
	var ps: PackedScene = load("res://scenes/main.tscn")
	_check(ps != null, "main.tscn 可加载")
	if ps == null:
		return
	var main := ps.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().physics_frame

	_check(main._grid != null, "main 建好了 FarmGrid")
	_check(main._grid.season == GameClock.season, "季节门禁已同步（%d）" % main._grid.season)

	var tb: Label = main.get_node_or_null("UI/ToolBar")
	_check(tb != null, "UI/ToolBar 存在")
	if tb != null:
		_check(tb.text.contains("锄头") and tb.text.contains("高级肥"), "工具条列出 7 个工具")
		_check(tb.text.contains("芜菁") and tb.text.contains("需肥"), "工具条显示种子与需肥等级")

	var p: Player = main.get_node("World/YSortRoot/Player")
	_check(Player.TOOL_LABEL.size() == 7, "工具总数 7")
	_check(p.selected_seed == &"turnip", "默认种子 = 芜菁")

	p.cycle_seed(1)
	_check(p.selected_seed != &"turnip", "Tab 切到了下一颗种子")
	p.set_seed(&"pumpkin")
	_check(p.seed_label() == "南瓜(秋)", "种子标签带季节")

	var cell := Vector2i(4, 6)
	main._plant(cell)
	_check(main._tip.text.contains("锄头"), "未锄地播种 → 提示先用锄头")

	main._grid.till(cell)
	main._plant(cell)
	_check(main._tip.text.contains("秋季作物"), "春天种南瓜被拒并说明原因：%s" % main._tip.text)
	_check(main._grid.tile_at(cell).crop_id == StringName(""), "被拒后地块仍是空的")

	p.set_seed(&"turnip")
	main._plant(cell)
	_check(main._grid.tile_at(cell).crop_id == &"turnip", "换成当季作物后种下了")

	# 施肥走 main（消耗背包）
	var fert_item := Fertilizer.item_id(Fertilizer.Level.BASIC)
	var fert_before := GameState.count_item(fert_item)
	_check(fert_before > 0, "开局给了基础肥（%d 袋）" % fert_before)
	main._on_tool_used(Player.Tool.FERT, cell)
	_check(main._grid.tile_at(cell).fertilized == 1, "main 施肥写入地块")
	_check(GameState.count_item(fert_item) == fert_before - 1, "施肥消耗 1 袋")
	_check(main._tip.text.contains("施基础肥"), "施肥有提示：%s" % main._tip.text)

	# 成熟 → 收获走 main
	main._grid.debug_grow(cell, 4)
	_check(main._grid.is_mature(cell), "催熟后成熟")
	main._on_tool_used(Player.Tool.HOE, cell)
	_check(main._grid.tile_at(cell).crop_id == StringName(""), "main 收获后地块清空")
	_check(main._tip.text.contains("收获"), "main 给出收获提示：%s" % main._tip.text)

	# HUD 里能看到作物 / 肥料统计
	main._refresh_hud()
	var hud: Label = main.get_node("UI/HUD")
	_check(hud.text.contains("地["), "HUD 显示地块统计")

	main.queue_free()
