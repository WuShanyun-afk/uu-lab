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
## 模块 10：靠 NPC 好感解锁的秘方（6 列，多两列解锁条件）
const SECRET_CSV := "res://data/secret_recipes.csv"

var recipes: Dictionary = {}     ## StringName(output) -> Dictionary（含秘方）
var by_input: Dictionary = {}    ## StringName(input)  -> StringName(output)
## StringName(output) -> Dictionary（只有秘方）—— 带 npc / hearts 解锁条件
var secrets: Dictionary = {}

func _ready() -> void:
	load_csv()

func load_csv() -> void:
	recipes.clear()
	by_input.clear()
	secrets.clear()
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
	_load_secrets()
	print("[RecipeDB] 载入 %d 条配方（另有 %d 条待好感解锁）" % [
		recipes.size() - secrets.size(), secrets.size()])

func _load_secrets() -> void:
	var f := FileAccess.open(SECRET_CSV, FileAccess.READ)
	if f == null:
		return                       # 没有秘方表也能跑（模块 7 的老存档 / 老测试）
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 6:
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
			"npc": StringName(row[4].strip_edges()),
			"hearts": maxi(1, int(row[5])),
			"secret": true,
		}
		recipes[r["output"]] = r
		secrets[r["output"]] = r
		# 秘方不进 by_input 的反查表：一个原料只能有一条「默认配方」，
		# 否则放牛奶会同时冒出奶酪和香草奶酪两个选项（放料面板就变成选单了）。

func has(output_id: StringName) -> bool:
	return recipes.has(output_id)

func get_recipe(output_id: StringName) -> Dictionary:
	return recipes.get(output_id, {})

## 原料 → 能做的加工品 id（做不了返回 &""）
func recipe_for_input(input_id: StringName) -> StringName:
	var base: StringName = CropQuality.split(input_id)["id"]
	return by_input.get(base, &"")

## 基础配方（**不含**秘方）。
## ⚠️ 模块 7 的测试把这里钉死成 11 条 —— 加秘方不许改这个函数的口径，
##    否则「模块 10 上线后模块 7 的验收单突然变红」。
func all_ids() -> Array:
	var out: Array = []
	for id in recipes:
		if not secrets.has(id):
			out.append(id)
	return out

## 全部配方（含秘方）—— 加工坊面板、调试用
func all_ids_all() -> Array:
	return recipes.keys()

func is_secret(output_id: StringName) -> bool:
	return secrets.has(output_id)

## 秘方的解锁条件 {npc, hearts}；不是秘方返回 {}
func secret_of(output_id: StringName) -> Dictionary:
	return secrets.get(output_id, {})

## 这个配方现在能不能用（秘方要 GameState 里登记过解锁）
func is_unlocked(output_id: StringName) -> bool:
	if not secrets.has(output_id):
		return true
	return GameState.is_recipe_unlocked(output_id)

## 当前可用的配方（基础 + 已解锁秘方）
func available_ids() -> Array:
	var out: Array = []
	for id in recipes:
		if is_unlocked(id):
			out.append(id)
	return out

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
