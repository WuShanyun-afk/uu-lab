class_name Herd
extends RefCounted
## 牧场动物集合（纯逻辑）
##
## 只管「一群动物」的增删查与整体跨日。单只动物的规则在 AnimalState。

var animals: Array[AnimalState] = []
var _rng := RandomNumberGenerator.new()
var _next_id: int = 1

func _init(rng_seed: int = 0) -> void:
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()

## 添加一只动物。species 未知返回 null。
func add(species: StringName, affection: int = 0, pos: Vector2 = Vector2.ZERO) -> AnimalState:
	if AnimalDB.get_animal(species) == null:
		return null
	var uid := StringName("%s_%d" % [species, _next_id])
	_next_id += 1
	var a := AnimalState.new(uid, species, _rng.randi())
	a.affection = clampi(affection, 0, AnimalState.MAX_AFFECTION)
	a.pos = pos
	animals.append(a)
	return a

func remove(uid: StringName) -> bool:
	for i in range(animals.size()):
		if animals[i].uid == uid:
			animals.remove_at(i)
			return true
	return false

func get_by_uid(uid: StringName) -> AnimalState:
	for a in animals:
		if a.uid == uid:
			return a
	return null

func count_species(species: StringName) -> int:
	var n := 0
	for a in animals:
		if a.species == species:
			n += 1
	return n

func size() -> int:
	return animals.size()

func total_hearts() -> int:
	var n := 0
	for a in animals:
		n += a.hearts()
	return n

## 全体跨日，汇总事件
func advance_day() -> Array:
	var events: Array = []
	for a in animals:
		events.append_array(a.advance_day())
	return events

## 离给定点最近的动物（半径内），没有返回 null
func nearest(pos: Vector2, radius: float) -> AnimalState:
	var best: AnimalState = null
	var best_d := radius
	for a in animals:
		var d := pos.distance_to(a.pos)
		if d <= best_d:
			best_d = d
			best = a
	return best
