class_name BreedingShed
extends Interactable
## 繁殖棚（模块 5 需求 4）—— 一栋建筑，两种状态
##
##   没盖 → 按 E = 出钱出木材把它盖起来（造价来自 data/buildings.csv）
##   盖了 → 按 E = 打开「选父母」界面（复用 ShopUI 这个通用壳）
##
## ⚠️ 本文件不碰 UI、不碰背包：只发 EventBus.shop_requested(&"breed")，
##    「到底是要盖房还是要配种」由 main 判断（它才知道 flag 的真值）。

const SHOP_ID := &"breed"
const BUILDING_ID := &"breeding_shed"

func _ready() -> void:
	super()
	prompt_text = "繁殖棚"

func prompt() -> String:
	if not GameState.has_flag(&"shed_built"):
		return "E  建造繁殖棚（%s）" % BuildingDB.cost_text(BUILDING_ID)
	return "E  繁殖棚（选两只父母 · %s）" % Breeding.cost_text()

func interact(_player: Node) -> void:
	EventBus.shop_requested.emit(SHOP_ID)

## 盖好之前：地基 + 脚手架；盖好之后：木棚 + 干草 + 两只剪影
func _draw() -> void:
	var wood := Color("#8B5E34")
	var dark := Color("#5C3A1E")
	var built := GameState.has_flag(&"shed_built")

	draw_rect(Rect2(-24, -4, 48, 6), dark)                 # 地基
	if not built:
		draw_rect(Rect2(-24, -4, 48, 6), Color("#6E6A63"), false, 1.0)
		for x in [-20, -4, 12]:
			draw_rect(Rect2(x, -26, 3, 22), wood)          # 脚手架
		draw_rect(Rect2(-22, -28, 44, 3), wood)
		return

	draw_rect(Rect2(-26, -30, 52, 26), wood)               # 棚体
	draw_rect(Rect2(-30, -36, 60, 7), Color("#C4553F"))    # 屋顶
	draw_rect(Rect2(-30, -36, 60, 2), Color("#8F3A2B"))
	draw_rect(Rect2(-20, -24, 12, 20), Color("#3A2A18"))   # 门洞
	draw_rect(Rect2(4, -22, 16, 8), Color("#D9C46A"))      # 干草堆
	draw_rect(Rect2(4, -14, 16, 6), Color("#C9A45B"))
	draw_rect(Rect2(-12, -24, 4, 6), Color("#F7F3E6"))     # 两只剪影
	draw_rect(Rect2(14, -24, 4, 6), Color("#F7F3E6"))
