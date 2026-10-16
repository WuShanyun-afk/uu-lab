extends Node
## 里程碑 4 验收：真地块素材 + 洒水壶动画
## 运行： godot --headless --path <项目> res://tests/test_tileset.tscn
##
## 断言的是「素材真的接上了」，不是「看起来像草地」。

var _fails: Array[String] = []

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails.append(label)
	print(("  [OK] " if cond else "  [FAIL] ") + label)

func _ready() -> void:
	print("=== 地块素材 + 洒水壶验收（里程碑 4）===")

	# --- 1. 图集构建 ---
	var ts: TileSet = GroundTileset.build()
	_check(ts != null, "GroundTileset.build() 成功")
	if ts:
		_check(ts.tile_size == Vector2i(32, 32), "TileSet 格尺寸 32×32（实际 %s）" % ts.tile_size)
		_check(ts.get_source_count() == 1, "只有 1 个图集源（实际 %d）" % ts.get_source_count())
		var src := ts.get_source(GroundTileset.SOURCE_ID) as TileSetAtlasSource
		_check(src != null, "源 0 是 TileSetAtlasSource")
		if src:
			_check(src.texture != null, "源有贴图")
			if src.texture:
				_check(src.texture.get_width() == 128 and src.texture.get_height() == 64,
					"图集 128×64（实际 %d×%d）" % [src.texture.get_width(), src.texture.get_height()])
			_check(src.get_tiles_count() == 8, "图集 8 块（实际 %d）" % src.get_tiles_count())

	# --- 2. 格号 ↔ 图集坐标 ---
	_check(GroundTileset.atlas_coords(GroundTileset.Kind.GRASS) == Vector2i(0, 0), "GRASS -> (0,0)")
	_check(GroundTileset.atlas_coords(GroundTileset.Kind.GRASS_STONE) == Vector2i(3, 0), "GRASS_STONE -> (3,0)")
	_check(GroundTileset.atlas_coords(GroundTileset.Kind.SOIL_FURROW_DRY) == Vector2i(1, 1), "SOIL_FURROW_DRY -> (1,1)")
	_check(GroundTileset.atlas_coords(GroundTileset.Kind.SOIL_FURROW_WET) == Vector2i(2, 1), "SOIL_FURROW_WET -> (2,1)")
	_check(GroundTileset.tile_count() == 8, "tile_count() = 8")

	# --- 3. 主场景真的把素材挂上了 ---
	var ps: PackedScene = load("res://scenes/main.tscn")
	_check(ps != null, "main.tscn 可加载")
	if ps == null:
		return _finish()
	var main := ps.instantiate()
	add_child(main)
	await get_tree().process_frame

	var ground := main.get_node_or_null("World/GroundLayer") as TileMapLayer
	_check(ground != null, "World/GroundLayer 是 TileMapLayer")
	if ground:
		_check(ground.tile_set != null, "GroundLayer 挂了 TileSet")
		var used := ground.get_used_cells()
		# 模块 5 起，地面层同时铺主地图（24×14）和秘密花园（20×12），所以总数是两块之和
		var main_cells := WorldConfig.MAP_TILES.x * WorldConfig.MAP_TILES.y
		var garden_cells := WorldConfig.GARDEN_TILES.x * WorldConfig.GARDEN_TILES.y
		_check(used.size() == main_cells + garden_cells,
			"铺满主地图 %d + 花园 %d = %d 格（实际 %d）" % [
				main_cells, garden_cells, main_cells + garden_cells, used.size()])
		# 花园那块的左上角格子必须在
		_check(ground.get_cell_source_id(WorldConfig.garden_cell_origin()) >= 0,
			"花园左上角有地块（%s）" % str(WorldConfig.garden_cell_origin()))
		# 每格都必须落在图集里，不能有空
		var empty := 0
		for c in used:
			if ground.get_cell_source_id(c) < 0:
				empty += 1
		_check(empty == 0, "没有空格（实际 %d）" % empty)

	var farm := main.get_node_or_null("World/FarmLayer")
	_check(farm != null, "有 World/FarmLayer")
	var soil := main.get_node_or_null("World/FarmLayer/SoilLayer") as TileMapLayer
	_check(soil != null, "FarmLayer/SoilLayer 是 TileMapLayer")
	if soil:
		_check(soil.tile_set != null, "SoilLayer 挂了 TileSet")

	# --- 4. 土壤跟着数据层变 ---
	if farm and soil:
		var grid: FarmGrid = farm.grid
		_check(grid != null, "FarmLayer 拿到了 FarmGrid")
		if grid:
			var cell := Vector2i(3, 3)
			_check(soil.get_used_cells().is_empty(), "开局没有耕地")
			grid.till(cell)
			farm.refresh()
			_check(soil.get_cell_atlas_coords(cell) == GroundTileset.atlas_coords(GroundTileset.Kind.SOIL_FURROW_DRY),
				"锄地后该格 = 干土犁沟")
			grid.water(cell)
			farm.refresh()
			_check(soil.get_cell_atlas_coords(cell) == GroundTileset.atlas_coords(GroundTileset.Kind.SOIL_FURROW_WET),
				"浇水后该格 = 湿土犁沟")
			_check(soil.get_used_cells().size() == 1, "只有 1 格耕地（实际 %d）" % soil.get_used_cells().size())

	# --- 5. 洒水壶图集 ---
	var can: SpriteFrames = load("res://assets/characters/player_can.tres")
	_check(can != null, "player_can.tres 可加载")
	if can:
		var anims := can.get_animation_names()
		_check(anims.size() == 12, "洒水壶图集 12 个动画（实际 %d）" % anims.size())
		for a in ["walk_up", "walk_down", "walk_left", "walk_right",
				  "thrust_up", "thrust_down", "thrust_left", "thrust_right",
				  "watering_up", "watering_down", "watering_left", "watering_right"]:
			_check(can.has_animation(a), "存在动画 %s" % a)
		if can.has_animation("watering_down"):
			_check(can.get_frame_count("watering_down") >= 4,
				"watering_down 帧数 >= 4（实际 %d）" % can.get_frame_count("watering_down"))
			_check(not can.get_animation_loop("watering_down"), "watering 是一次性动画（不循环）")
			var tex: Texture2D = can.get_frame_texture("watering_down", 0)
			_check(tex != null and tex.get_width() == 64 and tex.get_height() == 64,
				"帧尺寸 64×64")

	# --- 6. 玩家节点按工具换图集 ---
	var player := main.get_node_or_null("World/YSortRoot/Player")
	_check(player != null, "有玩家节点")
	if player:
		player.current_tool = Player.Tool.HOE
		_check(player.active_frames() == player.FRAMES_PLAIN, "锄头 -> 空手图集")
		player.current_tool = Player.Tool.CAN
		_check(player.active_frames() == player.FRAMES_CAN, "洒水壶 -> 洒水壶图集")

	main.queue_free()
	_finish()

func _finish() -> void:
	var ok := _fails.is_empty()
	print("=== 结果：%s ===" % ("全部通过" if ok else "失败 %d 项" % _fails.size()))
	if not ok:
		for f in _fails:
			print("   ! " + f)
	get_tree().quit(0 if ok else 1)
