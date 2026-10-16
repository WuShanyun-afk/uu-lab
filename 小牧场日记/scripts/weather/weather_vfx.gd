class_name WeatherVFX
extends Node2D
## 天气视觉：屏幕空间的雨 / 雪 / 闪电 —— 全 _draw() 确定性绘制，零素材
##
## 挂在 UI CanvasLayer 里 → 坐标就是 640×360 视口坐标，不用管相机、不用管缩放。
## 必须是 UI 的**第一个子节点**，否则雨会盖住 HUD。

const VIEW := Vector2(640, 360)

@export var drops: int = 140

var _t: float = 0.0
var _flash: float = 0.0
var _rng := RandomNumberGenerator.new()
var _seed_x: PackedFloat32Array = PackedFloat32Array()
var _seed_y: PackedFloat32Array = PackedFloat32Array()

func _ready() -> void:
	_rng.seed = 20261021
	_seed_x.resize(drops)
	_seed_y.resize(drops)
	for i in range(drops):
		_seed_x[i] = _rng.randf()
		_seed_y[i] = _rng.randf()

func _process(delta: float) -> void:
	_t += delta
	var w: int = WeatherSystem.today
	if w == WeatherSystem.Weather.STORM and _rng.randf() < delta * 0.35:
		_flash = 0.22
	_flash = maxf(0.0, _flash - delta * 0.8)
	visible = (w == WeatherSystem.Weather.RAIN
		or w == WeatherSystem.Weather.STORM
		or w == WeatherSystem.Weather.SNOW
		or _flash > 0.0)
	if visible:
		queue_redraw()

func _draw() -> void:
	var w: int = WeatherSystem.today
	if w == WeatherSystem.Weather.RAIN or w == WeatherSystem.Weather.STORM:
		_draw_rain(w == WeatherSystem.Weather.STORM)
	elif w == WeatherSystem.Weather.SNOW:
		_draw_snow()
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, VIEW), Color(1, 1, 1, _flash))

## 雨 = 斜线。暴风雨更密更快更白。
func _draw_rain(heavy: bool) -> void:
	var n := drops if heavy else int(drops * 0.6)
	var speed := 620.0 if heavy else 430.0
	var slant := 0.35
	var col := Color(0.72, 0.82, 1.0, 0.55 if heavy else 0.40)
	var seg := 9.0 if heavy else 7.0
	for i in range(n):
		var x := fposmod(_seed_x[i] * VIEW.x + _t * 60.0 * slant, VIEW.x)
		var y := fposmod(_seed_y[i] * VIEW.y + _t * speed, VIEW.y + 40.0) - 20.0
		draw_line(Vector2(x, y), Vector2(x - seg * slant, y + seg), col, 1.0)

## 雪 = 漂移的 2×2 白点
func _draw_snow() -> void:
	var n := int(drops * 0.7)
	var col := Color(1, 1, 1, 0.85)
	for i in range(n):
		var drift := sin(_t * 0.8 + _seed_x[i] * 6.283) * 10.0
		var x := fposmod(_seed_x[i] * VIEW.x + drift, VIEW.x)
		var y := fposmod(_seed_y[i] * VIEW.y + _t * 42.0, VIEW.y + 12.0) - 6.0
		draw_rect(Rect2(x, y, 2, 2), col)
