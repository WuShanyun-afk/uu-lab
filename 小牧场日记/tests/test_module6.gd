extends Node
## 模块 6 验收：畜舍建筑（分栏 + 棚舍）· 动物美术换装
##
## 需求对照：
##   ① 畜舍建筑：三栋可扩建的棚舍，容量决定能养几只；动物按物种自动分栏
##   ② 动物美术换装：9 种动物全部换成 32×32 真素材（占位 _draw 自动退居兜底）
##
## 运行： godot --headless --path <项目> res://tests/test_module6.tscn

var _fails: Array[String] = []
var _n := 0

func _check(cond: bool, label: String) -> void:
	_n += 1
	if not cond:
		_fails.append(label)
	print(("  [OK] " if cond else "  [FAIL] ") + label)

func _ready() -> void:
	print("=== 模块 6 验收：畜舍建筑 + 动物美术 ===")
	_test_housing_db()
	_test_housing_rules()
	_test_zones()
	await _test_main()
	_test_art()
	var ok := _fails.is_empty()
	print("=== 结果：%s（共 %d 项）===" % ["全部通过" if ok else "失败 %d 项" % _fails.size(), _n])
	if not ok:
		for f in _fails:
			print("   ! " + f)
	get_tree().quit(0 if ok else 1)

# ---------------- 1. 棚舍表 ----------------

func _test_housing_db() -> void:
	print("[1] 棚舍表（HousingDB）")
	_check(HousingDB.all_ids().size() == 3, "3 类棚舍（%d）" % HousingDB.all_ids().size())
	for id in [&"barn", &"coop", &"hive"]:
		_check(HousingDB.has(id), "表里有 %s" % id)
		_check(HousingDB.name_of(id) != "", "%s 有中文名（%s）" % [id, HousingDB.name_of(id)])
		_check(HousingDB.price_of(id) > 0, "%s 有造价（%dG）" % [id, HousingDB.price_of(id)])
		_check(HousingDB.material_of(id) == &"wood", "%s 用木材" % id)
		_check(HousingDB.max_level_of(id) == 3, "%s 最高 3 级" % id)

	# 容量公式：base + step × (lv - 1)
	_check(HousingDB.capacity_at(&"barn", 1) == 4, "畜舍 Lv1 = 4")
	_check(HousingDB.capacity_at(&"barn", 2) == 7, "畜舍 Lv2 = 7")
	_check(HousingDB.capacity_at(&"barn", 3) == 10, "畜舍 Lv3 = 10")
	_check(HousingDB.capacity_at(&"coop", 1) == 6, "禽舍 Lv1 = 6")
	_check(HousingDB.capacity_at(&"coop", 3) == 12, "禽舍 Lv3 = 12")
	_check(HousingDB.capacity_at(&"hive", 1) == 3, "蜂箱 Lv1 = 3")
	_check(HousingDB.capacity_at(&"hive", 3) == 7, "蜂箱 Lv3 = 7")
	_check(HousingDB.capacity_at(&"barn", 0) == 0, "没盖 = 0 容量")

	# 扩建价 / 木材：price × lv
	_check(HousingDB.upgrade_price(&"barn", 0) == 900, "畜舍从无到有 900G")
	_check(HousingDB.upgrade_price(&"barn", 1) == 900, "畜舍 Lv1→2 900G")
	_check(HousingDB.upgrade_price(&"barn", 2) == 1800, "畜舍 Lv2→3 1800G")
	_check(HousingDB.upgrade_material_count(&"barn", 1) == 15, "畜舍 Lv1→2 木材 15")
	_check(HousingDB.upgrade_material_count(&"barn", 2) == 30, "畜舍 Lv2→3 木材 30")
	_check(HousingDB.cost_text(&"barn", 1).contains("木材"),
		"cost_text 写明木材：%s" % HousingDB.cost_text(&"barn", 1))

	# 开局总容量必须装得下开局那 9 只，否则第一天就卡死
	var total := 0
	for id in HousingDB.all_ids():
		total += HousingDB.capacity_at(id, 1)
	_check(total >= 9, "Lv1 总容量 %d ≥ 开局 9 只" % total)

# ---------------- 2. 归属与容量判定 ----------------

func _test_housing_rules() -> void:
	print("[2] 归属与容量判定（Housing 纯逻辑）")
	_check(Housing.housing_of(&"cow") == &"barn", "奶牛住畜舍")
	_check(Housing.housing_of(&"pig") == &"barn", "猪住畜舍")
	_check(Housing.housing_of(&"chicken") == &"coop", "鸡住禽舍")
	_check(Housing.housing_of(&"bee") == &"hive", "蜜蜂住蜂箱")
	_check(Housing.housing_of(&"nope") == &"", "不认识的物种返回空")
	# 9 种动物必须全都能落到 3 种棚舍之一（漏一个就永远买不了）
	var orphan: Array[String] = []
	for id in AnimalDB.all_ids():
		if not HousingDB.has(Housing.housing_of(id)):
			orphan.append(String(id))
	_check(orphan.is_empty(), "9 种动物都有棚舍归属（漏 %s）" % str(orphan))

	var herd := Herd.new(1)
	herd.add(&"cow", 0, Vector2.ZERO)
	herd.add(&"chicken", 0, Vector2.ZERO)
	herd.add(&"bee", 0, Vector2.ZERO)
	_check(Housing.count_in(herd, &"barn") == 1, "畜舍里有 1 只")
	_check(Housing.count_in(herd, &"coop") == 1, "禽舍里有 1 只")
	_check(Housing.count_in(herd, &"hive") == 1, "蜂箱里有 1 只")

	_check(Housing.can_house(&"cow", herd, {}) == Housing.Reason.NO_BUILDING,
		"没盖棚舍 → NO_BUILDING")
	var b := {&"barn": 1, &"coop": 1, &"hive": 1}
	_check(Housing.can_house(&"cow", herd, b) == Housing.Reason.OK, "Lv1 畜舍 1/4 → 还能进")

	for i in range(3):
		herd.add(&"cow", 0, Vector2.ZERO)
	_check(Housing.count_in(herd, &"barn") == 4, "畜舍塞到 4 只")
	_check(Housing.can_house(&"cow", herd, b) == Housing.Reason.FULL, "4/4 → FULL")
	_check(Housing.can_house(&"cow", herd, {&"barn": 2}) == Housing.Reason.OK,
		"升到 Lv2（7 只）又能进")
	_check(Housing.can_house(&"nope", herd, b) == Housing.Reason.UNKNOWN, "未知物种 → UNKNOWN")

	_check(Housing.reason_text(Housing.Reason.FULL) != "",
		"FULL 有人话：%s" % Housing.reason_text(Housing.Reason.FULL))
	_check(Housing.reason_text(Housing.Reason.NO_BUILDING) != "",
		"NO_BUILDING 有人话：%s" % Housing.reason_text(Housing.Reason.NO_BUILDING))

	var sum := Housing.summary_text(herd, b)
	_check(sum.contains("畜4/4") and sum.contains("禽1/6") and sum.contains("蜂1/3"),
		"HUD 摘要：%s" % sum)
	_check(Housing.total_capacity(b) == 4 + 6 + 3, "总容量 = 13（%d）" % Housing.total_capacity(b))

# ---------------- 3. 分栏几何 ----------------

func _test_zones() -> void:
	print("[3] 分栏几何（WorldConfig 唯一真相）")
	var pen := WorldConfig.PEN
	var ids := [&"barn", &"coop", &"hive"]
	for id in ids:
		var z := WorldConfig.zone_rect(id)
		_check(pen.encloses(z), "%s 活动区在围栏内（%s）" % [id, z])
		var slot := WorldConfig.barn_slot(id)
		_check(pen.has_point(slot), "%s 建筑在围栏内（%s）" % [id, slot])
		_check(z.position.y > slot.y, "%s 活动区在建筑下方（%.0f > %.0f）" % [id, z.position.y, slot.y])

	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			_check(not WorldConfig.zone_rect(ids[i]).intersects(WorldConfig.zone_rect(ids[j])),
				"%s 与 %s 不重叠" % [ids[i], ids[j]])

	var total_w := 0.0
	for id in ids:
		total_w += WorldConfig.zone_rect(id).size.x
	_check(total_w >= pen.size.x - 24.0, "三块横向铺满（%.0f / %.0f）" % [total_w, pen.size.x])
	_check(WorldConfig.barn_slot(&"barn").x < WorldConfig.barn_slot(&"coop").x
		and WorldConfig.barn_slot(&"coop").x < WorldConfig.barn_slot(&"hive").x,
		"三栋建筑从左到右排")

	_check(WorldConfig.zone_rect(&"nope") == pen, "未知棚舍退回整块围栏（兜底不崩）")
	_check(WorldConfig.zone_at(Vector2(540, 200)) == &"barn", "坐标 540,200 属于畜舍区")
	_check(WorldConfig.zone_at(Vector2(700, 200)) == &"hive", "坐标 700,200 属于蜂箱区")
	_check(WorldConfig.zone_at(Vector2(1, 1)) == &"", "围栏外不属于任何区")

# ---------------- 4. main 集成 ----------------

func _test_main() -> void:
	print("[4] main 集成：三栋棚舍 + 容量门禁")
	GameState.reset()
	EventBus.ui_modal = false
	var ps: PackedScene = load("res://scenes/main.tscn")
	_check(ps != null, "main.tscn 可加载")
	if ps == null:
		return
	var main := ps.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().physics_frame

	# --- 三栋建筑 ---
	var nodes: Array = main._barn_nodes()
	_check(nodes.size() == 3, "场景里有 3 栋棚舍（%d）" % nodes.size())
	var got := {}
	for n in nodes:
		got[n.housing_id] = n
	for id in [&"barn", &"coop", &"hive"]:
		_check(got.has(id), "有 %s 建筑节点" % id)
		if not got.has(id):
			continue
		var n: HousingBarn = got[id]
		_check(GameState.barn_level(id) == 1, "%s 开局 Lv1" % id)
		_check(n.position.is_equal_approx(WorldConfig.barn_slot(id)), "%s 位置来自 WorldConfig" % id)
		_check(n.used_slots == Housing.count_in(main._herd, id),
			"%s 占用数已填（%d）" % [id, n.used_slots])
		_check(n.prompt().contains("Lv1"), "%s 提示含等级：%s" % [id, n.prompt()])
		_check(n.prompt().contains("只"), "%s 提示含占用：%s" % [id, n.prompt()])

	# --- 开局牧群全在自己的栏里 ---
	var strayed: Array[String] = []
	for a in main._herd.animals:
		if not Housing.zone_rect(a.species).has_point(a.pos):
			strayed.append(String(a.species))
	_check(strayed.is_empty(), "开局 9 只全在自己的栏里（越界 %s）" % str(strayed))

	# --- HUD ---
	main._refresh_hud()
	var hud: Label = main.get_node("UI/HUD")
	_check(hud.text.contains("棚舍"), "HUD 有棚舍摘要")
	_check(hud.text.contains("畜3/4"), "HUD 畜舍 3/4（%s）" % hud.text.split("\n")[0])
	_check(hud.text.contains("禽5/6"), "HUD 禽舍 5/6（%s）" % hud.text.split("\n")[0])
	_check(hud.text.contains("蜂1/3"), "HUD 蜂箱 1/3（%s）" % hud.text.split("\n")[0])

	# --- 升级：钱和木材都够 ---
	GameState.gold = 5000
	GameState.add_item(&"wood", 100)
	var g0: int = GameState.gold
	var w0: int = GameState.count_item(&"wood")
	main._on_housing_upgrade(&"barn")
	_check(GameState.barn_level(&"barn") == 2, "畜舍升到 Lv2")
	_check(GameState.gold == g0 - 900, "扣 900G（实扣 %d）" % (g0 - GameState.gold))
	_check(GameState.count_item(&"wood") == w0 - 15, "扣木材 15（实扣 %d）" % (w0 - GameState.count_item(&"wood")))
	_check(HousingDB.capacity_at(&"barn", 2) == 7, "容量变 7")
	_check(got[&"barn"].prompt().contains("Lv2"), "建筑提示跟着变 Lv2：%s" % got[&"barn"].prompt())
	main._refresh_hud()
	hud = main.get_node("UI/HUD")
	_check(hud.text.contains("畜3/7"), "HUD 畜舍变 3/7（%s）" % hud.text.split("\n")[0])

	main._on_housing_upgrade(&"barn")
	_check(GameState.barn_level(&"barn") == 3, "再升一次到 Lv3")
	main._on_housing_upgrade(&"barn")
	_check(GameState.barn_level(&"barn") == 3, "满级后升不动")
	_check(got[&"barn"].prompt().contains("满级"), "满级提示：%s" % got[&"barn"].prompt())

	# --- 钱不够 / 木材不够 ---
	var coop_lv: int = GameState.barn_level(&"coop")
	GameState.gold = 10
	main._on_housing_upgrade(&"coop")
	_check(GameState.barn_level(&"coop") == coop_lv, "钱不够不升级")
	GameState.gold = 5000
	GameState.remove_item(&"wood", GameState.count_item(&"wood"))
	main._on_housing_upgrade(&"coop")
	_check(GameState.barn_level(&"coop") == coop_lv, "木材不够不升级")
	GameState.add_item(&"wood", 50)

	# --- 商店容量门禁：把禽舍塞满 ---
	var cap: int = HousingDB.capacity_at(&"coop", GameState.barn_level(&"coop"))
	while Housing.count_in(main._herd, &"coop") < cap:
		main._herd.add(&"chicken", 0, main._free_spawn_pos(&"chicken"))
	_check(Housing.count_in(main._herd, &"coop") == cap, "禽舍塞满 %d 只" % cap)

	var chicken_entry := {}
	for e in main._animal_entries():
		if e["id"] == &"chicken":
			chicken_entry = e
	_check(not chicken_entry.is_empty(), "动物商店里有鸡")
	_check(not bool(chicken_entry.get("enabled", true)), "禽舍满了 → 鸡不可买")
	_check(str(chicken_entry.get("reason", "")).contains("满"),
		"写明了原因：%s" % chicken_entry.get("reason", ""))

	GameState.gold = 5000
	var g1: int = GameState.gold
	var n0: int = main._herd.count_species(&"chicken")
	main._on_buy(&"chicken")
	_check(GameState.gold == g1, "绕过 UI 直接买也扣不到钱")
	_check(main._herd.count_species(&"chicken") == n0, "鸡没多（%d）" % main._herd.count_species(&"chicken"))

	main._on_housing_upgrade(&"coop")
	main._on_buy(&"chicken")
	_check(main._herd.count_species(&"chicken") == n0 + 1,
		"扩建禽舍后能买进 1 只（%d → %d）" % [n0, main._herd.count_species(&"chicken")])

	# --- 出生落点分区 ---
	_check(WorldConfig.zone_rect(&"barn").has_point(main._free_spawn_pos(&"cow")),
		"奶牛的落点在畜舍区")
	_check(WorldConfig.zone_rect(&"coop").has_point(main._free_spawn_pos(&"chicken")),
		"鸡的落点在禽舍区")
	_check(WorldConfig.zone_rect(&"hive").has_point(main._free_spawn_pos(&"bee")),
		"蜜蜂的落点在蜂箱区")

	# --- 越界拉回 ---
	var stray: AnimalState = main._herd.animals[0]
	stray.pos = Vector2(10, 10)
	main._clamp_animals_to_zones()
	_check(Housing.zone_rect(stray.species).has_point(stray.pos),
		"越界的动物被拉回自己栏（%s）" % stray.pos)

	# --- 跨日不崩 ---
	EventBus.day_advanced.emit(2, 0, 1)
	await get_tree().process_frame
	_check(main._herd.size() >= 1, "跨日后牧群还在（%d 只）" % main._herd.size())
	main._refresh_barns()
	var sum_ok := true
	for n in main._barn_nodes():
		if n.used_slots != Housing.count_in(main._herd, n.housing_id):
			sum_ok = false
	_check(sum_ok, "跨日后建筑占用数仍与牧群一致")

	main.queue_free()
	await get_tree().process_frame

# ---------------- 5. 动物美术换装 ----------------

func _test_art() -> void:
	print("[5] 动物美术换装（32×32 真素材）")
	var miss: Array[String] = []
	for id in AnimalDB.all_ids():
		var path := "res://assets/sprites/animals/%s_32.png" % String(id)
		if not ResourceLoader.exists(path):
			miss.append(String(id))
			continue
		var tex: Texture2D = load(path)
		var size_ok := tex != null and tex.get_width() == 32 and tex.get_height() == 32
		_check(size_ok, "%s 是 32×32（%s）" % [id, "null" if tex == null
			else "%dx%d" % [tex.get_width(), tex.get_height()]])
	_check(miss.is_empty(), "9 种动物都有 32×32 素材（缺 %s）" % str(miss))

	# AnimalNode 认素材：setup 之后必须走 draw_texture 分支
	var st := AnimalState.new(&"cow_probe", &"cow", 1)
	var node := AnimalNode.new()
	add_child(node)
	node.setup(st)
	_check(node._has_sprite, "AnimalNode 用上了真素材（不再画占位方块）")
	_check(node._tex != null and node._tex.get_width() == 32, "纹理宽 32")
	node.queue_free()
	# 占位兜底：不存在的物种仍能安全 setup
	var st2 := AnimalState.new(&"ghost_probe", &"nope", 1)
	var node2 := AnimalNode.new()
	add_child(node2)
	node2.setup(st2)
	_check(not node2._has_sprite, "没有素材的物种退回 _draw 占位（不崩）")
	node2.queue_free()
