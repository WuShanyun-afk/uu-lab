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

## 挤奶黄金窗口的兜底值（真值来自 animals.csv 的 produce_window 列）
const MILK_WINDOW_MINUTES := 180

const SHOP_SEED := &"seed"
const SHOP_ANIMAL := &"animal"
const SHOP_SUPPLY := &"supply"     ## 模块 5：杂货铺（饲料 / 药剂 / 木材）
const SHOP_BREED := &"breed"       ## 模块 5：繁殖棚（盖房 or 选父母）

## 杂货铺卖的东西（价格一律来自 products.csv）
const SUPPLY_ITEMS: Array[StringName] = [&"feed", &"medicine", &"wood"]

## 药剂 / 木材的 item id（别写成裸字符串散落各处）
const MEDICINE := &"medicine"
const WOOD := &"wood"

## 新动物进牧场的落点（围栏内、避开栅栏与门洞）。按顺序找第一个空位。
const SPAWN_SLOTS: Array[Vector2] = [
	Vector2(544, 120), Vector2(608, 120), Vector2(672, 120), Vector2(712, 120),
	Vector2(544, 184), Vector2(608, 184), Vector2(672, 184), Vector2(712, 184),
	Vector2(544, 240), Vector2(608, 240), Vector2(672, 240), Vector2(712, 240),
]

@onready var _player: Player = $World/YSortRoot/Player
@onready var _light: CanvasModulate = $CanvasModulate
@onready var _hud: Label = $UI/HUD
@onready var _tip: Label = $UI/Tip
@onready var _prompt: Label = $UI/Prompt
@onready var _toolbar: Label = $UI/ToolBar
@onready var _shop: ShopUI = $UI/ShopPanel
@onready var _minigame: MinigameUI = $UI/Minigame
@onready var _dialogue: DialogueUI = $UI/Dialogue
@onready var _farm_layer: Node2D = $World/FarmLayer
@onready var _animal_layer: AnimalLayer = $World/YSortRoot/AnimalLayer
@onready var _ground: GroundLayer = $World/GroundLayer
@onready var _gate: GardenGate = $World/GardenGate
@onready var _shed: BreedingShed = $World/BreedingShed
@onready var _decor: GardenDecor = $World/GardenDecor

var _grid: FarmGrid
var _herd: Herd
var _last_tip := ""
var _tip_until := 0.0
## 商店里正在卖什么（种子 / 动物 / 杂货 / 繁殖）—— 成交后要按同一份货架刷新
var _shop_kind: StringName = &""
## 正在等节奏条结果的那只动物
var _pending_animal: AnimalState = null
## 繁殖棚里已经选好的父母（0 / 1 / 2 只）
var _breed_picks: Array[StringName] = []
## 玩家现在是不是在秘密花园里（决定相机 limit）
var _zone_garden := false
## 灾害判定专用（栅栏损坏 / 雷击烧作物）—— 和玩法随机分开，避免污染主随机流
var _storm_rng := RandomNumberGenerator.new()

func _ready() -> void:
	_storm_rng.seed = 20261022
	_grid = FarmGrid.new()
	_grid.season = GameClock.season     # 模块 3：季节门禁（春天种不了南瓜）
	_farm_layer.grid = _grid
	_give_starter_items()

	_herd = Herd.new(20261015)
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
	_shop.buy_requested.connect(_on_buy)
	_minigame.finished.connect(_on_minigame_finished)
	_minigame.cancelled.connect(_on_minigame_cancelled)
	GameState.gold_changed.connect(_on_gold)
	GameState.inventory_changed.connect(_on_inventory)

	_ground.set_season_tint(GameClock.season)
	_refresh_light()
	_apply_camera_limits()
	_sync_garden()
	_refresh_hud()
	_refresh_toolbar()
	_say("WASD 移动 · E 用工具/交互 · 1-7 换工具 · Tab 换种子 · F11 全屏")

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

func _toggle_fullscreen() -> void:
	var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

# ---------------- 动物初始化 ----------------

func _setup_animals() -> void:
	# ⚠️ 第 0 只必须是奶牛：test_weather.gd 用 _herd.animals[0] 断言「雨天留棚 +3」
	var cow1 := _herd.add(&"cow", 300, Vector2(576, 152))
	_herd.add(&"cow", 150, Vector2(664, 152))
	var c1 := _herd.add(&"chicken", 250, Vector2(560, 214))
	var c2 := _herd.add(&"chicken", 400, Vector2(620, 222))
	_herd.add(&"chicken", 100, Vector2(680, 208))
	# 模块 4 的展示阵容：羊（剪毛周期 3 天）、鸭、蜜蜂（采蜜周期 4 天）
	_herd.add(&"sheep", 220, Vector2(544, 120))
	_herd.add(&"duck", 180, Vector2(712, 120))
	_herd.add(&"bee", 300, Vector2(544, 240))
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
	_herd.add(&"turkey", 300, Vector2(664, 244))

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
			if _grid.water(cell):
				_say("浇水")
				_player.play_watering()
				_farm_layer.refresh()
			elif WeatherSystem.is_wet():
				_say("雨天不用浇水，地是湿的")
			else:
				_say("这格还没锄（先用 1 锄头）")
		Player.Tool.SEED:
			_plant(cell)
		Player.Tool.FERT:
			_fertilize(cell, Fertilizer.Level.BASIC)
		Player.Tool.FERT_HIGH:
			_fertilize(cell, Fertilizer.Level.HIGH)

# ---------------- 锄地（模块 3：顺带清理枯死作物）----------------

func _hoe(cell: Vector2i) -> void:
	var t := _grid.tile_at(cell)
	var was_dead := t != null and t.dead
	var was_tilled := t != null and t.tilled
	if _grid.till(cell):
		_player.play_hoe()
		if WeatherSystem.is_wet():
			_grid.water(cell)      # 雨天锄完就是湿的
		_say("清理枯死作物，这块地又能种了" if was_dead else "锄地")
		_farm_layer.refresh()
		_refresh_toolbar()
	elif was_tilled:
		_say("这块地已经锄过了")

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
	if _shop.is_open() or _minigame.is_active() or _dialogue.is_open():
		return
	_shop_kind = shop_id
	_breed_picks.clear()
	if shop_id == SHOP_SEED:
		_shop.open("种子商店 · %s季（买下即入背包）" % GameClock.season_name(), _seed_entries())
	elif shop_id == SHOP_ANIMAL:
		_shop.open("动物商店 · 买下直接放进牧场（成年）", _animal_entries())
	elif shop_id == SHOP_SUPPLY:
		_shop.open("杂货铺 · 饲料 / 药剂 / 木材（买下即入背包）", _supply_entries())
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
func _animal_entries() -> Array:
	var out: Array = []
	for id in AnimalDB.ids_by_price():
		var a: AnimalData = AnimalDB.get_animal(id)
		var afford := GameState.gold >= a.price
		out.append({
			"id": id,
			"name": a.display_name,
			"price": a.price,
			"note": "%s·%s·%s·成年%d天·有%d" % [
				a.housing_name(), a.action_name(), a.period_text(),
				a.mature_days, _herd.count_species(id)],
			"enabled": afford,
			"reason": "钱不够" if not afford else "",
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
		if GameState.spend_gold(spent):
			var st := _herd.add(entry_id, 0, _free_spawn_pos())
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
			_shop.update_entries(_supply_entries())
		SHOP_BREED:
			_shop.update_entries(_breed_entries())

## 围栏内第一个没有动物的落点
func _free_spawn_pos() -> Vector2:
	for p in SPAWN_SLOTS:
		if _herd.nearest(p, 20.0) == null:
			return p
	return SPAWN_SLOTS[_herd.size() % SPAWN_SLOTS.size()]

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
	if restructure:
		_animal_layer.rebuild()
	else:
		_animal_layer.refresh()
	EventBus.animal_events.emit(aevents)
	_check_awakenings()          # 模块 5：留棚 +3 也可能把动物喂到 10 心
	_sync_garden()
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
	_refresh_hud()

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
	# 分三行：觉醒进度 / 牧群 / 背包。一行塞不下会撞到右上角时钟（模块 4 踩过）。
	var garden := " 🌸秘密花园" if GameState.garden_unlocked else ""
	_hud.text = "💰%dG   工具[%s]   觉醒 %d/%d%s\n动物[%s] 总心 %d   地[%d 株 · 肥 %d 格]\n背包: %s" % [
		GameState.gold, Player.TOOL_LABEL[_player.current_tool],
		_herd.awakened_species_count(), AnimalDB.all_ids().size(), garden,
		_animal_summary(), _herd.total_hearts(),
		_grid.crop_count(), _grid.fertilized_count(), inv,
	]

## 左下角工具条：工具 1-7 + 当前种子（含季节、天数、库存）+ 药剂 / 木材
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
	_toolbar.text = "  ".join(parts) + "\n" + seed_line + fert_line

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
