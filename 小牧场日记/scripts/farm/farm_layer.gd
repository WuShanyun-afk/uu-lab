extends Node2D
## 农场渲染层
##
## 土壤 = 子节点 TileMapLayer（真地块素材，GDD §10.4 的目标形态）
## 作物 = 子节点 CropLayer 程序化占位（作物图集还没出）
##
## ⚠️ 与 GDD §10.4 的偏差：那一节说 FarmLayer 本身就是 TileMapLayer。
##    作物还没有逐阶段图集，硬套 TileMapLayer 得先造 4 阶段 × 18 种作物 = 72 张图。
##    所以这里拆成「TileMapLayer 画土 + CropLayer 画作物」。
##    等作物图集到位，只改这两个子节点，FarmGrid 一行不动。

@onready var _soil: TileMapLayer = $SoilLayer
@onready var _crops: Node2D = $CropLayer

var grid: FarmGrid:
	set(value):
		grid = value
		_crops.grid = value
		if is_node_ready():
			refresh()

func _ready() -> void:
	if _soil.tile_set == null:
		_soil.tile_set = GroundTileset.build()
	_crops.grid = grid
	refresh()

## 数据层变了就叫这个。替代以前的 queue_redraw()
func refresh() -> void:
	_rebuild_soil()
	_crops.refresh()

func _rebuild_soil() -> void:
	if _soil.tile_set == null or grid == null:
		return
	_soil.clear()
	for cell in grid.tiles:
		var t: FarmGrid.Tile = grid.tiles[cell]
		if not t.tilled:
			continue
		GroundTileset.put(_soil, cell, GroundTileset.Kind.SOIL_FURROW_WET if t.watered
			else GroundTileset.Kind.SOIL_FURROW_DRY)
