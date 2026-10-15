extends Node
## 渲染截图钩子：加载主场景，构造一份农场状态，存 PNG。
## 用法： godot --path <项目> res://tests/shot.tscn --resolution 1280x720
##
## ⚠️ 不要在这里用 advance_day() 逐格推进 —— 它是全局的，
##    给后面的格子推进天数会把前面长好的作物一起渴死。

func _mk(g, cell: Vector2i, crop: StringName, days: int, dry: int, wet: bool) -> void:
	g.till(cell)
	if crop != StringName(""):
		g.plant(cell, crop)
	var t = g.tile_at(cell)
	if t != null:
		t.days_grown = days
		t.dry_days = dry
		t.dead = dry >= 4
		t.watered = wet

func _ready() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	var main := ps.instantiate()
	add_child(main)
	await get_tree().process_frame

	var g = main.get("_grid")
	if g != null:
		var row := 8
		_mk(g, Vector2i(9, row), StringName(""), 0, 0, false)   # 干耕地
		_mk(g, Vector2i(10, row), StringName(""), 0, 0, true)   # 湿耕地
		_mk(g, Vector2i(11, row), &"turnip", 1, 0, true)        # 发芽（1/4 天）
		_mk(g, Vector2i(12, row), &"turnip", 4, 0, true)        # 成熟芜菁（4/4）
		_mk(g, Vector2i(13, row), &"potato", 3, 2, false)       # 枯萎（2 天没浇）
		_mk(g, Vector2i(14, row), &"spinach", 2, 4, false)      # 枯死（4 天没浇）
		# 再摆一格草莓长到一半，看中期形态
		_mk(g, Vector2i(15, row), &"strawberry", 5, 0, true)

		var fl = main.get_node_or_null("World/FarmLayer")
		if fl != null:
			fl.queue_redraw()

	for i in range(12):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://_uu/shot.png")
	var err := img.save_png(out)
	print("SHOT size=%dx%d err=%s path=%s" % [img.get_width(), img.get_height(), err, out])
	get_tree().quit()
