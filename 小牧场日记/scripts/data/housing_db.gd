extends Node
## 棚舍表（模块 6 需求 A）—— autoload: HousingDB
##
## 表结构（8 列）：
##   id,name,price,material,material_count,base_capacity,capacity_step,max_level
##
## 为什么和 buildings.csv 分开：繁殖棚是「一次性落成」的独立建筑，
## 棚舍是「有等级、有容量、可扩建」的容器。字段完全不同，硬塞一张表只会互相拖累。
##
## 容量公式（唯一真相，Housing 和 UI 都从这里取）：
##   capacity_at(id, lv) = base_capacity + capacity_step × (lv - 1)
##   barn  Lv1/2/3 = 4 / 7 / 10
##   coop  Lv1/2/3 = 5 / 8 / 11
##   hive  Lv1/2/3 = 2 / 4 / 6
##
## 扩建价（同样是公式，CSV 只管基准价）：
##   upgrade_price(id, lv) = price × lv        （lv = 当前等级，0 = 从无到有）
##   upgrade_material_count(id, lv) = material_count × max(1, lv)

const CSV_PATH := "res://data/housing.csv"
const COLUMNS := 8

var housings: Dictionary = {}     ## StringName -> Dictionary

func _ready() -> void:
	load_csv()

func load_csv() -> void:
	housings.clear()
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		push_error("[HousingDB] 打不开 " + CSV_PATH)
		return
	f.get_csv_line()     # 跳过表头
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < COLUMNS:
			continue
		var id := row[0].strip_edges()
		if id == "":
			continue
		housings[StringName(id)] = {
			"id": StringName(id),
			"name": row[1].strip_edges(),
			"price": maxi(0, int(row[2])),
			"material": StringName(row[3].strip_edges()),
			"material_count": maxi(0, int(row[4])),
			"base_capacity": maxi(1, int(row[5])),
			"capacity_step": maxi(0, int(row[6])),
			"max_level": maxi(1, int(row[7])),
		}
	print("[HousingDB] 载入 %d 类棚舍" % housings.size())

func get_housing(id: StringName) -> Dictionary:
	return housings.get(id, {})

func has(id: StringName) -> bool:
	return housings.has(id)

func all_ids() -> Array:
	return housings.keys()

func name_of(id: StringName) -> String:
	return str(get_housing(id).get("name", id))

func price_of(id: StringName) -> int:
	return int(get_housing(id).get("price", 0))

func material_of(id: StringName) -> StringName:
	return StringName(get_housing(id).get("material", &""))

func material_count_of(id: StringName) -> int:
	return int(get_housing(id).get("material_count", 0))

func base_capacity_of(id: StringName) -> int:
	return int(get_housing(id).get("base_capacity", 1))

func capacity_step_of(id: StringName) -> int:
	return int(get_housing(id).get("capacity_step", 0))

func max_level_of(id: StringName) -> int:
	return int(get_housing(id).get("max_level", 1))

## lv 从 1 起（1 级 = 刚盖好）；lv <= 0 视为 0 容量
func capacity_at(id: StringName, lv: int) -> int:
	if lv <= 0 or not housings.has(id):
		return 0
	return base_capacity_of(id) + capacity_step_of(id) * (lv - 1)

## 从 lv 升到 lv+1 要多少钱（lv = 0 表示从空地开始盖）
func upgrade_price(id: StringName, lv: int) -> int:
	if lv <= 0:
		return price_of(id)
	return price_of(id) * lv

## 从 lv 升到 lv+1 要多少木材
func upgrade_material_count(id: StringName, lv: int) -> int:
	return material_count_of(id) * maxi(1, lv)

## "900G + 木材×15"（lv = 0 建造价 / lv >= 1 扩建价）
func cost_text(id: StringName, lv: int = 0) -> String:
	var b := get_housing(id)
	if b.is_empty():
		return ""
	return "%dG + %s×%d" % [upgrade_price(id, lv),
		ProductDB.display_name(material_of(id)), upgrade_material_count(id, lv)]

## "Lv1 · 3/4 只"（建筑提示条用）
func slot_text(id: StringName, lv: int, used: int) -> String:
	return "Lv%d · %d/%d 只" % [maxi(0, lv), used, capacity_at(id, maxi(1, lv))]
