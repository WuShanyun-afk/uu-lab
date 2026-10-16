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

## 2:00 强制入睡 —— 跨日的那一瞬间（GameClock._roll_day 开头广播）
signal forced_sleep()

## 天气变化（今日天气, 昨日天气）—— 数值见 WeatherSystem.Weather
signal weather_changed(today: int, previous: int)

## 天气效果已派发（天气, 效果表 Dictionary）—— 农场 / 动物 / 音效各自订阅
signal weather_effects_applied(weather: int, effects: Dictionary)

## 玩家切换农具
signal tool_changed(tool: int)

## 玩家切换种子（模块 3）
signal seed_changed(seed_id: StringName)

## 动物事件（产出 / 生病 / 饥饿），由 Herd.advance_day 汇总后广播
signal animal_events(events: Array)

## 玩家与动物互动完成
signal animal_interacted(uid: StringName, action: String)

## 请求打开某个商店（模块 4）—— 可交互物只发这个，怎么渲染是 UI 的事
## shop_id: &"seed" 种子商店 / &"animal" 动物商店
signal shop_requested(shop_id: StringName)

## 商店成交（由 main 写入数据后广播，UI / 音效订阅）
signal shop_purchased(shop_id: StringName, entry_id: StringName, price: int)

## 小游戏（挤奶 / 剪毛节奏条）结束：等级 + 分数
signal minigame_finished(grade: int, score: float)

## UI 模态开关（商店 / 小游戏打开时 = true）
## 玩家只认这一个开关，不需要知道到底是谁把 UI 弹出来的（零耦合）。
signal ui_modal_changed(open: bool)

var ui_modal: bool = false

func set_ui_modal(open: bool) -> void:
	if ui_modal == open:
		return
	ui_modal = open
	ui_modal_changed.emit(open)

## 世界交互产生的文字（告示牌 / 出货箱 / 未来的 NPC 对话）
## —— 可交互物只管发这个信号，怎么显示是 UI 的事（零耦合）
signal world_message(text: String)

# ---------------- 模块 5 ----------------

## 请求弹一段对话（觉醒 / 剧情）。DialogueUI 订阅它，谁都能发。
## lines 是逐句推进的台词数组，color 是立绘色块（零素材）
signal dialogue_requested(speaker: String, lines: Array, color: Color)

## 某只动物刚刚觉醒（好感满 10 心）
signal animal_awakened(uid: StringName, species: StringName)

## 全部物种觉醒 → 秘密花园解锁
signal garden_unlocked()

## 玩家穿过传送门（dest: &"garden" / &"farm"）—— 传送本身由 main 执行
signal portal_used(dest: StringName)

## 建筑落成（模块 5：繁殖棚）
signal building_built(building_id: StringName)

