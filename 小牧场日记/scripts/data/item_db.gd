extends Node
## 物品总库（autoload: ItemDB）—— 模块 7 的统一物品视图
##
## 模块 3 之后，物品被拆散在四个地方：CropDB（作物）、CropDB 的 seed_ 前缀（种子）、
## ProductDB（畜产 / 消耗 / 材料）、Fertilizer（肥料）。每个系统自己认自己那套，
## 想做「一个背包界面列出所有东西」就得写四路 if。
##
## 本文件把它们**聚合**成 ItemDef：
##   作物 → Cat.CROP     种子 seed_<id> → Cat.SEED
##   products.csv kind=animal → PRODUCT · crafted → CRAFTED
##                    consumable → CONSUMABLE · material → MATERIAL
##   fertilizer / fertilizer_high → CONSUMABLE
##   upgrades.csv → TOOL（不进背包，买了直接生效）
##
## ⚠️ 本文件**不复制数值**。base_price 是运行时从各自 DB 读来的快照，
##    改 CSV 之后调 rebuild() 就同步（测试里常这么干）。
## ⚠️ 品质不进 ItemDef：item id 带 _silver / _gold 后缀，resolve() 自动拆。

const UPGRADE_CSV := "res://data/upgrades.csv"

var items: Dictionary = {}        ## StringName(基础 id) -> ItemDef
var _by_cat: Dictionary = {}      ## Cat -> Array[StringName]
var upgrades: Dictionary = {}     ## StringName(upgrade_id) -> {id, tool, level, price, ...}

func _ready() -> void:
	rebuild()

func rebuild() -> void:
	items.clear()
	_by_cat.clear()
	for c in range(ItemDef.Cat.size()):
		_by_cat[c] = []
	_build_crops()
	_build_seeds()
	_build_products()
	_build_fertilizers()
	_build_upgrades()
	print("[ItemDB] 聚合 %d 项物品（%s）" % [items.size(), _cat_summary()])

func _cat_summary() -> String:
	var parts: Array[String] = []
	for c in range(ItemDef.Cat.size()):
		parts.append("%s %d" % [ItemDef.CAT_NAME[c], (_by_cat[c] as Array).size()])
	return " / ".join(parts)

# ---------------- 构建 ----------------

func _build_crops() -> void:
	for id in CropDB.all_ids():
		var c: CropData = CropDB.get_crop(id)
		if c == null:
			continue
		var d := ItemDef.new()
		d.id = c.id
		d.display_name = c.display_name
		d.category = ItemDef.Cat.CROP
		d.base_price = c.sell_price
		d.stack_max = 99
		d.sellable = true
		d.color = Color(c.color) if c.color != "" else _fallback_color(c.id)
		d.note = "%s季 · %d 天成熟%s" % [
			c.season_name(), c.grow_days, " · 可再生" if c.regrow_days > 0 else ""]
		_add(d)

func _build_seeds() -> void:
	for id in CropDB.all_ids():
		var c: CropData = CropDB.get_crop(id)
		if c == null:
			continue
		var d := ItemDef.new()
		d.id = CropDB.seed_item(id)
		d.display_name = "%s种子" % c.display_name
		d.category = ItemDef.Cat.SEED
		d.base_price = c.seed_price
		d.stack_max = 99
		d.sellable = false            # 种子不进出货箱（模块 3 的老规矩，别改）
		d.buyable = true
		d.color = Color("#C9B27A")
		d.note = "%s季 · %d 天成熟 · 卖 %dG" % [c.season_name(), c.grow_days, c.sell_price]
		_add(d)

func _build_products() -> void:
	for id in ProductDB.products.keys():
		var p: Dictionary = ProductDB.get_product(id)
		if p.is_empty():
			continue
		var kind := str(p.get("kind", ""))
		var d := ItemDef.new()
		d.id = StringName(id)
		d.display_name = str(p.get("name", id))
		d.base_price = int(p.get("price", 0))
		d.stack_max = 99
		d.sellable = kind == "animal" or kind == "crafted"
		d.buyable = kind == "consumable" or kind == "material"
		d.color = _product_color(d.id)
		match kind:
			"animal":
				d.category = ItemDef.Cat.PRODUCT
				d.note = "畜产品"
			"crafted":
				d.category = ItemDef.Cat.CRAFTED
				d.note = "加工品"
			"consumable":
				d.category = ItemDef.Cat.CONSUMABLE
				d.note = "消耗品"
			_:
				d.category = ItemDef.Cat.MATERIAL
				d.note = "材料"
		_add(d)

func _build_fertilizers() -> void:
	for lv in [Fertilizer.Level.BASIC, Fertilizer.Level.HIGH]:
		var d := ItemDef.new()
		d.id = Fertilizer.item_id(lv)
		d.display_name = Fertilizer.level_name(lv)
		d.category = ItemDef.Cat.CONSUMABLE
		d.base_price = Fertilizer.price(lv)
		d.stack_max = 99
		d.sellable = false            # 肥料不进出货箱
		d.buyable = true
		d.color = Fertilizer.SOIL_MARK[lv]
		d.note = "施肥 · 提升品质率"
		_add(d)

func _build_upgrades() -> void:
	upgrades.clear()
	var f := FileAccess.open(UPGRADE_CSV, FileAccess.READ)
	if f == null:
		push_error("[ItemDB] 打不开 " + UPGRADE_CSV)
		return
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 8:
			continue
		var uid := row[0].strip_edges()
		if uid == "":
			continue
		var u := {
			"id": StringName(uid),
			"tool": StringName(row[1].strip_edges()),
			"level": maxi(2, int(row[2])),
			"price": int(row[3]),
			"material": StringName(row[4].strip_edges()),
			"material_count": int(row[5]),
			"name": row[6].strip_edges(),
			"note": row[7].strip_edges(),
		}
		upgrades[u["id"]] = u
		var d := ItemDef.new()
		d.id = u["id"]
		d.display_name = u["name"]
		d.category = ItemDef.Cat.TOOL
		d.base_price = u["price"]
		d.stack_max = 1
		d.sellable = false
		d.buyable = true
		d.color = Color("#9FB6C9")
		d.note = u["note"]
		_add(d)

func _add(d: ItemDef) -> void:
	items[d.id] = d
	(_by_cat[d.category] as Array).append(d.id)

# ---------------- 查询 ----------------

## item id（可带品质后缀）→ ItemDef。不认识返回 null。
func resolve(item_id: StringName) -> ItemDef:
	var base: StringName = CropQuality.split(item_id)["id"]
	return items.get(base)

func has(item_id: StringName) -> bool:
	return resolve(item_id) != null

func quality_of(item_id: StringName) -> int:
	return int(CropQuality.split(item_id)["quality"])

func base_id(item_id: StringName) -> StringName:
	return CropQuality.split(item_id)["id"]

func category_of(item_id: StringName) -> int:
	var d := resolve(item_id)
	return d.category if d != null else -1

## 带品质前缀的显示名（"金星牛奶" / "芜菁种子"）
func display_name(item_id: StringName) -> String:
	var d := resolve(item_id)
	if d == null:
		return str(item_id)
	return CropQuality.label(d.display_name, quality_of(item_id))

## 单价：基础价 × 品质倍率。**不含**季节与行情 —— 那两样在 Market。
func price_of(item_id: StringName) -> int:
	var d := resolve(item_id)
	if d == null:
		return 1
	return d.price_with_quality(quality_of(item_id))

func stack_max(item_id: StringName) -> int:
	var d := resolve(item_id)
	return d.stack_max if d != null else 99

func color_of(item_id: StringName) -> Color:
	var d := resolve(item_id)
	return d.color if d != null else Color("#888888")

func is_sellable(item_id: StringName) -> bool:
	var d := resolve(item_id)
	return d != null and d.sellable

func of_category(cat: int) -> Array:
	return (_by_cat.get(cat, []) as Array).duplicate()

## 出货箱 / 订单池用：所有能卖的基础 id（不含品质后缀）
func sellable_ids() -> Array:
	var out: Array = []
	for c in [ItemDef.Cat.CROP, ItemDef.Cat.PRODUCT, ItemDef.Cat.CRAFTED]:
		out.append_array(of_category(c))
	return out

func crafted_ids() -> Array:
	return of_category(ItemDef.Cat.CRAFTED)

func all_ids() -> Array:
	return items.keys()

# ---------------- 工具升级 ----------------

func upgrade_ids() -> Array:
	return upgrades.keys()

func get_upgrade(uid: StringName) -> Dictionary:
	return upgrades.get(uid, {})

## 某个工具当前等级的下一次升级（没有更高级返回空字典）
func next_upgrade(tool: StringName, cur_level: int) -> Dictionary:
	var best: Dictionary = {}
	for uid in upgrades.keys():
		var u: Dictionary = upgrades[uid]
		if u["tool"] != tool:
			continue
		if int(u["level"]) <= cur_level:
			continue
		if best.is_empty() or int(u["level"]) < int(best["level"]):
			best = u
	return best

# ---------------- 颜色兜底 ----------------

## 产物配色：常见项手工挑色，其余用 id 的稳定哈希出柔和色
func _product_color(id: StringName) -> Color:
	var table := {
		&"milk": "#F4F1E4", &"milk_large": "#F8F6EE",
		&"goat_milk": "#EFEAD8", &"goat_milk_large": "#F6F2E6",
		&"wool": "#E8E2D2", &"wool_fine": "#F3EEE2",
		&"alpaca_wool": "#D8C7B0", &"alpaca_wool_fine": "#E6D9C6",
		&"truffle": "#5B4032", &"truffle_premium": "#6E4E3C",
		&"egg": "#F2E2C4", &"gold_egg": "#E8C05A",
		&"duck_egg": "#DCE6D2", &"duck_egg_jumbo": "#E6EFDD",
		&"turkey_egg": "#EBD8C4", &"turkey_egg_jumbo": "#F2E4D2",
		&"honey": "#E8A93B", &"royal_jelly": "#F0D07A",
		&"feed": "#C9A45B", &"medicine": "#9FB6C9", &"wood": "#8A6A45",
		&"cheese": "#F0C24E", &"fine_cheese": "#F7D469",
		&"goat_cheese": "#E8E0B8", &"yarn": "#C98A6B",
		&"fine_yarn": "#DDA98C", &"alpaca_yarn": "#BFA98C",
		&"mayonnaise": "#F6F0D8", &"gold_mayonnaise": "#EBC766",
		&"duck_mayo": "#E4EAD6", &"truffle_oil": "#7A5A2E",
		&"mead": "#D9A94E",
	}
	if table.has(id):
		return Color(table[id])
	return _fallback_color(id)

func _fallback_color(id: StringName) -> Color:
	var h := absi(hash(str(id)))
	return Color.from_hsv(float(h % 360) / 360.0, 0.45, 0.80)
