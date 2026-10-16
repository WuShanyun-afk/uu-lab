class_name SignPost
extends Interactable
## 告示牌 —— 交互系统的最小示例，也是「加新可交互物」的抄写模板。
##
## 行为：走到跟前 → 底部出「E 看告示牌」→ 按 E → 消息走 EventBus.world_message
## 画法：纯 _draw()，不依赖任何素材（立柱 + 板子）

@export_multiline var message: String = "小牧场日记 · WASD 走 / E 交互 / 1-5 换工具 / F11 全屏"

func _ready() -> void:
	super()
	prompt_text = "看告示牌"

func prompt() -> String:
	return "E  看告示牌"

func interact(_player: Node) -> void:
	EventBus.world_message.emit(message)

func _draw() -> void:
	var post := Color("#6B4423")
	var board := Color("#A9773F")
	var edge := Color("#5C3A1E")
	draw_rect(Rect2(-2, -26, 4, 18), post)
	draw_rect(Rect2(-14, -42, 28, 17), board)
	draw_rect(Rect2(-14, -42, 28, 17), edge, false, 1.0)
	draw_rect(Rect2(-11, -37, 22, 2), edge)   # 两行"字"
	draw_rect(Rect2(-11, -32, 15, 2), edge)
