class_name AnimalNode
extends Node2D
## 单只动物的渲染节点（scenes/animal.tscn 的根）
##
## 逻辑全在 AnimalState，这里只负责画。
## 若 assets/sprites/animals/<species>_32.png 存在就用真素材，否则 _draw() 占位。
## ⚠️ 与 FarmLayer 同一哲学：素材到位只改这一个文件，逻辑一行不动。
##
## 模块 4：占位图从「只会画牛和鸡」升级成**表驱动**——
##   9 种动物全部由 SPECIES_ART 里的一行描述决定（体型 / 颜色 / 骨架形态）。
##   加第 10 种动物 = 加一行表 + 加一行 CSV，不用写新的 _draw 分支。

const C_EYE := Color("#1E1E1E")
const C_HEART := Color("#E8536B")
const C_HUNGRY := Color("#F5C542")
const C_BUBBLE := Color("#FFFFFF")
const C_SICK := Color("#8E6BB5")
const C_COMB := Color("#E04A3A")
const C_BEAK := Color("#F2A93B")
const C_AWAKE := Color("#F2C14E")       ## 觉醒：金冠
const C_PREGNANT := Color("#E88BA8")    ## 妊娠：粉点

## 物种 → 占位外形描述
##   shape: quad 四足 / bird 禽类 / bug 虫（悬空）
##   w,h:   身体尺寸    neck: 脖子额外高度（羊驼）    fly: 整体抬高（蜜蜂）
const SPECIES_ART := {
	"cow": {"shape": "quad", "body": "#F2F0EA", "accent": "#3B3B3B", "w": 28.0, "h": 15.0, "neck": 0.0, "fly": 0.0},
	"goat": {"shape": "quad", "body": "#D8D3C6", "accent": "#7A6A55", "w": 24.0, "h": 13.0, "neck": 0.0, "fly": 0.0},
	"sheep": {"shape": "quad", "body": "#F7F3E6", "accent": "#6E6A63", "w": 26.0, "h": 17.0, "neck": 0.0, "fly": 0.0},
	"alpaca": {"shape": "quad", "body": "#D9B98A", "accent": "#8A6A42", "w": 22.0, "h": 13.0, "neck": 7.0, "fly": 0.0},
	"pig": {"shape": "quad", "body": "#F0A8AE", "accent": "#C97F86", "w": 26.0, "h": 14.0, "neck": 0.0, "fly": 0.0},
	"chicken": {"shape": "bird", "body": "#FFF6E0", "accent": "#E04A3A", "w": 16.0, "h": 13.0, "neck": 0.0, "fly": 0.0},
	"duck": {"shape": "bird", "body": "#F6F1DC", "accent": "#F2A93B", "w": 17.0, "h": 12.0, "neck": 0.0, "fly": 0.0},
	"turkey": {"shape": "bird", "body": "#A9744F", "accent": "#D94A3A", "w": 19.0, "h": 15.0, "neck": 0.0, "fly": 0.0},
	"bee": {"shape": "bug", "body": "#F2C14E", "accent": "#2A2A2A", "w": 11.0, "h": 8.0, "neck": 0.0, "fly": 9.0},
}

var state: AnimalState
var _tex: Texture2D = null
var _has_sprite := false

func setup(s: AnimalState) -> void:
	state = s
	var path := "res://assets/sprites/animals/%s_32.png" % String(s.species)
	if ResourceLoader.exists(path):
		_tex = load(path)
		_has_sprite = _tex != null
	position = s.pos
	queue_redraw()

func sync_pos() -> void:
	if state != null:
		position = state.pos

func art() -> Dictionary:
	if state == null:
		return SPECIES_ART["chicken"]
	return SPECIES_ART.get(String(state.species), SPECIES_ART["chicken"])

func _draw() -> void:
	if state == null:
		return
	var d := state.data()
	if d == null:
		return

	# 成长阶段（模块 5 需求 2）：幼崽 0.62 → 成年 1.0，按 days_old 线性长大
	# ⚠️ 不再写死 0.7 —— 缩放来自 AnimalState.body_scale()，逻辑层单测得到。
	var k := state.body_scale()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))

	var a := art()
	if _has_sprite:
		draw_texture(_tex, Vector2(-16, -32))
	else:
		match String(a["shape"]):
			"quad":
				_draw_quad(a)
			"bug":
				_draw_bug(a)
			_:
				_draw_bird(a)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_badge()

# ---------------- 占位图形（表驱动）----------------

func _draw_quad(a: Dictionary) -> void:
	var body := Color(a["body"])
	var accent := Color(a["accent"])
	var w := float(a["w"])
	var h := float(a["h"])
	var neck := float(a["neck"])
	var leg_h := 7.0
	# 腿
	for lx in [-w * 0.34, -w * 0.12, w * 0.12, w * 0.34]:
		draw_rect(Rect2(lx - 1.5, -leg_h, 3.0, leg_h), accent)
	# 身体
	draw_rect(Rect2(-w * 0.5, -leg_h - h, w, h), body)
	# 斑纹
	draw_rect(Rect2(-w * 0.28, -leg_h - h + 3.0, w * 0.22, h * 0.42), accent)
	draw_rect(Rect2(w * 0.06, -leg_h - h + 5.0, w * 0.2, h * 0.34), accent)
	# 头（羊驼靠 neck 把头顶上去）
	var hw := h * 0.85
	var hy := -leg_h - h - hw * 0.55 - neck
	if neck > 0.0:
		draw_rect(Rect2(-w * 0.42, hy + hw, hw * 0.5, neck + 2.0), body)   # 脖子
	draw_rect(Rect2(-w * 0.5 - hw * 0.35, hy, hw, hw), body)
	draw_rect(Rect2(-w * 0.5 - hw * 0.1, hy + hw * 0.35, 2.0, 2.0), C_EYE)
	draw_rect(Rect2(-w * 0.5 - hw * 0.35, hy - 3.0, 4.0, 3.0), accent)     # 耳
	# 尾
	draw_rect(Rect2(w * 0.5 - 1.0, -leg_h - h + 2.0, 3.0, 5.0), accent)

func _draw_bird(a: Dictionary) -> void:
	var body := Color(a["body"])
	var accent := Color(a["accent"])
	var w := float(a["w"])
	var h := float(a["h"])
	draw_rect(Rect2(-4.0, -3.0, 2.0, 3.0), C_BEAK)                          # 脚
	draw_rect(Rect2(2.0, -3.0, 2.0, 3.0), C_BEAK)
	draw_rect(Rect2(-w * 0.5, -h - 2.0, w, h), body)                        # 身体
	draw_rect(Rect2(w * 0.18, -h - 2.0 - h * 0.62, w * 0.56, h * 0.68), body) # 头
	draw_rect(Rect2(w * 0.12, -h - 5.0 - h * 0.62, w * 0.3, 3.0), accent)   # 冠
	draw_rect(Rect2(w * 0.74, -h - 2.0 - h * 0.34, 4.0, 3.0), C_BEAK)       # 嘴
	draw_rect(Rect2(w * 0.44, -h - 2.0 - h * 0.4, 2.0, 2.0), C_EYE)
	draw_rect(Rect2(-w * 0.58, -h + 1.0, 4.0, h * 0.55), body)              # 翅
	draw_rect(Rect2(w * 0.42, -h - 2.0, 4.0, 5.0), accent)                  # 尾

func _draw_bug(a: Dictionary) -> void:
	var body := Color(a["body"])
	var accent := Color(a["accent"])
	var w := float(a["w"])
	var h := float(a["h"])
	var fly := float(a["fly"])
	var y := -fly
	draw_rect(Rect2(-w * 0.5, y - h, w, h), body)
	draw_rect(Rect2(-w * 0.22, y - h, 1.6, h), accent)                      # 条纹
	draw_rect(Rect2(w * 0.06, y - h, 1.6, h), accent)
	draw_rect(Rect2(-w * 0.3, y - h - 3.0, w * 0.7, 3.0), Color(1, 1, 1, 0.5))  # 翅膀
	draw_rect(Rect2(-w * 0.5, y - h, w, 1.0), C_EYE)

# ---------------- 状态气泡 ----------------

func _draw_badge() -> void:
	var top := -34.0
	var a := art()
	if String(a["shape"]) == "bug":
		top -= float(a["fly"])
	# 心数：一排小红方块
	var h := state.hearts()
	for i in range(h):
		draw_rect(Rect2(-10 + i * 2.2, top, 1.6, 3.0), C_HEART)
	# 觉醒金冠（模块 5 需求 1）—— 画在心数上面一排，一眼能扫出「谁醒了」
	if state.awakened:
		draw_rect(Rect2(-5, top - 5.0, 10, 2.0), C_AWAKE)
		for i in range(3):
			draw_rect(Rect2(-5 + i * 4.0, top - 8.0, 2.0, 3.0), C_AWAKE)
	# 需求图标
	var icon_y := top - 6.0
	if state.awakened:
		icon_y -= 5.0
	if state.sick:
		draw_rect(Rect2(-2, icon_y, 4, 4), C_SICK)          # 生病
	elif state.product_ready:
		draw_rect(Rect2(-2.5, icon_y, 5, 5), C_BUBBLE)      # 可收
		draw_rect(Rect2(-1.5, icon_y + 1, 3, 3), C_HEART)
	elif state.is_hungry():
		draw_rect(Rect2(-2, icon_y, 4, 4), C_HUNGRY)        # 饿
	# 妊娠中：脚边一颗粉点
	if state.is_pregnant():
		draw_rect(Rect2(-1.5, 1.0, 3.0, 3.0), C_PREGNANT)
