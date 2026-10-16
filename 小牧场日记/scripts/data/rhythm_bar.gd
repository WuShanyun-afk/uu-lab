class_name RhythmBar
extends RefCounted
## 挤奶 / 剪毛的节奏条小游戏（模块 4 需求 4）—— 纯逻辑，可 headless 断言
##
## 一条 0..1 的轨道，指针往返跑，目标区随机落点。
## 指针在目标区里按 E：越靠中心分越高。
##
## 等级 → 产出加成（apply_result）：
##   PERFECT  产量 +1 · 品质 +1 档
##   GOOD     品质 +1 档
##   OK       无加成
##   MISS     产量 -1（最少 1）
##
## ⚠️ 本文件**不碰任何 UI**。渲染在 ui/minigame_ui.gd，只读 pos / zone_center / zone_width。
##    所以「打几分」这件事可以在 headless 里精确断言，不用起窗口。

enum Grade { MISS, OK, GOOD, PERFECT }

const GRADE_NAME := ["失手", "还行", "不错", "完美"]
## 分数阈值：score = 1 - 距中心距离/半宽（中心 1.0，边缘 0.0）
const PERFECT_SCORE := 0.80
const GOOD_SCORE := 0.50

var speed := 1.25          ## 指针每秒扫过的轨道比例
var zone_center := 0.5
var zone_width := 0.24
var pos := 0.0
var dir := 1.0
var running := false
var grade: int = Grade.MISS
var score := 0.0

var _rng := RandomNumberGenerator.new()

func _init(rng_seed: int = 0) -> void:
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()

## 开一局。目标区位置随机，指针从最左出发向右。
func start(zone_w: float = 0.24) -> void:
	zone_width = clampf(zone_w, 0.06, 0.6)
	zone_center = _rng.randf_range(0.25, 0.75)
	pos = 0.0
	dir = 1.0
	score = 0.0
	grade = Grade.MISS
	running = true

func tick(delta: float) -> void:
	if not running:
		return
	pos += dir * speed * delta
	if pos > 1.0:
		pos = 2.0 - pos
		dir = -1.0
	elif pos < 0.0:
		pos = -pos
		dir = 1.0

## 按下 E。返回结果字典；没在跑就直接返回当前结果。
func press() -> Dictionary:
	if not running:
		return result()
	var d := absf(pos - zone_center)
	var half := zone_width * 0.5
	if d > half:
		score = 0.0
		grade = Grade.MISS
	else:
		score = 1.0 - d / half
		if score >= PERFECT_SCORE:
			grade = Grade.PERFECT
		elif score >= GOOD_SCORE:
			grade = Grade.GOOD
		else:
			grade = Grade.OK
	running = false
	return result()

## 超时（指针跑满 N 个来回都没按）＝ 失手
func timeout() -> Dictionary:
	running = false
	score = 0.0
	grade = Grade.MISS
	return result()

func result() -> Dictionary:
	return {"grade": grade, "score": score, "label": grade_label()}

func grade_label() -> String:
	return GRADE_NAME[clampi(grade, 0, 3)]

## 指针现在在不在目标区里（渲染层用它决定高亮）
func in_zone() -> bool:
	return absf(pos - zone_center) <= zone_width * 0.5

## 把等级套到产出上。返回 {count, quality}
static func apply_result(g: int, count: int, quality: int) -> Dictionary:
	var c := count
	var q := quality
	match g:
		Grade.PERFECT:
			c += 1
			q += 1
		Grade.GOOD:
			q += 1
		Grade.MISS:
			c -= 1
	return {"count": maxi(1, c), "quality": clampi(q, 0, CropQuality.Level.GOLD)}
