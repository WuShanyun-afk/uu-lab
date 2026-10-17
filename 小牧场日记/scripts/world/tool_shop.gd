class_name ToolShop
extends Interactable
## 工具铺（模块 7 需求 2）—— 锄头 / 洒水壶 / 背包的**升级**
##
## 为什么「卖工具」做成卖升级而不是卖新工具：
##   游戏里工具只有一把，Lv1 是白板。GDD §5.4 的工具表本来就是三级制
##   （1 格 → 3 格直线 → 3×3）。做成升级，玩家永远只有一个「锄头」按钮，
##   不用在工具条里塞三把锄头互相切换。
##
## 升级数据全在 data/upgrades.csv，本文件一行数值都不写。
## ⚠️ 本文件不碰 UI、不碰金币：只发 EventBus.shop_requested(&"tool")。

const SHOP_ID := &"tool"

func _ready() -> void:
	super()
	prompt_text = "工具铺"

func prompt() -> String:
	return "E  工具铺（锄头 / 洒水壶 / 背包升级）"

func interact(_player: Node) -> void:
	EventBus.shop_requested.emit(SHOP_ID)

## 铁匠摊：铁砧 + 三把挂着的工具 + 火星（纯 _draw）
func _draw() -> void:
	var wood := Color("#6B4A2E")
	var iron := Color("#7C8794")
	var dark := Color("#3A3F48")
	# 台面
	draw_rect(Rect2(-16, -10, 32, 10), dark)
	draw_rect(Rect2(-16, -14, 32, 5), wood)
	# 铁砧
	draw_rect(Rect2(-7, -20, 14, 6), iron)
	draw_rect(Rect2(-3, -24, 6, 4), iron.lightened(0.15))
	# 挂着的三把工具（锄 / 壶 / 背包）
	draw_rect(Rect2(-14, -34, 2, 14), Color("#8B5A2B"))   # 锄柄
	draw_rect(Rect2(-16, -36, 6, 3), iron)                # 锄头
	draw_rect(Rect2(-1, -30, 7, 8), Color("#5A8FA8"))     # 水壶身
	draw_rect(Rect2(5, -32, 3, 3), Color("#5A8FA8"))      # 壶嘴
	draw_rect(Rect2(8, -34, 8, 10), Color("#A9773F"))     # 背包
	draw_rect(Rect2(8, -34, 8, 2), Color("#7A5A3A"))
	# 棚顶
	draw_rect(Rect2(-19, -46, 38, 5), Color("#5B4636"))
	draw_rect(Rect2(-19, -46, 38, 2), Color("#3E2F24"))
	draw_rect(Rect2(-18, -41, 2, 27), dark)
	draw_rect(Rect2(16, -41, 2, 27), dark)
