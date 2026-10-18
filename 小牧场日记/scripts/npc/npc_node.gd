class_name NpcNode
extends Interactable
## 一位村民的**画布与碰撞**（模块 10 需求 1 / 2）
##
## 和 BuildingNode 一样是「数据在别处、节点只是视图」：
##   NpcState 才是好感真源，NpcSchedule 才是位置真源，
##   这个节点每帧被 main 喂一次 (目标位置, 在场吗, 在干什么)。
##
## 为什么不是每帧瞬间挪过去：
##   玩家看得见「玛莎从店里走到门口」才叫日程表；瞬移只会像 bug。
##   所以它自己用 move_toward 走，主循环只管给目标点。
##
## 素材：和建筑同一套 —— 全部 _draw() 画确定性色块（零素材）。
## 换真图时只覆盖 _draw()，逻辑一行不动。
##
## 交互：extends Interactable → 玩家的 InteractProbe 自动扫到，
##       E 发 EventBus.npc_interacted，G 由 main 处理（送礼面板）。

const SPEED := 34.0
const SKIN := Color("#F0C8A0")
const HAIR := Color("#4A3A2E")

var npc_id: StringName = &""
## 好感状态（只读引用，main 负责改）
var state: NpcState = null
## 日程里正在干什么（"看店" / "打铁" / "不在"）
var action: String = ""
## 不在场时的落脚点（家）
var home: Vector2 = Vector2.ZERO

var _target: Vector2 = Vector2.ZERO
var _shape: CollisionShape2D = null

func setup(id: StringName, st: NpcState) -> void:
	npc_id = id
	state = st
	var d := NpcDB.def_of(id)
	home = position
	if d == null:
		return
	# 交互范围：一个 26×26 的小方块（和商店同一量级）
	var sh := RectangleShape2D.new()
	sh.size = Vector2(30, 30)
	_shape = get_node_or_null("ProbeShape") as CollisionShape2D
	if _shape == null:
		_shape = CollisionShape2D.new()
		_shape.name = "ProbeShape"
		_shape.position = Vector2(0, -6)
		add_child(_shape)
	_shape.shape = sh
	queue_redraw()

## main 每帧调：给目标点 + 在场状态 + 正在干什么。
## 不在场 = 藏起来（不是删节点 —— 删了会把好感度一起丢掉）
func update_schedule(target: Vector2, visible_now: bool, act: String) -> void:
	action = act
	visible = visible_now
	enabled = visible_now          # 不在场就不可交互（探针会跳过）
	if not visible_now:
		return
	_target = target
	position = position.move_toward(_target, SPEED * get_process_delta_time())
	if position.distance_to(_target) < 0.5:
		position = _target
	queue_redraw()

## 直接落位（开局 / 读档用，别让村民从 (0,0) 走过来）
func snap_to(pos: Vector2) -> void:
	position = pos
	_target = pos
	home = pos

func _process(_delta: float) -> void:
	if not visible:
		return
	if position.distance_to(_target) > 0.5:
		queue_redraw()       # 名字牌 / 心数跟着走

func prompt() -> String:
	if npc_id == &"":
		return ""
	var d := NpcDB.def_of(npc_id)
	var h := 0 if state == null else state.hearts()
	var talk_hint := "E 说话" if (state != null and state.can_talk(GameClock.day)) else "E 说话（今天聊过了）"
	return "%s ｜ %s ｜ ♥%d/10 ｜ %s · G 送礼" % [
		d.display_name if d != null else str(npc_id),
		d.title if d != null else "", h, talk_hint]

func interact(_player: Node) -> void:
	if npc_id == &"":
		return
	EventBus.npc_interacted.emit(npc_id)

## 好感变了 / 状态变了 → 重画（心数显示在名字牌上）
func refresh_visual() -> void:
	queue_redraw()

# ---------------- 绘制 ----------------

func _draw() -> void:
	var d := NpcDB.def_of(npc_id)
	if d == null:
		return
	var body: Color = d.color
	# 影子
	draw_circle(Vector2(0, 2), 7.0, Color(0, 0, 0, 0.22))
	# 身体：一个梯形色块（比矩形更像人）
	var pts := PackedVector2Array([
		Vector2(-6, 0), Vector2(6, 0), Vector2(5, -12), Vector2(-5, -12)])
	draw_colored_polygon(pts, body)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-5, -12), Vector2(5, -12), Vector2(3.5, -15), Vector2(-3.5, -15)]),
		body.darkened(0.18))
	# 头
	draw_circle(Vector2(0, -19), 5.0, SKIN)
	# 头发（不同村民靠色相区分：直接用立绘色变暗）
	draw_circle(Vector2(0, -21), 5.0, body.darkened(0.25))
	draw_rect(Rect2(-5, -21, 10, 4), SKIN)
	# 名字 + 心数
	var font := ThemeDB.fallback_font
	if font != null:
		var h := 0 if state == null else state.hearts()
		var label := "%s ♥%d" % [d.display_name, h]
		var fs := 9
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(-w * 0.5, -28), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color("#FFF3D6"))
		# 正在干什么（小字，压在心数下面一行）
		if action != "":
			var fs2 := 8
			var a := "（%s）" % action
			var w2 := font.get_string_size(a, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
			draw_string(font, Vector2(-w2 * 0.5, -37), a, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2,
				Color("#D8D2C0"))
