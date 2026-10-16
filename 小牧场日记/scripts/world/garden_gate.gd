class_name GardenGate
extends Interactable
## 藤蔓门（模块 5 需求 5）—— 主地图东侧的传送门，解锁前是一堵长满藤的墙
##
## 解锁条件：**每个物种至少有一只动物觉醒**（9/9）。见 Herd.all_species_awakened()。
## 为什么按物种而不是按个体：牧场里有 20 个位置，把每一只都喂到 10 心
## 是纯粹的重复劳动，不是玩法。
##
## ⚠️ 只发 EventBus.portal_used，传送本身（改坐标 + 换相机 limit）在 main。
## ⚠️ 可交互物**不持有 Herd 引用**（零耦合），所以「觉醒了几种」这个数字
##    由 main 每帧写进来（set_awakened_count）。

## main 写进来的觉醒物种数（只用于提示文案）
var awakened_count: int = 0

func _ready() -> void:
	super()
	prompt_text = "藤蔓门"

func prompt() -> String:
	if not GameState.garden_unlocked:
		return "藤蔓门（沉睡）· 觉醒 %d/%d 种" % [awakened_count, AnimalDB.all_ids().size()]
	return "E  进入秘密花园"

func interact(_player: Node) -> void:
	if not GameState.garden_unlocked:
		EventBus.world_message.emit("藤蔓纹丝不动 —— 让每一种动物都醒过来，它才会开。")
		return
	EventBus.portal_used.emit(&"garden")

func set_awakened_count(n: int) -> void:
	if n == awakened_count:
		return
	awakened_count = n
	queue_redraw()

## 拱门 + 藤蔓。解锁后藤蔓开花（粉点），门洞发亮。
func _draw() -> void:
	var vine := Color("#3F6B45")
	var dark := Color("#2C4A31")
	var stone := Color("#7E7A72")
	var open := GameState.garden_unlocked

	draw_rect(Rect2(-20, -44, 6, 44), stone)          # 左柱
	draw_rect(Rect2(14, -44, 6, 44), stone)           # 右柱
	draw_rect(Rect2(-20, -50, 40, 7), stone)          # 拱顶
	if open:
		draw_rect(Rect2(-14, -44, 28, 44), Color(0.55, 0.85, 0.6, 0.28))   # 门内的光
	draw_rect(Rect2(-22, -52, 6, 52), vine)           # 藤
	draw_rect(Rect2(16, -52, 6, 52), vine)
	draw_rect(Rect2(-22, -40, 44, 3), dark)
	draw_rect(Rect2(-22, -18, 44, 3), dark)
	if open:
		for p in [Vector2(-19, -46), Vector2(19, -30), Vector2(-19, -24), Vector2(19, -44)]:
			draw_rect(Rect2(p.x, p.y, 3, 3), Color("#E88BA8"))   # 花开
