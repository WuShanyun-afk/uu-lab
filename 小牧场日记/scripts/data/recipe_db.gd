extends Node
## 加工配方表（autoload: RecipeDB）—— 模块 7 需求 4
##
## 表结构（4 列）：output,input,count,minutes
##   output  加工出来的产物 id（必须是 products.csv 里 kind=crafted 的项）
##   input   吃掉的原料 id（畜产品）
##   count   一次吃掉几个
##   minutes 游戏分钟数（120 = 2 小时）
##
## 数值来自 GDD §5.1 的「原料 → 加工品」价格表：加工增值 ×2.3~2.5。
## 但**增值倍率不写在这里**，它由 products.csv 的两个价格自然决定 ——
## 想调平衡就调 products.csv 的加工品价，别在配方里再叠一层倍率。
##
## 一个原料只能有一条配方（原料 → 加工品是一对一）。
## 反查表 by_input 就是靠这个约束建的，多对一会让「放料」变成要选配方。

const CSV_PATH := "res://data/recipes.csv"

var recipes: Dictionary = {}     ## StringName(output) -> Dictionary
var by_input: Dictionary = {}    ## StringName(input)  -> StringName(output)

func _ready() -> void:
	load_csv()

func load_csv() -> void:
	recipes.clear()
	by_input.clear()
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		push_error("[RecipeDB] 打不开 " + CSV_PATH)
		return
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 4:
			continue
		var out_id := row[0].strip_edges()
		if out_id == "":
			continue
		var r := {
			"id": StringName(out_id),
			"output": StringName(out_id),
			"input": StringName(row[1].strip_edges()),
			"count": maxi(1, int(row[2])),
			"minutes": maxi(1, int(row[3])),
		}
		recipes[r["output"]] = r
		by_input[r["input"]] = r["output"]
	print("[RecipeDB] 载入 %d 条配方" % recipes.size())

func has(output_id: StringName) -> bool:
	return recipes.has(output_id)

func get_recipe(output_id: StringName) -> Dictionary:
	return recipes.get(output_id, {})

## 原料 → 能做的加工品 id（做不了返回 &""）
func recipe_for_input(input_id: StringName) -> StringName:
	var base: StringName = CropQuality.split(input_id)["id"]
	return by_input.get(base, &"")

func all_ids() -> Array:
	return recipes.keys()

## 展示用："牛奶×2 → 奶酪（2 小时）"
func describe(output_id: StringName) -> String:
	var r: Dictionary = get_recipe(output_id)
	if r.is_empty():
		return ""
	return "%s×%d → %s（%s）" % [
		ItemDB.display_name(r["input"]), int(r["count"]),
		ItemDB.display_name(r["output"]), minutes_text(int(r["minutes"]))]

## 120 → "2 小时"；90 → "1.5 小时"；30 → "30 分"
static func minutes_text(m: int) -> String:
	if m < 60:
		return "%d 分" % m
	var h := float(m) / 60.0
	if is_equal_approx(h, roundf(h)):
		return "%d 小时" % int(roundf(h))
	return "%.1f 小时" % h
