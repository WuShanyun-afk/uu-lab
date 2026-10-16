extends Node
## 建筑表（模块 5 需求 4）—— autoload: BuildingDB
##
## 模块 5 只有一栋建筑：繁殖棚。但表结构是通用的：
##   id,name,price,material,material_count,gestation_days,note
## 以后加「鸡舍 / 谷仓 / 温室」= 加一行 CSV + 抄一遍 main 的建造流程。
##
## 为什么造价放 CSV 而不是常量：模块 4 的教训 —— 数值写死在脚本里，
## 想调平衡就得改代码 + 重跑测试，而 CSV 是能直接给策划改的。

const CSV_PATH := "res://data/buildings.csv"
const COLUMNS := 7

var buildings: Dictionary = {}     ## StringName -> Dictionary

func _ready() -> void:
	load_csv()

func load_csv() -> void:
	buildings.clear()
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		push_error("[BuildingDB] 打不开 " + CSV_PATH)
		return
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < COLUMNS:
			continue
		var id := row[0].strip_edges()
		if id == "":
			continue
		buildings[StringName(id)] = {
			"id": StringName(id),
			"name": row[1].strip_edges(),
			"price": int(row[2]),
			"material": StringName(row[3].strip_edges()),
			"material_count": int(row[4]),
			"gestation_days": maxi(1, int(row[5])),
			"note": row[6].strip_edges(),
		}
	print("[BuildingDB] 载入 %d 栋建筑" % buildings.size())

func get_building(id: StringName) -> Dictionary:
	return buildings.get(id, {})

func name_of(id: StringName) -> String:
	var b: Dictionary = get_building(id)
	return str(b.get("name", id))

func price_of(id: StringName) -> int:
	return int(get_building(id).get("price", 0))

func material_of(id: StringName) -> StringName:
	return get_building(id).get("material", &"")

func material_count_of(id: StringName) -> int:
	return int(get_building(id).get("material_count", 0))

func gestation_days_of(id: StringName) -> int:
	return int(get_building(id).get("gestation_days", 1))

## "1200G + 木材×20"
func cost_text(id: StringName) -> String:
	var b: Dictionary = get_building(id)
	if b.is_empty():
		return ""
	return "%dG + %s×%d" % [int(b["price"]), ProductDB.display_name(b["material"]),
		int(b["material_count"])]

func all_ids() -> Array:
	return buildings.keys()
