extends Node
## 时间系统 —— 严格实现 GDD §1
##
##   1 游戏日 = 20 游戏小时（6:00 → 次日 2:00）= 1200 游戏分钟
##   1 游戏分钟 = 0.6 现实秒
##   1 游戏日 = 720 现实秒 = 12 分钟
##   1 tick = 10 游戏分钟 = 6 现实秒，全天 120 tick
##
## 所有玩法系统都从 minutes 换算，不要再各自维护计时器。

enum Phase { DAWN, DAY, DUSK, NIGHT }

const PHASE_NAME := {
	Phase.DAWN: "清晨",
	Phase.DAY: "白天",
	Phase.DUSK: "黄昏",
	Phase.NIGHT: "夜晚",
}

const SEASON_NAME := ["春", "夏", "秋", "冬"]

const DAY_START_HOUR := 6
const TOTAL_MINUTES := 1200                                    # 6:00 → 次日 2:00
const TICK_GAME_MINUTES := 10
const TICK_REAL_SECONDS := 6.0
const TICKS_PER_DAY := TOTAL_MINUTES / TICK_GAME_MINUTES       # 120
const DAYS_PER_SEASON := 28

## 光照关键帧：当日已过分钟 → 环境光颜色（GDD §1.2 环境光 RGB 列）
##
## 模型 = 平台 + 短过渡，不是全程线性渐变。
## GDD 要求白天 9:00–17:00 整段 #FFFFFF「无覆盖」，所以白天区间内不许染色。
## 过渡窗口固定 50 游戏分钟（50 × 0.6 = 30 现实秒），骑在时段交界处：
##   8:35 → 9:25  |  16:35 → 17:25  |  19:35 → 20:25
const LIGHT_KEYS: Array = [
	[0, Color("#FFD9A0")],      # 6:00  清晨起点
	[155, Color("#FFD9A0")],    # 8:35  清晨保持
	[205, Color("#FFFFFF")],    # 9:25  完成转白天
	[635, Color("#FFFFFF")],    # 16:35 白天保持
	[685, Color("#FF9B5A")],    # 17:25 完成转黄昏
	[815, Color("#FF9B5A")],    # 19:35 黄昏保持
	[865, Color("#2A3A6B")],    # 20:25 完成转夜晚
	[1200, Color("#2A3A6B")],   # 2:00  强制入睡
]

var day: int = 1
var season: int = 0        # 0 春 / 1 夏 / 2 秋 / 3 冬
var year: int = 1
var minutes: int = 0       # 当日已过游戏分钟，0 = 6:00
var phase: Phase = Phase.DAWN
var paused: bool = false

var _acc: float = 0.0

func _ready() -> void:
	phase = phase_at(minutes)

func _process(delta: float) -> void:
	if paused:
		return
	_acc += delta
	while _acc >= TICK_REAL_SECONDS:
		_acc -= TICK_REAL_SECONDS
		_tick()

func _tick() -> void:
	minutes += TICK_GAME_MINUTES
	EventBus.tick_advanced.emit(minutes)

	var p := phase_at(minutes)
	if p != phase:
		var old := phase
		phase = p
		EventBus.phase_changed.emit(old, p)

	if minutes >= TOTAL_MINUTES:
		_roll_day()

func _roll_day() -> void:
	# 2:00 强制入睡：这是「新的一天」的分界，也是自动存档点（GDD §10.5）
	EventBus.forced_sleep.emit()
	minutes = 0
	# ⚠️ 必须把时段也拉回清晨：_tick 在归零前已经把它推到了 NIGHT，
	#    不重置的话 6:00 一睁眼右上角会写「夜晚」，直到下一个 tick 才自愈。
	var p := phase_at(0)
	if p != phase:
		var old := phase
		phase = p
		EventBus.phase_changed.emit(old, p)
	day += 1
	if day > DAYS_PER_SEASON:
		day = 1
		season = (season + 1) % 4
		if season == 0:
			year += 1
		EventBus.season_changed.emit(season)
	EventBus.day_advanced.emit(day, season, year)

## 主动睡觉（模块 12）：和 2:00 强制入睡走同一套跨日逻辑，但**不**发 forced_sleep。
## 发 forced_sleep = 昏倒（要扣钱）；睡觉是正常行为，所以分成两个入口。
func sleep_next_day() -> void:
	minutes = 0
	var p := phase_at(0)
	if p != phase:
		var old := phase
		phase = p
		EventBus.phase_changed.emit(old, p)
	day += 1
	if day > DAYS_PER_SEASON:
		day = 1
		season = (season + 1) % 4
		if season == 0:
			year += 1
		EventBus.season_changed.emit(season)
	EventBus.day_advanced.emit(day, season, year)

## 当日已过分钟 → 时段
func phase_at(m: int) -> Phase:
	if m < 180:        # 6:00 – 9:00
		return Phase.DAWN
	if m < 660:        # 9:00 – 17:00
		return Phase.DAY
	if m < 840:        # 17:00 – 20:00
		return Phase.DUSK
	return Phase.NIGHT   # 20:00 – 2:00

## 当日已过分钟 → 环境光颜色
func light_color_at(m: int) -> Color:
	m = clampi(m, 0, TOTAL_MINUTES)
	for i in range(LIGHT_KEYS.size() - 1):
		var a: Array = LIGHT_KEYS[i]
		var b: Array = LIGHT_KEYS[i + 1]
		if m >= a[0] and m <= b[0]:
			var span: float = float(b[0] - a[0])
			var t: float = 0.0 if span <= 0.0 else float(m - a[0]) / span
			return (a[1] as Color).lerp(b[1] as Color, t)
	return LIGHT_KEYS[-1][1]

## 24 小时制时钟文本
func clock_text() -> String:
	var total := DAY_START_HOUR * 60 + minutes
	return "%02d:%02d" % [int(total / 60) % 24, total % 60]

func season_name() -> String:
	return SEASON_NAME[season]

func phase_name() -> String:
	return PHASE_NAME[phase_at(minutes)]

## 当前时段 —— 从 minutes 现算，**不要**读缓存的 phase。
## 缓存的 phase 只在 _tick / _roll_day 里更新，直接改 minutes（存档读档、调试）会让它过期。
func current_phase() -> Phase:
	return phase_at(minutes)

## 当日已过分钟 → 24 小时制的「时」（0-23）
func hour() -> int:
	return int((DAY_START_HOUR * 60 + minutes) / 60) % 24

## 当日已过分钟 → 24 小时制的「分」
func minute_of_day() -> int:
	return (DAY_START_HOUR * 60 + minutes) % 60

## 是否在放牧窗口（GDD §1.3：9:00–17:00）
func in_graze_window() -> bool:
	return phase_at(minutes) == Phase.DAY

## 调试用：跳到一个指定时刻（0 = 6:00）
func debug_set_minutes(m: int) -> void:
	minutes = clampi(m, 0, TOTAL_MINUTES - TICK_GAME_MINUTES)
	phase = phase_at(minutes)

# ---------------- 存档（模块 8）----------------

func to_dict() -> Dictionary:
	return {
		"day": day,
		"season": season,
		"year": year,
		"minutes": minutes,
		"acc": _acc,
	}

## ⚠️ phase 是**派生值**，不存也不该信存档里的。
##    读档后必须 phase_at(minutes) 重算 —— 模块 2 就踩过「缓存 phase 过期」的坑。
func from_dict(d: Dictionary) -> void:
	day = clampi(int(d.get("day", 1)), 1, DAYS_PER_SEASON)
	season = clampi(int(d.get("season", 0)), 0, 3)
	year = maxi(1, int(d.get("year", 1)))
	minutes = clampi(int(d.get("minutes", 0)), 0, TOTAL_MINUTES - TICK_GAME_MINUTES)
	_acc = clampf(float(d.get("acc", 0.0)), 0.0, TICK_REAL_SECONDS)
	phase = phase_at(minutes)
