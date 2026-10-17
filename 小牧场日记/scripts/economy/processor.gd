class_name Processor
extends RefCounted
## 加工坊的**纯逻辑**（模块 7 需求 4）—— 不碰场景、不碰 UI、不碰 GameState
##
## 和 RhythmBar 同一套思路：机器状态机自己独立可测，
## headless 里 start → advance_minutes → take 全链路能跑完，不用起一个场景。
##
## 一条槽的一生：
##   start(配方, 品质)  →  remain = 配方的 minutes
##   advance_minutes(m) →  remain 递减，到 0 就 ready
##   take(index)        →  返回 {output, count, quality}，槽清空
##
## 为什么槽要记 quality：GDD §5.1「品质倍率在原料端计算，加工品继承原料品质倍率」。
## 金星牛奶做出的就是金星奶酪。品质只在**放料那一刻**读一次，中途不可变。
##
## ⚠️ 时间单位是**游戏分钟**，不是秒。main 在 tick_advanced(10) 里推进，
##    所以「2 小时」= 12 个 tick，和一天 24 小时的时钟天然对齐。

## 槽位上限按等级：GDD §5.1「Lv1 = 2 槽，Lv2 = 4 槽，Lv3 = 6 槽」
const SLOTS_BY_LEVEL := [2, 4, 6]
const MAX_LEVEL := 3

enum Reason { OK, NO_SLOT, NO_RECIPE, BUSY }

var level: int = 1
## 每个槽：null（空）或 {recipe, output, input, need, quality, remain, total}
var slots: Array = []

func _init(lv: int = 1) -> void:
	level = clampi(lv, 1, MAX_LEVEL)
	_rebuild_slots()

func _rebuild_slots() -> void:
	var n := slot_count()
	while slots.size() < n:
		slots.append(null)
	while slots.size() > n:
		slots.pop_back()

static func slot_count_at(lv: int) -> int:
	return int(SLOTS_BY_LEVEL[clampi(lv, 1, MAX_LEVEL) - 1])

func slot_count() -> int:
	return slot_count_at(level)

func set_level(lv: int) -> void:
	level = clampi(lv, 1, MAX_LEVEL)
	_rebuild_slots()

func used_slots() -> int:
	var n := 0
	for s in slots:
		if s != null:
			n += 1
	return n

func free_slots() -> int:
	return slot_count() - used_slots()

## 第一个空槽的下标（满了返回 -1）
func first_free() -> int:
	for i in range(slots.size()):
		if slots[i] == null:
			return i
	return -1

# ---------------- 放料 ----------------

## 能不能开始加工。返回 Reason 枚举（不是 bool —— 要能告诉玩家「槽满了」还是「这原料做不了」）
func can_start(recipe_output: StringName, have: int) -> int:
	if not RecipeDB.has(recipe_output):
		return Reason.NO_RECIPE
	var r: Dictionary = RecipeDB.get_recipe(recipe_output)
	if have < int(r["count"]):
		return Reason.NO_RECIPE
	if first_free() < 0:
		return Reason.NO_SLOT
	return Reason.OK

static func reason_text(reason: int) -> String:
	match reason:
		Reason.OK:
			return ""
		Reason.NO_SLOT:
			return "加工槽满了（等出货，或升级加工坊）"
		Reason.NO_RECIPE:
			return "这原料做不了加工品"
		Reason.BUSY:
			return "槽位正忙"
	return ""

## 占一个槽。**调用方负责扣原料**（本类不碰背包）。
func start(recipe_output: StringName, quality: int = 0) -> int:
	var r: Dictionary = RecipeDB.get_recipe(recipe_output)
	if r.is_empty():
		return -1
	var i := first_free()
	if i < 0:
		return -1
	slots[i] = {
		"recipe": recipe_output,
		"output": r["output"],
		"input": r["input"],
		"need": int(r["count"]),
		"quality": clampi(quality, 0, 2),
		"remain": int(r["minutes"]),
		"total": int(r["minutes"]),
	}
	return i

# ---------------- 时间推进 ----------------

## 推进 m 游戏分钟。返回**这一帧刚做完**的槽列表（供 main 弹提示 / 播音效）
func advance_minutes(m: int) -> Array:
	var done: Array = []
	if m <= 0:
		return done
	for i in range(slots.size()):
		var s = slots[i]
		if s == null or int(s["remain"]) <= 0:
			continue
		s["remain"] = int(s["remain"]) - m
		if int(s["remain"]) <= 0:
			s["remain"] = 0
			done.append(_snapshot(i, s))
	return done

## 跨日：加工坊 24 小时可用，跨日不重置任何东西。
## 留这个函数是为了「将来加通宵惩罚」时有地方写，顺便让 main 的跨日流程统一。
func advance_day() -> Array:
	return []

## 槽 i 的进度 0.0~1.0
func progress(i: int) -> float:
	var s = slots[i] if i >= 0 and i < slots.size() else null
	if s == null:
		return 0.0
	var total := maxf(1.0, float(s["total"]))
	return clampf(1.0 - float(s["remain"]) / total, 0.0, 1.0)

func is_ready(i: int) -> bool:
	var s = slots[i] if i >= 0 and i < slots.size() else null
	return s != null and int(s["remain"]) <= 0

func ready_count() -> int:
	var n := 0
	for i in range(slots.size()):
		if is_ready(i):
			n += 1
	return n

## 最近一个做好的槽（玩家对着机器按 E 时优先取它）
func first_ready() -> int:
	for i in range(slots.size()):
		if is_ready(i):
			return i
	return -1

## 第一个还在跑的槽（没做好就提示「还要 N 分钟」）
func first_running() -> int:
	for i in range(slots.size()):
		var s = slots[i]
		if s != null and int(s["remain"]) > 0:
			return i
	return -1

## 取走成品。返回 {output, count, quality, index}；没做好返回空字典。
func take(i: int) -> Dictionary:
	if not is_ready(i):
		return {}
	var s = slots[i]
	var out := {
		"index": i,
		"output": s["output"],
		"count": 1,
		"quality": int(s["quality"]),
	}
	slots[i] = null
	return out

## 取走所有做好的，返回列表
func take_all() -> Array:
	var out: Array = []
	for i in range(slots.size()):
		if is_ready(i):
			out.append(take(i))
	return out

func _snapshot(i: int, s: Dictionary) -> Dictionary:
	return {
		"index": i,
		"output": s["output"],
		"quality": int(s["quality"]),
	}

## 一句话状态（可交互物 prompt 用）
func status_text() -> String:
	var ready := ready_count()
	if ready > 0:
		return "有 %d 件加工好了" % ready
	var run := first_running()
	if run >= 0:
		return "加工中 · 还剩 %d 分" % int(slots[run]["remain"])
	if free_slots() <= 0:
		return "槽满"
	return "空闲 %d/%d 槽" % [free_slots(), slot_count()]

# ---------------- 存档（模块 8）----------------
#
# 槽位里的 recipe / output / input 是 StringName，JSON 回来会变 String，必须转回来：
# CropQuality.item_id() 和 RecipeDB 查表全按 StringName 走。

func to_dict() -> Dictionary:
	var arr: Array = []
	for s in slots:
		arr.append(s.duplicate(true) if s != null else null)
	return {"level": level, "slots": arr}

func from_dict(d: Dictionary) -> void:
	set_level(int(d.get("level", 1)))
	var src: Array = d.get("slots", [])
	for i in range(mini(src.size(), slots.size())):
		var raw: Variant = src[i]
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		slots[i] = {
			"recipe": StringName(str(raw.get("recipe", ""))),
			"output": StringName(str(raw.get("output", ""))),
			"input": StringName(str(raw.get("input", ""))),
			"need": maxi(0, int(raw.get("need", 0))),
			"quality": clampi(int(raw.get("quality", 0)), 0, 2),
			"remain": maxi(0, int(raw.get("remain", 0))),
			"total": maxi(1, int(raw.get("total", 1))),
		}
