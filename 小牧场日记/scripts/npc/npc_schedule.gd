class_name NpcSchedule
extends RefCounted
## 日程表求值（模块 10 需求 2）—— **纯逻辑**，不碰节点、不碰 UI、不碰存档
##
## 输入：村民 id + 当前游戏分钟（GameClock.minutes）+ 本季第几天
## 输出：{x, y, action, visible} —— 这一刻他应该在哪、在干什么、出不出门
##
## ⚠️ **小时要换算**：GameClock.minutes 是「从 6:00 起算的当日已过分钟」，
##    所以 0 = 6:00，1200 = 次日 2:00。这里给出统一的 hour_of()，
##    别在别处再写一遍 6 + minutes/60（写两遍就会有一处忘记 +6）。
##
## ⚠️ **缺席是一种状态**：阿海 12:00 收网、老陈 6:00-18:00 在家，
##    这些人不是「不存在」，而是 visible = false —— 节点藏起来，
##    但好感度、存档、剧情状态都还在。删节点再重建会把好感刷丢。

## 一天的起点小时
const DAY_START_HOUR := 6
## 一季天数（和 GameClock.DAYS_PER_SEASON 一致；这里写死是为了让本文件能脱离 autoload 测）
const DAYS_PER_SEASON := 28

## 分钟 → 连续小时（6.0 .. 26.0）
static func hour_of(minutes: int) -> float:
	return float(DAY_START_HOUR) + float(minutes) / 60.0

## 本季第几天（1..28）：存档里的 day 是全局天数，日程表按「本季第几天」算
static func day_of_season(day: int) -> int:
	return posmod(day - 1, DAYS_PER_SEASON) + 1

## 找出现在生效的那一行日程。没有匹配 → 返回 {}（调用方当「不在场」处理）
##
## 匹配顺序 = CSV 行序，**先匹配先赢**：
##   苏 的第一行带 days=7,14,21，第二行是全天兜底 —— 顺序反了苏就永远不出现。
static func slot_for(npc_id: StringName, minutes: int, season_day: int) -> Dictionary:
	var h := hour_of(minutes)
	for slot in NpcDB.schedule_of(npc_id):
		var days: Array = slot.get("days", [])
		if not days.is_empty() and not days.has(season_day):
			continue
		if h >= float(slot["from"]) and h < float(slot["to"]):
			return slot
	return {}

## 这一刻他在不在场上
static func visible_at(npc_id: StringName, minutes: int, season_day: int) -> bool:
	var s := slot_for(npc_id, minutes, season_day)
	return not s.is_empty() and bool(s["visible"])

## 位置（不在场时返回 `fallback`，通常是家 / 上次位置）
static func pos_at(npc_id: StringName, minutes: int, season_day: int,
		fallback: Vector2 = Vector2.ZERO) -> Vector2:
	var s := slot_for(npc_id, minutes, season_day)
	if s.is_empty():
		return fallback
	return Vector2(float(s["x"]), float(s["y"]))

## 正在干什么（"看店" / "打铁" / ...）；不在场返回 "不在"
static func action_at(npc_id: StringName, minutes: int, season_day: int) -> String:
	var s := slot_for(npc_id, minutes, season_day)
	if s.is_empty():
		return "不在"
	return str(s["action"])

## 这一行日程是不是整天都在（给测试断言「阿海只上半天班」用）
static func coverage_hours(npc_id: StringName) -> int:
	var total := 0
	for slot in NpcDB.schedule_of(npc_id):
		if bool(slot["visible"]):
			total += int(slot["to"]) - int(slot["from"])
	return total
