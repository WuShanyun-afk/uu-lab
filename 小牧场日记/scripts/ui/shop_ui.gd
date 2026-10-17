class_name ShopUI
extends Control
## 通用商店面板（模块 4 / 模块 7 扩展）—— 种子 / 动物 / 杂货 / 工具 / 订单 / 繁殖 / 回收 共用同一个壳
##
## 为什么做成「通用」而不是每家店一个界面：商店只有三件事会变
##   ① 标题 ② 货架（entries）③ 谁来回调
## 所以本文件只管「显示 + 选择 + 把 id 丢出去」，成交逻辑一律由 main 决定。
## 加新商店（工具店 / 订单板 / 回收站）= 造一份 entries，零改动。
##
## entries 每一项：
##   {id: StringName, name: String, price: int, note: String,
##    enabled: bool, reason: String}
##
## 操作：↑↓ / W S 选择 · E / Enter 买下（SELL 模式 = 卖出）· Shift+E 全卖 · Esc / Q 关闭
##
## 模块 7 新增 **SELL 模式**：
##   面板本身不知道自己卖的是「买」还是「卖」，只按 mode 发不同信号：
##     BUY  → buy_requested(id)
##     SELL → sell_requested(id, all)   （all = 按着 Shift，整叠卖掉）
##   这样「回收站」和「种子店」还是同一个文件，不用分叉。
##
## ⚠️ 打开的那一帧必须屏蔽输入。玩家按 E 触发 Interactable 和本面板吃到的是
##    **同一个 InputEvent**，不屏蔽就会出现「一按 E 开了商店又立刻买了一件」。
## ⚠️ 用 Control 而不是 CanvasLayer：它是 UI 层里最后一个子节点，天然画在所有 HUD 之上，
##    省掉一层嵌套 CanvasLayer。

enum Mode { BUY, SELL }

signal buy_requested(entry_id: StringName)
signal sell_requested(entry_id: StringName, all: bool)
## 按 T 请求切「买 ↔ 卖」（只有杂货铺接；其他店忽略）
signal mode_toggle_requested()

const VISIBLE := 10
const PANEL := Rect2(96, 42, 448, 276)

var _title := ""
var _entries: Array = []
var _hint := ""
var _index := 0
var _open := false
var _open_frame := -1
var _mode: int = Mode.BUY

var _bg: ColorRect
var _title_label: Label
var _list_label: Label
var _hint_label: Label
var _gold_label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false
	GameState.gold_changed.connect(func(_g: int) -> void: _refresh())

func _build() -> void:
	_bg = ColorRect.new()
	_bg.position = PANEL.position
	_bg.size = PANEL.size
	_bg.color = Color(0.05, 0.06, 0.09, 0.94)
	add_child(_bg)

	_title_label = _make_label(Vector2(PANEL.position.x + 10, PANEL.position.y + 6), Vector2(PANEL.size.x - 20, 18), 12)
	_list_label = _make_label(Vector2(PANEL.position.x + 14, PANEL.position.y + 28), Vector2(PANEL.size.x - 28, 200), 10)
	_hint_label = _make_label(Vector2(PANEL.position.x + 10, PANEL.end.y - 34), Vector2(PANEL.size.x - 20, 16), 9)
	_gold_label = _make_label(Vector2(PANEL.position.x + 10, PANEL.end.y - 18), Vector2(PANEL.size.x - 20, 16), 9)
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func _make_label(pos: Vector2, size: Vector2, font_size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = size
	l.add_theme_font_size_override("font_size", font_size)
	add_child(l)
	return l

# ---------------- 开关 ----------------

func is_open() -> bool:
	return _open

func mode() -> int:
	return _mode

## 打开货架。hint 留空 = 按 mode 用默认提示
func open(title: String, entries: Array, hint: String = "", mode: int = Mode.BUY) -> void:
	_title = title
	_entries = entries
	_hint = hint
	_mode = mode
	_index = 0
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

func update_entries(entries: Array) -> void:
	_entries = entries
	_index = clampi(_index, 0, maxi(0, _entries.size() - 1))
	_refresh()

## 换标题（模块 5 繁殖棚用：选第一只 / 选第二只，标题要跟着变）
func update_title(title: String) -> void:
	_title = title
	_refresh()

func current_id() -> StringName:
	if _entries.is_empty():
		return &""
	return _entries[clampi(_index, 0, _entries.size() - 1)].get("id", &"")

func current_entry() -> Dictionary:
	if _entries.is_empty():
		return {}
	return _entries[clampi(_index, 0, _entries.size() - 1)]

# ---------------- 输入 ----------------

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	# 打开那一帧的 E 不能算「成交」
	if Engine.get_process_frames() == _open_frame:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_UP, KEY_W:
			_move(-1)
		KEY_DOWN, KEY_S:
			_move(1)
		KEY_PAGEUP:
			_move(-VISIBLE)
		KEY_PAGEDOWN:
			_move(VISIBLE)
		KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_confirm(event.shift_pressed)
		KEY_T:
			mode_toggle_requested.emit()
		KEY_ESCAPE, KEY_Q:
			close()
		_:
			return
	get_viewport().set_input_as_handled()

func _move(step: int) -> void:
	if _entries.is_empty():
		return
	_index = posmod(_index + step, _entries.size())
	_refresh()

func _confirm(shift: bool = false) -> void:
	if _entries.is_empty():
		return
	var e: Dictionary = _entries[_index]
	if not bool(e.get("enabled", true)):
		return
	var id: StringName = e.get("id", &"")
	if _mode == Mode.SELL:
		sell_requested.emit(id, shift)
	else:
		buy_requested.emit(id)

# ---------------- 渲染 ----------------

func _refresh() -> void:
	_title_label.text = _title
	var lines: Array[String] = []
	var first := 0
	if _entries.size() > VISIBLE:
		first = clampi(_index - VISIBLE / 2, 0, _entries.size() - VISIBLE)
	for i in range(first, mini(first + VISIBLE, _entries.size())):
		lines.append(_line(i, _entries[i]))
	if _entries.is_empty():
		lines.append("  （空）")
	_list_label.text = "\n".join(lines)
	_hint_label.text = _hint if _hint != "" else default_hint()
	_gold_label.text = "💰 %dG" % GameState.gold

func default_hint() -> String:
	if _mode == Mode.SELL:
		return "↑↓ 选择 · E 卖 1 个 · Shift+E 全卖 · Esc 关掉"
	return "↑↓ 选择 · E 买下 · Esc 关掉"

func _line(i: int, e: Dictionary) -> String:
	var mark := "▶ " if i == _index else "  "
	var s := "%s%s" % [mark, _pad(str(e.get("name", "")), 9)]
	# price = 0 表示「这一行不是买卖」（模块 5 繁殖棚是选动物），不显示价格列
	var price := int(e.get("price", 0))
	if price > 0:
		s += " %dG" % price
	var note := str(e.get("note", ""))
	if note != "":
		s += "   " + note
	if not bool(e.get("enabled", true)):
		var why := str(e.get("reason", ""))
		if why != "":
			s += "   ← " + why
	return s

## 按显示宽度补空格（中日韩字符算 2 格），让价格列能对齐
func _pad(s: String, width: int) -> String:
	var w := 0
	for i in range(s.length()):
		var c := s.unicode_at(i)
		w += 2 if (c >= 0x1100 and c <= 0xFF60) or (c >= 0x3000 and c <= 0x9FFF) else 1
	var out := s
	while w < width:
		out += " "
		w += 1
	return out
