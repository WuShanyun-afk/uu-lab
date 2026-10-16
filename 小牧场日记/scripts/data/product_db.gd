extends Node
## 产物 / 消耗品数据库（autoload: ProductDB）
##
## 牛奶、鸡蛋、饲料…… 都是「物品」。HUD 显示名字、出货箱结算、动物商店
## 都从这里取，不在代码里写死。
##
## 模块 4 新增：**品质后缀**。
## 和作物同一套编码（CropQuality）：`milk` / `milk_silver` / `milk_gold`。
## 好处是背包结构一行不改，出货箱的 CropQuality.price_mult 直接复用。
## 于是「挤奶小游戏打出完美 → 金星牛奶 → 卖得更贵」这条链路是通的。

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

## 带品质的产物 item id（品质 0/1/2 → 无后缀 / _silver / _gold）
static func item_id(base: StringName, quality: int) -> StringName:
	return CropQuality.item_id(base, quality)

## 是不是本表里的东西（自动剥掉品质后缀）
func has(id: StringName) -> bool:
	return products.has(_base(id))

func get_product(id: StringName) -> Dictionary:
	return products.get(_base(id), {})

func display_name(id: StringName) -> String:
	var p: Dictionary = get_product(id)
	if p.is_empty():
		return str(id)
	return CropQuality.label(str(p.get("name", id)), _quality(id))

## 单价（含品质倍率 1.0 / 1.5 / 2.0，与作物共用 CropQuality.PRICE_MULT）
func price(id: StringName) -> int:
	var p: Dictionary = get_product(id)
	if p.is_empty():
		return 0
	return int(round(float(p.get("price", 0)) * CropQuality.price_mult(_quality(id))))

func kind_of(id: StringName) -> String:
	var p: Dictionary = get_product(id)
	return str(p.get("kind", ""))

func _base(id: StringName) -> StringName:
	return CropQuality.split(id)["id"]

func _quality(id: StringName) -> int:
	return int(CropQuality.split(id)["quality"])
