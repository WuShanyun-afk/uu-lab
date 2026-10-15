extends Node
## 作物数据库（autoload: CropDB）
## 启动时读 res://data/crops.csv，全表常驻内存。

const CSV_PATH := "res://data/crops.csv"

var crops: Dictionary = {}     ## StringName -> CropData

func _ready() -> void:
	load_csv()

func load_csv() -> void:
	crops.clear()
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		push_error("[CropDB] 打不开 " + CSV_PATH)
		return
	var header := f.get_csv_line()     # 跳过表头
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
		c.season = int(row[2])
		c.grow_days = int(row[3])
		c.seed_price = int(row[4])
		c.sell_price = int(row[5])
		c.regrow_days = int(row[6])
		c.fertilize = int(row[7])
		crops[c.id] = c
	print("[CropDB] 载入 %d 种作物" % crops.size())

func get_crop(id: StringName) -> CropData:
	return crops.get(id)

func all_ids() -> Array:
	return crops.keys()
