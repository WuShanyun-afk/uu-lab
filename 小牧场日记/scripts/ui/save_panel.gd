extends CanvasLayer
## 多存档位面板（模块 11 需求 2）—— autoload: SavePanel
##
## 为什么做成 autoload 而不是塞进某个场景：
##   `change_scene_to_file` 会把当前场景整个 free 掉。如果存档面板是场景里的节点，
##   那么在「房间里存档 → 读档回到牧场」这条路上，面板会在换场瞬间消失，
##   玩家看到的是「面板闪了一下就没了」。autoload 挂在 root 上，换场不影响它。
##
## 槽位（SaveSystem）：
##   0 自动存档（每天 2:00 跨日自动写，面板里只读）
##   1 快速存档（F5 写 / F9 读）
##   2–5 手动存档（本面板的 S/L/D 操作对象）
##
## 键位：F6 开关面板 · ↑↓ 选槽 · S 保存 · L 读取 · D 删除 · Esc 关
##      F5 快速存档 · F9 读最近的档（不打开面板）
##
## ⚠️ 面板打开时 set_ui_modal(true)：否则玩家在面板背后还能走动 / 用工具。
##    Esc 关面板那一下同样要吃掉输入，别让它顺手把商店也关了。

const PANEL_POS := Vector2(24, 46)
const PANEL_SIZE := Vector2(592, 258)
const ROW_H := 26

var _open := false
var _pick: int = SaveSystem.SLOT_MANUAL_START

var _root: Control = null
var _title: Label = null
var _hint: Label = null
var _rows: Array[Label] = []

func _ready() -> void:
	layer = 50
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.color = Color(0.05, 0.06, 0.09, 0.94)
	bg.position = PANEL_POS
	bg.size = PANEL_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	_title = _label(Vector2(PANEL_POS.x + 12, PANEL_POS.y + 8),
		Vector2(PANEL_SIZE.x - 24, 20), 12)
	_title.text = "存档 · 读档"
	for i in range(SaveSystem.SLOT_MAX + 1):
		var l := _label(Vector2(PANEL_POS.x + 16, PANEL_POS.y + 34 + i * ROW_H),
			Vector2(PANEL_SIZE.x - 32, ROW_H - 4), 10)
		_rows.append(l)
	_hint = _label(Vector2(PANEL_POS.x + 12, PANEL_POS.y + PANEL_SIZE.y - 26),
		Vector2(PANEL_SIZE.x - 24, 18), 9)
	_hint.text = "↑↓ 选槽 · S 保存 · L 读取 · D 删除 · Esc 关闭    （0 号自动档只读）"
	_root.visible = false
	SceneRouter.save_finished.connect(_on_save_finished)
	SceneRouter.load_finished.connect(_on_load_finished)

func _label(pos: Vector2, size: Vector2, fs: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = size
	l.add_theme_font_size_override("font_size", fs)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(l)
	return l

# ---------------- 开关 ----------------

func is_open() -> bool:
	return _open

func open() -> void:
	if _open:
		return
	_open = true
	_root.visible = true
	EventBus.set_ui_modal(true)
	_refresh()

func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	EventBus.set_ui_modal(false)

func toggle() -> void:
	if _open:
		close()
	else:
		open()

# ---------------- 刷新 ----------------

func _refresh() -> void:
	_pick = clampi(_pick, 0, SaveSystem.SLOT_MAX)
	if _title != null:
		_title.text = "存档 · 读档    （当前场景：%s）" % SceneRouter.current_scene_name()
	for i in range(_rows.size()):
		var slot := i
		var mark := "▶" if slot == _pick else " "
		var lock := "（只读）" if slot == SaveSystem.SLOT_AUTO else ""
		_rows[i].text = "%s %-6s %s%s" % [mark, lock, SaveSystem.slot_label(slot),
			SceneRouter.slot_summary(slot)]
		_rows[i].add_theme_color_override("font_color",
			Color("#FFDD88") if slot == _pick else Color("#D8D2C0"))

# ---------------- 动作 ----------------

func save_slot(slot: int) -> void:
	if slot == SaveSystem.SLOT_AUTO:
		return                    # 自动槽由跨日写入，手动不许覆盖
	var res := SceneRouter.save_session(slot)
	_refresh()
	# 提示通过信号回到当前场景的提示条（面板本身不抢 UI）

func load_slot(slot: int) -> void:
	var res := SceneRouter.load_session(slot)
	if not bool(res["ok"]):
		return
	close()                       # 换场 / 原地读档前先把面板收掉
	if not bool(res.get("switched", false)):
		_refresh()

func delete_slot(slot: int) -> void:
	if slot == SaveSystem.SLOT_AUTO:
		return
	SaveSystem.delete_slot(slot)
	_refresh()

func _on_save_finished(slot: int, ok: bool) -> void:
	EventBus.world_message.emit(("已存档 · %s" % SaveSystem.slot_label(slot)) if ok
		else "存档失败（%s）" % SaveSystem.slot_label(slot))

func _on_load_finished(slot: int, ok: bool) -> void:
	if ok:
		EventBus.world_message.emit("已读取 · %s" % SaveSystem.slot_label(slot))

# ---------------- 输入 ----------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F6:
			toggle()
			get_viewport().set_input_as_handled()
		KEY_F5:
			if not _open:
				save_slot(SaveSystem.SLOT_QUICK)
				get_viewport().set_input_as_handled()
		KEY_F9:
			if not _open:
				var slot := SceneRouter.latest_slot()
				if slot < 0:
					EventBus.world_message.emit("还没有存档 —— 先按 F5 存一个")
				else:
					load_slot(slot)
				get_viewport().set_input_as_handled()
		_:
			if not _open:
				return
			match event.keycode:
				KEY_UP:
					_pick = posmod(_pick - 1, SaveSystem.SLOT_MAX + 1)
					_refresh()
				KEY_DOWN:
					_pick = posmod(_pick + 1, SaveSystem.SLOT_MAX + 1)
					_refresh()
				KEY_S:
					save_slot(_pick)
				KEY_L:
					load_slot(_pick)
				KEY_D:
					delete_slot(_pick)
				KEY_ESCAPE, KEY_F6:
					close()
				_:
					return
			get_viewport().set_input_as_handled()
