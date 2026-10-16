extends Node
## 模块 4 截图：种子商店 / 动物商店 / 挤奶节奏条 / 九种动物
## 用法： godot --path <项目> res://tests/shot_module4.tscn

func _ready() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	var main := ps.instantiate()
	add_child(main)
	await get_tree().process_frame
	var p = main.get_node_or_null("World/YSortRoot/Player")

	# ---------- ① 种子商店 ----------
	if p != null:
		p.global_position = Vector2(416, 200)
		p.facing = "up"
		p.facing8 = "up"
	GameState.gold = 500
	main._refresh_hud()
	EventBus.shop_requested.emit(&"seed")
	for i in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module4_shop.png")

	# ---------- ② 动物商店（9 种）----------
	main._shop.close()
	await get_tree().process_frame
	EventBus.shop_requested.emit(&"animal")
	for i in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module4_animal_shop.png")

	# ---------- ③ 挤奶节奏条 ----------
	main._shop.close()
	await get_tree().process_frame
	var cow = main._herd.animals[0]
	cow.affection = 720
	cow.debug_feed_full()
	cow.debug_ready_produce()
	GameClock.debug_set_minutes(30)          # 6:30，窗口内
	main._start_minigame(cow, cow.data())
	for i in range(10):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module4_minigame.png")
	main._minigame._cancel()
	await get_tree().process_frame

	# ---------- ④ 九种动物同框 ----------
	main._minigame.visible = false
	var want := [&"goat", &"alpaca", &"pig", &"turkey"]
	for sp in want:
		var st = main._herd.add(sp, 600, main._free_spawn_pos())
		if st != null:
			st.debug_grow_adult()
			st.debug_ready_produce()
	main._animal_layer.rebuild()
	if p != null:
		p.global_position = Vector2(446, 140)
		p.facing = "right"
		p.facing8 = "right"
	main._refresh_hud()
	main._say("牧场：9 种动物 · 头顶心数 / 白泡=可收 / 黄点=饿 / 紫标=生病")
	for i in range(20):
		await get_tree().physics_frame
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module4_pen.png")

	get_tree().quit()

func _shot(res_path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path(res_path)
	print("SHOT %dx%d %s %s" % [img.get_width(), img.get_height(), img.save_png(out), out])
