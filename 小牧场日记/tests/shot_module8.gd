extends Node
## 模块 8 截图：F5 存档 / F9 读档（存档底座本身没有界面，能拍的就是「读档后世界还在」）
## 用法： godot --headless=false --path <项目> res://tests/shot_module8.tscn
##
## ⚠️ 截图脚本把 SaveSystem.save_dir 指到 user://saves_shot，
##    不会覆盖玩家真存档。

func _ready() -> void:
	SaveSystem.save_dir = "user://saves_shot"
	var ps: PackedScene = load("res://scenes/main.tscn")
	var main := ps.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().physics_frame
	var p = main.get_node_or_null("World/YSortRoot/Player")

	# ---------- ① 造一局「有进度」的场面，然后 F5 ----------
	GameState.add_gold(2500)
	GameState.add_item(&"turnip_gold", 3)
	GameState.set_tool_level(&"bag", 2)
	GameClock.day = 6
	GameClock.season = 1
	GameClock.minutes = 420
	GameClock.phase = GameClock.phase_at(GameClock.minutes)
	main._grid.till(Vector2i(6, 6))
	main._grid.plant(Vector2i(6, 6), &"turnip")
	main._grid.water(Vector2i(6, 6))
	main._herd.animals[0].gain_affection(200)
	main._proc.start(&"cheese", 1)
	main._refresh_hud()
	main._refresh_toolbar()
	main.get_node("UI/ClockPanel").refresh()     # 直接改时钟不会触发信号，手动刷
	_place(p, Vector2(384, 300), "down")
	_check_autosave_off()
	main._save_game(SaveSystem.SLOT_QUICK)
	await _settle(8)
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module8_save.png")

	# ---------- ② 把场面洗掉，再 F9 ----------
	GameState.reset()
	main._herd.animals.clear()
	main._proc = Processor.new(1)
	GameClock.day = 1
	GameClock.season = 0
	GameClock.minutes = 0
	main._player.global_position = Vector2(704, 288)
	main._refresh_hud()
	await _settle(4)
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module8_wiped.png")

	main._load_game(SaveSystem.SLOT_QUICK)
	await _settle(8)
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module8_loaded.png")

	main._say("F5 存档 · F9 读档 · 每天 2:00 自动存档（0 号槽）")
	await _settle(10)
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module8_hint.png")

	get_tree().quit()

## 截图期间别让自动存档掺进来
func _check_autosave_off() -> void:
	if SaveSystem.exists(SaveSystem.SLOT_AUTO):
		SaveSystem.delete_slot(SaveSystem.SLOT_AUTO)

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
