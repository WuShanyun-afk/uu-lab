class_name CraftWorkshop
extends Interactable
## 加工坊（模块 7 需求 4）—— 牛奶→奶酪 / 羊毛→毛线 / 鸡蛋→蛋黄酱
##
## 本节点只做两件事：显示状态 + 发事件。加工规则全在 Processor（纯逻辑）。
##
## 两种交互语义（main 按状态决定）：
##   · 有成品 → 按 E 直接取货（不弹面板，收东西不该多点两次）
##   · 没成品 → 按 E 弹「放料」面板（列出能做且原料够的配方）
##
## 状态由 main 写入（同 HousingBarn.used_slots 的写法）：节点不持有 Processor。

const SHOP_ID := &"craft"

## 加工坊等级（决定槽位 2/4/6）
var level: int = 1
## 已用槽 / 总槽（main 写）
var used: int = 0
var total: int = 2
## 有几件做好的（main 写）
var ready_count: int = 0
## 一句话状态（main 用 Processor.status_text() 灌进来）
var status: String = "空闲"

func _ready() -> void:
	super()
	prompt_text = "加工坊"

func prompt() -> String:
	if ready_count > 0:
		return "E  加工坊（%d 件好了，取货）" % ready_count
	return "E  加工坊 Lv%d（%s · %d/%d 槽）" % [level, status, used, total]

func interact(_player: Node) -> void:
	EventBus.shop_requested.emit(SHOP_ID)

## 小木屋 + 烟囱 + 三个罐子（纯 _draw）
func _draw() -> void:
	var wall := Color("#C9B18A")
	var roof := Color("#8B4A3A")
	var dark := Color("#4E3722")
	# 屋身
	draw_rect(Rect2(-18, -26, 36, 26), wall)
	draw_rect(Rect2(-18, -26, 36, 26), dark, false, 1.0)
	# 屋顶（三角）
	var pts := PackedVector2Array([
		Vector2(-21, -26), Vector2(0, -40), Vector2(21, -26),
	])
	draw_colored_polygon(pts, roof)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2]]), dark, 1.0)
	# 烟囱
	draw_rect(Rect2(8, -44, 6, 10), Color("#8A6A5A"))
	draw_rect(Rect2(8, -44, 6, 2), dark)
	# 门
	draw_rect(Rect2(-6, -16, 12, 16), dark)
	draw_rect(Rect2(-5, -15, 10, 15), Color("#6B4A2E"))
	# 窗（晚上亮一点，纯色块）
	draw_rect(Rect2(-15, -22, 6, 6), Color("#F2D98A"))
	draw_rect(Rect2(9, -22, 6, 6), Color("#F2D98A"))
	# 门口三个罐子（奶罐 / 毛线球 / 蛋筐）—— 都压在屋身内，别飘到草地上
	draw_rect(Rect2(12, -9, 5, 9), Color("#B9C4CC"))
	draw_rect(Rect2(12, -11, 5, 2), Color("#8C9AA5"))
	draw_circle(Vector2(-13, -5), 3.5, Color("#C98A6B"))
	draw_rect(Rect2(-17, -8, 7, 8), Color("#A9773F"))
	draw_rect(Rect2(-17, -8, 7, 1), Color("#7A5A3A"))
