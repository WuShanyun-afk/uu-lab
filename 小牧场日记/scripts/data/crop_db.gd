extends Node
## 作物数据库（autoload: CropDB）
## 启动时读 res://data/crops.csv，全表常驻内存。
##
## 表结构：id,name,season,grow_days,seed_price,sell_price,regrow_days,fertilize,color

const CSV_PATH := "res://data/crops.csv"
const SEASON_NAME := ["春", "夏", "秋", "冬"]
const COLUMNS := 9

var crops: Dictionary = {}     ## StringName -> CropData
## 季节 → 该季作物 id 列表（启动时建索引，避免每次遍历全表）
var by_season: Dictionary = {}

func _ready() -> void:
	load_csv()

func load_csv() -> void:
	crops.clear()
	by_season.clear()
	for s in range(4):
		by_season[s] = []
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		push_error("[CropDB] 打不开 " + CSV_PATH)
		return
	var _header := f.get_csv_line()     # 跳过表头
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 8:
			continue
		var id := row[0].strip_edges()
		if id == "":
			continue
		var c := CropData.new()
		c.id = StringName(id)
		c.display_name = row[1].strip_edges()
		c.season = clampi(int(row[2]), 0, 3)
		c.grow_days = maxi(1, int(row[3]))
		c.seed_price = int(row[4])
		c.sell_price = int(row[5])
		c.regrow_days = maxi(0, int(row[6]))
		c.fertilize = clampi(int(row[7]), 0, 2)
		if row.size() > 8 and row[8].strip_edges() != "":
			c.color = row[8].strip_edges()
		crops[c.id] = c
		(by_season[c.season] as Array).append(c.id)
	print("[CropDB] 载入 %d 种作物（春 %d / 夏 %d / 秋 %d / 冬 %d）" % [
		crops.size(),
		(by_season[0] as Array).size(), (by_season[1] as Array).size(),
		(by_season[2] as Array).size(), (by_season[3] as Array).size(),
	])

func get_crop(id: StringName) -> CropData:
	return crops.get(id)

func all_ids() -> Array:
	return crops.keys()

## 全表按季节顺序排好（种子切换 UI 用）
func ordered_ids() -> Array:
	var out: Array = []
	for s in range(4):
		out.append_array(by_season[s])
	return out

## 某一季的作物（模块 3 需求 2：每季 6-8 种）
func of_season(s: int) -> Array:
	return (by_season.get(s, []) as Array).duplicate()

func season_of(id: StringName) -> int:
	var c: CropData = get_crop(id)
	return c.season if c != null else -1

## 背包 item id → CropData（自动剥掉 _silver / _gold 后缀）
## 不是作物就返回 null。
func crop_of_item(item: StringName) -> CropData:
	var base: StringName = CropQuality.split(item)["id"]
	return get_crop(base)

## 某一品质的单价（不含季节倍率，季节倍率由出货箱套）
func quality_price(id: StringName, q: int) -> int:
	var c: CropData = get_crop(id)
	if c == null:
		return 0
	return int(round(float(c.sell_price) * CropQuality.price_mult(q)))

## 某一品质单价（背包 item id 版）
func item_price(item: StringName) -> int:
	var p := CropQuality.split(item)
	var c: CropData = get_crop(p["id"])
	if c == null:
		return 0
	return int(round(float(c.sell_price) * CropQuality.price_mult(int(p["quality"]))))

# ---------------- 种子物品（模块 4 种子商店）----------------
#
# 种子也做成背包物品：`seed_<crop_id>`。
# 好处：种子商店、背包、HUD 全部复用现有管线，不用新建「种子库存」这一套。
# 出货箱不会误卖种子（crop_of_item / ProductDB 都不认识 seed_ 前缀）。

const SEED_PREFIX := "seed_"

func seed_item(id: StringName) -> StringName:
	return StringName(SEED_PREFIX + str(id))

## 背包 item id → 对应作物（不是种子返回 null）
func crop_of_seed_item(item: StringName) -> CropData:
	var s := str(item)
	if not s.begins_with(SEED_PREFIX):
		return null
	return get_crop(StringName(s.substr(SEED_PREFIX.length())))

## 背包里某一季的种子总数（种子商店 / HUD 用）
func season_seed_count(s: int) -> int:
	var n := 0
	for id in of_season(s):
		n += GameState.count_item(seed_item(id))
	return n
