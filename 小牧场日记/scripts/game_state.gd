extends Node
## 全局状态：金币、背包（真槽位）、统计、进度标记（GDD §10.2 autoload: GameState）
##
## 模块 5 加了两个**进度标记**：秘密花园是否解锁、繁殖棚是否盖好。
## 为什么不放在 main 里：藤蔓门 / 繁殖棚这些可交互物要读它们来写提示文案，
## 而它们不该持有 main 的引用（零耦合）。标记放全局，谁都能查。
##
## ══════════════════════════════════════════════════════════════════════
## 模块 7 改造：背包从「字典计数」升级为「真槽位」
## ══════════════════════════════════════════════════════════════════════
##
## 旧结构：inventory: Dictionary[id] -> count。
##   · 好处：一行 add/remove 就完事，全项目 30 多处调用零成本。
##   · 坏处：**没有格子**。UI 里做拖拽排序、堆叠上限、拖出去丢弃，全都没地方落。
##
## 新结构：
##   slots:     Array，长度 = slot_capacity()，每项 null 或 {id: StringName, count: int}
##   inventory: Dictionary[id] -> 总数 —— **派生索引**，不是真源。
##
## 为什么要留 inventory：
##   出货箱 / HUD / 商店 / 订单全都按 id 查总数（count_item），
##   把它们改成遍历槽位是一次毫无收益的重写，而且很容易漏。
##   所以真源是 slots，inventory 是每次变更后重建的缓存。
##
## ⚠️ **不要**直接写 inventory[...]。它每次变更都会被 _rebuild_index() 覆盖。
## ⚠️ 堆叠上限来自 ItemDB.stack_max(id)（默认 99）。超了自动占下一格，
##    一格都占不到时 add_item 返回「实际放进去的数量」而不是全丢。

signal gold_changed(value: int)
signal inventory_changed(item_id: StringName, count: int)
## 槽位布局变了（增删 / 移动 / 合并）—— 背包 UI 订阅它重绘
signal slots_changed()
## 进度标记变化（名字, 新值）—— 想联动的系统订阅它，不用轮询
signal flag_changed(name: StringName, value: bool)

const BAG_BASE := 40          ## 初始格数（8 列 × 5 行）
const BAG_PER_LEVEL := 8      ## 每级扩容
const BAG_MAX_LEVEL := 3      ## Lv3 = 56 格
const BAG_COLUMNS := 8

var gold: int = 500
## 真源：槽位
var slots: Array = []
## 派生索引：id -> 总数（只读，别直接写）
var inventory: Dictionary = {}

## 进度标记（模块 5）
var garden_unlocked: bool = false
var shed_built: bool = false
## 成就：完成 10 张订单（模块 7 需求 3）
var famous: bool = false

## 累计统计（模块 9）：StringName -> int。
## 牧场阶段门槛里有「累计加工 10 件」「累计售出 100 件」这类**只能涨不能跌**的指标，
## 放这里而不是塞进 flag（flag 是 bool）也不塞进 main（main 会重建，统计得跟着存档走）。
## 和 inventory 的区别：inventory 是「现在有多少」，stats 是「一共来过多少」。
var stats: Dictionary = {}

## 模块 10：剧情标记（StringName -> bool）。和老的三个 flag 分开：
## 那三个是「玩法开关」（花园解锁 / 繁殖棚盖好 / 名人），有专门的 setter；
## 这里是**剧情数据**，键由 StoryData / NpcDB 的解锁表决定，只增不减。
var story_flags: Dictionary = {}
## 模块 10：已解锁的被动（NPC 好感奖励），StringName 数组
var perks: Array = []
## 模块 10：已解锁的秘方（RecipeDB 里 is_secret 的那些）
var secret_recipes: Array = []

# ---------------- 模块 12（7.5）：住宅 / 家具 / buff ----------------

## 住宅等级 1–3（真源；HouseDB 管每级的成本与解锁）
var house_level: int = 1
## 室内家具：[{id, x, y}]。摆在哪是玩家自己的事，存坐标就好。
var furniture: Array = []
## 当日生效的 buff：StringName -> int(生效到第几天)
var buffs: Dictionary = {}
## 谷仓给的额外背包格（派生值：每次建筑变化由 main 重算，不进存档）
var bonus_slots: int = 0
## 住宅升级工地（模块 12）：目标等级 + 剩余天数。0 天 = 没在施工。
var house_upgrade_target: int = 0
var house_upgrade_days: int = 0

## 棚舍等级（模块 6）：StringName(housing_id) -> int(level)。0 / 缺省 = 没盖。
## 为什么不塞进 flag：flag 是 bool，棚舍是「有等级的容器」，必须能查等级。
var barns: Dictionary = {}

## 工具等级（模块 7）：&"hoe" / &"can" / &"bag" -> 1..3
## 数值与升级价格在 data/upgrades.csv，这里只存等级。
var tool_levels: Dictionary = {}

func _ready() -> void:
	_ensure_slots()
	_reset_tool_levels()
	_reset_stats()

func _reset_tool_levels() -> void:
	tool_levels = {&"hoe": 1, &"can": 1, &"bag": 1}

# ---------------- 累计统计（模块 9）----------------

## 统计键（用常量，别写字面量 —— 拼错了是 0 而不是报错，最难查）
const ST_ORDERS := &"orders"      ## 完成订单数
const ST_CRAFTED := &"crafted"    ## 加工出件数
const ST_SOLD := &"sold"          ## 售出件数
const ST_BUILT := &"built"        ## 盖过的建筑数（统计用，不进阶段门槛）

func _reset_stats() -> void:
	stats = {ST_ORDERS: 0, ST_CRAFTED: 0, ST_SOLD: 0, ST_BUILT: 0}

func bump_stat(key: StringName, n: int = 1) -> void:
	if n == 0:
		return
	stats[key] = maxi(0, int(stats.get(key, 0)) + n)

func stat(key: StringName) -> int:
	return int(stats.get(key, 0))

# ---------------- 剧情标记 / 被动 / 秘方（模块 10）----------------

func set_story_flag(name: StringName, value: bool = true) -> void:
	story_flags[name] = value
	flag_changed.emit(StringName("story:" + String(name)), value)

func story_flag(name: StringName) -> bool:
	return bool(story_flags.get(name, false))

func add_perk(name: StringName) -> bool:
	if perks.has(name):
		return false
	perks.append(name)
	flag_changed.emit(StringName("perk:" + String(name)), true)
	return true

func has_perk(name: StringName) -> bool:
	return perks.has(name)

func unlock_recipe(id: StringName) -> bool:
	if secret_recipes.has(id):
		return false
	secret_recipes.append(id)
	flag_changed.emit(StringName("recipe:" + String(id)), true)
	return true

func is_recipe_unlocked(id: StringName) -> bool:
	return secret_recipes.has(id)

# ---------------- 住宅 / 家具 / buff（模块 12）----------------

func set_house_level(lv: int) -> void:
	house_level = clampi(lv, 1, HouseDB.MAX_LEVEL)
	flag_changed.emit(&"house_level", true)

## 加一件家具（同一格只能有一件）
func add_furniture(id: StringName, cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0:
		return false
	if furniture_at(cell) != StringName(""):
		return false
	furniture.append({"id": String(id), "x": cell.x, "y": cell.y})
	return true

func furniture_at(cell: Vector2i) -> StringName:
	for f in furniture:
		if int(f["x"]) == cell.x and int(f["y"]) == cell.y:
			return StringName(str(f["id"]))
	return &""

## 收走某格家具，返回家具 id（没有返回 &""）
func take_furniture(cell: Vector2i) -> StringName:
	for i in range(furniture.size()):
		var f: Dictionary = furniture[i]
		if int(f["x"]) == cell.x and int(f["y"]) == cell.y:
			var id := StringName(str(f["id"]))
			furniture.remove_at(i)
			return id
	return &""

func furniture_count() -> int:
	return furniture.size()

## 设一个「到第 day 天为止生效」的 buff
func set_buff(name: StringName, day: int) -> void:
	buffs[name] = day

func has_buff(name: StringName, day: int) -> bool:
	return int(buffs.get(name, -999)) >= day

## 消费 buff（用掉就删，保证一天只吃一次效果）
func consume_buff(name: StringName, day: int) -> bool:
	if not has_buff(name, day):
		return false
	buffs.erase(name)
	return true

# ---------------- 金币 ----------------

func add_gold(n: int) -> void:
	gold += n
	gold_changed.emit(gold)
	# 模块 附1：金币是「入账音」的唯一入口 —— 音频系统只订阅，不改这里的任何逻辑
	EventBus.gold_changed.emit(n, gold)

func spend_gold(n: int) -> bool:
	if gold < n:
		return false
	gold -= n
	gold_changed.emit(gold)
	EventBus.gold_changed.emit(-n, gold)
	return true

# ---------------- 槽位容量 ----------------

func bag_level() -> int:
	return clampi(int(tool_levels.get(&"bag", 1)), 1, BAG_MAX_LEVEL)

func slot_capacity() -> int:
	return BAG_BASE + (bag_level() - 1) * BAG_PER_LEVEL + maxi(0, bonus_slots)

## 谷仓给的额外格（模块 12）。派生值：建筑变了就重算，不进存档。
func set_bonus_slots(n: int) -> void:
	var v := maxi(0, n)
	if v == bonus_slots:
		return
	bonus_slots = v
	_ensure_slots()
	slots_changed.emit()

## 扩容：加格子（升到 Lv2 时 40 → 48）
func set_bag_level(lv: int) -> void:
	tool_levels[&"bag"] = clampi(lv, 1, BAG_MAX_LEVEL)
	_ensure_slots()
	slots_changed.emit()

func _ensure_slots() -> void:
	var cap := slot_capacity()
	while slots.size() < cap:
		slots.append(null)
	while slots.size() > cap:
		# 缩容（理论上不会发生，除非改数值）：把尾巴上还有东西的格挪到前面
		var last = slots.pop_back()
		if last != null:
			add_item(last["id"], int(last["count"]))

func slot_item(i: int) -> StringName:
	if i < 0 or i >= slots.size() or slots[i] == null:
		return &""
	return slots[i]["id"]

func slot_amount(i: int) -> int:
	if i < 0 or i >= slots.size() or slots[i] == null:
		return 0
	return int(slots[i]["count"])

# ---------------- 增删 ----------------

## 往背包放东西。返回**实际放进去的数量**（背包满了会少放，不会丢已放的）。
## 堆叠优先：先塞进已有的同 id 格，再找空格。
func add_item(id: StringName, n: int = 1) -> int:
	if n <= 0:
		return 0
	_ensure_slots()
	var cap := _stack_max(id)
	var left := n
	# ① 先叠到已有格
	for i in range(slots.size()):
		if left <= 0:
			break
		var s = slots[i]
		if s == null or s["id"] != id:
			continue
		var room := cap - int(s["count"])
		if room <= 0:
			continue
		var put := mini(room, left)
		s["count"] = int(s["count"]) + put
		left -= put
	# ② 再开新格
	for i in range(slots.size()):
		if left <= 0:
			break
		if slots[i] != null:
			continue
		var put := mini(cap, left)
		slots[i] = {"id": id, "count": put}
		left -= put
	var added := n - left
	if added > 0:
		_rebuild_index()
		inventory_changed.emit(id, count_item(id))
		slots_changed.emit()
	return added

func count_item(id: StringName) -> int:
	return int(inventory.get(id, 0))

## 能不能再放 n 个（不算已有堆叠的余量，保守版：只看空格 + 同 id 余量）
func can_add(id: StringName, n: int) -> int:
	var cap := _stack_max(id)
	var room := 0
	for i in range(slots.size()):
		var s = slots[i]
		if s == null:
			room += cap
		elif s["id"] == id:
			room += maxi(0, cap - int(s["count"]))
		if room >= n:
			return n
	return room

func remove_item(id: StringName, n: int = 1) -> bool:
	if n <= 0:
		return true
	if count_item(id) < n:
		return false
	var left := n
	# 从后往前扣：让前面的格子保持稳定，玩家不会看到物品在格子里跳
	for i in range(slots.size() - 1, -1, -1):
		if left <= 0:
			break
		var s = slots[i]
		if s == null or s["id"] != id:
			continue
		var take := mini(int(s["count"]), left)
		s["count"] = int(s["count"]) - take
		left -= take
		if int(s["count"]) <= 0:
			slots[i] = null
	_rebuild_index()
	inventory_changed.emit(id, count_item(id))
	slots_changed.emit()
	return true

## 丢掉某一格里的 n 个（背包 UI 的 X 键）
func drop_slot(i: int, n: int = 1) -> bool:
	if i < 0 or i >= slots.size() or slots[i] == null:
		return false
	var s = slots[i]
	var take := mini(n, int(s["count"]))
	s["count"] = int(s["count"]) - take
	if int(s["count"]) <= 0:
		slots[i] = null
	_rebuild_index()
	inventory_changed.emit(s["id"] if slots[i] != null else &"", 0)
	slots_changed.emit()
	return true

# ---------------- 拖拽 ----------------

## 把 from 格的物品拖到 to 格：
##   · to 空          → 整格移过去
##   · 同 id 且未满   → 合并，余量留在原格
##   · 其余           → 交换两格
## 返回 "moved" / "merged" / "swapped" / "noop"
func move_slot(from: int, to: int) -> String:
	if from == to or from < 0 or to < 0 or from >= slots.size() or to >= slots.size():
		return "noop"
	var a = slots[from]
	if a == null:
		return "noop"
	var b = slots[to]
	if b == null:
		slots[to] = a
		slots[from] = null
		_after_move()
		return "moved"
	if b["id"] == a["id"]:
		var cap := _stack_max(a["id"])
		var room := cap - int(b["count"])
		if room <= 0:
			return "noop"
		var moved := mini(room, int(a["count"]))
		b["count"] = int(b["count"]) + moved
		a["count"] = int(a["count"]) - moved
		if int(a["count"]) <= 0:
			slots[from] = null
		_after_move()
		return "merged"
	slots[from] = b
	slots[to] = a
	_after_move()
	return "swapped"

func _after_move() -> void:
	_rebuild_index()
	slots_changed.emit()

func _stack_max(id: StringName) -> int:
	# ItemDB 是 autoload，编译期就能解析；它没 ready 完时 stack_max 兜底 99
	return maxi(1, ItemDB.stack_max(id))

## 重建派生索引。**每次槽位变更后必须调**，否则 count_item 会读到旧值。
func _rebuild_index() -> void:
	inventory.clear()
	for s in slots:
		if s == null:
			continue
		var id: StringName = s["id"]
		inventory[id] = int(inventory.get(id, 0)) + int(s["count"])

## 背包里所有非空格的下标（UI 遍历用，避免 56 格里挨个判空）
func used_slot_indices() -> Array:
	var out: Array = []
	for i in range(slots.size()):
		if slots[i] != null:
			out.append(i)
	return out

func used_slot_count() -> int:
	return used_slot_indices().size()

# ---------------- 进度标记 ----------------

func set_flag(name: StringName, value: bool) -> void:
	match name:
		&"garden_unlocked":
			garden_unlocked = value
		&"shed_built":
			shed_built = value
		&"famous":
			famous = value
		_:
			return
	flag_changed.emit(name, value)

func has_flag(name: StringName) -> bool:
	match name:
		&"garden_unlocked":
			return garden_unlocked
		&"shed_built":
			return shed_built
		&"famous":
			return famous
	return false

# ---------------- 棚舍等级（模块 6）----------------

func barn_level(id: StringName) -> int:
	return int(barns.get(id, 0))

func has_barn(id: StringName) -> bool:
	return barn_level(id) > 0

func set_barn_level(id: StringName, level: int) -> void:
	if level <= 0:
		barns.erase(id)
	else:
		barns[id] = level
	flag_changed.emit(StringName("barn:" + String(id)), level > 0)

## 所有棚舍等级的快照（传给 Housing 纯逻辑函数用，避免它直接依赖 autoload）
func barn_levels() -> Dictionary:
	return barns.duplicate()

# ---------------- 工具等级（模块 7）----------------

func tool_level(tool: StringName) -> int:
	return clampi(int(tool_levels.get(tool, 1)), 1, 3)

func set_tool_level(tool: StringName, lv: int) -> void:
	tool_levels[tool] = clampi(lv, 1, 3)
	if tool == &"bag":
		_ensure_slots()
	flag_changed.emit(StringName("tool:" + String(tool)), true)

func reset() -> void:
	gold = 500
	slots.clear()
	inventory.clear()
	_ensure_slots()
	_reset_tool_levels()
	garden_unlocked = false
	shed_built = false
	famous = false
	barns.clear()
	_reset_stats()
	story_flags.clear()
	perks.clear()
	secret_recipes.clear()
	house_level = 1
	furniture.clear()
	buffs.clear()
	bonus_slots = 0
	house_upgrade_target = 0
	house_upgrade_days = 0
	gold_changed.emit(gold)
	slots_changed.emit()

# ---------------- 存档（模块 8）----------------
#
# 只存**真源**：gold / slots / tool_levels / barns / flags。
# inventory 是派生索引（每次 _rebuild_index 重建），不进存档 —— 存了反而会有两份真值。

## JSON 的对象键只能是字符串 —— StringName 键在存档前统一转一次（模块 10）
func _stringify_keys(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in src:
		out[String(k)] = src[k]
	return out

func to_dict() -> Dictionary:
	return {
		"gold": gold,
		"slots": slots.duplicate(true),
		"tool_levels": tool_levels.duplicate(),
		"barns": barns.duplicate(),
		"stats": stats.duplicate(),
		"story_flags": _stringify_keys(story_flags),
		"perks": perks.duplicate(),
		"secret_recipes": secret_recipes.duplicate(),
		"house_level": house_level,
		"furniture": furniture.duplicate(true),
		"buffs": _stringify_keys(buffs),
		"house_upgrade_target": house_upgrade_target,
		"house_upgrade_days": house_upgrade_days,
		"flags": {
			"garden_unlocked": garden_unlocked,
			"shed_built": shed_built,
			"famous": famous,
		},
	}

## ⚠️ 槽位里的 id 从 JSON 回来是 **String**，必须 StringName() 回来，
##    否则 count_item / remove_item 用 StringName 查 inventory 会全部查不到。
func from_dict(d: Dictionary) -> void:
	gold = int(d.get("gold", 500))
	slots.clear()
	var raw_slots: Array = d.get("slots", [])
	for raw in raw_slots:
		if typeof(raw) != TYPE_DICTIONARY:
			slots.append(null)
			continue
		var id := StringName(str(raw.get("id", "")))
		var cnt := int(raw.get("count", 0))
		if id == StringName("") or cnt <= 0:
			slots.append(null)
		else:
			slots.append({"id": id, "count": cnt})
	tool_levels.clear()
	var tl: Dictionary = d.get("tool_levels", {})
	for k in tl:
		tool_levels[StringName(str(k))] = clampi(int(tl[k]), 1, 3)
	if tool_levels.is_empty():
		_reset_tool_levels()
	barns.clear()
	var bn: Dictionary = d.get("barns", {})
	for k in bn:
		var lv := int(bn[k])
		if lv > 0:
			barns[StringName(str(k))] = lv
	# 累计统计：老档（v1）里没有这一段，缺省全 0 是正确语义
	_reset_stats()
	var st: Dictionary = d.get("stats", {})
	for k in st:
		stats[StringName(str(k))] = maxi(0, int(st[k]))
	# 模块 10：剧情标记 / 被动 / 秘方（老档没有 = 空，语义正确）
	story_flags.clear()
	var sf: Dictionary = d.get("story_flags", {})
	for k in sf:
		story_flags[StringName(str(k))] = bool(sf[k])
	perks.clear()
	for k in d.get("perks", []):
		perks.append(StringName(str(k)))
	secret_recipes.clear()
	for k in d.get("secret_recipes", []):
		secret_recipes.append(StringName(str(k)))
	# 模块 12：住宅等级 / 家具 / buff（老档缺省 = 1 级小木屋，语义正确）
	house_level = clampi(int(d.get("house_level", 1)), 1, HouseDB.MAX_LEVEL)
	furniture.clear()
	for f in d.get("furniture", []):
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var fid := StringName(str(f.get("id", "")))
		if fid == &"":
			continue
		furniture.append({"id": String(fid), "x": int(f.get("x", 0)), "y": int(f.get("y", 0))})
	buffs.clear()
	var bf: Dictionary = d.get("buffs", {})
	for k in bf:
		buffs[StringName(str(k))] = int(bf[k])
	house_upgrade_target = clampi(int(d.get("house_upgrade_target", 0)), 0, HouseDB.MAX_LEVEL)
	house_upgrade_days = maxi(0, int(d.get("house_upgrade_days", 0)))
	var fl: Dictionary = d.get("flags", {})
	garden_unlocked = bool(fl.get("garden_unlocked", false))
	shed_built = bool(fl.get("shed_built", false))
	famous = bool(fl.get("famous", false))
	# 长度按「当前背包等级」对齐，不走 _ensure_slots()：
	# 那个函数会调 add_item，而此刻派生索引还是空的，会把尾巴上的物品算丢。
	var cap := slot_capacity()
	while slots.size() < cap:
		slots.append(null)
	while slots.size() > cap:
		slots.pop_back()
	_rebuild_index()
	gold_changed.emit(gold)
	slots_changed.emit()
