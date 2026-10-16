class_name MinigameUI
extends Control
## 挤奶 / 剪毛的节奏条界面（模块 4 需求 4）—— 只画，不算
##
## 规则全在 RhythmBar（纯逻辑）。本文件读它的 pos / zone_center / zone_width 画一条轨道。
## 所以「指针在哪、打几分」可以在 headless 里断言，不用起窗口。
##
## 操作：E / 空格 出手 · Esc 放弃（放弃 = 不消耗产出，也不算失手）
## 超时（默认 4 秒）＝ 失手，避免玩家把界面晾在那儿。
##
## ⚠️ 和 ShopUI 同一个坑：打开那一帧的 E 必须屏蔽，否则「一按 E 开了又立刻出手」。

signal finished(grade: int, score: float)
signal cancelled()

const PANEL := Rect2(160, 166, 320, 86)
const TRACK := Rect2(178, 196, 284, 14)
const TIME_LIMIT := 4.0

var bar: RhythmBar

var _active := false
var _open_frame := -1
var _time_left := 0.0
var _title := ""

var _title_label: Label
var _hint_label: Label
var _result_label: Label
var _result_text := ""
var _close_at := -1.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar = RhythmBar.new()
	_build()
	visible = false

func _build() -> void:
	# ⚠️ 面板底色必须自己画，不能用 ColorRect 子节点：
	#    子节点在父节点 _draw() **之后**绘制，会把轨道整条盖住（踩过一次）。
	_title_label = _make_label(Vector2(PANEL.position.x + 10, PANEL.position.y + 5), Vector2(PANEL.size.x - 20, 16), 11)
	_hint_label = _make_label(Vector2(PANEL.position.x + 10, TRACK.end.y + 4), Vector2(PANEL.size.x - 20, 16), 9)
	_result_label = _make_label(Vector2(PANEL.position.x + 10, PANEL.end.y - 20), Vector2(PANEL.size.x - 20, 16), 10)

func _make_label(pos: Vector2, size: Vector2, font_size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = size
	l.add_theme_font_size_override("font_size", font_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

# ---------------- 开关 ----------------

func is_active() -> bool:
	return _active

func start(title: String) -> void:
	_title = title
	bar.start()
	_active = true
	_time_left = TIME_LIMIT
	_open_frame = Engine.get_process_frames()
	_result_text = ""
	_title_label.text = title
	_hint_label.text = "指针进亮区按 E —— 越靠中心越好 · Esc 放弃"
	_result_label.text = ""
	visible = true
	EventBus.set_ui_modal(true)
	queue_redraw()

func _finish(grade: int, score: float) -> void:
	_active = false
	_result_text = "%s（%.0f 分）" % [RhythmBar.GRADE_NAME[clampi(grade, 0, 3)], score * 100.0]
	_result_label.text = _result_text
	_hint_label.text = ""
	_time_left = 0.0
	EventBus.set_ui_modal(false)
	_close_at = Time.get_ticks_msec() / 1000.0 + 0.7     # 亮一下成绩再收
	queue_redraw()
	finished.emit(grade, score)

func _cancel() -> void:
	_active = false
	EventBus.set_ui_modal(false)
	visible = false
	queue_redraw()
	cancelled.emit()

# ---------------- 输入 / 计时 ----------------

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not _active:
		if _close_at > 0.0 and now >= _close_at:
			_close_at = -1.0
			visible = false
		return
	_time_left -= _delta
	if _time_left <= 0.0:
		bar.timeout()
		_finish(bar.grade, bar.score)
		return
	bar.tick(_delta)
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if Engine.get_process_frames() == _open_frame:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_E, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			bar.press()
			_finish(bar.grade, bar.score)
		KEY_ESCAPE, KEY_Q:
			_cancel()
		_:
			return
	get_viewport().set_input_as_handled()

# ---------------- 绘制 ----------------

func _draw() -> void:
	draw_rect(PANEL, Color(0.05, 0.06, 0.09, 0.94))
	draw_rect(Rect2(TRACK.position - Vector2(2, 2), TRACK.size + Vector2(4, 4)), Color("#1A1D24"))
	draw_rect(TRACK, Color("#2E3340"))
	# 目标区
	var zx := TRACK.position.x + (bar.zone_center - bar.zone_width * 0.5) * TRACK.size.x
	var zw := bar.zone_width * TRACK.size.x
	draw_rect(Rect2(zx, TRACK.position.y, zw, TRACK.size.y), Color("#3F6B45"))
	# 甜点（完美区）
	var half := bar.zone_width * 0.5
	var px := TRACK.position.x + (bar.zone_center - half * 0.2) * TRACK.size.x
	draw_rect(Rect2(px, TRACK.position.y, half * 0.4 * TRACK.size.x, TRACK.size.y), Color("#6FBF73"))
	# 指针
	var mx := TRACK.position.x + bar.pos * TRACK.size.x
	var mc := Color("#FFF6E0") if bar.in_zone() else Color("#C9CCD4")
	draw_rect(Rect2(mx - 1.5, TRACK.position.y - 3, 3, TRACK.size.y + 6), mc)
	# 剩余时间条
	if _active:
		var f := clampf(_time_left / TIME_LIMIT, 0.0, 1.0)
		draw_rect(Rect2(PANEL.position.x + 10, PANEL.end.y - 6, (PANEL.size.x - 20) * f, 2), Color("#F2C14E"))
