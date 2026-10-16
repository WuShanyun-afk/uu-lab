extends Node
## 模块 2 截图：右上角时钟面板 + 雨 / 雪 / 暴风雪 三种天气特效
## 用法： godot --path <项目> res://tests/shot_weather.tscn --resolution 1280x720

func _ready() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	var main := ps.instantiate()
	add_child(main)
	await get_tree().process_frame
	var p = main.get_node_or_null("World/YSortRoot/Player")
	if p != null:
		p.global_position = Vector2(300, 250)
		p.facing = "down"
		p.facing8 = "down"

	# 1. 雨 · 夏末黄昏
	_set_season(main, 1)
	GameClock.debug_set_minutes(700)
	WeatherSystem.debug_set(WeatherSystem.Weather.RAIN)
	await _settle()
	await _snap("res://_uu/shot_weather_rain.png")

	# 2. 雪 · 冬天白天
	_set_season(main, 3)
	GameClock.debug_set_minutes(420)
	WeatherSystem.debug_set(WeatherSystem.Weather.SNOW)
	await _settle()
	await _snap("res://_uu/shot_weather_snow.png")

	# 3. 暴风雪 · 冬天夜晚
	_set_season(main, 3)
	GameClock.debug_set_minutes(960)
	WeatherSystem.debug_set(WeatherSystem.Weather.SNOW, true)
	await _settle()
	await _snap("res://_uu/shot_weather_blizzard.png")

	get_tree().quit()

## 换季要广播，否则地面染色不会跟着变
func _set_season(main: Node, s: int) -> void:
	GameClock.season = s
	main._on_season(s)

func _settle() -> void:
	for i in range(30):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path(path)
	print("SHOT %dx%d %s %s" % [img.get_width(), img.get_height(), img.save_png(out), out])
