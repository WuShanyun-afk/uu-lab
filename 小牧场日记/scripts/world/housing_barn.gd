class_name HousingBarn
extends Interactable
## 棚舍建筑（模块 6 需求 A）—— 一个脚本，三种外形，三级成长
##
##   畜舍（barn）  红墙 + 木屋顶 + 双开大门      Lv2 加侧翼 · Lv3 加旗杆
##   禽舍（coop）  米墙 + 蓝顶 + 门洞            Lv2 加栖木 · Lv3 加烟囱
##   蜂箱（hive）  叠层木箱                      Lv2/3 加层 + 蜂群
##
## ⚠️ 本文件不碰 UI、不碰背包、不碰 herd：
##    按 E 只发 EventBus.housing_upgrade_requested(housing_id)，
##    「够不够钱、升到几级、容量多少」全在 main / HousingDB / Housing 里。
## ⚠️ `used_slots` 由 main 每次刷新时写入（它才持有 herd）。
##    建筑节点自己去摸 herd 就破坏零耦合了，而且 headless 测试也不好造。
##
## 尺寸与位置来自 WorldConfig.BARN_SLOTS / PEN_ZONES —— 画面和活动区同一份数据。

@export var housing_id: StringName = &"barn"

## 当前住了几只（main 写，这里只读来显示 "3/4 只"）
var used_slots: int = 0

func _ready() -> void:
	super()
	housing_id = StringName(housing_id)
	prompt_text = HousingDB.name_of(housing_id)
	add_to_group("housing_barn")

func level() -> int:
	return GameState.barn_level(housing_id)

func prompt() -> String:
	var nm := HousingDB.name_of(housing_id)
	var lv := level()
	if lv <= 0:
		return "E  建造%s（%s）" % [nm, HousingDB.cost_text(housing_id, 0)]
	var cap := HousingDB.capacity_at(housing_id, lv)
	var head := "%s %s" % [nm, HousingDB.slot_text(housing_id, lv, used_slots)]
	if lv >= HousingDB.max_level_of(housing_id):
		return "%s · 已满级" % head
	return "%s · E 扩建（%s）" % [head, HousingDB.cost_text(housing_id, lv)]

func interact(_player: Node) -> void:
	EventBus.housing_upgrade_requested.emit(housing_id)

# ---------------- 绘制 ----------------

func _draw() -> void:
	var lv := maxi(1, level())
	match String(housing_id):
		"coop":
			_draw_coop(lv)
		"hive":
			_draw_hive(lv)
		_:
			_draw_barn(lv)

## 红色谷仓（比玩家大一截：Lv1 宽 54、高 30，一眼能看出是「房子」）
## ⚠️ 等级成长只往上长（阁楼窗 / 旗杆），**不横向加侧翼** ——
##    侧翼会顶出围栏左边界（PEN.x = 512），画到栅栏外面去。
func _draw_barn(lv: int) -> void:
	var w := 54.0 + (lv - 1) * 5.0
	var h := 30.0 + (lv - 1) * 3.0
	var wall := Color("#C4553F")
	var dark := Color("#8F3A2B")
	var trim := Color("#F0E6D2")
	var roof := Color("#5C3A1E")

	# 主墙
	draw_rect(Rect2(-w * 0.5, -h, w, h), wall)
	draw_rect(Rect2(-w * 0.5 + 2, -h + 5, w - 4, 2.5), trim)      # 白腰带
	# 屋顶（梯形）
	draw_polygon(PackedVector2Array([
		Vector2(-w * 0.5 - 5, -h),
		Vector2(w * 0.5 + 5, -h),
		Vector2(w * 0.5 - 4, -h - 9),
		Vector2(-w * 0.5 + 4, -h - 9),
	]), PackedColorArray([roof]))
	# 双开大门
	draw_rect(Rect2(-11, -19, 22, 19), dark)
	draw_rect(Rect2(-10, -18, 9, 17), Color("#5C3A1E"))
	draw_rect(Rect2(1, -18, 9, 17), Color("#5C3A1E"))
	# 干草堆
	draw_rect(Rect2(w * 0.5 - 18, -11, 16, 11), Color("#D9C46A"))
	draw_rect(Rect2(w * 0.5 - 18, -11, 16, 2.5), Color("#C9A45B"))

	if lv >= 2:
		draw_rect(Rect2(-7, -h - 8, 14, 7), trim)              # 阁楼窗
		draw_rect(Rect2(-5, -h - 6, 10, 4), Color("#3A2A18"))
	if lv >= 3:
		draw_rect(Rect2(w * 0.5 - 4, -h - 26, 2, 18), Color("#6E6A63"))   # 旗杆
		draw_rect(Rect2(w * 0.5 - 4, -h - 26, 12, 7), Color("#E8C24A"))   # 旗
		draw_circle(Vector2(-w * 0.26, -h + 12), 3.5, trim)               # 圆窗

## 蓝色顶的禽舍
func _draw_coop(lv: int) -> void:
	var w := 50.0 + (lv - 1) * 5.0
	var h := 23.0 + (lv - 1) * 2.0
	var wall := Color("#E8DCC0")
	var roof := Color("#4E7FA8")
	var roof_hi := Color("#6E9CC4")
	var dark := Color("#8C7B5C")

	draw_rect(Rect2(-w * 0.5, -h, w, h), wall)
	draw_rect(Rect2(-w * 0.5, -h, w, 1.5), Color("#C9BC9C"))
	# 屋顶（两层矩形近似圆弧，像素风的老办法）
	draw_rect(Rect2(-w * 0.5 - 4, -h - 7, w + 8, 7), roof)
	draw_rect(Rect2(-w * 0.5 + 2, -h - 11, w - 4, 4), roof_hi)
	# 门洞 + 斜坡
	draw_rect(Rect2(-9, -14, 18, 14), Color("#3A2A18"))
	draw_rect(Rect2(-12, -3, 24, 3), dark)
	# 栖木
	draw_rect(Rect2(w * 0.5 - 16, -9, 14, 2.5), dark)
	if lv >= 2:
		draw_rect(Rect2(-w * 0.5 + 5, -8, 2, 8), dark)      # 栏杆
		draw_rect(Rect2(w * 0.5 - 7, -8, 2, 8), dark)
		draw_rect(Rect2(-w * 0.5 + 5, -10, w - 10, 2), dark)
	if lv >= 3:
		draw_rect(Rect2(w * 0.5 - 15, -h - 22, 7, 12), Color("#9C8A6E"))   # 烟囱
		draw_rect(Rect2(w * 0.5 - 16, -h - 23, 9, 2), Color("#6E6A63"))

## 叠层蜂箱
func _draw_hive(lv: int) -> void:
	var bw := 26.0 + lv * 3.0
	var bh := 8.0
	var layers := 1 + lv
	for i in range(layers):
		var y := -7.0 - (i + 1) * bh
		var c := Color("#C9A45B") if i % 2 == 0 else Color("#B08F4A")
		draw_rect(Rect2(-bw * 0.5, y, bw, bh - 1), c)
		draw_rect(Rect2(-bw * 0.5, y, bw, 1), Color("#8A6A32"))
	# 底座 + 入口
	draw_rect(Rect2(-bw * 0.5 - 2, -9, bw + 4, 3), Color("#6E5A34"))
	draw_rect(Rect2(-6, -8, 12, 8), Color("#3A2A18"))
	# 蜂群（Lv2 起多两只）
	var bee := Color("#E8C24A")
	var spots := [Vector2(-bw * 0.5 - 7, -18), Vector2(bw * 0.5 + 6, -14)]
	if lv >= 2:
		spots.append(Vector2(bw * 0.5 + 9, -23))
	if lv >= 3:
		spots.append(Vector2(-bw * 0.5 - 10, -27))
	for p in spots:
		draw_rect(Rect2(p.x, p.y, 3, 2), bee)
		draw_rect(Rect2(p.x + 1, p.y - 1, 1, 1), Color("#3A2A18"))
