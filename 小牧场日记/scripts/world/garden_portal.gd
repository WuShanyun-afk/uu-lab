class_name GardenPortal
extends Interactable
## 花园里的回程传送门（模块 5 需求 5）
##
## 和藤蔓门对称：一个负责进、一个负责出。
## 花园四周是实心围墙，所以这个门是**唯一**的出口 —— 别删它。

func _ready() -> void:
	super()
	prompt_text = "回牧场"

func prompt() -> String:
	return "E  回到牧场"

func interact(_player: Node) -> void:
	EventBus.portal_used.emit(&"farm")

## 一圈石台 + 中间旋转的光柱（纯 _draw，零素材）
func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	draw_rect(Rect2(-18, -6, 36, 8), Color("#7E7A72"))
	draw_rect(Rect2(-14, -10, 28, 5), Color("#9A968C"))
	var pulse := 0.55 + 0.45 * sin(t * 2.2)
	draw_rect(Rect2(-10, -34, 20, 26), Color(0.75, 0.9, 1.0, 0.20 + 0.12 * pulse))
	draw_rect(Rect2(-5, -32, 10, 24), Color(0.85, 0.95, 1.0, 0.30 + 0.20 * pulse))
	draw_rect(Rect2(-2, -30, 4, 22), Color(1, 1, 1, 0.45))
