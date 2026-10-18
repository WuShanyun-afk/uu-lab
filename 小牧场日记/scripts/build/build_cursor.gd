class_name BuildCursor
extends Node2D
## 建造模式的**幽灵预览**（模块 9 需求 4：布局自由摆放）
##
## 玩家面前那一格 = 预览位置。绿色 = 能放（按 E 落地），红色 = 不能放（提示条说原因）。
## 预览只画不写：真正的落地在 main._try_place() → BuildingGrid.place()。
##
## 为什么预测用「格子矩形」而不是建筑贴图：
##   真实建筑是画在 BuildingNode 里的（要碰撞、要 y-sort），预览只需要面积信息。
##   用面积矩形反而更准 —— 玩家能一眼看出 3×2 到底占几格、会不会压到围栏。
##
## 分层：本节点不知道钱、不知道阶段、不知道库存，只被 main 喂三个数：
##   cell / def_id / reason(枚举)。好画、好测、好换皮。

const OK_COLOR := Color(0.35, 0.95, 0.45, 0.45)
const BAD_COLOR := Color(0.95, 0.32, 0.28, 0.45)
const EDGE_OK := Color(0.45, 1.0, 0.55, 0.9)
const EDGE_BAD := Color(1.0, 0.42, 0.35, 0.9)

## 目标格（锚点，左上角）
var cell: Vector2i = Vector2i.ZERO
## 要把哪种建筑放在这里（&"" = 没在建造模式）
var def_id: StringName = &""
## can_place 返回的枚举，决定绿 / 红
var reason: StringName = BuildingGrid.OK
var active := false

func show_at(c: Vector2i, id: StringName, r: StringName) -> void:
	cell = c
	def_id = id
	reason = r
	active = id != &""
	visible = active
	queue_redraw()

func hide_cursor() -> void:
	active = false
	visible = false
	queue_redraw()

func _draw() -> void:
	if not active:
		return
	var d: BuildingDef = BuildingDB.def_of(def_id)
	if d == null:
		return
	var tile := float(WorldConfig.TILE)
	var ok := reason == BuildingGrid.OK
	var fill := OK_COLOR if ok else BAD_COLOR
	var edge := EDGE_OK if ok else EDGE_BAD
	var top_left := Vector2(cell) * tile
	# 每格单独画：跨格建筑哪里压住了，一眼看得出来
	for off in d.footprint():
		var r := Rect2(top_left + Vector2(off) * tile, Vector2(tile, tile))
		draw_rect(r, fill)
		draw_rect(r, edge, false, 1.0)
	# 外框加粗一点，边界更清楚
	draw_rect(Rect2(top_left, Vector2(d.size) * tile), edge, false, 2.0)
