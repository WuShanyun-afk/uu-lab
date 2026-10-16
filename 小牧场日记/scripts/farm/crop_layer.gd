extends Node2D
## 作物渲染层（程序化占位，模块 3 升级版）
##
## 为什么单独一个节点而不是写在 FarmLayer._draw() 里：
##   FarmLayer 自己画的东西永远排在它所有子节点**之前**，
##   所以只要 SoilLayer 是 FarmLayer 的子节点，土壤就会把作物盖住。
##   拆成「SoilLayer 先画土 → CropLayer 后画作物」，靠树序保证层次，不玩 z_index 玄学。
##
## 模块 3 改了什么：
##   · 果实颜色不再写死红色，改读 CropData.color（CSV 第 9 列）
##   · 施肥地块画肥力标记（基础肥棕点 / 高级肥绿点）
##   · 枯萎 / 枯死有独立形状，玩家一眼能分辨
##
## 作物图集到位后，本文件替换成 TileMapLayer 或 AnimatedSprite2D 池，FarmGrid 一行不动。

const TILE := 32

const C_SPROUT := Color("#79C455")
const C_LEAF := Color("#4C9A38")
const C_LEAF_DARK := Color("#357026")
const C_WITHER := Color("#9A8A5E")
const C_DEAD := Color("#6E6349")

var grid: FarmGrid

func refresh() -> void:
	queue_redraw()

func _draw() -> void:
	if grid == null:
		return
	# 第一遍：肥力标记（会被作物盖住，所以必须先画）
	for cell in grid.tiles:
		var t: FarmGrid.Tile = grid.tiles[cell]
		if t.tilled and t.fertilized > 0:
			_draw_fert_mark(Vector2(cell) * TILE, t.fertilized)
	# 第二遍：作物
	for cell in grid.tiles:
		var t: FarmGrid.Tile = grid.tiles[cell]
		if t.crop_id != StringName(""):
			_draw_crop(Vector2(cell) * TILE, t, grid.growth_ratio(cell))

## 肥力标记：格子底边的一条色带（基础肥棕 / 高级肥绿）
## ⚠️ 不能画在格子中央 —— 作物就长在那儿，标记会被叶子盖住。
##    底边 3px 是安全的：本格的作物最低只到 base（o.y+28），下一格的作物又从 o.y+41 才起步。
func _draw_fert_mark(o: Vector2, level: int) -> void:
	var col: Color = Fertilizer.SOIL_MARK[clampi(level, 0, 2)]
	draw_rect(Rect2(o.x + 2, o.y + TILE - 3, TILE - 4, 3), col)

func _draw_crop(o: Vector2, t: FarmGrid.Tile, ratio: float) -> void:
	var cx := o.x + TILE * 0.5
	var base := o.y + TILE - 4
	var c: CropData = CropDB.get_crop(t.crop_id)
	var fruit: Color = Color(c.color) if c != null else Color("#E8503A")

	if t.dead:
		# 枯死：倒伏的灰褐色残株（一眼看出「这格废了」）
		draw_rect(Rect2(cx - 8, base - 3, 16, 3), C_DEAD)
		draw_rect(Rect2(cx - 6, base - 7, 4, 5), C_DEAD)
		draw_rect(Rect2(cx + 3, base - 6, 4, 4), C_DEAD)
		return
	if t.dry_days >= FarmGrid.WITHER_DAYS:
		# 枯萎：叶子变黄，但还站着（浇一次水能救回来）
		draw_rect(Rect2(cx - 7, base - 9, 14, 9), C_WITHER)
		draw_rect(Rect2(cx - 3, base - 12, 6, 4), C_WITHER.darkened(0.15))
		return

	if ratio < 0.25:
		# 刚发芽：两个小点
		draw_rect(Rect2(cx - 3, base - 4, 2, 4), C_SPROUT)
		draw_rect(Rect2(cx + 1, base - 4, 2, 4), C_SPROUT)
	elif ratio < 0.5:
		# 幼苗：一丛小叶子
		draw_rect(Rect2(cx - 4, base - 7, 8, 7), C_SPROUT)
	elif ratio < 0.75:
		# 生长：叶子变大
		draw_rect(Rect2(cx - 6, base - 10, 12, 10), C_LEAF)
		draw_rect(Rect2(cx - 2, base - 13, 4, 4), C_SPROUT)
	elif ratio < 1.0:
		# 接近成熟：茂盛，但还没结果
		draw_rect(Rect2(cx - 8, base - 13, 16, 13), C_LEAF)
		draw_rect(Rect2(cx - 8, base - 15, 16, 3), C_LEAF_DARK)
	else:
		# 成熟：本作物的果实色 + 顶部高光
		draw_rect(Rect2(cx - 8, base - 13, 16, 13), C_LEAF)
		draw_rect(Rect2(cx - 6, base - 19, 6, 6), fruit)
		draw_rect(Rect2(cx + 1, base - 17, 6, 6), fruit)
		draw_rect(Rect2(cx - 5, base - 18, 4, 2), fruit.lightened(0.35))
