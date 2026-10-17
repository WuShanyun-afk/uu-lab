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

## 棚舍等级（模块 6）：StringName(housing_id) -> int(level)。0 / 缺省 = 没盖。
## 为什么不塞进 flag：flag 是 bool，棚舍是「有等级的容器」，必须能查等级。
var barns: Dictionary = {}

## 工具等级（模块 7）：&"hoe" / &"can" / &"bag" -> 1..3
## 数值与升级价格在 data/upgrades.csv，这里只存等级。
var tool_levels: Dictionary = {}

func _ready() -> void:
	_ensure_slots()
	_reset_tool_levels()

func _reset_tool_levels() -> void:
	tool_levels = {&"hoe": 1, &"can": 1, &"bag": 1}

# ---------------- 金币 ----------------

func add_gold(n: int) -> void:
	gold += n
	gold_changed.emit(gold)

func spend_gold(n: int) -> bool:
	if gold < n:
		return false
	gold -= n
	gold_changed.emit(gold)
	return true

# ---------------- 槽位容量 ----------------

func bag_level() -> int:
	return clampi(int(tool_levels.get(&"bag", 1)), 1, BAG_MAX_LEVEL)

func slot_capacity() -> int:
	return BAG_BASE + (bag_level() - 1) * BAG_PER_LEVEL

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
	gold_changed.emit(gold)
	slots_changed.emit()

# ---------------- 存档（模块 8）----------------
#
# 只存**真源**：gold / slots / tool_levels / barns / flags。
# inventory 是派生索引（每次 _rebuild_index 重建），不进存档 —— 存了反而会有两份真值。

func to_dict() -> Dictionary:
	return {
		"gold": gold,
		"slots": slots.duplicate(true),
		"tool_levels": tool_levels.duplicate(),
		"barns": barns.duplicate(),
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
