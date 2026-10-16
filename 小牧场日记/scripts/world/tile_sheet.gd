class_name TileSheet
extends RefCounted
## 图集 → TileSet 的代码构建工具（里程碑 4）
##
## 为什么用代码建 TileSet 而不是手搓 .tres：
##   1. 手写 .tres 的 sub_resource 极易错位，且无法被 headless 测试覆盖；
##   2. 图集索引（常量）和 TileSet 的 atlas 坐标必须一一对应，代码里只有一处真值；
##   3. 换素材只要改一个路径常量，不用重开编辑器点一遍。

## 从一张等分图集建一个单源 TileSet
static func build(sheet_path: String, cols: int, rows: int, tile_px: int) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_px, tile_px)
	var src := TileSetAtlasSource.new()
	src.texture = load(sheet_path)
	src.texture_region_size = Vector2i(tile_px, tile_px)
	for y in rows:
		for x in cols:
			src.create_tile(Vector2i(x, y))
	ts.add_source(src, 0)
	return ts

## 线性索引 → 图集坐标（行优先）
static func at(index: int, cols: int) -> Vector2i:
	return Vector2i(index % cols, index / cols)
