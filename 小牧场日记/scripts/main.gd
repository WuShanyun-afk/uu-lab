extends Node2D
## 里程碑 1 + 2 + 3 + 模块 2 / 3 / 4 / 5 主场景
## 真地块素材 + 昼夜光照 + 季节 + 天气 + 农场 + 动物 + 商店 + 挤奶小游戏 + HUD
## + 觉醒 / 成长 / 生病 / 繁殖 / 秘密花园
##
## 地面（草地/牧场/秘密花园）由 World/GroundLayer（TileMapLayer + ground_tileset.png）负责，
## 牧场木栅栏由 World/WorldCollision 提供**真实碰撞**、本节点的 _draw_pen() 只负责画
## 同一组矩形（WorldConfig 是唯一数据源，所以画面和碰撞永远一致）。
##
## 时间/天气的**规则**不在这里：GameClock 管时钟、WeatherSystem 管掷骰与效果表。
## 本节点只做一件事——把「今天的效果表」翻译成对农场/动物的实际操作。
##
## 模块 4 的两条链路：
##   ① 商店：Interactable 只发 EventBus.shop_requested → 这里把「货架」拼出来交给 ShopUI
##   ② 挤奶/剪毛：这里起 MinigameUI，规则全在 RhythmBar（纯逻辑，可 headless 断言）
##
## 模块 5 的四条链路：
##   ③ 觉醒：Herd.pending_awakenings() → EventBus.dialogue_requested（台词来自 Awakening 表）
##   ④ 治病：空手对着生病的动物按 E → 消耗药剂 → AnimalState.cure()
##   ⑤ 繁殖：繁殖棚只发 shop_requested(&"breed")，这里判断「盖房 / 选父母」，规则在 Breeding
##   ⑥ 花园：Herd.all_species_awakened() → 解锁 → EventBus.portal_used 传送 + 换相机 limit
##
## 模块 6 的两条链路：
##   ⑦ 棚舍：三栋 HousingBarn 只发 housing_upgrade_requested → 这里扣钱扣木材升等级；
##          容量规则全在 Housing（纯逻辑），动物按 housing 列自动分区活动
##   ⑧ 换装：AnimalNode 自己按 res://assets/sprites/animals/<species>_32.png 找素材，
##          有就画真图、没有就退回 _draw() 占位 —— 本文件一行都不用改
##
## 模块 7 的五条链路（经济与背包）：
##   ⑨ 背包：GameState 真槽位（40/48/56 格）→ InventoryUI 网格 + 拖拽；
##          「使用」的语义在本文件（种子 = 换当前种子），UI 只发 index
##   ⑩ 商店：ToolShop 发 shop_requested(&"tool") → 这里拼升级货架；
##          杂货铺按 T 切成 SELL 模式（sell_requested），成交在 _on_sell
##   ⑪ 订单：OrderPost 发 shop_requested(&"order") → OrderBoard 纯逻辑出单，
##          这里只负责「扣物品 / 加钱 / 广播」
##   ⑫ 加工：CraftWorkshop 发 shop_requested(&"craft") → Processor 纯逻辑跑槽位，
##          tick_advanced 里按游戏分钟推进
##   ⑬ 行情：出货箱 / 订单 / 背包详情统一走 Market.price()，四因子在那边算完

## 挤奶黄金窗口的兜底值（真值来自 animals.csv 的 produce_window 列）
const MILK_WINDOW_MINUTES := 180

const SHOP_SEED := &"seed"
const SHOP_ANIMAL := &"animal"
const SHOP_SUPPLY := &"supply"     ## 模块 5：杂货铺（饲料 / 药剂 / 木材）
const SHOP_BREED := &"breed"       ## 模块 5：繁殖棚（盖房 or 选父母）
const SHOP_TOOL := &"tool"         ## 模块 7：工具铺（锄头 / 洒水壶 / 背包升级）
const SHOP_ORDER := &"order"       ## 模块 7：订单板（NPC 委托）
const SHOP_CRAFT := &"craft"       ## 模块 7：加工坊（放料 / 取货）

## 杂货铺卖的东西（价格一律来自 products.csv）
const SUPPLY_ITEMS: Array[StringName] = [&"feed", &"medicine", &"wood"]

## 药剂 / 木材的 item id（别写成裸字符串散落各处）
const MEDICINE := &"medicine"
const WOOD := &"wood"

## 新动物进牧场的落点（模块 6 起不再写死一张表）：
##   动物按 animals.csv 的 housing 列落进自己的子栏，
##   网格点由 `_zone_slots()` 从 WorldConfig.PEN_ZONES 现算 —— 改分栏只改 WorldConfig。

@onready var _player: Player = $World/YSortRoot/Player
@onready var _light: CanvasModulate = $CanvasModulate
@onready var _hud: Label = $UI/HUD
@onready var _tip: Label = $UI/Tip
@onready var _prompt: Label = $UI/Prompt
@onready var _toolbar: Label = $UI/ToolBar
@onready var _shop: ShopUI = $UI/ShopPanel
@onready var _inv: InventoryUI = $UI/InventoryPanel
@onready var _minigame: MinigameUI = $UI/Minigame
@onready var _dialogue: DialogueUI = $UI/Dialogue
@onready var _farm_layer: Node2D = $World/FarmLayer
@onready var _animal_layer: AnimalLayer = $World/YSortRoot/AnimalLayer
@onready var _ground: GroundLayer = $World/GroundLayer
@onready var _gate: GardenGate = $World/GardenGate
@onready var _shed: BreedingShed = $World/BreedingShed
@onready var _decor: GardenDecor = $World/GardenDecor
@onready var _order_post: OrderPost = $World/OrderPost
@onready var _workshop: CraftWorkshop = $World/CraftWorkshop

var _grid: FarmGrid
var _herd: Herd
var _last_tip := ""
var _tip_until := 0.0
## 商店里正在卖什么（种子 / 动物 / 杂货 / 繁殖 / 工具 / 订单 / 加工）—— 成交后按同一份货架刷新
var _shop_kind: StringName = &""
## 正在等节奏条结果的那只动物
var _pending_animal: AnimalState = null
## 繁殖棚里已经选好的父母（0 / 1 / 2 只）
var _breed_picks: Array[StringName] = []
## 玩家现在是不是在秘密花园里（决定相机 limit）
var _zone_garden := false
## 灾害判定专用（栅栏损坏 / 雷击烧作物）—— 和玩法随机分开，避免污染主随机流
var _storm_rng := RandomNumberGenerator.new()
## 模块 7：订单板（纯逻辑，随本局存活；将来存档时整坨序列化）
var _orders := OrderBoard.new(20261101)
## 模块 7：加工坊（纯逻辑，槽位 2 个；Lv2/Lv3 的 4/6 槽接口已在 Processor 里）
var _proc := Processor.new(1)

func _ready() -> void:
	_storm_rng.seed = 20261022
	_grid = FarmGrid.new()
	_grid.season = GameClock.season     # 模块 3：季节门禁（春天种不了南瓜）
	_farm_layer.grid = _grid
	_give_starter_items()

	_herd = Herd.new(20261015)
	_init_barns()                # 模块 6：开局三栋棚舍都是 Lv1（牧场遗产，不是白手起家）
	_setup_animals()
	_animal_layer.herd = _herd
	_animal_layer.rebuild()

	_player.tool_used.connect(_on_tool_used)
	_player.prompt_changed.connect(_on_prompt)
	EventBus.tick_advanced.connect(_on_tick)
	EventBus.phase_changed.connect(_on_phase)
	EventBus.day_advanced.connect(_on_day)
	EventBus.season_changed.connect(_on_season)
	EventBus.tool_changed.connect(_on_tool_changed)
	EventBus.seed_changed.connect(_on_seed_changed)
	EventBus.world_message.connect(_say)
	EventBus.shop_requested.connect(_open_shop)
	EventBus.portal_used.connect(_on_portal)                 # 模块 5
	EventBus.dialogue_requested.connect(_on_dialogue)        # 模块 5
	EventBus.housing_upgrade_requested.connect(_on_housing_upgrade)   # 模块 6
	_shop.buy_requested.connect(_on_buy)
	_shop.sell_requested.connect(_on_sell)          # 模块 7：回收（SELL 模式）
	_shop.mode_toggle_requested.connect(_on_mode_toggle)
	_inv.use_requested.connect(_on_inv_use)         # 模块 7：背包里「使用」
	_inv.drop_requested.connect(_on_inv_drop)       # 模块 7：背包里「丢弃」
	_minigame.finished.connect(_on_minigame_finished)
	_minigame.cancelled.connect(_on_minigame_cancelled)
	GameState.gold_changed.connect(_on_gold)
	GameState.inventory_changed.connect(_on_inventory)

	_ground.set_season_tint(GameClock.season)
	_refresh_light()
	_apply_camera_limits()
	_sync_garden()
	_refresh_barns()             # 模块 6：三栋棚舍的「住了几只」开局就填上
	_init_workshop()             # 模块 7：加工坊等级 + 节点状态
	_tick_orders()               # 模块 7：开局就刷 2 单（day 1 - (-999) >= 3）
	_refresh_hud()
	_refresh_toolbar()
	# 模块 8：有档就告诉玩家 F9 能续，没档就把键位一次性说清楚（只占 2.5 秒提示条）
	if SaveSystem.exists(SaveSystem.SLOT_QUICK) or SaveSystem.exists(SaveSystem.SLOT_AUTO):
		var slot := SaveSystem.SLOT_QUICK if SaveSystem.exists(SaveSystem.SLOT_QUICK) else SaveSystem.SLOT_AUTO
		var info := SaveSystem.info(slot)
		_say("检测到%s：第 %d 天 · F9 继续 · F5 存档" % [SaveSystem.slot_label(slot),
			int(info.get("day", 0))])
	else:
		_say("WASD 移动 · E 用工具/交互 · 1-7 换工具 · Tab 换种子 · I 背包 · F5 存/F9 读 · F11 全屏")

## 开局补给：
##   · 每季作物各 3 颗种子（模块 4 起种子是要消耗的背包物品，种子商店能补货）
##   · 两档肥料各一批（肥料商店属于经济模块）
##   · 20 份干草饲料 / 3 瓶药剂 / 10 根木材（模块 5：杂货铺都能补货）
func _give_starter_items() -> void:
	for id in CropDB.all_ids():
		var item := CropDB.seed_item(id)
		if GameState.count_item(item) == 0:
			GameState.add_item(item, 3)
	if GameState.count_item(Fertilizer.item_id(Fertilizer.Level.BASIC)) == 0:
		GameState.add_item(Fertilizer.item_id(Fertilizer.Level.BASIC), 30)
	if GameState.count_item(Fertilizer.item_id(Fertilizer.Level.HIGH)) == 0:
		GameState.add_item(Fertilizer.item_id(Fertilizer.Level.HIGH), 10)
	if GameState.count_item(&"feed") == 0:
		GameState.add_item(&"feed", 20)
	if GameState.count_item(MEDICINE) == 0:
		GameState.add_item(MEDICINE, 3)
	if GameState.count_item(WOOD) == 0:
		GameState.add_item(WOOD, 10)

func _process(_delta: float) -> void:
	_refresh_light()
	_check_awakenings()          # 模块 5：觉醒要**立刻**弹对话，不能等到跨日
	_update_zone()               # 模块 5：进出花园 → 换相机 limit
	var now := Time.get_ticks_msec() / 1000.0
	if _tip_until > 0.0 and now > _tip_until:
		_tip_until = 0.0
		_tip.text = ""
	if _tip_until == 0.0:
		_show_hint()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			_toggle_fullscreen()
		elif event.keycode == KEY_F5:
			_save_game(SaveSystem.SLOT_QUICK)        # 模块 8
		elif event.keycode == KEY_F9:
			_load_latest()                            # 模块 8
		elif event.keycode == KEY_I:
			# 背包自己会吃掉「关」的那一次（它在树里更靠后，先收到 unhandled_input），
			# 所以这里只负责「开」。商店 / 对话弹着的时候不许开背包。
			if not EventBus.ui_modal:
				_inv.open()

func _toggle_fullscreen() -> void:
	var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

# ---------------- 动物初始化 ----------------

func _setup_animals() -> void:
	# ⚠️ 第 0 只必须是奶牛：test_weather.gd 用 _herd.animals[0] 断言「雨天留棚 +3」
	# ⚠️ 坐标全部落在 WorldConfig.PEN_ZONES 各自的子栏里（模块 6）：
	#    barn 516..584 / coop 588..656 / hive 660..732，y 120..250。
	#    摆错栏的话开局就会有动物站在别人的棚舍底下，_clamp_animals_to_zones 会在跨日拉回来。
	var cow1 := _herd.add(&"cow", 300, Vector2(536, 158))
	_herd.add(&"cow", 150, Vector2(566, 200))
	var c1 := _herd.add(&"chicken", 250, Vector2(604, 152))
	var c2 := _herd.add(&"chicken", 400, Vector2(638, 190))
	_herd.add(&"chicken", 100, Vector2(602, 232))
	# 模块 4 的展示阵容：羊（剪毛周期 3 天）、鸭、蜜蜂（采蜜周期 4 天）
	_herd.add(&"sheep", 220, Vector2(540, 236))
	_herd.add(&"duck", 180, Vector2(638, 228))
	_herd.add(&"bee", 300, Vector2(698, 168))
	for a in _herd.animals:
		a.debug_grow_adult()
	# 开局先给一次产出，方便立刻试「挤奶 / 捡蛋 / 剪毛 / 采蜜」
	if cow1 != null:
		cow1.debug_ready_produce()
	if c1 != null:
		c1.debug_ready_produce()
	if c2 != null:
		c2.debug_ready_produce()
	for a in _herd.animals:
		if a.species != &"cow" and a.species != &"chicken":
			a.debug_ready_produce()
	# 模块 5：再放一只**幼年**火鸡 —— 开局就能看见「幼年 → 成年」的成长过程。
	# 成年个体要走繁殖棚生崽，不摆这么一只的话，成长系统头几天完全看不见。
	# ⚠️ 必须加在**最后**：模块 4 的测试按索引取动物（animals[5] = 绵羊、animals[7] = 蜜蜂），
	#    往中间插一只会把那两个索引顶偏。
	# 3 心而不是 0 心：0 心 + 连续漏喂会直接走生病分支，开局就病一只太劝退。
	_herd.add(&"turkey", 300, Vector2(620, 248))

# ---------------- 工具 ----------------

func _on_tool_used(tool: int, cell: Vector2i) -> void:
	# 工具 4 / 5 走动物交互
	if tool == Player.Tool.FEED or tool == Player.Tool.HAND:
		_handle_animal(tool)
		return

	if not _grid.in_bounds(cell):
		return

	# 成熟优先收获（GDD §11 里程碑 2：可收获入背包）
	if _grid.is_mature(cell):
		_harvest(cell)
		return

	match tool:
		Player.Tool.HOE:
			_hoe(cell)
		Player.Tool.CAN:
			_water(cell)
		Player.Tool.SEED:
			_plant(cell)
		Player.Tool.FERT:
			_fertilize(cell, Fertilizer.Level.BASIC)
		Player.Tool.FERT_HIGH:
			_fertilize(cell, Fertilizer.Level.HIGH)

# ---------------- 工具作用范围（模块 7 需求 2：工具升级）----------------

## 一次工具作用到哪些格子。等级来自 GameState（1/2/3），数值见 data/upgrades.csv。
##   Lv1 → 1 格
##   Lv2 → 3 格直线（沿当前朝向往前推）
##   Lv3 → 以目标格为中心的 3×3
## 为什么把「范围」和「锄地 / 浇水」分开：范围是纯几何，能单独断言，
## 而 _hoe / _water 只管对每个格子调 FarmGrid。
func _tool_cells(cell: Vector2i, lv: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if lv <= 1:
		out.append(cell)
		return out
	if lv == 2:
		var d := _facing_step()
		for i in range(3):
			out.append(cell + d * i)
		return out
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			out.append(cell + Vector2i(dx, dy))
	return out

func _facing_step() -> Vector2i:
	match _player.facing:
		"up":
			return Vector2i(0, -1)
		"left":
			return Vector2i(-1, 0)
		"right":
			return Vector2i(1, 0)
	return Vector2i(0, 1)

# ---------------- 锄地（模块 3：顺带清理枯死作物；模块 7：范围随等级）----------------

func _hoe(cell: Vector2i) -> void:
	var cells := _tool_cells(cell, GameState.tool_level(&"hoe"))
	var tilled := 0
	var cleaned := 0
	var already := 0
	for c in cells:
		if not _grid.in_bounds(c):
			continue
		var t := _grid.tile_at(c)
		var was_dead := t != null and t.dead
		if _grid.till(c):
			tilled += 1
			if was_dead:
				cleaned += 1
			if WeatherSystem.is_wet():
				_grid.water(c)      # 雨天锄完就是湿的
		elif t != null and t.tilled:
			already += 1
	if tilled > 0:
		_player.play_hoe()
		if cleaned > 0:
			_say("清理枯死作物 %d 格，又能种了" % cleaned)
		else:
			_say("锄地 %d 格" % tilled if tilled > 1 else "锄地")
		_farm_layer.refresh()
		_refresh_toolbar()
	elif already > 0:
		_say("这块地已经锄过了" if already == 1 else "这几格都锄过了")

# ---------------- 浇水（模块 7：范围随等级）----------------

func _water(cell: Vector2i) -> void:
	var cells := _tool_cells(cell, GameState.tool_level(&"can"))
	var n := 0
	for c in cells:
		if not _grid.in_bounds(c):
			continue
		if _grid.water(c):
			n += 1
	if n > 0:
		_player.play_watering()
		_say("浇水 %d 格" % n if n > 1 else "浇水")
		_farm_layer.refresh()
	elif WeatherSystem.is_wet():
		_say("雨天不用浇水，地是湿的")
	else:
		_say("这格还没锄（先用 1 锄头）")

# ---------------- 播种（模块 3 需求 1 / 3 + 模块 4 种子消耗）----------------

func _plant(cell: Vector2i) -> void:
	var id := _player.selected_seed
	var c: CropData = CropDB.get_crop(id)
	if c == null:
		_say("没选种子（Tab 换种子）")
		return
	# dry_run = true：先问「种得下吗」，不写地块
	match _grid.plant_reason(cell, id, true):
		FarmGrid.OK:
			var need := CropDB.seed_item(id)
			if GameState.count_item(need) <= 0:
				_say("%s 种子用完了 —— 种子商店（棚子）能补货" % c.display_name)
				return
			_grid.plant(cell, id)
			GameState.remove_item(need, 1)
			if WeatherSystem.is_wet():
				_grid.water(cell)      # 雨天播种即浇水
			_say("种下 %s（%d 天成熟 · 单株卖 %dG · 种子剩 %d）" % [
				c.display_name, _grid.effective_grow_days(cell), c.sell_price,
				GameState.count_item(need)])
			_farm_layer.refresh()
			_refresh_toolbar()
		FarmGrid.WRONG_SEASON:
			if not SeasonEffects.can_plant_outdoor(GameClock.season):
				_say("冬天土地冻住了，只有耐寒作物种得下去（Tab 换种子）")
			else:
				_say("%s 是%s季作物，现在%s季种不活（Tab 换种子）" % [
					c.display_name, c.season_name(), GameClock.season_name()])
		FarmGrid.NOT_TILLED:
			_say("先用锄头（1）把这块地翻开")
		FarmGrid.OCCUPIED:
			_say("这格已经有作物了")

# ---------------- 施肥（模块 3 需求 5）----------------

func _fertilize(cell: Vector2i, level: int) -> void:
	var item := Fertilizer.item_id(level)
	if GameState.count_item(item) <= 0:
		_say("%s 用完了（%dG/袋，种子商店有卖）" % [
			Fertilizer.level_name(level), Fertilizer.price(level)])
		return
	match _grid.fertilize_reason(cell, level):
		FarmGrid.OK:
			_grid.fertilize(cell, level)
			GameState.remove_item(item, 1)
			_player.play_fertilize()
			var t := _grid.tile_at(cell)
			var c: CropData = CropDB.get_crop(t.crop_id)
			var aff := c.fertilize if c != null else 1
			var ch := Fertilizer.quality_chance(aff, level)
			var ch_txt := "优质率 %d%%" % int(Fertilizer.quality_total(aff, level) * 100.0)
			if float(ch[1]) > 0.0:
				ch_txt += "（金星 %d%%）" % int(float(ch[1]) * 100.0)
			if c != null:
				var d := Fertilizer.growth_delta(c.fertilize, level)
				_say("施%s：%s 成熟天数 %d 天%s · %s" % [
					Fertilizer.level_name(level), c.display_name,
					_grid.effective_grow_days(cell),
					"" if d == 0 else "（+%d 天）" % d, ch_txt])
			else:
				_say("施%s，肥力留在土里 · %s" % [Fertilizer.level_name(level), ch_txt])
			_farm_layer.refresh()
			_refresh_toolbar()
		FarmGrid.NOT_TILLED:
			_say("肥料要撒在耕地上（先用锄头 1）")
		FarmGrid.ALREADY_BETTER:
			_say("这格已经施过同级或更好的肥了")

# ---------------- 收获（模块 3 需求 4：品质进背包）----------------

func _harvest(cell: Vector2i) -> void:
	var out := _grid.harvest(cell)
	if out.is_empty():
		return
	var c: CropData = CropDB.get_crop(out["id"])
	var q := int(out["quality"])
	GameState.add_item(out["item"], int(out["count"]))
	var extra := ""
	if c.regrow_days > 0:
		extra = "（%d 天后再生）" % c.regrow_days
	_say("收获 %s%s ×%d%s" % [
		CropQuality.label(c.display_name, q), "" if q == 0 else " ★", int(out["count"]), extra])
	_farm_layer.refresh()
	_refresh_hud()

func _quality_name(q: int) -> String:
	return CropQuality.name(q)

# ---------------- 动物交互（里程碑 3 + 模块 4）----------------

func _handle_animal(tool: int) -> void:
	var a := _herd.nearest(_player.interact_point(), 46.0)
	if a == null:
		_say("附近没有动物（牧场在右边围栏里）")
		return
	var d := a.data()

	if tool == Player.Tool.FEED:
		_feed_animal(a, d)
	else:
		_hand_animal(a, d)

	_animal_layer.refresh()
	_refresh_hud()
	_check_awakenings()     # 模块 5：喂到 10 心要当场觉醒（不等跨日）
	EventBus.animal_interacted.emit(a.uid, "feed" if tool == Player.Tool.FEED else "hand")

func _feed_animal(a: AnimalState, d: AnimalData) -> void:
	if not a.is_hungry():
		_say("%s 已经吃饱了" % d.display_name)
		return
	var need := int(WeatherSystem.today_effects()["feed_mult"])
	if GameState.count_item(&"feed") < need:
		_say("饲料不够了（雪天要 %d 份）" % need if need > 1 else "没有干草饲料了")
		return
	GameState.remove_item(&"feed", need)
	a.feed()
	_say("喂了%s，好感 +%d（%s）" % [d.display_name, AnimalState.FEED_AFFECTION, a.heart_label()])

## 空手（工具 5）：
##   ① 生病 → 用药剂治（模块 5 需求 3；没药就提示去哪买）
##   ② 有产出且窗口允许 → 挤奶 / 剪毛走节奏条，捡拾 / 采蜜直接收
##   ③ 没产出 → 刷毛 → 抱抱 → 抚摸（按物种能力依次降级）
func _hand_animal(a: AnimalState, d: AnimalData) -> void:
	if a.sick:
		_try_cure(a, d)
		return

	var in_window := d.produce_window <= 0 or GameClock.minutes < d.produce_window

	if a.product_ready and a.is_producing():
		if not in_window:
			_say("%s：%s只在 %s 能收" % [d.display_name, d.action_name(), d.window_text()])
			return
		if d.needs_minigame():
			_start_minigame(a, d)
		else:
			_deliver(a, d, -1)
		return

	if a.brush():
		_say("给%s刷毛，好感 +%d（%s）" % [d.display_name, AnimalState.BRUSH_AFFECTION, a.heart_label()])
	elif a.hug():
		_say("抱了抱%s，好感 +%d（%s）" % [d.display_name, AnimalState.HUG_AFFECTION, a.heart_label()])
	elif a.pet():
		_say("抚摸%s，好感 +%d（%s）" % [d.display_name, AnimalState.PET_AFFECTION, a.heart_label()])
	elif d.pet_limit <= 0 and not d.brushable and not d.is_poultry():
		_say("%s 只能喂食和收成，不太亲人" % d.display_name)
	else:
		_say("%s 今天不想被摸了" % d.display_name)

## 用药治疗（模块 5 需求 3）
func _try_cure(a: AnimalState, d: AnimalData) -> void:
	if GameState.count_item(MEDICINE) <= 0:
		_say("%s 病第 %d 天 —— 杂货铺买药剂，拖到第 %d 天就救不回来了" % [
			d.display_name, a.sick_days, AnimalState.SICK_DEATH_DAYS])
		return
	GameState.remove_item(MEDICINE, 1)
	a.cure()
	_say("给%s灌了药剂，它退烧了 · 好感 +%d（%s）· 药剂剩 %d" % [
		d.display_name, AnimalState.CURE_AFFECTION, a.heart_label(), GameState.count_item(MEDICINE)])

## 把产出真正写进背包。grade >= 0 时套节奏条结果（产量 / 品质）。
func _deliver(a: AnimalState, d: AnimalData, grade: int) -> void:
	var in_window := d.produce_window <= 0 or GameClock.minutes < d.produce_window
	var out := a.produce(in_window)
	if out.is_empty():
		return
	var pid: StringName = out["id"]
	var cnt := int(out["count"])
	var q := int(out["quality"])
	var extra := ""
	if grade >= 0:
		var res := RhythmBar.apply_result(grade, cnt, q)
		cnt = int(res["count"])
		q = int(res["quality"])
		extra = " · %s" % RhythmBar.GRADE_NAME[clampi(grade, 0, 3)]
	if d.timed_product:
		cnt = SeasonEffects.apply_milk_mult(cnt, GameClock.season, _storm_rng)
	var item := ProductDB.item_id(pid, q)
	GameState.add_item(item, cnt)
	_say("收 %s ×%d%s（%s）" % [ProductDB.display_name(item), cnt, extra, a.heart_label()])

# ---------------- 挤奶 / 剪毛节奏条（模块 4 需求 4）----------------

func _start_minigame(a: AnimalState, d: AnimalData) -> void:
	_pending_animal = a
	_minigame.start("%s · %s" % [d.display_name, d.action_name()])

func _on_minigame_finished(grade: int, _score: float) -> void:
	var a := _pending_animal
	_pending_animal = null
	if a == null:
		return
	_deliver(a, a.data(), grade)
	_animal_layer.refresh()
	_refresh_hud()

func _on_minigame_cancelled() -> void:
	_pending_animal = null
	_say("这次没挤，产出还在（再来一次）")

## 空手站在动物旁边时，底部提示当前动物的状态
func _show_hint() -> void:
	var a := _herd.nearest(_player.interact_point(), 46.0)
	if a == null:
		_tip.text = ""
		return
	var d := a.data()
	var st := "饱" if not a.is_hungry() else "饿"
	if a.sick:
		st = "生病 第 %d/%d 天 · 空手按 E 用药剂" % [a.sick_days, AnimalState.SICK_DEATH_DAYS]
	elif a.is_pregnant():
		st = "妊娠中 · 还剩 %d 天" % a.pregnant_days
	elif not a.is_adult():
		st = "幼年 · 还有 %d 天成年" % a.days_to_mature()
	elif a.product_ready:
		var ready := d.produce_window <= 0 or GameClock.minutes < d.produce_window
		st = "可%s" % d.action_name() if ready else "%s（%s）" % [d.action_name(), d.window_text()]
	elif a.awakened:
		st = "已觉醒 · %s" % Awakening.gift_name(a.species)
	_tip.text = "%s  %s  %s" % [a.display_label(), a.heart_label(), st]

# ---------------- 商店（模块 4 + 模块 5）----------------

func _open_shop(shop_id: StringName) -> void:
	if _shop.is_open() or _minigame.is_active() or _dialogue.is_open() or _inv.is_open():
		return
	_shop_kind = shop_id
	_breed_picks.clear()
	if shop_id == SHOP_SEED:
		_shop.open("种子商店 · %s季（买下即入背包）" % GameClock.season_name(), _seed_entries())
	elif shop_id == SHOP_ANIMAL:
		_shop.open("动物商店 · 买下直接放进牧场（成年）", _animal_entries())
	elif shop_id == SHOP_SUPPLY:
		_shop.open("杂货铺 · 饲料 / 药剂 / 木材（T 键切成回收模式）", _supply_entries())
	elif shop_id == SHOP_TOOL:
		_shop.open("工具铺 · 升级（%s）" % _tool_levels_text(), _tool_entries())
	elif shop_id == SHOP_ORDER:
		_open_order_panel()
	elif shop_id == SHOP_CRAFT:
		_open_craft_panel()
	elif shop_id == SHOP_BREED:
		# 繁殖棚一个信号两件事：没盖就盖，盖了就配
		if not GameState.has_flag(&"shed_built"):
			_try_build_shed()
			return
		_shop.open(_breed_title(), _breed_entries(), "↑↓ 选动物 · E 选中 · Esc 关掉")

## 货架 = 当季 6 种种子 + 两档肥料
func _seed_entries() -> Array:
	var out: Array = []
	for id in CropDB.of_season(GameClock.season):
		var c: CropData = CropDB.get_crop(id)
		var item := CropDB.seed_item(id)
		var afford := GameState.gold >= c.seed_price
		out.append({
			"id": item,
			"name": "%s种子" % c.display_name,
			"price": c.seed_price,
			"note": "%d天·卖%dG·需肥%s·有%d" % [
				c.grow_days, c.sell_price, ["低", "中", "高"][c.fertilize],
				GameState.count_item(item)],
			"enabled": afford,
			"reason": "钱不够" if not afford else "",
		})
	for lv in [Fertilizer.Level.BASIC, Fertilizer.Level.HIGH]:
		var item := Fertilizer.item_id(lv)
		var p := Fertilizer.price(lv)
		var afford := GameState.gold >= p
		out.append({
			"id": item,
			"name": Fertilizer.level_name(lv),
			"price": p,
			"note": "品质率 +%d%%·有%d" % [int(Fertilizer.quality_total(1, lv) * 100.0),
				GameState.count_item(item)],
			"enabled": afford,
			"reason": "钱不够" if not afford else "",
		})
	return out

## 货架 = AnimalDB 全表，按价格升序
## 模块 6：棚舍满了 / 没盖 → 这一行变灰并写明原因（别让玩家点了没反应）
func _animal_entries() -> Array:
	var out: Array = []
	var barns := GameState.barn_levels()
	for id in AnimalDB.ids_by_price():
		var a: AnimalData = AnimalDB.get_animal(id)
		var afford := GameState.gold >= a.price
		var room := Housing.can_house(id, _herd, barns)
		var h := Housing.housing_of(id)
		var note := "%s·%s·%s·成年%d天·有%d" % [
			a.housing_name(), a.action_name(), a.period_text(),
			a.mature_days, _herd.count_species(id)]
		if room != Housing.Reason.OK:
			note += "·%s %d/%d" % [HousingDB.name_of(h),
				Housing.count_in(_herd, h), Housing.capacity(barns, h)]
		var why := ""
		if not afford:
			why = "钱不够"
		elif room != Housing.Reason.OK:
			why = Housing.reason_text(room)
		out.append({
			"id": id,
			"name": a.display_name,
			"price": a.price,
			"note": note,
			"enabled": afford and room == Housing.Reason.OK,
			"reason": why,
		})
	return out

## 货架 = 杂货铺三件套（饲料 / 药剂 / 木材），价格来自 products.csv
func _supply_entries() -> Array:
	var out: Array = []
	for id in SUPPLY_ITEMS:
		var p := ProductDB.price(id)
		var afford := GameState.gold >= p
		out.append({
			"id": id,
			"name": ProductDB.display_name(id),
			"price": p,
			"note": "%s · 有 %d" % [_supply_note(id), GameState.count_item(id)],
			"enabled": afford,
			"reason": "钱不够" if not afford else "",
		})
	return out

func _supply_note(id: StringName) -> String:
	match id:
		&"feed":
			return "喂动物 · 繁殖一次要 %d 份" % Breeding.FEED_COST
		&"medicine":
			return "治生病动物（拖 %d 天会病逝）" % AnimalState.SICK_DEATH_DAYS
		&"wood":
			return "盖繁殖棚要 %d 根" % BuildingDB.material_count_of(BreedingShed.BUILDING_ID)
	return ""

# ============================================================================
# 模块 7 · 工具铺（需求 2）
# ============================================================================
#
# 货架 = data/upgrades.csv 全表。每行都是「某工具升到某级」，
# 已经拥有 / 买不起 / 缺材料就变灰并写明原因（同模块 6 的棚舍：别让玩家点了没反应）。

func _tool_levels_text() -> String:
	return "锄 Lv%d · 壶 Lv%d · 背包 %d 格" % [
		GameState.tool_level(&"hoe"), GameState.tool_level(&"can"),
		GameState.slot_capacity()]

func _tool_entries() -> Array:
	var out: Array = []
	for uid in ItemDB.upgrade_ids():
		var u := ItemDB.get_upgrade(uid)
		var tool: StringName = u["tool"]
		var cur := GameState.tool_level(tool)
		var lv := int(u["level"])
		var mat: StringName = u["material"]
		var need := int(u["material_count"])
		var have_mat := GameState.count_item(mat)
		var price := int(u["price"])
		var afford := GameState.gold >= price
		var ok_mat := have_mat >= need
		var owned := cur >= lv
		var why := ""
		if owned:
			why = "已拥有"
		elif not afford:
			why = "钱不够"
		elif not ok_mat:
			why = "缺 %s×%d" % [ItemDB.display_name(mat), need - have_mat]
		out.append({
			"id": uid,
			"name": str(u["name"]),
			"price": price,
			"note": "%s · 现在 Lv%d · 需 %s×%d" % [u["note"], cur,
				ItemDB.display_name(mat), need],
			"enabled": not owned and afford and ok_mat,
			"reason": why,
		})
	return out

## 买升级：先问「有没有更高级 / 钱够不够 / 材料够不够」，再一次性扣干净
func _buy_upgrade(uid: StringName) -> bool:
	var u := ItemDB.get_upgrade(uid)
	if u.is_empty():
		return false
	var tool: StringName = u["tool"]
	var lv := int(u["level"])
	var price := int(u["price"])
	var mat: StringName = u["material"]
	var need := int(u["material_count"])
	if GameState.tool_level(tool) >= lv:
		_say("%s 已经拥有了" % u["name"])
		return false
	if GameState.gold < price:
		_say("%s 要 %dG，还差 %dG" % [u["name"], price, price - GameState.gold])
		return false
	if GameState.count_item(mat) < need:
		_say("还缺 %s×%d（杂货铺有卖）" % [ItemDB.display_name(mat),
			need - GameState.count_item(mat)])
		return false
	GameState.spend_gold(price)
	GameState.remove_item(mat, need)
	GameState.set_tool_level(tool, lv)
	EventBus.tool_upgraded.emit(tool, lv)
	_say("%s 到手 · %s（-%dG %s×%d）" % [u["name"], u["note"], price,
		ItemDB.display_name(mat), need])
	_refresh_hud()
	_refresh_toolbar()
	return true

# ============================================================================
# 模块 7 · 订单板（需求 3）
# ============================================================================
#
# OrderBoard 是纯逻辑（出单 / 过期 / 交付判定），本文件只做三件副作用：
# 扣物品、加金币、广播。UI 复用 ShopUI（一张单 = 一行货架）。

func _open_order_panel() -> void:
	if _orders.active_count() <= 0:
		_say("订单板空着 —— 每 %d 天会有新的委托" % OrderBoard.REFRESH_DAYS)
		return
	_shop.open("订单板 · 已完成 %d 单（报酬 = 行情价 × 数量 × 1.5）" % _orders.completed,
		_order_entries(), "↑↓ 选单 · E 交付 · Esc 关掉")

func _order_entries() -> Array:
	var out: Array = []
	for o in _orders.active_orders():
		var chk := _orders.can_deliver(o, GameState.count_item)
		var ok := bool(chk["ok"])
		out.append({
			"id": StringName("order:%d" % int(o["id"])),
			"name": "%s 要 %s" % [o["npc"], ItemDB.display_name(o["item"])],
			"price": int(o["reward"]),
			"note": "×%d · 有 %d · %s" % [int(o["count"]),
				GameState.count_item(o["item"]),
				_orders.due_text(o, GameClock.day, GameClock.minutes)],
			"enabled": ok,
			"reason": "" if ok else str(chk.get("reason", "")),
		})
	return out

## entry id 形如 "order:3" → 找到那张单
func _find_order(entry_id: StringName) -> Dictionary:
	var s := str(entry_id)
	if not s.begins_with("order:"):
		return {}
	var oid := int(s.substr(6))
	for o in _orders.orders:
		if int(o["id"]) == oid:
			return o
	return {}

func _on_order_deliver(entry_id: StringName) -> void:
	var o := _find_order(entry_id)
	if o.is_empty():
		return
	var chk := _orders.can_deliver(o, GameState.count_item)
	if not bool(chk["ok"]):
		_say("交不了：%s" % chk["reason"])
		return
	var res := _orders.deliver(o)
	if res.is_empty():
		return
	GameState.remove_item(res["item"], int(res["count"]))
	GameState.add_gold(int(res["reward"]))
	_say("%s 收下 %s×%d · +%dG · 已完成 %d 单" % [res["npc"],
		ItemDB.display_name(res["item"]), int(res["count"]), int(res["reward"]),
		_orders.completed])
	if bool(res["famous"]) and not GameState.has_flag(&"famous"):
		GameState.set_flag(&"famous", true)
		EventBus.dialogue_requested.emit("村长", [
			"十单了。",
			"村里人现在提起牧场，说的都是你的名字。",
			"——「村中名人」，这称号你担得起。",
		], Color("#E8C05A"))
		_say("解锁成就「村中名人」（完成 %d 单）" % OrderBoard.FAMOUS_GOAL)
	_refresh_orders()
	if _shop.is_open() and _shop_kind == SHOP_ORDER:
		if _orders.active_count() <= 0:
			_shop.close()
		else:
			_shop.update_entries(_order_entries())
	_refresh_hud()

## 把订单状态灌进节点（节点不持有 OrderBoard）+ HUD 跟着刷新
func _refresh_orders() -> void:
	if _order_post != null:
		_order_post.active_count = _orders.active_count()
		_order_post.ready_now = _ready_order_count()
		_order_post.queue_redraw()

func _ready_order_count() -> int:
	var n := 0
	for o in _orders.active_orders():
		if bool(_orders.can_deliver(o, GameState.count_item)["ok"]):
			n += 1
	return n

# ============================================================================
# 模块 7 · 加工坊（需求 4）
# ============================================================================
#
# Processor 是纯逻辑（槽位 / 倒计时 / 取货），本文件负责：
# 放料时扣原料、取货时进背包、每 tick 推进时间、把状态灌进节点。
#
# ⚠️ 原料按**品质**分别列货架。背包里「金星牛奶」和「牛奶」是两个 item id，
#    只按基础 id 查会让金星牛奶做不了奶酪 —— 第一版就是这么错的。

func _init_workshop() -> void:
	_proc.set_level(1)
	_refresh_workshop()

func _refresh_workshop() -> void:
	if _workshop == null:
		return
	_workshop.level = _proc.level
	_workshop.used = _proc.used_slots()
	_workshop.total = _proc.slot_count()
	_workshop.ready_count = _proc.ready_count()
	_workshop.status = _proc.status_text()
	_workshop.queue_redraw()

## 按 E：有成品就取货（不弹面板），没成品就弹「放料」
func _open_craft_panel() -> void:
	if _proc.ready_count() > 0:
		_collect_crafts()
		return
	var entries := _craft_entries()
	if entries.is_empty():
		_say("没有能做的东西 —— 先去收点牛奶 / 羊毛 / 蛋")
		return
	_shop.open("加工坊 · 放料（%d/%d 槽 · 24 小时开工）" % [_proc.used_slots(),
		_proc.slot_count()], entries, "↑↓ 选配方 · E 放料 · Esc 关掉")

func _craft_entries() -> Array:
	var out: Array = []
	var free := _proc.first_free() >= 0
	for rid in RecipeDB.all_ids():
		var r := RecipeDB.get_recipe(rid)
		for q in range(3):
			var input_item := CropQuality.item_id(r["input"], q)
			var have := GameState.count_item(input_item)
			if have <= 0:
				continue
			var need := int(r["count"])
			var ok := have >= need and free
			var why := ""
			if not free:
				why = "槽满了"
			elif have < need:
				why = "还差 %d" % (need - have)
			out.append({
				"id": StringName("%s@%d" % [rid, q]),
				"name": ItemDB.display_name(rid),
				"price": 0,
				"note": "%s×%d → %s（有 %d）" % [
					ItemDB.display_name(input_item), need,
					RecipeDB.minutes_text(int(r["minutes"])), have],
				"enabled": ok,
				"reason": why,
			})
	return out

## "cheese@1" → {rid: cheese, quality: 1}
static func parse_craft_entry(entry_id: StringName) -> Dictionary:
	var s := str(entry_id)
	var at := s.find("@")
	if at < 0:
		return {}
	return {
		"rid": StringName(s.substr(0, at)),
		"quality": clampi(int(s.substr(at + 1)), 0, 2),
	}

func _on_craft_start(entry_id: StringName) -> void:
	var p := parse_craft_entry(entry_id)
	if p.is_empty():
		return
	var rid: StringName = p["rid"]
	var q := int(p["quality"])
	var r := RecipeDB.get_recipe(rid)
	if r.is_empty():
		return
	var input_item := CropQuality.item_id(r["input"], q)
	var need := int(r["count"])
	if GameState.count_item(input_item) < need:
		_say("原料不够（要 %s×%d）" % [ItemDB.display_name(input_item), need])
		return
	if _proc.first_free() < 0:
		_say("加工槽满了 —— 先取货")
		return
	GameState.remove_item(input_item, need)
	_proc.start(rid, q)
	_say("放进 %s×%d → %s（%s 后取）" % [ItemDB.display_name(input_item), need,
		ItemDB.display_name(CropQuality.item_id(rid, q)),
		RecipeDB.minutes_text(int(r["minutes"]))])
	_refresh_workshop()
	_refresh_hud()
	if _shop.is_open() and _shop_kind == SHOP_CRAFT:
		var entries := _craft_entries()
		if entries.is_empty():
			_shop.close()
		else:
			_shop.update_entries(entries)

func _collect_crafts() -> void:
	var got := _proc.take_all()
	if got.is_empty():
		_say("还没有加工好的东西")
		return
	var parts: Array[String] = []
	for g in got:
		var item := CropQuality.item_id(g["output"], int(g["quality"]))
		var put := GameState.add_item(item, int(g["count"]))
		parts.append(ItemDB.display_name(item) if put > 0
			else "%s（背包满了）" % ItemDB.display_name(item))
	_say("取货：%s" % "、".join(parts))
	_refresh_workshop()
	_refresh_hud()
	_refresh_toolbar()

## 每个 tick 推进加工槽（时间单位是游戏分钟，和时钟天然对齐）
func _advance_workshop(minutes: int) -> void:
	var done := _proc.advance_minutes(minutes)
	if not done.is_empty():
		var names: Array[String] = []
		for d in done:
			names.append(ItemDB.display_name(
				CropQuality.item_id(d["output"], int(d["quality"]))))
		_say("加工好了：%s —— 去加工坊取货" % "、".join(names))
	_refresh_workshop()

# ============================================================================
# 模块 7 · 背包（需求 1）—— 「使用」的语义在这一层
# ============================================================================
#
# UI 只把「第几格」丢上来。什么东西能怎么用属于玩法，不属于 UI。

func _on_inv_use(i: int) -> void:
	var id := GameState.slot_item(i)
	if id == &"":
		return
	# ① 种子 → 直接换成当前种子（省得 Tab 一颗颗翻过 24 种）
	var c: CropData = CropDB.crop_of_seed_item(id)
	if c != null:
		_player.set_seed(c.id)
		_inv.close()
		_say("当前种子换成 %s（%s季 · %d 天 · 有 %d 颗）" % [
			c.display_name, c.season_name(), c.grow_days, GameState.count_item(id)])
		return
	# ② 消耗品 → 必须对着地块 / 动物用，背包里用不了
	var d := ItemDB.resolve(id)
	if d != null and d.category == ItemDef.Cat.CONSUMABLE:
		_inv.close()
		_say("%s 要在世界里用：肥料选 6 / 7 号工具，饲料选 4 号，药剂空手对着病畜按 E"
			% d.display_name)
		return
	# ③ 作物 / 畜产品 / 加工品 → 出货或加工，不能「吃」
	_say("%s 不能直接使用 —— 拿去出货箱卖，或放进加工坊" % ItemDB.display_name(id))

func _on_inv_drop(i: int) -> void:
	var id := GameState.slot_item(i)
	if id == &"":
		return
	var nm := ItemDB.display_name(id)
	if GameState.drop_slot(i, 1):
		_say("丢掉了 1 个 %s" % nm)

# ============================================================================
# 模块 7 · 商店回收（需求 2：买卖）
# ============================================================================
#
# ShopUI 的 SELL 模式把 (entry_id, all) 丢过来。all = 按着 Shift，整叠卖掉。
# 为什么不做成「独立回收站」：出货箱已经能一键全卖，玩家真正缺的是
# 「只卖某一种、看清楚单价和行情」—— 那就是杂货铺的第二个页签。

## 可回收的东西：能卖 + 背包里有
func _sell_entries() -> Array:
	var out: Array = []
	for id in GameState.inventory.keys():
		if not ItemDB.is_sellable(id):
			continue
		var n := GameState.count_item(id)
		if n <= 0:
			continue
		var unit := Market.price(id, GameClock.season, GameClock.day)
		var delta := Market.delta_percent(id, GameClock.season, GameClock.day)
		out.append({
			"id": id,
			"name": ItemDB.display_name(id),
			"price": unit,
			"note": "×%d · 行情 %+d%% · 共 %dG" % [n, delta, unit * n],
			"enabled": true,
		})
	# 贵的排前面：一眼看到该先卖什么
	out.sort_custom(func(a, b): return int(a["price"]) > int(b["price"]))
	return out

func _on_sell(entry_id: StringName, all: bool) -> void:
	if entry_id == &"":
		return
	var have := GameState.count_item(entry_id)
	if have <= 0:
		_say("背包里没有 %s 了" % ItemDB.display_name(entry_id))
		_refresh_shop()
		return
	var n := have if all else 1
	var unit := Market.price(entry_id, GameClock.season, GameClock.day)
	var total := unit * n
	GameState.remove_item(entry_id, n)
	GameState.add_gold(total)
	_say("卖出 %s×%d · +%dG（%dG/个）" % [ItemDB.display_name(entry_id), n, total, unit])
	EventBus.shop_purchased.emit(_shop_kind, entry_id, -total)
	_refresh_shop()
	_refresh_hud()
	_refresh_toolbar()

## 杂货铺按 T 在「买」和「回收」之间切
func _on_mode_toggle() -> void:
	if _shop_kind != SHOP_SUPPLY:
		return
	if _shop.mode() == ShopUI.Mode.BUY:
		_shop.open("杂货铺 · 回收（E 卖 1 个 · Shift+E 全卖 · T 切回买）",
			_sell_entries(), "", ShopUI.Mode.SELL)
	else:
		_shop.open("杂货铺 · 饲料 / 药剂 / 木材（T 键切成回收模式）",
			_supply_entries(), "", ShopUI.Mode.BUY)

# ---------------- 繁殖棚（模块 5 需求 4）----------------

## 盖房：金币 + 木材，数值全在 data/buildings.csv
func _try_build_shed() -> void:
	var id := BreedingShed.BUILDING_ID
	var price := BuildingDB.price_of(id)
	var mat := BuildingDB.material_of(id)
	var need := BuildingDB.material_count_of(id)
	if GameState.gold < price:
		_say("盖%s要 %dG，还差 %dG" % [BuildingDB.name_of(id), price, price - GameState.gold])
		return
	if GameState.count_item(mat) < need:
		_say("还缺 %s×%d（杂货铺有卖）" % [
			ProductDB.display_name(mat), need - GameState.count_item(mat)])
		return
	GameState.spend_gold(price)
	GameState.remove_item(mat, need)
	GameState.set_flag(&"shed_built", true)
	_shed.queue_redraw()
	EventBus.building_built.emit(id)
	_say("%s 盖好了（%s）· 再按一次 E 选父母" % [BuildingDB.name_of(id), BuildingDB.cost_text(id)])
	_refresh_hud()

## 繁殖货架 = 牧场里所有动物，点一只选一只（选中的打 ✔）
func _breed_title() -> String:
	if _breed_picks.is_empty():
		return "繁殖棚 · 选第一只（一次 %s · %d 天后生崽）" % [
			Breeding.cost_text(), BuildingDB.gestation_days_of(BreedingShed.BUILDING_ID)]
	return "繁殖棚 · 选第二只（第一只：%s）" % _breed_label(_breed_picks[0])

func _breed_label(uid: StringName) -> String:
	var a := _herd.get_by_uid(uid)
	return "?" if a == null else a.display_label()

func _breed_entries() -> Array:
	var out: Array = []
	for a in _herd.animals:
		var picked := _breed_picks.has(a.uid)
		var st := "%s · %s · %s" % [a.stage_name(), a.heart_label(), _animal_state_text(a)]
		out.append({
			"id": a.uid,
			"name": ("✔" if picked else "") + a.display_label(),
			"price": 0,
			"note": st + ("  ← 已选" if picked else ""),
			"enabled": true,
		})
	return out

## 动物当前状态的短文案（繁殖货架用）
func _animal_state_text(a: AnimalState) -> String:
	if a.sick:
		return "生病第%d天" % a.sick_days
	if a.is_pregnant():
		return "妊娠剩%d天" % a.pregnant_days
	if a.awakened:
		return "已觉醒"
	return "健康"

## 在繁殖棚里点了一只动物
func _on_breed_pick(uid: StringName) -> void:
	var a := _herd.get_by_uid(uid)
	if a == null:
		return
	if _breed_picks.has(uid):
		_breed_picks.erase(uid)
	elif _breed_picks.size() < 2:
		_breed_picks.append(uid)
	if _breed_picks.size() < 2:
		_shop.update_title(_breed_title())
		_shop.update_entries(_breed_entries())
		return
	var x := _herd.get_by_uid(_breed_picks[0])
	var y := _herd.get_by_uid(_breed_picks[1])
	_breed_picks.clear()
	_do_breed(x, y)

## 真正开配：先问 Breeding（纯逻辑）能不能配，再扣钱扣饲料
func _do_breed(a: AnimalState, b: AnimalState) -> void:
	var reason := Breeding.can_breed(a, b, GameState.has_flag(&"shed_built"),
		_herd.size(), Herd.MAX_ANIMALS)
	var fail := ""
	if reason != Breeding.Reason.OK:
		fail = Breeding.reason_text(reason)
	else:
		# 模块 6：繁殖前也要看棚舍还有没有床位（生下来没地方住就是白配）
		var room := Housing.can_house(a.species, _herd, GameState.barn_levels())
		if room != Housing.Reason.OK:
			fail = "%s%s" % [HousingDB.name_of(Housing.housing_of(a.species)),
				Housing.reason_text(room)]
		elif GameState.gold < Breeding.GOLD_COST:
			fail = "手续费不够（%dG）" % Breeding.GOLD_COST
		elif GameState.count_item(&"feed") < Breeding.FEED_COST:
			fail = "饲料不够（要 %d 份）" % Breeding.FEED_COST

	if fail != "":
		_say("配不了：%s" % fail)
		_shop.update_title(_breed_title())
		_shop.update_entries(_breed_entries())
		return

	GameState.spend_gold(Breeding.GOLD_COST)
	GameState.remove_item(&"feed", Breeding.FEED_COST)
	var days := BuildingDB.gestation_days_of(BreedingShed.BUILDING_ID)
	Breeding.start(a, b, days)
	_shop.close()
	_say("%s × %s 配上了（-%dG 饲料×%d）· %d 天后有小家伙" % [
		a.display_label(), b.display_label(), Breeding.GOLD_COST, Breeding.FEED_COST, days])
	_animal_layer.refresh()
	_refresh_hud()
	_refresh_toolbar()

func _on_buy(entry_id: StringName) -> void:
	# 繁殖棚的货架不是「买」，是「选父母」，走另一条路
	if _shop_kind == SHOP_BREED:
		_on_breed_pick(entry_id)
		return
	# 模块 7：订单板 / 加工坊 / 工具铺也复用同一个壳，但语义各不相同
	if _shop_kind == SHOP_ORDER:
		_on_order_deliver(entry_id)
		return
	if _shop_kind == SHOP_CRAFT:
		_on_craft_start(entry_id)
		return
	if _shop_kind == SHOP_TOOL:
		if _buy_upgrade(entry_id):
			_refresh_shop()
		return

	var bought := false
	var spent := 0

	var seed_crop: CropData = CropDB.crop_of_seed_item(entry_id)
	var fert_level := Fertilizer.level_of_item(entry_id)
	var animal: AnimalData = AnimalDB.get_animal(entry_id)

	if seed_crop != null:
		spent = seed_crop.seed_price
		if GameState.spend_gold(spent):
			GameState.add_item(entry_id, 1)
			_say("买了 1 颗 %s 种子（-%dG，共 %d 颗）" % [
				seed_crop.display_name, spent, GameState.count_item(entry_id)])
			bought = true
	elif fert_level > 0:
		spent = Fertilizer.price(fert_level)
		if GameState.spend_gold(spent):
			GameState.add_item(entry_id, 1)
			_say("买了 1 袋 %s（-%dG，共 %d 袋）" % [
				Fertilizer.level_name(fert_level), spent, GameState.count_item(entry_id)])
			bought = true
	elif SUPPLY_ITEMS.has(entry_id):
		spent = ProductDB.price(entry_id)
		if GameState.spend_gold(spent):
			GameState.add_item(entry_id, 1)
			_say("买了 1 份 %s（-%dG，共 %d）" % [
				ProductDB.display_name(entry_id), spent, GameState.count_item(entry_id)])
			bought = true
	elif animal != null:
		spent = animal.price
		var room := Housing.can_house(entry_id, _herd, GameState.barn_levels())
		if room != Housing.Reason.OK:
			_say("%s：%s（对着棚舍按 E 扩建）" % [animal.display_name,
				Housing.reason_text(room)])
			return
		if GameState.spend_gold(spent):
			var st := _herd.add(entry_id, 0, _free_spawn_pos(entry_id))
			if st == null:
				GameState.add_gold(spent)      # 放不下就退钱
				_say("牧场满了，钱退给你了")
			else:
				st.debug_grow_adult()          # 商店卖的都是成年畜
				st.debug_ready_produce()       # 立刻给一次产出，方便上手
				_animal_layer.rebuild()
				_say("买下 %s（-%dG），已放进牧场 · %s" % [
					animal.display_name, spent, animal.action_name()])
				bought = true

	if not bought:
		return
	_refresh_shop()
	_refresh_hud()
	_refresh_toolbar()
	EventBus.shop_purchased.emit(_shop_kind, entry_id, spent)

## 成交后重铺货架（金币 / 持有数 / 可买状态都变了），并保持光标位置
func _refresh_shop() -> void:
	if not _shop.is_open():
		return
	match _shop_kind:
		SHOP_SEED:
			_shop.update_entries(_seed_entries())
		SHOP_ANIMAL:
			_shop.update_entries(_animal_entries())
		SHOP_SUPPLY:
			# 模块 7：杂货铺有「买」和「回收」两页，重铺时按当前模式走
			if _shop.mode() == ShopUI.Mode.SELL:
				_shop.update_entries(_sell_entries())
			else:
				_shop.update_entries(_supply_entries())
		SHOP_TOOL:
			_shop.update_entries(_tool_entries())
		SHOP_ORDER:
			_shop.update_entries(_order_entries())
		SHOP_CRAFT:
			_shop.update_entries(_craft_entries())
		SHOP_BREED:
			_shop.update_entries(_breed_entries())

## 围栏内第一个没有动物的落点（模块 6：按物种落进自己的子栏）
func _free_spawn_pos(species: StringName = &"") -> Vector2:
	var zone := WorldConfig.PEN
	var h := Housing.housing_of(species)
	if h != &"":
		zone = WorldConfig.zone_rect(h)
	var cands := _zone_slots(zone)
	for p in cands:
		if _herd.nearest(p, 18.0) == null:
			return p
	return cands[_herd.size() % cands.size()]

## 一块 zone 内均匀撒 3×3 个候选点（不写死坐标表，改分栏只改 WorldConfig）
func _zone_slots(z: Rect2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var cols := 3
	var rows := 3
	for r in range(rows):
		for c in range(cols):
			out.append(Vector2(
				z.position.x + z.size.x * (float(c) + 0.5) / float(cols),
				z.position.y + z.size.y * (float(r) + 0.5) / float(rows)))
	return out

# ---------------- 棚舍（模块 6 需求 A）----------------

## 开局：三栋棚舍都是 Lv1。牧场有牛有鸡有蜂，从空地开始盖会自相矛盾。
func _init_barns() -> void:
	for id in HousingDB.all_ids():
		if GameState.barn_level(id) <= 0:
			GameState.set_barn_level(id, 1)

func _barn_nodes() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("housing_barn"):
		if n is HousingBarn:
			out.append(n)
	return out

## 把「住了几只」写进建筑节点（建筑自己不去摸 herd，保持零耦合）
func _refresh_barns() -> void:
	for n in _barn_nodes():
		n.used_slots = Housing.count_in(_herd, n.housing_id)
		n.queue_redraw()

## 建筑按 E：盖房 / 扩建。价格与木材全是公式（HousingDB），这里只扣款与升级。
func _on_housing_upgrade(housing_id: StringName) -> void:
	if not HousingDB.has(housing_id):
		return
	var nm := HousingDB.name_of(housing_id)
	var lv := GameState.barn_level(housing_id)
	var max_lv := HousingDB.max_level_of(housing_id)
	if lv >= max_lv:
		_say("%s 已经满级 Lv%d（可养 %d 只）" % [nm, lv,
			HousingDB.capacity_at(housing_id, lv)])
		return
	var price := HousingDB.upgrade_price(housing_id, lv)
	var mat := HousingDB.material_of(housing_id)
	var need := HousingDB.upgrade_material_count(housing_id, lv)
	if GameState.gold < price:
		_say("%s%s要 %dG，还差 %dG" % ["建造" if lv <= 0 else "扩建", nm,
			price, price - GameState.gold])
		return
	if GameState.count_item(mat) < need:
		_say("还缺 %s×%d（杂货铺有卖）" % [ProductDB.display_name(mat),
			need - GameState.count_item(mat)])
		return
	GameState.spend_gold(price)
	GameState.remove_item(mat, need)
	GameState.set_barn_level(housing_id, lv + 1)
	_refresh_barns()
	_refresh_hud()
	_refresh_shop()                 # 容量变了，动物商店的灰行要跟着变
	EventBus.housing_upgraded.emit(housing_id, lv + 1)
	_say("%s 升到 Lv%d · 可养 %d 只（-%dG 木材×%d）" % [nm, lv + 1,
		HousingDB.capacity_at(housing_id, lv + 1), price, need])

## 把跑出自己子栏的动物拉回来（买来 / 生崽 / 换分栏规格之后都要跑一次）
func _clamp_animals_to_zones() -> void:
	for a in _herd.animals:
		var z := Housing.zone_rect(a.species)
		if z.has_point(a.pos):
			continue
		a.pos = Vector2(
			clampf(a.pos.x, z.position.x + 10.0, z.end.x - 10.0),
			clampf(a.pos.y, z.position.y + 12.0, z.end.y - 6.0))

# ---------------- 时间 ----------------

func _on_day(_d: int, _s: int, _y: int) -> void:
	var events := _grid.advance_day()
	var aevents := _herd.advance_day()
	# 天气效果必须在 advance_day 之后：advance_day 把 watered 重置了，雨天再浇满新的那一天
	var weather_notes := _apply_weather_day()
	_farm_layer.refresh()
	# 生崽 / 病逝会改变牧群成员数 —— 只 refresh() 是同步不了「多一只 / 少一只」的
	var restructure := false
	for e in aevents:
		if e["type"] == "birth" or e["type"] == "died":
			restructure = true
	_clamp_animals_to_zones()    # 模块 6：生崽会落在母亲旁边，可能跨栏
	if restructure:
		_animal_layer.rebuild()
	else:
		_animal_layer.refresh()
	EventBus.animal_events.emit(aevents)     # ⚠️ 模块 8 修：这行以前被并进上一行的注释里，成了死代码
	_refresh_barns()             # 模块 6：容量占用变了，建筑提示条要重画
	_check_awakenings()          # 模块 5：留棚 +3 也可能把动物喂到 10 心
	_sync_garden()
	# 模块 7：换天 = 行情重掷。清缓存后 Market 会按新的 day 重算三个品类。
	Market.clear_cache()
	_orders.prune()
	_tick_orders()
	_refresh_orders()
	_refresh_workshop()
	_refresh_hud()
	_refresh_toolbar()

	var withered := 0
	var died := 0
	var matured := 0
	for e in events:
		match e["type"]:
			"wither":
				withered += 1
			"dead":
				died += 1
			"mature":
				matured += 1
	var sick := 0
	var hungry := 0
	var neglected := 0
	var a_mature := 0
	var born := 0
	var lost := 0
	var critical := 0
	for e in aevents:
		match e["type"]:
			"sick":
				sick += 1
			"hungry":
				hungry += 1
			"neglect":
				neglected += 1
			"mature":
				a_mature += 1
			"birth":
				born += 1
			"died":
				lost += 1
			"critical":
				critical += 1
	var parts: Array = []
	if matured > 0:
		parts.append("成熟可收 %d 株" % matured)
	if withered > 0 or died > 0:
		parts.append("作物枯萎 %d·枯死 %d" % [withered, died])
	if hungry > 0:
		parts.append("动物漏喂 %d" % hungry)
	if neglected > 0:
		parts.append("被冷落 %d（好感 -%d）" % [neglected, AnimalState.NEGLECT_PENALTY])
	if sick > 0:
		parts.append("动物生病 %d（要药剂）" % sick)
	if critical > 0:
		parts.append("病危 %d 只 —— 明天不用药就没了" % critical)
	if lost > 0:
		parts.append("病逝 %d 只" % lost)
	if born > 0:
		parts.append("新生 %d 只幼崽" % born)
	if a_mature > 0:
		parts.append("长成成年 %d 只" % a_mature)
	parts.append_array(weather_notes)
	if not parts.is_empty():
		_say(" | ".join(parts))

	# 模块 8：跨日结算完 = 自动存档点（GDD §10.5「每天 2:00 强制入睡时自动存」）。
	# ⚠️ 必须放在所有 advance_day 之后：这时存下的才是「新一天开始」的干净状态，
	#    放在开头会存成「旧的一天 + 已推进的时钟」，读档时等于白过一天。
	_save_game(SaveSystem.SLOT_AUTO, true)

# ---------------- 天气效果落地（模块 2）----------------
#
# WeatherSystem 只给「效果表」，真正对农场/动物做什么由这里决定。
# 返回给玩家看的提示文字列表（不直接 _say，避免多条消息互相覆盖）。

func _apply_weather_day() -> Array[String]:
	var eff := WeatherSystem.today_effects()
	var notes: Array[String] = []

	if bool(eff["auto_water"]):
		var n := _grid.water_all()
		if n > 0:
			notes.append("雨天自动浇水 %d 格" % n)

	# 雨 / 雪天不放牧 → 留棚好感 +3（GDD §3.3）
	if not bool(eff["graze"]) and int(eff["affection_bonus"]) > 0:
		_herd.add_affection_all(int(eff["affection_bonus"]))
		notes.append("留棚动物好感 +%d" % int(eff["affection_bonus"]))

	if WeatherSystem.blizzard:
		notes.append("暴风雪：室外活动体力 ×2")

	# 暴风雨灾害（GDD §2.2）
	if float(eff["fence_risk"]) > 0.0 and _storm_rng.randf() < float(eff["fence_risk"]):
		notes.append("暴风雨打坏了栅栏（木材 ×2 可修）")
	if float(eff["crop_burn_risk"]) > 0.0:
		var burned := _burn_crops(float(eff["crop_burn_risk"]))
		if burned > 0:
			notes.append("雷击烧毁 %d 格作物" % burned)
	return notes

## 逐格掷雷击骰，烧死命中格上的作物（返回烧毁格数）
func _burn_crops(risk: float) -> int:
	var n := 0
	for cell in _grid.tiles.keys():
		var t: FarmGrid.Tile = _grid.tile_at(cell)
		if t == null or t.crop_id == StringName("") or t.dead:
			continue
		if _storm_rng.randf() < risk:
			t.dead = true
			n += 1
	return n

func _on_tick(_m: int) -> void:
	_advance_workshop(GameClock.TICK_GAME_MINUTES)   # 模块 7：加工坊按游戏分钟跑
	_tick_orders()                                   # 模块 7：订单过期 / 刷新
	_refresh_hud()

## 订单板的时间推进（每 tick 一次）。OrderBoard 只返回事件，弹提示在这里。
func _tick_orders() -> void:
	var ev := _orders.tick(GameClock.day, GameClock.minutes,
		ItemDB.sellable_ids(), GameClock.season)
	if ev.is_empty():
		return
	var fresh := 0
	var expired := 0
	for e in ev:
		match e["type"]:
			"new":
				fresh += 1
			"expired":
				expired += 1
	if expired > 0:
		_say("有 %d 张订单超时了（%s）" % [expired,
			"已完成 %d 单" % _orders.completed])
	elif fresh > 0:
		_say("订单板来了 %d 张新委托（%s 看板）" % [fresh, "对着订单板按 E"])
	_refresh_orders()
	if _shop.is_open() and _shop_kind == SHOP_ORDER:
		if _orders.active_count() <= 0:
			_shop.close()
		else:
			_shop.update_entries(_order_entries())

func _on_phase(_old: int, _new: int) -> void:
	_refresh_hud()

func _on_season(s: int) -> void:
	_ground.set_season_tint(s)      # 换季 → 地面染色（GDD §2.1 草地色）
	_grid.season = s                # 模块 3：季节门禁跟着换
	queue_redraw()                  # 牧场地面是 Main 自己画的，也要重绘
	_refresh_light()
	_refresh_hud()
	_refresh_toolbar()
	_refresh_shop()                 # 种子商店换季就换货
	_say("换季了：%s季。地里没成熟的老作物不会死，但只能种%s季作物" % [
		GameClock.season_name(), GameClock.season_name()])

func _on_tool_changed(_t: int) -> void:
	_refresh_hud()
	_refresh_toolbar()

func _on_seed_changed(_id: StringName) -> void:
	_refresh_toolbar()

func _on_gold(_g: int) -> void:
	_refresh_hud()

func _on_inventory(_id: StringName, _n: int) -> void:
	_refresh_hud()
	_refresh_toolbar()
	_refresh_orders()      # 模块 7：背包变了，「现在能交的订单」可能跟着变

# ---------------- 觉醒 / 对话（模块 5 需求 1）----------------

## 扫一遍「刚觉醒」的动物，逐个弹拟人化对话。
## 每帧都调（_process），但平时列表是空的，代价接近零。
func _check_awakenings() -> void:
	var pending := _herd.pending_awakenings()
	if pending.is_empty():
		return
	for a in pending:
		a.just_awakened = false
		_announce_awakening(a)
	_sync_garden()

func _announce_awakening(a: AnimalState) -> void:
	var ev := Awakening.event(a.species)
	if ev.is_empty():
		return
	EventBus.animal_awakened.emit(a.uid, a.species)
	EventBus.dialogue_requested.emit(Awakening.speaker(a.species), ev["lines"],
		Awakening.portrait(a.species))
	_say("%s 醒过来了 —— %s · %s（每天 30%% 概率产出 %s）" % [
		a.display_label(), Awakening.persona(a.species), Awakening.title_of(a.species),
		Awakening.gift_name(a.species)])
	_animal_layer.refresh()

func _on_dialogue(speaker: String, lines: Array, color: Color) -> void:
	_dialogue.show_dialogue(speaker, lines, color)

# ---------------- 秘密花园（模块 5 需求 5）----------------

## 同步花园状态：藤蔓门的进度文案 + 石碑的点亮 + 解锁判定。
## 只在「可能变了」的时候调（跨日 / 有动物觉醒 / _ready），不要每帧调 ——
## 每帧调会让 GardenDecor 每帧重绘。
func _sync_garden() -> void:
	var n := _herd.awakened_species_count()
	_gate.set_awakened_count(n)
	_decor.sync(_herd, GameState.garden_unlocked)
	if GameState.garden_unlocked:
		return
	if not _herd.all_species_awakened():
		return
	GameState.set_flag(&"garden_unlocked", true)
	_decor.sync(_herd, true)
	EventBus.garden_unlocked.emit()
	EventBus.dialogue_requested.emit(Awakening.GARDEN_UNLOCK["persona"],
		Awakening.GARDEN_UNLOCK["lines"], Awakening.GARDEN_UNLOCK["portrait"])
	_say("全部 %d 种动物都觉醒了 —— 东边的藤蔓门开了！" % AnimalDB.all_ids().size())

## 传送（模块 5）：藤蔓门 → 花园，花园里的门 → 牧场
func _on_portal(dest: StringName) -> void:
	if dest == &"garden":
		if not GameState.garden_unlocked:
			_say("藤蔓门还锁着 —— 先让每一种动物都醒过来")
			return
		_player.global_position = WorldConfig.GARDEN_ENTRY
		_zone_garden = true
		_say("秘密花园 · 每一座石碑，都是你亲手唤醒的动物")
	else:
		_player.global_position = WorldConfig.FARM_ENTRY
		_zone_garden = false
	_apply_camera_limits()
	_player.facing = "down"
	_player.facing8 = "down"

## 玩家跨区域 → 换相机 limit。
## 花园和主地图是两块分开的地，相机不能再用一套 limit 包住两块
## （那样会露出中间那条 64px 的空缝）。
func _update_zone() -> void:
	var in_garden := WorldConfig.in_garden(_player.global_position)
	if in_garden == _zone_garden:
		return
	_zone_garden = in_garden
	_apply_camera_limits()

func _apply_camera_limits() -> void:
	var cam: Camera2D = _player.get_node_or_null("Camera2D")
	if cam == null:
		return
	var l := WorldConfig.camera_limits_for(_zone_garden)
	cam.limit_left = int(l[0])
	cam.limit_top = int(l[1])
	cam.limit_right = int(l[2])
	cam.limit_bottom = int(l[3])

# ---------------- HUD ----------------

func _refresh_light() -> void:
	var base := GameClock.light_color_at(GameClock.minutes)
	var m: float = WeatherSystem.light_mult      # 阴天 -10%
	_light.color = Color(base.r * m, base.g * m, base.b * m, 1.0)

func _item_name(id: StringName) -> String:
	var fert := Fertilizer.name_of_item(id)
	if fert != "":
		return fert
	var seed_crop: CropData = CropDB.crop_of_seed_item(id)
	if seed_crop != null:
		return "%s种子" % seed_crop.display_name
	var p := CropQuality.split(id)
	var c: CropData = CropDB.get_crop(p["id"])
	if c != null:
		return CropQuality.label(c.display_name, int(p["quality"]))
	if ProductDB.has(id):
		return ProductDB.display_name(id)
	return str(id)

## 牧群摘要：按 CSV 顺序列出实际拥有的物种（模块 4 有 9 种，不能写死牛/鸡）
func _animal_summary() -> String:
	var parts: Array[String] = []
	for id in AnimalDB.all_ids():
		var n := _herd.count_species(id)
		if n > 0:
			parts.append("%s×%d" % [AnimalDB.get_animal(id).display_name, n])
	return " ".join(parts) if not parts.is_empty() else "无"

func _refresh_hud() -> void:
	# 背包一行放不下 24 种种子 —— 种子汇总成一项，其余逐项列出。
	# 具体某种种子还剩几颗，看左下角工具条（当前选中那颗）。
	var seeds := 0
	var inv := ""
	for id in GameState.inventory:
		if CropDB.crop_of_seed_item(id) != null:
			seeds += GameState.count_item(id)
			continue
		inv += "%s×%d " % [_item_name(id), GameState.count_item(id)]
	if seeds > 0:
		inv = "种子×%d " % seeds + inv
	if inv == "":
		inv = "空"
	# 日期 / 时间 / 天气已交给右上角的 ClockHUD，这里只管资源，不再重复。
	# 分四行：资源 / 牧群与地 / 行情与订单与加工 / 背包。
	# ⚠️ HUD 的右边界是 442（不是 632）—— 再往右是 ClockBg 的地盘，模块 4 踩过。
	var garden := " 🌸秘密花园" if GameState.garden_unlocked else ""
	var barns := Housing.summary_text(_herd, GameState.barn_levels())
	_hud.text = "💰%dG  工具[%s]  觉醒 %d/%d%s  棚舍 %s\n动物[%s] 总心 %d  地[%d株 肥%d格]\n%s\n订单 %d/%d · 加工 %d/%d槽\n背包 %d/%d格: %s" % [
		GameState.gold, Player.TOOL_LABEL[_player.current_tool],
		_herd.awakened_species_count(), AnimalDB.all_ids().size(), garden, barns,
		_animal_summary(), _herd.total_hearts(),
		_grid.crop_count(), _grid.fertilized_count(),
		Market.summary(GameClock.day, GameClock.season),
		_orders.active_count(), OrderBoard.MAX_ACTIVE,
		_proc.ready_count(), _proc.slot_count(),
		GameState.used_slot_count(), GameState.slot_capacity(), inv,
	]

## 左下角工具条：工具 1-7 + 当前种子 + 消耗品 + 工具等级 / 背包 / 订单 / 加工
func _refresh_toolbar() -> void:
	var parts: Array[String] = []
	for i in range(Player.TOOL_LABEL.size()):
		var t: String = Player.TOOL_LABEL[i]
		parts.append("[%d%s%s]" % [i + 1, t, "●" if i == _player.current_tool else ""])
	var c: CropData = CropDB.get_crop(_player.selected_seed)
	var seed_line := ""
	if c != null:
		var ok := _grid.can_plant(c.id)
		seed_line = "种子 %s%s(%s) %d天·卖%dG·需肥[%s]·有%d%s " % [
			"✔" if ok else "✘",
			c.display_name, c.season_name(),
			c.grow_days, c.sell_price,
			["低", "中", "高"][c.fertilize],
			GameState.count_item(CropDB.seed_item(c.id)),
			"" if ok else "←非当季 ",
		]
	var fert_line := "基础肥×%d 高级肥×%d 饲料×%d 药剂×%d 木材×%d  Tab换种" % [
		GameState.count_item(Fertilizer.item_id(Fertilizer.Level.BASIC)),
		GameState.count_item(Fertilizer.item_id(Fertilizer.Level.HIGH)),
		GameState.count_item(&"feed"),
		GameState.count_item(MEDICINE),
		GameState.count_item(WOOD),
	]
	var up_line := "  锄Lv%d 壶Lv%d 背包%d/%d格 · 订单%d/%d · 加工%d/%d" % [
		GameState.tool_level(&"hoe"), GameState.tool_level(&"can"),
		GameState.used_slot_count(), GameState.slot_capacity(),
		_orders.active_count(), OrderBoard.MAX_ACTIVE,
		_proc.ready_count(), _proc.slot_count(),
	]
	_toolbar.text = "  ".join(parts) + "\n" + seed_line + "\n" + fert_line + up_line

func _say(msg: String) -> void:
	_tip.text = msg
	_tip_until = Time.get_ticks_msec() / 1000.0 + 2.5

## 交互提示：玩家探针发现可交互物 → 底部提示条（GDD §10.4）
func _on_prompt(text: String) -> void:
	_prompt.text = text

# ---------------- 牧场木栅栏（碰撞在 WorldCollision，这里只画同一组矩形）----------------

## 牧场地面色（已套季节染色）。
## ⚠️ 这块是 Main 自己画的，不经过 GroundLayer 的季节着色器，所以必须手动套同一组参数，
## 否则围栏里四季常绿、跟外面完全脱节。抽成函数是为了能被测试断言。
func pen_color() -> Color:
	return Color("#8FC96A").lerp(
		SeasonEffects.grass_color(GameClock.season),
		SeasonEffects.grass_tint_amount(GameClock.season))

func _draw() -> void:
	_draw_pen()

func _draw_pen() -> void:
	draw_rect(WorldConfig.PEN, pen_color())
	# 栅栏：直接画 WorldConfig 给的那 5 段（跟碰撞体一一对应，不可能穿模）
	var c := Color("#8B5A2B")
	for r in WorldConfig.fence_walls():
		draw_rect(r, c)
	# 门洞两侧加两根立柱，暗示「这里能走进去」
	var g := WorldConfig.GATE
	draw_rect(Rect2(g.position.x - 2, g.position.y - 6, 5, 10), c)
	draw_rect(Rect2(g.position.x - 2, g.end.y - 4, 5, 10), c)

# ============================================================================
# 模块 8 · 存档系统
# ============================================================================
#
# 三层分工（前两层在别处，这里只做第三层）：
#   SaveSystem          只管「字典 ⇄ 文件」：JSON 化 / 原子写 / 版本 / 容错
#   各系统 to_dict      只管自己有哪些字段（GameClock / FarmGrid / Herd / …）
#   本文件              只管「一局 = 哪几坨」，以及**读档后的画面同步**
#
# 存：clock / weather / state / farm / herd / orders / processor / player
# 不存：
#   · Market 行情缓存 —— (天, 品类) 的纯函数，清掉缓存按新天数重算即可
#   · just_awakened / _pending_animal / _breed_picks / UI 开关 —— 瞬态
#   · inventory 派生索引 —— GameState.from_dict 里会 _rebuild_index()
#
# 键位：F5 快速存档到 1 号槽 · F9 读档 · 跨日 2:00 自动存 0 号槽

## 把一局摊平成字典（version / 时间戳由 SaveSystem.save 补）
func _build_save() -> Dictionary:
	return {
		"meta": {
			"day": GameClock.day,
			"season": GameClock.season,
			"year": GameClock.year,
			"clock": GameClock.clock_text(),
			"weather": WeatherSystem.weather_name(),
			"gold": GameState.gold,
			"animals": _herd.size(),
			"awakened": _herd.awakened_species_count(),
			"garden": GameState.garden_unlocked,
		},
		"clock": GameClock.to_dict(),
		"weather": WeatherSystem.to_dict(),
		"state": GameState.to_dict(),
		"farm": _grid.to_dict(),
		"herd": _herd.to_dict(),
		"orders": _orders.to_dict(),
		"processor": _proc.to_dict(),
		"player": _player.to_dict(),
	}

## 存档。quiet = true 时不弹提示（自动存档用，别每天 2:00 怼玩家一句）
func _save_game(slot: int, quiet: bool = false) -> bool:
	var res := SaveSystem.save(slot, _build_save())
	if bool(res["ok"]):
		if not quiet:
			_say("已存档 · 第 %d 天 %s · %s" % [GameClock.day, GameClock.clock_text(),
				SaveSystem.slot_label(slot)])
		return true
	_say("存档失败：%s" % res["error"])
	return false

## 读档。返回是否成功。
func _load_game(slot: int) -> bool:
	var res := SaveSystem.load_slot(slot)
	if not bool(res["ok"]):
		_say("读档失败：%s" % res["error"])
		return false
	_apply_save(res["data"])
	_say("已读档 · 第 %d 天 %s · %s（%d 只动物 · %dG）" % [
		GameClock.day, GameClock.clock_text(), SaveSystem.slot_label(slot),
		_herd.size(), GameState.gold])
	return true

## F9：优先快速存档（F5 手存的），没有就退回自动存档
func _load_latest() -> void:
	if SaveSystem.exists(SaveSystem.SLOT_QUICK):
		_load_game(SaveSystem.SLOT_QUICK)
	elif SaveSystem.exists(SaveSystem.SLOT_AUTO):
		_load_game(SaveSystem.SLOT_AUTO)
	else:
		_say("还没有存档 —— 先按 F5 存一个")

## 把字典灌回每个系统，然后把画面从头同步一遍。
## ⚠️ 顺序：先数据后视觉。_sync_garden() 要读 herd + GameState 的 flag，
##    必须等 state / herd 都灌完再调。
## ⚠️ 读档不触发任何 advance_day / tick —— 时间直接落位，不结算、不掷骰。
func _apply_save(d: Dictionary) -> void:
	_shop.close()
	_inv.close()
	GameState.from_dict(d.get("state", {}))
	GameClock.from_dict(d.get("clock", {}))
	WeatherSystem.from_dict(d.get("weather", {}))
	_grid.from_dict(d.get("farm", {}))
	_grid.season = GameClock.season          # 存档里的 season 可能和门禁不一致，以时钟为准
	_herd.from_dict(d.get("herd", {}))
	_orders.from_dict(d.get("orders", {}))
	_proc = Processor.new(1)
	_proc.from_dict(d.get("processor", {}))
	_player.from_dict(d.get("player", {}))
	_zone_garden = WorldConfig.in_garden(_player.global_position)

	Market.clear_cache()                     # 行情按读回来的天数重算
	_ground.set_season_tint(GameClock.season)
	_farm_layer.grid = _grid                 # 防御：grid 出过实例就重新挂上
	_farm_layer.refresh()
	_animal_layer.herd = _herd
	_animal_layer.rebuild()
	_refresh_barns()
	_refresh_workshop()
	_refresh_orders()
	_sync_garden()
	_apply_camera_limits()
	# 时钟面板自己订阅 tick / day 刷新，读档不触发任何 tick —— 得手动叫它刷一次，
	# 否则读档后右上角会拿旧时间糊你 0.6 秒（到下一个 tick 才自愈）。
	var clock_panel := get_node_or_null("UI/ClockPanel") as ClockHUD
	if clock_panel != null:
		clock_panel.refresh()
	_refresh_light()
	_refresh_hud()
	_refresh_toolbar()
