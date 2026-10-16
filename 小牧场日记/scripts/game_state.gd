extends Node
## 全局状态：金币、背包、统计、进度标记（GDD §10.2 autoload: GameState）
##
## 模块 5 加了两个**进度标记**：秘密花园是否解锁、繁殖棚是否盖好。
## 为什么不放在 main 里：藤蔓门 / 繁殖棚这些可交互物要读它们来写提示文案，
## 而它们不该持有 main 的引用（零耦合）。标记放全局，谁都能查。

signal gold_changed(value: int)
signal inventory_changed(item_id: StringName, count: int)
## 进度标记变化（名字, 新值）—— 想联动的系统订阅它，不用轮询
signal flag_changed(name: StringName, value: bool)

var gold: int = 500
var inventory: Dictionary = {}     ## StringName -> int

## 进度标记（模块 5）
var garden_unlocked: bool = false
var shed_built: bool = false

func add_gold(n: int) -> void:
	gold += n
	gold_changed.emit(gold)

func spend_gold(n: int) -> bool:
	if gold < n:
		return false
	gold -= n
	gold_changed.emit(gold)
	return true

func add_item(id: StringName, n: int = 1) -> void:
	inventory[id] = count_item(id) + n
	inventory_changed.emit(id, inventory[id])

func count_item(id: StringName) -> int:
	return int(inventory.get(id, 0))

func remove_item(id: StringName, n: int = 1) -> bool:
	var have := count_item(id)
	if have < n:
		return false
	inventory[id] = have - n
	if int(inventory[id]) <= 0:
		inventory.erase(id)
	inventory_changed.emit(id, count_item(id))
	return true

# ---------------- 进度标记 ----------------

func set_flag(name: StringName, value: bool) -> void:
	match name:
		&"garden_unlocked":
			garden_unlocked = value
		&"shed_built":
			shed_built = value
		_:
			return
	flag_changed.emit(name, value)

func has_flag(name: StringName) -> bool:
	match name:
		&"garden_unlocked":
			return garden_unlocked
		&"shed_built":
			return shed_built
	return false

func reset() -> void:
	gold = 500
	inventory.clear()
	garden_unlocked = false
	shed_built = false
	gold_changed.emit(gold)
