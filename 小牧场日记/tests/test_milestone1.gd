extends Node
## 里程碑 1 验收测试（GDD §11）
## 运行： godot --headless --path <项目> res://tests/test_milestone1.tscn
##
## 断言全部来自 GDD §1 的数值表，不接受"看起来对"。

var _fails: Array[String] = []

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails.append(label)
	print(("  [OK] " if cond else "  [FAIL] ") + label)

func _ready() -> void:
	print("=== 《小牧场日记》里程碑 1 验收 ===")

	# --- 1. 时段边界 ---
	_check(GameClock.phase_at(0) == GameClock.Phase.DAWN, "6:00 是清晨")
	_check(GameClock.phase_at(179) == GameClock.Phase.DAWN, "8:59 仍是清晨")
	_check(GameClock.phase_at(180) == GameClock.Phase.DAY, "9:00 转白天")
	_check(GameClock.phase_at(659) == GameClock.Phase.DAY, "16:59 仍是白天")
	_check(GameClock.phase_at(660) == GameClock.Phase.DUSK, "17:00 转黄昏")
	_check(GameClock.phase_at(839) == GameClock.Phase.DUSK, "19:59 仍是黄昏")
	_check(GameClock.phase_at(840) == GameClock.Phase.NIGHT, "20:00 转夜晚")
	_check(GameClock.phase_at(1199) == GameClock.Phase.NIGHT, "1:59 仍是夜晚")

	# --- 2. 光照关键帧 ---
	_check(GameClock.light_color_at(90).is_equal_approx(Color("#FFD9A0")), "7:30 清晨中段 = #FFD9A0")
	_check(GameClock.light_color_at(420).is_equal_approx(Color("#FFFFFF")), "13:00 白天中段 = #FFFFFF")
	_check(GameClock.light_color_at(750).is_equal_approx(Color("#FF9B5A")), "18:30 黄昏中段 = #FF9B5A")
	_check(GameClock.light_color_at(1020).is_equal_approx(Color("#2A3A6B")), "23:00 夜晚中段 = #2A3A6B")
	# 过渡窗口必须恰好 50 游戏分钟（= 30 现实秒）
	_check(GameClock.light_color_at(155).is_equal_approx(Color("#FFD9A0")), "8:35 仍为清晨色")
	_check(GameClock.light_color_at(205).is_equal_approx(Color("#FFFFFF")), "9:25 已为白天色")
	_check(GameClock.light_color_at(635).is_equal_approx(Color("#FFFFFF")), "16:35 仍为白天色")
	_check(GameClock.light_color_at(685).is_equal_approx(Color("#FF9B5A")), "17:25 已为黄昏色")
	_check(GameClock.light_color_at(815).is_equal_approx(Color("#FF9B5A")), "19:35 仍为黄昏色")
	_check(GameClock.light_color_at(865).is_equal_approx(Color("#2A3A6B")), "20:25 已为夜晚色")

	# --- 3. 时钟文本 ---
	GameClock.minutes = 0
	_check(GameClock.clock_text() == "06:00", "minutes=0 -> 06:00")
	GameClock.minutes = 660
	_check(GameClock.clock_text() == "17:00", "minutes=660 -> 17:00")
	GameClock.minutes = 1199
	_check(GameClock.clock_text() == "01:59", "minutes=1199 -> 01:59")

	# --- 4. 跑满 120 tick 跨日 ---
	GameClock.day = 1
	GameClock.season = 0
	GameClock.year = 1
	GameClock.minutes = 0
	for i in range(GameClock.TICKS_PER_DAY):
		GameClock._tick()
	_check(GameClock.day == 2, "跑满 120 tick 后 day = 2（实际 %d）" % GameClock.day)
	_check(GameClock.minutes == 0, "跨日后 minutes 归零（实际 %d）" % GameClock.minutes)

	# --- 5. 第 28 天换季 ---
	GameClock.day = 28
	GameClock.season = 0
	GameClock.minutes = 0
	for i in range(GameClock.TICKS_PER_DAY):
		GameClock._tick()
	_check(GameClock.season == 1 and GameClock.day == 1,
		"第 28 天结束 -> 春转夏且 day=1（实际 season=%d day=%d）" % [GameClock.season, GameClock.day])

	# --- 6. 冬季结束回春且年份 +1 ---
	GameClock.day = 28
	GameClock.season = 3
	GameClock.year = 1
	GameClock.minutes = 0
	for i in range(GameClock.TICKS_PER_DAY):
		GameClock._tick()
	_check(GameClock.season == 0 and GameClock.year == 2,
		"冬末 -> 春 + 年份 +1（实际 season=%d year=%d）" % [GameClock.season, GameClock.year])

	# --- 7. 常量自洽 ---
	_check(GameClock.TICKS_PER_DAY == 120, "TICKS_PER_DAY = 120")
	_check(absf(GameClock.TICKS_PER_DAY * GameClock.TICK_REAL_SECONDS - 720.0) < 0.001,
		"全天 = 720 现实秒 = 12 分钟")
	_check(absf(720.0 / GameClock.TICKS_PER_DAY - 6.0) < 0.001, "1 tick = 6 现实秒")

	var ok := _fails.is_empty()
	print("=== 结果：%s ===" % ("全部通过" if ok else "失败 %d 项" % _fails.size()))
	if not ok:
		for f in _fails:
			print("   ! " + f)
	get_tree().quit(0 if ok else 1)
