class_name ShippingBin
extends Interactable
## 出货箱 —— 背包里的作物/畜产品一键换金币（GDD §11 经济闭环最小版）
##
## 价格一律来自数据表：作物查 CropDB.sell_price，畜产品查 ProductDB.price。
## 本文件里**没有任何写死的数值**，改价格 = 改 CSV。
##
## 模块 3 新增两件事：
##   1. 品质倍率 —— 背包里的 turnip_gold 按金星 ×1.5 结算（CropQuality）
##   2. 只卖能卖的东西 —— 肥料 / 饲料是 kind=consumable，留在背包里，不会被顺手卖掉

func _ready() -> void:
	super()
	prompt_text = "卖东西"

func prompt() -> String:
	var n := sellable_count()
	return "E  出货（%d 件）" % n if n > 0 else "E  出货箱（空）"

## 这件东西能不能卖：作物 → 能；畜产品（kind=animal）→ 能；消耗品 / 肥料 → 不能
func is_sellable(id: StringName) -> bool:
	if CropDB.crop_of_item(id) != null:
		return true
	var p := ProductDB.get_product(id)
	return str(p.get("kind", "")) == "animal"

## 背包里一共有多少件可卖的东西
func sellable_count() -> int:
	var n := 0
	for id in GameState.inventory.keys():
		if is_sellable(id):
			n += GameState.count_item(id)
	return n

func interact(_player: Node) -> void:
	var total := 0
	var kinds := 0
	var shiny := 0
	for id in GameState.inventory.keys().duplicate():
		if not is_sellable(id):
			continue
		var count := GameState.count_item(id)
		if count <= 0:
			continue
		total += unit_price(id) * count
		kinds += 1
		if int(CropQuality.split(id)["quality"]) > 0:
			shiny += count
		GameState.remove_item(id, count)
	if total <= 0:
		EventBus.world_message.emit("出货箱是空的，先去收获点东西")
		return
	GameState.add_gold(total)
	var note := "" if shiny == 0 else "（含 %d 件银星/金星）" % shiny
	EventBus.world_message.emit("卖出 %d 种，共 %dG%s" % [kinds, total, note])

## 单价：作物表 → 产物表 → 兜底 1G
## 秋季作物售价 +10%（GDD §2.1），倍率来自 SeasonEffects，本文件不写死数值。
## 品质倍率来自 CropQuality（普通 ×1 / 银星 ×1.25 / 金星 ×1.5）。
func unit_price(id: StringName) -> int:
	var p := CropQuality.split(id)
	var c: CropData = CropDB.get_crop(p["id"])
	if c != null:
		var mult := SeasonEffects.crop_price_multiplier(GameClock.season)
		return int(round(float(c.sell_price) * CropQuality.price_mult(int(p["quality"])) * mult))
	if ProductDB.has(id):
		return ProductDB.price(id)
	return 1

func _draw() -> void:
	draw_rect(Rect2(-14, -26, 28, 20), Color("#8B5E34"))
	draw_rect(Rect2(-14, -31, 28, 6), Color("#A9773F"))   # 掀开的盖
	draw_rect(Rect2(-14, -26, 28, 20), Color("#5C3A1E"), false, 1.0)
