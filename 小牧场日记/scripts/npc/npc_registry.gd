class_name NpcRegistry
extends RefCounted
## 全部村民的好感状态（模块 10 需求 1）—— 纯数据容器，不碰节点
##
## 为什么单独一个类而不是塞进 GameState：
##   GameState 已经 400 行，管金币 / 背包 / 棚舍 / 工具等级 / 统计。
##   好感是「一张 NPC 表」，塞进去会让 GameState 变成上帝对象。
##   存档时 main 把 NpcRegistry.to_dict() 单独放一段，各管各的。
##
## 单例语义：main 持有一个实例，存档读档都是整坨替换。

## StringName -> NpcState
var states: Dictionary = {}

func _init() -> void:
	reset()

func reset() -> void:
	states.clear()
	for id in NpcDB.all_ids():
		states[id] = NpcState.new(id)

## 取状态；不认识的 id 返回 null（不自动创建 —— 打错字要当场发现，不要静默长出一个 NPC）
func state(id: StringName) -> NpcState:
	return states.get(id, null)

func ensure(id: StringName) -> NpcState:
	if not states.has(id):
		states[id] = NpcState.new(id)
	return states[id]

func hearts(id: StringName) -> int:
	var s := state(id)
	return 0 if s == null else s.hearts()

## {StringName: int} 快照 —— 给剧情条件 / HUD 用，避免到处传 registry
func hearts_map() -> Dictionary:
	var out: Dictionary = {}
	for id in states:
		out[id] = (states[id] as NpcState).hearts()
	return out

func total_hearts() -> int:
	var n := 0
	for id in states:
		n += (states[id] as NpcState).hearts()
	return n

## 有几位的某颗心以上（剧情「至少 3 人 4 心」这类条件）
func count_at_least(hearts: int) -> int:
	var n := 0
	for id in states:
		if (states[id] as NpcState).hearts() >= hearts:
			n += 1
	return n

# ---------------- 每天的动作 ----------------

## 聊天。返回实际加点（同一天第二次 = 0）
func talk(id: StringName, day: int) -> int:
	var s := state(id)
	return 0 if s == null else s.talk(day)

func can_gift(id: StringName, day: int) -> bool:
	var s := state(id)
	return s != null and s.can_gift(day)

func gifts_left(id: StringName, day: int) -> int:
	var s := state(id)
	return 0 if s == null else maxi(0, NpcState.GIFTS_PER_DAY - s.gift_used(day))

## 送礼。返回实际加点（可能是负的）
func gift(id: StringName, item_id: StringName, day: int) -> int:
	var s := state(id)
	if s == null:
		return 0
	return s.gift(NpcDB.def_of(id), item_id, day)

# ---------------- 解锁 ----------------

## 当前已经达到的解锁项
func unlocks_of(id: StringName) -> Array:
	var s := state(id)
	return NpcDB.unlocks_reached(id, 0 if s == null else s.hearts())

## 按 kind 汇总成可直接用的结构：
##   price: {seed: 10, tool: 20}   （百分比）
##   perks: [immune_once, ...]
##   stories: [permit_expansion, ...]
##   recipes: [honey_butter, ...]
func unlock_summary() -> Dictionary:
	var out := {"price": {}, "perks": [], "stories": [], "recipes": [], "tools": []}
	for id in states:
		for u in unlocks_of(id):
			match String(u["kind"]):
				"price":
					var scope: StringName = u["id"]
					out["price"][scope] = maxi(int(out["price"].get(scope, 0)), int(u["value"]))
				"perk":
					out["perks"].append(u["id"])
				"story":
					out["stories"].append(u["id"])
				"recipe":
					out["recipes"].append(u["id"])
				"tool":
					out["tools"].append(u["id"])
	return out

## 某个作用域的打折百分比（0 = 不打折）
func discount_percent(scope: StringName) -> int:
	return int(unlock_summary()["price"].get(scope, 0))

# ---------------- 存档 ----------------

func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for id in states:
		out[String(id)] = (states[id] as NpcState).to_dict()
	return out

func from_dict(d: Dictionary) -> void:
	reset()
	for key in d:
		var raw: Variant = d[key]
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var id := StringName(str(key))
		if not NpcDB.has(id):
			continue                       # 表里删掉的村民：丢掉，别让存档污染状态
		states[id] = NpcState.from_dict(raw)
