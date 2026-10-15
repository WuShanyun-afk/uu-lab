extends Node
## 里程碑 3 截图钩子：把玩家挪到牧场边，构造几种动物状态，存 PNG。
## 用法： godot --path <项目> res://tests/shot_animals.tscn --resolution 1280x720

func _ready() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	var main := ps.instantiate()
	add_child(main)
	await get_tree().process_frame

	var player = main.get_node_or_null("World/YSortRoot/Player")
	if player != null:
		player.position = Vector2(600, 200)

	var herd = main.get("_herd")
	if herd != null:
		for a in herd.animals:
			a.debug_grow_adult()
		# 一头可挤奶的奶牛、一只可捡蛋的鸡、一只饿的、一只生病的
		if herd.animals.size() >= 5:
			herd.animals[0].affection = 950      # 9 心 → 金星
			herd.animals[0].product_ready = true
			herd.animals[1].affection = 650      # 6 心 → 银星
			herd.animals[1].product_ready = false
			herd.animals[2].affection = 400
			herd.animals[2].product_ready = true
			herd.animals[3].affection = 150
			herd.animals[3].product_ready = false
			herd.animals[4].affection = 50
			herd.animals[4].sick = true
			# 让第 5 只显示为幼年（70% 缩放）
			herd.animals[4].days_old = 0
	var layer = main.get_node_or_null("World/YSortRoot/AnimalLayer")
	if layer != null:
		layer.refresh()

	for i in range(12):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://_uu/shot_animals.png")
	var err := img.save_png(out)
	print("SHOT size=%dx%d err=%s path=%s" % [img.get_width(), img.get_height(), err, out])
	get_tree().quit()
