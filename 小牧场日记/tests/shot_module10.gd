extends Node
## 模块 10 截图：村民日程 / 对话框 / 送礼 / 剧情 / 结局
## 用法： godot --path <项目> res://tests/shot_module10.tscn
##
## ⚠️ 截图脚本把 SaveSystem.save_dir 指到 user://saves_shot10，不动玩家真存档。

var _main: Node2D = null

func _ready() -> void:
	SaveSystem.save_dir = "user://saves_shot10"
	GameState.reset()
	GameClock.day = 7                 # 第 7 天：旅行商人苏也会出摊
	GameClock.season = 0
	GameClock.minutes = 180           # 9:00 —— 玛莎看店、老周打铁、阿海打渔
	GameClock.phase = GameClock.phase_at(GameClock.minutes)
	var ps: PackedScene = load("res://scenes/main.tscn")
	_main = ps.instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().physics_frame

	# 给点好感，让 HUD / 名字牌上有心数
	_main._npcs.state(&"masa").points = 160
	_main._npcs.state(&"zhou").points = 210
	_main._npcs.state(&"chen").points = 90
	_main._npcs.state(&"mia").points = 60
	_main._npcs.state(&"masa").met = true
	_main._npcs.state(&"zhou").met = true
	_main._npcs.state(&"chen").met = true
	_main._update_npcs(true)
	_main._refresh_hud()

	# ---------- ① 集市：白天村民各在各的岗位上 ----------
	_place_player(Vector2(460, 300), "down")
	await _settle(6)
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module10_npcs.png")

	# ---------- ② 对话框：第一次和玛莎说话 ----------
	_main._on_npc_interacted(&"masa")
	await _settle(6)
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module10_dialogue.png")
	_drain()

	# ---------- ③ 送礼面板 ----------
	GameState.add_item(&"honey", 3)
	GameState.add_item(&"milk", 2)
	_main._gift_target = &"masa"
	_main._open_gift_panel(&"masa")
	await _settle(6)
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module10_gift.png")
	_main._shop.close()

	# ---------- ④ 剧情：A 线第 1 幕（老陈给信） ----------
	GameClock.day = 2
	GameClock.minutes = 720           # 18:00 —— 老陈在酒馆
	_main._npcs.state(&"chen").points = 60
	_main._update_npcs(true)
	_place_player(Vector2(160, 150), "up")
	_main._on_npc_interacted(&"chen")
	await _settle(6)
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module10_story.png")
	_drain()

	# ---------- ⑤ 隐藏结局：牧场之心 ----------
	_main._builds.stage = 5
	GameState.set_story_flag(&"quest_letter_done")
	GameState.set_story_flag(&"quest_secret_done")
	GameState.set_story_flag(&"quest_season_done")
	_main._story.quest_act[&"letter"] = 6
	_main._story.quest_act[&"secret"] = 5
	_main._story.quest_act[&"season"] = 5
	_main._refresh_story()
	await _settle(6)
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module10_ending.png")

	print("村民=%d 好感总=%d 剧情节点=%d 结局=%s" % [
		_main._npc_nodes.size(), _main._npcs.total_hearts(),
		_main._story.done.size(), str(_main._story.endings_seen)])
	get_tree().quit()

func _drain() -> void:
	var guard := 0
	while _main._dialogue.is_open() and guard < 40:
		_main._dialogue.skip()
		guard += 1

func _place_player(pos: Vector2, dir: String) -> void:
	var p = _main.get_node_or_null("World/YSortRoot/Player")
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

func _shot(res_path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path(res_path)
	print("SHOT %dx%d %s %s" % [img.get_width(), img.get_height(), img.save_png(out), out])
