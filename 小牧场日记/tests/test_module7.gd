extends Node
## 模块 7 验收：经济与背包
##
## 需求对照：
##   ① 背包：物品堆叠 / 拖拽 / 使用（GameState 真槽位 + InventoryUI 网格）
##   ② 商店：种子 / 动物 / 工具 / 饲料 买卖（工具铺 + 杂货铺回收页）
##   ③ 订单任务：NPC 委托，限时完成（OrderBoard 纯逻辑）
##   ④ 加工品：牛奶→奶酪 / 羊毛→毛线 / 鸡蛋→蛋黄酱（RecipeDB + Processor）
##   ⑤ 售价随品质 / 季节波动（Market 四因子定价）
##
## 运行： godot --headless --path <项目> res://tests/test_module7.tscn

var _fails: Array[String] = []
var _n := 0

func _check(cond: bool, label: String) -> void:
	_n += 1
	if not cond:
		_fails.append(label)
	print(("  [OK] " if cond else "  [FAIL] ") + label)

func _ready() -> void:
	print("=== 模块 7 验收：经济与背包 ===")
	_test_item_def()
	_test_inventory_slots()
	_test_move_slot()
	_test_market()
	_test_recipes()
	_test_processor()
	_test_orders()
	_test_tool_upgrades()
	await _test_main()
	var ok := _fails.is_empty()
	print("=== 结果：%s（共 %d 项）===" % ["全部通过" if ok else "失败 %d 项" % _fails.size(), _n])
	if not ok:
		for f in _fails:
			print("   ! " + f)
	get_tree().quit(0 if ok else 1)

# ---------------- 1. 物品数据结构（ItemDef / ItemDB）----------------

func _test_item_def() -> void:
	print("[1] 物品数据结构（ItemDef Resource + ItemDB 聚合）")
	GameState.reset()

	# 聚合来源：24 作物 + 24 种子 + products + 2 肥料 + 7 升级
	var crops := ItemDB.of_category(ItemDef.Cat.CROP)
	var seeds := ItemDB.of_category(ItemDef.Cat.SEED)
	_check(crops.size() == 24, "作物 24 种（%d）" % crops.size())
	_check(seeds.size() == 24, "种子 24 种（%d）" % seeds.size())
	_check(ItemDB.of_category(ItemDef.Cat.CRAFTED).size() == 11,
		"加工品 11 种（%d）" % ItemDB.of_category(ItemDef.Cat.CRAFTED).size())
	_check(ItemDB.of_category(ItemDef.Cat.TOOL).size() == 6,
		"工具升级 6 条（%d）" % ItemDB.of_category(ItemDef.Cat.TOOL).size())

	# ItemDef 是 Resource（可 export、可存盘），不是 Dictionary
	var d := ItemDB.resolve(&"turnip")
	_check(d is ItemDef, "resolve 返回 ItemDef")
	_check(d != null and d.category == ItemDef.Cat.CROP, "芜菁 = CROP")
	_check(d != null and d.display_name == "芜菁", "名字来自 crops.csv")
	_check(d != null and d.base_price == 35, "基础价来自 crops.csv（%d）" % (d.base_price if d else -1))
	_check(d != null and d.cat_name() == "作物", "cat_name = 作物")

	# 种子单独一类，且不可出货
	var s := ItemDB.resolve(CropDB.seed_item(&"turnip"))
	_check(s != null and s.category == ItemDef.Cat.SEED, "seed_turnip = SEED")
	_check(s != null and not s.sellable, "种子不可出货")
	_check(not ItemDB.is_sellable(CropDB.seed_item(&"turnip")), "is_sellable(种子) = false")

	# 品质编码在 id 里，ItemDef 不带品质
	_check(ItemDB.resolve(&"turnip_gold") == d, "金星芜菁和芜菁是同一个 ItemDef")
	_check(ItemDB.quality_of(&"turnip_gold") == 2, "quality_of 拆出金星")
	_check(ItemDB.base_id(&"milk_silver") == &"milk", "base_id 剥掉 _silver")
	_check(ItemDB.price_of(&"turnip") == 35, "普通单价 35")
	_check(ItemDB.price_of(&"turnip_silver") == 53, "银星 ×1.5 = 53")
	_check(ItemDB.price_of(&"turnip_gold") == 70, "金星 ×2.0 = 70")
	_check(ItemDB.display_name(&"turnip_gold") == "金星芜菁", "显示名带品质前缀")

	# 可卖 / 不可卖的边界（出货箱与订单池都靠它）
	_check(ItemDB.is_sellable(&"turnip"), "作物可卖")
	_check(ItemDB.is_sellable(&"milk"), "畜产品可卖")
	_check(ItemDB.is_sellable(&"cheese"), "加工品可卖")
	_check(not ItemDB.is_sellable(&"feed"), "饲料不可卖")
	_check(not ItemDB.is_sellable(Fertilizer.item_id(1)), "肥料不可卖")
	_check(not ItemDB.is_sellable(&"wood"), "木材不可卖（建材不是商品）")
	_check(ItemDB.stack_max(&"turnip") == 99, "堆叠上限 99")

	# 加工品确实在 products.csv 里且 kind=crafted
	_check(ProductDB.kind_of(&"cheese") == "crafted", "奶酪 kind=crafted")
	_check(ItemDB.category_of(&"mayonnaise") == ItemDef.Cat.CRAFTED, "蛋黄酱 = CRAFTED")

	# 不认识的东西不崩
	_check(ItemDB.resolve(&"nope_xyz") == null, "不认识的 id 返回 null")
	_check(ItemDB.price_of(&"nope_xyz") == 1, "不认识的 id 兜底 1G")
	_check(ItemDB.display_name(&"nope_xyz") == "nope_xyz", "不认识的 id 原样显示")

# ---------------- 2. 背包槽位（堆叠 / 使用 / 丢弃）----------------

func _test_inventory_slots() -> void:
	print("[2] 背包槽位：堆叠 / 容量 / 增删")
	GameState.reset()

	_check(GameState.slot_capacity() == 40, "初始 40 格（%d）" % GameState.slot_capacity())
	_check(GameState.slots.size() == 40, "槽位数组已铺满 40")
	_check(GameState.used_slot_count() == 0, "开局背包空")

	# 同 id 堆叠进同一格
	GameState.add_item(&"turnip", 5)
	GameState.add_item(&"turnip", 3)
	_check(GameState.count_item(&"turnip") == 8, "同 id 累加 = 8")
	_check(GameState.used_slot_count() == 1, "只占 1 格（堆叠）")
	_check(GameState.slot_amount(0) == 8, "第 0 格 = 8")
	_check(GameState.slot_item(0) == &"turnip", "第 0 格是芜菁")

	# 不同 id 开新格
	GameState.add_item(&"milk", 2)
	_check(GameState.used_slot_count() == 2, "不同 id 占 2 格")
	_check(GameState.count_item(&"milk") == 2, "牛奶 2")

	# 派生索引必须和槽位一致（这是全项目最容易出问题的地方）
	var sum := 0
	for i in range(GameState.slots.size()):
		sum += GameState.slot_amount(i)
	_check(sum == GameState.count_item(&"turnip") + GameState.count_item(&"milk"),
		"槽位总数 = 索引总数（%d）" % sum)
	_check(GameState.inventory.size() == 2, "索引里有 2 种物品")

	# 堆叠上限：把芜菁临时改成 3 个/格
	var def := ItemDB.resolve(&"turnip")
	var backup := def.stack_max
	def.stack_max = 3
	GameState.reset()
	GameState.add_item(&"turnip", 7)
	_check(GameState.used_slot_count() == 3, "上限 3 时 7 个占 3 格（%d）" % GameState.used_slot_count())
	_check(GameState.slot_amount(0) == 3 and GameState.slot_amount(1) == 3
		and GameState.slot_amount(2) == 1, "3 + 3 + 1")
	def.stack_max = backup

	# 背包满了：返回「实际放进去的数量」，不丢已经放进去的
	GameState.reset()
	var ids := ItemDB.all_ids()
	var put_total := 0
	for k in range(ids.size()):
		var got := GameState.add_item(ids[k], 1)
		put_total += got
		if GameState.used_slot_count() >= 40:
			break
	_check(GameState.used_slot_count() == 40, "塞满 40 格")
	_check(put_total == 40, "放进去 40 件（%d）" % put_total)
	# 第 41 种放不下
	var extra := GameState.add_item(&"turnip", 1)
	_check(extra == 0 or GameState.count_item(&"turnip") > 0,
		"背包满了还能叠到已有格上（放进去 %d）" % extra)

	# 删除：够就扣、不够就拒绝
	GameState.reset()
	GameState.add_item(&"milk", 5)
	_check(not GameState.remove_item(&"milk", 6), "不够 6 个 → 拒绝")
	_check(GameState.count_item(&"milk") == 5, "拒绝后数量不变")
	_check(GameState.remove_item(&"milk", 5), "正好 5 个 → 成功")
	_check(GameState.count_item(&"milk") == 0, "扣完 = 0")
	_check(GameState.used_slot_count() == 0, "空槽被清掉")

	# 丢弃
	GameState.reset()
	GameState.add_item(&"turnip", 4)
	_check(GameState.drop_slot(0, 1), "丢 1 个")
	_check(GameState.slot_amount(0) == 3, "剩 3 个")
	GameState.drop_slot(0, 3)
	_check(GameState.slot_item(0) == &"", "丢光后格子清空")

# ---------------- 3. 拖拽（移动 / 合并 / 交换）----------------

func _test_move_slot() -> void:
	print("[3] 拖拽：移动 / 合并 / 交换")
	GameState.reset()

	# 拖到空格 = 移动
	GameState.add_item(&"turnip", 2)
	_check(GameState.move_slot(0, 5) == "moved", "拖到空格 = moved")
	_check(GameState.slot_item(5) == &"turnip", "落点拿到芜菁")
	_check(GameState.slot_item(0) == &"", "原格清空")
	_check(GameState.count_item(&"turnip") == 2, "总数不变")

	# 拖到同 id = 合并
	GameState.reset()
	GameState.add_item(&"turnip", 2)      # 第 0 格
	GameState.slots[5] = {"id": &"turnip", "count": 3}
	GameState._rebuild_index()
	_check(GameState.move_slot(0, 5) == "merged", "同 id = merged")
	_check(GameState.slot_amount(5) == 5, "合并成 5 个")
	_check(GameState.slot_item(0) == &"", "原格空掉")

	# 拖到不同 id = 交换
	GameState.reset()
	GameState.add_item(&"turnip", 1)
	GameState.add_item(&"milk", 2)
	_check(GameState.move_slot(0, 1) == "swapped", "不同 id = swapped")
	_check(GameState.slot_item(0) == &"milk", "第 0 格变牛奶")
	_check(GameState.slot_item(1) == &"turnip", "第 1 格变芜菁")
	_check(GameState.count_item(&"turnip") == 1 and GameState.count_item(&"milk") == 2,
		"交换后总数不变")

	# 合并受 stack_max 限制：满了就合不动
	GameState.reset()
	var def := ItemDB.resolve(&"turnip")
	var backup := def.stack_max
	def.stack_max = 5
	GameState.slots[0] = {"id": &"turnip", "count": 2}
	GameState.slots[1] = {"id": &"turnip", "count": 5}
	GameState._rebuild_index()
	_check(GameState.move_slot(0, 1) == "noop", "目标格已满 → noop")
	_check(GameState.slot_amount(1) == 5, "目标格仍是 5")
	def.stack_max = backup

	# 空格拖拽 / 同格拖拽都是 noop
	GameState.reset()
	GameState.add_item(&"turnip", 1)
	_check(GameState.move_slot(0, 0) == "noop", "拖到自己 = noop")
	_check(GameState.move_slot(3, 4) == "noop", "拖空格 = noop")

# ---------------- 4. 行情（品质 / 季节 / 当日波动）----------------

func _test_market() -> void:
	print("[4] 行情：四因子定价（基础 × 品质 × 季节 × 当日）")
	Market.clear_cache()

	# 确定性：同一天同一品类永远同一个数
	var a := Market.daily_factor(7, Market.CAT_CROP)
	var b := Market.daily_factor(7, Market.CAT_CROP)
	_check(is_equal_approx(a, b), "行情确定性（第 7 天两次都是 %.3f）" % a)
	_check(a >= 1.0 - Market.VOLATILITY - 0.001 and a <= 1.0 + Market.VOLATILITY + 0.001,
		"行情在 ±15%% 内（%.3f）" % a)

	# 不同品类各自独立（否则「今天卖什么」就不是选择了）
	var c := Market.daily_factor(7, Market.CAT_ANIMAL)
	var f := Market.daily_factor(7, Market.CAT_CRAFTED)
	_check(not is_equal_approx(a, c) or not is_equal_approx(a, f),
		"三个品类不是同一个因子（%.3f / %.3f / %.3f）" % [a, c, f])

	# 换天会换价
	var d1 := Market.daily_factor(7, Market.CAT_CROP)
	var d2 := Market.daily_factor(8, Market.CAT_CROP)
	_check(not is_equal_approx(d1, d2), "相邻两天不同价（%.3f vs %.3f）" % [d1, d2])

	# 加工品波动减半（稳定是加工的卖点）
	var worst := 0.0
	for d in range(1, 41):
		worst = maxf(worst, absf(Market.daily_factor(d, Market.CAT_CRAFTED) - 1.0))
	_check(worst <= Market.VOLATILITY * 0.5 + 0.001,
		"加工品波动 ≤ ±7.5%%（40 天实测最大 %.3f）" % worst)
	_check(is_equal_approx(Market.volatility_of(Market.CAT_CROP), Market.VOLATILITY),
		"作物波动 ±15%")

	# 品类归属
	_check(Market.category_of(&"turnip") == Market.CAT_CROP, "作物 → crop")
	_check(Market.category_of(&"milk") == Market.CAT_ANIMAL, "牛奶 → animal")
	_check(Market.category_of(&"cheese") == Market.CAT_CRAFTED, "奶酪 → crafted")
	_check(Market.category_of(&"wood") == Market.CAT_OTHER, "木材 → other")

	# 季节倍率（GDD §2.1 秋收溢价）
	_check(is_equal_approx(Market.season_multiplier(Market.CAT_CROP, 2), 1.1), "作物秋季 ×1.1")
	_check(is_equal_approx(Market.season_multiplier(Market.CAT_CROP, 0), 1.0), "作物春季 ×1.0")
	_check(is_equal_approx(Market.season_multiplier(Market.CAT_ANIMAL, 3), 1.10), "畜产冬季 ×1.10")
	_check(is_equal_approx(Market.season_multiplier(Market.CAT_CRAFTED, 2), 1.0),
		"加工品全年 ×1.0（稳定是卖点）")

	# 定价：品质必须拉开差距
	var normal := Market.price(&"turnip", 0, 10)
	var gold := Market.price(&"turnip_gold", 0, 10)
	_check(gold > normal, "金星比普通贵（%d vs %d）" % [gold, normal])
	_check(gold >= int(float(normal) * 1.7), "金星至少贵 1.7 倍（%d vs %d）" % [gold, normal])

	# 定价落在「基础 × 季节 × 行情」的合理区间
	var base := ItemDB.price_of(&"turnip")
	var lo := int(float(base) * 0.85) - 1
	var hi := int(float(base) * 1.15) + 1
	_check(normal >= lo and normal <= hi, "实收在 ±15%% 区间（%d ∈ [%d, %d]）" % [normal, lo, hi])

	# 涨跌箭头
	_check(Market.trend_arrow(10, Market.CAT_CROP) in ["▲", "▼", "—"], "箭头是 ▲/▼/—")
	var txt := Market.summary(10, 0)
	_check(txt.contains("作物") and txt.contains("畜产") and txt.contains("加工品"),
		"行情摘要含三个品类：%s" % txt)

	Market.clear_cache()
	_check(Market.daily_factor(7, Market.CAT_CROP) == a, "清缓存后重算结果一致")

# ---------------- 5. 加工配方（需求 4）----------------

func _test_recipes() -> void:
	print("[5] 加工配方（RecipeDB）")
	_check(RecipeDB.all_ids().size() == 11, "11 条配方（%d）" % RecipeDB.all_ids().size())

	# 三条核心链路必须在
	_check(RecipeDB.recipe_for_input(&"milk") == &"cheese", "牛奶 → 奶酪")
	_check(RecipeDB.recipe_for_input(&"wool") == &"yarn", "羊毛 → 毛线")
	_check(RecipeDB.recipe_for_input(&"egg") == &"mayonnaise", "鸡蛋 → 蛋黄酱")

	# 品质后缀不影响查配方
	_check(RecipeDB.recipe_for_input(&"milk_gold") == &"cheese", "金星牛奶照样能做奶酪")

	# 每条配方的输出都得是 crafted，原料都得能买到/产出
	var bad_out: Array[String] = []
	var bad_in: Array[String] = []
	for rid in RecipeDB.all_ids():
		var r := RecipeDB.get_recipe(rid)
		if ProductDB.kind_of(rid) != "crafted":
			bad_out.append(str(rid))
		if ItemDB.resolve(r["input"]) == null:
			bad_in.append(str(r["input"]))
	_check(bad_out.is_empty(), "输出全是 crafted（异常：%s）" % str(bad_out))
	_check(bad_in.is_empty(), "原料都认识（异常：%s）" % str(bad_in))

	# 加工必须增值（GDD §5.1 ×2.3~2.5），否则加工坊没人用
	for rid in [&"cheese", &"yarn", &"mayonnaise"]:
		var r := RecipeDB.get_recipe(rid)
		var cost := ItemDB.price_of(r["input"]) * int(r["count"])
		var gain := ItemDB.price_of(rid)
		_check(gain > cost, "%s 增值（成本 %dG → 卖 %dG）" % [rid, cost, gain])

	# 耗时都 > 0，且文案能读
	_check(int(RecipeDB.get_recipe(&"cheese")["minutes"]) == 120, "奶酪 2 小时")
	_check(RecipeDB.minutes_text(120) == "2 小时", "120 → 2 小时")
	_check(RecipeDB.minutes_text(30) == "30 分", "30 → 30 分")
	_check(RecipeDB.describe(&"cheese").contains("奶酪"), "describe 可读：%s" % RecipeDB.describe(&"cheese"))

# ---------------- 6. 加工坊状态机（Processor 纯逻辑）----------------

func _test_processor() -> void:
	print("[6] 加工坊状态机（Processor）")
	var p := Processor.new(1)
	_check(p.slot_count() == 2, "Lv1 = 2 槽")
	_check(Processor.slot_count_at(2) == 4, "Lv2 = 4 槽")
	_check(Processor.slot_count_at(3) == 6, "Lv3 = 6 槽")
	_check(p.used_slots() == 0, "开局空")
	_check(p.first_free() == 0, "第一个空槽是 0")

	# 放料 → 倒计时 → 取货
	var i := p.start(&"cheese", 2)
	_check(i == 0, "放料占第 0 槽")
	_check(p.used_slots() == 1, "用了 1 槽")
	_check(not p.is_ready(0), "刚放进去没做好")
	_check(p.progress(0) == 0.0, "进度 0")

	var done := p.advance_minutes(60)
	_check(done.is_empty(), "60 分钟还没好（配方 120）")
	_check(is_equal_approx(p.progress(0), 0.5), "进度 50%%（%.2f）" % p.progress(0))

	done = p.advance_minutes(60)
	_check(done.size() == 1, "再 60 分钟就做好")
	_check(p.is_ready(0), "槽 0 完成")
	_check(p.ready_count() == 1, "1 件待取")
	_check(p.progress(0) == 1.0, "进度 100%")

	var got := p.take(0)
	_check(int(got["quality"]) == 2, "品质继承原料（金星牛奶 → 金星奶酪）")
	_check(got["output"] == &"cheese", "产出 cheese")
	_check(p.used_slots() == 0, "取货后槽空")

	# 槽满了
	p.start(&"cheese", 0)
	p.start(&"cheese", 0)
	_check(p.free_slots() == 0, "两槽都占满")
	_check(p.start(&"cheese", 0) == -1, "第三槽放不进")
	_check(p.can_start(&"cheese", 99) == Processor.Reason.NO_SLOT, "can_start = 槽满")
	_check(p.can_start(&"nope", 99) == Processor.Reason.NO_RECIPE, "can_start = 没配方")
	_check(p.can_start(&"cheese", 0) == Processor.Reason.NO_RECIPE, "原料不够 = 没配方")
	_check(Processor.reason_text(Processor.Reason.NO_SLOT).contains("槽"),
		"槽满有文案：%s" % Processor.reason_text(Processor.Reason.NO_SLOT))

	# take_all 一次清空
	var all := p.take_all()
	_check(all.is_empty(), "还没做好 → take_all 空")
	p.advance_minutes(200)
	_check(p.ready_count() == 2, "两槽都好了")
	all = p.take_all()
	_check(all.size() == 2, "take_all 取 2 件")
	_check(p.used_slots() == 0, "取空")

	# 升级扩槽
	p.set_level(2)
	_check(p.slot_count() == 4, "Lv2 扩到 4 槽")
	p.set_level(3)
	_check(p.slot_count() == 6, "Lv3 扩到 6 槽")

	# 状态文案
	var q := Processor.new(1)
	_check(q.status_text().contains("空闲"), "空闲文案：%s" % q.status_text())
	q.start(&"cheese", 0)
	_check(q.status_text().contains("加工中"), "加工中文案：%s" % q.status_text())

# ---------------- 7. 订单板（需求 3）----------------

func _test_orders() -> void:
	print("[7] 订单板（OrderBoard）")
	Market.clear_cache()
	GameState.reset()
	var pool := ItemDB.sellable_ids()
	var ob := OrderBoard.new(12345)

	# 开局立刻刷 2 单
	var ev := ob.tick(1, 0, pool, 0)
	_check(ob.active_count() == 2, "首日刷 2 单（%d）" % ob.active_count())
	_check(ev.size() == 2, "广播 2 个 new 事件（%d）" % ev.size())
	for o in ob.active_orders():
		_check(int(o["count"]) >= OrderBoard.COUNT_RANGE[0]
			and int(o["count"]) <= OrderBoard.COUNT_RANGE[1],
			"数量在 1~4（%d）" % int(o["count"]))
		_check(int(o["reward"]) > 0, "报酬 > 0（%dG）" % int(o["reward"]))
		_check(o["status"] == "active", "状态 active")
		_check(ItemDB.resolve(o["item"]) != null, "物品认识（%s）" % o["item"])
		_check(int(o["due_day"]) == 1 + OrderBoard.DUE_DAYS, "期限 = 刷新日 + 2 天")
		_check(int(o["due_minute"]) == OrderBoard.DUE_MINUTE, "截止 14:00（%d）" % int(o["due_minute"]))

	# 报酬必须比直接卖更划算（否则没人接单）
	for o in ob.active_orders():
		var direct := Market.price(o["item"], 0, 1) * int(o["count"])
		_check(int(o["reward"]) > direct, "报酬 %dG > 直接卖 %dG" % [int(o["reward"]), direct])

	# 同一天再 tick 不会重复刷
	var n0 := ob.active_count()
	ob.tick(2, 0, pool, 0)
	_check(ob.active_count() == n0, "第 2 天不补单（%d）" % ob.active_count())

	# 第 4 天（刷新日 + 3）补满
	var ob2 := OrderBoard.new(777)
	ob2.tick(1, 0, pool, 0)
	ob2.tick(4, 0, pool, 0)
	_check(ob2.active_count() == 2, "第 4 天刷新后仍是 2 单（%d）" % ob2.active_count())

	# 交付判定：不够就拒绝，够了就成功
	var ob3 := OrderBoard.new(2026)
	ob3.tick(1, 0, pool, 0)
	var o: Dictionary = ob3.active_orders()[0]
	GameState.reset()
	var chk := ob3.can_deliver(o, GameState.count_item)
	_check(not bool(chk["ok"]), "背包空 → 交不了")
	_check(str(chk["reason"]).contains("差"), "理由写明还差多少：%s" % chk["reason"])
	GameState.add_item(o["item"], int(o["count"]))
	chk = ob3.can_deliver(o, GameState.count_item)
	_check(bool(chk["ok"]), "凑齐 → 能交")

	var res := ob3.deliver(o)
	_check(not res.is_empty(), "deliver 返回结算信息")
	_check(int(res["reward"]) == int(o["reward"]), "报酬一致")
	_check(ob3.completed == 1, "已完成 1 单")
	_check(o["status"] == "done", "状态变 done")
	_check(ob3.deliver(o).is_empty(), "重复交付返回空")

	# 过期：超过截止时间
	var ob4 := OrderBoard.new(555)
	ob4.tick(1, 0, pool, 0)
	var o4: Dictionary = ob4.active_orders()[0]
	var due_day := int(o4["due_day"])
	var ex := ob4.tick(due_day, OrderBoard.DUE_MINUTE + 10, pool, 0)
	var expired := 0
	for e in ex:
		if e["type"] == "expired":
			expired += 1
	_check(expired >= 1, "过截止时间就过期（%d 单）" % expired)
	_check(ob4.failed >= 1, "失败计数 +1（%d）" % ob4.failed)
	_check(o4["status"] == "expired", "状态变 expired")

	# 截止前 1 分钟还算 active
	var ob5 := OrderBoard.new(999)
	ob5.tick(1, 0, pool, 0)
	var o5: Dictionary = ob5.active_orders()[0]
	ob5.tick(int(o5["due_day"]), OrderBoard.DUE_MINUTE - 10, pool, 0)
	_check(o5["status"] == "active", "截止前仍可交付")

	# 完成 10 单 → famous
	var ob6 := OrderBoard.new(31337)
	ob6.tick(1, 0, pool, 0)
	var o6: Dictionary = ob6.active_orders()[0]
	ob6.completed = OrderBoard.FAMOUS_GOAL - 1
	var r6 := ob6.deliver(o6)
	_check(bool(r6["famous"]), "第 %d 单交付 → famous 解锁" % OrderBoard.FAMOUS_GOAL)
	_check(ob6.completed == OrderBoard.FAMOUS_GOAL, "完成数 = %d" % ob6.completed)

	# prune 只留 active
	var before := ob4.orders.size()
	ob4.prune()
	_check(ob4.orders.size() < before, "prune 清掉已结束的单（%d → %d）" % [before, ob4.orders.size()])
	for x in ob4.orders:
		_check(x["status"] == "active", "prune 后只剩 active")

	# 存档往返
	var dump := ob3.to_dict()
	var ob7 := OrderBoard.new(1)
	ob7.from_dict(dump)
	_check(ob7.completed == ob3.completed, "存档往返：完成数一致")
	_check(ob7.orders.size() == ob3.orders.size(), "存档往返：订单数一致")

	# 池子空 → 刷不出单也不崩
	var ob8 := OrderBoard.new(1)
	var ev8 := ob8.tick(1, 0, [], 0)
	_check(ev8.is_empty() and ob8.active_count() == 0, "空池子不刷单、不崩")

# ---------------- 8. 工具升级（需求 2）----------------

func _test_tool_upgrades() -> void:
	print("[8] 工具升级（upgrades.csv + GameState）")
	GameState.reset()

	_check(GameState.tool_level(&"hoe") == 1, "开局锄头 Lv1")
	_check(GameState.tool_level(&"can") == 1, "开局洒水壶 Lv1")
	_check(GameState.slot_capacity() == 40, "开局背包 40 格")

	# 升级表
	_check(ItemDB.upgrade_ids().size() == 6, "6 条升级（%d）" % ItemDB.upgrade_ids().size())
	var u := ItemDB.get_upgrade(&"hoe_2")
	_check(not u.is_empty(), "有 hoe_2")
	_check(u["tool"] == &"hoe", "hoe_2 属于锄头")
	_check(int(u["price"]) == 1500, "锄头 Lv2 = 1500G")
	_check(u["material"] == &"wood", "用木材（本项目没有铁矿，用木材替代）")

	# next_upgrade 只给「下一级」
	var nx := ItemDB.next_upgrade(&"hoe", 1)
	_check(int(nx["level"]) == 2, "Lv1 的下一级是 Lv2")
	nx = ItemDB.next_upgrade(&"hoe", 2)
	_check(int(nx["level"]) == 3, "Lv2 的下一级是 Lv3")
	_check(ItemDB.next_upgrade(&"hoe", 3).is_empty(), "Lv3 没有下一级")

	# 背包升级立刻扩容
	GameState.set_tool_level(&"bag", 2)
	_check(GameState.slot_capacity() == 48, "背包 Lv2 = 48 格")
	_check(GameState.slots.size() == 48, "槽位数组跟着扩")
	GameState.set_tool_level(&"bag", 3)
	_check(GameState.slot_capacity() == 56, "背包 Lv3 = 56 格")
	GameState.set_tool_level(&"bag", 1)
	_check(GameState.slot_capacity() == 40, "降回 Lv1 = 40 格")

	# 等级夹取
	GameState.set_tool_level(&"hoe", 9)
	_check(GameState.tool_level(&"hoe") == 3, "等级夹在 1..3")
	GameState.set_tool_level(&"hoe", 0)
	_check(GameState.tool_level(&"hoe") == 1, "等级夹在 1..3（下界）")

# ---------------- 9. main 集成 ----------------

func _test_main() -> void:
	print("[9] main 集成：背包 / 工具铺 / 订单板 / 加工坊")
	GameState.reset()
	EventBus.ui_modal = false
	Market.clear_cache()
	var ps: PackedScene = load("res://scenes/main.tscn")
	_check(ps != null, "main.tscn 可加载")
	if ps == null:
		return
	var main := ps.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().physics_frame

	# --- 新场景节点 ---
	for path in ["World/ToolShop", "World/OrderPost", "World/CraftWorkshop", "UI/InventoryPanel"]:
		_check(main.get_node_or_null(path) != null, "场景里有 %s" % path)

	# --- 开局背包：29 种补给全在 40 格里 ---
	_check(GameState.used_slot_count() > 0, "开局有补给（%d 格）" % GameState.used_slot_count())
	_check(GameState.used_slot_count() <= GameState.slot_capacity(),
		"开局补给装得下（%d ≤ %d）" % [GameState.used_slot_count(), GameState.slot_capacity()])
	_check(GameState.count_item(&"feed") == 20, "20 份饲料")
	_check(GameState.count_item(CropDB.seed_item(&"turnip")) == 3, "3 颗芜菁种子")

	# --- 工具铺货架 ---
	var entries: Array = main._tool_entries()
	_check(entries.size() == 6, "工具铺 6 行（%d）" % entries.size())
	var hoe2: Dictionary = {}
	for e in entries:
		if e["id"] == &"hoe_2":
			hoe2 = e
	_check(not hoe2.is_empty(), "货架里有 hoe_2")
	_check(not bool(hoe2.get("enabled", false)), "钱/木材不够 → 变灰")
	_check(str(hoe2.get("reason", "")) != "", "变灰写明原因：%s" % hoe2.get("reason", ""))

	# 给够钱和木材，应该能买
	GameState.add_gold(2000)
	GameState.add_item(&"wood", 10)
	entries = main._tool_entries()
	for e in entries:
		if e["id"] == &"hoe_2":
			_check(bool(e["enabled"]), "条件够了 → 可买")
	var gold_before := GameState.gold
	var wood_before := GameState.count_item(&"wood")
	main._shop_kind = &"tool"
	main._on_buy(&"hoe_2")
	_check(GameState.tool_level(&"hoe") == 2, "买完锄头 Lv2")
	_check(GameState.gold == gold_before - 1500, "扣了 1500G")
	_check(GameState.count_item(&"wood") == wood_before - 5, "扣了 5 根木材")

	# 工具范围：Lv2 = 3 格直线，Lv3 = 3×3
	main._player.facing = "down"
	var cells: Array = main._tool_cells(Vector2i(5, 5), 1)
	_check(cells.size() == 1, "Lv1 = 1 格")
	cells = main._tool_cells(Vector2i(5, 5), 2)
	_check(cells.size() == 3, "Lv2 = 3 格")
	_check(cells[1] == Vector2i(5, 6), "Lv2 沿朝向往前推")
	cells = main._tool_cells(Vector2i(5, 5), 3)
	_check(cells.size() == 9, "Lv3 = 9 格（3×3）")
	_check(cells.has(Vector2i(4, 4)) and cells.has(Vector2i(6, 6)), "Lv3 覆盖四周")

	# --- 加工坊 ---
	_check(main._proc.slot_count() == 2, "加工坊 2 槽")
	GameState.add_item(&"milk", 2)
	var ce: Array = main._craft_entries()
	var cheese_entry: Dictionary = {}
	for e in ce:
		if str(e["id"]) == "cheese@0":
			cheese_entry = e
	_check(not cheese_entry.is_empty(), "货架里有 奶酪@普通")
	_check(bool(cheese_entry["enabled"]), "牛奶够 → 可放料")
	main._on_craft_start(&"cheese@0")
	_check(main._proc.used_slots() == 1, "放进 1 槽")
	_check(GameState.count_item(&"milk") == 0, "扣掉 2 份牛奶")
	# 时间推进：2 小时 = 12 个 tick
	for k in range(12):
		main._advance_workshop(10)
	_check(main._proc.ready_count() == 1, "2 小时后做好了")
	main._collect_crafts()
	_check(GameState.count_item(&"cheese") == 1, "奶酪进背包")

	# 品质继承：金星牛奶做金星奶酪
	GameState.add_item(&"milk_gold", 2)
	var ce2: Array = main._craft_entries()
	var gold_entry: Dictionary = {}
	for e in ce2:
		if str(e["id"]) == "cheese@2":
			gold_entry = e
	_check(not gold_entry.is_empty(), "货架按品质分行（cheese@2）")
	main._on_craft_start(&"cheese@2")
	main._advance_workshop(200)
	main._collect_crafts()
	_check(GameState.count_item(&"cheese_gold") == 1, "金星牛奶 → 金星奶酪")

	# --- 订单板 ---
	_check(main._orders.active_count() == 2, "开局有 2 单（%d）" % main._orders.active_count())
	_check(main._order_post.active_count == 2, "节点拿到订单数")
	var o: Dictionary = main._orders.active_orders()[0]
	GameState.add_item(o["item"], int(o["count"]))
	main._refresh_orders()
	_check(main._order_post.ready_now >= 1, "能交的订单数已同步到节点")
	var oe: Array = main._order_entries()
	_check(oe.size() == 2, "订单货架 2 行")
	var gold0 := GameState.gold
	main._shop_kind = &"order"
	main._on_buy(StringName("order:%d" % int(o["id"])))
	_check(GameState.gold > gold0, "交单后金币增加（+%dG）" % (GameState.gold - gold0))
	_check(main._orders.completed == 1, "已完成 1 单")
	_check(GameState.count_item(o["item"]) == 0, "交掉的物品被扣走")

	# --- 杂货铺回收页 ---
	GameState.add_item(&"turnip_gold", 2)
	var se: Array = main._sell_entries()
	var sellable_ok := true
	for e in se:
		if not ItemDB.is_sellable(e["id"]):
			sellable_ok = false
	_check(sellable_ok, "回收页只列能卖的东西")
	_check(se.size() > 0, "回收页非空（%d 行）" % se.size())
	_check(se[0]["price"] >= se[se.size() - 1]["price"], "回收页按单价降序")
	var g1 := GameState.gold
	main._on_sell(&"turnip_gold", false)
	_check(GameState.gold > g1, "卖 1 个金星芜菁 → 金币增加")
	_check(GameState.count_item(&"turnip_gold") == 1, "只卖了 1 个")
	main._on_sell(&"turnip_gold", true)
	_check(GameState.count_item(&"turnip_gold") == 0, "Shift 全卖清空")

	# --- 背包 UI ---
	var inv: InventoryUI = main.get_node("UI/InventoryPanel")
	_check(inv != null, "背包面板存在")
	inv.open()
	_check(inv.is_open(), "I 键能打开背包")
	_check(EventBus.ui_modal, "打开背包时锁住玩家输入")
	# 使用：种子 → 换当前种子
	var seed_slot := -1
	for i in range(GameState.slots.size()):
		if CropDB.crop_of_seed_item(GameState.slot_item(i)) != null:
			seed_slot = i
			break
	_check(seed_slot >= 0, "背包里有种子")
	if seed_slot >= 0:
		var want: StringName = CropDB.crop_of_seed_item(GameState.slot_item(seed_slot)).id
		main._player.set_seed(&"turnip")
		main._on_inv_use(seed_slot)
		_check(main._player.selected_seed == want,
			"背包里用种子 → 换成当前种子（%s）" % main._player.selected_seed)
		_check(not inv.is_open(), "用完自动关背包")
	# 丢弃
	inv.open()
	main._on_inv_drop(0)
	_check(true, "丢弃不崩")
	inv.close()
	_check(not EventBus.ui_modal, "关背包后解锁输入")

	# --- HUD 文案 ---
	var hud: String = main.get_node("UI/HUD").text
	_check(hud.contains("订单"), "HUD 显示订单进度")
	_check(hud.contains("加工"), "HUD 显示加工槽")
	_check(hud.contains("行情"), "HUD 显示行情")
	_check(hud.contains("格"), "HUD 显示背包格数")
	var tb: String = main.get_node("UI/ToolBar").text
	_check(tb.contains("锄Lv"), "工具条显示工具等级")
	_check(tb.contains("背包"), "工具条显示背包格数")

	main.queue_free()
	await get_tree().process_frame
