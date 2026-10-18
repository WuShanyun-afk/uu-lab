class_name RoomScene
extends Node2D
## 房间场景的**唯一脚本**（模块 11 需求 3）—— 屋内 / 镇上 / 商店 / 矿洞共用
##
## 一个房间 = RoomData 里的一条数据。本脚本只做四件事：
##   ① 按数据搭场景（地板 / 墙 / 出口 / 可交互物 / 玩家）
##   ② 在 SceneRouter 注册位置钩子（房间没有农场数据，capture 留空）
##   ③ 处理可交互物的动作（存档柜 / 柜台 / 床 / 机器）
##   ④ 进场景时按「入口名 / 读档坐标」把玩家放好
##
## 为什么这些房间**不持有**农场数据：
##   农田 / 牧群 / 建筑 / 订单都住在 main.gd。房间只是「另一个地方」，
##   玩家在屋里睡觉时，牧场里的牛并没有消失 —— 它们的真源在 SceneRouter.carry 里。
##   房间只读 GameState / GameClock / WeatherSystem 这些 autoload（它们不属于任何场景）。
##
## ⚠️ 本脚本必须能在**任何场景**下独立跑（直接从编辑器运行 house.tscn 也不该崩）：
##    carry 为空时按「新开一局」处理，不假设牧场一定来过。

const PLAYER_SCENE := "res://scenes/player.tscn"

@export var room_id: StringName = &"house"

var _room: Dictionary = {}
var _player: Player = null
var _ui: CanvasLayer = null
var _hud: Label = null
var _tip: Label = null
var _dialogue: DialogueUI = null
var _shop: ShopUI = null
var _shop_mode_buy := true
var _tip_until := 0.0

func _ready() -> void:
	_room = RoomData.room(room_id)
	if _room.is_empty():
		push_error("[RoomScene] 没有这个房间：%s" % String(room_id))
		return
	_build_ui()
	_build_world()
	# 房间不捕获农场数据（_capture 留空 → carry 原样带着）；
	# 只注册「读档时放哪 / 现在在哪」两个位置钩子。
	SceneRouter.register_scene(room_id, Callable(), Callable(self, "_apply_loaded"),
		Callable(self, "_player_pos"), Callable(self, "_place_player"))
	_place_from_entry()
	_refresh_hud()
	_say("%s · E 交互 · F5 快速存档 / F6 存档面板 / F9 读档" % RoomData.room_name(room_id))
	EventBus.room_prop_used.connect(_on_prop_used)
	EventBus.dialogue_requested.connect(_on_dialogue_requested)
	EventBus.world_message.connect(_say)              # 存档面板的提示也走提示条
	# 模块 附1：屋里是木地板，脚步换个音；回牧场时 main 会把地表查询重新注册回来
	AudioManager.set_terrain_provider(_terrain_wood)

## 房间地表恒为木地板（没有 FarmGrid，也不需要知道草地是什么）
func _terrain_wood(_world_pos: Vector2) -> StringName:
	return &"wood"

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _tip_until > 0.0 and now > _tip_until:
		_tip_until = 0.0
		_tip.text = ""

# ---------------- 搭场景 ----------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "UI"
	add_child(_ui)
	_hud = Label.new()
	_hud.position = Vector2(8, 4)
	_hud.size = Vector2(430, 60)
	_hud.add_theme_font_size_override("font_size", 10)
	_hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ui.add_child(_hud)
	_tip = Label.new()
	_tip.position = Vector2(8, 292)
	_tip.size = Vector2(500, 40)
	_tip.add_theme_font_size_override("font_size", 11)
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ui.add_child(_tip)
	_dialogue = DialogueUI.new()
	_dialogue.name = "Dialogue"
	_ui.add_child(_dialogue)
	_shop = ShopUI.new()
	_shop.name = "ShopPanel"
	_ui.add_child(_shop)
	_shop.buy_requested.connect(_on_shop_buy)
	_shop.sell_requested.connect(_on_shop_sell)
	_shop.mode_toggle_requested.connect(_on_mode_toggle)

func _build_world() -> void:
	var size := Vector2(RoomData.room_size(room_id))
	# 玩家
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_player.name = "Player"
	add_child(_player)
	_player.z_index = 1
	var cam := _player.get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		cam.limit_left = 0
		cam.limit_top = 0
		cam.limit_right = int(size.x)
		cam.limit_bottom = int(size.y)
	# 出口
	for e in RoomData.exits_of(room_id):
		var ex := RoomExit.new()
		ex.name = "Exit_" + String(e["to"])
		add_child(ex)
		ex.setup(e["to"], e["entry"], str(e["label"]),
			Vector2(e["pos"]), Vector2(e["size"]))
	# 可交互物：住宅按**等级**动态生成（模块 12 需求 3），其余房间读 RoomData
	if room_id == &"house":
		_build_house_props()
	else:
		for p in RoomData.props_of(room_id):
			_add_prop(p["id"], p["action"], str(p["label"]),
				Vector2(p["pos"]), Vector2(p["size"]))

func _draw() -> void:
	var size := Vector2(RoomData.room_size(room_id))
	var bg: Color = _room.get("bg", Color("#3A3A44"))
	var floor_c: Color = _room.get("floor", Color("#55515E"))
	draw_rect(Rect2(Vector2.ZERO, size), bg)
	draw_rect(Rect2(16, 16, size.x - 32, size.y - 32), floor_c)
	# 地砖缝
	var step := 32
	for x in range(16, int(size.x) - 16, step):
		draw_rect(Rect2(x, 16, 1, size.y - 32), floor_c.darkened(0.08))
	for y in range(16, int(size.y) - 16, step):
		draw_rect(Rect2(16, y, size.x - 32, 1), floor_c.darkened(0.08))
	# 四面墙
	var wall := Color("#2A2018")
	draw_rect(Rect2(0, 0, size.x, 16), wall)
	draw_rect(Rect2(0, size.y - 16, size.x, 16), wall)
	draw_rect(Rect2(0, 0, 16, size.y), wall)
	draw_rect(Rect2(size.x - 16, 0, 16, size.y), wall)
	# 墙上的暗角，别让房间看起来像一个纯色矩形
	draw_rect(Rect2(16, 16, size.x - 32, 10), Color(0, 0, 0, 0.18))
	draw_rect(Rect2(16, 16, 10, size.y - 32), Color(0, 0, 0, 0.18))
	_draw_furniture()          # 模块 12：玩家摆的家具（画在地板上、道具下面）

## 住宅里的道具随等级增加（需求 3）：
##   Lv1 床 + 存档箱 + 工作台（升级用）
##   Lv2 再加灶台（做饭）
##   Lv3 再加地窖门（酿酒）
## 工作台放在屋里而不是农场：房子的升级本来就该在**房子里**点。
func _build_house_props() -> void:
	var lv := GameState.house_level
	_add_prop(&"bed", &"bed", "床（睡觉 → 次日）", Vector2(150, 240), Vector2(64, 36))
	_add_prop(&"chest", &"save", "存档柜", Vector2(510, 240), Vector2(52, 36))
	_add_prop(&"bench", &"house_upgrade", "工作台（升级房子）", Vector2(510, 110),
		Vector2(60, 36))
	if lv >= 2:
		_add_prop(&"kitchen", &"cook", "灶台（做饭）", Vector2(330, 240), Vector2(66, 36))
	if lv >= 3:
		_add_prop(&"cellar", &"brew", "地窖门（酿酒）", Vector2(150, 110), Vector2(56, 36))

func _add_prop(id: StringName, action: StringName, label: String,
		pos: Vector2, size: Vector2) -> void:
	var prop := RoomProp.new()
	prop.name = "Prop_" + String(id)
	add_child(prop)
	prop.setup(id, action, label, pos, size)

# ---------------- 落位（入口 / 读档）----------------

func _place_from_entry() -> void:
	if SceneRouter.has_pending_pos:
		_place_player(SceneRouter.pending_pos)
	else:
		_place_player(RoomData.entry_pos(room_id, SceneRouter.pending_entry))
	SceneRouter.has_pending_pos = false

func _place_player(pos: Vector2) -> void:
	if _player == null:
		return
	_player.global_position = pos
	_player.position = pos
	_player.facing = "down"
	_player.facing8 = "down"

func _player_pos() -> Vector2:
	return Vector2.ZERO if _player == null else _player.global_position

## 读档：SceneRouter 在原地读档时调（同场景）
func _apply_loaded(_d: Dictionary, pos: Variant) -> void:
	if pos != null:
		_place_player(pos)
	EventBus.set_ui_modal(false)
	if _shop != null:
		_shop.close()
	if _dialogue != null:
		_dialogue.close()
	_refresh_hud()

# ---------------- 可交互物 ----------------

func _on_prop_used(prop_id: StringName, action: StringName) -> void:
	match String(action):
		"save":
			# 存档柜 = 多存档位面板（F6 的另一种开法，玩家不用记快捷键）
			SavePanel.open()
			_say("存档柜：↑↓ 选档位 · S 保存 · L 读取 · D 删除 · Esc 关")
		"shop":
			_open_shop()
		"bed":
			_sleep()
		"cook":
			_cook()
		"brew":
			_brew()
		"house_upgrade":
			_upgrade_house()
		"machine":
			_talk_machine()
		_:
			_talk("东西", ["（%s。没什么特别的。）" % String(prop_id)], Color("#D8D2C0"))

func _talk(speaker: String, lines: Array, color: Color) -> void:
	EventBus.dialogue_requested.emit(speaker, lines, color)

## DialogueUI 自己不订阅信号（主场景是 main 收到后转发给它的）。
## 房间场景没有 main，所以这里自己接一次 —— 否则床 / 机器的台词发出去没人显示。
func _on_dialogue_requested(speaker: String, lines: Array, color: Color) -> void:
	if _dialogue != null:
		_dialogue.show_dialogue(speaker, lines, color)

# ---------------- 住宅：睡觉 / 做饭 / 酿酒 / 升级（需求 3 / 4 / 5）----------------

## 睡觉（需求 4 / 5）：推进到次日 + 自动存档，人还醒在屋里（出门才回牧场）
## 为什么睡觉要自动存档：这是**唯一的跨日点**，不存的话玩家睡完直接关游戏就白睡一天。
func _sleep() -> void:
	var day := DayCycle.sleep_to_next_day()
	SceneRouter.save_session(SaveSystem.SLOT_AUTO)
	_say("第 %d 天 %s · 已睡到天亮（自动存档 %s）" % [day, GameClock.clock_text(),
		SaveSystem.slot_label(SaveSystem.SLOT_AUTO)])
	_refresh_hud()
	_rebuild_house_props()

## 睡觉后等级可能变了（升级在工期里完成），道具要重建
func _rebuild_house_props() -> void:
	if room_id != &"house":
		return
	for child in get_children():
		if child is RoomProp:
			child.queue_free()
	_build_house_props()

## 做饭（Lv2）：消耗牛奶 + 鸡蛋 → 家常菜；当天动物友好度 +5（次日结算时生效）
func _cook() -> void:
	if GameState.house_level < 2:
		_say("还没有厨房 —— 先把房子升到 Lv2")
		return
	if GameState.has_buff(&"cooked", GameClock.day):
		_say("今天已经做过一顿了（一天一次）")
		return
	if GameState.count_item(&"milk") < 1 or GameState.count_item(&"egg") < 1:
		_say("要 牛奶×1 + 鸡蛋×1")
		return
	GameState.remove_item(&"milk", 1)
	GameState.remove_item(&"egg", 1)
	GameState.add_item(&"home_cooked", 1)
	GameState.set_buff(&"cooked", GameClock.day)
	GameState.set_buff(&"warm_meal", GameClock.day)
	_say("做了一份家常菜（放背包 · 可卖）· 今天动物会吃得很开心")
	_refresh_hud()

## 酿酒（Lv3）：消耗蜂蜜×2 → 蜂蜜酒
func _brew() -> void:
	if GameState.house_level < 3:
		_say("还没有地窖 —— 先把房子升到 Lv3")
		return
	if GameState.has_buff(&"brewed", GameClock.day):
		_say("今天已经酿过一轮了（一天一次）")
		return
	if GameState.count_item(&"honey") < 2:
		_say("要 蜂蜜×2")
		return
	GameState.remove_item(&"honey", 2)
	GameState.add_item(&"mead", 1)
	GameState.set_buff(&"brewed", GameClock.day)
	_say("酿出了一瓶蜂蜜酒（放背包 · 可卖）")
	_refresh_hud()

## 升级住宅（需求 3）：扣钱料 → 进工期（2/3 天）→ DayCycle 跨日推进 → 等级 +1
func _upgrade_house() -> void:
	var lv := GameState.house_level
	if GameState.house_upgrade_days > 0:
		_say("还在施工 · 剩 %d 天（睡一觉就会推进）" % GameState.house_upgrade_days)
		return
	var cost := HouseDB.upgrade_cost(lv)
	if cost.is_empty():
		_say("房子已经是最高级 Lv%d 了" % lv)
		return
	if GameState.gold < int(cost["gold"]):
		_say("要 %dG，还差 %dG" % [int(cost["gold"]), int(cost["gold"]) - GameState.gold])
		return
	if GameState.count_item(&"wood") < int(cost["wood"]) or \
			GameState.count_item(&"stone") < int(cost["stone"]):
		_say("还缺 木材×%d / 石头×%d" % [int(cost["wood"]), int(cost["stone"])])
		return
	GameState.spend_gold(int(cost["gold"]))
	GameState.remove_item(&"wood", int(cost["wood"]))
	GameState.remove_item(&"stone", int(cost["stone"]))
	GameState.house_upgrade_target = int(cost["to"])
	GameState.house_upgrade_days = int(cost["days"])
	_say("开工 · 「%s」%d 天后落成（睡 %d 觉）" % [cost["name"], int(cost["days"]),
		int(cost["days"])])
	_refresh_hud()

# ---------------- 家具摆放（需求 4 · 可选）----------------
#
# 规则压到最简：
#   F = 把背包里的家具放到脚下那一格（地毯 / 盆栽）
#   站在家具上按 F = 收回家具
# 家具的真源是 GameState.furniture（存档里带坐标），这里只画 + 改数据。

const FURNITURE := [&"rug", &"plant"]

func _furniture_action() -> void:
	var cell := WorldConfig.px_to_cell(_player.global_position)
	var here := GameState.take_furniture(cell)
	if here != &"":
		GameState.add_item(here, 1)
		_say("收起了 %s" % ItemDB.display_name(here))
		queue_redraw()
		return
	for id in FURNITURE:
		if GameState.count_item(id) > 0:
			if GameState.add_furniture(id, cell):
				GameState.remove_item(id, 1)
				_say("摆下了 %s（F 可以收回）" % ItemDB.display_name(id))
				queue_redraw()
			else:
				_say("这一格已经有家具了")
			return
	_say("背包里没有家具 —— 小镇杂货铺有卖")

func _draw_furniture() -> void:
	var tile := float(WorldConfig.TILE)
	for f in GameState.furniture:
		var id := StringName(str(f["id"]))
		var cell := Vector2i(int(f["x"]), int(f["y"]))
		var r := Rect2(Vector2(cell) * tile + Vector2(4, 4), Vector2(tile - 8, tile - 8))
		var col := Color("#C06A8A") if id == &"rug" else Color("#4F9A5E")
		draw_rect(r, col)
		draw_rect(r, col.lightened(0.25), false, 1.0)
## 矿洞里的机器：和模块 10 的 B 线咬在一起（有没有唤醒，台词不一样）
func _talk_machine() -> void:
	if GameState.story_flag(&"quest_secret_done"):
		_talk("会说话的机器", [
			"「你回来了。」",
			"「我把记得的都给你了。现在，轮到你替这座镇子记住。」",
		], Color("#5E5580"))
	elif GameState.story_flag(&"secret_machine_awake"):
		_talk("会说话的机器", [
			"「蜂蜜。还有牛奶。他说那是最诚实的两样。」",
			"「你带来了吗？」",
		], Color("#5E5580"))
	elif GameState.story_flag(&"secret_mine_open"):
		_talk("睡着的机器", [
			"（机器上有一格灯在闪，但没有任何声音。）",
			"（也许它需要别的东西才会开口。）",
		], Color("#5E5580"))
	else:
		_talk("睡着的机器", [
			"（一台锈得看不出用途的机器。老周说过晚上别来这儿。）",
		], Color("#5E5580"))

# ---------------- 商店（小镇杂货铺 = 第二处买卖）----------------
#
# 牧场上的商店是 main.gd 在管（模块 4/7）。这里是一个**独立的购买路径**：
# 只买不卖、只卖固定几种，货架 40 行，和主场景的完整交易互不影响。
# 为什么不把 main._on_buy 抄一遍：那是 80 行叠加了种子/肥料/动物/杂货四种语义的
# if-else 链，为了一个只卖消耗品的房间去复用它，代价比写一个 30 行的本地版本大。

func _open_shop() -> void:
	_shop_mode_buy = true
	_shop.open("杂货铺 · 小镇店（T 切回收）", _shop_entries(), "↑↓ 选 · E 买 · T 买卖切换 · Esc 关")

func _shop_entries() -> Array:
	var out: Array = []
	if _shop_mode_buy:
		for id in [&"feed", &"medicine", &"wood"]:
			var p := ProductDB.price(id)
			out.append({
				"id": id, "name": ProductDB.display_name(id), "price": p,
				"note": "有 %d" % GameState.count_item(id),
				"enabled": GameState.gold >= p,
				"reason": "" if GameState.gold >= p else "钱不够",
			})
		var disc := _medicine_discount()
		if disc > 0:
			for e in out:
				if e["id"] == &"medicine":
					e["price"] = maxi(1, int(floor(float(e["price"]) * (100.0 - float(disc)) / 100.0)))
					e["note"] = "%s · 小葵好感 -%d%%" % [e["note"], disc]
		return out
	# 回收模式：背包里能卖的
	for id in GameState.inventory.keys():
		if not ItemDB.is_sellable(id):
			continue
		var n := GameState.count_item(id)
		if n <= 0:
			continue
		var unit := Market.price(id, GameClock.season, GameClock.day)
		out.append({
			"id": id, "name": ItemDB.display_name(id), "price": unit,
			"note": "×%d · 行情 %+d%%" % [n, Market.delta_percent(id, GameClock.season, GameClock.day)],
			"enabled": true,
		})
	out.sort_custom(func(a, b): return int(a["price"]) > int(b["price"]))
	return out

func _medicine_discount() -> int:
	# 小葵 5 心的药剂半价在牧场的 main 里；房间场景没法读 main，
	# 所以拿 SavePanel/SceneRouter 里没有的东西一律按「没有折扣」处理 —— 宁可少给优惠，
	# 也不要读一个不存在的对象。折扣的完整来源见 NpcRegistry（存于 carry）。
	return 0

func _on_shop_buy(entry_id: StringName) -> void:
	if not _shop_mode_buy:
		return
	var p := ProductDB.price(entry_id)
	if not GameState.spend_gold(p):
		_say("钱不够（要 %dG）" % p)
		_refresh_shop()
		return
	GameState.add_item(entry_id, 1)
	_say("买了 1 份 %s（-%dG）" % [ProductDB.display_name(entry_id), p])
	_refresh_hud()

func _on_shop_sell(entry_id: StringName, all: bool) -> void:
	if _shop_mode_buy:
		return
	var have := GameState.count_item(entry_id)
	if have <= 0:
		return
	var n := have if all else 1
	var unit := Market.price(entry_id, GameClock.season, GameClock.day)
	GameState.remove_item(entry_id, n)
	GameState.add_gold(unit * n)
	GameState.bump_stat(GameState.ST_SOLD, n)
	_say("卖了 %s×%d · +%dG" % [ItemDB.display_name(entry_id), n, unit * n])
	_refresh_shop()

func _refresh_shop() -> void:
	if _shop != null and _shop.is_open():
		_shop.update_entries(_shop_entries())

func _on_mode_toggle() -> void:
	_shop_mode_buy = not _shop_mode_buy
	_refresh_shop()
	_say("切成%s模式" % ("购买" if _shop_mode_buy else "回收"))

# ---------------- 提示 / HUD ----------------

func _say(msg: String) -> void:
	if _tip == null:
		return
	_tip.text = msg
	_tip_until = Time.get_ticks_msec() / 1000.0 + 2.5

func _refresh_hud() -> void:
	if _hud == null:
		return
	var season: String = GameClock.SEASON_NAME[clampi(GameClock.season, 0, 3)]
	var title := RoomData.room_name(room_id)
	if room_id == &"house":
		title = "住宅 Lv%d「%s」· %s" % [GameState.house_level,
			HouseDB.name_of(GameState.house_level),
			HouseDB.features_text(GameState.house_level)]
	_hud.text = "%s\n第 %d 天 %s %s · %dG · 背包 %d/%d 格\nE 交互 · F 摆家具 · F5 存档 · F6 存档面板 · F9 读档" % [
		title, GameClock.day, season, GameClock.clock_text(), GameState.gold,
		GameState.used_slot_count(), GameState.slot_capacity()]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# 商店开着的时候 T 切买卖（ShopUI 自己不发这个信号，房间这边接一下）
		if _shop != null and _shop.is_open() and event.keycode == KEY_T:
			_on_mode_toggle()
			get_viewport().set_input_as_handled()
			return
		# 模块 12：屋内 F 摆/收家具
		if room_id == &"house" and event.keycode == KEY_F and not EventBus.ui_modal:
			_furniture_action()
			get_viewport().set_input_as_handled()
