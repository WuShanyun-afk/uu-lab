class_name RoomProp
extends Interactable
## 房间里的**可交互物**（模块 11 需求 3）—— 床 / 存档柜 / 柜台 / 机器 / 告示牌
##
## 节点只发一个信号：EventBus.room_prop_used(prop_id, action)。
## 「按了之后发生什么」属于玩法，由 RoomScene 处理（和商店 / 建筑同一套分层）。
##
## 为什么 action 用 StringName 枚举而不是给每个道具写个子类：
##   目前 5 种道具的动作都只有几行（弹对话 / 开存档柜 / 开商店），
##   5 个子类 × 20 行样板还不如一个 match。等哪天某个道具复杂到值得独立，
##   再拆成子类 —— 那时 RoomScene 的 match 里少一个分支即可。

var prop_id: StringName = &""
var action: StringName = &"info"
var label_text: String = "东西"

func setup(id: StringName, act: StringName, label: String,
		pos: Vector2, size: Vector2) -> void:
	prop_id = id
	action = act
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
	return "%s（E）" % label_text

func interact(_player: Node) -> void:
	EventBus.room_prop_used.emit(prop_id, action)

func _draw() -> void:
	# 每个道具画一个能认出来的色块（零素材，和建筑 / NPC 同一套思路）
	var color := Color("#8A7458")
	match String(action):
		"save":
			color = Color("#C9A227")      # 存档柜：金色
		"shop":
			color = Color("#3F8F6A")      # 柜台：绿色
		"bed":
			color = Color("#7A6EA8")      # 床：紫
		"machine":
			color = Color("#5E5580")      # 机器：暗紫
	var r := Rect2(-16, -14, 32, 18)
	draw_rect(r, color)
	draw_rect(r, color.lightened(0.25), false, 1.0)
	if action == &"machine":
		# 机器上那格「灯」：觉醒后是亮的（这部分是表现，状态在 GameState 里）
		var lit := GameState.story_flag(&"secret_machine_awake")
		draw_rect(Rect2(-3, -11, 6, 4), Color("#F2C14E") if lit else Color("#3A3A44"))
	if action == &"bed":
		draw_rect(Rect2(-16, -14, 32, 5), Color("#E8DCC0"))
	if action == &"shop":
		draw_rect(Rect2(-18, -16, 36, 5), Color("#E8DCC0"))
	draw_rect(Rect2(-20, 4, 40, 3), Color(0, 0, 0, 0.25))
