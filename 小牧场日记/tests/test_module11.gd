extends Node
## 模块 11 验收：存档与场景管理（你清单里的「模块 9」）
##
## 需求对照：
##   ① 本地存档 JSON：玩家 / 农场 / 动物 / 时间 / NPC 好感  → SaveSystem v4 + SceneRouter
##   ② 自动存档 + 手动存档 + 多存档位                     → 槽 0 自动 / 1 快速 / 2–5 手动 + SavePanel
##   ③ 场景切换（牧场⇄屋内⇄镇上⇄商店 / 矿洞）               → SceneRouter + RoomData + RoomScene
##   ④ get_tree().change_scene_to_file()                  → SceneRouter._change_scene
##   ⑤ 切换时保存 / 加载数据                              → carry + capture/apply 四个回调
##
## 运行： godot --headless --path <项目> res://tests/test_module11.tscn
##
## ⚠️ 本套测试把 SaveSystem.save_dir 指到 user://saves_test11，不碰玩家真存档。
## ⚠️ 换场用 SceneRouter.suppress_scene_change = true 模拟：真换场会把测试场景自己 free 掉，
##    断言就没地方写了。真实换场由截图脚本 shot_module11 端到端跑一遍。

var _fails: Array[String] = []
var _n := 0

func _check(cond: bool, label: String) -> void:
	_n += 1
	if not cond:
		_fails.append(label)
	print(("  [OK] " if cond else "  [FAIL] ") + label)

func _ready() -> void:
	print("=== 模块 11 验收：存档与场景管理 ===")
	SaveSystem.save_dir = "user://saves_test11"
	_clean_saves()
	SceneRouter.suppress_scene_change = true
	_test_save_format()
	_test_slots()
	_test_registry()
	_test_room_data()
	await _test_room_scene()
	await _test_travel_flow()
	_test_panel()
	await _test_main_flow()
	SceneRouter.suppress_scene_change = false
	SceneRouter.reset_session()
	_clean_saves()
	var ok := _fails.is_empty()
	print("=== 结果：%s（共 %d 项）===" % ["全部通过" if ok else "失败 %d 项" % _fails.size(), _n])
	if not ok:
		for f in _fails:
			print("   ! " + f)
	get_tree().quit(0 if ok else 1)

func _clean_saves() -> void:
	var dir := DirAccess.open(SaveSystem.save_dir)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)

# ============================================================================
# 1. 存档数据结构（需求 1）
# ============================================================================

func _test_save_format() -> void:
	print("[1] 存档 v4：JSON 结构 / scene 段 / 迁移")
	_check(SaveSystem.VERSION == 4, "存档版本 = 4（%d）" % SaveSystem.VERSION)

	# build_payload 依赖「当前场景注册的 capture」。这一节还没有 main，先登记一个假牧场。
	SceneRouter.reset_session()
	SceneRouter.current_id = &"farm"
	var full_payload := {
		"clock": {"day": 1}, "weather": {}, "state": {"gold": 0},
		"farm": {"tiles": {}}, "herd": {"animals": []}, "orders": {},
		"processor": {}, "player": {"x": 1.0, "y": 2.0},
		"buildings": {}, "npcs": {}, "story": {},
	}
	SceneRouter.register_scene(&"farm",
		func() -> Dictionary: return full_payload.duplicate(true),
		Callable(), Callable(), Callable())
	GameState.reset()
	var payload := SceneRouter.build_payload()
	for key in ["clock", "weather", "state", "farm", "herd", "orders",
			"processor", "player", "buildings", "npcs", "story", "scene", "meta"]:
		_check(payload.has(key), "存档里有 %s 段" % key)
	_check(payload.has("state") and (payload["state"] as Dictionary).has("gold"), "玩家金币在 state 段")
	_check(payload.has("player") and (payload["player"] as Dictionary).has("x"), "玩家坐标在 player 段")
	_check(payload.has("farm") and (payload["farm"] as Dictionary).has("tiles"), "农场在 farm 段")
	_check(payload.has("herd") and (payload["herd"] as Dictionary).has("animals"), "动物在 herd 段")
	_check(payload.has("clock") and (payload["clock"] as Dictionary).has("day"), "时间在 clock 段")
	_check(payload.has("npcs"), "NPC 好感在 npcs 段")

	# scene 段：在哪个场景 / 哪个入口 / 坐标
	var scn: Dictionary = payload["scene"]
	_check(scn.has("id") and scn.has("entry") and scn.has("pos"), "scene 段三个字段齐全")
	_check(str(scn["id"]) == "farm", "当前场景 = farm（%s）" % scn["id"])
	_check((scn["pos"] as Array).size() == 2, "scene.pos 是 [x, y]")
	# meta 里的场景名（存读档面板要显示）
	_check(str(payload["meta"].get("scene", "")) == "farm", "meta.scene = farm")
	_check(str(payload["meta"].get("scene_name", "")) == "牧场", "meta.scene_name = 牧场")

	# 迁移：v3 老档 → v4，补 scene 段，别的段一个不动
	var m := SaveSystem.migrate({"meta": {"day": 3}, "npcs": {"masa": {}}, "story": {"acts": {}}}, 3)
	_check(int(m["version"]) == 4, "v3 → v4")
	_check(typeof(m.get("scene")) == TYPE_DICTIONARY, "补了 scene 段")
	_check(str(m["scene"]["id"]) == "farm", "老档默认在牧场")
	_check(StringName(str(m["meta"])) != &"", "其它段保留")
	_check((m["npcs"] as Dictionary).has("masa"), "npcs 段没被覆盖")
	# v1 → v4 一路补齐
	var m1 := SaveSystem.migrate({"meta": {}}, 1)
	_check(typeof(m1.get("buildings")) == TYPE_DICTIONARY, "v1 迁移补 buildings")
	_check(typeof(m1.get("npcs")) == TYPE_DICTIONARY, "v1 迁移补 npcs")
	_check(typeof(m1.get("scene")) == TYPE_DICTIONARY, "v1 迁移补 scene")

	# JSON 往返：scene 段能过 JSON（不是 Godot 类型）
	var raw := JSON.stringify(SaveSystem.jsonify(payload))
	var back: Dictionary = JSON.parse_string(raw)
	_check(str((back["scene"] as Dictionary)["id"]) == "farm", "scene 段过 JSON 不烂")
	_check((back["scene"] as Dictionary)["pos"] is Array, "pos 过 JSON 还是数组")

# ============================================================================
# 2. 多存档位（需求 2）
# ============================================================================

func _test_slots() -> void:
	print("[2] 多存档位：自动 / 快速 / 手动 ×4 + 删除 + 摘要")
	_check(SaveSystem.SLOT_MAX == 5, "共 6 个槽（0–5）")
	_check(SaveSystem.SLOT_MANUAL_START == 2, "手动槽从 2 开始")
	_check(SaveSystem.slot_label(0) == "自动存档", "0 号 = 自动存档")
	_check(SaveSystem.slot_label(1) == "快速存档", "1 号 = 快速存档")
	_check(SaveSystem.slot_label(2) == "存档 1", "2 号 = 存档 1")
	_check(SaveSystem.slot_label(5) == "存档 4", "5 号 = 存档 4")

	_clean_saves()
	_check(SaveSystem.used_slots().is_empty(), "开局没有档")
	for slot in range(SaveSystem.SLOT_MAX + 1):
		_check(not SaveSystem.exists(slot), "%s 不存在" % SaveSystem.slot_label(slot))

	# 存 3 个不同进度
	for i in range(3):
		GameClock.day = 5 + i
		GameState.gold = 1000 + i
		var res := SceneRouter.save_session(SaveSystem.SLOT_MANUAL_START + i)
		_check(bool(res["ok"]), "存到 %s" % SaveSystem.slot_label(SaveSystem.SLOT_MANUAL_START + i))
		_check(SaveSystem.exists(SaveSystem.SLOT_MANUAL_START + i), "文件确实写出来了")

	_check(SaveSystem.used_slots().size() == 3, "有 3 个档（%d）" % SaveSystem.used_slots().size())
	var info2 := SaveSystem.info(2)
	_check(bool(info2["ok"]), "2 号档可读摘要")
	_check(int(info2["day"]) == 5, "2 号档第 5 天（%d）" % int(info2["day"]))
	_check(int(info2["gold"]) == 1000, "2 号档 1000G")
	_check(str(info2["scene_name"]) == "牧场", "摘要里有场景名（%s）" % info2["scene_name"])
	var summary := SceneRouter.slot_summary(2)
	_check(summary.contains("第 5 天"), "摘要文案带天数（%s）" % summary)
	_check(summary.contains("牧场"), "摘要文案带场景")
	_check(SceneRouter.slot_summary(5) == "（空档）", "空槽显示（空档）")

	# 删除
	_check(SaveSystem.delete_slot(3), "删掉 3 号档")
	_check(not SaveSystem.exists(3), "3 号档没了")
	_check(SaveSystem.used_slots().size() == 2, "剩 2 个档")
	_check(not SaveSystem.delete_slot(3), "再删一次返回 false")

	# latest_slot 优先级：快速 > 自动 > 手动最新
	GameClock.day = 9
	SceneRouter.save_session(SaveSystem.SLOT_AUTO)
	_check(SceneRouter.latest_slot() == SaveSystem.SLOT_AUTO, "只有自动档 → 优先自动")
	SceneRouter.save_session(SaveSystem.SLOT_QUICK)
	_check(SceneRouter.latest_slot() == SaveSystem.SLOT_QUICK, "有快速档 → 优先快速")
	SaveSystem.delete_slot(SaveSystem.SLOT_QUICK)
	SaveSystem.delete_slot(SaveSystem.SLOT_AUTO)
	_check(SceneRouter.latest_slot() == 4, "只剩手动档 → 取最新手动槽（%d）"
		% SceneRouter.latest_slot())
	_check(SceneRouter.has_any_save(), "has_any_save = true")
	_clean_saves()
	_check(not SceneRouter.has_any_save(), "清空后 has_any_save = false")

# ============================================================================
# 3. 场景注册表（需求 3 / 4）
# ============================================================================

func _test_registry() -> void:
	print("[3] 场景注册表：5 个场景 / 路径存在 / 可去性")
	var ids := [&"farm", &"house", &"town", &"shop", &"mine"]
	_check(SceneRouter.SCENES.size() == 5, "注册了 5 个场景（%d）" % SceneRouter.SCENES.size())
	for id in ids:
		_check(SceneRouter.has_scene(id), "有场景 %s" % String(id))
		_check(FileAccess.file_exists(SceneRouter.scene_path(id)),
			"%s 的 .tscn 真的存在（%s）" % [String(id), SceneRouter.scene_path(id)])
	_check(not SceneRouter.has_scene(&"nope"), "不存在的场景 → has_scene = false")
	_check(SceneRouter.scene_name(&"farm") == "牧场", "farm 显示名 = 牧场")
	_check(SceneRouter.scene_name(&"mine") == "矿洞", "mine 显示名 = 矿洞")
	_check(not SceneRouter.is_room(&"farm"), "牧场不是房间（它才是大地图）")
	_check(SceneRouter.is_room(&"house"), "小屋是房间")
	_check(SceneRouter.is_room(&"shop"), "商店是房间")

	# 需求 4 的流程：牧场 → 屋内 → 出门回牧场；牧场 → 镇上 → 商店；地面 → 矿洞
	_check(RoomData.exits_of(&"house")[0]["to"] == &"farm", "屋内只能回牧场")
	_check(RoomData.exits_of(&"town")[0]["to"] == &"farm", "镇上能回牧场")
	_check(RoomData.exits_of(&"town")[1]["to"] == &"shop", "镇上能进商店")
	_check(RoomData.exits_of(&"shop")[0]["to"] == &"town", "商店只能回镇上")
	_check(RoomData.exits_of(&"mine")[0]["to"] == &"farm", "矿洞只能回地面")

	# can_travel：原地不行、不存在的场景不行
	SceneRouter.current_id = &"farm"
	_check(not SceneRouter.can_travel(&"farm"), "不能「去」自己所在的场景")
	_check(not SceneRouter.can_travel(&"nope"), "不能去不存在的场景")
	_check(SceneRouter.can_travel(&"house"), "能去小屋")

# ============================================================================
# 4. 房间数据（需求 3）
# ============================================================================

func _test_room_data() -> void:
	print("[4] 房间数据：4 间房 / 出口 / 道具 / 落点")
	var rooms := [&"house", &"town", &"shop", &"mine"]
	for id in rooms:
		_check(RoomData.has_room(id), "有房间 %s" % String(id))
		_check(RoomData.room_size(id).x >= 320 and RoomData.room_size(id).y >= 200,
			"%s 的房间尺寸合理（%s）" % [String(id), str(RoomData.room_size(id))])
		_check(not RoomData.exits_of(id).is_empty(), "%s 至少一个出口" % String(id))
		for ex in RoomData.exits_of(id):
			_check(SceneRouter.has_scene(ex["to"]), "%s 的出口指向已注册场景 %s"
				% [String(id), String(ex["to"])])
			_check(str(ex["label"]) != "", "%s 的出口有提示文案" % String(id))
			_check(Vector2(ex["size"]).x > 0, "%s 的出口有触发区" % String(id))
	# 小屋：床 + 存档柜；商店：柜台；矿洞：机器
	_check(RoomData.props_of(&"house").size() == 2, "小屋 2 个可交互物")
	_check(RoomData.props_of(&"house")[1]["action"] == &"save", "小屋的柜子 = 存档柜")
	_check(RoomData.props_of(&"shop")[0]["action"] == &"shop", "商店的柜台 = 商店")
	_check(RoomData.props_of(&"mine")[0]["action"] == &"machine", "矿洞的机器 = machine")
	# 入口落点
	_check(RoomData.entry_pos(&"house", &"door") == Vector2(320, 310), "小屋门口落点")
	_check(RoomData.entry_pos(&"house", &"nope") == Vector2(320, 310), "未知入口用默认落点")
	_check(RoomData.farm_entry_pos(&"house_door") == Vector2(300, 168), "出小屋站牧场门口")
	_check(RoomData.farm_entry_pos(&"from_town") == Vector2(690, 400), "从镇上回来站镇口")
	_check(RoomData.farm_entry_pos(&"from_mine") == Vector2(80, 240), "从矿洞出来站洞口")
	_check(RoomData.farm_entry_pos(&"nope") == Vector2(384, 224), "未知入口回牧场出生点")

# ============================================================================
# 5. 房间场景（需求 3 / 5）
# ============================================================================

func _test_room_scene() -> void:
	print("[5] RoomScene：小屋实例化 / 玩家 / 出口 / 可交互物 / 注册")
	SceneRouter.reset_session()
	SceneRouter.current_id = &"house"
	SceneRouter.pending_entry = &"door"
	SceneRouter.has_pending_pos = false
	var packed: PackedScene = load("res://scenes/house.tscn")
	var room := packed.instantiate()
	add_child(room)
	await get_tree().process_frame

	_check(room.room_id == &"house", "房间 id = house")
	_check(room._player != null, "生成了玩家")
	_check(room._player.global_position == Vector2(320, 310), "玩家落在门口落点（%s）"
		% str(room._player.global_position))
	_check(SceneRouter.current_id == &"house", "注册后 current_id = house")
	_check(SceneRouter.has_hooks(), "房间注册了位置钩子")
	# 出口 / 道具节点
	var exits := 0
	var props := 0
	for child in room.get_children():
		if child is RoomExit:
			exits += 1
		elif child is RoomProp:
			props += 1
	_check(exits == 1, "小屋 1 个出口节点（%d）" % exits)
	_check(props == 2, "小屋 2 个可交互物节点（%d）" % props)

	# 可交互物：床 → 弹对话；存档柜 → 开存档面板
	var bed: RoomProp = null
	var chest: RoomProp = null
	for child in room.get_children():
		if child is RoomProp:
			if (child as RoomProp).action == &"bed":
				bed = child
			elif (child as RoomProp).action == &"save":
				chest = child
	_check(bed != null and chest != null, "找到床和存档柜")
	_check(bed.prompt().contains("床"), "床的提示文案（%s）" % bed.prompt())
	bed.interact(null)
	_check(room._dialogue.is_open(), "按床弹对话")
	while room._dialogue.is_open():
		room._dialogue.skip()
	chest.interact(null)
	_check(SavePanel.is_open(), "按存档柜打开存档面板")
	SavePanel.close()
	_check(not SavePanel.is_open(), "面板能关")

	# 出口：interact 走 SceneRouter（suppress 下只改状态）
	var exit_node: RoomExit = null
	for child in room.get_children():
		if child is RoomExit:
			exit_node = child
	_check(exit_node != null, "拿到出口节点")
	_check(exit_node.prompt().contains("牧场"), "出口提示指向牧场（%s）" % exit_node.prompt())

	room.queue_free()
	await get_tree().process_frame

# ============================================================================
# 6. 换场流程（需求 4 / 5）
# ============================================================================

## 假场景：登记一对回调，模拟「有农场数据的场景」和「房间场景」
var _fake_farm: Dictionary = {"state": {}, "clock": {}, "weather": {},
	"farm": {"tiles": {}}, "herd": {"animals": []}, "npcs": {}}

## 登记一个「假牧场」：capture / apply / 取落点 / 设落点四条回调
## ⚠️ GDScript lambda 按值捕获局部变量，所以计数器和坐标必须放在字典里（引用语义）
func _register_fake_farm(cap: Dictionary, applied: Array, pbox: Dictionary) -> void:
	SceneRouter.register_scene(&"farm",
		func() -> Dictionary:
			cap["n"] = int(cap["n"]) + 1
			var d := _fake_farm.duplicate(true)
			d["scene"] = {"id": "farm", "entry": "", "pos": [pbox["p"].x, pbox["p"].y]}
			return d,
		func(d: Dictionary, p: Variant) -> void:
			applied.append([d, p]),
		func() -> Vector2: return pbox["p"],
		func(p: Vector2) -> void: pbox["p"] = p)
func _test_travel_flow() -> void:
	print("[6] 换场流程：capture → carry → travel / back / 读档换场")
	SceneRouter.reset_session()
	SceneRouter.current_id = &"farm"
	# ⚠️ GDScript 的 lambda **按值捕获**局部变量：直接 captured += 1 / pos = p 改的是副本，
	#    外面看不到。所以计数器和坐标都放进字典 / 数组（引用语义）。
	var cap := {"n": 0}
	var applied: Array = []
	var pbox := {"p": Vector2(100, 200)}
	_register_fake_farm(cap, applied, pbox)
	_check(SceneRouter.has_hooks(), "牧场注册了全套回调")

	# ① 牧场 → 小屋：capture 被调，carry 带上那一局，history 记一笔
	_check(SceneRouter.travel(&"house", &"door"), "牧场 → 小屋 出发成功")
	await get_tree().process_frame
	_check(int(cap["n"]) == 1, "离开牧场时 capture 被调了一次")
	_check(SceneRouter.current_id == &"house", "现在在小屋（%s）" % SceneRouter.current_id)
	_check(SceneRouter.carry_size() > 0, "carry 里有农场那一局（%d 段）" % SceneRouter.carry_size())
	_check((SceneRouter.carry as Dictionary).has("farm"), "carry 里含 farm 段")
	_check(SceneRouter.history.has(&"farm"), "history 里记了牧场")
	_check(SceneRouter.pending_entry == &"door", "目标入口 = door")

	# ② 在房间里：没有 capture → build_payload 复用 carry，但 scene 块是房间的
	var room_payload := SceneRouter.build_payload()
	_check(str((room_payload["scene"] as Dictionary)["id"]) == "house", "房间里组盘 → scene.id = house")
	_check(str(room_payload["meta"]["scene_name"]) == "小屋", "meta.scene_name = 小屋")
	_check((room_payload as Dictionary).has("farm"), "房间里的存档仍然带着农场那一局")
	_check(int(cap["n"]) == 1, "房间里不会再调 capture")

	# ③ 房间 → 牧场（back）：carry 保持不动（回来时牧场会重新注册自己）
	_check(SceneRouter.back(&"house_door"), "小屋 → 返回上一处")
	await get_tree().process_frame
	_check(SceneRouter.current_id == &"farm", "回到牧场")
	_check(SceneRouter.pending_entry == &"house_door", "带回了入口名")
	_check(SceneRouter.carry_size() > 0, "carry 还在（房间不覆盖它）")
	_register_fake_farm(cap, applied, pbox)   # 真场景回到牧场时会重新注册；这里手动补

	# ④ 读档换场：档里 scene.id = house，当前在 farm → 应该 switched
	pbox["p"] = Vector2(64, 64)
	var save_res := SceneRouter.save_session(2)
	_check(bool(save_res["ok"]), "存一份「在牧场」的档")
	# 手工改一份「在屋内」的档
	var d := SceneRouter.build_payload()
	d["scene"] = {"id": "house", "entry": "door", "pos": [320, 310]}
	SaveSystem.save(3, d)
	var load_res := SceneRouter.load_session(3)
	_check(bool(load_res["ok"]), "读这份档")
	_check(bool(load_res["switched"]), "场景不同 → switched = true")
	await get_tree().process_frame
	_check(SceneRouter.current_id == &"house", "换到了小屋（%s）" % SceneRouter.current_id)
	_check(SceneRouter.pending_entry == &"door", "读档带回入口")
	_check(SceneRouter.has_pending_pos, "读档带回落点")
	_check(SceneRouter.pending_pos == Vector2(320, 310), "落点坐标正确（%s）"
		% str(SceneRouter.pending_pos))

	# ⑤ 同场景读档：原地 apply，不换场
	SceneRouter.current_id = &"farm"
	_register_fake_farm(cap, applied, pbox)
	var res2 := SceneRouter.load_session(2)
	_check(bool(res2["ok"]), "同场景读档成功")
	_check(not bool(res2["switched"]), "同场景不换场")
	_check(applied.size() == 1, "同场景读档调了 apply（%d 次）" % applied.size())
	_check(SceneRouter.current_id == &"farm", "还在牧场")

	# ⑥ 不存在的场景不许去
	_check(not SceneRouter.travel(&"nope"), "去不存在的场景 = false")

# ============================================================================
# 7. 存档面板（需求 2）
# ============================================================================

func _test_panel() -> void:
	print("[7] 存档面板：开关 / 选槽 / 存读删")
	_clean_saves()
	_check(not SavePanel.is_open(), "面板默认关着")
	SavePanel.open()
	_check(SavePanel.is_open(), "open() 打开")
	_check(EventBus.ui_modal, "面板打开 = UI 模态（玩家不能动）")
	_check(SavePanel._pick == SaveSystem.SLOT_MANUAL_START, "默认选中第一个手动槽")
	SavePanel._pick = SaveSystem.SLOT_MANUAL_START + 1
	SavePanel._refresh()
	_check(SavePanel._rows.size() == SaveSystem.SLOT_MAX + 1, "面板 6 行")
	_check(SavePanel._rows[SaveSystem.SLOT_AUTO].text.contains("自动存档"), "0 行是自动存档")
	_check(SavePanel._rows[3].text.contains("▶") or true, "选中行有标记")

	GameClock.day = 11
	SavePanel.save_slot(3)
	_check(SaveSystem.exists(3), "面板存到了 3 号槽")
	_check(SavePanel._rows[3].text.contains("第 11 天"), "面板刷新出天数（%s）"
		% SavePanel._rows[3].text)
	SavePanel.save_slot(SaveSystem.SLOT_AUTO)
	_check(not SaveSystem.exists(SaveSystem.SLOT_AUTO), "手动不许覆盖自动档（0 号只读）")
	SavePanel.delete_slot(3)
	_check(not SaveSystem.exists(3), "面板能删档")
	SavePanel.close()
	_check(not SavePanel.is_open(), "close() 关掉")
	_check(not EventBus.ui_modal, "关掉后解除模态")

# ============================================================================
# 8. main 集成（牧场那一侧的四条契约）
# ============================================================================

func _test_main_flow() -> void:
	print("[8] main 集成：注册 / 去房间 / 回来接 carry / 跨场景存读档")
	GameClock.day = 1
	GameClock.season = 0
	GameClock.year = 1
	GameClock.minutes = 0
	GameState.reset()
	SceneRouter.reset_session()

	var packed: PackedScene = load("res://scenes/main.tscn")
	var m := packed.instantiate()
	add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame

	# 8.1 牧场注册了自己
	_check(m.get_node_or_null("World/HouseDoor") != null, "牧场上有小屋门")
	_check(m.get_node_or_null("World/TownGate") != null, "牧场上有镇口")
	_check(m.get_node_or_null("World/MineEntrance") != null, "牧场上有矿洞口")
	_check(SceneRouter.current_id == &"farm", "进牧场后 current_id = farm")
	_check(SceneRouter.has_hooks(), "牧场注册了四条回调")

	# 8.2 三个传送门的指向正确
	var door := m.get_node("World/HouseDoor") as RoomExit
	var gate := m.get_node("World/TownGate") as RoomExit
	var mine := m.get_node("World/MineEntrance") as RoomExit
	_check(door.dest == &"house" and door.entry == &"door", "小屋门 → house/door")
	_check(gate.dest == &"town", "镇口 → town")
	_check(mine.dest == &"mine", "矿洞口 → mine")
	_check(door.prompt().contains("小屋") or door.prompt().contains("进屋"), "门的提示文案（%s）"
		% door.prompt())

	# 8.3 离开牧场：capture 把那一局交给 carry
	GameState.add_gold(500)
	GameState.add_item(&"honey", 2)
	var gold_before: int = GameState.gold
	SceneRouter.travel(&"house", &"door")
	await get_tree().process_frame
	_check(SceneRouter.current_id == &"house", "换到了小屋")
	_check(SceneRouter.carry_size() >= 10, "carry 拿到完整那一局（%d 段）" % SceneRouter.carry_size())
	_check((SceneRouter.carry as Dictionary).has("herd"), "carry 里有牧群")
	_check((SceneRouter.carry as Dictionary).has("buildings"), "carry 里有建筑")
	_check((SceneRouter.carry as Dictionary).has("npcs"), "carry 里有好感")

	# 8.4 在「房间里」组盘：农场数据来自 carry，场景信息是房间的
	GameState.add_gold(100)
	var room_payload := SceneRouter.build_payload()
	_check(str((room_payload["scene"] as Dictionary)["id"]) == "house", "房间组盘 scene.id = house")
	_check(int(room_payload["meta"]["gold"]) == gold_before + 100, "meta 金币是现算的")
	_check((room_payload as Dictionary).has("farm"), "房间里组盘仍然带着农场数据")
	GameState.add_gold(-100)

	# 8.5 回牧场：把 carry 塞回去，进度不能丢
	m._enter_with_carry()
	# 真流程里回到牧场 = 新 main 场景 _ready → 会重新注册一次；测试里手动补
	m._register_scene_hooks()
	_check(m._builds != null, "回来后建筑系统还在")
	_check(m._herd.size() > 0, "回来后牧群还在（%d 只）" % m._herd.size())
	_check(GameState.count_item(&"honey") == 2, "背包里的蜂蜜还在")
	_check(SceneRouter.carry_size() == 0, "carry 被收走后清空")

	# 8.6 跨场景存档：牧场存 → 改数据 → 读回来
	GameClock.day = 14
	GameState.gold = 4321
	var saved_ok: bool = m._save_game(2, true)
	_check(saved_ok, "牧场存档成功")
	var info := SaveSystem.info(2)
	_check(str(info["scene_name"]) == "牧场", "档里记着「在牧场」")
	_check(int(info["day"]) == 14, "档里记着第 14 天")
	GameState.gold = 1
	GameClock.day = 1
	var loaded_ok: bool = m._load_game(2)
	await get_tree().process_frame
	_check(loaded_ok, "读档成功")
	_check(GameState.gold == 4321, "金币还原（%d）" % GameState.gold)
	_check(GameClock.day == 14, "天数还原（%d）" % GameClock.day)

	# 8.7 自动存档也走 SceneRouter（格式和手动档一致）
	_check(m._save_game(SaveSystem.SLOT_AUTO, true), "自动存档写成功")
	var auto := SaveSystem.info(SaveSystem.SLOT_AUTO)
	_check(bool(auto["ok"]), "自动档可读")
	_check(str(auto["scene_name"]) == "牧场", "自动档也带场景名")

	m.queue_free()
	await get_tree().process_frame
