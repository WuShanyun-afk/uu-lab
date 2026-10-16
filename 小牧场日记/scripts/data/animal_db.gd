extends Node
## 动物数据库（autoload: AnimalDB）
## 启动时读 res://data/animals.csv，全表常驻内存。
##
## 表结构（17 列，见 AnimalData）：
##   id,name,kind,housing,price,product,product_min,product_max,product_high,
##   high_chance,feed_freq,mature_days,produce_action,produce_window,
##   produce_period,brushable,pet_limit
##
## 容错：列数不足时用默认值补齐（旧版 12 列的表也能读，不会崩）。

const CSV_PATH := "res://data/animals.csv"
const COLUMNS := 17

var animals: Dictionary = {}     ## StringName -> AnimalData

func _ready() -> void:
	load_csv()

func load_csv() -> void:
	animals.clear()
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		push_error("[AnimalDB] 打不开 " + CSV_PATH)
		return
	f.get_csv_line()     # 跳过表头
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < COLUMNS:
			continue
		var id := row[0].strip_edges()
		if id == "":
			continue
		var a := AnimalData.new()
		a.id = StringName(id)
		a.display_name = row[1].strip_edges()
		a.kind = row[2].strip_edges()
		a.housing = row[3].strip_edges()
		a.price = int(row[4])
		a.product = StringName(row[5].strip_edges())
		a.product_min = int(row[6])
		a.product_max = int(row[7])
		a.product_high = StringName(row[8].strip_edges())
		a.high_chance = float(row[9])
		a.feed_freq = int(row[10])
		a.mature_days = int(row[11])
		a.produce_action = row[12].strip_edges()
		a.produce_window = int(row[13])
		a.produce_period = maxi(1, int(row[14]))
		a.brushable = int(row[15]) != 0
		a.pet_limit = maxi(0, int(row[16]))
		a.timed_product = a.produce_window > 0
		animals[a.id] = a
	print("[AnimalDB] 载入 %d 种动物" % animals.size())

func get_animal(id: StringName) -> AnimalData:
	return animals.get(id)

func all_ids() -> Array:
	return animals.keys()

## 全表按「价格升序」排好（商店列表用，便宜的在前）
func ids_by_price() -> Array:
	var out := animals.values()
	out.sort_custom(func(x: AnimalData, y: AnimalData) -> bool: return x.price < y.price)
	var ids: Array = []
	for a in out:
		ids.append(a.id)
	return ids

## 同一棚舍的动物（畜舍 / 禽舍 / 蜂箱）
func of_housing(h: String) -> Array:
	var out: Array = []
	for a in animals.values():
		if a.housing == h:
			out.append(a.id)
	return out
