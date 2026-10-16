class_name GroundLayer
extends TileMapLayer
## 地面层：草地 + 牧场地面，真素材（ground_tileset.png），不再是棋盘格占位。
##
## 尺寸和牧场范围全部来自 WorldConfig —— 本文件不再自己写坐标。
## 节点在 main.tscn 里 z_index = -1，压在 Main._draw()（牧场木栅栏）下面。

const SEED := 20261016
const SEASON_SHADER := "res://assets/shaders/season_tint.gdshader"

var _season_mat: ShaderMaterial

func _ready() -> void:
	if tile_set == null:
		tile_set = GroundTileset.build()
	rebuild()

## 确定性铺地：同一个种子永远铺出同一张地图（测试可复现）
func rebuild() -> void:
	if tile_set == null:
		return
	clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var pen := _pen_cells()
	for y in range(WorldConfig.MAP_TILES.y):
		for x in range(WorldConfig.MAP_TILES.x):
			var cell := Vector2i(x, y)
			GroundTileset.put(self, cell, _pick(rng, pen.has(cell)))
	_rebuild_garden(rng)

## 秘密花园的地面（模块 5）：花多、草密，十字石板路靠 GardenDecor 画。
## 用的是同一张图集、同一个 rng 序列（接着主地图往下抽），所以整张世界图仍然可复现。
func _rebuild_garden(rng: RandomNumberGenerator) -> void:
	var origin := WorldConfig.garden_cell_origin()
	for y in range(WorldConfig.GARDEN_TILES.y):
		for x in range(WorldConfig.GARDEN_TILES.x):
			GroundTileset.put(self, origin + Vector2i(x, y), _pick_garden(rng))

## 花园地面：花 26% / 草丛 20% / 石头 6% / 其余纯草
func _pick_garden(rng: RandomNumberGenerator) -> int:
	var r := rng.randf()
	if r < 0.26:
		return GroundTileset.Kind.GRASS_FLOWER
	if r < 0.46:
		return GroundTileset.Kind.GRASS_TUFT
	if r < 0.52:
		return GroundTileset.Kind.GRASS_STONE
	return GroundTileset.Kind.GRASS

## 季节外观：用 canvas_item 着色器把地表朝当季目标色 mix（GDD §2.1 草地色）。
##
## ⚠️ 不用 modulate：modulate 只能乘，冬天的草地乘多亮都还是绿，永远变不成雪白。
## 以后每季重画一套图集时，把这里换成切图集即可，玩法代码一行不用动。
func set_season_tint(season: int) -> void:
	if _season_mat == null:
		_season_mat = ShaderMaterial.new()
		_season_mat.shader = load(SEASON_SHADER)
		material = _season_mat
	_season_mat.set_shader_parameter("tint", SeasonEffects.grass_color(season))
	_season_mat.set_shader_parameter("amount", SeasonEffects.grass_tint_amount(season))

func _pen_cells() -> Dictionary:
	var out := {}
	var t := GroundTileset.TILE_SIZE
	var x0 := int(WorldConfig.PEN.position.x) / t
	var y0 := int(WorldConfig.PEN.position.y) / t
	var x1 := int(WorldConfig.PEN.end.x) / t
	var y1 := int(WorldConfig.PEN.end.y) / t
	for y in range(y0, y1):
		for x in range(x0, x1):
			out[Vector2i(x, y)] = true
	return out

## 围栏里草更密更齐，外面留一点花和石头当视觉噪音
##
## ⚠️ 不用 Kind.GRASS_DARK：图集里那块是**纯色深绿方块**，
##    单块撒在草地里会读成「地洞」而不是「深一点的草」。
##    等重画成带纹理的版本再启用（见 _uu/地块笔记.md）。
func _pick(rng: RandomNumberGenerator, in_pen: bool) -> int:
	var r := rng.randf()
	if in_pen:
		return GroundTileset.Kind.GRASS_TUFT if r < 0.14 else GroundTileset.Kind.GRASS
	if r < 0.14:
		return GroundTileset.Kind.GRASS_TUFT
	if r < 0.20:
		return GroundTileset.Kind.GRASS_FLOWER
	if r < 0.23:
		return GroundTileset.Kind.GRASS_STONE
	return GroundTileset.Kind.GRASS
