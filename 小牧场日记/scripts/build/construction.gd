class_name Construction
extends RefCounted
## 施工队列（模块 12 需求 2：建造需要游戏内 1–3 天）
##
## 为什么「施工中」要单独一个状态，而不是直接落一栋建筑再盖块布：
##   ① 建筑一旦落地就开始给加成（床位 / 加工速度 / 背包格），
##      施工期间不该生效 —— 不然玩家可以「先盖后等」，工期变成纯装饰。
##   ② 存档要能存「还剩几天」，读到一半不能凭空多出一栋。
##   ③ 建筑表里的 build_days 是 0–3，0 的（栅栏 / 繁殖棚）当场落成，
##      其余进这里排队。
##
## 数据结构（也是存档结构）：
##   sites = [
##     {def_id, x, y, days_left, total_days, day_started}
##   ]
##
## ⚠️ 占位用 footprint 判定：施工中的 3×2 鸡舍整块地都不能再放东西，
##    否则玩家能在脚手架里叠第二栋（BuildingGrid.can_place 会问 blocks()）。

var sites: Array = []

# ---------------- 查询 ----------------

func count() -> int:
	return sites.size()

func is_empty() -> bool:
	return sites.is_empty()

## 某个格子被脚手架占了吗（逐格扫 footprint，和 BuildingGrid 一套判定）
func blocks(cell: Vector2i) -> bool:
	for s in sites:
		var d: BuildingDef = BuildingDB.def_of(StringName(str(s["def_id"])))
		if d == null:
			continue
		for c in d.footprint_at(Vector2i(int(s["x"]), int(s["y"]))):
			if c == cell:
				return true
	return false

## 那格上的施工点（没有返回 {}）—— 用于「再按一次 E 取消/查看」
func site_at(cell: Vector2i) -> Dictionary:
	for s in sites:
		var d: BuildingDef = BuildingDB.def_of(StringName(str(s["def_id"])))
		if d == null:
			continue
		for c in d.footprint_at(Vector2i(int(s["x"]), int(s["y"]))):
			if c == cell:
				return s
	return {}

## 全部施工点的显示摘要（HUD 一行）
func summary_text() -> String:
	if sites.is_empty():
		return ""
	var parts: Array[String] = []
	for s in sites:
		parts.append("%s(%d天)" % [BuildingDB.name_of(StringName(str(s["def_id"]))),
			int(s["days_left"])])
	return "施工 " + " ".join(parts)

# ---------------- 开工 / 推进 ----------------

## 开工。days 来自 BuildingDef.build_days；返回新站点（存档用）
func start(def_id: StringName, anchor: Vector2i, days: int, day: int) -> Dictionary:
	var site := {
		"def_id": String(def_id),
		"x": anchor.x,
		"y": anchor.y,
		"days_left": maxi(1, days),
		"total_days": maxi(1, days),
		"day_started": day,
	}
	sites.append(site)
	return site

## 过一天：所有工地天数 -1。返回**今天竣工**的站点（并从队列里移除）。
func tick_day() -> Array:
	var done: Array = []
	var keep: Array = []
	for s in sites:
		s["days_left"] = int(s["days_left"]) - 1
		if int(s["days_left"]) <= 0:
			done.append(s)
		else:
			keep.append(s)
	sites = keep
	return done

## 一次推进 n 天（读档补进度 / 睡好几天的兜底），最多 n 天
func tick_days(n: int) -> Array:
	var done: Array = []
	for i in range(maxi(0, n)):
		done.append_array(tick_day())
	return done

# ---------------- 存档 ----------------

func to_dict() -> Dictionary:
	var out: Array = []
	for s in sites:
		out.append(s.duplicate(true))
	return {"sites": out}

func from_dict(d: Dictionary) -> void:
	sites.clear()
	for raw in d.get("sites", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var id := StringName(str(raw.get("def_id", "")))
		if id == &"" or BuildingDB.def_of(id) == null:
			continue                     # 表里删掉的建筑：丢掉，别让存档炸
		sites.append({
			"def_id": String(id),
			"x": int(raw.get("x", 0)),
			"y": int(raw.get("y", 0)),
			"days_left": maxi(1, int(raw.get("days_left", 1))),
			"total_days": maxi(1, int(raw.get("total_days", 1))),
			"day_started": int(raw.get("day_started", 1)),
		})

func reset() -> void:
	sites.clear()
