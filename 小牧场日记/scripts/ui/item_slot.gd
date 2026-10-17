class_name ItemSlot
extends Control
## 背包里的**一格**（模块 7 需求 1：堆叠 / 拖拽 / 使用）
##
## 为什么单独一个 Control 类而不是 InventoryUI 自己 _draw 所有格子：
##   拖拽是 Control 级别的 API（_get_drag_data / _can_drop_data / _drop_data），
##   只有「一格 = 一个 Control」才能让 Godot 的拖拽系统替我们做命中测试。
##   在一个大 Control 里手搓拖拽，等于重新实现一遍鼠标捕获和 preview 跟随。
##
## 本类只负责「画自己 + 把拖拽事件转给 board」，所有数据变更都在 InventoryUI
## 和 GameState 里 —— 格子是纯展示层，不持有物品真源。
##
## ⚠️ 数量用 draw_string 画（纯数字，默认字体够用）；
##    物品**名字**不画在这里，放面板底部的信息条 —— 中文在 draw_string 里会缺字。

const SIZE := 26

var index: int = 0
var board: Node = null
var item_id: StringName = &""
var amount: int = 0
var highlighted: bool = false

func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP

func set_item(id: StringName, n: int) -> void:
	if id == item_id and n == amount:
		return
	item_id = id
	amount = n
	queue_redraw()

func set_highlight(on: bool) -> void:
	if highlighted == on:
		return
	highlighted = on
	queue_redraw()

func is_empty() -> bool:
	return item_id == &""

# ---------------- 绘制 ----------------

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(SIZE, SIZE))
	draw_rect(r, Color(0.10, 0.11, 0.15, 0.95))
	if is_empty():
		draw_rect(r, Color(0.28, 0.30, 0.36), false, 1.0)
		if highlighted:
			draw_rect(Rect2(1, 1, SIZE - 2, SIZE - 2), Color("#F2C14E"), false, 1.0)
		return
	var col := ItemDB.color_of(item_id)
	draw_rect(Rect2(4, 4, SIZE - 8, SIZE - 8), col)
	draw_rect(Rect2(4, 4, SIZE - 8, SIZE - 8), col.darkened(0.45), false, 1.0)
	# 品质星（银 / 金）画在右上角
	var q := ItemDB.quality_of(item_id)
	if q > 0:
		var sc: Color = CropQuality.STAR_COLOR[q]
		var pts := PackedVector2Array([
			Vector2(SIZE - 6, 3), Vector2(SIZE - 3, 6), Vector2(SIZE - 6, 9),
			Vector2(SIZE - 9, 6),
		])
		draw_colored_polygon(pts, sc)
	# 数量（>1 才画）
	if amount > 1:
		var txt := str(amount)
		var f: Font = ThemeDB.fallback_font
		var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		draw_string(f, Vector2(SIZE - w - 2, SIZE - 2), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("#FFFFFF"))
	# 边框：选中 = 金色
	draw_rect(r, Color("#F2C14E") if highlighted else Color(0.34, 0.36, 0.42), false,
		1.0 if not highlighted else 1.5)

# ---------------- 交互 ----------------

func _gui_input(event: InputEvent) -> void:
	if board == null:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			board.use_index(index)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			board.set_cursor(index)
			accept_event()

func _get_drag_data(_at: Vector2) -> Variant:
	if board == null or is_empty():
		return null
	board.set_cursor(index)
	# 拖动预览：跟着鼠标走的一小块色块 + 数量
	var pv := Control.new()
	pv.custom_minimum_size = Vector2(SIZE, SIZE)
	var cr := ColorRect.new()
	cr.position = Vector2(4, 4)
	cr.size = Vector2(SIZE - 8, SIZE - 8)
	cr.color = Color(ItemDB.color_of(item_id), 0.85)
	pv.add_child(cr)
	set_drag_preview(pv)
	return {"from": index}

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return board != null and data is Dictionary and data.has("from")

func _drop_data(_at: Vector2, data: Variant) -> void:
	if board == null:
		return
	board.on_drop(int(data["from"]), index)
