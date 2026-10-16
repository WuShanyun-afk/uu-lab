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

