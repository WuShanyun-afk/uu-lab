class_name Housing
extends RefCounted
## 棚舍规则（模块 6 需求 A）—— **纯逻辑**，不碰节点、不碰 UI、不碰背包
##
## 回答三个问题：
##   ① 这只动物住哪种棚舍？（`housing_of` —— 从 animals.csv 的 housing 列派生）
##   ② 现在还能不能再塞一只？（`can_house` —— 返回枚举，不是 bool）
##   ③ 它该在哪块地里活动？（`zone_rect` —— 转调 WorldConfig，视觉分栏的唯一真相）
##
## 和 Breeding / RhythmBar / FarmGrid 一样的分层哲学：
## 判断全在静态函数里，headless 可断言；main 只负责「扣钱、改等级、刷新画面」。
##
## ⚠️ `barns` 参数是 `{StringName(housing_id): int(level)}`，0 / 缺省 = 没盖。
##    为什么不直接读 GameState：这个文件要在没有 autoload 的纯逻辑测试里也能跑。
##    真值由 GameState.barns 提供，main 传进来即可。

enum Reason {
	OK,           ## 能住
	NO_BUILDING,  ## 这种棚舍还没盖
	FULL,         ## 棚舍住满了
	UNKNOWN,      ## 动物 id 不认识 / 没写 housing 列
}

static func reason_text(r: int) -> String:
	match r:
		Reason.OK:
			return ""
		Reason.NO_BUILDING:
			return "棚舍还没盖"
		Reason.FULL:
			return "棚舍住满了"
		Reason.UNKNOWN:
			return "这种动物没有对应的棚舍"
	return "住不进去"

## 这只动物住哪种棚舍（"barn" / "coop" / "hive"）；不认识返回 &""
static func housing_of(species: StringName) -> StringName:
	var d: AnimalData = AnimalDB.get_animal(species)
	if d == null or d.housing == "":
		return &""
	return StringName(d.housing)

## 这个棚舍现在住了几只（按物种的 housing 归属算，不看动物自己的 pos）
static func count_in(herd: Herd, housing_id: StringName) -> int:
	if herd == null:
		return 0
	var n := 0
	for a in herd.animals:
		if housing_of(a.species) == housing_id:
			n += 1
	return n

static func level_of(barns: Dictionary, housing_id: StringName) -> int:
	return int(barns.get(housing_id, 0))

## 容量 = 棚舍等级给的 + 地上额外盖的同类建筑给的（模块 9）。
## bonus 是 `{housing_id: 额外容量}`，来自 BuildingGrid.capacity_bonus()。
## 为什么用参数而不是直接读 BuildingGrid：这个文件要在没有 autoload 的纯逻辑测试里跑。
static func capacity(barns: Dictionary, housing_id: StringName, bonus: int = 0) -> int:
	return HousingDB.capacity_at(housing_id, level_of(barns, housing_id)) + maxi(0, bonus)

static func bonus_of(bonus: Dictionary, housing_id: StringName) -> int:
	return maxi(0, int(bonus.get(housing_id, 0)))

## 还能不能再养一只这种动物？返回 Reason。
static func can_house(species: StringName, herd: Herd, barns: Dictionary,
		bonus: Dictionary = {}) -> int:
	var h := housing_of(species)
	if h == &"" or not HousingDB.has(h):
		return Reason.UNKNOWN
	var b := bonus_of(bonus, h)
	if level_of(barns, h) <= 0 and b <= 0:
		return Reason.NO_BUILDING
	if count_in(herd, h) >= capacity(barns, h, b):
		return Reason.FULL
	return Reason.OK

## 这种动物该待的活动区（像素矩形）—— WorldConfig 是唯一真相
static func zone_rect(species: StringName) -> Rect2:
	return WorldConfig.zone_rect(housing_of(species))

## 棚舍建筑该盖在哪（地面中心点）
static func slot_pos(housing_id: StringName) -> Vector2:
	return WorldConfig.barn_slot(housing_id)

## "畜 3/4 禽 5/5 蜂 1/2" —— HUD 一行摘要（省地方，用单字前缀）
static func summary_text(herd: Herd, barns: Dictionary, bonus: Dictionary = {}) -> String:
	var parts: Array[String] = []
	for id in HousingDB.all_ids():
		var lv := level_of(barns, id)
		var used := count_in(herd, id)
		var cap := capacity(barns, id, bonus_of(bonus, id))
		parts.append("%s%d/%d" % [short_name(id), used, cap])
	return " ".join(parts)

## 棚舍的单字简称（HUD / 提示条用）
static func short_name(housing_id: StringName) -> String:
	match String(housing_id):
		"barn":
			return "畜"
		"coop":
			return "禽"
		"hive":
			return "蜂"
	return String(housing_id).substr(0, 1)

## 牧场里所有棚舍的总容量（Herd.MAX_ANIMALS 之外的第二道闸）
static func total_capacity(barns: Dictionary, bonus: Dictionary = {}) -> int:
	var n := 0
	for id in HousingDB.all_ids():
		n += capacity(barns, id, bonus_of(bonus, id))
	return n
