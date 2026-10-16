class_name AnimalShop
extends Interactable
## 动物商店（模块 4 需求 1 / 2）—— 货架 = AnimalDB 全表按价格升序
##
## 买下的都是**成年**动物，并且立刻给一次产出（debug_ready_produce），
## 目的是让玩家买完就能马上试挤奶小游戏，不用等 7 天。
##
## ⚠️ 同样不碰 UI / 不碰金币：只发 shop_requested。

const SHOP_ID := &"animal"

func _ready() -> void:
	super()
	prompt_text = "动物商店"

func prompt() -> String:
	return "E  动物商店（%d 种）" % AnimalDB.animals.size()

func interact(_player: Node) -> void:
	EventBus.shop_requested.emit(SHOP_ID)

## 一个带围栏的牌子 + 动物剪影（纯 _draw）
func _draw() -> void:
	var wood := Color("#8B5E34")
	var dark := Color("#5C3A1E")
	var board := Color("#A9773F")
	draw_rect(Rect2(-2, -20, 4, 16), wood)              # 立柱
	draw_rect(Rect2(-18, -42, 36, 24), board)           # 板子
	draw_rect(Rect2(-18, -42, 36, 24), dark, false, 1.0)
	draw_rect(Rect2(-13, -37, 10, 7), Color("#F2F0EA")) # 牛剪影
	draw_rect(Rect2(-13, -39, 3, 3), dark)
	draw_rect(Rect2(1, -36, 6, 6), Color("#FFF6E0"))    # 鸡剪影
	draw_rect(Rect2(2, -38, 3, 2), Color("#E04A3A"))
	draw_rect(Rect2(-13, -27, 26, 2), dark)             # 一行字
