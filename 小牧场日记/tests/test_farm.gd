extends Node
## 农场系统验收（GDD §11 里程碑 2）
## 验收标准：锄地后 tile 变为耕地；浇水后 watered=true；4 天后芜菁可收获入背包
## 运行： godot --headless --path <项目> res://tests/test_farm.tscn

var _fails: Array[String] = []

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails.append(label)
	print(("  [OK] " if cond else "  [FAIL] ") + label)

func _ready() -> void:
	print("=== 农场系统验收（里程碑 2）===")

	var g := FarmGrid.new(12345)
	var cell := Vector2i(5, 5)

	# --- 1. 锄地 ---
	_check(g.tile_at(cell) == null, "初始该格无数据")
	_check(g.till(cell), "锄地成功")
	_check(g.tile_at(cell).tilled, "锄地后 tilled = true")
	_check(not g.till(cell), "同一格不能重复锄")

	# --- 2. 浇水 ---
	_check(g.water(cell), "浇水成功")
	_check(g.tile_at(cell).watered, "浇水后 watered = true")
	_check(not g.water(cell), "同一天不能重复浇水")

	# --- 3. 播种 ---
	_check(g.plant(cell, &"turnip"), "播种芜菁")
	_check(g.tile_at(cell).crop_id == &"turnip", "crop_id = turnip")
	_check(not g.is_mature(cell), "刚种下未成熟")
	_check(not g.plant(cell, &"potato"), "已有作物的格子不能再种")
	_check(not g.plant(Vector2i(9, 9), &"turnip"), "未锄地的格子不能种")
	_check(not g.plant(Vector2i(5, 6), &"nonexistent"), "未知作物 id 拒绝")

	# --- 4. 4 天生长（GDD 验收标准）---
	for i in range(4):
		g.water(cell)
		g.advance_day()
	_check(g.is_mature(cell), "4 天后芜菁成熟（days_grown = %d）" % g.tile_at(cell).days_grown)

	# --- 5. 收获 ---
	var out := g.harvest(cell)
	_check(not out.is_empty(), "收获有产出")
	_check(out.get("id") == "turnip", "产出 id = turnip")
	_check(g.tile_at(cell).crop_id == StringName(""), "一次性作物收获后清空")
	_check(not g.is_mature(cell), "收获后不再成熟")

	# --- 6. 未浇水 → 枯萎 → 枯死 ---
	var c2 := Vector2i(6, 6)
	g.till(c2)
	g.plant(c2, &"potato")
	g.advance_day()
	_check(g.tile_at(c2).dry_days == 1, "1 天没浇水 dry_days = 1")
	g.advance_day()
	_check(g.tile_at(c2).dry_days == 2, "2 天没浇水 dry_days = 2（枯萎）")
	_check(not g.tile_at(c2).dead, "枯萎但未死")
	g.water(c2)
	_check(g.tile_at(c2).dry_days == 0, "浇水后 dry_days 归零 → 复活")

	# 枯死另开一格测，避免被上面的浇水打乱计数
	var c2b := Vector2i(11, 11)
	g.till(c2b)
	g.plant(c2b, &"potato")
	g.advance_day()
	_check(g.tile_at(c2b).dry_days == 1, "新格 1 天没浇水 dry_days = 1")
	g.advance_day()
	g.advance_day()
	_check(g.tile_at(c2b).dry_days == 3, "3 天没浇水仍未死")
	g.advance_day()
	_check(g.tile_at(c2b).dead, "连续 4 天不浇水 → 枯死")

	# --- 7. 再生作物（草莓：8 天成熟 / 4 天再生）---
	var c4 := Vector2i(8, 8)
	g.till(c4)
	g.plant(c4, &"strawberry")
	for i in range(8):
		g.water(c4)
		g.advance_day()
	_check(g.is_mature(c4), "草莓 8 天成熟")
	var o1 := g.harvest(c4)
	_check(not o1.is_empty(), "草莓第一次收获")
	_check(g.tile_at(c4).crop_id == &"strawberry", "再生作物收获后保留")
	_check(not g.is_mature(c4), "收获后立刻不再成熟")
	for i in range(4):
		g.water(c4)
		g.advance_day()
	_check(g.is_mature(c4), "4 天后草莓再生成熟")

	# --- 8. 数据表（GDD §4.1 春季 6 种）---
	_check(CropDB.crops.size() >= 6, "作物表 >= 6 种（实际 %d）" % CropDB.crops.size())
	var t: CropData = CropDB.get_crop(&"turnip")
	_check(t != null, "能查到芜菁")
	if t:
		_check(t.grow_days == 4, "芜菁 4 天成熟")
		_check(t.seed_price == 20, "芜菁种子 20G")
		_check(t.sell_price == 35, "芜菁售价 35G")
		_check(t.display_name == "芜菁", "芜菁中文名正确")
	var sb: CropData = CropDB.get_crop(&"strawberry")
	_check(sb != null and sb.regrow_days == 4, "草莓再生间隔 4 天")

	# --- 9. 生长进度 ---
	var c5 := Vector2i(10, 10)
	g.till(c5)
	g.plant(c5, &"cauliflower")
	_check(is_equal_approx(g.growth_ratio(c5), 0.0), "刚种下进度 0.0")
	g.water(c5)
	g.advance_day()
	_check(g.growth_ratio(c5) > 0.0 and g.growth_ratio(c5) < 1.0, "生长中进度在 (0,1)")

	# --- 10. 边界 ---
	_check(not g.till(Vector2i(-1, 0)), "越界锄地失败（负数）")
	_check(not g.till(Vector2i(999, 999)), "越界锄地失败（超界）")
	_check(g.in_bounds(Vector2i(0, 0)), "原点在界内")
	_check(g.in_bounds(FarmGrid.SIZE - Vector2i(1, 1)), "右下角在界内")
	_check(not g.in_bounds(FarmGrid.SIZE), "SIZE 本身越界")

	var ok := _fails.is_empty()
	print("=== 结果：%s ===" % ("全部通过" if ok else "失败 %d 项" % _fails.size()))
	if not ok:
		for f in _fails:
			print("   ! " + f)
	get_tree().quit(0 if ok else 1)
