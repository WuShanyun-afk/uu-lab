class_name FarmGrid
extends RefCounted
## 农场网格数据层（GDD §4 / 模块 3）
##
## 纯逻辑，不碰渲染、不碰节点。渲染由 FarmLayer / CropLayer 读这里的状态。
## 这样 tileset 换素材时逻辑一行不用动，也方便 headless 断言。
##
## 模块 3 新增的三件事：
##   1. season 门禁 —— 每颗作物只在自己那一季能种（春天种不了南瓜）
##   2. 肥料 —— fertilize() 写入 Tile.fertilized，同时影响「成熟天数」和「品质骰」
##   3. 品质 —— 收获产出带 _silver / _gold 后缀的 item id，售价由 CropQuality 决定

const SIZE := Vector2i(24, 14)
const TILE := 32

## 未浇水枯萎/枯死的天数阈值（GDD §4.1）
const WITHER_DAYS := 2
const DEAD_DAYS := 4

## plant_reason() / fertilize_reason() 的返回码
const OK := &"ok"
const NOT_TILLED := &"not_tilled"
const OCCUPIED := &"occupied"
const UNKNOWN_CROP := &"unknown_crop"
const WRONG_SEASON := &"wrong_season"
const ALREADY_BETTER := &"already_better"
const OUT_OF_BOUNDS := &"out_of_bounds"


class Tile:
	var tilled := false
	var watered := false
	var crop_id := StringName("")
	var days_grown := 0
	var dry_days := 0          ## 连续未浇水天数
	var dead := false
	var fertilized := 0        ## 0 无 / 1 基础 / 2 高级（Fertilizer.Level）
	var harvested_once := false
	var harvest_count := 0     ## 这格累计收获次数（统计用）


var tiles: Dictionary = {}     ## Vector2i -> Tile
var rng := RandomNumberGenerator.new()
## 当前季节门禁：-1 = 不限制（测试/沙盒），0-3 = 只允许该季作物。
## main.gd 在 _ready 和 season_changed 时同步成 GameClock.season。
var season: int = -1

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

# ---------------- 锄地 ----------------

## 锄地：草地 → 耕地。
## 已经有**活作物**的格子不能锄（返回 false）；枯死作物的格子会被清理干净（返回 true）。
func till(cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return false
	var t := _ensure(cell)
	if t.dead:
		_clear(t)              # 清理枯死作物 → 重新可用
		return true
	if t.tilled:
		return false
	t.tilled = true
	return true

## 清空一格（作物 / 肥料 / 枯萎状态），保留 tilled
func _clear(t: Tile) -> void:
	t.crop_id = StringName("")
	t.days_grown = 0
	t.dry_days = 0
	t.dead = false
	t.fertilized = 0
	t.harvested_once = false

## 外部想手动铲掉一格作物（含未枯死的）
func clear_crop(cell: Vector2i) -> bool:
	var t := tile_at(cell)
	if t == null or not t.tilled:
		return false
	_clear(t)
	return true

# ---------------- 浇水 ----------------

## 浇水（同一天只能浇一次；浇水会清掉枯萎计数）
func water(cell: Vector2i) -> bool:
	var t := tile_at(cell)
	if t == null or not t.tilled or t.watered:
		return false
	t.watered = true
	t.dry_days = 0
	return true

## 雨天自动浇水（GDD §2.2）：所有已耕地一次浇满，不耗玩家体力。
## 返回浇到的格数。
func water_all() -> int:
	var n := 0
	for cell in tiles:
		var t: Tile = tiles[cell]
		if t.tilled and not t.watered:
			t.watered = true
			t.dry_days = 0
			n += 1
	return n

# ---------------- 肥料（模块 3 需求 5）----------------

## 施肥。只能施在已耕地上，且不能降级（基础肥盖不掉高级肥）。
func fertilize(cell: Vector2i, level: int) -> bool:
	return fertilize_reason(cell, level) == OK

func fertilize_reason(cell: Vector2i, level: int) -> StringName:
	if not in_bounds(cell):
		return OUT_OF_BOUNDS
	var t := tile_at(cell)
	if t == null or not t.tilled:
		return NOT_TILLED
	if level <= 0:
		return ALREADY_BETTER
	if t.fertilized >= level:
		return ALREADY_BETTER
	t.fertilized = clampi(level, 0, Fertilizer.MAX_LEVEL)
	return OK

# ---------------- 播种（模块 3 需求 1 / 3）----------------

## 播种。季节门禁见 self.season（-1 = 不限制）
func plant(cell: Vector2i, crop_id: StringName) -> bool:
	return plant_reason(cell, crop_id) == OK

## 返回 OK / NOT_TILLED / OCCUPIED / UNKNOWN_CROP / WRONG_SEASON / OUT_OF_BOUNDS
## main.gd 拿它给玩家说人话，测试拿它断言。
##
## ⚠️ dry_run = true 时**只看不种**（不写 t.crop_id）。
##    模块 4 的种子商店要求「先确认种得下，再检查有没有种子」，所以需要一个纯查询入口。
##    默认 false 保持老行为（调用即种下），里程碑 2 / 3 的测试不受影响。
func plant_reason(cell: Vector2i, crop_id: StringName, dry_run: bool = false) -> StringName:
	if not in_bounds(cell):
		return OUT_OF_BOUNDS
	var t := tile_at(cell)
	if t == null or not t.tilled:
		return NOT_TILLED
	if t.crop_id != StringName("") or t.dead:
		return OCCUPIED
	var c: CropData = CropDB.get_crop(crop_id)
	if c == null:
		return UNKNOWN_CROP
	if season >= 0 and c.season != season:
		return WRONG_SEASON
	if not dry_run:
		t.crop_id = crop_id
		t.days_grown = 0
		t.harvested_once = false
	return OK

## 这颗作物现在能不能种（给种子选择 UI 灰显用）
func can_plant(crop_id: StringName) -> bool:
	var c: CropData = CropDB.get_crop(crop_id)
	if c == null:
		return false
	return season < 0 or c.season == season

# ---------------- 生长（模块 3 需求 6）----------------

## 施肥后的实际成熟天数（不施肥 = c.grow_days）
## 高级肥 +1 天，但「施肥需求 高」的作物吸收好、不加天（Fertilizer.growth_delta）
func effective_grow_days(cell: Vector2i) -> int:
	var t := tile_at(cell)
	if t == null or t.crop_id == StringName(""):
		return 0
	var c: CropData = CropDB.get_crop(t.crop_id)
	if c == null:
		return 0
	return maxi(1, c.grow_days + Fertilizer.growth_delta(c.fertilize, t.fertilized))

func is_mature(cell: Vector2i) -> bool:
	var t := tile_at(cell)
	if t == null or t.crop_id == StringName("") or t.dead:
		return false
	return t.days_grown >= effective_grow_days(cell)

## 生长进度 0.0 ~ 1.0（给渲染层分阶段用）
func growth_ratio(cell: Vector2i) -> float:
	var t := tile_at(cell)
	if t == null or t.crop_id == StringName(""):
		return 0.0
	var need := effective_grow_days(cell)
	if need <= 0:
		return 1.0
	return clampf(float(t.days_grown) / float(need), 0.0, 1.0)

## 还要几天成熟（HUD 提示用）
func days_left(cell: Vector2i) -> int:
	if is_mature(cell):
		return 0
	return maxi(0, effective_grow_days(cell) - tile_at(cell).days_grown)

# ---------------- 收获 ----------------

## 收获。返回 {id, quality, count, item}，不满足条件返回 {}
##   id     基础作物 id（turnip）
##   quality  CropQuality.Level（0 普通 / 1 银星 / 2 金星）
##   item    背包用 id（turnip / turnip_silver / turnip_gold）
func harvest(cell: Vector2i) -> Dictionary:
	if not is_mature(cell):
		return {}
	var t := tile_at(cell)
	var c: CropData = CropDB.get_crop(t.crop_id)
	var quality := _roll_quality(t, c)
	t.harvest_count += 1

	if c.regrow_days > 0:
		# 再生作物：留在地里，回退到「成熟 - 再生间隔」天
		t.days_grown = maxi(0, effective_grow_days(cell) - c.regrow_days)
		t.harvested_once = true
	else:
		t.crop_id = StringName("")
		t.days_grown = 0
		t.harvested_once = false
		t.fertilized = 0       # 肥料被这一茬吃掉了，下茬要重新施

	return {
		"id": c.id,
		"quality": quality,
		"count": 1,
		"item": CropQuality.item_id(c.id, quality),
	}

func _roll_quality(t: Tile, c: CropData) -> int:
	var affinity := c.fertilize if c != null else 0
	return Fertilizer.roll_quality(affinity, t.fertilized, rng)

# ---------------- 跨日结算 ----------------

## 跨日结算。返回事件列表（供 UI / 音效订阅）
## ⚠️ 全局语义：调一次 = 全世界过了一天，不管这个 grid 属于谁。
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
			if is_mature(cell):
				events.append({"cell": cell, "type": "mature"})
		else:
			t.dry_days += 1
			if t.dry_days >= DEAD_DAYS:
				t.dead = true
				events.append({"cell": cell, "type": "dead"})
			elif t.dry_days >= WITHER_DAYS:
				events.append({"cell": cell, "type": "wither"})
		t.watered = false      # 次日清晨重置
	return events

# ---------------- 统计 / 调试 ----------------

## 地里现在有几株活作物（HUD 用）
func crop_count() -> int:
	var n := 0
	for cell in tiles:
		var t: Tile = tiles[cell]
		if t.crop_id != StringName("") and not t.dead:
			n += 1
	return n

## 有几格施了肥
func fertilized_count() -> int:
	var n := 0
	for cell in tiles:
		var t: Tile = tiles[cell]
		if t.tilled and t.fertilized > 0:
			n += 1
	return n

## 调试 / 测试用：直接推进 N 天，每天自动浇水
func debug_grow(cell: Vector2i, days: int) -> void:
	for i in range(days):
		water(cell)
		advance_day()
