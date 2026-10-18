class_name PlacedBuilding
extends RefCounted
## 一栋**已落地**的建筑（模块 9）
##
## 和 BuildingDef 的关系：Def 是「种类」，这个是「这一栋」。
## 同一份 CSV 里的鸡舍可以在地上盖 5 栋，每栋有自己的等级和账本。
##
## 为什么要记 spent_gold / spent_wood：
##   拆除返还 50% 说的是「返还造它花的钱」。如果只按 CSV 现价算，
##   一栋升级到 Lv3、投了 900+540+1080 的鸡舍，拆掉只退 450 —— 玩家会骂人。
##   所以账本跟着实例走，返还永远按真实投入算。
##
## 为什么记 built_day：小镇/阶段 UI 要显示「第 12 天落成」，也给成就系统留口子。

var def_id: StringName = &""
## 占地的**左上角**格子（不是中心）—— 左上角在网格里唯一，中心可能落在半格
var anchor: Vector2i = Vector2i.ZERO
var level: int = 1
var built_day: int = 1
var spent_gold: int = 0
var spent_wood: int = 0

func _init(id: StringName = &"", at: Vector2i = Vector2i.ZERO, day: int = 1) -> void:
	def_id = id
	anchor = at
	built_day = day

func def() -> BuildingDef:
	return BuildingDB.def_of(def_id)

func display_name() -> String:
	return BuildingDB.name_of(def_id)

## 占地面积（格）
func cells() -> Array[Vector2i]:
	var d := def()
	if d == null:
		return [] as Array[Vector2i]
	return d.footprint_at(anchor)

func covers(cell: Vector2i) -> bool:
	var d := def()
	if d == null:
		return false
	return cell.x >= anchor.x and cell.y >= anchor.y \
		and cell.x < anchor.x + d.size.x and cell.y < anchor.y + d.size.y

## 这栋建筑当前位置的世界坐标中心（画图 / 相机用）
func world_center() -> Vector2:
	var d := def()
	var tiles := Vector2i.ONE if d == null else d.size
	return Vector2(anchor) * float(WorldConfig.TILE) \
		+ Vector2(tiles) * float(WorldConfig.TILE) * 0.5

func capacity() -> int:
	var d := def()
	return 0 if d == null else d.capacity_at(level)

func efficiency() -> int:
	var d := def()
	return 0 if d == null else d.efficiency_at(level)

func can_upgrade() -> bool:
	var d := def()
	return d != null and level < d.max_level

## 拆掉返还多少（金币 / 木材各按实际投入的一半）
func refund_gold() -> int:
	return BuildingDef.refund_of(spent_gold)

func refund_wood() -> int:
	return BuildingDef.refund_of(spent_wood)

func to_dict() -> Dictionary:
	return {
		"id": String(def_id),
		"x": anchor.x,
		"y": anchor.y,
		"level": level,
		"day": built_day,
		"gold": spent_gold,
		"wood": spent_wood,
	}

## ⚠️ JSON 回来全是 String / float，必须逐个转回来。
##    模块 8 踩过：AnimalState 的 StringName 没转，读档后全变未知物种。
static func from_dict(d: Dictionary) -> PlacedBuilding:
	var b := PlacedBuilding.new(
		StringName(str(d.get("id", ""))),
		Vector2i(int(d.get("x", 0)), int(d.get("y", 0))),
		int(d.get("day", 1)))
	b.level = maxi(1, int(d.get("level", 1)))
	b.spent_gold = maxi(0, int(d.get("gold", 0)))
	b.spent_wood = maxi(0, int(d.get("wood", 0)))
	return b
