class_name GardenDecor
extends Node2D
## 秘密花园的装饰层（模块 5 需求 5）—— 只画，不写数据
##
## 构成：
##   · 中心喷泉（三层石台 + 水）
##   · 一圈花坛（确定性摆放，不随机 —— 截图和测试都要能复现）
##   · **9 座觉醒石碑**：每个物种一座，觉醒的那座会亮起来（金色顶 + 该物种的颜色）
##   · 四条石板路
##
## ⚠️ 石碑的亮/灭来自 herd，所以本节点和 AnimalLayer 一样是「只读数据的渲染层」。
##    没解锁之前整层不画 —— 免得玩家在牧场边缘偷看到还没开放的内容。

var herd: Herd
var unlocked := false

func sync(p_herd: Herd, p_unlocked: bool) -> void:
	herd = p_herd
	unlocked = p_unlocked
	visible = p_unlocked
	queue_redraw()

## 某个物种觉醒了没（石碑亮不亮）
func is_species_awakened(species: StringName) -> bool:
	if herd == null:
		return false
	for a in herd.animals:
		if a.species == species and a.awakened:
			return true
	return false

func _draw() -> void:
	if not unlocked:
		return
	var center := WorldConfig.GARDEN_FOUNTAIN
	var stone := Color("#9A968C")
	var stone_dark := Color("#6E6A63")
	var water := Color("#5E8FB8")

	# 石板路（十字）
	draw_rect(Rect2(center.x - 8, WorldConfig.garden_rect().position.y + 6, 16,
		WorldConfig.garden_rect().size.y - 12), Color("#B9B4A6"))
	draw_rect(Rect2(WorldConfig.garden_rect().position.x + 6, center.y - 8,
		WorldConfig.garden_rect().size.x - 12, 16), Color("#B9B4A6"))

	# 花坛：一圈小方点（确定性，不随机）
	var total := AnimalDB.all_ids().size()
	var petals: Array[Color] = [Color("#E88BA8"), Color("#F2C14E"),
		Color("#8FC96A"), Color("#C9A6E8")]
	for i in range(total * 3):
		var a := TAU * float(i) / float(total * 3) + 0.12
		var p := center + Vector2(cos(a), sin(a)) * 62.0
		var c: Color = petals[i % 4]
		draw_rect(Rect2(p.x - 2, p.y - 2, 4, 4), c)

	# 喷泉
	draw_rect(Rect2(center.x - 26, center.y - 10, 52, 20), stone_dark)
	draw_rect(Rect2(center.x - 22, center.y - 14, 44, 18), stone)
	draw_rect(Rect2(center.x - 18, center.y - 12, 36, 10), water)
	draw_rect(Rect2(center.x - 6, center.y - 30, 12, 18), stone)
	draw_rect(Rect2(center.x - 4, center.y - 28, 8, 14), water)

	# 9 座觉醒石碑
	var ids := AnimalDB.all_ids()
	for i in range(ids.size()):
		_draw_stele(WorldConfig.stele_pos(i, ids.size()), ids[i], i)

## 单座石碑：底座 + 碑身 + 顶（觉醒 = 金顶 + 发光宝石，未觉醒 = 灰）
func _draw_stele(p: Vector2, species: StringName, index: int) -> void:
	var lit := is_species_awakened(species)
	var stone := Color("#9A968C") if lit else Color("#6E6A63")
	draw_rect(Rect2(p.x - 9, p.y - 4, 18, 8), stone.darkened(0.25))
	draw_rect(Rect2(p.x - 6, p.y - 30, 12, 28), stone)
	draw_rect(Rect2(p.x - 8, p.y - 34, 16, 5), Color("#F2C14E") if lit else Color("#57534C"))
	if lit:
		var c := Awakening.portrait(species)
		draw_rect(Rect2(p.x - 3, p.y - 24, 6, 6), c)
		draw_rect(Rect2(p.x - 5, p.y - 12, 10, 2), Color("#F2C14E"))
	else:
		# 未觉醒：碑面刻一个问号
		draw_rect(Rect2(p.x - 2, p.y - 24, 4, 2), Color("#3A3833"))
		draw_rect(Rect2(p.x + 0, p.y - 22, 2, 4), Color("#3A3833"))
		draw_rect(Rect2(p.x - 2, p.y - 17, 4, 2), Color("#3A3833"))
	# 序号（第几座），纯方块计数，不依赖字体
	for i in range(index + 1):
		draw_rect(Rect2(p.x - 6 + i * 2, p.y + 5, 1.5, 3), Color("#F2C14E") if lit else Color("#3A3833"))
