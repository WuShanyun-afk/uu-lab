class_name ClockHUD
extends Label
## 右上角时钟面板：天气 / 日期 / 时间 / 时段 / 明日预报（GDD §9.1 顶栏）
##
## 自己订阅 EventBus 的信号刷新，main.gd 一行都不用管它。
## 想换排版只改这一个文件，不碰任何玩法代码。

func _ready() -> void:
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	EventBus.tick_advanced.connect(_on_tick)
	EventBus.phase_changed.connect(_on_phase)
	EventBus.day_advanced.connect(_on_day)
	EventBus.weather_changed.connect(_on_weather)
	refresh()

func _on_tick(_m: int) -> void:
	refresh()

func _on_phase(_old: int, _new: int) -> void:
	refresh()

func _on_day(_d: int, _s: int, _y: int) -> void:
	refresh()

func _on_weather(_today: int, _prev: int) -> void:
	refresh()

func refresh() -> void:
	var lines: Array[String] = []
	lines.append("%s  %s" % [WeatherSystem.weather_icon(), WeatherSystem.weather_name()])
	lines.append("第 %d 年 %s季 %d 日" % [GameClock.year, GameClock.season_name(), GameClock.day])
	lines.append("%s   %s" % [GameClock.clock_text(), GameClock.phase_name()])
	if WeatherSystem.has_forecast():
		lines.append("明日 %s %s" % [
			WeatherSystem.weather_icon(WeatherSystem.forecast),
			WeatherSystem.weather_name(WeatherSystem.forecast),
		])
	text = "\n".join(lines)
