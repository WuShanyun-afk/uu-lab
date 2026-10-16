extends Node
## 模块 3 截图：验证「种植循环」的视觉 —— 生长阶段 / 作物配色 / 肥料标记 / 季节门禁提示
## 用法： godot --path <项目> res://tests/shot_module3.tscn --resolution 1280x720

func _ready() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	var main := ps.instantiate()
	add_child(main)
	await get_tree().process_frame

	var grid = main._grid
	var p = main.get_node_or_null("World/YSortRoot/Player")

	# 试验田 4 行 × 8 列（每行一种当季作物）
	#   col 0..7 直接写 days_grown，做出「刚发芽 → 成熟」的连续进度条
	#   左 4 列基础肥 / 右 4 列高级肥 → 土壤上的肥力标记颜色不同
	# ⚠️ 不能靠 advance_day 造进度：它是全局的，会把整片地一起推进
	var crops := [&"turnip", &"potato", &"strawberry", &"cauliflower"]
	for row in range(4):
		for col in range(8):
			var cell := Vector2i(2 + col, 3 + row)
			grid.till(cell)
			grid.plant(cell, crops[row])
			grid.fertilize(cell, 1 if col < 4 else 2)
			var t = grid.tile_at(cell)
			# col 0..5 铺满生长进度，col 5..7 一律成熟（才能看到各自的果实色）
			var c: CropData = CropDB.get_crop(crops[row])
			t.days_grown = maxi(int(round(col * c.grow_days / 5.0)), c.grow_days if col >= 5 else 0)
			t.watered = (col % 2 == 0)

	# 一格枯死 + 一格枯萎，验证异常状态的美术
	var dead := Vector2i(11, 8)
	grid.till(dead)
	grid.plant(dead, &"potato")
	grid.tile_at(dead).dead = true
	var wither := Vector2i(12, 8)
	grid.till(wither)
	grid.plant(wither, &"potato")
	grid.tile_at(wither).dry_days = 2

	main._farm_layer.refresh()

	# 玩家站到试验田右边，拎着洒水壶
	if p != null:
		p.global_position = Vector2(360, 300)
		p.facing = "left"
		p.facing8 = "left"
		p._set_tool(Player.Tool.CAN)
		p.set_seed(&"strawberry")
	main._refresh_hud()
	main._refresh_toolbar()
	main._say("试验田：左 4 列基础肥 / 右 4 列高级肥 · 越往右越成熟")

	for i in range(20):
		await get_tree().physics_frame
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://_uu/shot_module3.png")
	print("SHOT3 %dx%d %s %s" % [img.get_width(), img.get_height(), img.save_png(out), out])

	# 第二张：春天选中南瓜 —— 抓住「非当季」的拒绝提示
	if p != null:
		p.set_seed(&"pumpkin")
		p.global_position = Vector2(300, 250)
	main._grid.till(Vector2i(11, 3))
	main._plant(Vector2i(11, 3))
	main._refresh_toolbar()
	for i in range(6):
		await get_tree().physics_frame
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img2 := get_viewport().get_texture().get_image()
	var out2 := ProjectSettings.globalize_path("res://_uu/shot_module3_season.png")
	print("SHOT4 %dx%d %s %s" % [img2.get_width(), img2.get_height(), img2.save_png(out2), out2])

	get_tree().quit()
