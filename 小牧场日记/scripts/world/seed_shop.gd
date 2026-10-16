class_name SeedShop
extends Interactable
## 种子商店（模块 4）—— 只卖**当季** 6 种作物种子 + 两档肥料
##
## 为什么按季节卖：这是最省事也最像样的季节教学。
## 玩家站在店里看不到南瓜种子，就会自己去想「哦，秋天再来」。
##
## ⚠️ 本文件不碰 UI、不碰背包：只发 EventBus.shop_requested，谁接谁负责。
##    所以以后加「工具店 / 家具店」= 抄这个文件改一行 shop_id。

const SHOP_ID := &"seed"

func _ready() -> void:
	super()
	prompt_text = "种子商店"

func prompt() -> String:
	return "E  种子商店（%s季）" % CropDB.SEASON_NAME[GameClock.season]

func interact(_player: Node) -> void:
	EventBus.shop_requested.emit(SHOP_ID)

## 摊子：木台 + 一排种子袋 + 遮阳棚（纯 _draw，零素材）
func _draw() -> void:
	var wood := Color("#8B5E34")
	var dark := Color("#5C3A1E")
	var cloth := Color("#C4553F")
	draw_rect(Rect2(-16, -8, 32, 8), dark)          # 台面阴影
	draw_rect(Rect2(-16, -14, 32, 6), wood)         # 台面
	for i in range(4):
		draw_rect(Rect2(-13 + i * 7, -20, 5, 6), Color("#D9C46A"))   # 种子袋
	draw_rect(Rect2(-18, -34, 36, 6), cloth)        # 棚顶
	draw_rect(Rect2(-18, -34, 36, 2), Color("#8F3A2B"))
	draw_rect(Rect2(-17, -28, 2, 14), dark)         # 棚柱
	draw_rect(Rect2(15, -28, 2, 14), dark)
