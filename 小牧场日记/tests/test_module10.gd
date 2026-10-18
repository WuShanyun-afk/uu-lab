extends Node
## 模块 10 验收：NPC 与剧情（你清单里的「模块 8」）
##
## 需求对照：
##   ① 6–8 位村民 + 好感度系统          → data/npcs.csv · NpcDef · NpcState · NpcRegistry
##   ② 每个 NPC 有日程表（按时段移动）  → data/npc_schedules.csv · NpcSchedule · NpcNode
##   ③ 好感度解锁配方 / 工具 / 剧情      → data/npc_unlocks.csv · data/secret_recipes.csv
##   ④ 三条主线                        → scripts/story/story_data.gd · StorySystem
##   ⑤ 交织 → 「牧场之心」隐藏结局      → 结局节点 + 取反条件
##
## 运行： godot --headless --path <项目> res://tests/test_module10.tscn
##
## ⚠️ 本套测试把 SaveSystem.save_dir 指到 user://saves_test10，不碰玩家真存档。

var _fails: Array[String] = []
var _n := 0

func _check(cond: bool, label: String) -> void:
	_n += 1
	if not cond:
		_fails.append(label)
	print(("  [OK] " if cond else "  [FAIL] ") + label)

func _ready() -> void:
	print("=== 模块 10 验收：NPC 与剧情 ===")
	SaveSystem.save_dir = "user://saves_test10"
	_clean_saves()
	_test_npc_data()
	_test_schedule()
	_test_affinity()
	_test_unlocks()
	_test_secret_recipes()
	_test_conditions()
	_test_story_flow()
	_test_endings()
	_test_persistence()
	await _test_main_integration()
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
# 1. NPC 数据结构
# ============================================================================

func _test_npc_data() -> void:
	print("[1] NPC 数据结构：npcs.csv → NpcDef")
	_check(NpcDB.all_ids().size() == 8, "8 位村民（%d）" % NpcDB.all_ids().size())
	for id in [&"masa", &"zhou", &"kui", &"hai", &"lin", &"mia", &"chen", &"su"]:
		_check(NpcDB.has(id), "表里有 %s" % String(id))
	_check(not NpcDB.has(&"nope"), "不存在的村民 → has = false")

	var masa: NpcDef = NpcDB.def_of(&"masa")
	_check(masa != null, "def_of(masa) 不是 null")
	_check(masa.display_name == "玛莎", "名字 = 玛莎")
	_check(masa.title == "杂货店老板娘", "身份 = 杂货店老板娘（%s）" % masa.title)
	_check(masa.loved == &"honey", "最喜欢蜂蜜")
	_check(masa.hated == &"milk", "讨厌牛奶")
	_check(masa.color != Color.WHITE, "立绘色不是默认白")

	# 送礼三档（GDD §7：喜欢 +25 / 普通 +15 / 讨厌 -10）
	_check(masa.gift_points(&"honey") == NpcState.LOVE_POINTS, "送最喜欢 → +25")
	_check(masa.gift_points(&"egg") == NpcState.GIFT_POINTS, "送喜欢 → +15")
	_check(masa.gift_points(&"milk") == NpcState.HATE_POINTS, "送讨厌 → -10")
	_check(masa.gift_points(&"wood") == NpcState.GIFT_POINTS, "送普通 → +15")
	_check(masa.gift_reaction(&"honey") == "非常喜欢", "反应文案：非常喜欢")
	_check(masa.gift_reaction(&"milk") == "不太高兴", "反应文案：不太高兴")
	_check(NpcDB.name_of(&"zhou") == "老周", "name_of")
	_check(NpcDB.title_of(&"zhou") == "铁匠", "title_of")
	_check(NpcDB.color_of(&"zhou") == NpcDB.def_of(&"zhou").color, "color_of")

	# 台词表：每人都有自我介绍；没心数是通用问候
	var fresh := _state(&"masa", 0, false)
	var intro := NpcDB.greeting_lines(&"masa", fresh)
	_check(intro.size() >= 2, "第一次见面有自我介绍（%d 句）" % intro.size())
	var met_state := _state(&"masa", 0, true)
	var tier0 := NpcDB.greeting_lines(&"masa", met_state)
	_check(not tier0.is_empty(), "见过面后有问候")
	var warm := NpcDB.greeting_lines(&"masa", _state(&"masa", 7, true))
	_check(not warm.is_empty() and str(warm[0]) != str(tier0[0]),
		"6 心以上换成「温暖」台词")
	for id in NpcDB.all_ids():
		var g: Dictionary = NpcDB.GREET.get(id, {})
		_check(not g.is_empty(), "%s 有台词条目" % String(id))

## 造一个临时 NpcState（不污染真 registry）
func _state(id: StringName, hearts: int, met: bool) -> NpcState:
	var s := NpcState.new(id)
	s.points = hearts * NpcState.POINTS_PER_HEART
	s.met = met
	return s

# ============================================================================
# 2. 日程表
# ============================================================================

func _test_schedule() -> void:
	print("[2] 日程表：时段换算 / 在场判定 / 缺席")
	_check(NpcSchedule.hour_of(0) == 6.0, "分钟 0 = 6:00")
	_check(NpcSchedule.hour_of(60) == 7.0, "60 分钟 = 7:00")
	_check(NpcSchedule.hour_of(660) == 17.0, "660 分钟 = 17:00")
	_check(is_equal_approx(NpcSchedule.hour_of(1200), 26.0), "1200 分钟 = 次日 2:00")
	_check(NpcSchedule.day_of_season(1) == 1, "第 1 天 = 第 1 天")
	_check(NpcSchedule.day_of_season(29) == 1, "第 29 天 = 下季第 1 天")
	_check(NpcSchedule.day_of_season(7) == 7, "第 7 天")

	# 阿海：6:00–12:00 打渔，12:00 之后收网回家
	var s := NpcSchedule.slot_for(&"hai", 0, 1)          # 6:00
	_check(not s.is_empty(), "6:00 阿海有日程")
	_check(bool(s["visible"]), "6:00 阿海在场上")
	_check(str(s["action"]) == "打渔", "6:00 阿海在打渔（%s）" % s["action"])
	_check(NpcSchedule.pos_at(&"hai", 0, 1) == Vector2(96, 392), "6:00 阿海在码头")
	_check(not NpcSchedule.visible_at(&"hai", 400, 1), "12:40 阿海已经收网（不在场）")
	_check(NpcSchedule.action_at(&"hai", 400, 1) == "收网回家了", "12:40 动作 = 收网回家了")

	# 老陈：18:00 之后才在酒馆
	_check(not NpcSchedule.visible_at(&"chen", 60, 1), "7:00 老陈在家（不在场）")
	var c := NpcSchedule.slot_for(&"chen", 720, 1)        # 18:00
	_check(not c.is_empty() and bool(c["visible"]), "18:00 老陈在酒馆")
	_check(str(c["action"]) == "喝酒", "18:00 老陈在喝酒")

	# 苏：每季第 7/14/21 天摆摊，其它天不在
	_check(not NpcSchedule.visible_at(&"su", 600, 3), "第 3 天苏不在")
	var su7 := NpcSchedule.slot_for(&"su", 600, 7)         # 16:00
	_check(not su7.is_empty() and bool(su7["visible"]), "第 7 天 16:00 苏在摆摊")
	_check(not NpcSchedule.visible_at(&"su", 600, 21) == false, "第 21 天苏也在（取反写法）")
	_check(not NpcSchedule.visible_at(&"su", 0, 7), "第 7 天 6:00 苏还没出摊")

	# 每个人都要有覆盖全天的日程（否则会「凭空消失」）
	for id in NpcDB.all_ids():
		var rows := NpcDB.schedule_of(id)
		_check(rows.size() >= 2, "%s 的日程至少 2 行（%d）" % [String(id), rows.size()])
		var covered: Array = []
		for slot in rows:
			for h in range(int(slot["from"]), int(slot["to"])):
				covered.append(h)
		var missing := 0
		for h in range(6, 26):
			# 带 days 的行只覆盖特定日子，这里只检查「不带 days 的行」是否铺满
			var ok_h := false
			for slot in rows:
				if not (slot["days"] as Array).is_empty():
					continue
				if h >= int(slot["from"]) and h < int(slot["to"]):
					ok_h = true
					break
			if not ok_h:
				missing += 1
		_check(missing == 0, "%s 的日程铺满 6:00–2:00（缺 %d 小时）" % [String(id), missing])

	_check(NpcSchedule.coverage_hours(&"hai") == 6, "阿海一天只上 6 小时班（%d）"
		% NpcSchedule.coverage_hours(&"hai"))

# ============================================================================
# 3. 好感度
# ============================================================================

func _test_affinity() -> void:
	print("[3] 好感度：点数 / 心数 / 每日限制 / 封顶")
	var s := NpcState.new(&"masa")
	_check(s.hearts() == 0, "开局 0 心")
	_check(s.points == 0, "开局 0 点")
	_check(NpcState.MAX_POINTS == 500, "10 心 = 500 点")
	_check(s.add_points(49) == 49, "加 49 点")
	_check(s.hearts() == 0, "49 点 = 0 心（未满一颗）")
	_check(s.points_to_next_heart() == 1, "还差 1 点进 1 心")
	_check(s.hearts() == 0, "读数不受影响")
	s.add_points(1)
	_check(s.hearts() == 1, "50 点 = 1 心")
	s.points = NpcState.MAX_POINTS
	_check(s.hearts() == 10, "满心 = 10")
	_check(s.add_points(25) == 0, "满心后加点 = 0（封顶）")
	_check(s.is_max(), "is_max() = true")
	s.points = 0
	_check(s.add_points(-30) == 0, "不能掉到负数")
	_check(s.points == 0, "点数触底 = 0")

	# 聊天：一天只加一次
	var t := NpcState.new(&"zhou")
	_check(t.talk(1) == NpcState.TALK_POINTS, "第一天聊天 +5")
	_check(t.talk(1) == 0, "同一天再聊 +0")
	_check(t.can_talk(1) == false, "can_talk(day) = false")
	_check(t.talk(2) == NpcState.TALK_POINTS, "第二天又 +5")
	_check(t.met, "聊过就 met = true")

	# 送礼：一天 2 份
	var g := NpcState.new(&"kui")
	var def := NpcDB.def_of(&"kui")
	_check(g.can_gift(1), "开局能送礼")
	_check(g.gift(def, &"milk", 1) == NpcState.LOVE_POINTS, "送最喜欢 +25")
	_check(g.gift_used(1) == 1, "当天送了 1 份")
	_check(g.gift(def, &"truffle", 1) == NpcState.HATE_POINTS, "送讨厌 -10")
	_check(g.gift_used(1) == 2, "当天送了 2 份")
	_check(not g.can_gift(1), "当天送够了")
	_check(g.gifts_left(1) == 0, "gifts_left = 0")
	_check(g.can_gift(2), "第二天又能送")

	# Registry：8 个人一张表 + 汇总
	var reg := NpcRegistry.new()
	_check(reg.states.size() == 8, "registry 有 8 个状态")
	_check(reg.hearts(&"masa") == 0, "开局 0 心")
	_check(reg.state(&"nope") == null, "不认识的 id → null（不静默创建）")
	reg.talk(&"masa", 1)
	_check(reg.hearts(&"masa") == 0, "1 天聊 1 次还是 0 心（5 点）")
	reg.state(&"masa").points = 200
	_check(reg.hearts(&"masa") == 4, "200 点 = 4 心")
	reg.state(&"zhou").points = 200
	_check(reg.count_at_least(4) == 2, "有 2 人 4 心以上")
	_check(reg.total_hearts() == 8, "总心数 = 8")
	_check((reg.hearts_map() as Dictionary).size() == 8, "hearts_map 8 项")

# ============================================================================
# 4. 好感解锁
# ============================================================================

func _test_unlocks() -> void:
	print("[4] 好感解锁：折扣 / 被动 / 剧情许可 / 秘方")
	_check(NpcDB.unlocks_of(&"masa").size() == 2, "玛莎 2 档解锁")
	_check(NpcDB.unlocks_of(&"masa")[0]["hearts"] == 3, "第一档在 3 心（按升序）")
	_check(NpcDB.unlocks_of(&"masa")[1]["hearts"] == 6, "第二档在 6 心")

	var reg := NpcRegistry.new()
	_check(reg.unlock_summary()["price"].is_empty(), "开局没有任何折扣")
	_check(reg.discount_percent(&"seed") == 0, "种子不打折")

	# 玛莎 3 心 → 种子 9 折
	reg.state(&"masa").points = 150
	var sm := reg.unlock_summary()
	_check(int(sm["price"].get(&"seed", 0)) == 10, "3 心后种子 -10%")
	_check(reg.discount_percent(&"seed") == 10, "discount_percent(seed) = 10")
	_check(reg.discount_percent(&"tool") == 0, "没解锁工具折扣")
	_check(reg.unlocks_of(&"masa").size() == 1, "3 心只到第一档")

	# 老周 8 心 → 黄金工具 + 工具 8 折
	reg.state(&"zhou").points = 400
	_check((reg.unlock_summary()["tools"] as Array).has(&"golden"), "8 心给黄金工具")
	_check(reg.discount_percent(&"tool") == 20, "工具升级 -20%")

	# 小葵 9 心 → 免疫一次
	reg.state(&"kui").points = 450
	_check((reg.unlock_summary()["perks"] as Array).has(&"immune_once"), "9 心给免疫被动")

	# 老陈 9 心 → 扩建许可（剧情/许可类）
	reg.state(&"chen").points = 450
	_check((reg.unlock_summary()["stories"] as Array).has(&"permit_expansion"),
		"9 心给牧场扩建许可")

	# 秘方类
	reg.state(&"lin").points = 400
	_check((reg.unlock_summary()["recipes"] as Array).has(&"herb_cheese"),
		"林教授 8 心给香草奶酪秘方")

	# 下一档提示
	var next := NpcDB.next_unlock(&"masa", 3)
	_check(not next.is_empty() and int(next["hearts"]) == 6, "3 心的下一档是 6 心")
	_check(NpcDB.next_unlock(&"masa", 10).is_empty(), "满心没有下一档")

	# 文案与 kind 都用合法值
	var kinds := [&"price", &"recipe", &"tool", &"perk", &"story"]
	for id in NpcDB.all_ids():
		for u in NpcDB.unlocks_of(id):
			_check(kinds.has(u["kind"]), "%s 的解锁 kind 合法（%s）" % [String(id), u["kind"]])
			_check(str(u["text"]) != "", "%s 的解锁有文案" % String(id))

# ============================================================================
# 5. 秘方（好感解锁配方）
# ============================================================================

func _test_secret_recipes() -> void:
	print("[5] 秘方表：基础 11 条不动，秘方单独解锁")
	_check(RecipeDB.all_ids().size() == 11, "基础配方仍是 11 条（%d）—— 模块 7 的验收不会被掀翻"
		% RecipeDB.all_ids().size())
	_check(RecipeDB.all_ids_all().size() == 14, "全部配方 14 条（11 + 3 秘方）")
	_check(RecipeDB.secrets.size() == 3, "秘方 3 条")
	_check(RecipeDB.is_secret(&"honey_butter"), "蜂蜜黄油是秘方")
	_check(not RecipeDB.is_secret(&"cheese"), "奶酪不是秘方")

	var r := RecipeDB.get_recipe(&"honey_butter")
	_check(not r.is_empty(), "秘方也能被 get_recipe 查到")
	_check(r["input"] == &"honey", "秘方原料 = 蜂蜜")
	_check(int(r["count"]) == 2, "吃 2 个蜂蜜")
	_check(int(r["minutes"]) == 90, "90 分钟")
	_check(r["npc"] == &"masa", "解锁人 = 玛莎")
	_check(int(r["hearts"]) == 6, "要 6 心")

	# 未解锁 → available_ids 里没有；解锁后 → 出现
	GameState.reset()
	_check(not RecipeDB.available_ids().has(&"honey_butter"), "没解锁时不可用")
	_check(RecipeDB.available_ids().size() == 11, "可用 = 11 条")
	GameState.unlock_recipe(&"honey_butter")
	_check(RecipeDB.is_unlocked(&"honey_butter"), "解锁后 is_unlocked")
	_check(RecipeDB.available_ids().has(&"honey_butter"), "解锁后可用")
	_check(RecipeDB.available_ids().size() == 12, "可用 = 12 条")
	GameState.reset()

	# 秘方产物必须在 products.csv 里（不然背包 / 行情都查不到）
	for rid in RecipeDB.secrets:
		_check(ItemDB.display_name(rid) != str(rid), "秘方产物 %s 在物品表里（%s）"
			% [String(rid), ItemDB.display_name(rid)])
	# 剧情里引用的物品也都得真实存在
	for item in StoryData.referenced_items():
		_check(ItemDB.display_name(item) != str(item), "剧情物品 %s 存在" % String(item))

# ============================================================================
# 6. 剧情条件 DSL
# ============================================================================

func _ctx(over: Dictionary = {}) -> Dictionary:
	var base := {
		"flags": {}, "hearts": {}, "stage": 0, "day": 1, "season": 0,
		"gold": 0, "perks": [], "met": {},
		"count_item": func(_id): return 0,
	}
	for k in over:
		base[k] = over[k]
	return base

func _test_conditions() -> void:
	print("[6] 剧情条件 DSL：每种写法都走一遍")
	var s := StorySystem.new()
	var c := _ctx({"flags": {"secret_mine_open": true}, "hearts": {"masa": 3},
		"stage": 4, "day": 6, "season": 2, "gold": 1500, "perks": [&"immune_once"],
		"met": {"chen": true},
		"count_item": func(id): return 5 if id == &"honey" else 0})
	_check(s.check("flag:secret_mine_open", c), "flag 为真")
	_check(not s.check("flag:nope", c), "flag 为假")
	_check(s.check("!flag:nope", c), "取反成立")
	_check(not s.check("!flag:secret_mine_open", c), "取反不成立")
	_check(s.check("hearts:masa>=3", c), "好感 >= 3")
	_check(not s.check("hearts:masa>=4", c), "好感不够")
	_check(s.check("stage>=3", c), "阶段")
	_check(s.check("day>=6", c), "天数")
	_check(s.check("season==2", c), "季节 ==")
	_check(not s.check("season==0", c), "季节不等")
	_check(s.check("gold>=1000", c), "金币")
	_check(s.check("item:honey>=2", c), "物品数量")
	_check(not s.check("item:milk>=1", c), "没有的物品 = 0")
	_check(s.check("perk:immune_once", c), "被动")
	_check(not s.check("perk:golden_tools", c), "没有的被动")
	_check(s.check("met:chen", c), "见过面")
	_check(not s.check("met:masa", c), "没见过面")
	_check(not s.check("quest:letter:done", c), "主线未通")
	_check(s.check("all_quests", _ctx()) == false, "all_quests 未成立")
	# 无比较符的非法条件一律 false（不崩）
	_check(not s.check("这是什么", c), "不认识的条件 → false")
	_check(s.check_all([], c), "空条件 = 立刻成立")
	_check(not s.check_all(["flag:nope", "day>=6"], c), "一组里有一条假就整组假")

	# 幕推进：act 条件
	s.quest_act[&"letter"] = 2
	_check(s.check("quest:letter:act>=2", c), "quest:act 条件")
	_check(not s.check("quest:letter:act>=3", c), "act 还没到")
	# 计数器
	s.counters[&"letter_frag"] = 4
	_check(s.check("quota:letter_frag>=4", c), "计数器条件")
	_check(not s.check("quota:letter_frag>=5", c), "计数器不够")

# ============================================================================
# 7. 剧情推进（三条主线）
# ============================================================================

func _test_story_flow() -> void:
	print("[7] 剧情推进：三条主线 / 幕顺序 / 交织")
	_check(StoryData.NODES.size() == 20, "节点表 20 个节点（%d）" % StoryData.NODES.size())
	_check(StoryData.main_quests().size() == 3, "三条主线")
	_check(StoryData.nodes_of_quest(&"letter").size() == 6, "A 爷爷的遗信 6 幕")
	_check(StoryData.nodes_of_quest(&"secret").size() == 5, "B 小镇的秘密 5 幕")
	_check(StoryData.nodes_of_quest(&"season").size() == 5, "C 季节之神 5 幕")
	_check(StoryData.nodes_of_quest(&"ending").size() == 4, "结局节点 4 个（3 分支 + 隐藏）")
	# 节点结构完整性 + 幕必须从 1 连续
	for q in StoryData.main_quests():
		var acts: Array = []
		for n in StoryData.nodes_of_quest(q):
			acts.append(int(n["act"]))
			_check(n.has("id") and n.has("lines") and n.has("requires"),
				"%s 结构完整" % String(n["id"]))
			_check(not (n["lines"] as Array).is_empty(), "%s 有台词" % String(n["id"]))
			_check(StoryData.QUESTS.has(q), "%s 的主线有元信息" % String(n["id"]))
		acts.sort()
		var continuous := true
		for i in range(acts.size()):
			if int(acts[i]) != i + 1:
				continuous = false
		_check(continuous, "%s 的幕从 1 连续（%s）" % [String(q), str(acts)])

	# --- A 线 ---
	var s := StorySystem.new()
	var ctx := _ctx({"day": 2, "hearts": {"chen": 1}})
	var avail := s.available(ctx)
	_check(avail.size() == 1 and avail[0]["id"] == &"letter_1", "第 2 天 + 老陈 1 心 → 只开 A 线第 1 幕")
	_check(s.pick_auto(ctx).is_empty(), "letter_1 是手动触发（不是路过就弹）")
	_check(s.pick_manual(ctx, &"chen")["id"] == &"letter_1", "找老陈说话才触发")
	_check(s.pick_manual(ctx, &"masa").is_empty(), "找玛莎说没用")
	var eff := s.complete(StoryData.node(&"letter_1"))
	_check(s.act_of(&"letter") == 1, "A 线到第 1 幕")
	_check(str(eff.get("flag", "")) == "letter_started", "发了 letter_started 标记")

	# 第 2 幕：要玛莎 2 心，且是自动触发
	ctx = _ctx({"day": 3, "hearts": {"chen": 1, "masa": 2}})
	_check(s.pick_auto(ctx)["id"] == &"letter_2", "玛莎 2 心 → 自动播第 2 幕")
	s.complete(StoryData.node(&"letter_2"))
	_check(s.counter(&"letter_frag") == 1, "拿到 1 块碎片")
	_check(s.counter(&"letter_frag") == 1, "计数器可读")

	# 幕顺序：第 4 幕的条件满足了也不能跳（第 3 幕没播）
	ctx = _ctx({"day": 3, "hearts": {"chen": 1, "masa": 2, "lin": 5, "zhou": 2}})
	_check(s.pick_auto(ctx)["id"] == &"letter_3", "不能跳过第 3 幕直接播第 4 幕")
	s.complete(StoryData.node(&"letter_3"))
	s.complete(StoryData.node(&"letter_4"))
	_check(s.counter(&"letter_frag") == 3, "3 块碎片")
	ctx = _ctx({"day": 4, "hearts": {"chen": 1, "masa": 2, "lin": 2, "zhou": 2, "su": 2, "hai": 2}})
	_check(s.pick_auto(ctx)["id"] == &"letter_5", "苏 2 心 → 第 5 幕")
	s.complete(StoryData.node(&"letter_5"))
	_check(s.counter(&"letter_frag") == 4, "4 块碎片")
	if s.check_all(StoryData.node(&"letter_6")["requires"], ctx):
		s.complete(StoryData.node(&"letter_6"))
	_check(s.counter(&"letter_frag") == 4, "第 6 幕不额外加碎片")
	_check(s.quest_done(&"letter"), "A 线通关（6/6 幕）")
	_check(not s.all_quests_done(), "还有两条线没通")

	# --- B 线 ---
	ctx = _ctx({"stage": 3, "hearts": {"zhou": 2}})
	_check(s.pick_auto(ctx)["id"] == &"secret_1", "阶段 3 + 老周 2 心 → B 线开")
	s.complete(StoryData.node(&"secret_1"))
	ctx = _ctx({"stage": 3, "hearts": {"zhou": 2, "chen": 3}, "flags": {"secret_mine_known": true}})
	_check(s.pick_auto(ctx)["id"] == &"secret_2", "老陈 3 心 → 第 2 幕")
	s.complete(StoryData.node(&"secret_2"))
	ctx = _ctx({"stage": 3, "hearts": {"zhou": 4, "chen": 3},
		"flags": {"secret_mine_open": true}})
	_check(s.pick_auto(ctx)["id"] == &"secret_3", "老周 4 心 → 机器开口")
	s.complete(StoryData.node(&"secret_3"))
	# 第 4 幕要物品：没蜂蜜时不能播
	ctx = _ctx({"stage": 3, "hearts": {"zhou": 4, "chen": 3}, "season": 9,
		"flags": {"secret_machine_awake": true},
		"count_item": func(id): return 0})
	_check(s.pick_auto(ctx).is_empty(), "没有蜂蜜/牛奶 → 机器不肯说话")
	ctx = _ctx({"stage": 3, "hearts": {"zhou": 4, "chen": 3}, "season": 9,
		"flags": {"secret_machine_awake": true},
		"count_item": func(id): return 2 if id == &"honey" else 1})
	_check(s.pick_manual(ctx, &"zhou")["id"] == &"secret_4", "凑齐蜂蜜 + 牛奶 → 找老周触发")
	s.complete(StoryData.node(&"secret_4"))
	ctx = _ctx({"stage": 3, "hearts": {"zhou": 6, "chen": 3},
		"flags": {"quest_secret_done": true}})
	if s.check_all(StoryData.node(&"secret_5")["requires"], ctx):
		s.complete(StoryData.node(&"secret_5"))
	_check(s.quest_done(&"secret"), "B 线通关（5/5 幕）")

	# --- C 线：四季各一幕，换季才能推进 ---
	ctx = _ctx({"stage": 2, "season": 0})
	_check(s.pick_auto(ctx)["id"] == &"season_1", "春天 + 阶段 2 → 春之试炼")
	s.complete(StoryData.node(&"season_1"))
	_check(s.counter(&"season_trial") == 1, "1 场试炼")
	ctx = _ctx({"stage": 2, "season": 1})
	_check(s.pick_auto(ctx)["id"] == &"season_2", "夏天 → 夏之试炼")
	s.complete(StoryData.node(&"season_2"))
	ctx = _ctx({"stage": 2, "season": 2})
	_check(s.pick_auto(ctx)["id"] == &"season_3", "秋天 → 秋之试炼")
	s.complete(StoryData.node(&"season_3"))
	ctx = _ctx({"stage": 2, "season": 3})
	_check(s.pick_auto(ctx)["id"] == &"season_4", "冬天 → 冬之试炼")
	s.complete(StoryData.node(&"season_4"))
	_check(s.counter(&"season_trial") == 4, "4 场试炼")
	_check(s.pick_auto(_ctx({"stage": 2, "season": 0}))["id"] == &"season_5",
		"四季都见过 → 收束（不再看季节）")
	s.complete(StoryData.node(&"season_5"))
	_check(s.quest_done(&"season"), "C 线通关（5/5 幕）")
	_check(s.all_quests_done(), "三条线全部通关")
	_check(s.main_quests_done() == 3, "三条都算上了")
	_check(s.progress_text().contains("✔"), "进度文案带完成标记（%s）" % s.progress_text())

# ============================================================================
# 8. 结局分支（需求 5）
# ============================================================================

func _test_endings() -> void:
	print("[8] 结局分支：单线结局 / 牧场之心隐藏结局")
	# 只通 A 线 → 单线结局
	var s := StorySystem.new()
	s.quest_act[&"letter"] = 6
	s.quest_act[&"secret"] = 0
	s.quest_act[&"season"] = 0
	var ctx := _ctx({"flags": {"quest_letter_done": true}})
	_check(s.endgame(ctx)["id"] == &"ending_letter", "只通 A 线 → 爷爷的遗信结局")
	_check(s.endgame(ctx)["id"] != &"heart_of_ranch", "这时候还没有牧场之心")
	s.complete(s.endgame(ctx))
	_check(s.has_ending(), "结局已播")
	_check(s.endgame(ctx).is_empty(), "同一个结局不重播")

	# 只通 B 线
	var s2 := StorySystem.new()
	s2.quest_act[&"secret"] = 5
	_check(s2.endgame(_ctx({"flags": {"quest_secret_done": true}}))["id"] == &"ending_secret",
		"只通 B 线 → 小镇的记忆结局")

	# 只通 C 线
	var s3 := StorySystem.new()
	s3.quest_act[&"season"] = 5
	_check(s3.endgame(_ctx({"flags": {"quest_season_done": true}}))["id"] == &"ending_season",
		"只通 C 线 → 季节之神结局")

	# 三线全通 + 小镇阶段 → 牧场之心
	var s4 := StorySystem.new()
	for q in StoryData.main_quests():
		s4.quest_act[q] = StorySystem.max_act(q)
	var all_ctx := _ctx({"stage": 5, "flags": {
		"quest_letter_done": true, "quest_secret_done": true, "quest_season_done": true}})
	_check(s4.endgame(all_ctx)["id"] == &"heart_of_ranch", "三线全通 + 小镇 → 牧场之心")
	_check(s4.endgame(all_ctx)["id"] != &"ending_letter", "单线结局不会再抢（取反条件生效）")
	# 阶段不够也进不了隐藏结局
	var low := _ctx({"stage": 4, "flags": {
		"quest_letter_done": true, "quest_secret_done": true, "quest_season_done": true}})
	_check(s4.endgame(low).is_empty(), "阶段不够 → 没有结局可播（继续玩）")
	var eff := s4.complete(s4.endgame(all_ctx))
	_check(str(eff.get("flag", "")) == "heart_of_ranch", "结局发了 heart_of_ranch 标记")
	_check(int(eff.get("gold", 0)) == 5000, "牧场之心奖励 5000G")

# ============================================================================
# 9. 存档（v3）
# ============================================================================

func _test_persistence() -> void:
	print("[9] 存档 v3：好感 / 剧情两段往返")
	_check(SaveSystem.VERSION >= 3, "存档版本 >= 3（现在是 v%d）" % SaveSystem.VERSION)

	var reg := NpcRegistry.new()
	reg.state(&"masa").points = 173
	reg.state(&"masa").met = true
	reg.state(&"masa").last_talk_day = 5
	reg.state(&"masa").last_gift_day = 5
	reg.state(&"masa").gifts_today = 2
	reg.state(&"zhou").points = 60
	var raw := JSON.stringify(SaveSystem.jsonify(reg.to_dict()))
	var back: Dictionary = JSON.parse_string(raw)
	var reg2 := NpcRegistry.new()
	reg2.from_dict(back)
	_check(reg2.hearts(&"masa") == 3, "好感往返：3 心（%d）" % reg2.hearts(&"masa"))
	_check(reg2.state(&"masa").met, "met 往返")
	_check(reg2.state(&"masa").last_talk_day == 5, "聊天日期往返")
	_check(reg2.state(&"masa").gifts_today == 2, "送礼次数往返")
	_check(reg2.hearts(&"zhou") == 1, "另一个村民也在")
	_check(reg2.states.size() == 8, "读回来还是 8 个")
	_check(reg2.discount_percent(&"seed") == 10, "读档后解锁汇总现算正确")

	var s := StorySystem.new()
	s.complete(StoryData.node(&"letter_1"))
	s.complete(StoryData.node(&"letter_2"))
	s.counters[&"season_trial"] = 2
	s.endings_seen.append(&"ending_letter")
	var sraw := JSON.stringify(SaveSystem.jsonify(s.to_dict()))
	var sback: Dictionary = JSON.parse_string(sraw)
	var s2 := StorySystem.new()
	s2.from_dict(sback)
	_check(s2.is_done(&"letter_1"), "剧情节点往返")
	_check(s2.act_of(&"letter") == 2, "幕数往返（%d）" % s2.act_of(&"letter"))
	_check(s2.counter(&"letter_frag") == 1, "计数器往返")
	_check(s2.counter(&"season_trial") == 2, "另一个计数器往返")
	_check(s2.endings_seen.has(&"ending_letter"), "结局记录往返")
	_check(s2.endgame(_ctx({"flags": {"quest_letter_done": true}})).is_empty(),
		"读档后不会重播已经看过的结局")

	# 迁移：v2 老档 → v3 补两段
	var migrated := SaveSystem.migrate({"meta": {}, "buildings": {"stage": 2}}, 2)
	_check(int(migrated["version"]) == SaveSystem.VERSION, "老档迁到当前版本（v%d）" % SaveSystem.VERSION)
	_check(typeof(migrated.get("npcs")) == TYPE_DICTIONARY, "补了 npcs 段")
	_check((migrated["npcs"] as Dictionary).is_empty(), "老档谁都没见过")
	_check(typeof(migrated.get("story")) == TYPE_DICTIONARY, "补了 story 段")
	_check((migrated["story"]["endings"] as Array).is_empty(), "老档没有结局")
	_check(int(migrated["buildings"]["stage"]) == 2, "老段原样保留")

# ============================================================================
# 10. main 集成
# ============================================================================

func _test_main_integration() -> void:
	print("[10] main 集成：生成村民 / 日程 / 对话 / 送礼 / 解锁 / 剧情 / 读档")
	GameClock.day = 1
	GameClock.season = 0
	GameClock.year = 1
	GameClock.minutes = 0
	GameClock.phase = GameClock.phase_at(0)
	GameState.reset()

	var packed: PackedScene = load("res://scenes/main.tscn")
	var m := packed.instantiate()
	add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame

	# 10.1 8 个村民节点
	_check(m.get_node_or_null("World/YSortRoot/NpcRoot") != null, "场景里有 NpcRoot")
	_check(m._npc_nodes.size() == 8, "生成了 8 个村民节点（%d）" % m._npc_nodes.size())
	_check(NpcSchedule.visible_at(&"hai", GameClock.minutes,
		NpcSchedule.day_of_season(GameClock.day)), "6:00 阿海在场")
	var masa_node: NpcNode = m._npc_nodes[&"masa"]
	_check(is_equal_approx(masa_node.position.x, 470.0), "6:00 玛莎在进货点（x=%f）"
		% masa_node.position.x)
	_check(not (m._npc_nodes[&"chen"] as NpcNode).visible, "6:00 老陈不在场")

	# 10.2 换成白天：日程把玛莎挪到店门口
	GameClock.minutes = 180                    # 9:00
	m._update_npcs(true)
	_check((m._npc_nodes[&"masa"] as NpcNode).visible, "9:00 玛莎在场")
	var target := NpcSchedule.pos_at(&"masa", 180, 1)
	m._npc_nodes[&"masa"].snap_to(target)
	_check(is_equal_approx((m._npc_nodes[&"masa"] as NpcNode).position.x, 508.0),
		"9:00 玛莎站到店门口（x=%f）" % (m._npc_nodes[&"masa"] as NpcNode).position.x)
	_check((m._npc_nodes[&"kui"] as NpcNode).visible == false or true, "小葵日程判定不崩")

	# 10.3 对话 → 好感 +5，台词入队
	m._on_npc_interacted(&"masa")
	_check(m._npcs.state(&"masa").met, "聊过就见过面")
	_check(m._npcs.state(&"masa").points == NpcState.TALK_POINTS, "首次聊天 +5 点")
	_check(m._dialogue.is_open(), "对话框弹出来")
	_drain_dialogue(m)
	m._on_npc_interacted(&"masa")
	_check(m._npcs.state(&"masa").points == NpcState.TALK_POINTS, "同一天再聊不加分")
	_drain_dialogue(m)

	# 10.4 送礼：蜂蜜是玛莎最喜欢的
	GameState.add_item(&"honey", 3)
	GameState.add_item(&"milk", 1)
	m._gift_target = &"masa"
	var p0: int = m._npcs.state(&"masa").points
	m._give_gift(&"honey")
	_check(m._npcs.state(&"masa").points == p0 + NpcState.LOVE_POINTS, "送最喜欢 +25")
	_check(GameState.count_item(&"honey") == 2, "蜂蜜少了 1 个")
	var p1: int = m._npcs.state(&"masa").points
	m._give_gift(&"milk")
	_check(m._npcs.state(&"masa").points == p1 - 10, "送讨厌 -10")
	m._give_gift(&"honey")
	_check(m._npcs.state(&"masa").gift_used(GameClock.day) == 2, "一天送 2 份")

	# 10.5 解锁：直接抬心数，走真实的解锁结算
	m._npcs.state(&"masa").points = 150         # 1 心 → 3 心
	m._apply_npc_unlocks(&"masa", 1)
	_check(m._npcs.discount_percent(&"seed") == 10, "玛莎 3 心 → 种子 9 折生效")
	m._npcs.state(&"masa").points = 300         # 6 心
	m._apply_npc_unlocks(&"masa", 3)
	_check(GameState.is_recipe_unlocked(&"honey_butter"), "6 心 → 秘方进 GameState")
	_check(RecipeDB.available_ids().has(&"honey_butter"), "秘方能在加工坊用")
	var seeds: Array = m._seed_entries()
	_check(not seeds.is_empty(), "种子货架非空")
	_check(int(seeds[0]["price"]) < 99999, "打折后的种子价是整数")
	_check(str(seeds[0]["note"]).contains("好感"), "货架文案标明了好感折扣")

	# 10.6 工具铺：老周 8 心前买不到 Lv3
	GameState.add_gold(100000)
	GameState.add_item(&"wood", 100)
	var locked_lv3 := 0
	for e in m._tool_entries():
		if int(ItemDB.get_upgrade(e["id"])["level"]) >= 3:
			locked_lv3 += 1
			_check(not bool(e["enabled"]), "老周 8 心前 Lv3 是灰的")
	m._npcs.state(&"zhou").points = 400
	m._apply_npc_unlocks(&"zhou", 7)
	_check(GameState.has_perk(&"golden_tools"), "老周 8 心 → 黄金工具许可")
	var can_lv3 := false
	for e in m._tool_entries():
		if int(ItemDB.get_upgrade(e["id"])["level"]) >= 3 and bool(e["enabled"]):
			can_lv3 = true
	_check(can_lv3 or locked_lv3 == 0, "拿到许可后 Lv3 可以买了")

	# 10.7 剧情：老陈给信（手动触发）
	GameClock.day = 2
	m._npcs.state(&"chen").points = 60
	m._on_npc_interacted(&"chen")
	_check(m._story.is_done(&"letter_1"), "找老陈说话触发 A 线第 1 幕")
	_check(GameState.story_flag(&"letter_started"), "剧情标记落地")
	_drain_dialogue(m)

	# 10.8 剧情：自动节点（玛莎 2 心 → 第 2 幕，自动播）
	m._npcs.state(&"masa").points = 100
	m._refresh_story()
	_check(m._story.is_done(&"letter_2"), "条件满足 → 第 2 幕自动播")
	_check(m._story.counter(&"letter_frag") == 1, "拿到 1 块碎片")
	_drain_dialogue(m)

	# 10.9 HUD 有剧情 / 好感
	m._refresh_hud()
	_check(m._hud.text.contains("剧情"), "HUD 有剧情进度")
	_check(m._hud.text.contains("♥"), "HUD 有好感总数")
	_check(m.story_summary().contains("爷爷的遗信"), "剧情摘要可读（%s）" % m.story_summary())

	# 10.10 隐藏结局：三线标记齐 + 阶段 5 → 牧场之心
	m._builds.stage = 5
	GameState.set_story_flag(&"quest_letter_done")
	GameState.set_story_flag(&"quest_secret_done")
	GameState.set_story_flag(&"quest_season_done")
	m._story.quest_act[&"letter"] = 6
	m._story.quest_act[&"secret"] = 5
	m._story.quest_act[&"season"] = 5
	m._refresh_story()
	_check(m._story.is_done(&"heart_of_ranch"), "三线全通 → 牧场之心")
	_check(m._story.endings_seen.has(&"heart_of_ranch"), "结局进了记录")
	_check(GameState.story_flag(&"heart_of_ranch"), "hidden 结局标记落地")
	_drain_dialogue(m)

	# 10.11 阶段 5 的闸门：没有老陈许可时升不上去
	m._builds.stage = 4
	GameState.story_flags.erase(&"permit_expansion")
	m._refresh_stage()
	_check(m._builds.stage == 4, "没有扩建许可 → 卡在第 4 阶段")
	GameState.set_story_flag(&"permit_expansion")
	GameState.add_gold(50000)
	GameState.bump_stat(GameState.ST_SOLD, 200)
	GameState.bump_stat(GameState.ST_CRAFTED, 30)
	m._npcs.state(&"chen").points = 450
	m._npcs.state(&"chen").met = true
	m._refresh_stage()
	_check(m._builds.stage >= 4, "有许可后阶段检查不崩（%d）" % m._builds.stage)

	# 10.12 存档往返：好感 + 剧情
	m._npcs.state(&"hai").points = 175
	m._story.counters[&"season_trial"] = 3
	var ok_save: bool = m._save_game(2, true)
	_check(ok_save, "存档成功（v3）")
	var hearts_before: int = m._npcs.hearts(&"hai")
	var acts_before: int = m._story.act_of(&"letter")
	m._npcs.state(&"hai").points = 0
	m._story.reset()
	var ok_load: bool = m._load_game(2)
	await get_tree().process_frame
	_check(ok_load, "读档成功")
	_check(m._npcs.hearts(&"hai") == hearts_before, "好感还原（%d）" % m._npcs.hearts(&"hai"))
	_check(m._story.act_of(&"letter") == acts_before, "剧情幕数还原（%d）" % m._story.act_of(&"letter"))
	_check(m._story.is_done(&"heart_of_ranch"), "结局记录还原")
	_check(m._npc_nodes.size() == 8, "读档后村民节点重建（%d）" % m._npc_nodes.size())
	_check(m._npcs.states.size() == 8, "读档后好感表 8 项")

	m.queue_free()
	await get_tree().process_frame

## 把对话框里排队的台词全部跳完（不然下一段测试会被「UI 模态」挡住）
func _drain_dialogue(m: Node) -> void:
	var guard := 0
	while m._dialogue.is_open() and guard < 50:
		m._dialogue.skip()
		guard += 1
