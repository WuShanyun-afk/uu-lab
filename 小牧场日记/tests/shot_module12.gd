extends Node
## 模块 12 截图：施工中 / 竣工 / 屋内 Lv1 / 屋内 Lv3（厨房+地窖+家具）
## 用法： godot --path <项目> res://tests/shot_module12.tscn
##
## ⚠️ 换场会 free 掉 current_scene，所以驱动逻辑挂在 root 上（同模块 11 的写法）。
## ⚠️ SaveSystem.save_dir 指到 user://saves_shot12，不动玩家真存档。

func _ready() -> void:
	SaveSystem.save_dir = "user://saves_shot12"
	GameState.reset()
	GameClock.day = 6
	GameClock.season = 0
	GameClock.minutes = 300
	GameClock.phase = GameClock.phase_at(GameClock.minutes)
	var driver := Driver.new()
	driver.name = "ShotDriver"
	get_tree().root.add_child.call_deferred(driver)
	# 直接换到牧场场景：引导节点自己会被 change_scene 换掉，Driver 挂在 root 上不受影响
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")

class Driver extends Node:
	func _ready() -> void:
		await _settle(30)
		var m := get_tree().current_scene
		if m == null or not m.has_method("_try_place"):
			push_error("没进到牧场场景")
			get_tree().quit(1)
			return
		# 给足资源，把阶段抬到 5，好摆一整套建筑
		GameState.add_gold(200000)
		GameState.add_item(&"wood", 500)
		GameState.add_item(&"stone", 300)
		GameState.add_item(&"permit", 20)
		m._builds.stage = 5
		m._refresh_build_effects()
		# ① 施工中的工地（畜棚要 2 天，先别推进）
		m._try_place(&"barn", Vector2i(2, 8))
		m._try_place(&"coop", Vector2i(7, 8))
		m._tick_construction()          # 鸡舍 2 天 → 还剩 1 天；畜棚还剩 1 天
		_place_player(m, Vector2(180, 300), "up")
		m._refresh_hud()
		m._refresh_toolbar()
		await _settle(6)
		await _shot("res://_uu/shot_module12_site.png", "施工中")
		# ② 竣工（再推一天）
		m._tick_construction()
		await _settle(6)
		await _shot("res://_uu/shot_module12_built.png", "竣工")
		# ③ 屋内 Lv1
		GameState.house_level = 1
		SceneRouter.travel(&"house", &"door")
		await _settle(40)
		await _shot("res://_uu/shot_module12_house1.png", "屋内 Lv1")
		# ④ 屋内 Lv3：厨房 + 地窖 + 家具
		GameState.house_level = 3
		GameState.add_item(&"rug", 1)
		GameState.add_item(&"plant", 1)
		var room := get_tree().current_scene
		room._rebuild_house_props()
		GameState.add_furniture(&"rug", Vector2i(9, 7))
		GameState.add_furniture(&"plant", Vector2i(16, 6))
		room._player.global_position = Vector2(320, 250)
		room._player.position = Vector2(320, 250)
		room.queue_redraw()
		room._refresh_hud()
		room._say("Lv3：厨房做饭 · 地窖酿酒 · F 摆家具 · 床睡觉推进到次日")
		await _settle(8)
		await _shot("res://_uu/shot_module12_house3.png", "屋内 Lv3")
		# ⑤ 睡觉 → 次日（真实推进 + 自动存档）
		var before := GameClock.day
		room._sleep()
		await _settle(8)
		await _shot("res://_uu/shot_module12_sleep.png", "睡觉后")
		print("SLEEP day %d -> %d  自动档=%s  house_level=%d  家具=%d" % [before,
			GameClock.day, str(SaveSystem.exists(SaveSystem.SLOT_AUTO)),
			GameState.house_level, GameState.furniture_count()])
		get_tree().quit()

	func _place_player(m: Node, pos: Vector2, dir: String) -> void:
		var p = m.get_node_or_null("World/YSortRoot/Player")
		if p == null:
			return
		p.global_position = pos
		p.position = pos
		p.facing = dir
		p.facing8 = dir
		var cam := p.get_node_or_null("Camera2D")
		if cam != null:
			cam.reset_smoothing()

	func _settle(frames: int) -> void:
		for i in range(frames):
			await get_tree().physics_frame
			await get_tree().process_frame

	func _shot(res_path: String, label: String) -> void:
		var cur := get_tree().current_scene
		var img := get_viewport().get_texture().get_image()
		var out := ProjectSettings.globalize_path(res_path)
		print("SHOT[%s] scene=%s ok=%s" % [label,
			"" if cur == null else cur.scene_file_path, str(img.save_png(out))])
