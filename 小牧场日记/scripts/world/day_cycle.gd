extends Node
## 一天怎么结束（模块 12 需求 5）—— autoload: DayCycle
##
## 时间系统（GameClock）只管「分钟走到 2:00 就把日子 +1」，
## 但**玩法上的一天**有两件事它管不了：
##   ① 玩家主动睡觉 → 立刻跳到次日清晨（并自动存档）
##   ② 超过 2:00 没睡 → 强制昏倒 → 扣钱 + 次日体力差（现在是扣钱 + 提示条）
##
## 为什么做成 autoload 而不是塞进 main：
##   玩家在**屋内**睡觉时 main 根本不在场景树里（模块 11 的 change_scene 会把牧场 free 掉）。
##   惩罚 / 睡觉这类「跨场景都该生效」的规则必须挂在一直活着的地方。
##
## ⚠️ 睡觉推进天数后，牧场那边要「补课」：
##    农田长一天、动物结算一天。但牧场不在场时没人跑 _on_day。
##    解法：main 回场时比较「存档里的天数」和「当前 GameClock.day」，
##    差几天就补几天（见 main._catch_up_days）。本文件不碰农场数据。

## 昏倒罚款（金币，不够就扣到 0）
const COLLAPSE_FEE := 120
## 昏倒后次日开局时间推后（分钟；0 = 从 6:00 正常起）
const COLLAPSE_DELAY := 120

## 最近一次睡觉/昏倒的摘要（提示条 + 测试断言用）
var last_message: String = ""

func _ready() -> void:
	EventBus.forced_sleep.connect(_on_forced_sleep)
	EventBus.day_advanced.connect(_on_day_advanced)

## 跨日：推进住宅升级工地（模块 12 需求 3）
## 为什么放在 autoload 里：玩家在**屋内**睡觉时 main 不在场景树里，
## 但住宅升级必须在任何场景都能推进。
func _on_day_advanced(_d: int, _s: int, _y: int) -> void:
	if GameState.house_upgrade_days <= 0:
		return
	GameState.house_upgrade_days -= 1
	if GameState.house_upgrade_days > 0:
		return
	var target := GameState.house_upgrade_target
	GameState.house_upgrade_target = 0
	if target <= 0:
		return
	GameState.set_house_level(target)
	last_message = "住宅升级完成 · Lv%d「%s」· 解锁：%s" % [target,
		HouseDB.name_of(target), HouseDB.unlock_of(target)]
	EventBus.world_message.emit(last_message)

## 2:00 还没睡 → 昏倒
func _on_forced_sleep() -> void:
	var fee := mini(COLLAPSE_FEE, GameState.gold)
	if fee > 0:
		GameState.spend_gold(fee)
	GameClock.minutes = COLLAPSE_DELAY          # 昏倒的人起得晚
	GameClock.phase = GameClock.phase_at(GameClock.minutes)
	last_message = "不知不觉在田里睡着了……医药费 -%dG" % fee
	EventBus.world_message.emit(last_message)

## 主动睡觉：跳到次日清晨。返回新的天数。
## ⚠️ 只负责「时间」——存档由调用方（屋内床 / main）负责，因为存档需要场景上下文。
func sleep_to_next_day() -> int:
	GameClock.sleep_next_day()
	last_message = "睡了一觉 · 第 %d 天 %s" % [GameClock.day, GameClock.clock_text()]
	EventBus.world_message.emit(last_message)
	return GameClock.day

## 现在能不能睡（白天睡觉不拦，但给个提示文案用）
func sleep_advice() -> String:
	var h := GameClock.hour()
	if h >= 20 or h < 2:
		return "夜里了，睡吧"
	return "才 %d 点，现在睡会浪费一天" % h
