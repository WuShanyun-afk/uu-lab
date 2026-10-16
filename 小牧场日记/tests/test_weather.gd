extends Node
## 模块 2 验收：时间与天气系统
## 运行： godot --headless --path <项目> res://tests/test_weather.tscn
##
## 覆盖（全部是断言，不接受「看起来对」）：
##   1. 时钟常量：12 分钟/天 · 6:00 起床 · 2:00 强制入睡 · 四时段边界
##   2. 季节效果表：草地色 / 牛奶倍率 / 售价倍率 / 冬季禁种
##   3. 天气概率表：每季和 = 1 · 冬季无雨 · 雪只在冬
##   4. 天气效果表：自动浇水 / 留棚好感 / 饲料 ×2 / 灾害概率 / 光照 -10%
##   5. 预报：20:00 才可看 · 85% 准 · 报错池不含真天气
##   6. 掷骰分布：20000 次统计
##   7. 集成：换季染色 · 阴天光照 · 雨天自动浇水 · 留棚 · 雪天喂食 ×2 · 冬禁种 · 右上角 UI

var _fails: Array[String] = []

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails.append(label)
	print(("  [OK] " if cond else "  [FAIL] ") + label)

## Godot 的 String % 不吃 %.3f 这种精度修饰符（报 unsupported format character），
## 所以自己把浮点截成 3 位再当字符串塞进去。
func _f3(x: float) -> String:
	return str(snappedf(x, 0.001))

func _ready() -> void:
	print("=== 模块 2：时间与天气系统 ===")
	_test_clock()
	_test_season_effects()
	_test_weather_table()
	_test_weather_effects()
	_test_forecast()
	_test_roll_distribution()
	await _test_integration()

	var ok := _fails.is_empty()
	print("=== 结果：%s ===" % ("全部通过" if ok else "失败 %d 项" % _fails.size()))
	if not ok:
		for f in _fails:
			print("   ! " + f)
	get_tree().quit(0 if ok else 1)

# ---------------- 1. 时钟 ----------------

func _test_clock() -> void:
	print("[1] 时钟常量与时段")
	_check(absf(GameClock.TICKS_PER_DAY * GameClock.TICK_REAL_SECONDS - 720.0) < 0.001,
		"1 游戏日 = 720 现实秒 = 12 分钟")
	_check(GameClock.TOTAL_MINUTES == 1200, "一天 20 小时 = 1200 游戏分钟（6:00 → 次日 2:00）")

	GameClock.minutes = 0
	_check(GameClock.clock_text() == "06:00", "minutes=0 → 06:00 起床")
	_check(GameClock.hour() == 6 and GameClock.minute_of_day() == 0, "hour()=6 · minute_of_day()=0")

	var end_hour := int((GameClock.DAY_START_HOUR * 60 + GameClock.TOTAL_MINUTES) / 60) % 24
	_check(end_hour == 2, "最后一个 tick 落在 2:00（强制入睡）")
	GameClock.minutes = GameClock.TOTAL_MINUTES - GameClock.TICK_GAME_MINUTES
	_check(GameClock.clock_text() == "01:50", "睡前最后一格 = 01:50")

	_check(GameClock.phase_at(0) == GameClock.Phase.DAWN, "6:00 清晨")
	_check(GameClock.phase_at(180) == GameClock.Phase.DAY, "9:00 白天")
	_check(GameClock.phase_at(660) == GameClock.Phase.DUSK, "17:00 黄昏")
	_check(GameClock.phase_at(840) == GameClock.Phase.NIGHT, "20:00 夜晚")

	var slept := [0]
	EventBus.forced_sleep.connect(func() -> void: slept[0] += 1)
	GameClock.day = 1
	GameClock.season = 0
	GameClock.year = 1
	GameClock.minutes = 0
	for i in range(GameClock.TICKS_PER_DAY):
		GameClock._tick()
	_check(slept[0] == 1, "跨日瞬间广播 forced_sleep 一次（实际 %d）" % slept[0])
	_check(GameClock.day == 2 and GameClock.minutes == 0, "跨日后 day=2 且回到 6:00")
	_check(GameClock.phase == GameClock.Phase.DAWN, "跨日后时段回到清晨（不残留昨天的夜晚）")

	# 时段必须从 minutes 现算 —— 直接改 minutes（存档读档 / 调试）也要立刻正确
	GameClock.minutes = 700
	_check(GameClock.phase_name() == "黄昏", "直接改 minutes=700 → 立刻是黄昏（%s）" % GameClock.phase_name())
	_check(GameClock.current_phase() == GameClock.Phase.DUSK, "current_phase() 同样现算")
	GameClock.minutes = 420
	_check(GameClock.phase_name() == "白天", "minutes=420 → 白天")
	_check(GameClock.in_graze_window(), "13:00 在放牧窗口内")
	GameClock.minutes = 960
	_check(not GameClock.in_graze_window(), "23:00 不在放牧窗口内")
	GameClock.minutes = 0

# ---------------- 2. 季节效果 ----------------

func _test_season_effects() -> void:
	print("[2] 季节效果表")
	_check(SeasonEffects.NAMES == ["春", "夏", "秋", "冬"], "四季名")
	_check(SeasonEffects.grass_color(0).is_equal_approx(Color("#7FC15E")), "春草地 #7FC15E")
	_check(SeasonEffects.grass_color(1).is_equal_approx(Color("#5FA83C")), "夏草地 #5FA83C")
	_check(SeasonEffects.grass_color(2).is_equal_approx(Color("#C9A44C")), "秋草地 #C9A44C")
	_check(SeasonEffects.grass_color(3).is_equal_approx(Color("#E8EDF2")), "冬草地 #E8EDF2")
	_check(is_equal_approx(SeasonEffects.grass_tint_amount(0), 0.0), "春染色强度 = 0（地表与美术原图完全一致）")
	_check(SeasonEffects.grass_tint_amount(3) > 0.5, "冬染色强度够大（真的会变雪白）")
	_check(SeasonEffects.grass_tint_amount(2) > 0.0, "秋会染色")

	_check(is_equal_approx(SeasonEffects.milk_multiplier(1), 1.2), "夏牛奶 +20%")
	_check(is_equal_approx(SeasonEffects.milk_multiplier(3), 0.85), "冬牛奶 -15%")
	_check(is_equal_approx(SeasonEffects.milk_multiplier(0), 1.0), "春牛奶无加成")
	_check(is_equal_approx(SeasonEffects.crop_price_multiplier(2), 1.1), "秋作物售价 +10%")
	_check(is_equal_approx(SeasonEffects.crop_price_multiplier(0), 1.0), "春售价无加成")
	_check(SeasonEffects.can_plant_outdoor(0) and SeasonEffects.can_plant_outdoor(1)
		and SeasonEffects.can_plant_outdoor(2), "春/夏/秋可户外种植")
	_check(not SeasonEffects.can_plant_outdoor(3), "冬季户外禁种")

	# 牛奶加成是「期望值」放大，不能被四舍五入吃掉
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n := 20000
	var sum := 0
	for i in range(n):
		sum += SeasonEffects.apply_milk_mult(1, 1, rng)
	var mean := float(sum) / float(n)
	_check(absf(mean - 1.2) < 0.03, "夏 1 罐 → 期望 1.2（实测 %s）" % _f3(mean))
	sum = 0
	for i in range(n):
		sum += SeasonEffects.apply_milk_mult(2, 3, rng)
	var mean2 := float(sum) / float(n)
	_check(absf(mean2 - 1.7) < 0.03, "冬 2 罐 → 期望 1.7（实测 %s）" % _f3(mean2))
	_check(SeasonEffects.apply_milk_mult(1, 0, rng) == 1, "春 1 罐 → 恒为 1")

# ---------------- 3. 天气概率表 ----------------

func _test_weather_table() -> void:
	print("[3] 天气概率表")
	_check(WeatherSystem.ORDER.size() == 5, "5 种天气")
	_check(WeatherSystem.NAME.size() == 5 and WeatherSystem.ICON.size() == 5, "5 个名字 + 5 个图标")
	for s in range(4):
		var total := 0.0
		for w in WeatherSystem.ORDER:
			total += float(WeatherSystem.TABLE[w][s])
		_check(absf(total - 1.0) < 1e-6, "%s季概率和 = 1.00（实际 %s）" % [SeasonEffects.name(s), _f3(total)])
	_check(is_equal_approx(float(WeatherSystem.TABLE[WeatherSystem.Weather.RAIN][3]), 0.0), "冬季不下雨")
	_check(is_equal_approx(float(WeatherSystem.TABLE[WeatherSystem.Weather.STORM][3]), 0.0), "冬季无暴风雨")
	_check(is_equal_approx(float(WeatherSystem.TABLE[WeatherSystem.Weather.SNOW][3]), 0.4), "冬季雪 40%")
	for s in range(3):
		_check(is_equal_approx(float(WeatherSystem.TABLE[WeatherSystem.Weather.SNOW][s]), 0.0),
			"%s季不下雪" % SeasonEffects.name(s))

# ---------------- 4. 天气效果表 ----------------

func _test_weather_effects() -> void:
	print("[4] 天气效果表")
	var W := WeatherSystem.Weather

	var clear := WeatherSystem.effects(W.CLEAR, 0)
	_check(not clear["auto_water"] and clear["graze"] and int(clear["affection_bonus"]) == 0,
		"晴天：正常放牧 · 不自动浇水 · 无留棚奖励")
	var cloudy := WeatherSystem.effects(W.CLOUDY, 0)
	_check(is_equal_approx(float(cloudy["light_mult"]), 0.9), "阴天：光照 -10%")
	_check(not cloudy["auto_water"] and cloudy["graze"], "阴天：不影响放牧与浇水")

	var rain := WeatherSystem.effects(W.RAIN, 0)
	_check(rain["auto_water"], "雨天：自动浇水")
	_check(not rain["graze"], "雨天：不放牧")
	_check(int(rain["affection_bonus"]) == 3, "雨天：留棚好感 +3")

	var storm := WeatherSystem.effects(W.STORM, 0)
	_check(is_equal_approx(float(storm["fence_risk"]), 0.05), "暴风雨：栅栏损坏 5%")
	_check(is_equal_approx(float(storm["crop_burn_risk"]), 0.03), "暴风雨：雷击 3%")
	_check(storm["auto_water"], "暴风雨：也自动浇水")

	var snow := WeatherSystem.effects(W.SNOW, 3)
	_check(int(snow["feed_mult"]) == 2, "雪天：饲料 ×2")
	_check(not snow["graze"] and int(snow["affection_bonus"]) == 3, "雪天：不放牧 · 留棚 +3")
	_check(not snow["auto_water"], "雪天：不自动浇水")

	_check(is_equal_approx(float(WeatherSystem.effects(W.CLEAR, 1)["milk_mult"]), 1.2), "夏天牛奶倍率进效果表")
	_check(is_equal_approx(float(WeatherSystem.effects(W.CLEAR, 2)["crop_price_mult"]), 1.1), "秋天售价倍率进效果表")

# ---------------- 5. 预报 ----------------

func _test_forecast() -> void:
	print("[5] 预报（20:00 可看 / 85% 准）")
	_check(is_equal_approx(WeatherSystem.FORECAST_ACCURACY, 0.85), "预报准确率 85%")
	GameClock.minutes = WeatherSystem.FORECAST_MINUTES - 1
	_check(not WeatherSystem.has_forecast(), "19:59 看不到预报")
	GameClock.minutes = WeatherSystem.FORECAST_MINUTES
	_check(WeatherSystem.has_forecast(), "20:00 起可看预报")

	var W := WeatherSystem.Weather
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var hit := 0
	var n := 20000
	for i in range(n):
		if WeatherSystem.make_forecast(W.RAIN, rng) == W.RAIN:
			hit += 1
	var acc := float(hit) / float(n)
	_check(absf(acc - 0.85) < 0.02, "预报命中率 ≈ 85%%（实测 %s）" % _f3(acc))

	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 5
	var seen := {}
	for i in range(4000):
		var f := WeatherSystem.make_forecast(W.SNOW, rng2)
		if f != W.SNOW:
			seen[f] = true
	_check(seen.size() == 4, "报错时 4 种其它天气都可能出现（实测 %d 种）" % seen.size())
	_check(not seen.has(W.SNOW), "报错池里不含真天气")

# ---------------- 6. 掷骰分布 ----------------

func _frac(counts: Dictionary, w: int, n: int) -> float:
	return float(counts[w]) / float(n)

func _near(counts: Dictionary, w: int, n: int, expect: float) -> bool:
	return absf(_frac(counts, w, n) - expect) < 0.02

func _test_roll_distribution() -> void:
	print("[6] 掷骰分布（各 20000 次统计）")
	var W := WeatherSystem.Weather
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var n := 20000
	var counts := {}
	for w in WeatherSystem.ORDER:
		counts[w] = 0
	for i in range(n):
		counts[WeatherSystem.roll(0, rng)] += 1
	_check(_near(counts, W.RAIN, n, 0.30), "春·雨 ≈ 30%%（%s）" % _f3(_frac(counts, W.RAIN, n)))
	_check(_near(counts, W.STORM, n, 0.10), "春·暴风雨 ≈ 10%%（%s）" % _f3(_frac(counts, W.STORM, n)))
	_check(int(counts[W.SNOW]) == 0, "春·永不下雪")

	for w in WeatherSystem.ORDER:
		counts[w] = 0
	for i in range(n):
		counts[WeatherSystem.roll(3, rng)] += 1
	_check(_near(counts, W.SNOW, n, 0.40), "冬·雪 ≈ 40%%（%s）" % _f3(_frac(counts, W.SNOW, n)))
	_check(int(counts[W.RAIN]) == 0, "冬·永不下雨")
	_check(int(counts[W.STORM]) == 0, "冬·永无暴风雨")

# ---------------- 7. 集成 ----------------

func _test_integration() -> void:
	print("[7] 与农场 / 动物 / 渲染 / UI 的集成")
	GameClock.season = 2                 # 秋
	GameClock.day = 1
	GameClock.year = 1
	GameClock.minutes = 0

	var ps: PackedScene = load("res://scenes/main.tscn")
	_check(ps != null, "main.tscn 可加载")
	if ps == null:
		return
	var main := ps.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().physics_frame

	# --- 季节外观 ---
	var ground: GroundLayer = main.get_node("World/GroundLayer")
	_check(ground.material is ShaderMaterial, "地面挂了季节染色着色器")
	var mat: ShaderMaterial = ground.material
	_check(Color(mat.get_shader_parameter("tint")).is_equal_approx(SeasonEffects.grass_color(2)),
		"开局 = 秋色目标 #C9A44C")
	_check(is_equal_approx(float(mat.get_shader_parameter("amount")), SeasonEffects.grass_tint_amount(2)),
		"开局 = 秋色强度")
	# 走真实路径：先改 GameClock.season，再广播 season_changed（正常换季就是这么发生的）
	GameClock.season = 3
	EventBus.season_changed.emit(3)
	_check(Color(mat.get_shader_parameter("tint")).is_equal_approx(SeasonEffects.grass_color(3)),
		"换季 → 冬色目标 #E8EDF2")
	_check(float(mat.get_shader_parameter("amount")) > 0.5, "换季 → 冬天染白强度够大")
	_check(main.pen_color().is_equal_approx(Color("#8FC96A").lerp(
		SeasonEffects.grass_color(3), SeasonEffects.grass_tint_amount(3))),
		"牧场地面也吃季节染色（不会四季常绿）")

	# --- 阴天光照 -10% ---
	GameClock.minutes = 420              # 13:00 → 白天纯白
	WeatherSystem.debug_set(WeatherSystem.Weather.CLOUDY)
	main._refresh_light()
	_check(main._light.color.is_equal_approx(Color(0.9, 0.9, 0.9, 1.0)),
		"阴天正午光照 = 白 × 0.9（实际 %s）" % str(main._light.color))
	WeatherSystem.debug_set(WeatherSystem.Weather.CLEAR)
	main._refresh_light()
	_check(main._light.color.is_equal_approx(Color(1, 1, 1, 1)), "晴天正午光照 = 纯白")

	# --- 雨天自动浇水 ---
	var grid: FarmGrid = main._grid
	grid.till(Vector2i(3, 3))
	grid.till(Vector2i(4, 3))
	_check(not grid.tile_at(Vector2i(3, 3)).watered, "刚锄完的地还没浇水")
	WeatherSystem.debug_set(WeatherSystem.Weather.RAIN)
	main._apply_weather_day()
	_check(grid.tile_at(Vector2i(3, 3)).watered, "雨天：耕地自动浇水")
	_check(grid.tile_at(Vector2i(4, 3)).watered, "雨天：第二块也浇了")

	# --- 雨天留棚好感 +3 ---
	var cow: AnimalState = main._herd.animals[0]
	var aff := cow.affection
	WeatherSystem.debug_set(WeatherSystem.Weather.RAIN)
	main._apply_weather_day()
	_check(cow.affection == aff + 3, "雨天：动物留棚好感 +3（%d → %d）" % [aff, cow.affection])
	var aff2 := cow.affection
	WeatherSystem.debug_set(WeatherSystem.Weather.CLEAR)
	main._apply_weather_day()
	_check(cow.affection == aff2, "晴天：不留棚奖励")

	# --- 雪天喂食消耗 ×2 ---
	GameState.add_item(&"feed", 10)
	WeatherSystem.debug_set(WeatherSystem.Weather.SNOW)
	cow.fed_today = 0
	main._player.global_position = cow.pos
	main._player.facing = "down"
	main._player.facing8 = "down"
	var feed_before := GameState.count_item(&"feed")
	main._handle_animal(Player.Tool.FEED)
	_check(GameState.count_item(&"feed") == feed_before - 2,
		"雪天：喂食消耗饲料 ×2（%d → %d）" % [feed_before, GameState.count_item(&"feed")])
	_check(cow.fed_today == 1, "雪天：喂食仍只算 1 次")

	# --- 冬季户外禁种 ---
	GameClock.season = 3
	grid.till(Vector2i(6, 6))
	main._on_tool_used(Player.Tool.SEED, Vector2i(6, 6))
	_check(grid.tile_at(Vector2i(6, 6)).crop_id == StringName(""), "冬天：没种下去")
	var tip: Label = main.get_node("UI/Tip")
	_check(tip.text.contains("冬天"), "冬天：播种被拦下并提示（%s）" % tip.text)

	# --- 右上角 UI ---
	var clock := main.get_node_or_null("UI/ClockPanel")
	_check(clock != null and clock is ClockHUD, "UI 有右上角时钟面板")
	var vfx := main.get_node_or_null("UI/WeatherVFX")
	_check(vfx != null and vfx is WeatherVFX, "UI 有天气特效层")
	_check(main.get_node("UI").get_child(0) == vfx, "天气层是 UI 第一个子节点（雨不会盖住 HUD）")

	GameClock.day = 3
	GameClock.season = 0
	GameClock.year = 1
	GameClock.debug_set_minutes(0)
	WeatherSystem.debug_set(WeatherSystem.Weather.SNOW)
	clock.refresh()
	var flat: String = clock.text.replace("\n", " / ")
	_check(clock.text.contains("第 1 年 春季 3 日"), "面板显示日期（%s）" % flat)
	_check(clock.text.contains("06:00"), "面板显示时间")
	_check(clock.text.contains("清晨"), "面板显示时段")
	_check(clock.text.contains("雪"), "面板显示天气")

	WeatherSystem.debug_set(WeatherSystem.Weather.SNOW, true)
	# 故意不手动 refresh()：改暴风雪标记也必须自己广播出来
	_check(clock.text.contains("暴风雪"), "暴风雪单独命名（靠信号刷新，没手动 refresh）")

	WeatherSystem.debug_set(WeatherSystem.Weather.CLEAR)
	GameClock.minutes = 100
	clock.refresh()
	_check(not clock.text.contains("明日"), "白天不显示明日预报")
	GameClock.minutes = 900
	clock.refresh()
	_check(clock.text.contains("明日"), "夜晚显示明日预报")

	main.queue_free()
	await get_tree().process_frame
