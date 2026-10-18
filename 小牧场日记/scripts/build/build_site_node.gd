class_name BuildSiteNode
extends Node2D
## 施工中的脚手架（模块 12 需求 2）—— 纯视图
##
## 和 BuildingNode 分开的原因：施工点不是建筑，它没有等级、没有账本、不提供任何加成。
## 硬用一个「假 PlacedBuilding」去复用 BuildingNode 的话，网格里会多出一栋
## 「其实不存在」的建筑，存档、加成一类的地方迟早踩雷。
##
## 画什么：虚线框（占位有多大）+ 剩余天数 + 一个小锤子符号（NPC 在施工）。

var def_id: StringName = &""
var anchor: Vector2i = Vector2i.ZERO
var days_left: int = 1
var total_days: int = 1

func setup(id: StringName, at: Vector2i, left: int, total: int) -> void:
	def_id = id
	anchor = at
	days_left = left
	total_days = maxi(1, total)
	var d: BuildingDef = BuildingDB.def_of(id)
	var tile := float(WorldConfig.TILE)
	var size := Vector2(d.size) * tile if d != null else Vector2(tile, tile)
	position = Vector2(anchor) * tile + size * 0.5
	queue_redraw()

func refresh(left: int) -> void:
	days_left = left
	queue_redraw()

func _draw() -> void:
	var d: BuildingDef = BuildingDB.def_of(def_id)
	var tile := float(WorldConfig.TILE)
	var size := Vector2(d.size) * tile if d != null else Vector2(tile, tile)
	var r := Rect2(-size * 0.5, size)
	# 虚线框：一格一格画短边，看起来像「还没盖好」
	var col := Color(0.95, 0.80, 0.35, 0.85)
	var step := 8.0
	var x := r.position.x
	while x < r.end.x:
		var w := minf(step * 0.6, r.end.x - x)
		draw_rect(Rect2(x, r.position.y, w, 2), col)
		draw_rect(Rect2(x, r.end.y - 2, w, 2), col)
		x += step
	var y := r.position.y
	while y < r.end.y:
		var h := minf(step * 0.6, r.end.y - y)
		draw_rect(Rect2(r.position.x, y, 2, h), col)
		draw_rect(Rect2(r.end.x - 2, y, 2, h), col)
		y += step
	# 内部淡淡的底色：一眼看出这块地被占了
	draw_rect(r, Color(0.85, 0.72, 0.30, 0.12))
	var font := ThemeDB.fallback_font
	if font != null:
		var label := "施工中 %d/%d 天" % [total_days - days_left, total_days]
		var w2 := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		draw_string(font, Vector2(-w2 * 0.5, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			Color("#FFE9A8"))
		if d != null:
			var n := d.display_name
			var w3 := font.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			draw_string(font, Vector2(-w3 * 0.5, 16), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
				Color("#F4EFE2"))
		# 小锤子
		draw_rect(Rect2(-2, r.position.y - 10, 2, 8), Color("#8B5A2B"))
		draw_rect(Rect2(-5, r.position.y - 12, 8, 3), Color("#9A9A9A"))
