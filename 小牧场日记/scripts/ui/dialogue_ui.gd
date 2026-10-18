class_name DialogueUI
extends Control
## 对话框（模块 5 需求 1：觉醒的「拟人化对话」）—— 只显示 + 推进，不生产内容
##
## 内容全部来自 Awakening（数据表），本文件不知道什么是「奶牛」。
## 所以以后加 NPC 对话 / 剧情事件 = 造一份 lines，UI 一行不改。
##
## 接口：
##   show_dialogue(speaker, lines, color)   入队（正开着就排队，不会丢台词）
##   advance()                              下一句；最后一句再按一次 = 关掉
##   is_open() / current_line() / progress()
##
## 操作：E / 空格 / Enter 推进 · Esc 直接看完
##
## ⚠️ 和商店 / 节奏条同一个坑：打开那一帧的 E 必须屏蔽，
##    否则「按 E 喂到 10 心 → 弹对话 → 同一个 E 又把它翻页了」。

signal closed()

const PANEL := Rect2(24, 232, 592, 112)
const PORTRAIT_SIZE := 40.0
const PORTRAIT_POS := Vector2(34, 240)

var _queue: Array = []          ## 待播 [{speaker, lines, color}]
var _open := false
var _speaker := ""
var _lines: Array = []
var _index := 0
var _color := Color.WHITE
var _open_frame := -1

var _name_label: Label
var _text_label: Label
var _hint_label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false

func _build() -> void:
	# ⚠️ 面板底色在 _draw() 里画，不用 ColorRect 子节点 ——
	#    子节点在父节点 _draw() **之后**绘制，会把头像框整块盖住（节奏条踩过一次）。
	_name_label = _make_label(Vector2(PANEL.position.x + 84, PANEL.position.y + 8),
		Vector2(PANEL.size.x - 96, 18), 11)
	_text_label = _make_label(Vector2(PANEL.position.x + 84, PANEL.position.y + 30),
		Vector2(PANEL.size.x - 100, 56), 11)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label = _make_label(Vector2(PANEL.position.x + 10, PANEL.end.y - 20),
		Vector2(PANEL.size.x - 20, 16), 9)

func _make_label(pos: Vector2, size: Vector2, font_size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = size
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

# ---------------- 开关 ----------------

func is_open() -> bool:
	return _open

## 入队一句（或一组）台词。正开着对话就排队，播完自动接上。
func show_dialogue(speaker: String, lines: Array, color: Color = Color.WHITE) -> void:
	if lines.is_empty():
		return
	_queue.append({"speaker": speaker, "lines": lines, "color": color})
	if not _open:
		_next()

func _next() -> void:
	if _queue.is_empty():
		_open = false
		visible = false
		EventBus.set_ui_modal(false)
		queue_redraw()
		closed.emit()
		return
	var d: Dictionary = _queue.pop_front()
	_speaker = str(d["speaker"])
	_lines = d["lines"]
	_color = d.get("color", Color.WHITE)
	_index = 0
	if not _open:
		_open = true
		_open_frame = Engine.get_process_frames()
		visible = true
		EventBus.set_ui_modal(true)
	_refresh()
	queue_redraw()

## 下一句 / 关掉
func advance() -> void:
	if not _open:
		return
	_index += 1
	if _index >= _lines.size():
		_next()
	else:
		_refresh()
		queue_redraw()

## 直接看完这一组（Esc）
func skip() -> void:
	if not _open:
		return
	_next()

## 强制关掉（换场景 / 读档时用）：队列一起清，别让上一局的台词飘到新场景里
func close() -> void:
	_queue.clear()
	_open = false
	visible = false
	EventBus.set_ui_modal(false)
	queue_redraw()
	closed.emit()

func current_line() -> String:
	if not _open or _lines.is_empty():
		return ""
	return str(_lines[clampi(_index, 0, _lines.size() - 1)])

func progress() -> String:
	return "%d/%d" % [_index + 1, _lines.size()]

func pending_count() -> int:
	return _queue.size()

# ---------------- 输入 ----------------

func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if Engine.get_process_frames() == _open_frame:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_E, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			advance()
		KEY_ESCAPE, KEY_Q:
			skip()
		_:
			return
	get_viewport().set_input_as_handled()

# ---------------- 渲染 ----------------

func _refresh() -> void:
	_name_label.text = _speaker
	_text_label.text = current_line()
	_hint_label.text = "E 继续（%s）· Esc 跳过" % progress()

func _draw() -> void:
	if not _open:
		return
	draw_rect(PANEL, Color(0.05, 0.06, 0.09, 0.95))
	draw_rect(Rect2(PANEL.position, PANEL.size), Color("#6F7C8F"), false, 1.0)
	# 立绘：一个纯色方块 + 一行深色底边（零素材，颜色来自 Awakening 数据表）
	var pr := Rect2(PORTRAIT_POS, Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE))
	draw_rect(pr, _color)
	draw_rect(Rect2(pr.position, Vector2(pr.size.x, 4.0)), _color.darkened(0.35))
	draw_rect(pr, Color(0.05, 0.06, 0.09), false, 1.0)
	# 右下角「还有几句排队」
	var n := _queue.size()
	if n > 0:
		draw_rect(Rect2(PANEL.end.x - 12, PANEL.end.y - 10, 6, 4), Color("#F2C14E"))
