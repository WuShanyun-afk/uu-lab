class_name NpcDef
extends RefCounted
## 一位村民的**静态定义**（模块 10）—— data/npcs.csv 一行的结构化投影
##
## 和 BuildingDef / AnimalData 同一套思路：CSV 是唯一真源，Def 只是强类型壳。
## 「她几点在哪」不在这里 —— 那是日程表（data/npc_schedules.csv），
## 因为同一个人的位置是一张表而不是一个字段。
##
## 送礼三档（GDD §7）：喜欢 +25、普通 +15、讨厌 -10。
## 判断顺序：loved → liked → hated → 其它（普通）。
## 「讨厌」必须显式写，不能靠「不喜欢＝讨厌」推 —— 否则送什么都掉好感。

var id: StringName = &""
var display_name: String = ""
## 身份（杂货店老板娘 / 铁匠 / ...）—— 对话框标题右半
var title: String = ""
## 立绘色块（零素材：UI 画一个纯色方块）
var color: Color = Color.WHITE
var loved: StringName = &""
var liked: StringName = &""
var hated: StringName = &""

static func from_row(row: PackedStringArray) -> NpcDef:
	var d := NpcDef.new()
	d.id = StringName(row[0].strip_edges())
	d.display_name = row[1].strip_edges()
	d.title = row[2].strip_edges()
	d.color = Color(row[3].strip_edges()) if row.size() > 3 else Color.WHITE
	d.loved = StringName(row[4].strip_edges())
	d.liked = StringName(row[5].strip_edges())
	d.hated = StringName(row[6].strip_edges())
	return d

## 送礼的好感变化（点数，不是心）
func gift_points(item_id: StringName) -> int:
	if item_id == &"":
		return 0
	if item_id == loved:
		return NpcState.LOVE_POINTS
	if item_id == liked:
		return NpcState.GIFT_POINTS
	if item_id == hated:
		return NpcState.HATE_POINTS
	return NpcState.GIFT_POINTS      # 普通礼物：基础 15

## 送这个反应是哪一档（提示条用："她很喜欢"/"她不太高兴"）
func gift_reaction(item_id: StringName) -> String:
	if item_id == loved:
		return "非常喜欢"
	if item_id == liked:
		return "喜欢"
	if item_id == hated:
		return "不太高兴"
	return "收下了"
