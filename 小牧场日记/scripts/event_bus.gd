extends Node
## 全局信号总线 —— 零耦合通信（GDD §10.2）
##
## 规则：任何系统想通知别人，往这里发信号。
##       任何系统都不要持有别人的引用。加系统 = 加信号，不改旧代码。

## 每推进一个 tick（10 游戏分钟）
signal tick_advanced(day_minutes: int)

## 时段切换（清晨 / 白天 / 黄昏 / 夜晚）
signal phase_changed(old_phase: int, new_phase: int)

## 跨日
signal day_advanced(day: int, season: int, year: int)

## 换季
signal season_changed(season: int)

## 玩家切换农具
signal tool_changed(tool: int)

## 动物事件（产出 / 生病 / 饥饿），由 Herd.advance_day 汇总后广播
signal animal_events(events: Array)

## 玩家与动物互动完成
signal animal_interacted(uid: StringName, action: String)
