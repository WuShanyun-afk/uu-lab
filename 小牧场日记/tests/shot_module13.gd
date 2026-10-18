extends Node
## 附属模块 1 截图：**音频系统真的在跑**（面板 / 雨天 / 黄昏 / 屋内）
## 用法： godot --path <项目> res://tests/shot_module13.tscn
##
## ⚠️ 换场会 free 掉 current_scene，所以驱动挂在 root 上（和模块 11/12 同一套写法）。
## ⚠️ 音频本身截不出来 —— 所以每张图都带 F3 调试面板：BGM 曲名 / 环境音 /
##    选曲理由 / SFX 池占用，这些字就是「声音在响」的证据。

func _ready() -> void:
	SaveSystem.save_dir = "user://saves_shot13"
	GameState.reset()
	GameClock.day = 5
	GameClock.season = 1
	GameClock.minutes = 420              # 13:00 白天
	GameClock.phase = GameClock.phase_at(GameClock.minutes)
	WeatherSystem.today = WeatherSystem.Weather.CLEAR
	var driver := Driver.new()
	driver.name = "ShotDriver"
	get_tree().root.add_child.call_deferred(driver)
	# 和模块 11 复验同一个教训：不可 queue_free 自己（current_scene 会变 null、截图空白）
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")

class Driver extends Node:
	func _ready() -> void:
		await get_tree().process_frame
		await _settle(8)
		AudioDebugPanel.set_open(true)
		await _settle(4)
		# ① 白天牧场
		await _shot("res://_uu/shot_module13_day.png", "白天牧场")
		# ② 雨天：忧郁 BGM + 雨声环境音
		WeatherSystem.debug_set(WeatherSystem.Weather.RAIN)
		await _settle(30)
		await _shot("res://_uu/shot_module13_rain.png", "雨天")
		# ③ 黄昏：换曲但雨还没停
		WeatherSystem.debug_set(WeatherSystem.Weather.CLEAR)
		GameClock.minutes = 700          # 17:40 黄昏
		GameClock.phase = GameClock.phase_at(GameClock.minutes)
		AudioManager.refresh_bgm()
		await _settle(24)
		await _shot("res://_uu/shot_module13_dusk.png", "黄昏")
		# ④ 夜晚进屋：室内曲 + 木地板脚步声
		GameClock.minutes = 900          # 21:00 夜晚
		GameClock.phase = GameClock.phase_at(GameClock.minutes)
		SceneRouter.travel(&"house", &"door")
		await _settle(36)
		AudioManager.footstep(Vector2(120, 200))     # 走两步（木地板）
		await _settle(10)
		AudioManager.footstep(Vector2(160, 200))
		await _settle(10)
		await _shot("res://_uu/shot_module13_indoor.png", "夜晚屋内")
		print("AUDIO bgm=%s amb=%s scene=%s explain=%s" % [
			String(AudioManager.current_bgm()), String(AudioManager.current_ambience()),
			String(SceneRouter.current_id), AudioDebugPanel._label.text.replace("\n", " | ")])
		AudioDebugPanel.set_open(false)
		get_tree().quit()

	func _settle(frames: int) -> void:
		for i in range(frames):
			await get_tree().physics_frame
			await get_tree().process_frame

	func _shot(res_path: String, label: String) -> void:
		var cur := get_tree().current_scene
		var cur_path := "" if cur == null else cur.scene_file_path
		var img := get_viewport().get_texture().get_image()
		var out := ProjectSettings.globalize_path(res_path)
		print("SHOT[%s] scene=%s bgm=%s %s" % [label, cur_path,
			String(AudioManager.current_bgm()), str(img.save_png(out) == OK)])
