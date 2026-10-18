extends Node
## 建筑表 —— autoload: BuildingDB
##
## 模块 5 只有一栋建筑（繁殖棚），模块 9 扩成「全项目可建造物的总表」：
##   id,name,category,size_x,size_y,price,material,material_count,gestation_days,
##   max_level,capacity_housing,capacity_base,capacity_step,efficiency,stage_required,note
##
## 两个身份：
##   ① `def_of(id) -> BuildingDef` —— 模块 9 建造系统用的强类型壳
##   ② `get_building(id) -> Dictionary` —— 模块 5 的老接口，繁殖棚那段代码还在用
## 两套读数同一份 CSV，不存两份真值。
##
## 为什么不把列顺序写死成 `row[13] = ...`：
##   模块 4 的教训 —— 加一列就要去改 8 个下标，改漏一个不报错、只是数值全错。
##   所以这里按**表头名字**建列索引，加列只改 CSV + Def 的字段。

const CSV_PATH := "res://data/buildings.csv"
## 老接口的兼容列数：模块 5 时代只有 7 列，现在 16 列。少于 7 列的行直接丢。
const MIN_COLUMNS := 7

## StringName -> BuildingDef
var defs: Dictionary = {}
## 表头名 -> 列下标（按名字取值，别按位置）
var _columns: Dictionary = {}

func _ready() -> void:
	load_csv()

func load_csv() -> void:
	defs.clear()
	_columns.clear()
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		push_error("[BuildingDB] 打不开 " + CSV_PATH)
		return
	var header := f.get_csv_line()
	for i in range(header.size()):
		_columns[header[i].strip_edges()] = i
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < MIN_COLUMNS:
			continue
		var id := row[0].strip_edges()
		if id == "":
			continue
		# 老格式（模块 5 的 7 列）也要能读：缺的列补缺省值
		var d := BuildingDef.from_row(_padded(row))
		if d.id == &"":
			continue
		defs[d.id] = d
	print("[BuildingDB] 载入 %d 种可建造物" % defs.size())

## 把一行补齐到 18 列（模块 12 加了 stone_count / build_days），缺的位置填 ""
func _padded(row: PackedStringArray) -> PackedStringArray:
	var out := row
	while out.size() < 18:
		out.append("")
	return out

# ---------------- 新接口（模块 9）----------------

func def_of(id: StringName) -> BuildingDef:
	return defs.get(id, null)

func has(id: StringName) -> bool:
	return defs.has(id)

func all_ids() -> Array:
	return defs.keys()

## 建造菜单里能选的那些（排除繁殖棚这种走剧情的），按**解锁阶段 → 价格**排序。
## 排序在 DB 里做一次，UI 和测试都拿同一份顺序。
func buildable_ids() -> Array:
	var out: Array = []
	for id in defs:
		var d: BuildingDef = defs[id]
		if d.buildable():
			out.append(id)
	out.sort_custom(func(a, b):
		var da: BuildingDef = defs[a]
		var db: BuildingDef = defs[b]
		if da.stage_required != db.stage_required:
			return da.stage_required < db.stage_required
		return da.price < db.price)
	return out

## 某一阶段能盖哪些（建造菜单按阶段过滤 —— 还没解锁的不显示，而不是灰显一排）
func ids_unlocked_at(stage: int) -> Array:
	var out: Array = []
	for id in buildable_ids():
		if defs[id].stage_required <= stage:
			out.append(id)
	return out

# ---------------- 老接口（模块 5 兼容）----------------

func get_building(id: StringName) -> Dictionary:
	var d: BuildingDef = def_of(id)
	if d == null:
		return {}
	return {
		"id": d.id,
		"name": d.display_name,
		"price": d.price,
		"material": d.material,
		"material_count": d.material_count,
		"gestation_days": maxi(1, d.gestation_days),
		"note": d.note,
	}

func name_of(id: StringName) -> String:
	var d: BuildingDef = def_of(id)
	return d.display_name if d != null else str(id)

func price_of(id: StringName) -> int:
	var d: BuildingDef = def_of(id)
	return d.price if d != null else 0

func material_of(id: StringName) -> StringName:
	var d: BuildingDef = def_of(id)
	return d.material if d != null else &""

func material_count_of(id: StringName) -> int:
	var d: BuildingDef = def_of(id)
	return d.material_count if d != null else 0

func gestation_days_of(id: StringName) -> int:
	var d: BuildingDef = def_of(id)
	return maxi(1, d.gestation_days) if d != null else 1

## "1200G + 木材×20"
func cost_text(id: StringName) -> String:
	var d: BuildingDef = def_of(id)
	return d.cost_text() if d != null else ""
