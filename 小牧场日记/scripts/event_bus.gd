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

# ---------------- 模块 6 ----------------

## 请求扩建某种棚舍（畜舍 / 禽舍 / 蜂箱）。建筑节点只发这个，
## 「够不够钱、升到几级」由 main 判断（和繁殖棚同一套写法）。
signal housing_upgrade_requested(housing_id: StringName)

## 棚舍升级完成（housing_id, 新等级）
signal housing_upgraded(housing_id: StringName, level: int)

# ---------------- 模块 7 ----------------

## 工具升级完成（&"hoe" / &"can" / &"bag", 新等级）
signal tool_upgraded(tool: StringName, level: int)

## 背包槽位布局变化（拖拽 / 合并 / 增删后）—— 背包 UI 订阅它重绘
signal inventory_slots_changed()

# ---------------- 模块 9（建造与牧场扩建）----------------

## 玩家按 E 点了某栋建筑（传它占地的锚点格）—— 建筑节点不自己扣钱，交给 main
signal building_interacted(cell: Vector2i)

## 建筑落成（def_id, 锚点格）
signal building_placed(def_id: StringName, cell: Vector2i)

## 建筑被拆（def_id, 锚点格, 返还金币, 返还木材）
signal building_removed(def_id: StringName, cell: Vector2i, refund_gold: int, refund_wood: int)

## 牧场扩建到新阶段（阶段序号）
signal stage_advanced(stage: int)

## 建造模式开关。玩家工具键在建造模式下要让位给「选建筑 / 放置 / 拆除」，
## 所以 player.gd 也认这个开关（和 ui_modal 同一个思路：全局状态，不是谁给谁发消息）。
var build_mode: bool = false

func set_build_mode(on: bool) -> void:
	build_mode = on

# ---------------- 模块 10（NPC 与剧情）----------------

## 玩家和某位村民说话（npc_id）
signal npc_interacted(npc_id: StringName)

## 玩家要把手里（背包里）的东西送给某位村民
signal npc_gift_requested(npc_id: StringName)

## 好感度变化（npc_id, 新心数, 实际加点）—— 负数是送错礼
signal npc_hearts_changed(npc_id: StringName, hearts: int, delta: int)

## 好感解锁（npc_id, 心数门槛, kind, id, 文案）
signal npc_unlocked(npc_id: StringName, hearts: int, kind: StringName, id: StringName, text: String)

## 某段剧情开始播（节点 id, 主线）
signal story_node_started(node_id: StringName, quest: StringName)

## 某段剧情播完（节点 id）
signal story_node_done(node_id: StringName)

## 触发结局（节点 id：ending_* / heart_of_ranch）
signal story_ending(node_id: StringName)

# ---------------- 模块 11（存档与场景管理）----------------

## 房间里某个可交互物被用（prop_id, action：save / shop / bed / machine / info）
signal room_prop_used(prop_id: StringName, action: StringName)

# 换场完成的信号在 SceneRouter 上（SceneRouter.scene_entered），不要在这里再造一个：
# 模块 11 曾经留过一个同名死信号，结果音频系统连错了地方、进屋不换 BGM。

# ---------------- 附属模块 1（全局音频与氛围）----------------
## 音频系统只订阅这些**已经在发生的玩法事件**，不反过来改玩法。
## 这样「加音效」= 在一个地方订阅，不用去每个系统里埋 AudioManager 调用。

## 金币变化（delta 正为入账、负为花费；total 是变化后的余额）
## 由 GameState.add_gold / spend_gold 广播 —— 那里是金币唯一的出入口。
signal gold_changed(delta: int, total: int)

## 动物叫了一声（species 是物种 id，pos 是世界坐标）—— 只有镜头附近的动物才会发
signal animal_vocalized(species: StringName, pos: Vector2)

## 玩家落地走了一步（世界坐标）—— 具体踩的是草/泥/木板由地表查询决定
signal player_stepped(world_pos: Vector2)

