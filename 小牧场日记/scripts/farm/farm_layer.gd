extends Node2D
## 农场渲染层（MVP 占位绘制）
##
## ⚠️ GDD §10.4 说 FarmLayer 是 TileMapLayer。但 TileMapLayer 必须有 TileSet 资源，
##    而地块素材（ssyubix）还没生成。所以这里先用 _draw() 占位：
##    数据层 FarmGrid 完全不感知渲染，等 tileset 到位后只重写这一个文件。

const TILE := 32

var grid: FarmGrid

const C_SOIL_DRY := Color("#6B4A2F")
const C_SOIL_WET := Color("#42301E")
const C_FURROW := Color("#573B26")
const C_FURROW_WET := Color("#33240F")
const C_SPROUT := Color("#79C455")
const C_LEAF := Color("#4C9A38")
const C_FRUIT := Color("#E8503A")
const C_WITHER := Color("#9A8A5E")
const C_DEAD := Color("#6E6349")

func _draw() -> void:
	if grid == null:
		return
	for cell in grid.tiles:
		var t: FarmGrid.Tile = grid.tiles[cell]
		var o := Vector2(cell) * TILE
		if t.tilled:
			_draw_soil(o, t.watered)
		if t.crop_id != StringName(""):
			_draw_crop(o, t, grid.growth_ratio(cell))

func _draw_soil(o: Vector2, wet: bool) -> void:
	draw_rect(Rect2(o, Vector2(TILE, TILE)), C_SOIL_WET if wet else C_SOIL_DRY)
	var furrow := C_FURROW_WET if wet else C_FURROW
	for i in range(4):
		draw_rect(Rect2(o.x + 3, o.y + 5 + i * 7, TILE - 6, 2), furrow)

func _draw_crop(o: Vector2, t: FarmGrid.Tile, ratio: float) -> void:
	var cx := o.x + TILE * 0.5
	var base := o.y + TILE - 4

	if t.dead:
		draw_rect(Rect2(cx - 4, base - 6, 8, 6), C_DEAD)
		return
	if t.dry_days >= FarmGrid.WITHER_DAYS:
		draw_rect(Rect2(cx - 4, base - 8, 8, 8), C_WITHER)
		return

	if ratio < 0.34:
		# 发芽：两个小点
		draw_rect(Rect2(cx - 3, base - 4, 2, 4), C_SPROUT)
		draw_rect(Rect2(cx + 1, base - 4, 2, 4), C_SPROUT)
	elif ratio < 0.67:
		# 生长：一丛叶子
		draw_rect(Rect2(cx - 6, base - 9, 12, 9), C_LEAF)
		draw_rect(Rect2(cx - 2, base - 12, 4, 4), C_SPROUT)
	elif ratio < 1.0:
		# 接近成熟：更大一丛
		draw_rect(Rect2(cx - 8, base - 12, 16, 12), C_LEAF)
		draw_rect(Rect2(cx - 3, base - 16, 6, 5), C_SPROUT)
	else:
		# 成熟：带果实
		draw_rect(Rect2(cx - 8, base - 13, 16, 13), C_LEAF)
		draw_rect(Rect2(cx - 6, base - 18, 5, 5), C_FRUIT)
		draw_rect(Rect2(cx + 2, base - 16, 5, 5), C_FRUIT)
