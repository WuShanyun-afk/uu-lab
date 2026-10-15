class_name FarmGrid
extends RefCounted
## 农场网格数据层（GDD §4 / §11 里程碑 2）
##
## 纯逻辑，不碰渲染、不碰节点。渲染由 FarmLayer 读这里的状态。
## 这样 tileset 换素材时逻辑一行不用动，也方便 headless 断言。

const SIZE := Vector2i(24, 14)
const TILE := 32

## 未浇水枯萎/枯死的天数阈值（GDD §4.1）
const WITHER_DAYS := 2
const DEAD_DAYS := 4


class Tile:
	var tilled := false
	var watered := false
	var crop_id := StringName("")
	var days_grown := 0
	var dry_days := 0          ## 连续未浇水天数
	var dead := false
	var fertilized := 0        ## 0 无 / 1 基础 / 2 高级
	var harvested_once := false


var tiles: Dictionary = {}     ## Vector2i -> Tile
var rng := RandomNumberGenerator.new()

func _init(rng_seed: int = 20261014) -> void:
	rng.seed = rng_seed

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < SIZE.x and cell.y < SIZE.y

func tile_at(cell: Vector2i) -> Tile:
	return tiles.get(cell)

func _ensure(cell: Vector2i) -> Tile:
	if not tiles.has(cell):
		tiles[cell] = Tile.new()
	return tiles[cell]

## 锄地：草地 → 耕地
func till(cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return false
	var t := _ensure(cell)
	if t.tilled:
		return false
	t.tilled = true
	return true

## 浇水（同一天只能浇一次；浇水会清掉枯萎计数）
func water(cell: Vector2i) -> bool:
	var t := tile_at(cell)
	if t == null or not t.tilled or t.watered:
		return false
	t.watered = true
	t.dry_days = 0
	return true

## 播种
func plant(cell: Vector2i, crop_id: StringName) -> bool:
	var t := tile_at(cell)
	if t == null or not t.tilled:
		return false
	if t.crop_id != StringName("") or t.dead:
		return false
	if CropDB.get_crop(crop_id) == null:
		return false
	t.crop_id = crop_id
	t.days_grown = 0
	t.harvested_once = false
	return true

func is_mature(cell: Vector2i) -> bool:
	var t := tile_at(cell)
	if t == null or t.crop_id == StringName("") or t.dead:
		return false
	var c: CropData = CropDB.get_crop(t.crop_id)
	if c == null:
		return false
	return t.days_grown >= c.grow_days

## 生长进度 0.0 ~ 1.0（给渲染层分阶段用）
func growth_ratio(cell: Vector2i) -> float:
	var t := tile_at(cell)
	if t == null or t.crop_id == StringName(""):
		return 0.0
	var c: CropData = CropDB.get_crop(t.crop_id)
	if c == null or c.grow_days <= 0:
		return 1.0
	return clampf(float(t.days_grown) / float(c.grow_days), 0.0, 1.0)

## 收获。返回 {id, quality, count}，不满足条件返回 {}
## quality: 0 基础 / 1 银星 / 2 金星（GDD §4.1）
func harvest(cell: Vector2i) -> Dictionary:
	if not is_mature(cell):
		return {}
	var t := tile_at(cell)
	var c: CropData = CropDB.get_crop(t.crop_id)
	var quality := _roll_quality(t)

	if c.regrow_days > 0:
		t.days_grown = c.grow_days - c.regrow_days
		t.harvested_once = true
	else:
		t.crop_id = StringName("")
		t.days_grown = 0
		t.harvested_once = false

	return {"id": c.id, "quality": quality, "count": 1}

func _roll_quality(t: Tile) -> int:
	var p_silver := 0.05
	var p_gold := 0.0
	match t.fertilized:
		1:
			p_silver = 0.15
			p_gold = 0.03
		2:
			p_silver = 0.30
			p_gold = 0.08
	var r := rng.randf()
	if r < p_gold:
		return 2
	if r < p_gold + p_silver:
		return 1
	return 0

## 跨日结算。返回事件列表（供 UI / 音效订阅）
func advance_day() -> Array:
	var events: Array = []
	for cell in tiles:
		var t: Tile = tiles[cell]
		if t.crop_id == StringName("") or t.dead:
			t.watered = false
			continue
		if t.watered:
			t.days_grown += 1
			t.dry_days = 0
		else:
			t.dry_days += 1
			if t.dry_days >= DEAD_DAYS:
				t.dead = true
				events.append({"cell": cell, "type": "dead"})
			elif t.dry_days >= WITHER_DAYS:
				events.append({"cell": cell, "type": "wither"})
		t.watered = false      # 次日清晨重置
	return events

## 调试 / 测试用：直接推进 N 天，每天自动浇水
func debug_grow(cell: Vector2i, days: int) -> void:
	for i in range(days):
		water(cell)
		advance_day()
