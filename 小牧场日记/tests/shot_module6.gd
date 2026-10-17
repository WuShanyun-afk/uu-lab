extends Node
## 模块 6 截图：棚舍分栏 / 畜舍提示 / 扩建到满级 / 动物商店容量门禁
## 用法： godot --path <项目> res://tests/shot_module6.tscn

func _ready() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	var main := ps.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().physics_frame
	var p = main.get_node_or_null("World/YSortRoot/Player")

	# ---------- ① 围栏全景：三栋 Lv1 棚舍 + 动物按物种分栏 ----------
	_place(p, Vector2(506, 190), "right")
	main._say("牧场分成三栏：畜舍（左）/ 禽舍（中）/ 蜂箱（右）· 动物自己住自己的")
	await _settle(20)
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module6_pen.png")

	# ---------- ② 站在畜舍前：底部提示「Lv1 · 3/4 只 · E 扩建」 ----------
	_place(p, Vector2(552, 146), "up")
	await _settle(12)
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module6_barn.png")

	# ---------- ③ 一路扩建到 Lv3（建筑长大 + 旗杆 + 圆窗） ----------
	GameState.gold = 6000
	GameState.add_item(&"wood", 120)
	main._on_housing_upgrade(&"barn")
	main._on_housing_upgrade(&"barn")
	main._on_housing_upgrade(&"coop")
	_place(p, Vector2(506, 190), "right")
	main._say("畜舍 Lv3（10 只 · 红墙+旗杆）· 禽舍 Lv2（9 只 · 栖木栏杆）")
	await _settle(20)
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module6_upgrade.png")

	# ---------- ④ 动物商店：禽舍满了 → 鸡/鸭/火鸡整行变灰 ----------
	GameState.gold = 3000
	while Housing.count_in(main._herd, &"coop") < HousingDB.capacity_at(
			&"coop", GameState.barn_level(&"coop")):
		main._herd.add(&"chicken", 0, main._free_spawn_pos(&"chicken"))
	main._animal_layer.rebuild()
	main._refresh_barns()
	main._refresh_hud()
	EventBus.shop_requested.emit(&"animal")
	await _settle(8)
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module6_shop.png")
	main._shop.close()

	get_tree().quit()

func _place(p, pos: Vector2, dir: String) -> void:
	if p == null:
		return
	p.global_position = pos
	p.facing = dir
	p.facing8 = dir

func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().physics_frame
		await get_tree().process_frame

func _shot(res_path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path(res_path)
	print("SHOT %dx%d %s %s" % [img.get_width(), img.get_height(), img.save_png(out), out])
