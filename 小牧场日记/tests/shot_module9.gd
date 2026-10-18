extends Node
## 模块 9 截图：建造模式 / 幽灵活 / 活红 / 已落地 / 阶段 HUD
## 用法： godot --path <项目> res://tests/shot_module9.tscn
##
## ⚠️ 截图脚本把 SaveSystem.save_dir 指到 user://saves_shot9，不动玩家真存档。

var _main: Node2D = null

func _ready() -> void:
	SaveSystem.save_dir = "user://saves_shot9"
	GameState.reset()
	GameClock.day = 9
	GameClock.season = 0
	GameClock.minutes = 360
	GameClock.phase = GameClock.phase_at(GameClock.minutes)
	var ps: PackedScene = load("res://scenes/main.tscn")
	_main = ps.instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().physics_frame

	# 造一局「已经扩建过」的场面：钱料给足，阶段先抬到 5 才能盖市场 / 小镇广场
	GameState.add_gold(60000)
	GameState.add_item(&"wood", 400)
	_main._builds.stage = 5
	_main._refresh_hud()
	await _settle(2)

	# ---------- ① 建造模式：幽灵预览（绿） ----------
	_main._toggle_build_mode()
	_select(&"fence")
	_place_player(Vector2(5 * 32 + 16, 9 * 32 + 16), "down")   # 面朝 (5,10)：空地
	_main._refresh_build_hint()
	await _settle(6)
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module9_build.png")

	# ---------- ② 幽灵预览（红）：对着牧场围栏 ----------
	_place_player(Vector2(15 * 32 + 16, 4 * 32 + 16), "right")  # 面朝 (16,4)：围栏里
	_main._refresh_build_hint()
	await _settle(6)
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module9_blocked.png")

	# ---------- ③ 一排已落地的建筑 ----------
	_main._toggle_build_mode()          # 退出建造模式，看正常世界
	for x in range(2, 8):
		_main._try_place(&"fence", Vector2i(x, 10))
	_main._try_place(&"coop", Vector2i(2, 8))
	_main._try_place(&"hive", Vector2i(5, 2))
	_main._try_place(&"workshop", Vector2i(8, 7))
	_main._try_place(&"market", Vector2i(12, 1))
	_main._try_upgrade(Vector2i(2, 8))   # 鸡舍 Lv2：屋顶上会多一个「能升级」箭头
	_main._try_upgrade(Vector2i(2, 8))
	_place_player(Vector2(4 * 32 + 16, 6 * 32 + 16), "down")
	_main._refresh_hud()
	_main._refresh_toolbar()
	await _settle(8)
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module9_placed.png")

	# ---------- ④ 阶段推进：HUD + 播报 ----------
	_main._builds.stage = 1
	_main._orders.completed = 5          # 完成订单数也够了，第 2 阶段门槛才齐
	GameState.add_gold(20000)
	GameState.bump_stat(GameState.ST_CRAFTED, 12)
	_main._tip_until = 0.0               # 清掉上一句提示，让阶段播报能立刻说出来
	_main._tip.text = ''
	await _settle(6)                     # _process 里把阶段推到 2 并播报
	_main._refresh_hud()
	_main._refresh_toolbar()
	await _settle(6)
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module9_stage.png")

	print("STAGE=%d  BUILDINGS=%d  节点=%d" % [_main._builds.stage,
		_main._builds.count(), _main._build_nodes.size()])
	get_tree().quit()

## 把建造菜单的选中项设成某个 id（截图要能指定画哪种幽灵）
func _select(id: StringName) -> void:
	var cat: Array = _main._build_catalog()
	var i := cat.find(id)
	if i >= 0:
		_main._build_pick = i
	_main._refresh_toolbar()
	_main._refresh_build_hint()

func _place_player(pos: Vector2, dir: String) -> void:
	var p = _main.get_node_or_null("World/YSortRoot/Player")
	if p == null:
		return
	p.global_position = pos
	p.position = pos
	p.facing = dir
	p.facing8 = dir
	# 相机跟着玩家：直接改位置不会触发平滑，强制对齐一帧
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
