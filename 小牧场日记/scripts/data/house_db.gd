extends Node
## 住宅等级表（模块 12 / 需求 3）—— autoload: HouseDB
##
## 为什么住宅不进 data/buildings.csv：
##   建造系统里的建筑是「占一块地的一次性物件」，而住宅是**玩家自己的房子**：
##   有独立的室内场景、三级功能解锁、家具摆放。把它塞进 buildings 表的结果是
##   那张表要长出一堆只有住宅用得上的列（室内尺寸 / 解锁功能 / 家具位）。
##   所以住宅单独一张表，`GameState.house_level` 是它的真源等级。
##
## 升级流程（需求 3）：
##   E 对着屋内的工作台 → 查 level → 要钱要料 → 扣 → 进入「施工」build 天数
##   → 工期满 → house_level +1 → 室内道具与外观立刻变
##
## 1 级：只能睡觉 / 存档
## 2 级：加厨房（做饭 → 家常菜，当天动物友好度 +5）
## 3 级：加地下室（酿酒 → 蜂蜜酒）

const CSV_PATH := "res://data/house_levels.csv"
const MAX_LEVEL := 3
## 住宅升级的工期（游戏日）：Lv1→2 要 2 天，Lv2→3 要 3 天
const BUILD_DAYS := {2: 2, 3: 3}

var levels: Array = []     ## [{level, name, wood, stone, gold, unlock, interior}]

func _ready() -> void:
	load_csv()

func load_csv() -> void:
	levels.clear()
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		push_error("[HouseDB] 打不开 " + CSV_PATH)
		return
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 4 or row[0].strip_edges() == "":
			continue
		levels.append({
			"level": int(row[0]),
			"name": row[1].strip_edges(),
			"wood": maxi(0, int(row[2])),
			"stone": maxi(0, int(row[3])),
			"gold": maxi(0, int(row[4])),
			"unlock": row[5].strip_edges() if row.size() > 5 else "",
			"interior": row[6].strip_edges() if row.size() > 6 else "",
		})
	levels.sort_custom(func(a, b): return int(a["level"]) < int(b["level"]))
	print("[HouseDB] 载入 %d 级住宅" % levels.size())

func info(level: int) -> Dictionary:
	for l in levels:
		if int(l["level"]) == clampi(level, 1, MAX_LEVEL):
			return l
	return {}

func name_of(level: int) -> String:
	return str(info(level).get("name", "小木屋"))

func unlock_of(level: int) -> String:
	return str(info(level).get("unlock", ""))

func interior_of(level: int) -> String:
	return str(info(level).get("interior", ""))

## 从 level 升到 level+1 要什么（level 已是满级返回 {}）
func upgrade_cost(level: int) -> Dictionary:
	if level >= MAX_LEVEL:
		return {}
	var nxt := info(level + 1)
	if nxt.is_empty():
		return {}
	return {
		"gold": int(nxt["gold"]),
		"wood": int(nxt["wood"]),
		"stone": int(nxt["stone"]),
		"to": level + 1,
		"days": int(BUILD_DAYS.get(level + 1, 1)),
		"name": str(nxt["name"]),
	}

func can_upgrade(level: int) -> bool:
	return level < MAX_LEVEL

## "睡觉 · 存档 · 摆家具 / 做饭 / 酿酒" —— 当前等级已经有的功能（HUD / 提示条用）
func features_text(level: int) -> String:
	var parts: Array[String] = ["睡觉", "存档", "摆家具"]
	if level >= 2:
		parts.append("做饭")
	if level >= 3:
		parts.append("酿酒")
	return " · ".join(parts)
