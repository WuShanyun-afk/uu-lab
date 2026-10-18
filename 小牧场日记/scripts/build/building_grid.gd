class_name BuildingGrid
extends RefCounted
## 建造网格（模块 9 需求 1 / 2 / 4）—— **纯逻辑**，不碰节点、不碰 UI、不碰 GameState
##
## 一件事：地上有哪些建筑、还能不能放新的、拆了退多少、升级要多少钱。
## 「够不够钱 / 扣钱 / 扣木材 / 刷新画面」全在 main —— 这里只回答规则问题。
## 和 FarmGrid / Housing / Processor 同一套分层哲学，headless 可断言。
##
## 坐标系：全部是**格子坐标**（Vector2i），1 格 = WorldConfig.TILE = 32px。
## 建筑记录的 anchor 是**左上角**那一格 —— 左上角唯一，中心会落在半格上，
## 而半格坐标在「点到哪栋建筑」的判定里会变成浮点误差。
##
## 占位判定用「先按 anchor 建索引，再线性扫 footprint」：
##   一栋建筑最多 4×3 = 12 格，地上最多几十栋 —— 线性扫完全够快，
##   换来的好处是不用维护第二份「格子 → 建筑」的表（那份表最容易和真源不同步）。
##
## 返回值用枚举不用 bool（模块 3 起的老规矩）：main 要把它翻成人话，
## 测试要断言「到底是越界还是被占了」——bool 两个都答不了。

const OK := &"ok"
const UNKNOWN := &"unknown"            ## 表里没这种建筑
const NO_STAGE := &"no_stage"          ## 牧场阶段不够
const OUT_OF_BOUNDS := &"out_of_bounds" ## 出建造范围 / 出地图
const KEEPOUT := &"keepout"            ## 压围栏 / 商店 / 繁殖棚 / 藤蔓门
const OCCUPIED := &"occupied"          ## 压到别的建筑
const FARM := &"farm"                  ## 压到已耕的地
const NOT_FOUND := &"not_found"        ## 那格上没有建筑
const MAX_LEVEL := &"max_level"        ## 已经满级
const SITE := &"site"                  ## 模块 12：这块地上正在施工

## Vector2i(anchor) -> PlacedBuilding
var placed: Dictionary = {}
## 牧场当前阶段（由 main 从 RanchStage 同步过来；BuildingGrid 不自己去算指标）
var stage: int = 0
## 农场网格（可选）。null = 不检查农田（纯逻辑测试里常常没有 FarmGrid）
var farm: FarmGrid = null
## 施工队列（可选）。有的话，施工中的 footprint 也算「被占」——
## 否则玩家能在脚手架里再叠一栋，工期就白等了。
var sites: Construction = null

# ---------------- 查询 ----------------

func count() -> int:
	return placed.size()

func is_empty() -> bool:
	return placed.is_empty()

## 那格上的建筑（没有返回 null）
func building_at(cell: Vector2i) -> PlacedBuilding:
	for anchor in placed:
		var b: PlacedBuilding = placed[anchor]
		if b.covers(cell):
			return b
	return null

func anchor_of(cell: Vector2i) -> Vector2i:
	var b := building_at(cell)
	return b.anchor if b != null else cell

## 地上有没有某一种建筑（阶段软门禁 / 检查「加工坊盖了没」用）
func has_building(def_id: StringName) -> bool:
	for anchor in placed:
		if (placed[anchor] as PlacedBuilding).def_id == def_id:
			return true
	return false

func buildings_of_category(cat: StringName) -> Array:
	var out: Array = []
	for anchor in placed:
		var b: PlacedBuilding = placed[anchor]
		var d := b.def()
		if d != null and d.category == cat:
			out.append(b)
	return out

## 某一类建筑的最高等级（HUD / 效率计算用；没有返回 0）
func max_level_of_category(cat: StringName) -> int:
	var n := 0
	for b in buildings_of_category(cat):
		n = maxi(n, (b as PlacedBuilding).level)
	return n

# ---------------- 放置 ----------------

## 能不能把 def_id 放在 anchor。返回枚举，OK 才代表能放。
## ⚠️ 顺序有讲究：先查「这种建筑存不存在 / 阶段够不够」，再查位置。
##    玩家在没解锁时点空地，应该听到「还没解锁」而不是「这里放不下」。
func can_place(def_id: StringName, anchor: Vector2i) -> StringName:
	var d: BuildingDef = BuildingDB.def_of(def_id)
	if d == null:
		return UNKNOWN
	if not RanchStage.can_build(stage, d.stage_required):
		return NO_STAGE
	for cell in d.footprint_at(anchor):
		if not WorldConfig.buildable_cell(cell):
			return OUT_OF_BOUNDS
		if WorldConfig.keepout_cell(cell):
			return KEEPOUT
		if sites != null and sites.blocks(cell):
			return SITE
		if building_at(cell) != null:
			return OCCUPIED
		if farm != null:
			var t := farm.tile_at(cell)
			if t != null and t.tilled:
				return FARM
	return OK

func can_place_at_cell(def_id: StringName, cell: Vector2i, anchor_offset: Vector2i = Vector2i.ZERO) -> StringName:
	## 鼠标点在 footprint 中间时，anchor 要往回退，否则 3×2 的鸡舍会整个往右下偏
	return can_place(def_id, cell - anchor_offset)

## 真正落地。返回 PlacedBuilding，放不了返回 null。
## day 只用于显示「第几天落成」，不参与任何判定。
func place(def_id: StringName, anchor: Vector2i, day: int = 1) -> PlacedBuilding:
	if can_place(def_id, anchor) != OK:
		return null
	var d: BuildingDef = BuildingDB.def_of(def_id)
	var b := PlacedBuilding.new(def_id, anchor, day)
	b.level = 1
	b.spent_gold = d.price
	b.spent_wood = d.material_count
	placed[anchor] = b
	return b

## 给 main / 测试用的「无钱无料落地」—— 默认走 place()，
## 但读档时钱已经花过了，不能再扣一次，所以读档走 from_dict 而不是这个。
func force_place(def_id: StringName, anchor: Vector2i, level: int = 1,
		day: int = 1, gold: int = -1, wood: int = -1) -> PlacedBuilding:
	var d: BuildingDef = BuildingDB.def_of(def_id)
	if d == null:
		return null
	var b := PlacedBuilding.new(def_id, anchor, day)
	b.level = clampi(level, 1, d.max_level)
	b.spent_gold = d.price if gold < 0 else gold
	b.spent_wood = d.material_count if wood < 0 else wood
	placed[anchor] = b
	return b

func reason_text(r: StringName) -> String:
	match String(r):
		"ok":
			return ""
		"unknown":
			return "没有这种建筑"
		"no_stage":
			return "牧场阶段不够 · 先扩建"
		"out_of_bounds":
			return "超出建造范围"
		"keepout":
			return "这里压着围栏 / 店铺 / 藤蔓门"
		"occupied":
			return "这里已经有建筑了"
		"farm":
			return "这里种着地 · 先收掉作物"
		"not_found":
			return "这格上没有建筑"
		"max_level":
			return "已经满级了"
		"site":
			return "这里正在施工 · 等工期"
	return "放不下"

# ---------------- 拆除 ----------------

## 拆掉那格上的建筑。返回 {ok, error, building, gold, wood}
## 返还按**实际投入**算（BuildingDef.refund_of），所以升级过的建筑拆得更多。
## ⚠️ 这里的 gold / wood 只是「该退多少」，真正加回背包由 main 做 ——
##    这个类不碰 GameState，测试才能在无 autoload 环境下跑。
func remove_at(cell: Vector2i) -> Dictionary:
	var b := building_at(cell)
	if b == null:
		return {"ok": false, "error": NOT_FOUND, "building": null, "gold": 0, "wood": 0}
	var gold := b.refund_gold()
	var wood := b.refund_wood()
	placed.erase(b.anchor)
	return {"ok": true, "error": OK, "building": b, "gold": gold, "wood": wood}

## 拆之前问一句「能不能拆」（目前只有「那格没建筑」会拒；留给将来加限制）
func can_remove(cell: Vector2i) -> StringName:
	return OK if building_at(cell) != null else NOT_FOUND

# ---------------- 升级 ----------------

## 升级要花多少。返回 {} = 不能升（没建筑 / 已满级）。
func upgrade_cost(cell: Vector2i) -> Dictionary:
	var b := building_at(cell)
	if b == null or not b.can_upgrade():
		return {}
	var d := b.def()
	if d == null:
		return {}
	return {
		"gold": d.upgrade_gold(b.level),
		"wood": d.upgrade_wood(b.level),
		"from": b.level,
		"to": b.level + 1,
		"def": d,
	}

## 扣款由 main 做，这里只负责「升级 + 记账」。
func apply_upgrade(cell: Vector2i, gold: int, wood: int) -> bool:
	var b := building_at(cell)
	if b == null or not b.can_upgrade():
		return false
	b.level += 1
	b.spent_gold += maxi(0, gold)
	b.spent_wood += maxi(0, wood)
	return true

## 一步到位的升级（测试 / 调试用：不查钱）
func upgrade_at(cell: Vector2i) -> bool:
	var c := upgrade_cost(cell)
	if c.is_empty():
		return false
	return apply_upgrade(cell, int(c["gold"]), int(c["wood"]))

# ---------------- 对其它系统的加成 ----------------

## 棚舍容量加成：{housing_id -> 额外容量}
## 这是模块 9 接进模块 6 的那个口子 —— Housing.capacity(barns, id, bonus) 的 bonus。
func capacity_bonus() -> Dictionary:
	var out: Dictionary = {}
	for anchor in placed:
		var b: PlacedBuilding = placed[anchor]
		var d := b.def()
		if d == null or d.capacity_housing == &"":
			continue
		var id: StringName = d.capacity_housing
		out[id] = int(out.get(id, 0)) + b.capacity()
	return out

## 加工速度倍率：1.0 = 没有加工坊；每级 +15% 就叠到 1.15 / 1.30 / 1.45
func craft_speed() -> float:
	var pct := 0
	for b in buildings_of_category(BuildingDef.CAT_WORKSHOP):
		pct += (b as PlacedBuilding).efficiency()
	return 1.0 + float(pct) / 100.0

## 出货售价加成（加在 Market 算出来的价上）：0.0 = 没有农贸市场
func sell_bonus() -> float:
	var pct := 0
	for b in buildings_of_category(BuildingDef.CAT_MARKET):
		pct += (b as PlacedBuilding).efficiency()
	return float(pct) / 100.0

## 阶段进度：地上有哪些「地标建筑」—— 存档里的阶段和建筑不一致时用它兜底
func landmarks() -> Array:
	var out: Array = []
	for anchor in placed:
		var b: PlacedBuilding = placed[anchor]
		var d := b.def()
		if d != null and d.category == BuildingDef.CAT_TOWN:
			out.append(d.id)
	return out

func reset() -> void:
	placed.clear()
	stage = 0

# ---------------- 存档（模块 8 / 9）----------------
#
# 只存真源：每栋建筑的 def_id / anchor / 等级 / 账本 + 当前阶段。
# 派生量（容量加成、加工倍率）一律读档后现算 —— 存了就会出现两份真值，
# 而两份真值里总有一份是旧的。

func to_dict() -> Dictionary:
	var items: Array = []
	for anchor in placed:
		items.append((placed[anchor] as PlacedBuilding).to_dict())
	# 排序：Dictionary 的遍历顺序在存档里不该影响 diff，按 (y, x) 钉死一个顺序
	items.sort_custom(func(a, b):
		if int(a["y"]) != int(b["y"]):
			return int(a["y"]) < int(b["y"])
		return int(a["x"]) < int(b["x"]))
	return {"stage": stage, "items": items}

func from_dict(d: Dictionary) -> void:
	placed.clear()
	stage = RanchStage.clamp_stage(int(d.get("stage", 0)))
	var items: Array = d.get("items", [])
	for raw in items:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var b := PlacedBuilding.from_dict(raw)
		if b.def_id == &"" or BuildingDB.def_of(b.def_id) == null:
			continue                      # 表里删掉的建筑：丢掉，别让存档把游戏搞崩
		placed[b.anchor] = b
