extends Node
## 产物 / 消耗品数据库（autoload: ProductDB）
##
## 牛奶、鸡蛋、饲料…… 都是「物品」。HUD 显示名字、商店（里程碑 4）卖东西
## 都从这里取，不在代码里写死。

const CSV_PATH := "res://data/products.csv"

var products: Dictionary = {}     ## StringName -> {id, name, price, kind}

func _ready() -> void:
	load_csv()

func load_csv() -> void:
	products.clear()
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		push_error("[ProductDB] 打不开 " + CSV_PATH)
		return
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 4:
			continue
		var id := row[0].strip_edges()
		if id == "":
			continue
		products[StringName(id)] = {
			"id": StringName(id),
			"name": row[1].strip_edges(),
			"price": int(row[2]),
			"kind": row[3].strip_edges(),
		}
	print("[ProductDB] 载入 %d 项" % products.size())

func has(id: StringName) -> bool:
	return products.has(id)

func get_product(id: StringName) -> Dictionary:
	return products.get(id, {})

func display_name(id: StringName) -> String:
	var p: Dictionary = get_product(id)
	return p.get("name", str(id))

func price(id: StringName) -> int:
	var p: Dictionary = get_product(id)
	return int(p.get("price", 0))
