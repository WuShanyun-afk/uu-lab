class_name GroundTileset
extends RefCounted
## 地块图集 —— ssyubix 确定性绘制产物（**不是** AI 生图，AI 出过 31×33 裂缝）
##
## 素材：assets/tiles/ground_tileset.png   128×64 = 4 列 × 2 行，每块 32×32
##   行 0： 0 纯草      1 草丛       2 草花       3 草石
##   行 1： 4 干土      5 干土犁沟   6 湿土犁沟   7 深草
##   配套 meta：assets/tiles/ground_tileset.json
##
## 设计取舍：TileSet 在运行时用代码构建，不手写 .tres。
##   换素材 = 换 PNG + 改本文件常量，不用开编辑器。

const TILE_SIZE := 32
const COLUMNS := 4
const ROWS := 2
const TEXTURE_PATH := "res://assets/tiles/ground_tileset.png"
const SOURCE_ID := 0

enum Kind {
	GRASS = 0,          ## 纯草地
	GRASS_TUFT = 1,     ## 草丛
	GRASS_FLOWER = 2,   ## 草花
	GRASS_STONE = 3,    ## 草石
	SOIL_DRY = 4,       ## 干土（未犁）
	SOIL_FURROW_DRY = 5,## 干土犁沟 —— 已锄未浇
	SOIL_FURROW_WET = 6,## 湿土犁沟 —— 已浇
	GRASS_DARK = 7,     ## 深草（明暗对比用）
}

## 图集格号（行主序）→ 图集坐标
static func atlas_coords(kind: int) -> Vector2i:
	return Vector2i(kind % COLUMNS, kind / COLUMNS)

## 图集格数（供测试断言）
static func tile_count() -> int:
	return COLUMNS * ROWS

## 构建 TileSet。素材缺失时返回 null 并报错，不静默降级
static func build() -> TileSet:
	var tex: Texture2D = load(TEXTURE_PATH)
	if tex == null:
		push_error("地块图集缺失：" + TEXTURE_PATH)
		return null
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	for y in range(ROWS):
		for x in range(COLUMNS):
			src.create_tile(Vector2i(x, y))
	ts.add_source(src, SOURCE_ID)
	return ts

## 往 TileMapLayer 放一块
static func put(layer: TileMapLayer, cell: Vector2i, kind: int) -> void:
	layer.set_cell(cell, SOURCE_ID, atlas_coords(kind))
