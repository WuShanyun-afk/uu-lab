extends Node
## 模块 1 截图：验证女角色立绘 + 真栅栏/门洞 + 告示牌 + 交互提示
## 用法： godot --path <项目> res://tests/shot_module1.tscn --resolution 1280x720

func _ready() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	var main := ps.instantiate()
	add_child(main)
	await get_tree().process_frame

	var p = main.get_node_or_null("World/YSortRoot/Player")
	var sign = main.get_node_or_null("World/SignPost")
	if p != null and sign != null:
		# 站在告示牌下方，面朝上 —— 触发「E 看告示牌」提示
		p.global_position = Vector2(sign.global_position.x, sign.global_position.y + 26)
		p.facing = "up"
		p.facing8 = "up"
	for i in range(20):
		await get_tree().physics_frame
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://_uu/shot_module1.png")
	print("SHOT1 %dx%d %s %s" % [img.get_width(), img.get_height(), img.save_png(out), out])

	# 第二张：走进牧场门洞，跟牛站一起
	if p != null:
		p.global_position = Vector2(576, 190)
		p.facing = "right"
		p.facing8 = "right"
		p._set_tool(Player.Tool.CAN)
	for i in range(20):
		await get_tree().physics_frame
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img2 := get_viewport().get_texture().get_image()
	var out2 := ProjectSettings.globalize_path("res://_uu/shot_module1_pen.png")
	print("SHOT2 %dx%d %s %s" % [img2.get_width(), img2.get_height(), img2.save_png(out2), out2])

	get_tree().quit()
