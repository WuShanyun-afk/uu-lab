extends Node
## 模块 9 验收：建造与牧场扩建（你的清单里叫「模块 7」）
##
## 需求对照：
##   ① 放置栅栏 / 畜棚 / 鸡舍 / 加工坊 / 蜂箱
##   ② 升级扩建：容量（棚舍）、效率（加工速度 / 售价）
##   ③ 牧场扩建五阶段：一块地 → 鸡舍 → 畜棚 → 加工坊 → 农贸市场 → 小镇（+ 镇长称号）
##   ④ 布局自由摆放，支持拆除（按实际投入返还 50%）
##
## 分层对照：BuildingDef（CSV）→ PlacedBuilding（实例）→ BuildingGrid（规则）
##           → BuildingNode / BuildCursor（表现）→ main（钱料 + 存档）
##
## 运行： godot --headless --path <项目> res://tests/test_module9.tscn
##
## ⚠️ 本套测试把 SaveSystem.save_dir 指到 user://saves_test9，
##    不会碰玩家真存档（user://saves）。

var _fails: Array[String] = []
var _n := 0

func _check(cond: bool, label: String) -> void:
	_n += 1
	if not cond:
		_fails.append(label)
	print(("  [OK] " if cond else "  [FAIL] ") + label)

func _ready() -> void:
	print("=== 模块 9 验收：建造与牧场扩建 ===")
	SaveSystem.save_dir = "user://saves_test9"
	_clean_saves()
	_test_building_db()
	_test_build_area()
	_test_can_place()
	_test_place_and_remove()
	_test_upgrade()
	_test_ranch_stage()
	_test_grid_save()
	_test_save_v2()
	await _test_main_integration()
	_clean_saves()
	var ok := _fails.is_empty()
	print("=== 结果：%s（共 %d 项）===" % ["全部通过" if ok else "失败 %d 项" % _fails.size(), _n])
	if not ok:
		for f in _fails:
			print("   ! " + f)
	get_tree().quit(0 if ok else 1)

func _clean_saves() -> void:
	var dir := DirAccess.open(SaveSystem.save_dir)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)

# ---------------- 1. 建筑数据结构（需求输出第一项）----------------

func _test_building_db() -> void:
	print("[1] 建筑数据结构：CSV → BuildingDef → BuildingDB")
	_check(BuildingDB.has(&"breeding_shed"), "表里有繁殖棚（模块 5 的老数据没丢）")
	_check(BuildingDB.has(&"fence"), "表里有栅栏")
	_check(BuildingDB.has(&"coop"), "表里有鸡舍")
	_check(BuildingDB.has(&"barn"), "表里有畜棚")
	_check(BuildingDB.has(&"workshop"), "表里有加工坊")
	_check(BuildingDB.has(&"hive"), "表里有蜂箱")
	_check(BuildingDB.has(&"market"), "表里有农贸市场")
	_check(BuildingDB.has(&"town_square"), "表里有小镇广场")
	_check(not BuildingDB.has(&"nope"), "不存在的建筑 → has() = false")

	var coop: BuildingDef = BuildingDB.def_of(&"coop")
	_check(coop != null, "def_of(coop) 不是 null")
	_check(coop.id == &"coop", "id 正确")
	_check(coop.display_name == "鸡舍", "名字正确（%s）" % coop.display_name)
	_check(coop.category == BuildingDef.CAT_HOUSING, "分类 = housing")
	_check(coop.size == Vector2i(3, 2), "占地 3×2（%s）" % str(coop.size))
	_check(coop.price == 900, "造价 900（%d）" % coop.price)
	_check(coop.material == &"wood", "材料 = 木材")
	_check(coop.material_count == 15, "木材 15（%d）" % coop.material_count)
	_check(coop.max_level == 3, "最高 3 级")
	_check(coop.capacity_housing == &"coop", "住的是禽舍（%s）" % coop.capacity_housing)
	_check(coop.capacity_base == 4, "Lv1 容量 4")
	_check(coop.capacity_step == 3, "每级 +3")
	_check(coop.capacity_at(1) == 4, "capacity_at(1) = 4")
	_check(coop.capacity_at(2) == 7, "capacity_at(2) = 7")
	_check(coop.capacity_at(3) == 10, "capacity_at(3) = 10")
	_check(coop.capacity_at(0) == 0, "capacity_at(0) = 0（没盖就没容量）")
	_check(coop.upgrade_gold(1) == 540, "Lv1→2 要 540G（造价 60%%：%d）" % coop.upgrade_gold(1))
	_check(coop.upgrade_gold(2) == 1080, "Lv2→3 要 1080G（%d）" % coop.upgrade_gold(2))
	_check(coop.upgrade_wood(1) == 15, "Lv1→2 要木材 15")
	_check(coop.upgrade_wood(2) == 30, "Lv2→3 要木材 30")
	_check(coop.footprint().size() == 6, "footprint = 6 格（%d）" % coop.footprint().size())
	_check(coop.is_housing(), "is_housing() = true")
	_check(not coop.is_fence(), "is_housing 的 not is_fence")

	var fence: BuildingDef = BuildingDB.def_of(&"fence")
	_check(fence.size == Vector2i(1, 1), "栅栏 1×1")
	_check(fence.max_level == 1, "栅栏没有等级（max_level = 1）")
	_check(fence.is_fence(), "栅栏分类对")
	_check(fence.capacity_at(1) == 0, "栅栏不给容量")

	var ws: BuildingDef = BuildingDB.def_of(&"workshop")
	_check(ws.efficiency == 15, "加工坊每级 +15%%（%d）" % ws.efficiency)
	_check(ws.efficiency_at(1) == 15, "Lv1 速度 +15%")
	_check(ws.efficiency_at(3) == 45, "Lv3 速度 +45%")

	var mk: BuildingDef = BuildingDB.def_of(&"market")
	_check(mk.efficiency == 5, "农贸市场每级 +5% 售价")
	_check(mk.stage_required == 4, "农贸市场要第 4 阶段")

	var special: BuildingDef = BuildingDB.def_of(&"breeding_shed")
	_check(special.category == BuildingDef.CAT_SPECIAL, "繁殖棚 = special")
	_check(not special.buildable(), "繁殖棚不在建造菜单里（走剧情）")
	_check(special.gestation_days == 3, "繁殖棚妊娠 3 天（老字段还在）")

	# 建造菜单：按阶段过滤 + 排序
	var all_menu := BuildingDB.buildable_ids()
	_check(not all_menu.has(&"breeding_shed"), "菜单里没有繁殖棚")
	_check(all_menu.size() == 7, "菜单共 7 种（%d）" % all_menu.size())
	var at0 := BuildingDB.ids_unlocked_at(0)
	_check(at0.size() == 1 and at0[0] == &"fence", "第 0 阶段只能盖栅栏（%s）" % str(at0))
	var at1 := BuildingDB.ids_unlocked_at(1)
	_check(at1.has(&"coop") and at1.has(&"hive"), "第 1 阶段解锁鸡舍 + 蜂箱")
	_check(not at1.has(&"barn"), "第 1 阶段还没有畜棚")
	_check(BuildingDB.ids_unlocked_at(2).has(&"barn"), "第 2 阶段解锁畜棚")
	_check(BuildingDB.ids_unlocked_at(3).has(&"workshop"), "第 3 阶段解锁加工坊")
	_check(BuildingDB.ids_unlocked_at(4).has(&"market"), "第 4 阶段解锁农贸市场")
	_check(BuildingDB.ids_unlocked_at(5).has(&"town_square"), "第 5 阶段解锁小镇广场")

	# 模块 5 的老接口必须还能用（繁殖棚那段代码没改）
	var old: Dictionary = BuildingDB.get_building(&"breeding_shed")
	_check(int(old["price"]) == 1200, "老接口 get_building 还能读出造价")
	_check(int(old["gestation_days"]) == 3, "老接口妊娠天数正确")
	_check(BuildingDB.gestation_days_of(&"breeding_shed") == 3, "gestation_days_of 兼容")
	_check(BuildingDB.price_of(&"coop") == 900, "price_of 新接口")
	_check(BuildingDB.cost_text(&"coop").contains("900"), "cost_text 带造价（%s）"
		% BuildingDB.cost_text(&"coop"))

# ---------------- 2. 建造用地（WorldConfig）----------------

func _test_build_area() -> void:
	print("[2] 建造用地：范围 / 禁区（WorldConfig 是唯一真相）")
	var area := WorldConfig.build_area()
	_check(area.position == Vector2(32, 32), "用地左上内缩 1 格（%s）" % str(area.position))
	_check(area.size == Vector2(704, 384), "用地 22×12 格（%s）" % str(area.size))
	_check(WorldConfig.buildable_cell(Vector2i(1, 1)), "(1,1) 可以盖")
	_check(not WorldConfig.buildable_cell(Vector2i(0, 0)), "(0,0) 是围墙，不能盖")
	_check(not WorldConfig.buildable_cell(Vector2i(-1, 5)), "负坐标不能盖")
	_check(not WorldConfig.buildable_cell(Vector2i(23, 13)), "右下角出界")
	_check(WorldConfig.buildable_cell(Vector2i(22, 12)), "(22,12) 在界内")

	# 牧场围栏里绝对不能盖（三块棚舍分栏在里面，盖上去动物会站墙里）
	_check(WorldConfig.keepout_cell(Vector2i(17, 4)), "牧场围栏内是禁区")
	_check(WorldConfig.keepout_cell(Vector2i(16, 2)), "围栏左上角是禁区")
	# 商店 / 繁殖棚 / 藤蔓门
	_check(WorldConfig.keepout_cell(Vector2i(12, 5)), "种子商店占地是禁区")
	_check(WorldConfig.keepout_cell(Vector2i(19, 9)), "繁殖棚是禁区")
	_check(WorldConfig.keepout_cell(Vector2i(23, 9)), "藤蔓门是禁区")
	_check(not WorldConfig.keepout_cell(Vector2i(2, 10)), "左下草地不是禁区")

	# 每个禁区都得落在主地图内（不然是抄坐标抄错了）
	var out_of_map := 0
	for r in WorldConfig.build_keepers():
		if r.position.x < 0 or r.position.y < 0 \
				or r.end.x > float(WorldConfig.MAP_PX.x) \
				or r.end.y > float(WorldConfig.MAP_PX.y):
			out_of_map += 1
	_check(out_of_map == 0, "所有禁区都在主地图内（越界 %d 个）" % out_of_map)
	_check(WorldConfig.build_keepers().size() == 14, "禁区共 14 块（%d）"
		% WorldConfig.build_keepers().size())
	_check(WorldConfig.px_to_cell(Vector2(33, 65)) == Vector2i(1, 2), "px → 格换算")
	_check(WorldConfig.cell_to_px(Vector2i(3, 4)) == Vector2(96, 128), "格 → px 换算")

# ---------------- 3. 放置规则（需求 1 / 4）----------------

func _test_can_place() -> void:
	print("[3] 放置规则：can_place 的每个返回码都走一遍")
	var g := BuildingGrid.new()
	g.stage = 0
	_check(g.can_place(&"fence", Vector2i(2, 10)) == BuildingGrid.OK, "空地 + 栅栏 → OK")
	_check(g.can_place(&"coop", Vector2i(2, 8)) == BuildingGrid.NO_STAGE,
		"阶段 0 想盖鸡舍 → NO_STAGE")
	_check(g.can_place(&"nope", Vector2i(2, 10)) == BuildingGrid.UNKNOWN,
		"表里没有的建筑 → UNKNOWN")
	_check(g.can_place(&"fence", Vector2i(0, 5)) == BuildingGrid.OUT_OF_BOUNDS,
		"压围墙 → OUT_OF_BOUNDS")
	_check(g.can_place(&"fence", Vector2i(17, 4)) == BuildingGrid.KEEPOUT,
		"压牧场围栏 → KEEPOUT")

	g.stage = 3
	_check(g.can_place(&"coop", Vector2i(2, 8)) == BuildingGrid.OK, "阶段 3 → 鸡舍 OK")
	# 多格建筑的 footprint 也要逐格检查：3×2 的鸡舍横跨进禁区就得拒
	_check(g.can_place(&"coop", Vector2i(15, 7)) == BuildingGrid.KEEPOUT,
		"多格建筑只有一格压禁区 → 整个拒（KEEPOUT）")
	_check(g.can_place(&"coop", Vector2i(0, 1)) == BuildingGrid.OUT_OF_BOUNDS,
		"多格建筑有一格出界 → OUT_OF_BOUNDS")

	# 占地后的重复判定
	var b := g.place(&"coop", Vector2i(2, 8), 3)
	_check(b != null, "鸡舍落地成功")
	_check(g.can_place(&"fence", Vector2i(2, 8)) == BuildingGrid.OCCUPIED, "锚点格被占")
	_check(g.can_place(&"fence", Vector2i(4, 9)) == BuildingGrid.OCCUPIED,
		"3×2 的右下角也算被占")
	_check(g.can_place(&"fence", Vector2i(6, 9)) == BuildingGrid.OK,
		"footprint 外面就自由了")
	_check(g.building_at(Vector2i(3, 8)) != null, "building_at 找到覆盖格")
	_check(g.building_at(Vector2i(3, 8)).anchor == Vector2i(2, 8),
		"building_at 返回的建筑 anchor 正确")
	_check(g.building_at(Vector2i(9, 9)) == null, "空地上 building_at = null")
	_check(b.covers(Vector2i(3, 8)), "PlacedBuilding.covers 覆盖判定")
	_check(not b.covers(Vector2i(9, 9)), "PlacedBuilding.covers 对空地返回 false")

	# 农田不能压
	var g2 := BuildingGrid.new()
	g2.stage = 3
	g2.farm = FarmGrid.new()
	g2.farm.till(Vector2i(5, 10))
	_check(g2.can_place(&"fence", Vector2i(5, 10)) == BuildingGrid.FARM,
		"压已耕的地 → FARM")
	_check(g2.can_place(&"fence", Vector2i(6, 10)) == BuildingGrid.OK,
		"旁边没耕的地还能盖")

	# 原因文案都得是能看的字（不能把枚举名直接怼给玩家）
	for code in [BuildingGrid.OK, BuildingGrid.UNKNOWN, BuildingGrid.NO_STAGE,
			BuildingGrid.OUT_OF_BOUNDS, BuildingGrid.KEEPOUT, BuildingGrid.OCCUPIED,
			BuildingGrid.FARM, BuildingGrid.NOT_FOUND, BuildingGrid.MAX_LEVEL]:
		_check(not g.reason_text(code).contains("_"), "原因文案是人话：%s"
			% g.reason_text(code))

# ---------------- 4. 落地 / 拆除（需求 2 / 4）----------------

func _test_place_and_remove() -> void:
	print("[4] 落地与拆除：账本 + 返还 50%")
	var g := BuildingGrid.new()
	g.stage = 5
	var b := g.place(&"coop", Vector2i(2, 8), 7)
	_check(b != null, "鸡舍落地")
	_check(g.count() == 1, "地上 1 栋")
	_check(b.level == 1, "落地默认 Lv1")
	_check(b.built_day == 7, "记下落成日（第 7 天）")
	_check(b.spent_gold == 900, "账本：花了 900G（%d）" % b.spent_gold)
	_check(b.spent_wood == 15, "账本：花了木材 15")
	_check(b.refund_gold() == 450, "拆了退 450G（%d）" % b.refund_gold())
	_check(b.refund_wood() == 7, "拆了退木材 7（一半向下取整：%d）" % b.refund_wood())

	var r := g.remove_at(Vector2i(3, 8))     # 用非锚点格也能拆到同一栋
	_check(bool(r["ok"]), "用 footprint 内任意一格都能拆")
	_check(int(r["gold"]) == 450, "返还金币 450")
	_check(int(r["wood"]) == 7, "返还木材 7")
	_check(g.count() == 0, "拆完地空了")
	_check(g.can_place(&"fence", Vector2i(2, 8)) == BuildingGrid.OK, "拆完原地又能盖")
	_check(g.can_remove(Vector2i(2, 8)) == BuildingGrid.NOT_FOUND, "空地拆不了")

	var r2 := g.remove_at(Vector2i(9, 9))
	_check(not bool(r2["ok"]), "空地拆除 → ok = false")
	_check(StringName(str(r2["error"])) == BuildingGrid.NOT_FOUND, "错误码 = NOT_FOUND")
	_check(int(r2["gold"]) == 0, "拆空手不退钱")

	# 升级过再拆：返还按**实际投入**算，不是按造价算
	var g2 := BuildingGrid.new()
	g2.stage = 5
	var c := g2.place(&"coop", Vector2i(2, 8), 1)
	g2.upgrade_at(Vector2i(2, 8))
	g2.upgrade_at(Vector2i(2, 8))
	_check(c.level == 3, "连升两级到 Lv3（%d）" % c.level)
	_check(c.spent_gold == 900 + 540 + 1080, "账本累计 2520G（%d）" % c.spent_gold)
	_check(c.refund_gold() == 1260, "Lv3 拆掉退 1260G（%d）" % c.refund_gold())
	var r3 := g2.remove_at(Vector2i(2, 8))
	_check(int(r3["gold"]) == 1260, "拆除实返 1260G")

	# 满级之后不能再升
	var g3 := BuildingGrid.new()
	g3.stage = 5
	g3.place(&"fence", Vector2i(2, 10), 1)
	_check(g3.upgrade_cost(Vector2i(2, 10)).is_empty(), "栅栏满级 → 升级成本为空")
	_check(not g3.upgrade_at(Vector2i(2, 10)), "满级建筑升不动")
	_check(g3.upgrade_cost(Vector2i(8, 8)).is_empty(), "空地上没有升级成本")

# ---------------- 5. 升级：容量 / 效率（需求 2）----------------

func _test_upgrade() -> void:
	print("[5] 升级扩建：容量 + 效率加成")
	var g := BuildingGrid.new()
	g.stage = 5
	g.place(&"coop", Vector2i(2, 8), 1)
	var cost := g.upgrade_cost(Vector2i(2, 8))
	_check(not cost.is_empty(), "Lv1 鸡舍能升级")
	_check(int(cost["gold"]) == 540, "升级价 540G（%d）" % int(cost["gold"]))
	_check(int(cost["wood"]) == 15, "升级木材 15")
	_check(int(cost["from"]) == 1 and int(cost["to"]) == 2, "from/to 正确")
	_check(g.apply_upgrade(Vector2i(2, 8), 540, 15), "升级落地")
	var b := g.building_at(Vector2i(2, 8))
	_check(b.level == 2, "等级到 2")
	_check(b.capacity() == 7, "容量 4 → 7（%d）" % b.capacity())
	_check(b.spent_gold == 1440, "账本累加（%d）" % b.spent_gold)

	# 容量加成汇总给 Housing
	var g2 := BuildingGrid.new()
	g2.stage = 5
	g2.place(&"coop", Vector2i(2, 8), 1)
	g2.place(&"coop", Vector2i(6, 8), 1)
	g2.place(&"hive", Vector2i(2, 2), 1)
	var bonus := g2.capacity_bonus()
	_check(int(bonus.get(&"coop", 0)) == 8, "两栋鸡舍 → 禽舍 +8（%d）"
		% int(bonus.get(&"coop", 0)))
	_check(int(bonus.get(&"hive", 0)) == 3, "一栋蜂箱 → 蜂巢 +3（%d）"
		% int(bonus.get(&"hive", 0)))
	_check(not bonus.has(&"barn"), "没盖畜棚就没有畜舍加成")
	_check(int(Housing.bonus_of(bonus, &"coop")) == 8, "Housing.bonus_of 读数一致")

	# 容量接进模块 6 的公式：棚舍等级容量 + 建筑加成
	var barns := {&"coop": 1}
	var base_cap := HousingDB.capacity_at(&"coop", 1)
	_check(Housing.capacity(barns, &"coop") == base_cap,
		"没加成 = 原容量（%d）" % base_cap)
	_check(Housing.capacity(barns, &"coop", 8) == base_cap + 8,
		"带加成 = 原容量 + 8（%d）" % Housing.capacity(barns, &"coop", 8))
	_check(Housing.capacity(barns, &"coop", -5) == base_cap,
		"负加成就当没有（不许扣容量）")

	# 效率：加工坊加速度、农贸市场加售价
	var g3 := BuildingGrid.new()
	g3.stage = 5
	_check(g3.craft_speed() == 1.0, "没加工坊 → 速度倍率 1.0")
	_check(g3.sell_bonus() == 0.0, "没农贸市场 → 售价加成为 0")
	g3.place(&"workshop", Vector2i(10, 11), 1)
	_check(g3.craft_speed() == 1.15, "Lv1 加工坊 → 1.15（%f）" % g3.craft_speed())
	g3.upgrade_at(Vector2i(10, 11))
	_check(g3.craft_speed() == 1.30, "Lv2 → 1.30（%f）" % g3.craft_speed())
	g3.place(&"market", Vector2i(6, 9), 1)
	_check(g3.sell_bonus() == 0.05, "Lv1 农贸市场 → 售价 +5%（%f）" % g3.sell_bonus())
	_check(g3.max_level_of_category(BuildingDef.CAT_WORKSHOP) == 2,
		"最高工坊等级 = 2")
	_check(g3.buildings_of_category(BuildingDef.CAT_MARKET).size() == 1,
		"地上 1 座市场")
	_check(g3.has_building(&"market"), "has_building(market)")
	_check(not g3.has_building(&"barn"), "has_building(barn) = false")

# ---------------- 6. 阶段（需求 3）----------------

func _test_ranch_stage() -> void:
	print("[6] 牧场五阶段：门槛 / 单调 / 文案")
	_check(RanchStage.STAGES.size() == 6, "阶段表 6 项（0..5：一块地→小镇）")
	_check(RanchStage.last_stage() == 5, "最后一阶段 = 5")
	_check(RanchStage.stage_name(0) == "一块地", "第 0 阶段 = 一块地")
	_check(RanchStage.stage_name(1) == "鸡舍", "第 1 阶段 = 鸡舍")
	_check(RanchStage.stage_name(2) == "畜棚", "第 2 阶段 = 畜棚")
	_check(RanchStage.stage_name(3) == "加工坊", "第 3 阶段 = 加工坊")
	_check(RanchStage.stage_name(4) == "农贸市场", "第 4 阶段 = 农贸市场")
	_check(RanchStage.stage_name(5) == "小镇", "第 5 阶段 = 小镇")
	_check(RanchStage.stage_name(9) == "？", "越界阶段名兜底")

	# 门槛判定
	var none := {}
	_check(not RanchStage.meets(1, none), "什么都没有 → 第 1 阶段不达标")
	_check(RanchStage.meets(1, {RanchStage.M_COINS: 800, RanchStage.M_ANIMALS: 3}),
		"800G + 3 只 → 第 1 阶段达标")
	_check(not RanchStage.meets(1, {RanchStage.M_COINS: 799, RanchStage.M_ANIMALS: 3}),
		"差 1G 就不算达标")
	_check(RanchStage.next_stage(0, none) == 0, "开局原地不动")
	_check(RanchStage.next_stage(0, {RanchStage.M_COINS: 800, RanchStage.M_ANIMALS: 3}) == 1,
		"达标 → 升到 1")
	# 一次只升一级：不能一口气从 0 跳到 5（否则中间那句「解锁 XX」永远看不见）
	var rich := {
		RanchStage.M_COINS: 99999, RanchStage.M_ANIMALS: 99,
		RanchStage.M_ORDERS: 99, RanchStage.M_CRAFTED: 99, RanchStage.M_SOLD: 999,
	}
	_check(RanchStage.next_stage(0, rich) == 1, "指标爆表也只升一级（0→1）")
	_check(RanchStage.next_stage(4, rich) == 5, "第 4 阶段能升到小镇")
	_check(RanchStage.next_stage(5, rich) == 5, "小镇是终点，不再升")
	# 单调：钱花掉了阶段也不掉（next_stage 只看「下一级」，从不回退）
	_check(RanchStage.next_stage(3, none) == 3, "钱花光阶段也不回退")

	_check(RanchStage.clamp_stage(-3) == 0, "负阶段夹到 0")
	_check(RanchStage.clamp_stage(99) == 5, "超界夹到 5")
	_check(RanchStage.valid(5) and not RanchStage.valid(6), "valid() 边界")

	# 还差什么（UI 直接 join 这一行）
	var miss := RanchStage.missing_of(1, {RanchStage.M_COINS: 100, RanchStage.M_ANIMALS: 3})
	_check(miss.size() == 1, "只差金币 → 1 条（%d）" % miss.size())
	_check(miss[0].contains("800"), "缺的条目带目标值（%s）" % miss[0])
	_check(miss[0].contains("100"), "缺的条目带当前值（%s）" % miss[0])
	_check(RanchStage.missing_of(0, none).is_empty(), "第 0 阶段没有门槛")

	var p := RanchStage.progress_to_next(0,
		{RanchStage.M_COINS: 400, RanchStage.M_ANIMALS: 3})
	_check(absf(p - 0.75) < 0.001, "进度 0.75（%f）" % p)
	_check(RanchStage.progress_to_next(5, rich) == 1.0, "终点进度 = 1.0")

	# 镇长 = 终局称号，不是第 6 个阶段
	_check(not RanchStage.is_mayor(4, {RanchStage.M_ORDERS: 99}), "没到小镇当不了镇长")
	_check(not RanchStage.is_mayor(5, {RanchStage.M_ORDERS: 29}), "订单不够当不了镇长")
	_check(RanchStage.is_mayor(5, {RanchStage.M_ORDERS: 30}), "小镇 + 30 单 = 镇长")

	_check(RanchStage.can_build(1, 1), "阶段 1 能盖要求 1 的建筑")
	_check(not RanchStage.can_build(1, 2), "阶段 1 盖不了要求 2 的")
	_check(RanchStage.landmark_building(1) == &"coop", "第 1 阶段地标 = 鸡舍")
	_check(RanchStage.landmark_building(0) == &"", "第 0 阶段没有地标")
	var ann := RanchStage.announce(3)
	_check(ann.contains("加工坊"), "阶段播报带建筑名（%s）" % ann)
	var hud := RanchStage.hud_text(1, {RanchStage.M_COINS: 1000, RanchStage.M_ANIMALS: 4})
	_check(hud.contains("阶段 1/5"), "HUD 文案带阶段号（%s）" % hud)
	_check(hud.contains("畜棚"), "HUD 文案带下一阶段名（%s）" % hud)
	_check(RanchStage.hud_text(5, {RanchStage.M_ORDERS: 30}).contains("镇长"),
		"小镇 + 30 单 → HUD 显示镇长")

# ---------------- 7. 建筑存档 ----------------

func _test_grid_save() -> void:
	print("[7] 建筑存档：to_dict / from_dict 往返")
	var g := BuildingGrid.new()
	g.stage = 3
	g.place(&"coop", Vector2i(2, 8), 5)
	g.place(&"fence", Vector2i(2, 10), 9)
	g.upgrade_at(Vector2i(2, 8))
	var d := g.to_dict()
	_check(int(d["stage"]) == 3, "存档带阶段")
	_check((d["items"] as Array).size() == 2, "存档带 2 栋建筑")

	var g2 := BuildingGrid.new()
	g2.from_dict(d)
	_check(g2.count() == 2, "读档 2 栋")
	_check(g2.stage == 3, "读档阶段 3")
	var c := g2.building_at(Vector2i(2, 8))
	_check(c != null, "读档找到鸡舍")
	_check(c.def_id == &"coop", "def_id 正确（%s）" % c.def_id)
	_check(c.level == 2, "等级 2 保留")
	_check(c.built_day == 5, "落成日保留")
	_check(c.spent_gold == 1440, "账本保留（%d）" % c.spent_gold)
	_check(g2.building_at(Vector2i(2, 10)) != null, "栅栏也读回来了")
	_check(g2.capacity_bonus().get(&"coop", 0) == 7, "读档后容量加成现算正确")

	# 老档 / 脏数据容错
	var g3 := BuildingGrid.new()
	g3.from_dict({"stage": 99, "items": [
		{"id": "coop", "x": 2, "y": 8, "level": 2, "day": 1, "gold": 900, "wood": 15},
		{"id": "已经删掉的建筑", "x": 8, "y": 8, "level": 1, "day": 1, "gold": 0, "wood": 0},
		"不是字典的垃圾",
	]})
	_check(g3.stage == 5, "脏阶段夹到 5（%d）" % g3.stage)
	_check(g3.count() == 1, "不认识的建筑被丢掉，只留 1 栋（%d）" % g3.count())
	_check(g3.building_at(Vector2i(2, 8)).level == 2, "合法建筑正常读回")

	var g4 := BuildingGrid.new()
	g4.from_dict({})
	_check(g4.count() == 0 and g4.stage == 0, "空字典 → 空地 + 阶段 0")

# ---------------- 8. 存档 v2 迁移 ----------------

func _test_save_v2() -> void:
	print("[8] 存档 v2：版本号 + 老档迁移")
	_check(SaveSystem.VERSION >= 2, "存档版本 >= v2（现在是 v%d）" % SaveSystem.VERSION)

	# v1 老档迁移：补 buildings 段，其它一个字段都不许动
	var v1 := {
		"meta": {"day": 12, "gold": 999},
		"clock": {"day": 12},
		"state": {"gold": 999},
	}
	var m := SaveSystem.migrate(v1, 1)
	_check(int(m["version"]) == SaveSystem.VERSION, "迁移后版本 = 当前版本（v%d）" % SaveSystem.VERSION)
	_check(typeof(m.get("buildings")) == TYPE_DICTIONARY, "迁移补了 buildings 段")
	_check(int(m["buildings"]["stage"]) == 0, "老档阶段 = 0（一片空地）")
	_check((m["buildings"]["items"] as Array).is_empty(), "老档没有建筑")
	_check(int(m["meta"]["day"]) == 12, "meta 原样保留")
	_check(int(m["state"]["gold"]) == 999, "state 原样保留")

	# 已经有 buildings 的档不许被迁移覆盖
	var v2 := {"meta": {}, "buildings": {"stage": 3, "items": [{"id": "coop"}]}}
	var m2 := SaveSystem.migrate(v2, 2)
	_check(int(m2["buildings"]["stage"]) == 3, "v2 档的 buildings 不被覆盖")

	# 真存档 → 读档：buildings 段过得去
	var g := BuildingGrid.new()
	g.stage = 2
	g.place(&"fence", Vector2i(2, 10), 1)
	var payload := {"meta": {"day": 1}, "buildings": g.to_dict()}
	var sr := SaveSystem.save(2, payload)
	_check(bool(sr["ok"]), "带建筑的档能存（%s）" % sr["error"])
	var lr := SaveSystem.load_slot(2)
	_check(bool(lr["ok"]), "带建筑的档能读")
	var back: Dictionary = lr["data"].get("buildings", {})
	var g5 := BuildingGrid.new()
	g5.from_dict(back)
	_check(g5.stage == 2, "往返后阶段还在")
	_check(g5.count() == 1, "往返后建筑还在")
	_check(not back.has("version"), "建筑段不带自己的版本号（版本只在顶层）")

# ---------------- 9. main 集成（放置 / 拆除 / 升级 / 读档）----------------

func _test_main_integration() -> void:
	print("[9] main 集成：建造模式 / 扣款 / 加成 / 存档往返")
	# 时钟与全局状态先归零：模块 8 踩过「上一个测试留下的季节让种植被拒」
	GameClock.day = 1
	GameClock.season = 0
	GameClock.year = 1
	GameClock.minutes = 0
	GameState.reset()

	var packed: PackedScene = load("res://scenes/main.tscn")
	var m := packed.instantiate()
	add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(m.get_node_or_null("World/YSortRoot/BuildRoot") != null, "场景里有 BuildRoot")
	_check(m.get_node_or_null("World/BuildCursor") != null, "场景里有 BuildCursor")
	_check(m._builds != null, "main 建了 BuildingGrid")
	_check(m._builds.farm == m._grid, "建造网格挂上了农场（不许压耕地）")
	_check(not EventBus.build_mode, "开局不在建造模式")

	# 给足钱料，把阶段抬到 5 好测所有建筑
	GameState.add_gold(100000)
	GameState.add_item(&"wood", 500)
	m._builds.stage = 5
	await get_tree().process_frame

	# 模块 10 加进来以后，_process 可能会弹剧情对话（UI 模态会挡住建造模式开关），
	# 先把对话框清空再测建造
	while m._dialogue.is_open():
		m._dialogue.skip()

	# 9.1 建造模式开关
	m._toggle_build_mode()
	_check(EventBus.build_mode, "B 进建造模式")
	_check(not m._build_catalog().is_empty(), "建造菜单非空")
	_check(m._build_toolbar_text().contains("建造"), "工具条切成建造菜单")
	m._cycle_build_pick(1)
	_check(m._build_pick == 1, "J/K 换选中项")

	# 9.2 放一栋栅栏：扣钱扣木材 + 节点生成
	var gold0 := GameState.gold
	var wood0 := GameState.count_item(&"wood")
	var fence_def: BuildingDef = BuildingDB.def_of(&"fence")
	m._player.position = Vector2(3 * 32 + 16, 11 * 32 + 16)
	m._player.facing = "up"
	await get_tree().process_frame
	_check(m._player.target_cell() == Vector2i(3, 10), "玩家面朝的格子 = (3,10)")
	m._try_place(&"fence", Vector2i(3, 10))
	_check(m._builds.count() == 1, "栅栏落地")
	_check(GameState.gold == gold0 - fence_def.price, "扣了 %dG（%d → %d）"
		% [fence_def.price, gold0, GameState.gold])
	_check(GameState.count_item(&"wood") == wood0 - fence_def.material_count,
		"扣了木材 %d" % fence_def.material_count)
	_check(m._build_nodes.has(Vector2i(3, 10)), "生成了建筑节点")
	_check(GameState.stat(GameState.ST_BUILT) == 1, "累计建造统计 = 1")

	# 9.3 重复放置被拒（钱不能白扣）
	var gold1 := GameState.gold
	m._try_place(&"fence", Vector2i(3, 10))
	_check(m._builds.count() == 1, "同一格放不了第二栋")
	_check(GameState.gold == gold1, "被拒时不扣钱")

	# 9.4 放一栋鸡舍并升级：容量加成接进 Housing
	m._try_place(&"coop", Vector2i(6, 8))
	var coop: PlacedBuilding = m._builds.building_at(Vector2i(6, 8))
	_check(coop != null, "鸡舍落地")
	_check(int(m._builds.capacity_bonus().get(&"coop", 0)) == 4, "禽舍容量 +4")
	m._try_upgrade(Vector2i(6, 8))
	_check(coop.level == 2, "鸡舍升到 Lv2")
	_check(int(m._builds.capacity_bonus().get(&"coop", 0)) == 7, "禽舍容量 +7")
	_check(Housing.capacity(GameState.barn_levels(), &"coop",
		Housing.bonus_of(m._builds.capacity_bonus(), &"coop")) \
		== HousingDB.capacity_at(&"coop", GameState.barn_level(&"coop")) + 7,
		"模块 6 的容量公式吃到了模块 9 的加成")

	# 9.5 加工坊加速 / 农贸市场加价
	m._try_place(&"workshop", Vector2i(10, 11))
	_check(m._builds.craft_speed() == 1.15, "地上有 Lv1 加工坊 → 加工快 15%")
	m._try_place(&"market", Vector2i(6, 1))
	_check(m._builds.sell_bonus() == 0.05, "地上有农贸市场 → 售价 +5%")
	var item := CropQuality.item_id(&"turnip", 0)
	GameState.add_item(item, 1)
	var base := Market.price(item, GameClock.season, GameClock.day)
	var boosted: int = m._sell_unit_price(item)
	_check(boosted >= base, "加价后不低于原价（%d → %d）" % [base, boosted])
	_check(boosted == int(round(float(base) * 1.05)), "加价 = 原价 × 1.05")

	# 9.6 拆除：返还进钱包 + 节点消失
	var before: int = m._builds.count()
	m._player.position = Vector2(3 * 32 + 16, 11 * 32 + 16)
	m._player.facing = "up"
	var g2 := GameState.gold
	m._try_demolish()
	_check(m._builds.count() == before - 1, "拆掉一栋（%d → %d）" % [before, m._builds.count()])
	_check(GameState.gold == g2 + 15, "返还 15G（栅栏 30G 的一半：%d）"
		% (GameState.gold - g2))
	_check(not m._build_nodes.has(Vector2i(3, 10)), "建筑节点被清掉")
	_check(m._builds.building_at(Vector2i(3, 10)) == null, "那格空了")

	# 9.7 阶段：只升不降
	m._builds.stage = 0
	GameState.add_gold(200000)
	GameState.bump_stat(GameState.ST_CRAFTED, 50)
	GameState.bump_stat(GameState.ST_SOLD, 500)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(m._builds.stage == 1, "指标达标但每帧只升一级 → 阶段 1（%d）" % m._builds.stage)
	_check(m._stage_metrics().has(RanchStage.M_CRAFTED), "指标快照带加工数")

	# 9.8 存档往返：建筑 + 阶段都进档
	m._builds.stage = 4
	var saved_ok: bool = m._save_game(2, true)
	_check(saved_ok, "存档成功（含 buildings 段）")
	var cnt: int = m._builds.count()
	m._builds.reset()
	m._rebuild_build_nodes()
	_check(m._builds.count() == 0, "清空后用存档恢复")
	var loaded_ok: bool = m._load_game(2)
	await get_tree().process_frame
	_check(loaded_ok, "读档成功")
	_check(m._builds.count() == cnt, "建筑数量还原（%d）" % m._builds.count())
	_check(m._builds.stage == 4, "阶段还原 = 4（%d）" % m._builds.stage)
	_check(m._build_nodes.size() == cnt, "建筑节点按存档重建（%d）" % m._build_nodes.size())
	_check(m._builds.building_at(Vector2i(6, 8)) != null, "鸡舍位置还原")
	_check(m._builds.building_at(Vector2i(6, 8)).level == 2, "鸡舍等级还原")
	_check(not EventBus.build_mode, "读档后退出建造模式")

	# 9.9 阶段早于建筑的老档：读进来不崩
	var legacy := {"version": 1, "meta": {"day": 3}, "state": {"gold": 500}}
	SaveSystem.save(3, legacy)
	var ok3: bool = m._load_game(3)
	await get_tree().process_frame
	_check(ok3, "v1 老档能读")
	_check(m._builds.count() == 0, "老档没有建筑 = 一片空地")
	_check(m._builds.stage >= 0 and m._builds.stage <= 5, "老档阶段合法（%d）" % m._builds.stage)

	m.queue_free()
	await get_tree().process_frame
	EventBus.set_build_mode(false)
	SaveSystem.save_dir = "user://saves_test9"
