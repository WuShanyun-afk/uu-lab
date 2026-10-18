class_name NpcState
extends RefCounted
## 一位村民的**运行时状态**（模块 10 需求 1：好感度系统）
##
## 心数 = 点数 / POINTS_PER_HEART。用点数存而不是直接存心数，因为
## GDD §7 的加分是「对话 +5 / 送礼 +15 / 喜欢 +25 / 讨厌 -10」——
## 如果直接存整数心，一次送礼就 +0.3 心，四舍五入永远进不了位。
##
## 10 心封顶 = 500 点。按「每天聊一次 +5、送一份喜欢 +25」算，
## 纯聊天要 100 天，聊天 + 送礼约 17 天满心 —— 一个季节 28 天，节奏刚好。
##
## ⚠️ 存档要注意的点（模块 7/8 的老坑）：
##    1. 所有 id 从 JSON 回来都是 String，必须 StringName() 回来
##    2. 只存真源（points / 次数 / 日期），心数永远现算

const POINTS_PER_HEART := 50
const MAX_HEARTS := 10
const MAX_POINTS := POINTS_PER_HEART * MAX_HEARTS

const TALK_POINTS := 5        ## 每天第一次说话
const GIFT_POINTS := 15       ## 普通礼物
const LOVE_POINTS := 25       ## 最喜欢的礼物
const HATE_POINTS := -10      ## 讨厌的礼物

var id: StringName = &""
var points: int = 0
## 见过面了吗（第一次对话会播自我介绍，之后换成心数台词）
var met: bool = false
## 上一次「聊天加分」是哪一天（同一游戏日只加一次）
var last_talk_day: int = -999
## 上一次送礼是哪一天 + 当天送了几次（一天最多 2 次，防止开局刷满心）
var last_gift_day: int = -999
var gifts_today: int = 0

const GIFTS_PER_DAY := 2

func _init(npc_id: StringName = &"") -> void:
	id = npc_id

func hearts() -> int:
	return clampi(points / POINTS_PER_HEART, 0, MAX_HEARTS)

## 距离下一颗心还差几点（UI 画半颗心用）
func points_to_next_heart() -> int:
	if hearts() >= MAX_HEARTS:
		return 0
	return POINTS_PER_HEART - (points % POINTS_PER_HEART)

func is_max() -> bool:
	return points >= MAX_POINTS

## 加/减好感。返回实际变化量（封顶/触底会变少，UI 要显示真实的数）。
func add_points(delta: int) -> int:
	var before := points
	points = clampi(points + delta, 0, MAX_POINTS)
	return points - before

# ---------------- 每天的动作 ----------------

## 聊天：每天第一次 +5，之后 0（返回实际加点）
func talk(day: int) -> int:
	met = true
	if last_talk_day == day:
		return 0
	last_talk_day = day
	return add_points(TALK_POINTS)

func can_talk(day: int) -> bool:
	return last_talk_day != day

func gift_used(day: int) -> int:
	if last_gift_day != day:
		return 0
	return gifts_today

func can_gift(day: int) -> bool:
	return gift_used(day) < GIFTS_PER_DAY

## 今天还能送几份（UI 提示用）
func gifts_left(day: int) -> int:
	return maxi(0, GIFTS_PER_DAY - gift_used(day))

## 收礼：返回实际加点（讨厌的礼物是负数）
func gift(def: NpcDef, item_id: StringName, day: int) -> int:
	met = true
	if last_gift_day != day:
		last_gift_day = day
		gifts_today = 0
	gifts_today += 1
	return add_points(def.gift_points(item_id) if def != null else GIFT_POINTS)

# ---------------- 存档 ----------------

func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"points": points,
		"met": met,
		"talk_day": last_talk_day,
		"gift_day": last_gift_day,
		"gifts": gifts_today,
	}

static func from_dict(d: Dictionary) -> NpcState:
	var s := NpcState.new(StringName(str(d.get("id", ""))))
	s.points = clampi(int(d.get("points", 0)), 0, MAX_POINTS)
	s.met = bool(d.get("met", false))
	s.last_talk_day = int(d.get("talk_day", -999))
	s.last_gift_day = int(d.get("gift_day", -999))
	s.gifts_today = maxi(0, int(d.get("gifts", 0)))
	return s
