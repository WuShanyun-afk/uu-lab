class_name SupplyShop
extends Interactable
## 杂货铺（模块 5）—— 卖饲料 / 药剂 / 木材
##
## 为什么模块 5 才开这家店：模块 4 的 20 份干草饲料是**开局补给，没有补货渠道**，
## 用完就永远喂不了动物了。模块 5 又刚好需要「药剂」（治病）和「木材」（盖繁殖棚），
## 三样都是消耗品，一家店全包。
##
## ⚠️ 本文件不碰 UI、不碰背包：只发 EventBus.shop_requested，谁接谁负责。

const SHOP_ID := &"supply"

func _ready() -> void:
	super()
	prompt_text = "杂货铺"

func prompt() -> String:
	return "E  杂货铺（饲料 / 药剂 / 木材）"

func interact(_player: Node) -> void:
	EventBus.shop_requested.emit(SHOP_ID)

## 摊子：木箱 + 三个麻袋 + 遮阳棚（纯 _draw，零素材）
func _draw() -> void:
	var wood := Color("#7A5A3A")
	var dark := Color("#4E3722")
	draw_rect(Rect2(-16, -10, 32, 10), dark)          # 台面阴影
	draw_rect(Rect2(-16, -16, 32, 6), wood)           # 台面
	draw_rect(Rect2(-13, -25, 8, 9), Color("#C9A45B"))   # 麻袋（饲料）
	draw_rect(Rect2(-3, -24, 6, 8), Color("#9FB6C9"))    # 药瓶
	draw_rect(Rect2(-3, -26, 6, 2), Color("#5A6B78"))
	draw_rect(Rect2(6, -24, 8, 8), Color("#8A6A45"))     # 木料
	draw_rect(Rect2(-18, -38, 36, 6), Color("#3F6B45"))  # 棚顶
	draw_rect(Rect2(-18, -38, 36, 2), Color("#2C4A31"))
	draw_rect(Rect2(-17, -32, 2, 16), dark)
	draw_rect(Rect2(15, -32, 2, 16), dark)
