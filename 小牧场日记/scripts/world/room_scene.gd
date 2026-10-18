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
	# 可交互物
	for p in RoomData.props_of(room_id):
		var prop := RoomProp.new()
		prop.name = "Prop_" + String(p["id"])
		add_child(prop)
		prop.setup(p["id"], p["action"], str(p["label"]),
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
			_talk("床", [
				"（被褥叠得很整齐，是妈妈留下的那种叠法。）",
				"（现在还不困 —— 先把今天的活干完吧。）",
			], Color("#7A6EA8"))
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
	_hud.text = "%s\n第 %d 天 %s %s · %dG · 背包 %d/%d 格\nE 交互 · F5 快速存档 · F6 存档面板 · F9 读档" % [
		RoomData.room_name(room_id),
		GameClock.day, season, GameClock.clock_text(), GameState.gold,
		GameState.used_slot_count(), GameState.slot_capacity()]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# 商店开着的时候 T 切买卖（ShopUI 自己不发这个信号，房间这边接一下）
		if _shop != null and _shop.is_open() and event.keycode == KEY_T:
			_on_mode_toggle()
			get_viewport().set_input_as_handled()
