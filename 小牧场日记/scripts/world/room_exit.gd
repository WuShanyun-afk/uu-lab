class_name RoomExit
extends Interactable
## 房间里的**出口**（模块 11 需求 3 / 4）—— 按 E 就换场景
##
## 它只做一件事：把 EventBus 换成 SceneRouter.travel()。
## 换场的脏活（抓取那一局、收 UI、change_scene_to_file）全在 SceneRouter 里 ——
## 出口节点不该知道「存档」「carry」这些词。
##
## 为什么用 Interactable 而不是 Area2D + body_entered 自动传送：
##   自动传送会让玩家「路过门口就被弹出去」，而牧场/房间里门和路常常擦着走。
##   E 确认是老派牧场游戏的标准手感，也和商店 / NPC / 建筑同一套交互。

var dest: StringName = &"farm"
var entry: StringName = &""
var label_text: String = "出口"

func setup(to_scene: StringName, to_entry: StringName, label: String,
		pos: Vector2, size: Vector2) -> void:
	dest = to_scene
	entry = to_entry
	label_text = label
	position = pos
	var sh := RectangleShape2D.new()
	sh.size = size
	var cs := get_node_or_null("Shape") as CollisionShape2D
	if cs == null:
		cs = CollisionShape2D.new()
		cs.name = "Shape"
		add_child(cs)
	cs.shape = sh
	queue_redraw()

func prompt() -> String:
	return "%s（E）→ %s" % [label_text, SceneRouter.scene_name(dest)]

func interact(_player: Node) -> void:
	SceneRouter.travel(dest, entry)

func _draw() -> void:
	# 门框：一个深色门洞 + 地上一道亮色提示
	var r := Rect2(-18, -26, 36, 26)
	draw_rect(r, Color(0.12, 0.10, 0.10, 0.85))
	draw_rect(r, Color("#C9A227"), false, 1.0)
	draw_rect(Rect2(-20, 0, 40, 4), Color(0.95, 0.85, 0.45, 0.5))
