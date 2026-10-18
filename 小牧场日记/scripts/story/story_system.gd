class_name StorySystem
extends RefCounted
## 剧情推进器（模块 10 需求 4 / 5）—— **纯逻辑**，不碰节点、不碰 UI、不碰存档文件
##
## 它只回答四个问题：
##   ① 现在有哪些节点能播？（available / pick）
##   ② 这个节点播完了 → 登记 + 返回要给玩家的东西（complete）
##   ③ 三条主线各走到第几幕了 / 通关了吗？（quest_act / quest_done）
##   ④ 该给哪个结局？（endgame）
##
## 条件语法（StoryData.NODES 的 requires 里用）：
##
##   "flag:xxx"               剧情标记为真
##   "!flag:xxx"              取反（任何条件前面都可以加 !）
##   "hearts:masa>=3"         某村民好感 >= 3 心
##   "quest:letter:act>=2"    某主线已经播到第 2 幕
##   "quest:letter:done"      某主线通关
##   "quota:letter_frag>=4"   计数器（碎片数 / 试炼数）
##   "stage>=5" / "day>=2" / "season==1" / "gold>=1000"
##   "item:honey>=2"          背包里有多少（走 ctx["count_item"] 回调）
##   "perk:immune_once"       已解锁的被动
##   "all_quests"             三条主线全通
##
## 为什么用字符串 DSL 而不是给每个节点写一段 if：
##   20 个节点 × 平均 2 个条件 = 40 段判断，写在代码里就是 40 个特例；
##   写成数据之后**加一个节点不用改代码**，而且条件能被测试一条条断言。
##   解析器只有 60 行，比 40 段特例好维护得多。
##
## ⚠️ 上下文（ctx）由 main 每帧拼一次：flags / hearts / stage / day / season /
##    gold / perks / count_item。本类不认识 GameState，测试可以喂假数据。

## 已完成节点 id
var done: Dictionary = {}
## quest -> 已完成到第几幕
var quest_act: Dictionary = {}
## 计数器：碎片数 / 试炼数……
var counters: Dictionary = {}
## 已经播过的结局（正常只会有一个）
var endings_seen: Array = []

func _init() -> void:
	reset()

func reset() -> void:
	done.clear()
	quest_act.clear()
	counters.clear()
	endings_seen.clear()
	for q in StoryData.main_quests():
		quest_act[q] = 0

# ---------------- 查询 ----------------

func is_done(id: StringName) -> bool:
	return bool(done.get(id, false))

func act_of(quest: StringName) -> int:
	return int(quest_act.get(quest, 0))

func counter(key: StringName) -> int:
	return int(counters.get(key, 0))

## 某条主线的最后一幕（StoryData 里 act 的最大值）
static func max_act(quest: StringName) -> int:
	var m := 0
	for n in StoryData.nodes_of_quest(quest):
		m = maxi(m, int(n["act"]))
	return m

func quest_done(quest: StringName) -> bool:
	var m := max_act(quest)
	return m > 0 and act_of(quest) >= m

func all_quests_done() -> bool:
	for q in StoryData.main_quests():
		if not quest_done(q):
			return false
	return true

func main_quests_done() -> int:
	var n := 0
	for q in StoryData.main_quests():
		if quest_done(q):
			n += 1
	return n

func has_ending() -> bool:
	return not endings_seen.is_empty()

# ---------------- 条件解析 ----------------

## 一条条件成立吗
func check(cond: String, ctx: Dictionary) -> bool:
	var c := cond.strip_edges()
	if c.begins_with("!"):
		return not _check_positive(c.substr(1), ctx)
	return _check_positive(c, ctx)

## 一组条件全成立吗（空数组 = 立刻成立）
func check_all(conds: Array, ctx: Dictionary) -> bool:
	for c in conds:
		if not check(str(c), ctx):
			return false
	return true

func _check_positive(c: String, ctx: Dictionary) -> bool:
	# 先拆比较符：>= / == / >
	if c.contains(">="):
		var p := c.split(">=")
		return _value_of(p[0].strip_edges(), ctx) >= int(p[1].strip_edges())
	if c.contains("=="):
		var p2 := c.split("==")
		return _value_of(p2[0].strip_edges(), ctx) == int(p2[1].strip_edges())
	if c.contains(">"):
		var p3 := c.split(">")
		return _value_of(p3[0].strip_edges(), ctx) > int(p3[1].strip_edges())
	# 没有比较符 = 布尔条件
	var parts := c.split(":")
	match parts[0]:
		"flag":
			return parts.size() > 1 and bool((ctx.get("flags", {}) as Dictionary).get(parts[1], false))
		"quest":
			if parts.size() > 2 and parts[2] == "done":
				return quest_done(StringName(parts[1]))
			return false
		"perk":
			return parts.size() > 1 and (ctx.get("perks", []) as Array).has(StringName(parts[1]))
		"all_quests":
			return all_quests_done()
		"met":
			return parts.size() > 1 and bool((ctx.get("met", {}) as Dictionary).get(parts[1], false))
	return false

## 条件左边的「量」：hearts:masa → 3、quota:x → 计数器、stage → 阶段……
func _value_of(key: String, ctx: Dictionary) -> int:
	var parts := key.split(":")
	match parts[0]:
		"hearts":
			if parts.size() > 1:
				return int((ctx.get("hearts", {}) as Dictionary).get(parts[1], 0))
			return 0
		"quota":
			if parts.size() > 1:
				return counter(StringName(parts[1]))
			return 0
		"quest":
			# quest:letter:act —— 已经播到第几幕
			if parts.size() > 2 and parts[2] == "act":
				return act_of(StringName(parts[1]))
			return 0
		"item":
			var fn: Callable = ctx.get("count_item", Callable())
			if parts.size() > 1 and fn.is_valid():
				return int(fn.call(StringName(parts[1])))
			return 0
		"day":
			return int(ctx.get("day", 0))
		"season":
			return int(ctx.get("season", 0))
		"stage":
			return int(ctx.get("stage", 0))
		"gold":
			return int(ctx.get("gold", 0))
		"npcs_at":
			# npcs_at:4>=3 —— 有几位村民到了 4 心以上（count 在前面不方便，用 hearts 键更好读）
			var h := int(parts[1]) if parts.size() > 1 else 0
			var n := 0
			for k in (ctx.get("hearts", {}) as Dictionary):
				if int((ctx.get("hearts", {}) as Dictionary)[k]) >= h:
					n += 1
			return n
	return 0

# ---------------- 可播节点 ----------------

## 现在能播的节点（按 StoryData.NODES 的顺序 = 优先级）。
## 同一主线里必须**按幕推进**：act 必须正好等于「已完成幕 + 1」，
## 否则会出现「第 3 幕先播、第 2 幕永远播不到」。
func available(ctx: Dictionary) -> Array:
	var out: Array = []
	for n in StoryData.NODES:
		var id: StringName = n["id"]
		if is_done(id):
			continue
		var q: StringName = n["quest"]
		if q != &"ending":
			if int(n["act"]) != act_of(q) + 1:
				continue
		if not check_all(n.get("requires", []), ctx):
			continue
		out.append(n)
	return out

## 只要一个（每帧最多播一个，播完关掉再播下一个 —— 别一口气弹 5 段对话）
func pick(ctx: Dictionary) -> Dictionary:
	var a := available(ctx)
	return {} if a.is_empty() else a[0]

## 自动触发的那一个（auto = true）。
## auto = false 的节点只能靠**找对人说话**触发 —— 否则「老陈在门口把信塞给你」
## 会变成路过就自己弹，玩家根本不知道是谁给的。
func pick_auto(ctx: Dictionary) -> Dictionary:
	for n in available(ctx):
		if bool(n.get("auto", true)):
			return n
	return {}

## 和某位村民对话时能触发的那一个（不看 auto，只看是不是他说的）
func pick_manual(ctx: Dictionary, npc_id: StringName) -> Dictionary:
	for n in available(ctx):
		if StringName(str(n.get("npc", ""))) == npc_id:
			return n
	return {}

## 给 UI / 存档用的进度摘要
func progress_text() -> String:
	var parts: Array[String] = []
	for q in StoryData.main_quests():
		var meta: Dictionary = StoryData.QUESTS[q]
		var m := max_act(q)
		if quest_done(q):
			parts.append("%s✔" % meta["name"])
		else:
			parts.append("%s%d/%d" % [meta["name"], act_of(q), m])
	return "剧情 " + " · ".join(parts)

# ---------------- 完成一个节点 ----------------

## 登记节点完成，返回 effects（金币 / 物品由 main 真正发放）。
## ⚠️ 计数器在这里就加完了 —— 所以 main 只要照着 returned dict 发钱发东西。
func complete(node: Dictionary) -> Dictionary:
	var id: StringName = node.get("id", &"")
	if id == &"" or is_done(id):
		return {}
	done[id] = true
	var q: StringName = node.get("quest", &"")
	if q == &"ending":
		if not endings_seen.has(id):
			endings_seen.append(id)
	else:
		quest_act[q] = maxi(act_of(q), int(node.get("act", 0)))
	var eff: Dictionary = node.get("effects", {})
	if eff.has("quota"):
		var key := StringName(str(eff["quota"]))
		counters[key] = counter(key) + int(eff.get("quota_count", 1))
	return eff.duplicate(true)

# ---------------- 结局 ----------------

## 该播哪个结局（只返回**还没播过**的）。{}
## 顺序由 StoryData 决定：三条单线结局在前，牧场之心在最后 ——
## 但单线结局都带「另外两条没完成」的取反条件，所以三条全通时只有牧场之心成立。
func endgame(ctx: Dictionary) -> Dictionary:
	for n in StoryData.NODES:
		if not bool(n.get("ending", false)) or is_done(n["id"]):
			continue
		# 已经播过的结局不再返回（endings_seen 和 done 是两回事：
		# 结局节点可能因为读档 / 老档只登记了其中一边）
		if endings_seen.has(n["id"]):
			continue
		if check_all(n.get("requires", []), ctx):
			return n
	return {}

# ---------------- 存档 ----------------

func to_dict() -> Dictionary:
	var d: Dictionary = {}
	for id in done:
		d[String(id)] = true
	return {
		"done": d,
		"acts": _stringify_keys(quest_act),
		"counters": _stringify_keys(counters),
		"endings": endings_seen.duplicate(),
	}

func from_dict(d: Dictionary) -> void:
	reset()
	var dn: Dictionary = d.get("done", {})
	for k in dn:
		if bool(dn[k]):
			done[StringName(str(k))] = true
	var ac: Dictionary = d.get("acts", {})
	for k in ac:
		quest_act[StringName(str(k))] = int(ac[k])
	var ct: Dictionary = d.get("counters", {})
	for k in ct:
		counters[StringName(str(k))] = int(ct[k])
	endings_seen.clear()
	for k in d.get("endings", []):
		endings_seen.append(StringName(str(k)))

## JSON 的键只能是字符串 —— 存档前统一转一次，读回来再转回来
func _stringify_keys(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in src:
		out[String(k)] = src[k]
	return out
