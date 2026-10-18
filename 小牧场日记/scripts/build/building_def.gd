class_name BuildingDef
extends RefCounted
## 一种「可建造物」的**静态定义**（模块 9）—— CSV 一行的结构化投影
##
## 分层：data/buildings.csv（唯一真源）→ BuildingDB（解析 + 缓存）→ BuildingDef（这份）
## 最后才是 BuildingGrid 里的 PlacedBuilding（某个具体的落地实例）。
##
## 为什么 Def 和 Placed 要分开：
##   Def 回答「鸡舍长什么样、多少钱、几级」—— 全项目只有 8 个，CSV 改了就变；
##   Placed 回答「这栋鸡舍在 (10,3)、Lv2、花了多少钱」—— 每个存档都有一堆。
##   混成一个类的下场：改平衡数值时把玩家的建筑一起改了。
##
## 分类（category）决定「放置要注意什么」和「升级加什么」：
##   fence    栅栏 —— 纯装饰 / 场地划分，没有等级（max_level = 1）
##   housing  棚舍 —— 升级加**容量**（capacity_housing 指向 barn / coop / hive）
##   workshop 加工坊 —— 升级加**加工速度**
##   market   农贸市场 —— 升级加**售价**
##   town     小镇建筑 —— 阶段门禁用
##   special  一次性建筑（繁殖棚）—— 不进建造菜单，走原来的剧情流程

const CAT_FENCE := &"fence"
const CAT_HOUSING := &"housing"
const CAT_WORKSHOP := &"workshop"
const CAT_MARKET := &"market"
const CAT_TOWN := &"town"
const CAT_SPECIAL := &"special"

## 拆建筑返还比例（GDD §6：拆除返还 50% 材料）
const REFUND_RATIO := 0.5
## 扩建价 = 造价 × 这个系数 × 当前等级
const UPGRADE_RATIO := 0.6

var id: StringName = &""
var display_name: String = ""
var category: StringName = &""
## 占地格数（1 格 = 32px）。锚点 = **左上角**那一格。
var size: Vector2i = Vector2i.ONE
var price: int = 0
var material: StringName = &""
var material_count: int = 0
## 繁殖棚专用（其它建筑填 0）
var gestation_days: int = 0
var max_level: int = 1
## 这栋建筑住的是哪种棚舍（barn / coop / hive）；空 = 不提供容量
var capacity_housing: StringName = &""
var capacity_base: int = 0
var capacity_step: int = 0
## 每级效率加成（百分点）：加工坊 = 速度，农贸市场 = 售价
var efficiency: int = 0
## 需要牧场到第几阶段才能盖（0 = 开局就能盖）
var stage_required: int = 0
var note: String = ""

## 一行 CSV → 一份 Def。列顺序见 data/buildings.csv 的表头。
## ⚠️ 解析放在 DB 里做，这里只接一个已经切好的行数组 —— 方便测试直接构造。
static func from_row(row: PackedStringArray) -> BuildingDef:
	var d := BuildingDef.new()
	d.id = StringName(row[0].strip_edges())
	d.display_name = row[1].strip_edges()
	d.category = StringName(row[2].strip_edges())
	d.size = Vector2i(maxi(1, int(row[3])), maxi(1, int(row[4])))
	d.price = maxi(0, int(row[5]))
	d.material = StringName(row[6].strip_edges())
	d.material_count = maxi(0, int(row[7]))
	d.gestation_days = maxi(0, int(row[8]))
	d.max_level = maxi(1, int(row[9]))
	d.capacity_housing = StringName(row[10].strip_edges())
	d.capacity_base = maxi(0, int(row[11]))
	d.capacity_step = maxi(0, int(row[12]))
	d.efficiency = maxi(0, int(row[13]))
	d.stage_required = maxi(0, int(row[14]))
	d.note = row[15].strip_edges() if row.size() > 15 else ""
	return d

## 占地格数 → 相对锚点的偏移表（含 (0,0)）
func footprint() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(size.y):
		for x in range(size.x):
			out.append(Vector2i(x, y))
	return out

## 锚点 → 真实占用的所有格子
func footprint_at(anchor: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for off in footprint():
		out.append(anchor + off)
	return out

func is_housing() -> bool:
	return category == CAT_HOUSING

func is_fence() -> bool:
	return category == CAT_FENCE

## 能出现在建造菜单里吗（繁殖棚/小镇这类走剧情或阶段，不进菜单）
func buildable() -> bool:
	return category != CAT_SPECIAL

## 某等级的容量（只有 housing 类会有非 0 值）
func capacity_at(lv: int) -> int:
	if capacity_housing == &"" or lv <= 0:
		return 0
	return capacity_base + capacity_step * (lv - 1)

## 某等级的效率加成（百分点，不是小数）
func efficiency_at(lv: int) -> int:
	if lv <= 0:
		return 0
	return efficiency * lv

## 从 lv 升到 lv+1 的造价（lv = 当前等级，1 起）
func upgrade_gold(lv: int) -> int:
	return int(round(float(price) * UPGRADE_RATIO * float(maxi(1, lv))))

func upgrade_wood(lv: int) -> int:
	return int(round(float(material_count) * float(maxi(1, lv))))

## 拆掉它返还多少（按**实际花掉的钱**算，不是按当前售价）——
## 所以 Lv3 的建筑拆掉返得比 Lv1 多，升级过的钱不会凭空消失。
static func refund_of(spent: int) -> int:
	return int(floor(float(spent) * REFUND_RATIO))

## "900G + 木材×15"
func cost_text() -> String:
	return "%dG + %s×%d" % [price, ProductDB.display_name(material), material_count]

## "Lv2 容量 +7 / 速度 +30%"（提示条用）
func stat_text(lv: int) -> String:
	match String(category):
		"housing":
			return "Lv%d · 容量 +%d" % [lv, capacity_at(lv)]
		"workshop":
			return "Lv%d · 加工速度 +%d%%" % [lv, efficiency_at(lv)]
		"market":
			return "Lv%d · 售价 +%d%%" % [lv, efficiency_at(lv)]
		"fence":
			return "1 格栅栏"
	return "Lv%d" % lv
