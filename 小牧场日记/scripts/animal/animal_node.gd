class_name AnimalNode
extends Node2D
## 单只动物的渲染节点（scenes/animal.tscn 的根）
##
## 逻辑全在 AnimalState，这里只负责画。
## 若 assets/sprites/animals/<species>_32.png 存在就用真素材，否则 _draw() 占位。
## ⚠️ 与 FarmLayer 同一哲学：素材到位只改这一个文件，逻辑一行不动。

const C_COW_BODY := Color("#F2F0EA")
const C_COW_SPOT := Color("#3B3B3B")
const C_COW_HOOF := Color("#2A2A2A")
const C_CHICK_BODY := Color("#FFF6E0")
const C_CHICK_COMB := Color("#E04A3A")
const C_CHICK_BEAK := Color("#F2A93B")
const C_EYE := Color("#1E1E1E")

const C_HEART := Color("#E8536B")
const C_HUNGRY := Color("#F5C542")
const C_BUBBLE := Color("#FFFFFF")
const C_SICK := Color("#8E6BB5")

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

func _draw() -> void:
	if state == null:
		return
	var d := state.data()
	if d == null:
		return

	# 幼年 = 70% 缩放（GDD §3.2）
	var k := 1.0 if state.is_adult() else 0.7
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))

	if _has_sprite:
		draw_texture(_tex, Vector2(-16, -32))
	else:
		if d.is_poultry():
			_draw_chicken()
		else:
			_draw_cow()

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_badge()

# ---------------- 占位图形 ----------------

func _draw_cow() -> void:
	# 腿
	for lx in [-12, -6, 3, 9]:
		draw_rect(Rect2(lx, -7, 3, 7), C_COW_HOOF)
	# 身体
	draw_rect(Rect2(-14, -21, 28, 15), C_COW_BODY)
	draw_rect(Rect2(-10, -19, 7, 6), C_COW_SPOT)
	draw_rect(Rect2(2, -17, 6, 5), C_COW_SPOT)
	# 头
	draw_rect(Rect2(-19, -28, 12, 12), C_COW_BODY)
	draw_rect(Rect2(-17, -26, 3, 3), C_EYE)
	draw_rect(Rect2(-19, -30, 4, 3), C_COW_HOOF)   # 耳

func _draw_chicken() -> void:
	draw_rect(Rect2(-4, -3, 2, 3), C_CHICK_BEAK)   # 脚
	draw_rect(Rect2(2, -3, 2, 3), C_CHICK_BEAK)
	draw_rect(Rect2(-8, -15, 16, 13), C_CHICK_BODY) # 身体
	draw_rect(Rect2(2, -21, 9, 9), C_CHICK_BODY)    # 头
	draw_rect(Rect2(1, -24, 5, 4), C_CHICK_COMB)    # 冠
	draw_rect(Rect2(11, -18, 4, 3), C_CHICK_BEAK)   # 嘴
	draw_rect(Rect2(6, -20, 2, 2), C_EYE)
	draw_rect(Rect2(-9, -12, 4, 8), C_CHICK_BODY)   # 翅膀
	draw_rect(Rect2(9, -14, 4, 5), C_CHICK_COMB)    # 尾

# ---------------- 状态气泡 ----------------

func _draw_badge() -> void:
	var top := -34.0
	# 心数：一排小红方块
	var h := state.hearts()
	for i in range(h):
		draw_rect(Rect2(-10 + i * 2.2, top, 1.6, 3.0), C_HEART)
	# 需求图标
	var icon_y := top - 6.0
	if state.sick:
		draw_rect(Rect2(-2, icon_y, 4, 4), C_SICK)          # 生病
	elif state.product_ready:
		draw_rect(Rect2(-2.5, icon_y, 5, 5), C_BUBBLE)      # 可收
		draw_rect(Rect2(-1.5, icon_y + 1, 3, 3), C_HEART)
	elif state.is_hungry():
		draw_rect(Rect2(-2, icon_y, 4, 4), C_HUNGRY)        # 饿
