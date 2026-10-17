class_name OrderPost
extends Interactable
## 订单板（模块 7 需求 3）—— NPC 委托的**投递口**
##
## 命名不叫 OrderBoard 是因为那个名字已经被纯逻辑类占了（scripts/economy/order_board.gd）。
## 本节点只是「一块能按 E 的木板」，订单规则一行都不在这里。
##
## 状态由 main 写入（和模块 6 的 HousingBarn.used_slots 同一套写法）：
## 节点不持有 OrderBoard 引用，main 每次刷新时把「几单 / 几单可交」灌进来。
##
## prompt() 是动态的：玩家不用打开面板就知道有没有能立刻交的委托。

const SHOP_ID := &"order"

## 挂着几单（main 写）
var active_count: int = 0
## 现在就能交的有几单（main 写）
var ready_now: int = 0

func _ready() -> void:
	super()
	prompt_text = "订单板"

func prompt() -> String:
	if active_count <= 0:
		return "E  订单板（暂时没有委托）"
	if ready_now > 0:
		return "E  订单板（%d 单 · %d 单可交）" % [active_count, ready_now]
	return "E  订单板（%d 单在等）" % active_count

func interact(_player: Node) -> void:
	EventBus.shop_requested.emit(SHOP_ID)

## 木板 + 两张钉着的委托单 + 图钉（纯 _draw）
func _draw() -> void:
	var wood := Color("#8A6A45")
	var dark := Color("#5C452C")
	# 两根立柱
	draw_rect(Rect2(-13, -18, 3, 20), dark)
	draw_rect(Rect2(10, -18, 3, 20), dark)
	# 板面
	draw_rect(Rect2(-16, -42, 32, 26), wood)
	draw_rect(Rect2(-16, -42, 32, 26), dark, false, 1.0)
	# 两张委托单
	draw_rect(Rect2(-13, -39, 12, 15), Color("#F2EDE0"))
	draw_rect(Rect2(1, -38, 12, 14), Color("#EDE6D6"))
	draw_rect(Rect2(-11, -36, 8, 1), Color("#9A9384"))
	draw_rect(Rect2(-11, -33, 8, 1), Color("#9A9384"))
	draw_rect(Rect2(3, -35, 8, 1), Color("#9A9384"))
	# 图钉
	draw_rect(Rect2(-8, -40, 2, 2), Color("#D9483B"))
	draw_rect(Rect2(6, -39, 2, 2), Color("#D9483B"))
	# 顶部横梁
	draw_rect(Rect2(-18, -46, 36, 4), Color("#6B4A2E"))
