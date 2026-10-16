extends Node
## 模块 1 验收：核心框架与移动交互
## 运行： godot --headless --path <项目> res://tests/test_module1.tscn
##
## 覆盖（全部是断言，不是"看着像"）：
##   1. WorldConfig 单一数据源（地图尺寸 / 相机 limit / 围墙 / 门洞）
##   2. 8 方向移动的朝向量化（含 8 向 → 4 向立绘映射）
##   3. 相机跟随 + 场景边界限制
##   4. 真实物理碰撞：撞栅栏被挡 / 走门洞能过 / 地图边界有围墙
##   5. 交互系统：靠近出提示 → 按 E 触发 → 走远清空
##   6. 手持道具切换：数字键 / 滚轮 / 图集跟着换

var _fails: Array[String] = []

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails.append(label)
	print(("  [OK] " if cond else "  [FAIL] ") + label)

func _ready() -> void:
	print("=== 模块 1：核心框架与移动交互 ===")
	_test_world_config()
	_test_dir8()
	_test_art()

	var main := await _spawn_main()
	if main != null:
		_test_camera(main)
		await _test_collision(main)
		await _test_interaction(main)
		_test_tools(main)
		main.queue_free()
		await get_tree().process_frame

	var ok := _fails.is_empty()
	print("=== 结果：%s ===" % ("全部通过" if ok else "失败 %d 项" % _fails.size()))
	if not ok:
		for f in _fails:
			print("   ! " + f)
	get_tree().quit(0 if ok else 1)

# ---------------- 1. 世界数据源 ----------------

func _covered(p: Vector2) -> bool:
	for r in WorldConfig.fence_walls():
		if r.has_point(p):
			return true
	return false

func _test_world_config() -> void:
	print("[1] WorldConfig 单一数据源")
	_check(WorldConfig.MAP_PX == Vector2i(768, 448), "地图 768×448 px")
	_check(WorldConfig.MAP_PX == WorldConfig.MAP_TILES * WorldConfig.TILE, "MAP_PX 与格数自洽")
	_check(WorldConfig.camera_limits() == [0, 0, 768, 448], "相机 limit = 整张地图")
	_check(WorldConfig.fence_walls().size() == 5, "栅栏拆成 5 段（左边被门洞断成两截）")
	_check(WorldConfig.bounds_walls().size() == 4, "地图四边 4 面围墙")

	var pen := WorldConfig.PEN
	var cx := pen.get_center().x
	_check(_covered(Vector2(cx, pen.position.y + 3)), "栅栏上边有实体")
	_check(_covered(Vector2(cx, pen.end.y - 3)), "栅栏下边有实体")
	_check(_covered(Vector2(pen.end.x - 3, pen.get_center().y)), "栅栏右边有实体")
	_check(_covered(Vector2(pen.position.x + 3, pen.position.y + 20)), "栅栏左上段有实体")
	_check(_covered(Vector2(pen.position.x + 3, pen.end.y - 20)), "栅栏左下段有实体")
	_check(not _covered(Vector2(pen.position.x + 3, 192)), "左边 y=192 是门洞（无实体）")
	_check(not _covered(WorldConfig.GATE.get_center()), "门洞中心点不在任何栅栏里")

# ---------------- 2. 8 方向 ----------------

func _test_dir8() -> void:
	print("[2] 8 方向移动")
	_check(Player.dir8_of(Vector2(1, 0)) == "right", "(1,0) → right")
	_check(Player.dir8_of(Vector2(0, 1)) == "down", "(0,1) → down")
	_check(Player.dir8_of(Vector2(-1, 0)) == "left", "(-1,0) → left")
	_check(Player.dir8_of(Vector2(0, -1)) == "up", "(0,-1) → up")
	_check(Player.dir8_of(Vector2(1, 1)) == "down_right", "(1,1) → down_right")
	_check(Player.dir8_of(Vector2(-1, 1)) == "down_left", "(-1,1) → down_left")
	_check(Player.dir8_of(Vector2(-1, -1)) == "up_left", "(-1,-1) → up_left")
	_check(Player.dir8_of(Vector2(1, -1)) == "up_right", "(1,-1) → up_right")
	_check(Player.dir8_of(Vector2.ZERO) == "down", "零输入 → 保持 down")
	# 斜向输入也是 8 向里的合法值（归一化后角度不变）
	_check(Player.dir8_of(Vector2(3, 3).normalized()) == "down_right", "斜向归一化后仍是 down_right")
	# 8 向 → LPC 4 向立绘
	_check(Player.cardinal_of("down_right") == "down", "down_right → 立绘 down")
	_check(Player.cardinal_of("up_left") == "up", "up_left → 立绘 up")
	_check(Player.cardinal_of("right") == "right", "right → 立绘 right")

# ---------------- 立绘素材 ----------------

func _test_art() -> void:
	print("[3] 立绘素材（女 · 白皮 · Q 萌）")
	var plain: SpriteFrames = load("res://assets/characters/player.tres")
	var can: SpriteFrames = load("res://assets/characters/player_can.tres")
	_check(plain != null and plain.get_animation_names().size() == 16, "player.tres 16 套动画")
	_check(can != null and can.has_animation("watering_down"), "player_can.tres 有 watering_down")
	if can != null and can.has_animation("watering_down"):
		var tex: Texture2D = can.get_frame_texture("watering_down", 0)
		_check(tex != null and tex.get_width() == 64, "浇水帧 64×64（实际 %s）" %
			("null" if tex == null else "%d" % tex.get_width()))
	var csv := FileAccess.get_file_as_string("res://assets/characters/player_credits.csv")
	_check(csv.contains("/female"), "立绘是女性基底（credits 里有 /female）")
	_check(csv.contains("overalls"), "穿着背带裤（农家妹套装）")

# ---------------- 主场景 ----------------

func _spawn_main() -> Node:
	print("[4] 主场景结构")
	var ps: PackedScene = load("res://scenes/main.tscn")
	_check(ps != null, "main.tscn 可加载")
	if ps == null:
		return null
	var m := ps.instantiate()
	add_child(m)
	await get_tree().process_frame
	await get_tree().physics_frame
	return m

func _test_camera(main: Node) -> void:
	print("[5] 相机跟随 + 场景边界")
	var p: Player = main.get_node_or_null("World/YSortRoot/Player")
	_check(p != null, "主场景里有玩家")
	if p == null:
		return
	var cam: Camera2D = p.get_node_or_null("Camera2D")
	_check(cam != null, "相机挂在玩家身上（跟随）")
	if cam == null:
		return
	_check(cam.limit_left == 0 and cam.limit_top == 0, "相机左上 limit = 0,0")
	_check(cam.limit_right == WorldConfig.MAP_PX.x and cam.limit_bottom == WorldConfig.MAP_PX.y,
		"相机右下 limit = 地图右下（%d,%d）" % [cam.limit_right, cam.limit_bottom])
	_check(cam.position_smoothing_enabled, "开了平滑跟随")

func _test_collision(main: Node) -> void:
	print("[6] 真实物理碰撞")
	var p: Player = main.get_node("World/YSortRoot/Player")
	var wall: Node = main.get_node_or_null("World/WorldCollision")
	_check(wall != null, "有 WorldCollision 静态碰撞体")
	if wall == null:
		return
	var expect: int = WorldConfig.fence_walls().size() + WorldConfig.bounds_walls().size()
	_check(wall.get_child_count() == expect, "碰撞形状数 = 围墙 4 + 栅栏 5 = %d（实际 %d）"
		% [expect, wall.get_child_count()])

	# 栅栏左墙上段（y 70–160）：往左走应被挡住
	p.global_position = Vector2(530, 120)
	await get_tree().physics_frame
	_check(p.test_move(p.global_transform, Vector2(-12, 0)), "y=120 撞栅栏 → 被挡住")
	# 门洞（y 160–224）：同一个动作应该穿得过去
	p.global_position = Vector2(530, 192)
	await get_tree().physics_frame
	_check(not p.test_move(p.global_transform, Vector2(-12, 0)), "y=192 是门洞 → 能穿过去")
	# 地图边界（玩家碰撞盒在 y-10..y，所以贴到 y=12 再往上顶一定能撞上）
	p.global_position = Vector2(40, 12)
	await get_tree().physics_frame
	_check(p.test_move(p.global_transform, Vector2(0, -12)), "地图上边界有围墙")

# ---------------- 交互系统 ----------------

func _test_interaction(main: Node) -> void:
	print("[7] 交互系统")
	var p: Player = main.get_node("World/YSortRoot/Player")
	var sign: Node = main.get_node_or_null("World/SignPost")
	var bin: Node = main.get_node_or_null("World/ShippingBin")
	_check(sign != null and sign.is_in_group("interactable"), "告示牌注册进 interactable 组")
	_check(bin != null and bin.is_in_group("interactable"), "出货箱注册进 interactable 组")
	if sign == null or bin == null:
		return
	_check(sign.collision_layer == 2, "可交互物在碰撞层 2（玩家探针只扫这一层）")

	var label: Label = main.get_node_or_null("UI/Prompt")
	_check(label != null, "UI 里有 Prompt 提示标签")

	# 靠近告示牌 → 出提示
	p.global_position = Vector2(sign.global_position.x, sign.global_position.y + 26)
	p.facing = "up"
	p.facing8 = "up"
	for i in range(3):
		await get_tree().physics_frame
	_check(p.focus == sign, "走到告示牌前 → 聚焦到它")
	_check(label != null and label.text.contains("E"), "UI 出「E …」提示（实际「%s」）"
		% ("" if label == null else label.text))

	# 按 E → 触发 interact()
	var msgs: Array[String] = []
	EventBus.world_message.connect(func(t: String) -> void: msgs.append(t))
	var ev := InputEventKey.new()
	ev.keycode = KEY_E
	ev.pressed = true
	p._unhandled_input(ev)
	_check(msgs.size() == 1, "按 E 触发 interact()（收到 %d 条消息）" % msgs.size())

	# 走开 → 提示自动清空
	p.global_position = Vector2(120, 320)
	for i in range(3):
		await get_tree().physics_frame
	_check(p.focus == null, "走远 → 不再聚焦")
	_check(label != null and label.text == "", "提示自动清空")

	# 出货箱：背包 → 金币
	GameState.reset()
	GameState.add_item(&"turnip", 3)
	GameState.add_item(&"milk", 2)
	var before := GameState.gold
	var expect_gold: int = bin.unit_price(&"turnip") * 3 + bin.unit_price(&"milk") * 2
	p.global_position = Vector2(bin.global_position.x, bin.global_position.y + 26)
	p.facing = "up"
	p.facing8 = "up"
	for i in range(3):
		await get_tree().physics_frame
	_check(p.focus == bin, "走到出货箱前 → 聚焦到它")
	p._unhandled_input(ev)
	_check(GameState.gold == before + expect_gold, "出货换到 %dG（实际 +%d）"
		% [expect_gold, GameState.gold - before])
	_check(GameState.count_item(&"turnip") == 0 and GameState.count_item(&"milk") == 0,
		"出货后背包清空")

# ---------------- 道具切换 ----------------

func _test_tools(main: Node) -> void:
	print("[8] 手持道具切换")
	var p: Player = main.get_node("World/YSortRoot/Player")
	var seen: Array[int] = []
	EventBus.tool_changed.connect(func(t: int) -> void: seen.append(t))

	p._set_tool(Player.Tool.CAN)
	_check(p.current_tool == Player.Tool.CAN, "切到洒水壶")
	_check(seen.has(Player.Tool.CAN), "切工具广播了 tool_changed")
	_check(p.active_frames() == load("res://assets/characters/player_can.tres"), "拿壶 → 用洒水壶图集")
	p._set_tool(Player.Tool.SEED)
	_check(p.active_frames() == load("res://assets/characters/player.tres"), "拿种子 → 回空手图集")

	p._set_tool(Player.Tool.HAND)
	p._cycle_tool(1)
	_check(p.current_tool == Player.Tool.FERT, "滚轮循环 手(5) → 基础肥(6)")
	p._cycle_tool(-1)
	_check(p.current_tool == Player.Tool.HAND, "滚轮回退 6 → 手(5)")
	p._set_tool(Player.Tool.FERT_HIGH)
	p._cycle_tool(1)
	_check(p.current_tool == Player.Tool.HOE, "滚轮 高级肥(7) → 绕回 锄头(1)")
