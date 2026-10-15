extends Node
## 全局状态：金币、背包、统计（GDD §10.2 autoload: GameState）

signal gold_changed(value: int)
signal inventory_changed(item_id: StringName, count: int)

var gold: int = 500
var inventory: Dictionary = {}     ## StringName -> int

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

func reset() -> void:
	gold = 500
	inventory.clear()
	gold_changed.emit(gold)
