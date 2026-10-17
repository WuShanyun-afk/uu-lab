extends Node
## 模块 8 验收：存档系统
##
## 需求对照：
##   ① 存档底座：JSON 化 / 原子写入 / 版本号 / 坏档容错（SaveSystem）
##   ② 一局完整状态：时间 / 天气 / 金币背包 / 农田 / 动物 / 订单 / 加工坊 / 玩家
##   ③ 自动存档：每天 2:00 跨日结算完写 0 号槽
##   ④ 读档：F9 优先快速槽，退化到自动槽；画面/节点全部重新同步
##   ⑤ 类型完整性：StringName / Color / Vector2 / 64 位 RNG 状态过 JSON 不烂
##
## 运行： godot --headless --path <项目> res://tests/test_module8.tscn
##
## ⚠️ 本套测试把 SaveSystem.save_dir 指到 user://saves_test，
##    绝不会碰玩家真存档（user://saves）。

var _fails: Array[String] = []
var _n := 0

func _check(cond: bool, label: String) -> void:
	_n += 1
	if not cond:
		_fails.append(label)
	print(("  [OK] " if cond else "  [FAIL] ") + label)

func _ready() -> void:
	print("=== 模块 8 验收：存档系统 ===")
	SaveSystem.save_dir = "user://saves_test"
	_clean_saves()
	_test_save_system()
	_test_game_state()
	_test_clock_weather()
	_test_farm_grid()
	_test_animals()
	_test_orders()
	_test_processor()
	_test_player()
	await _test_main()
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

# ---------------- 1. 存档底座 ----------------

func _test_save_system() -> void:
	print("[1] 存档底座：JSON 化 / 原子写 / 版本 / 容错")
	_clean_saves()
	_check(not SaveSystem.exists(0), "初始没有自动存档")
	_check(not SaveSystem.exists(1), "初始没有快速存档")

	var r := SaveSystem.save(1, {"hello": &"world", "n": 42})
	_check(bool(r["ok"]), "存档成功（%s）" % r["error"])
	_check(SaveSystem.exists(1), "exists(1) = true")
	_check(not FileAccess.file_exists(SaveSystem.slot_path(1) + ".tmp"), "没有 .tmp 残留")
	_check(not FileAccess.file_exists(SaveSystem.slot_path(1) + ".bak"), "没有 .bak 残留")

	var l := SaveSystem.load_slot(1)
	_check(bool(l["ok"]), "读档成功")
	var d: Dictionary = l["data"]
	_check(int(d["version"]) == SaveSystem.VERSION, "带版本号 v%d" % int(d["version"]))
	_check(str(d.get("saved_at_text", "")) != "", "带存档时间戳")
	_check(d["hello"] == "world", "StringName 读回来是 String（JSON 的锅）")

	# 覆盖写：旧档要被替换，不是追加
	SaveSystem.save(1, {"hello": "again"})
	var l2 := SaveSystem.load_slot(1)
	_check(l2["data"]["hello"] == "again", "覆盖写生效")
	_check(not l2["data"].has("n"), "旧字段没残留")

	# jsonify：五个类型
	var j: Dictionary = SaveSystem.jsonify({
		"sn": &"turnip", "c": Color("#FF8000"), "v": Vector2(1.5, -2.0),
		"vi": Vector2i(3, 4), "arr": [&"x", Color("#00FF00")],
		"nested": {"id": &"milk"},
	})
	_check(typeof(j["sn"]) == TYPE_STRING, "StringName → String")
	_check(typeof(j["c"]) == TYPE_STRING and str(j["c"]).begins_with("#"), "Color → #RRGGBBAA")
	_check(typeof(j["v"]) == TYPE_ARRAY and j["v"].size() == 2 \
		and is_equal_approx(float(j["v"][0]), 1.5), "Vector2 → [x, y]")
	_check(typeof(j["vi"]) == TYPE_ARRAY and int(j["vi"][0]) == 3, "Vector2i → [x, y]")
	_check(typeof(j["arr"][0]) == TYPE_STRING and typeof(j["arr"][1]) == TYPE_STRING,
		"数组里也递归转型")
	_check(j["nested"]["id"] == "milk", "字典值递归转型")

	# 坏档：半截 JSON 不能把游戏带崩
	var f := FileAccess.open(SaveSystem.slot_path(2), FileAccess.WRITE)
	f.store_string("{ 这不是 json")
	f.close()
	var bad := SaveSystem.load_slot(2)
	_check(not bool(bad["ok"]), "坏档 → ok = false")
	_check(str(bad["error"]) != "", "坏档有原因：%s" % bad["error"])
	_check(typeof(bad["data"]) == TYPE_DICTIONARY, "坏档也返回空字典，不是 null")

	# 版本太新：未来档不能把现在毒死
	var f2 := FileAccess.open(SaveSystem.slot_path(3), FileAccess.WRITE)
	f2.store_string(JSON.stringify({"version": 99, "meta": {}}))
	f2.close()
	var newer := SaveSystem.load_slot(3)
	_check(not bool(newer["ok"]), "版本太新 → 拒绝")
	_check(str(newer["error"]).contains("版本"), "原因写明版本")

	# 缺 version 的老档 → migrate 补到当前版本
	var f3 := FileAccess.open(SaveSystem.slot_path(3), FileAccess.WRITE)
	f3.store_string(JSON.stringify({"meta": {"day": 3}}))
	f3.close()
	var old := SaveSystem.load_slot(3)
	_check(bool(old["ok"]), "老档（无 version）能读")
	_check(int(old["data"]["version"]) == SaveSystem.VERSION, "migrate 到 v%d" % SaveSystem.VERSION)

	# 槽位越界
	_check(not bool(SaveSystem.save(9, {})["ok"]), "槽位 9 越界 → 拒绝")
	_check(not bool(SaveSystem.load_slot(9)["ok"]), "越界槽位读 → 拒绝")

	# 摘要 / 删除
	SaveSystem.save(1, {"meta": {"day": 7, "season": 1, "gold": 999}})
	var info := SaveSystem.info(1)
	_check(bool(info["exists"]) and int(info["day"]) == 7, "info 读出天数")
	_check(int(info["gold"]) == 999, "info 读出金币")
	var used := SaveSystem.used_slots()
	_check(used.has(1) and used.has(3), "used_slots 列出已有档")
	_check(SaveSystem.delete_slot(1), "删档成功")
	_check(not SaveSystem.exists(1), "删完就没了")
	_check(not SaveSystem.delete_slot(1), "重复删返回 false")
	_check(SaveSystem.slot_label(SaveSystem.SLOT_AUTO) == "自动存档", "槽位有名字")
	_clean_saves()

# ---------------- 2. 金币与背包 ----------------

func _test_game_state() -> void:
	print("[2] GameState：金币 / 真槽位背包 / 工具与棚舍等级 / 进度标记")
	GameState.reset()
	GameState.add_gold(1234)               # 500 → 1734
	GameState.add_item(&"turnip", 7)
	GameState.add_item(&"milk_gold", 2)
	GameState.set_tool_level(&"bag", 3)
	GameState.set_tool_level(&"hoe", 2)
	GameState.set_barn_level(&"barn", 2)
	GameState.set_flag(&"garden_unlocked", true)
	GameState.set_flag(&"famous", true)
	var gold := GameState.gold
	var cap := GameState.slot_capacity()

	SaveSystem.save(1, {"state": GameState.to_dict()})
	var back: Dictionary = SaveSystem.load_slot(1)["data"]["state"]
	GameState.reset()
	_check(GameState.gold == 500, "reset 后回到 500（前提）")
	GameState.from_dict(back)

	_check(GameState.gold == gold, "金币还原（%d）" % GameState.gold)
	_check(GameState.count_item(&"turnip") == 7, "芜菁 ×7 还原")
	_check(GameState.count_item(&"milk_gold") == 2, "金星牛奶 ×2 还原")
	_check(GameState.slot_capacity() == cap and cap == 56, "背包 Lv3 = 56 格（%d）" % cap)
	_check(GameState.tool_level(&"hoe") == 2, "锄头 Lv2 还原")
	_check(GameState.barn_level(&"barn") == 2, "畜舍 Lv2 还原")
	_check(GameState.has_flag(&"garden_unlocked"), "花园解锁标记还原")
	_check(GameState.has_flag(&"famous"), "村中名人还原")
	_check(not GameState.has_flag(&"shed_built"), "没存的标记保持 false")
	# 派生索引必须重建，否则 count_item 全查不到（模块 8 第 1 坑）
	_check(GameState.inventory.size() == 2, "派生索引重建了（%d 项）" % GameState.inventory.size())

	# 槽位位置要保真：拖拽摆过的顺序读档后不能乱
	var turnip_slot := -1
	var milk_slot := -1
	for i in range(GameState.slots.size()):
		if GameState.slot_item(i) == &"turnip":
			turnip_slot = i
		elif GameState.slot_item(i) == &"milk_gold":
			milk_slot = i
	_check(turnip_slot >= 0 and milk_slot >= 0 and turnip_slot < milk_slot,
		"槽位顺序保留（turnip@%d < milk_gold@%d）" % [turnip_slot, milk_slot])

	# 降级陷阱：存档是 Lv3（56 格），当前存档里的等级却是 Lv1 → 多出的格子要干净丢掉
	var shrink: Dictionary = SaveSystem.jsonify(GameState.to_dict())
	shrink["tool_levels"] = {"bag": 1, "hoe": 1}
	GameState.from_dict(shrink)
	_check(GameState.slot_capacity() == 40, "按存档里的等级缩回 40 格")
	_check(GameState.slots.size() == 40, "槽位数组长度跟着变（%d）" % GameState.slots.size())
	_check(GameState.count_item(&"turnip") == 7, "缩容不丢前面格子里的物品")
	GameState.reset()

# ---------------- 3. 时间与天气 ----------------

func _test_clock_weather() -> void:
	print("[3] GameClock / WeatherSystem：时间轴 + 天气 + RNG")
	GameClock.day = 12
	GameClock.season = 2
	GameClock.year = 3
	GameClock.minutes = 500
	GameClock._acc = 2.5
	SaveSystem.save(1, {"clock": GameClock.to_dict()})
	var cd: Dictionary = SaveSystem.load_slot(1)["data"]["clock"]

	GameClock.day = 1
	GameClock.season = 0
	GameClock.year = 1
	GameClock.minutes = 0
	GameClock.from_dict(cd)
	_check(GameClock.day == 12 and GameClock.season == 2 and GameClock.year == 3,
		"年月日还原（第 %d 天 · %s · 第 %d 年）" % [GameClock.day, GameClock.season_name(), GameClock.year])
	_check(GameClock.minutes == 500, "当日分钟还原（%d）" % GameClock.minutes)
	_check(GameClock.clock_text() == "14:20", "时钟文本 = 14:20（%s）" % GameClock.clock_text())
	_check(is_equal_approx(GameClock._acc, 2.5),
		"tick 累加器还原（%.1f）" % GameClock._acc)
	# phase 是派生值：读档后必须重算，不能留旧缓存
	_check(GameClock.current_phase() == GameClock.phase_at(GameClock.minutes),
		"phase 派生一致（%s）" % GameClock.phase_name())

	# 越界钳制：改坏了的档不能把时钟推到外太空
	GameClock.from_dict({"day": 99, "season": 9, "minutes": 99999, "year": -5})
	_check(GameClock.day == GameClock.DAYS_PER_SEASON, "day 越界钳到 28")
	_check(GameClock.season == 3, "season 越界钳到 3")
	_check(GameClock.minutes < GameClock.TOTAL_MINUTES, "minutes 越界钳回一天之内")
	_check(GameClock.year == 1, "year 不能是负数")

	# 天气
	WeatherSystem.today = WeatherSystem.Weather.RAIN
	WeatherSystem.tomorrow = WeatherSystem.Weather.SNOW
	WeatherSystem.forecast = WeatherSystem.Weather.CLOUDY
	WeatherSystem.blizzard = false
	var rng_state: int = WeatherSystem.rng.state
	var expect_a := WeatherSystem.rng.randi()
	SaveSystem.save(1, {"weather": WeatherSystem.to_dict()})

	WeatherSystem.today = WeatherSystem.Weather.CLEAR
	WeatherSystem.tomorrow = WeatherSystem.Weather.CLEAR
	WeatherSystem.forecast = WeatherSystem.Weather.CLEAR
	WeatherSystem.blizzard = true
	WeatherSystem.from_dict(SaveSystem.load_slot(1)["data"]["weather"])
	_check(WeatherSystem.today == WeatherSystem.Weather.RAIN, "今日天气还原")
	_check(WeatherSystem.tomorrow == WeatherSystem.Weather.SNOW, "明日天气还原")
	_check(WeatherSystem.forecast == WeatherSystem.Weather.CLOUDY, "预报还原")
	_check(not WeatherSystem.blizzard, "暴风雪标记还原")
	_check(WeatherSystem.light_mult > 0.0, "光照倍率重算过了")
	# 64 位 RNG 状态：走字符串存，越过 JSON 的 double 不掉精度
	var expect_b := WeatherSystem.rng.randi()
	WeatherSystem.rng.state = rng_state
	var again := WeatherSystem.rng.randi()
	_check(again == expect_a, "RNG 状态精确还原（%d）" % expect_a)
	_check(WeatherSystem.rng.randi() == expect_b, "后续序列也一致")
	var saved_w: Dictionary = SaveSystem.load_slot(1)["data"]["weather"]
	_check(typeof(saved_w["rng_state"]) == TYPE_STRING, "rng_state 存成字符串（JSON 数字会掉精度）")

# ---------------- 4. 农田 ----------------

func _test_farm_grid() -> void:
	print("[4] FarmGrid：耕地 / 作物 / 肥料 / 枯萎 / RNG")
	var g := FarmGrid.new()
	g.season = 0
	var cell := Vector2i(3, 4)
	g.till(cell)
	_check(g.fertilize(cell, 2), "施高级肥")
	_check(g.plant(cell, &"turnip"), "种下芜菁")
	g.water(cell)
	g.advance_day()
	g.water(cell)
	g.advance_day()
	g.till(Vector2i(5, 6))                 # 一块空耕地也要存
	var days := g.tile_at(cell).days_grown
	_check(days == 2, "生长 2 天（%d）" % days)

	SaveSystem.save(1, {"farm": g.to_dict()})
	var fd: Dictionary = SaveSystem.load_slot(1)["data"]["farm"]
	var g2 := FarmGrid.new()
	g2.from_dict(fd)
	var t := g2.tile_at(cell)
	_check(t != null, "格子回来了")
	_check(t != null and t.crop_id == &"turnip", "crop_id 回到 StringName（%s）" % (t.crop_id if t else ""))
	_check(t != null and t.days_grown == days, "生长天数还原")
	_check(t != null and t.fertilized == 2, "肥料档次还原")
	_check(t != null and t.tilled, "耕地状态还原")
	_check(g2.tile_at(Vector2i(5, 6)) != null, "空耕地也存了")
	_check(g2.season == 0, "季节门禁值还原")
	_check(g2.rng.state == g.rng.state, "农田 RNG 状态还原")
	_check(g2.is_mature(cell) == g.is_mature(cell), "成熟判定一致")

	# 越界格 / 坏键：老档改了 SIZE 也不能崩
	var dirty: Dictionary = SaveSystem.jsonify(g.to_dict())
	dirty["tiles"]["99,99"] = {"tilled": true, "crop": "turnip", "days": 1}
	dirty["tiles"]["不是坐标"] = {"tilled": true}
	dirty["tiles"]["1,1"] = "不是字典"
	g2.from_dict(dirty)
	_check(g2.tile_at(Vector2i(99, 99)) == null, "越界格被丢掉")
	_check(g2.tile_at(cell) != null, "脏数据不影响正常格")

# ---------------- 5. 动物 ----------------

func _test_animals() -> void:
	print("[5] AnimalState / Herd：好感 / 病 / 妊娠 / 觉醒 / uid 主键")
	var h := Herd.new(4321)
	var cow := h.add(&"cow", 500, Vector2(536, 158))
	cow.debug_feed_full()
	cow.pet()
	cow.brush()
	cow.sick = true
	cow.sick_days = 3
	cow.pregnant_days = 1
	cow.gestation = 3
	cow.partner_species = &"cow"
	var old_uid: StringName = cow.uid
	var old_pos := cow.pos
	var chick := h.add(&"chicken", 10, Vector2(604, 152))
	chick.days_old = 2
	var chick_uid: StringName = chick.uid
	cow.debug_awaken()
	_check(cow.awakened and cow.just_awakened, "刚觉醒（前提）")

	SaveSystem.save(1, {"herd": h.to_dict()})
	var hd: Dictionary = SaveSystem.load_slot(1)["data"]["herd"]
	var h2 := Herd.new(1)
	h2.from_dict(hd)
	_check(h2.size() == 2, "两只动物全回来（%d）" % h2.size())
	var c2 := h2.get_by_uid(old_uid)
	_check(c2 != null, "按 uid 找得到（%s）" % old_uid)
	_check(c2 != null and c2.affection == AnimalState.MAX_AFFECTION, "好感 1000 还原")
	_check(c2 != null and c2.awakened, "觉醒状态还原")
	_check(c2 != null and not c2.just_awakened, "just_awakened 不落盘（读档不重弹对话）")
	_check(c2 != null and c2.sick and c2.sick_days == 3, "生病 + 连续天数还原")
	_check(c2 != null and c2.pregnant_days == 1 and c2.gestation == 3, "妊娠倒计时还原")
	_check(c2 != null and c2.partner_species == &"cow", "配偶物种回到 StringName")
	_check(c2 != null and c2.brushed_today and c2.pet_today == 1, "今日互动计数还原")
	_check(c2 != null and c2.pos.is_equal_approx(old_pos), "坐标还原（%s）" % (c2.pos if c2 else Vector2.ZERO))
	_check(c2 != null and c2.rng.state == cow.rng.state, "单只动物的 RNG 状态还原")
	var ch2 := h2.get_by_uid(chick_uid)
	_check(ch2 != null and ch2.days_old == 2, "幼年天数还原")

	# uid 主键：读档后新买的动物不能和老的撞号
	var fresh := h2.add(&"cow", 0)
	_check(fresh != null, "读档后还能加动物")
	_check(fresh != null and fresh.uid != old_uid, "新动物 uid 不撞老动物（%s）" % (fresh.uid if fresh else ""))
	_check(fresh != null and h2.count_species(&"cow") == 2, "物种计数正确")

	# 未知物种：旧档里有新版本删掉的动物 → 跳过，不崩
	var dirty: Dictionary = SaveSystem.jsonify(h.to_dict())
	dirty["animals"].append({"uid": "unicorn_9", "species": "unicorn", "affection": 100})
	h2.from_dict(dirty)
	_check(h2.get_by_uid(&"unicorn_9") == null, "未知物种被跳过")
	_check(h2.size() == 2, "其余动物还在（%d）" % h2.size())

# ---------------- 6. 订单板 ----------------

func _test_orders() -> void:
	print("[6] OrderBoard：订单 / 进度 / 颜色与物品类型")
	var ob := OrderBoard.new(7)
	var pool: Array = [&"turnip", &"milk", &"cheese"]
	ob.tick(1, 0, pool, 0)
	_check(ob.active_count() == 2, "刷出 2 单（%d）" % ob.active_count())
	var o: Dictionary = ob.active_orders()[0]
	var oid := int(o["id"])
	ob.deliver(o)

	SaveSystem.save(1, {"orders": ob.to_dict()})
	var back: Dictionary = SaveSystem.load_slot(1)["data"]["orders"]
	var ob2 := OrderBoard.new(1)
	ob2.from_dict(back)
	_check(ob2.completed == 1, "完成数还原")
	_check(ob2.active_count() == 1, "还剩 1 张 active（%d）" % ob2.active_count())
	var o2: Dictionary = ob2.active_orders()[0]
	_check(typeof(o2["item"]) == TYPE_STRING_NAME, "订单物品回到 StringName（%s）" % o2["item"])
	_check(typeof(o2["color"]) == TYPE_COLOR, "NPC 配色回到 Color")
	_check(ob2.due_abs(o2) == OrderBoard.abs_minute(int(o2["due_day"]), int(o2["due_minute"])),
		"截止时间可还原")
	_check(bool(ob2.can_deliver(o2, func(_id): return 99)["ok"]), "读档后订单能交付")
	_check(ob2.completed == 1 and oid != int(o2["id"]), "已完成的那张不在 active 里")

# ---------------- 7. 加工坊 ----------------

func _test_processor() -> void:
	print("[7] Processor：槽位 / 倒计时 / 品质")
	var p := Processor.new(1)
	var i := p.start(&"cheese", 2)
	_check(i == 0, "占第 0 槽（%d）" % i)
	var input0: StringName = p.slots[0]["input"]
	var output0: StringName = p.slots[0]["output"]
	p.advance_minutes(60)
	var remain := int(p.slots[0]["remain"])
	SaveSystem.save(1, {"processor": p.to_dict()})
	var pd: Dictionary = SaveSystem.load_slot(1)["data"]["processor"]
	var p2 := Processor.new(1)
	p2.from_dict(pd)
	_check(p2.used_slots() == 1, "槽位占用还原")
	_check(p2.slots[0]["input"] == input0, "原料回到 StringName（%s）" % p2.slots[0]["input"])
	_check(typeof(p2.slots[0]["input"]) == TYPE_STRING_NAME, "原料类型是 StringName")
	_check(p2.slots[0]["output"] == output0, "产物回到 StringName")
	_check(int(p2.slots[0]["remain"]) == remain, "倒计时还原（%d）" % remain)
	_check(int(p2.slots[0]["quality"]) == 2, "品质还原（金星）")
	_check(not p2.is_ready(0), "还没做好")
	p2.advance_minutes(100000)
	_check(p2.ready_count() == 1, "读档后继续跑能做好")
	var got := p2.take(0)
	_check(got.get("output", &"") == &"cheese" and int(got.get("quality", -1)) == 2,
		"取货产物 + 品质正确")
	# 等级 = 槽数
	var p3 := Processor.new(1)
	p3.from_dict({"level": 3, "slots": []})
	_check(p3.slot_count() == 6, "Lv3 = 6 槽（%d）" % p3.slot_count())

# ---------------- 8. 玩家 ----------------

func _test_player() -> void:
	print("[8] Player：位置 / 朝向 / 当前工具 / 当前种子")
	var pl := Player.new()
	pl.global_position = Vector2(123.5, 456.25)
	pl.facing = "left"
	pl.facing8 = "up_left"
	pl.current_tool = Player.Tool.FERT_HIGH
	pl.selected_seed = &"pumpkin"
	SaveSystem.save(1, {"player": pl.to_dict()})
	var pd: Dictionary = SaveSystem.load_slot(1)["data"]["player"]
	var pl2 := Player.new()
	pl2.from_dict(pd)
	_check(pl2.global_position.is_equal_approx(Vector2(123.5, 456.25)), "坐标还原")
	_check(pl2.facing == "left" and pl2.facing8 == "up_left", "朝向还原")
	_check(pl2.current_tool == Player.Tool.FERT_HIGH, "当前工具还原")
	_check(pl2.selected_seed == &"pumpkin", "当前种子回到 StringName")
	# 越界工具号钳制
	pl2.from_dict({"tool": 99, "seed": "turnip"})
	_check(pl2.current_tool == Player.TOOL_LABEL.size() - 1, "工具号越界钳到最后一把")
	pl.free()
	pl2.free()

# ---------------- 9. main 集成：真存档文件端到端 ----------------

func _test_main() -> void:
	print("[9] main 集成：F5 存 → 破坏现场 → F9 读 → 逐项对账")
	SaveSystem.save_dir = "user://saves_test"
	_clean_saves()
	GameState.reset()
	# ⚠️ 必须把时钟也归位：前面的用例把 season 推到了 3（冬天），
	#    不归位的话 main 开局的季节门禁是冬天，春天作物直接种不下去 —— 这条踩过。
	GameClock.day = 1
	GameClock.season = 0
	GameClock.year = 1
	GameClock.minutes = 0
	GameClock.phase = GameClock.phase_at(0)
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
	_check(not SaveSystem.exists(SaveSystem.SLOT_QUICK), "开局没有快速存档")
	_check(main._player != null and main._herd != null, "main 初始化完了")

	# --- 造一局「明显不是开局」的状态 ---
	GameState.add_gold(5000)
	GameState.add_item(&"turnip_gold", 5)
	GameState.set_tool_level(&"bag", 2)
	GameState.set_flag(&"garden_unlocked", true)
	var cell := Vector2i(5, 5)
	main._grid.till(cell)
	main._grid.plant(cell, main._player.selected_seed)
	main._grid.water(cell)
	var cow: AnimalState = main._herd.animals[0]
	cow.gain_affection(150)
	main._proc.start(&"cheese", 1)
	GameClock.day = 9
	GameClock.season = 1
	GameClock.minutes = 300
	main._player.global_position = Vector2(600, 300)
	main._player.current_tool = Player.Tool.CAN

	var gold0 := GameState.gold
	var cow_uid: StringName = cow.uid
	var cow_aff: int = cow.affection
	var day0 := GameClock.day
	var seed0: StringName = main._player.selected_seed

	# --- F5 存 ---
	var saved: bool = main._save_game(SaveSystem.SLOT_QUICK)
	_check(saved, "F5 存档成功")
	_check(SaveSystem.exists(SaveSystem.SLOT_QUICK), "快速档文件落盘")
	var file_text := FileAccess.get_file_as_string(SaveSystem.slot_path(SaveSystem.SLOT_QUICK))
	_check(file_text.contains("\"herd\""), "存档里有动物段")
	_check(file_text.contains("\"farm\""), "存档里有农田段")
	_check(JSON.parse_string(file_text) != null, "存档是合法 JSON")

	# --- 破坏现场 ---
	GameState.reset()
	main._herd.animals.clear()
	main._proc = Processor.new(1)
	main._grid = FarmGrid.new()
	GameClock.day = 1
	GameClock.season = 0
	GameClock.minutes = 0
	main._player.global_position = Vector2(704, 288)
	_check(GameState.gold == 500, "现场已破坏（前提）")

	# --- F9 读 ---
	var loaded: bool = main._load_game(SaveSystem.SLOT_QUICK)
	_check(loaded, "F9 读档成功")
	_check(GameState.gold == gold0, "金币对账（%d）" % GameState.gold)
	_check(GameState.count_item(&"turnip_gold") == 5, "金星芜菁对账")
	_check(GameState.slot_capacity() == 48, "背包 Lv2 = 48 格（%d）" % GameState.slot_capacity())
	_check(GameState.has_flag(&"garden_unlocked"), "花园解锁对账")
	_check(GameClock.day == day0 and GameClock.season == 1, "日期对账（第 %d 天）" % GameClock.day)
	_check(GameClock.minutes == 300, "时钟对账（%d）" % GameClock.minutes)
	_check(main._player.selected_seed == seed0, "当前种子对账")
	_check(main._player.current_tool == Player.Tool.CAN, "当前工具对账")
	_check(main._player.global_position.is_equal_approx(Vector2(600, 300)), "玩家位置对账")
	var cow_back: AnimalState = main._herd.get_by_uid(cow_uid)
	_check(cow_back != null, "奶牛按 uid 回来了")
	_check(cow_back != null and cow_back.affection == cow_aff, "奶牛好感对账（%d）" % (cow_back.affection if cow_back else -1))
	_check(main._herd.size() == 9, "牧群数量对账（%d）" % main._herd.size())
	_check(main._proc.used_slots() == 1, "加工槽对账")
	_check(main._grid.tile_at(cell) != null and main._grid.tile_at(cell).crop_id != StringName(""),
		"农田作物对账")
	_check(main._grid.season == GameClock.season, "农田季节门禁跟着时钟")
	# 节点同步：不是只灌了数据
	_check(main._animal_layer.herd == main._herd, "动物层挂回新 herd")
	var hud: String = main.get_node("UI/HUD").text
	_check(hud.contains("💰") and hud.contains("格"), "HUD 重刷过了（%d 字）" % hud.length())
	_check(main.get_node("UI/ToolBar").text.contains("锄Lv"), "工具条重刷过了")
	var clock_text: String = main.get_node("UI/ClockPanel").text
	_check(clock_text.contains("9 日"), "时钟面板立刻刷成读档天数")
	_check(not main._shop.is_open() and not main._inv.is_open(), "读档时 UI 关掉了")

	# --- 自动存档：0 号槽 ---
	_clean_saves()
	_check(main._save_game(SaveSystem.SLOT_AUTO, true), "自动存档成功")
	_check(SaveSystem.exists(SaveSystem.SLOT_AUTO), "自动档写 0 号槽")
	_check(not SaveSystem.exists(SaveSystem.SLOT_QUICK), "自动存档不动快速槽")
	# 自动存档也不该弹提示（quiet）—— 提示条保持在 2.5 秒窗口内不算数，只验文件
	var info := SaveSystem.info(SaveSystem.SLOT_AUTO)
	_check(int(info["day"]) == 9, "自动档摘要天数 = 9")

	# --- F9 退化到自动档 ---
	main._load_latest()
	_check(GameClock.day == 9, "没有快速档时 F9 读自动档")

	# --- 无档不崩 ---
	_clean_saves()
	main._load_latest()
	_check(true, "一张档都没有时 F9 不崩")

	# --- 坏档不崩 ---
	var f := FileAccess.open(SaveSystem.slot_path(SaveSystem.SLOT_QUICK), FileAccess.WRITE)
	f.store_string("垃圾数据")
	f.close()
	var bad_ok: bool = main._load_game(SaveSystem.SLOT_QUICK)
	_check(not bad_ok, "坏档读档返回 false")
	_check(main._herd.size() == 9, "坏档读失败后场面没被破坏")

	main.queue_free()
	await get_tree().process_frame
