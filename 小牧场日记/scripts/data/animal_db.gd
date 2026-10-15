extends Node
## 动物数据库（autoload: AnimalDB）
## 启动时读 res://data/animals.csv，全表常驻内存。

const CSV_PATH := "res://data/animals.csv"

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
		if row.size() < 12:
			continue
		var id := row[0].strip_edges()
		if id == "":
			continue
		var a := AnimalData.new()
		a.id = StringName(id)
		a.display_name = row[1].strip_edges()
		a.kind = row[2].strip_edges()
		a.price = int(row[3])
		a.product = StringName(row[4].strip_edges())
		a.product_min = int(row[5])
		a.product_max = int(row[6])
		a.product_high = StringName(row[7].strip_edges())
		a.high_chance = float(row[8])
		a.feed_freq = int(row[9])
		a.mature_days = int(row[10])
		a.timed_product = int(row[11]) != 0
		animals[a.id] = a
	print("[AnimalDB] 载入 %d 种动物" % animals.size())

func get_animal(id: StringName) -> AnimalData:
	return animals.get(id)

func all_ids() -> Array:
	return animals.keys()
