class_name InventoryUI
extends Control
## 背包面板（模块 7 需求 1）—— 堆叠 / 拖拽 / 使用
##
## 结构：
##   InventoryUI（Control，全屏锚点，只管布局与键盘）
##     └─ ItemSlot × 容量（每个 26×26，鼠标拖拽由 Godot 的 Control 拖拽系统接管）
##
## 三套操作并存，因为游戏是键盘驱动、但背包天生适合鼠标：
##   · 键盘：方向键 / WASD 选格 · E 使用 · X 丢 1 个 · I / Esc 关
##   · 鼠标：左键点选 · 右键使用 · **拖拽换位 / 合并**
##
## 为什么拖拽走 move_slot 而不是「交换 item id」：
##   同 id 拖到同 id 上要**合并**（受 stack_max 限制，可能合不完），
##   拖到空格要**移动**，拖到不同 id 上要**交换** —— 三条分支写在 GameState.move_slot 里，
##   UI 只负责把 (from, to) 丢过去。UI 里写业务，测试就没法断言了。
##
## ⚠️ 打开的那一帧屏蔽输入（同 ShopUI 的坑：E 会被同一个 InputEvent 再吃一次）。
## ⚠️ 中文物品名不画在格子里（draw_string 缺字），放底部信息条用 Label。

signal use_requested(index: int)
signal drop_requested(index: int)

const COLS := 8
const CELL := ItemSlot.SIZE
const GAP := 2
const PAD := 11
const TITLE_H := 20
const INFO_H := 16
const HINT_H := 14

var _slots: Array = []
var _cursor := 0
var _open := false
var _open_frame := -1

var _bg: ColorRect
var _title: Label
var _info: Label
var _hint: Label
var _grid: Control
var _panel_size := Vector2.ZERO

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_shell()
	visible = false
	GameState.slots_changed.connect(_on_slots_changed)

func _build_shell() -> void:
	_bg = ColorRect.new()
	_bg.color = Color(0.05, 0.06, 0.09, 0.95)
	add_child(_bg)

	_grid = Control.new()
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grid)

	_title = _label(12)
	_info = _label(9)
	_hint = _label(8)

func _label(fs: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	add_child(l)
	return l

# ---------------- 开关 ----------------

func is_open() -> bool:
	return _open

func open() -> void:
	if _open:
		return
	_rebuild()
	_open = true
	_open_frame = Engine.get_process_frames()
	visible = true
	EventBus.set_ui_modal(true)
	_refresh()

func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	EventBus.set_ui_modal(false)

func toggle() -> void:
	if _open:
		close()
	else:
		open()

# ---------------- 布局 ----------------

func _rebuild() -> void:
	var cap := GameState.slot_capacity()
	var rows := int(ceil(float(cap) / float(COLS)))
	var grid_w := COLS * CELL + (COLS - 1) * GAP
	var grid_h := rows * CELL + (rows - 1) * GAP
	var w := grid_w + PAD * 2
	var h := TITLE_H + grid_h + INFO_H + HINT_H + PAD + 8
	_panel_size = Vector2(w, h)

	# 居中偏上：面板别压住底部工具条
	var pos := Vector2(roundf((640.0 - w) * 0.5), 36.0)
	_bg.position = pos
	_bg.size = _panel_size
	_bg.color = Color(0.05, 0.06, 0.09, 0.95)

	_title.position = pos + Vector2(PAD, 4)
	_title.size = Vector2(w - PAD * 2, TITLE_H - 4)

	_grid.position = pos + Vector2(PAD, TITLE_H)

	_info.position = pos + Vector2(PAD, TITLE_H + grid_h + 4)
	_info.size = Vector2(w - PAD * 2, INFO_H)

	_hint.position = pos + Vector2(PAD, TITLE_H + grid_h + 4 + INFO_H)
	_hint.size = Vector2(w - PAD * 2, HINT_H)

	# 格子：容量变了就重建（扩容 40 → 48）
	while _slots.size() < cap:
		var s := ItemSlot.new()
		s.index = _slots.size()
		s.board = self
		s.position = Vector2(
			(s.index % COLS) * (CELL + GAP),
			floori(float(s.index) / float(COLS)) * (CELL + GAP))
		_grid.add_child(s)
		_slots.append(s)
	while _slots.size() > cap:
		var s: ItemSlot = _slots.pop_back()
		s.queue_free()

# ---------------- 数据同步 ----------------

func _on_slots_changed() -> void:
	if not _open:
		return
	# 扩容后格子数变了 —— 直接重建一次布局最省事
	if _slots.size() != GameState.slot_capacity():
		_rebuild()
	_refresh()

func _refresh() -> void:
	if _slots.is_empty():
		return
	_cursor = clampi(_cursor, 0, _slots.size() - 1)
	for i in range(_slots.size()):
		var s: ItemSlot = _slots[i]
		s.set_item(GameState.slot_item(i), GameState.slot_amount(i))
		s.set_highlight(i == _cursor)
	_title.text = "背包 %d/%d 格 · %d 种物品" % [
		GameState.used_slot_count(), GameState.slot_capacity(),
		GameState.inventory.size()]
	var id := GameState.slot_item(_cursor)
	if id == &"":
		_info.text = "空格 —— 把物品拖到别的格可以换位 / 合并"
	else:
		var d := ItemDB.resolve(id)
		var unit := Market.price(id, GameClock.season, GameClock.day)
		_info.text = "%s ×%d · 单价 %dG%s%s" % [
			ItemDB.display_name(id), GameState.slot_amount(_cursor), unit,
			"" if d == null or d.note == "" else " · " + d.note,
			"" if d == null else " · 堆叠上限 %d" % d.stack_max]
	_hint.text = "←→↑↓ 选格 · E 使用 · X 丢 1 个 · 拖拽换位/合并 · I 或 Esc 关闭"

# ---------------- 输入 ----------------

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if Engine.get_process_frames() == _open_frame:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_LEFT, KEY_A:
			_move_cursor(-1)
		KEY_RIGHT, KEY_D:
			_move_cursor(1)
		KEY_UP, KEY_W:
			_move_cursor(-COLS)
		KEY_DOWN, KEY_S:
			_move_cursor(COLS)
		KEY_E, KEY_ENTER, KEY_KP_ENTER:
			use_index(_cursor)
		KEY_X, KEY_DELETE:
			drop_requested.emit(_cursor)
		KEY_I, KEY_ESCAPE, KEY_Q:
			close()
		_:
			return
	get_viewport().set_input_as_handled()

func _move_cursor(step: int) -> void:
	if _slots.is_empty():
		return
	_cursor = posmod(_cursor + step, _slots.size())
	_refresh()

func set_cursor(i: int) -> void:
	if i < 0 or i >= _slots.size():
		return
	_cursor = i
	_refresh()

func cursor_index() -> int:
	return _cursor

# ---------------- 操作 ----------------

## 使用当前格：UI 不做判定，只把 index 丢给 main
## （「种子 = 换成当前种子」「饲料 = 对着动物喂」这些语义属于玩法层）
func use_index(i: int) -> void:
	if i < 0 or i >= _slots.size():
		return
	if GameState.slot_item(i) == &"":
		return
	_cursor = i
	_refresh()
	use_requested.emit(i)

## 拖拽落下
func on_drop(from: int, to: int) -> void:
	var r := GameState.move_slot(from, to)
	if r == "noop":
		return
	_cursor = to
	_refresh()
