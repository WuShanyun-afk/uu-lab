class_name RoomData
extends RefCounted
## 房间 / 场景数据表（模块 11 需求 3）—— 纯数据，一个房间 = 一条字典
##
## 为什么不给每间房写一个 .gd：
##   屋内 / 镇上 / 商店 / 矿洞这四个场景的**结构完全一样**
##   （一块地板 + 若干出口 + 若干可交互物）。给每个写 80 行脚本的后果是
##   改一次「出口提示文案」要改四遍 —— 所以房间描述进数据表，
##   场景脚本只有一个 RoomScene（按 room_id 读表搭场景）。
##
## 出口（exits）字段：
##   to / entry : 目标场景 + 目标入口名
##   label      : 提示条上「出门回牧场」这种文字
##   pos / size : 出口触发区（房间坐标）
##
## 可交互物（props）字段：
##   id / label / action / pos / size
##   action 由 RoomScene 解释：save=存档柜 · shop=柜台 · bed=床 · machine=机器 · info=告示牌
##
## ⚠️ 坐标是**房间局部坐标**（房间左上角 = 0,0），和牧场那张大地图无关。
##    RoomScene 会把相机 limit 设成房间大小，所以房间别超过 ~640×360（否则一屏看不全）。

## 牧场那边的落点：出房间 → 回牧场时站在哪
const FARM_ENTRIES := {
	&"house_door": Vector2(300, 168),    # 小屋门外
	&"from_town": Vector2(690, 400),     # 镇口
	&"from_mine": Vector2(80, 240),      # 矿洞口
	&"": Vector2(384, 224),              # 兜底：牧场出生点
}

const ROOMS := {
	&"house": {
		"name": "我的小屋",
		"bg": Color("#4E3B2A"),
		"floor": Color("#6B5138"),
		"size": Vector2i(640, 360),
		"entries": {
			&"door": Vector2(320, 310),
			&"": Vector2(320, 310),
		},
		"exits": [
			{"to": &"farm", "entry": &"house_door", "label": "出门回牧场",
				"pos": Vector2(320, 42), "size": Vector2(80, 32)},
		],
		"props": [
			{"id": &"bed", "label": "床", "action": &"bed",
				"pos": Vector2(130, 210), "size": Vector2(56, 32)},
			{"id": &"chest", "label": "存档柜", "action": &"save",
				"pos": Vector2(500, 210), "size": Vector2(48, 32)},
		],
	},
	&"town": {
		"name": "小镇",
		"bg": Color("#7E8C6A"),
		"floor": Color("#A0AE88"),
		"size": Vector2i(640, 360),
		"entries": {
			&"from_farm": Vector2(90, 310),
			&"from_shop": Vector2(540, 210),
			&"": Vector2(90, 310),
		},
		"exits": [
			{"to": &"farm", "entry": &"from_town", "label": "回牧场",
				"pos": Vector2(56, 310), "size": Vector2(48, 40)},
			{"to": &"shop", "entry": &"from_town", "label": "进杂货铺",
				"pos": Vector2(540, 100), "size": Vector2(64, 40)},
		],
		"props": [
			{"id": &"notice", "label": "告示牌", "action": &"info",
				"pos": Vector2(320, 170), "size": Vector2(56, 32)},
		],
	},
	&"shop": {
		"name": "杂货铺",
		"bg": Color("#5A4A38"),
		"floor": Color("#8A7458"),
		"size": Vector2i(640, 360),
		"entries": {
			&"from_town": Vector2(320, 310),
			&"": Vector2(320, 310),
		},
		"exits": [
			{"to": &"town", "entry": &"from_shop", "label": "回小镇",
				"pos": Vector2(320, 40), "size": Vector2(80, 32)},
		],
		"props": [
			{"id": &"counter", "label": "柜台", "action": &"shop",
				"pos": Vector2(320, 150), "size": Vector2(96, 36)},
		],
	},
	&"mine": {
		"name": "旧矿洞",
		"bg": Color("#2E2E38"),
		"floor": Color("#3E3E4A"),
		"size": Vector2i(640, 360),
		"entries": {
			&"from_farm": Vector2(320, 310),
			&"": Vector2(320, 310),
		},
		"exits": [
			{"to": &"farm", "entry": &"from_mine", "label": "出矿洞",
				"pos": Vector2(320, 40), "size": Vector2(80, 32)},
		],
		"props": [
			{"id": &"machine", "label": "睡着的机器", "action": &"machine",
				"pos": Vector2(500, 150), "size": Vector2(64, 40)},
			{"id": &"cart", "label": "矿车", "action": &"info",
				"pos": Vector2(140, 210), "size": Vector2(56, 32)},
		],
	},
}

static func has_room(id: StringName) -> bool:
	return ROOMS.has(id)

static func room(id: StringName) -> Dictionary:
	return ROOMS.get(id, {})

static func room_name(id: StringName) -> String:
	return str(room(id).get("name", String(id)))

static func room_size(id: StringName) -> Vector2i:
	return room(id).get("size", Vector2i(640, 360))

static func exits_of(id: StringName) -> Array:
	return room(id).get("exits", [])

static func props_of(id: StringName) -> Array:
	return room(id).get("props", [])

## 某房间某个入口名的出生点（找不到就用默认入口 / 房间中心）
static func entry_pos(id: StringName, entry: StringName) -> Vector2:
	var entries: Dictionary = room(id).get("entries", {})
	if entries.has(entry):
		return entries[entry]
	if entries.has(&""):
		return entries[&""]
	return Vector2(room_size(id)) * 0.5

## 回牧场时站哪
static func farm_entry_pos(entry: StringName) -> Vector2:
	return FARM_ENTRIES.get(entry, FARM_ENTRIES[&""])
