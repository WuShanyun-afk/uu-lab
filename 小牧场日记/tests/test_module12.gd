extends Node
## 模块 12 验收：建筑与房屋系统（你清单里的「模块 7.5」）
##
## 需求对照：
##   ① 可建造类型（住宅 3 级 / 畜棚 / 鸡舍 / 加工坊 / 蜂箱 / 谷仓 / 温室）
##   ② 建造流程：许可证 → 网格预览 → 木/石/金 → 工期 1–3 天
##   ③ 房屋升级：Lv1 睡觉存档 / Lv2 厨房 / Lv3 地下室
##   ④ 室内场景：进出 / 家具摆放 / 睡觉存档进次日
##   ⑤ 时间联动：睡觉才推进 / 2 点不睡强制昏倒扣钱
##
## 运行： godot --headless --path <项目> res://tests/test_module12.tscn
##
## ⚠️ SaveSystem.save_dir 指到 user://saves_test12，不碰玩家真存档。

var _fails: Array[String] = []
var _n := 0

func _check(cond: bool, label: String) -> void:
	_n += 1
	if not cond:
		_fails.append(label)
	print(("  [OK] " if cond else "  [FAIL] ") + label)

func _ready() -> void:
	print("=== 模块 12 验收：建筑与房屋系统 ===")
	SaveSystem.save_dir = "user://saves_test12"
	_clean_saves()
	SceneRouter.suppress_scene_change = true
	_test_building_data()
	_test_construction_logic()
	_test_settlement_bonus()
	_test_house_data()
	_test_collapse()
	await _test_house_room()
	await _test_main_integration()
	SceneRouter.suppress_scene_change = false
	SceneRouter.reset_session()
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

# ============================================================================
# 1. 建筑数据结构（要求输出第一项）
# ============================================================================

func _test_building_data() -> void:
	print("[1] 建筑表：石头 / 工期两列 + 谷仓 / 温室新分类")
	for id in [&"coop", &"barn", &"workshop", &"hive", &"granary", &"greenhouse"]:
		_check(BuildingDB.has(id), "表里有 %s" % String(id))
	var granary: BuildingDef = BuildingDB.def_of(&"granary")
	_check(granary != null, "谷仓 def 能取到")
	_check(granary.category == BuildingDef.CAT_STORAGE, "谷仓分类 = storage")
	_check(granary.stone_count == 6, "谷仓要石头 6（%d）" % granary.stone_count)
	_check(granary.build_days == 2, "谷仓工期 2 天（%d）" % granary.build_days)
	_check(granary.price == 1800, "谷仓 1800G")
	var gh: BuildingDef = BuildingDB.def_of(&"greenhouse")
	_check(gh.category == BuildingDef.CAT_GREENHOUSE, "温室分类 = greenhouse")
	_check(gh.build_days == 3, "温室工期 3 天")
	_check(gh.max_level == 1, "温室只有 1 级")

	var barn: BuildingDef = BuildingDB.def_of(&"barn")
	_check(barn.stone_count == 4, "畜棚要石头 4")
	_check(barn.build_days == 2, "畜棚工期 2 天")
	_check(barn.cost_text().contains("石头"), "造价文案带石头（%s）" % barn.cost_text())
	var fence: BuildingDef = BuildingDB.def_of(&"fence")
	_check(fence.stone_count == 0, "栅栏不要石头")
	_check(fence.build_days == 0, "栅栏当场落成（工期 0）")
	_check(not fence.cost_text().contains("石头"), "栅栏造价文案不带石头")

	# 菜单里能看到的类型
	var menu := BuildingDB.buildable_ids()
	_check(menu.has(&"granary") and menu.has(&"greenhouse"), "菜单里有谷仓和温室")
	_check(menu.size() == 9, "菜单 9 种建筑（%d）" % menu.size())
	_check(BuildingDB.ids_unlocked_at(2).has(&"granary"), "第 2 阶段解锁谷仓")
	_check(BuildingDB.ids_unlocked_at(3).has(&"greenhouse"), "第 3 阶段解锁温室")

	# 新物品（建材 / 许可证 / 家常菜 / 家具）
	for id in [&"permit", &"stone", &"home_cooked", &"rug", &"plant"]:
		_check(ItemDB.display_name(id) != str(id), "物品表里有 %s（%s）" % [String(id),
			ItemDB.display_name(id)])
	_check(ProductDB.price(&"stone") > 0, "石头有价格（%d）" % ProductDB.price(&"stone"))

# ============================================================================
# 2. 施工队列纯逻辑（需求 2）
# ============================================================================

func _test_construction_logic() -> void:
	print("[2] 施工队列：开工 / 工期 / 竣工 / 占位")
	var c := Construction.new()
	_check(c.is_empty(), "开局没有工地")
	_check(not c.blocks(Vector2i(5, 5)), "空队列不占地")

	c.start(&"coop", Vector2i(4, 4), 2, 10)
	_check(c.count() == 1, "开工 1 个工地")
	_check(c.blocks(Vector2i(4, 4)), "锚点格被占")
	_check(c.blocks(Vector2i(6, 5)), "3×2 的 footprint 右下角也被占")
	_check(not c.blocks(Vector2i(9, 9)), "footprint 外不受影响")
	var s := c.site_at(Vector2i(5, 4))
	_check(not s.is_empty(), "site_at 能找到工地")
	_check(int(s["days_left"]) == 2, "剩 2 天")
	_check(int(s["day_started"]) == 10, "记了开工日")
	_check(c.summary_text().contains("鸡舍"), "摘要带建筑名（%s）" % c.summary_text())

	var done := c.tick_day()
	_check(done.is_empty(), "第 1 天没竣工")
	_check(int((c.sites)[0]["days_left"]) == 1, "剩 1 天")
	done = c.tick_day()
	_check(done.size() == 1, "第 2 天竣工")
	_check(StringName(str(done[0]["def_id"])) == &"coop", "竣工的是鸡舍")
	_check(c.is_empty(), "竣工后队列清空")
	_check(not c.blocks(Vector2i(4, 4)), "竣工后不再占地")

	# 存档往返
	var c2 := Construction.new()
	c2.start(&"barn", Vector2i(10, 4), 3, 2)
	var raw := JSON.stringify(SaveSystem.jsonify(c2.to_dict()))
	var back: Dictionary = JSON.parse_string(raw)
	var c3 := Construction.new()
	c3.from_dict(back)
	_check(c3.count() == 1, "工地存档往返")
	_check(int((c3.sites)[0]["days_left"]) == 3, "工期往返")
	_check(StringName(str((c3.sites)[0]["def_id"])) == &"barn", "建筑 id 往返")
	# 脏数据：表里不存在的建筑直接丢
	var c4 := Construction.new()
	c4.from_dict({"sites": [{"def_id": "不存在的建筑", "x": 1, "y": 1}]})
	_check(c4.count() == 0, "不认识的建筑被丢掉")

	# 网格判定：施工中的格子不能再放东西
	var g := BuildingGrid.new()
	g.stage = 5
	g.sites = c2
	_check(g.can_place(&"fence", Vector2i(10, 4)) == BuildingGrid.SITE,
		"压着工地 → SITE")
	_check(not g.reason_text(BuildingGrid.SITE).contains("_"), "SITE 的原因是人话：%s"
		% g.reason_text(BuildingGrid.SITE))

# ============================================================================
# 3. 谷仓 / 温室的实际效果
# ============================================================================

func _test_settlement_bonus() -> void:
	print("[3] 谷仓 → 背包格 / 温室 → 反季种植")
	GameState.reset()
	var base := GameState.slot_capacity()
	_check(base == 40, "初始 40 格")
	GameState.set_bonus_slots(8)
	_check(GameState.slot_capacity() == 48, "谷仓 Lv1 → +8 格（%d）" % GameState.slot_capacity())
	GameState.set_bonus_slots(16)
	_check(GameState.slot_capacity() == 56, "谷仓 Lv2 → +16 格")
	GameState.set_bonus_slots(0)
	_check(GameState.slot_capacity() == 40, "拆了谷仓回到 40 格")
	_check(GameState.slots.size() == 40, "槽位数组跟着缩回来（%d）" % GameState.slots.size())

	# 温室效果在 main 里落到 FarmGrid.season（-1 = 不限制）
	var grid := FarmGrid.new()
	grid.season = 0
	_check(not grid.plant(Vector2i(1, 1), &"turnip"), "没耕地不能种（前提）")
	grid.till(Vector2i(1, 1))
	grid.season = 0
	_check(grid.plant(Vector2i(1, 1), &"turnip"), "春天能种芜菁")
	grid.till(Vector2i(2, 1))
	grid.season = 0
	_check(not grid.plant(Vector2i(2, 1), &"pumpkin"), "春天种不了南瓜（前提）")
	grid.till(Vector2i(3, 1))
	grid.season = -1
	_check(grid.plant(Vector2i(3, 1), &"pumpkin"), "温室（season = -1）能反季种南瓜")

# ============================================================================
# 4. 住宅等级表（需求 3）
# ============================================================================

func _test_house_data() -> void:
	print("[4] 住宅等级：3 级 / 成本 / 功能解锁")
	_check(HouseDB.MAX_LEVEL == 3, "最高 3 级")
	_check(HouseDB.levels.size() == 3, "表里 3 级（%d）" % HouseDB.levels.size())
	_check(HouseDB.name_of(1) == "小木屋", "Lv1 = 小木屋")
	_check(HouseDB.name_of(2).contains("厨房"), "Lv2 带厨房（%s）" % HouseDB.name_of(2))
	_check(HouseDB.name_of(3).contains("地下室"), "Lv3 带地下室（%s）" % HouseDB.name_of(3))
	_check(HouseDB.features_text(1).contains("睡觉"), "Lv1 能睡觉")
	_check(not HouseDB.features_text(1).contains("做饭"), "Lv1 还不能做饭")
	_check(HouseDB.features_text(2).contains("做饭"), "Lv2 解锁做饭")
	_check(not HouseDB.features_text(2).contains("酿酒"), "Lv2 还不能酿酒")
	_check(HouseDB.features_text(3).contains("酿酒"), "Lv3 解锁酿酒")

	var c1 := HouseDB.upgrade_cost(1)
	_check(not c1.is_empty(), "Lv1 能升级")
	_check(int(c1["to"]) == 2, "升到 Lv2")
	_check(int(c1["days"]) == 2, "工期 2 天")
	_check(int(c1["gold"]) == 2500, "要 2500G")
	_check(int(c1["stone"]) == 8, "要石头 8")
	var c3 := HouseDB.upgrade_cost(3)
	_check(c3.is_empty(), "满级没有升级成本")
	_check(not HouseDB.can_upgrade(3), "满级 can_upgrade = false")
	_check(HouseDB.can_upgrade(2), "Lv2 还能升")

	# 等级进存档
	GameState.reset()
	_check(GameState.house_level == 1, "开局 Lv1")
	GameState.set_house_level(3)
	var d := GameState.to_dict()
	_check(int(d["house_level"]) == 3, "存档带住宅等级")
	GameState.set_house_level(1)
	GameState.from_dict(d)
	_check(GameState.house_level == 3, "读档还原住宅等级")
	GameState.reset()

# ============================================================================
# 5. 时间联动：2 点不睡强制昏倒（需求 5）
# ============================================================================

func _test_collapse() -> void:
	print("[5] 昏倒：2:00 不睡 → 扣钱 + 起得晚")
	GameState.reset()
	GameState.gold = 1000
	EventBus.forced_sleep.emit()
	_check(GameState.gold == 1000 - DayCycle.COLLAPSE_FEE, "昏倒扣 %dG（剩 %d）" % [
		DayCycle.COLLAPSE_FEE, GameState.gold])
	_check(DayCycle.last_message.contains("睡着"), "有提示文案（%s）" % DayCycle.last_message)
	_check(GameClock.minutes == DayCycle.COLLAPSE_DELAY, "昏倒的人起得晚（minutes=%d）"
		% GameClock.minutes)
	# 钱不够时扣到 0，不会变成负数
	GameState.gold = 30
	EventBus.forced_sleep.emit()
	_check(GameState.gold == 0, "钱不够就扣到 0（%d）" % GameState.gold)
	GameState.reset()
	GameClock.minutes = 0

# ============================================================================
# 6. 室内场景：道具随等级 / 睡觉 / 做饭 / 酿酒 / 家具（需求 3 / 4）
# ============================================================================

func _test_house_room() -> void:
	print("[6] 室内场景：道具按等级 / 睡觉推进 / 厨房 / 地窖 / 家具")
	SceneRouter.reset_session()
	SceneRouter.current_id = &"house"
	GameState.reset()
	GameState.house_level = 1
	var packed: PackedScene = load("res://scenes/house.tscn")
	var room := packed.instantiate()
	add_child(room)
	await get_tree().process_frame

	var count1 := _count_props(room)
	_check(count1 == 3, "Lv1 屋内 3 个道具（床/存档柜/工作台）：%d" % count1)
	_check(_has_action(room, &"cook") == false, "Lv1 没有灶台")
	_check(_has_action(room, &"brew") == false, "Lv1 没有地窖门")

	# 升到 2 级 → 多灶台
	GameState.house_level = 2
	room._rebuild_house_props()
	await get_tree().process_frame
	_check(_count_props(room) == 4, "Lv2 多一个灶台（%d）" % _count_props(room))
	_check(_has_action(room, &"cook"), "Lv2 有灶台")
	# 升到 3 级 → 再多地窖
	GameState.house_level = 3
	room._rebuild_house_props()
	await get_tree().process_frame
	_check(_count_props(room) == 5, "Lv3 再多一个地窖门（%d）" % _count_props(room))

	# 做饭：需要牛奶 + 鸡蛋
	GameState.house_level = 2
	GameState.remove_item(&"milk", 99)
	GameState.remove_item(&"egg", 99)
	room._cook()
	_check(GameState.count_item(&"home_cooked") == 0, "没原料做不了饭")
	GameState.add_item(&"milk", 1)
	GameState.add_item(&"egg", 1)
	room._cook()
	_check(GameState.count_item(&"home_cooked") == 1, "做饭产出家常菜")
	_check(GameState.count_item(&"milk") == 0, "牛奶被消耗")
	_check(GameState.has_buff(&"warm_meal", GameClock.day), "热饭菜 buff 生效")
	room._cook()
	_check(GameState.count_item(&"home_cooked") == 1, "一天只能做一次")

	# 酿酒：需要蜂蜜 ×2
	GameState.house_level = 3
	GameState.remove_item(&"mead", 99)
	GameState.remove_item(&"honey", 99)
	room._brew()
	_check(GameState.count_item(&"mead") == 0, "没蜂蜜酿不了酒")
	GameState.add_item(&"honey", 2)
	room._brew()
	_check(GameState.count_item(&"mead") == 1, "酿酒产出蜂蜜酒")
	_check(GameState.count_item(&"honey") == 0, "蜂蜜被消耗")
	room._brew()
	_check(GameState.count_item(&"mead") == 1, "一天只能酿一次")

	# 睡觉：推进到次日 + 自动存档
	GameClock.day = 5
	GameClock.minutes = 900
	GameState.house_level = 1
	_clean_saves()
	room._sleep()
	_check(GameClock.day == 6, "睡一觉到第 6 天（%d）" % GameClock.day)
	_check(GameClock.minutes == 0, "醒来是清晨")
	_check(SaveSystem.exists(SaveSystem.SLOT_AUTO), "睡觉自动存档（0 号槽）")
	var info := SaveSystem.info(SaveSystem.SLOT_AUTO)
	_check(int(info["day"]) == 6, "自动档记的是新的一天（第 %d 天）" % int(info["day"]))
	_check(str(info["scene"]) == "house", "档里记着「在屋内」（%s）" % info["scene_name"])

	# 家具：F 摆 / F 收
	GameState.furniture.clear()
	GameState.add_item(&"rug", 1)
	room._player.global_position = Vector2(320, 200)
	room._player.position = Vector2(320, 200)
	room._furniture_action()
	_check(GameState.furniture_count() == 1, "摆下 1 件家具")
	_check(GameState.count_item(&"rug") == 0, "背包里少了一件")
	room._furniture_action()
	_check(GameState.furniture_count() == 0, "再按一次收回家具")
	_check(GameState.count_item(&"rug") == 1, "家具回到背包")
	# 家具进存档
	GameState.add_furniture(&"plant", Vector2i(3, 4))
	var fd := GameState.to_dict()
	GameState.furniture.clear()
	GameState.from_dict(fd)
	_check(GameState.furniture_count() == 1, "家具进存档")
	_check(GameState.furniture_at(Vector2i(3, 4)) == &"plant", "家具坐标往返")

	room.queue_free()
	await get_tree().process_frame
	GameState.reset()

func _count_props(room: Node) -> int:
	var n := 0
	for c in room.get_children():
		if c is RoomProp:
			n += 1
	return n

func _has_action(room: Node, action: StringName) -> bool:
	for c in room.get_children():
		if c is RoomProp and (c as RoomProp).action == action:
			return true
	return false

# ============================================================================
# 7. main 集成：许可证 / 石头 / 工期 / 住宅升级 / 回场补结算
# ============================================================================

func _test_main_integration() -> void:
	print("[7] main 集成：建造许可证 / 石头 / 工期 / 补结算")
	GameClock.day = 1
	GameClock.season = 0
	GameClock.year = 1
	GameClock.minutes = 0
	GameState.reset()
	SceneRouter.reset_session()

	var packed: PackedScene = load("res://scenes/main.tscn")
	var m := packed.instantiate()
	add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame

	GameState.add_gold(100000)
	GameState.add_item(&"wood", 500)
	GameState.add_item(&"stone", 200)
	m._builds.stage = 5
	m._refresh_build_effects()

	# 7.1 没有许可证 → 放不下
	m._try_place(&"fence", Vector2i(3, 10))
	_check(m._builds.count() == 0, "没许可证放不下")
	_check(m._sites.is_empty(), "没许可证也不开工")

	# 7.2 有证没石头 → 放不下（畜棚要石头 4）
	GameState.add_item(&"permit", 10)
	var stone_before := GameState.count_item(&"stone")
	var gold_before := GameState.gold
	m._try_place(&"coop", Vector2i(4, 3))
	_check(m._sites.count() == 1, "鸡舍开工（工地 1 个）")
	_check(GameState.count_item(&"permit") == 9, "扣了 1 张许可证")
	_check(GameState.count_item(&"stone") == stone_before - 2, "扣了石头 2")
	_check(GameState.gold == gold_before - 900, "扣了 900G")
	_check(m._builds.count() == 0, "施工期间地上还没有这栋建筑")
	# 施工中同一块地不能再放
	_check(m._builds.can_place(&"fence", Vector2i(4, 3)) == BuildingGrid.SITE,
		"施工中的格子不能再放东西")

	# 7.3 工期：第 1 天没竣工，第 2 天竣工
	m._tick_construction()
	await get_tree().process_frame
	_check(m._builds.count() == 0, "第 1 天还没竣工")
	_check(int(m._sites.sites[0]["days_left"]) == 1, "还剩 1 天")
	m._tick_construction()
	await get_tree().process_frame
	_check(m._sites.is_empty(), "第 2 天工地清空")
	_check(m._builds.count() == 1, "鸡舍落成")
	_check(m._builds.has_building(&"coop"), "落成的确实是鸡舍")
	_check(m._build_nodes.has(Vector2i(4, 3)), "建筑节点生成了")
	_check(not m._site_nodes.has(Vector2i(4, 3)), "脚手架节点没了")

	# 7.4 谷仓 → 背包格；温室 → 反季
	var slots_before := GameState.slot_capacity()
	m._build_now(&"granary", Vector2i(5, 8), 1)
	_check(GameState.slot_capacity() == slots_before + 8, "谷仓 Lv1 → 背包 +8 格（%d → %d）"
		% [slots_before, GameState.slot_capacity()])
	m._build_now(&"greenhouse", Vector2i(1, 10), 1)
	_check(m._grid.season == -1, "温室建成 → 农场不再限制季节（season=%d）" % m._grid.season)
	m._grid.till(Vector2i(6, 1))
	_check(m._grid.plant(Vector2i(6, 1), &"pumpkin"), "温室里春天能种南瓜")

	# 7.5 住宅升级：扣钱料 → 进工期 → 跨日推进 → 等级 +1
	GameState.house_level = 1
	GameState.house_upgrade_target = 0
	GameState.house_upgrade_days = 0
	GameState.add_item(&"stone", 50)
	GameState.add_item(&"wood", 60)
	var cost := HouseDB.upgrade_cost(1)
	var gold1 := GameState.gold
	GameState.spend_gold(int(cost["gold"]))
	GameState.remove_item(&"wood", int(cost["wood"]))
	GameState.remove_item(&"stone", int(cost["stone"]))
	GameState.house_upgrade_target = 2
	GameState.house_upgrade_days = 2
	_check(GameState.gold == gold1 - 2500, "住宅升级扣 2500G")
	# 跨日两次 → 升级完成
	EventBus.day_advanced.emit(GameClock.day, GameClock.season, GameClock.year)
	_check(GameState.house_upgrade_days == 1, "跨 1 天后还剩 1 天")
	_check(GameState.house_level == 1, "还没升完")
	EventBus.day_advanced.emit(GameClock.day, GameClock.season, GameClock.year)
	_check(GameState.house_level == 2, "跨 2 天后升到 Lv2（%d）" % GameState.house_level)
	_check(GameState.house_upgrade_days == 0, "工期清零")

	# 7.6 回场补结算：在屋里睡掉的天数，牧场要补
	var before_day := GameClock.day
	m._catch_up_days({"clock": {"day": before_day - 2, "season": GameClock.season}})
	_check(GameClock.day == before_day, "补结算不会额外改天数")
	_check(m._tip.text.contains("补上"), "有补结算提示（%s）" % m._tip.text)

	# 7.7 施工队列进存档
	m._try_place(&"barn", Vector2i(16, 11))
	_check(m._sites.count() == 1, "畜棚开工")
	_check(m._save_game(2, true), "带工地的存档写成功")
	var saved_sites: int = m._sites.count()
	m._sites.reset()
	_check(m._load_game(2), "读档成功")
	await get_tree().process_frame
	_check(m._sites.count() == saved_sites, "工地进度还原（%d）" % m._sites.count())
	_check(m._site_nodes.size() == saved_sites, "脚手架节点重建（%d）" % m._site_nodes.size())

	m.queue_free()
	await get_tree().process_frame
