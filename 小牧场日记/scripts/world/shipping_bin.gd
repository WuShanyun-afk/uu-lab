class_name ShippingBin
extends Interactable
## 出货箱 —— 背包里的作物 / 畜产品 / 加工品一键换金币（GDD §11 经济闭环）
##
## 模块 7 改造：定价从「本文件自己乘」改成**统一走 Market.price()**。
##
## 以前是 CropQuality × SeasonEffects 两处相乘，只服务作物；
## 模块 7 之后订单奖励、商店回收也要同一套定价 —— 三处各写一遍迟早对不上。
## 现在唯一入口是 Market.price(item, season, day)，四个因子（基础价 / 品质 / 季节 / 行情）
## 都在那边算完。
##
## 展示与结算的区别：
##   base_price(id)  = 基础价 × 品质 × 季节   —— **标价**，不随行情抖，用来写价目表
##   unit_price(id)  = base_price × 当日行情  —— **实收**，出货按它结算
## 玩家想多赚就得挑行情高的那天出货，这是模块 7 新增的决策点。

func _ready() -> void:
	super()
	prompt_text = "卖东西"

func prompt() -> String:
	var n := sellable_count()
	return "E  出货（%d 件）" % n if n > 0 else "E  出货箱（空）"

## 这件东西能不能卖：ItemDB 说了算（作物 / 畜产品 / 加工品 = true，
## 种子 / 肥料 / 饲料 / 药剂 / 木材 = false）
func is_sellable(id: StringName) -> bool:
	return ItemDB.is_sellable(id)

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
	var trend := Market.trend_arrow(GameClock.day, Market.CAT_CROP)
	EventBus.world_message.emit("卖出 %d 种，共 %dG%s · 行情%s" % [kinds, total, note, trend])

## 实收单价（含当日行情）—— 出货结算用
func unit_price(id: StringName) -> int:
	return Market.price(id, GameClock.season, GameClock.day)

## 标价（不含行情）—— 价目表 / 测试基准用
func base_price(id: StringName) -> int:
	if ItemDB.resolve(id) == null:
		return 1
	var cat := Market.category_of(id)
	return maxi(1, int(round(float(ItemDB.price_of(id))
		* Market.season_multiplier(cat, GameClock.season))))

func _draw() -> void:
	draw_rect(Rect2(-14, -26, 28, 20), Color("#8B5E34"))
	draw_rect(Rect2(-14, -31, 28, 6), Color("#A9773F"))   # 掀开的盖
	draw_rect(Rect2(-14, -26, 28, 20), Color("#5C3A1E"), false, 1.0)
