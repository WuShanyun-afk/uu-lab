extends Node
## 模块 5 截图：觉醒对话 / 杂货铺 / 繁殖棚选父母 / 秘密花园
## 用法： godot --path <项目> res://tests/shot_module5.tscn

func _ready() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	var main := ps.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().physics_frame
	var p = main.get_node_or_null("World/YSortRoot/Player")

	# ---------- ① 觉醒对话（拟人化台词）----------
	var cow = main._herd.animals[0]
	if p != null:
		# ⚠️ 站位要贴着目标动物：围栏里动物挨得近，站偏了会被隔壁那只「抢焦点」
		#    （第一版站在 (560,268)，结果喂的是蜜蜂不是奶牛）。
		p.global_position = cow.pos + Vector2(-30, 0)
		p.facing = "right"
		p.facing8 = "right"
	cow.affection = 999
	cow.awakened = false
	cow.just_awakened = false
	cow.fed_today = 0
	main._handle_animal(Player.Tool.FEED)
	main._refresh_hud()
	for i in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module5_dialogue.png")
	main._dialogue.skip()
	await get_tree().process_frame

	# ---------- ② 杂货铺（饲料 / 药剂 / 木材）----------
	GameState.gold = 3000
	EventBus.shop_requested.emit(&"supply")
	for i in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module5_supply.png")
	main._shop.close()
	await get_tree().process_frame

	# ---------- ③ 繁殖棚：选父母 ----------
	GameState.set_flag(&"shed_built", true)
	main._shed.queue_redraw()
	for a in main._herd.animals:
		a.debug_grow_adult()
		if a.species == &"cow":
			a.affection = 900
	if p != null:
		p.global_position = Vector2(600, 320)
		p.facing = "up"
		p.facing8 = "up"
	# 先让探针跑几帧把底部交互提示刷新过来（弹窗期间玩家被冻住，提示不会更新）
	for i in range(4):
		await get_tree().physics_frame
	EventBus.shop_requested.emit(&"breed")
	for i in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module5_breeding.png")
	main._shop.close()
	await get_tree().process_frame

	# ---------- ④ 秘密花园（全部觉醒）----------
	for sp in [&"goat", &"pig", &"alpaca"]:
		var st = main._herd.add(sp, 0, main._free_spawn_pos())
		if st != null:
			st.debug_grow_adult()
	for a in main._herd.animals:
		a.debug_grow_adult()
		a.debug_awaken()
		a.just_awakened = false
	main._animal_layer.rebuild()
	main._sync_garden()
	while main._dialogue.is_open():
		main._dialogue.skip()
	if p != null:
		p.global_position = WorldConfig.GARDEN_ENTRY + Vector2(0, -40)
		p.facing = "up"
		p.facing8 = "up"
	main._zone_garden = true
	main._apply_camera_limits()
	main._refresh_hud()
	main._say("秘密花园 · 9 座石碑都亮了（金顶 = 已觉醒）")
	for i in range(24):
		await get_tree().physics_frame
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module5_garden.png")

	# ---------- ⑤ 幼崽成长（围栏里的幼年火鸡）----------
	main._zone_garden = false
	main._apply_camera_limits()
	if p != null:
		p.global_position = Vector2(600, 300)
		p.facing = "up"
		p.facing8 = "up"
	var baby = main._herd.animals[8]
	baby.days_old = 1
	main._animal_layer.rebuild()
	main._refresh_hud()
	main._say("第 9 只是幼年火鸡（缩放 %.2f）—— 5 天长成成年" % baby.body_scale())
	for i in range(20):
		await get_tree().physics_frame
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module5_baby.png")

	get_tree().quit()

func _shot(res_path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path(res_path)
	print("SHOT %dx%d %s %s" % [img.get_width(), img.get_height(), img.save_png(out), out])
