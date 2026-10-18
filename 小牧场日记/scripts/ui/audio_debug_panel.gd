extends CanvasLayer
## 音频调试面板 —— autoload: AudioDebugPanel（模块 附1）
##
## F3 开关，任何场景都能看。为什么做成调试面板而不是「设置菜单」：
##   · 设置菜单是给玩家调音量的，要等标题页 / 设置页那块做完；
##   · 现在真正需要的是**开发期自查**：为什么放的是这首 BGM、池子是不是快满了、
##     有没有缺素材、脚步为什么没响。这些信息用一行行字看最快，而且能截图当验收证据。
##
## 不参与玩法、不写存档：只读 AudioManager / GameClock / WeatherSystem / SceneRouter 的状态。

const PANEL_W := 300.0
const REFRESH := 0.2

var _open := false
var _box: PanelContainer
var _label: Label
var _accum := 0.0

func _ready() -> void:
	layer = 90                       # 压在 HUD 上面、模态 UI 下面
	_box = PanelContainer.new()
	_box.name = "AudioDebug"
	_box.position = Vector2(8, 132)
	_box.custom_minimum_size = Vector2(PANEL_W, 0)
	_box.visible = false
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.09, 0.88)
	style.border_color = Color(0.35, 0.75, 0.55, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	_box.add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 9)
	_label.add_theme_color_override("font_color", Color(0.85, 0.95, 0.88))
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_label)
	add_child(_box)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		set_open(not _open)
		get_viewport().set_input_as_handled()

func is_open() -> bool:
	return _open

func set_open(on: bool) -> void:
	_open = on
	_box.visible = on
	if on:
		_refresh()

func _process(delta: float) -> void:
	if not _open:
		return
	_accum += delta
	if _accum < REFRESH:
		return
	_accum = 0.0
	_refresh()

func _refresh() -> void:
	var st := AudioManager.stats()
	var recent: Array = AudioManager.recent_plays(3)
	var lines: Array = []
	lines.append("♪ 音频调试（F3 关闭）")
	lines.append("BGM  %s  [%s]" % [str(st["bgm"]), str(st["bgm_name"])])
	lines.append("选曲  %s" % str(st["explain"]))
	lines.append("环境  %s · 天气 %s / %s · 场景 %s" % [
		"雨" if str(st["ambience"]) != "" else "—", str(st["weather"]),
		str(st["phase"]), str(st["scene"])])
	lines.append("SFX   池 %d/%d 忙 · 2D %d/%d · 共 %d 声 · 拦下 %d" % [
		int(st["sfx_busy"]), int(st["sfx_voices"]), int(st["pos_busy"]), int(st["pos_voices"]),
		int(st["plays"]), _reject_total(st["rejects"])])
	lines.append("音量  主 %.2f  乐 %.2f  效 %.2f  环 %.2f" % [
		float(st["master"]), float(st["bgm_vol"]), float(st["sfx_vol"]), float(st["amb_vol"])])
	if recent.is_empty():
		lines.append("最近  （还没响过）")
	else:
		for r in recent:
			lines.append("最近  %s" % str(r))
	var missing := int(st["missing"])
	if missing > 0:
		lines.append("⚠ 缺素材 %d 条（跑 _uu/gen_audio.py）" % missing)
	_label.text = "\n".join(lines)

func _reject_total(rejects: Dictionary) -> int:
	var n := 0
	for k in rejects:
		n += int(rejects[k])
	return n
