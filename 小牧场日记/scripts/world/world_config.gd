class_name WorldConfig
extends RefCounted
## 世界尺寸与关键区域的**唯一真相来源**（GDD §10.1 / §10.4）
##
## 以前 PEN / FIELD_TILES 在 main.gd 和 ground_layer.gd 各写了一份，
## 改地图要改两处、还容易忘 —— 现在全部收在这里：
##   地面铺设、牧场栅栏、物理碰撞墙、相机 limit 全部从这一份数据派生。
##
## 规则：想让地图变大/挪栅栏，只改本文件。别的地方不许再写字面量。

const TILE := 32

## 地图格数 24 × 14 = 768 × 448 px（视口 640×360 的 1.2 / 1.24 倍，相机才推得动）
const MAP_TILES := Vector2i(24, 14)
const MAP_PX := Vector2i(768, 448)

## 牧场栅栏（像素）
const PEN := Rect2(512, 64, 224, 192)
## 栅栏门洞（左侧，2 格宽）—— 玩家从这里走进牧场喂牛
const GATE := Rect2(512, 160, 32, 64)

## 栅栏厚度 / 地图围墙厚度
const WALL_T := 6.0
const BOUNDS_T := 8.0

## 相机可用区域 → [left, top, right, bottom]
static func camera_limits() -> Array:
	return [0, 0, MAP_PX.x, MAP_PX.y]

## 地图四边围墙（矩形列表）—— 防止玩家走出场景
static func bounds_walls() -> Array[Rect2]:
	var t := BOUNDS_T
	var w := float(MAP_PX.x)
	var h := float(MAP_PX.y)
	return [
		Rect2(0.0, -t, w, t),          # 上
		Rect2(0.0, h, w, t),           # 下
		Rect2(-t, 0.0, t, h),          # 左
		Rect2(w, 0.0, t, h),           # 右
	]

## 牧场栅栏拆成 5 段实体：左边被门洞断成上、下两截，其余三边各一段
static func fence_walls() -> Array[Rect2]:
	var t := WALL_T
	var out: Array[Rect2] = []
	out.append(Rect2(PEN.position, Vector2(PEN.size.x, t)))                                  # 上
	out.append(Rect2(Vector2(PEN.position.x, PEN.end.y - t), Vector2(PEN.size.x, t)))         # 下
	out.append(Rect2(Vector2(PEN.position.x, PEN.position.y + t),                            # 左上段
		Vector2(t, GATE.position.y - PEN.position.y - t)))
	out.append(Rect2(Vector2(PEN.position.x, GATE.end.y),                                    # 左下段
		Vector2(t, PEN.end.y - GATE.end.y - t)))
	out.append(Rect2(Vector2(PEN.end.x - t, PEN.position.y + t),                             # 右
		Vector2(t, PEN.size.y - 2.0 * t)))
	return out

# ============================================================================
# 棚舍分栏（模块 6 需求 A）
# ============================================================================
#
# 围栏内横向切三段，每段对应一种棚舍。动物按 animals.csv 的 housing 列
# 自动落到自己那段里活动（见 Housing.zone_rect / main._clamp_animals_to_zones）。
#
#   y 64 ───────────── 围栏顶
#   y 72..112   [畜舍]      [禽舍]      [蜂箱]     ← 建筑向上长
#   y 120..250  barn 区     coop 区     hive 区    ← 动物活动
#   y 256 ───────────── 围栏底
#
# ⚠️ 三块 zone 必须都在 PEN 里、互不重叠、且不压到建筑 —— 测试会断言这三条。
# ⚠️ 别改 PEN / GATE：模块 1 的碰撞测试按那组矩形钉死了。

const PEN_ZONES := {
	&"barn": Rect2(516, 120, 68, 130),
	&"coop": Rect2(588, 120, 68, 130),
	&"hive": Rect2(660, 120, 72, 130),
}

## 棚舍建筑的地面中心点（建筑向上画，所以这是「脚下」那一点）
const BARN_SLOTS := {
	&"barn": Vector2(552, 112),
	&"coop": Vector2(624, 112),
	&"hive": Vector2(700, 112),
}

## 某种棚舍的活动区；不认识的 housing 返回整个围栏（兜底，不崩）
static func zone_rect(housing_id: StringName) -> Rect2:
	if PEN_ZONES.has(housing_id):
		return PEN_ZONES[housing_id]
	return PEN

## 某种棚舍建筑的位置
static func barn_slot(housing_id: StringName) -> Vector2:
	return BARN_SLOTS.get(housing_id, PEN.get_center())

## 给定坐标属于哪块 zone（不在任何 zone 里返回 &""）—— 出生点夹取用
static func zone_at(pos: Vector2) -> StringName:
	for id in PEN_ZONES.keys():
		if PEN_ZONES[id].has_point(pos):
			return id
	return &""

# ============================================================================
# 秘密花园（模块 5 需求 5）—— 主地图右侧的一块独立区域
# ============================================================================
#
# ⚠️ 这里**不动** MAP_PX / camera_limits()。模块 1 的测试把主地图尺寸钉死了
#    （768×448 / camera_limits = [0,0,768,448]），花园走自己的一套函数：
#    camera_limits_for(in_garden) 由 main 按玩家所在区域切换。
#
# 两块地之间留 64px 视觉缝（主地图 x 到 768，花园从 832 起），
# 所以从主地图**走不过去** —— 只能从藤蔓门传送。这是有意的：
# 花园是奖励，不是「绕个远路就能提前摸进去」。

## 花园左上角（px）与格数。20×12 格 = 640×384 px，比视口 640×360 大，
## 相机 limit 才不会比视口还小（否则边缘会露出背景色）。
const GARDEN_ORIGIN := Vector2i(832, 32)
const GARDEN_TILES := Vector2i(20, 12)

## 藤蔓门（主地图一侧）/ 回到牧场时的落点
const GATE_POS := Vector2(744, 288)
const FARM_ENTRY := Vector2(704, 288)

## 花园里的传送门（回牧场）与玩家进场落点
const GARDEN_PORTAL_POS := Vector2(880, 360)
const GARDEN_ENTRY := Vector2(1152, 340)

## 花园中心的喷泉（9 座觉醒石碑围着它排一圈）
const GARDEN_FOUNTAIN := Vector2(1152, 224)
const GARDEN_STELE_RADIUS := 116.0

static func garden_rect() -> Rect2:
	return Rect2(Vector2(GARDEN_ORIGIN), Vector2(GARDEN_TILES * TILE))

## 花园左上角 → TileMapLayer 的格子坐标
static func garden_cell_origin() -> Vector2i:
	return GARDEN_ORIGIN / TILE

## 花园四周的围墙（4 面，没有门洞 —— 进出都靠传送）
static func garden_walls() -> Array[Rect2]:
	var t := WALL_T
	var r := garden_rect()
	var out: Array[Rect2] = []
	out.append(Rect2(r.position, Vector2(r.size.x, t)))
	out.append(Rect2(Vector2(r.position.x, r.end.y - t), Vector2(r.size.x, t)))
	out.append(Rect2(Vector2(r.position.x, r.position.y + t), Vector2(t, r.size.y - 2.0 * t)))
	out.append(Rect2(Vector2(r.end.x - t, r.position.y + t), Vector2(t, r.size.y - 2.0 * t)))
	return out

## 花园的相机可用区域
static func garden_camera_limits() -> Array:
	var r := garden_rect()
	return [int(r.position.x), int(r.position.y), int(r.end.x), int(r.end.y)]

## 按「玩家在哪块地」取相机 limit
static func camera_limits_for(in_garden: bool) -> Array:
	return garden_camera_limits() if in_garden else camera_limits()

## 这个坐标是不是在花园里
static func in_garden(pos: Vector2) -> bool:
	return garden_rect().has_point(pos)

## 第 i 座觉醒石碑的位置（i = 物种在 AnimalDB 里的序号，0..8）
## 从正上方开始顺时针排一圈，纯几何，确定性 —— 测试可以断言不会重叠。
static func stele_pos(i: int, total: int) -> Vector2:
	if total <= 0:
		return GARDEN_FOUNTAIN
	var a := -PI * 0.5 + TAU * float(i) / float(total)
	return GARDEN_FOUNTAIN + Vector2(cos(a), sin(a)) * GARDEN_STELE_RADIUS

# ============================================================================
# 建造用地（模块 9 需求 4：布局自由摆放）
# ============================================================================
#
# 「自由摆放」不等于「随便哪里都能塞」。这条链上有三样东西**绝对不能压**：
#   ① 牧场围栏（PEN）—— 里面是三块棚舍分栏，动物按 zone 活动；
#      在栏中间盖个鸡舍，动物会站在墙里，而且 _clamp_animals_to_zones 每跨日
#      都会把它拽回去，看上去像「建筑会跑」。
#   ② 现有商店 / 出货箱 / 繁殖棚 / 藤蔓门 —— 它们的位置定死在 main.tscn 里，
#      再盖一栋上去会两个 Area2D 重叠，玩家按 E 触发哪个看运气。
#   ③ 已耕的地 —— 玩家花钱锄过的地不能被建筑吃掉，这跟「别压作物」是同一条。
#
# 剩下的整块草地随便摆。地图 24×14 格，四边各留 1 格当围墙缓冲，
# 所以可用范围是 x 1..22、y 1..12 —— 扣掉上面三样之后仍有 ~40 格空地。

## 可建造的像素范围（地图向内缩 1 格）
const BUILD_INSET := TILE

static func build_area() -> Rect2:
	return Rect2(Vector2(BUILD_INSET, BUILD_INSET),
		Vector2(MAP_PX - Vector2i(BUILD_INSET * 2, BUILD_INSET * 2)))

## 已有建筑物占地的近似矩形（比碰撞体略大一圈，留出「别贴着盖」的余量）。
## 数值来自 scenes/main.tscn 里的 position + CollisionShape2D.size，
## 改那棵树的时候**必须**回来改这里 —— 所以测试会断言每个 keepout 都落在 build_area 内。
static func build_keepers() -> Array[Rect2]:
	return [
		PEN,                                                    # 牧场围栏（含三栋棚舍）
		Rect2(334, 160, 36, 32),                                # 告示牌 SignPost
		Rect2(400, 160, 32, 32),                                # 种子商店 SeedShop
		Rect2(464, 160, 32, 32),                                # 出货箱 ShippingBin
		Rect2(400, 232, 32, 32),                                # 动物商店 AnimalShop
		Rect2(464, 232, 32, 32),                                # 杂货铺 SupplyShop
		Rect2(336, 304, 32, 32),                                # 工具铺 ToolShop
		Rect2(400, 304, 32, 32),                                # 订单板 OrderPost
		Rect2(456, 302, 48, 36),                                # 加工坊 CraftWorkshop
		Rect2(572, 270, 56, 38),                                # 繁殖棚 BreedingShed
		Rect2(724, 262, 40, 50),                                # 藤蔓门 GardenGate
		Rect2(284, 134, 32, 32),                                # 模块 11：小屋门（进屋内）
		Rect2(674, 384, 32, 32),                                # 模块 11：镇口（去镇上）
		Rect2(64, 224, 32, 32),                                 # 模块 11：矿洞口
	]

## 格子在可建造范围内吗
static func buildable_cell(cell: Vector2i) -> bool:
	var r := build_area()
	var px := Rect2(Vector2(cell) * float(TILE), Vector2(TILE, TILE))
	return r.encloses(px)

## 这个格子压到已有建筑 / 围栏了吗
static func keepout_cell(cell: Vector2i) -> bool:
	var px := Rect2(Vector2(cell) * float(TILE), Vector2(TILE, TILE))
	for r in build_keepers():
		if r.intersects(px):
			return true
	return false

## 像素坐标 → 格子（负数向下取整也要正确，所以用 floori 而不是 int 强转）
static func px_to_cell(px: Vector2) -> Vector2i:
	return Vector2i(floori(px.x / float(TILE)), floori(px.y / float(TILE)))

static func cell_to_px(cell: Vector2i) -> Vector2:
	return Vector2(cell) * float(TILE)

