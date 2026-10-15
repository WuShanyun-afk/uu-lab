extends Node2D
## 里程碑 1 + 2 + 3 主场景：草地占位 + 昼夜光照 + 农场 + 牧场动物 + HUD

const FIELD_TILES := Vector2i(24, 14)
const TILE := Vector2(32, 32)
## 牧场围栏区域（像素）
const PEN := Rect2(512, 64, 224, 192)
## 挤奶黄金窗口：6:00–9:00（minutes 0 = 6:00）
const MILK_WINDOW_MINUTES := 180

@onready var _player: Player = $World/YSortRoot/Player
@onready var _light: CanvasModulate = $CanvasModulate
@onready var _hud: Label = $UI/HUD
@onready var _tip: Label = $UI/Tip
@onready var _farm_layer: Node2D = $World/FarmLayer
@onready var _animal_layer: AnimalLayer = $World/YSortRoot/AnimalLayer

var _grid: FarmGrid
var _herd: Herd
var _last_tip := ""
var _tip_until := 0.0

func _ready() -> void:
	_grid = FarmGrid.new()
	_farm_layer.grid = _grid

	_herd = Herd.new(20261015)
	_setup_animals()
	_animal_layer.herd = _herd
	_animal_layer.rebuild()

	_player.tool_used.connect(_on_tool_used)
	EventBus.tick_advanced.connect(_on_tick)
	EventBus.phase_changed.connect(_on_phase)
	EventBus.day_advanced.connect(_on_day)
	EventBus.season_changed.connect(_on_season)
	EventBus.tool_changed.connect(_on_tool_changed)
	GameState.gold_changed.connect(_on_gold)
	GameState.inventory_changed.connect(_on_inventory)

	_refresh_light()
	_refresh_hud()
	_say("WASD 移动 · 1 锄头 2 水壶 3 种子 4 饲料 5 手 · E/左键 · F11 全屏")

func _process(_delta: float) -> void:
	_refresh_light()
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
	if GameState.count_item(&"feed") == 0:
		GameState.add_item(&"feed", 20)
	var cow1 := _herd.add(&"cow", 300, Vector2(576, 152))
	_herd.add(&"cow", 150, Vector2(664, 152))
	var c1 := _herd.add(&"chicken", 250, Vector2(560, 214))
	var c2 := _herd.add(&"chicken", 400, Vector2(620, 222))
	_herd.add(&"chicken", 100, Vector2(680, 208))
	for a in _herd.animals:
		a.debug_grow_adult()
	# 开局先给一次产出，方便立刻试「挤奶 / 捡蛋」
	if cow1 != null:
		cow1.product_ready = true
	if c1 != null:
		c1.product_ready = true
	if c2 != null:
		c2.product_ready = true

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
		var out := _grid.harvest(cell)
		if not out.is_empty():
			var c: CropData = CropDB.get_crop(out["id"])
			GameState.add_item(out["id"], out["count"])
			_say("收获 %s ×%d（%s）" % [c.display_name, out["count"], _quality_name(out["quality"])])
			_farm_layer.queue_redraw()
			_refresh_hud()
			return

	match tool:
		Player.Tool.HOE:
			if _grid.till(cell):
				_say("锄地")
				_farm_layer.queue_redraw()
		Player.Tool.CAN:
			if _grid.water(cell):
				_say("浇水")
				_farm_layer.queue_redraw()
		Player.Tool.SEED:
			var c: CropData = CropDB.get_crop(_player.selected_seed)
			if _grid.plant(cell, _player.selected_seed):
				_say("种下 %s（%d 天成熟）" % [c.display_name, c.grow_days])
				_farm_layer.queue_redraw()

func _quality_name(q: int) -> String:
	return ["基础", "银星", "金星"][q]

# ---------------- 动物交互（里程碑 3）----------------

func _handle_animal(tool: int) -> void:
	var a := _herd.nearest(_player.interact_point(), 46.0)
	if a == null:
		_say("附近没有动物（牧场在右边围栏里）")
		return
	var d := a.data()

	if tool == Player.Tool.FEED:
		if not a.is_hungry():
			_say("%s 已经吃饱了" % d.display_name)
			return
		if GameState.count_item(&"feed") <= 0:
			_say("没有干草饲料了")
			return
		GameState.remove_item(&"feed", 1)
		a.feed()
		_say("喂了%s，好感 +%d（%s）" % [d.display_name, AnimalState.FEED_AFFECTION, a.heart_label()])
	else:
		var in_window := GameClock.minutes < MILK_WINDOW_MINUTES
		var out := a.produce(in_window)
		if not out.is_empty():
			var pid: StringName = out["id"]
			GameState.add_item(pid, int(out["count"]))
			_say("获得 %s ×%d（%s）" % [ProductDB.display_name(pid), int(out["count"]), _quality_name(int(out["quality"]))])
		elif a.is_producing() and a.product_ready and d.timed_product and not in_window:
			_say("%s 现在挤不出奶（只有 6:00–9:00）" % d.display_name)
		elif a.pet():
			_say("抚摸%s，好感 +%d（%s）" % [d.display_name, AnimalState.PET_AFFECTION, a.heart_label()])
		else:
			_say("%s 今天不想被摸了" % d.display_name)

	_animal_layer.refresh()
	_refresh_hud()
	EventBus.animal_interacted.emit(a.uid, "feed" if tool == Player.Tool.FEED else "hand")

## 空手站在动物旁边时，底部提示当前动物的状态
func _show_hint() -> void:
	var a := _herd.nearest(_player.interact_point(), 46.0)
	if a == null:
		_tip.text = ""
		return
	var d := a.data()
	var st := "饱" if not a.is_hungry() else "饿"
	if a.sick:
		st = "生病"
	elif a.product_ready:
		st = "可收"
	_tip.text = "%s  %s  %s" % [d.display_name, a.heart_label(), st]

# ---------------- 时间 ----------------

func _on_day(_d: int, _s: int, _y: int) -> void:
	var events := _grid.advance_day()
	var aevents := _herd.advance_day()
	_farm_layer.queue_redraw()
	_animal_layer.refresh()
	EventBus.animal_events.emit(aevents)
	_refresh_hud()

	var withered := 0
	var died := 0
	for e in events:
		if e["type"] == "wither":
			withered += 1
		else:
			died += 1
	var sick := 0
	var hungry := 0
	for e in aevents:
		if e["type"] == "sick":
			sick += 1
		elif e["type"] == "hungry":
			hungry += 1
	var parts: Array = []
	if withered > 0 or died > 0:
		parts.append("作物枯萎 %d·枯死 %d" % [withered, died])
	if hungry > 0:
		parts.append("动物漏喂 %d" % hungry)
	if sick > 0:
		parts.append("动物生病 %d" % sick)
	if not parts.is_empty():
		_say(" | ".join(parts))

func _on_tick(_m: int) -> void:
	_refresh_hud()

func _on_phase(_old: int, _new: int) -> void:
	_refresh_hud()

func _on_season(_s: int) -> void:
	_refresh_hud()

func _on_tool_changed(_t: int) -> void:
	_refresh_hud()

func _on_gold(_g: int) -> void:
	_refresh_hud()

func _on_inventory(_id: StringName, _n: int) -> void:
	_refresh_hud()

# ---------------- HUD ----------------

func _refresh_light() -> void:
	_light.color = GameClock.light_color_at(GameClock.minutes)

func _item_name(id: StringName) -> String:
	var c: CropData = CropDB.get_crop(id)
	if c != null:
		return c.display_name
	if ProductDB.has(id):
		return ProductDB.display_name(id)
	return str(id)

func _refresh_hud() -> void:
	var inv := ""
	for id in GameState.inventory:
		inv += "%s×%d " % [_item_name(id), GameState.count_item(id)]
	if inv == "":
		inv = "空"
	var animals := "牛×%d 鸡×%d" % [_herd.count_species(&"cow"), _herd.count_species(&"chicken")]
	_hud.text = "第 %d 年 %s季 %d 日   %s   %s   💰%dG   工具[%s]\n动物[%s] 总心 %d   背包: %s" % [
		GameClock.year, GameClock.season_name(), GameClock.day,
		GameClock.clock_text(), GameClock.phase_name(),
		GameState.gold, Player.TOOL_LABEL[_player.current_tool],
		animals, _herd.total_hearts(), inv,
	]

func _say(msg: String) -> void:
	_tip.text = msg
	_tip_until = Time.get_ticks_msec() / 1000.0 + 2.5

# ---------------- 占位地面 + 牧场围栏 ----------------

func _draw() -> void:
	var light := Color("#7FC15E")
	var dark := Color("#76B857")
	for y in range(FIELD_TILES.y):
		for x in range(FIELD_TILES.x):
			draw_rect(Rect2(Vector2(x, y) * TILE, TILE), light if (x + y) % 2 == 0 else dark)
	_draw_pen()

func _draw_pen() -> void:
	# 牧场地面略浅
	draw_rect(PEN, Color("#8FC96A"))
	# 木栅栏
	var c := Color("#8B5A2B")
	var t := 3.0
	draw_rect(Rect2(PEN.position, Vector2(PEN.size.x, t)), c)
	draw_rect(Rect2(Vector2(PEN.position.x, PEN.end.y - t), Vector2(PEN.size.x, t)), c)
	draw_rect(Rect2(PEN.position, Vector2(t, PEN.size.y)), c)
	draw_rect(Rect2(Vector2(PEN.end.x - t, PEN.position.y), Vector2(t, PEN.size.y)), c)
	# 栅栏立柱
	for x in range(int(PEN.position.x), int(PEN.end.x), 32):
		draw_rect(Rect2(x, PEN.position.y - 2, 3, 7), c)
		draw_rect(Rect2(x, PEN.end.y - 5, 3, 7), c)
