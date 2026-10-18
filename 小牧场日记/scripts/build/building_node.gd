class_name BuildingNode
extends Interactable
## 一栋落地建筑的**画面与碰撞**（模块 9）
##
## 和模块 6 的 HousingBarn 一样是「数据在别处、节点只负责画」：
##   PlacedBuilding 才是真源，这个节点只是它的一个视图。
## 拆掉建筑 = 把节点 queue_free + 从 BuildingGrid 删掉，两边不做任何状态同步。
##
## 为什么 extends Interactable 而不是自己写 Area2D：
##   玩家的 InteractProbe 只认 layer 2 的 Interactable —— 继承它就不用改 player.gd，
##   而且「建筑能被 E 看/升级」和商店是同一套交互语义。
##
## 碰撞：StaticBody2D 子节点把整块 footprint 挡住，玩家走不进建筑里。
##   ⚠️ 碰撞体比画面**矮一点**（只到画面下沿），否则玩家从上方走来会被
##      「看不见的墙」卡住 —— 这是 2D 俯视角建筑的经典坑。
##
## 素材：全部 _draw() 画的确定性色块（和模块 1 的围栏同一套思路），
## 换成真图时只要覆盖 _draw() 一个函数，别的逻辑一行不动。

## 分类配色（屋顶 / 墙体 / 边框）
const PALETTE := {
	&"fence": [Color("#8B5A2B"), Color("#A9743F")],
	&"housing": [Color("#B4463C"), Color("#8C3A32")],
	&"workshop": [Color("#4E6E8E"), Color("#3C566E")],
	&"market": [Color("#3F8F6A"), Color("#2F6B4F")],
	&"town": [Color("#C9A227"), Color("#9E7E1C")],
	&"special": [Color("#7A5AA0"), Color("#5E4580")],
}
const WALL := Color("#E8DCC0")
const WALL_DARK := Color("#CFC0A0")
const ROOF_H := 16.0

## 它代表的那栋建筑（由 main 在 spawn 时塞进来）
var building: PlacedBuilding = null
## 升级可用时屋顶上加一个小箭头，告诉玩家「这个还能升」
var can_upgrade_now := false

var _body: StaticBody2D = null
var _shape: CollisionShape2D = null

func setup(b: PlacedBuilding) -> void:
	building = b
	var d := b.def()
	if d == null:
		return
	var tile := float(WorldConfig.TILE)
	position = Vector2(b.anchor) * tile + Vector2(d.size) * tile * 0.5
	var half := Vector2(d.size) * tile * 0.5
	# 触发范围 = 整块地（比碰撞稍大，站在边上也能 E 到）
	var area_shape := RectangleShape2D.new()
	area_shape.size = Vector2(d.size) * tile + Vector2(6, 6)
	var cs := get_node_or_null("AreaShape") as CollisionShape2D
	if cs == null:
		cs = CollisionShape2D.new()
		cs.name = "AreaShape"
		add_child(cs)
	cs.shape = area_shape
	# 实体碰撞：宽度占满，高度只到「脚下」，别挡住上方的视线通道
	_body = get_node_or_null("Body") as StaticBody2D
	if _body == null:
		_body = StaticBody2D.new()
		_body.name = "Body"
		add_child(_body)
	var body_shape := RectangleShape2D.new()
	body_shape.size = Vector2(half.x * 2.0, tile * 0.6)
	_shape = _body.get_node_or_null("Shape") as CollisionShape2D
	if _shape == null:
		_shape = CollisionShape2D.new()
		_shape.name = "Shape"
		_body.add_child(_shape)
	_shape.shape = body_shape
	_shape.position = Vector2(0, half.y - tile * 0.3)
	prompt_text = _prompt_text()
	queue_redraw()

func _prompt_text() -> String:
	if building == null:
		return "建筑"
	var d := building.def()
	var base := "%s · %s" % [building.display_name(), d.stat_text(building.level) if d != null else ""]
	if building.can_upgrade():
		var cost := d.upgrade_gold(building.level)
		return "%s ｜ E 升级（%dG + 木材×%d）" % [base, cost, d.upgrade_wood(building.level)]
	return "%s ｜ 已满级" % base

func prompt() -> String:
	return _prompt_text()

## 按 E：交给 main（升级 / 提示）。这里不扣钱 —— 规则和表现分开。
func interact(_player: Node) -> void:
	if building == null:
		return
	EventBus.building_interacted.emit(building.anchor)

## 升级完成后刷新提示条与「能升级」标记
func refresh_state(can_up: bool) -> void:
	can_upgrade_now = can_up
	queue_redraw()

# ---------------- 绘制 ----------------

func _draw() -> void:
	if building == null:
		return
	var d := building.def()
	if d == null:
		return
	var tile := float(WorldConfig.TILE)
	var size := Vector2(d.size) * tile
	var half := size * 0.5
	var top_left := -half
	if d.category == BuildingDef.CAT_FENCE:
		_draw_fence(top_left, size)
		return
	var cols: Array = PALETTE.get(d.category, [Color("#B4463C"), Color("#8C3A32")])
	var roof: Color = cols[0]
	var wall: Color = WALL
	# 墙：下半截
	var wall_rect := Rect2(top_left + Vector2(2, size.y * 0.42), Vector2(size.x - 4, size.y * 0.56))
	draw_rect(wall_rect, wall)
	draw_rect(wall_rect, WALL_DARK, false, 1.0)
	# 屋顶：梯形（上窄下宽），一眼能看出「这是栋房子」
	var roof_pts := PackedVector2Array([
		Vector2(top_left.x - 2.0, top_left.y + size.y * 0.46),
		Vector2(top_left.x + size.x * 0.16, top_left.y - ROOF_H * 0.2),
		Vector2(top_left.x + size.x * 0.84, top_left.y - ROOF_H * 0.2),
		Vector2(top_left.x + size.x + 2.0, top_left.y + size.y * 0.46),
	])
	draw_colored_polygon(roof_pts, roof)
	draw_polyline(roof_pts + PackedVector2Array([roof_pts[0]]), roof.darkened(0.35), 1.0)
	# 门
	var door_w := minf(10.0, size.x * 0.3)
	draw_rect(Rect2(Vector2(-door_w * 0.5, size.y * 0.62), Vector2(door_w, size.y * 0.36)),
		Color("#6B4A2F"))
	# 名牌：建筑名 + 等级（小字号，压在地面上不挡视线）
	var font := ThemeDB.fallback_font
	if font != null:
		var label := "%s Lv%d" % [building.display_name(), building.level]
		var fs := 9
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(-w * 0.5, top_left.y - 4.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#F4EFE2"))
	if can_upgrade_now:
		# 屋顶上的小三角箭头：还能升级
		var ay := top_left.y - ROOF_H * 0.2 - 12.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(-5, ay + 6), Vector2(5, ay + 6), Vector2(0, ay)]), Color("#FFDD55"))

func _draw_fence(top_left: Vector2, size: Vector2) -> void:
	# 1 格栅栏：两根立柱 + 一道横杆，透明感强一点，别把地面全挡住
	var post := Color("#8B5A2B")
	var bar := Color("#A9743F")
	var w := size.x
	draw_rect(Rect2(top_left + Vector2(2, size.y * 0.2), Vector2(4, size.y * 0.76)), post)
	draw_rect(Rect2(top_left + Vector2(w - 6, size.y * 0.2), Vector2(4, size.y * 0.76)), post)
	draw_rect(Rect2(top_left + Vector2(2, size.y * 0.42), Vector2(w - 4, 3)), bar)
	draw_rect(Rect2(top_left + Vector2(2, size.y * 0.66), Vector2(w - 4, 3)), bar)
