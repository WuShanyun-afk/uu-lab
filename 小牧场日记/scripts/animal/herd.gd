class_name Herd
extends RefCounted
## 牧场动物集合（纯逻辑）
##
## 只管「一群动物」的增删查与整体跨日。单只动物的规则在 AnimalState。
##
## 模块 5 新增三件事：
##   ① `advance_day()` 不只转发事件了 —— 它还要处理**生崽**（born → add）和**病逝**（died → remove）
##   ② `MAX_ANIMALS` 牧场上限（繁殖会一直加动物，总得有个屋顶）
##   ③ 觉醒统计（`awakened_species()` / `all_species_awakened()`）—— 秘密花园的解锁条件

const MAX_ANIMALS := 20

var animals: Array[AnimalState] = []
var _rng := RandomNumberGenerator.new()
var _next_id: int = 1

func _init(rng_seed: int = 0) -> void:
	if rng_seed != 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()

## 添加一只动物。species 未知 / 牧场满 返回 null。
func add(species: StringName, affection: int = 0, pos: Vector2 = Vector2.ZERO) -> AnimalState:
	if AnimalDB.get_animal(species) == null:
		return null
	if animals.size() >= MAX_ANIMALS:
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

func is_full() -> bool:
	return animals.size() >= MAX_ANIMALS

func total_hearts() -> int:
	var n := 0
	for a in animals:
		n += a.hearts()
	return n

## 全体好感 +n（雨天 / 雪天留棚奖励，GDD §3.3）
## ⚠️ 走 AnimalState.gain_affection()，不能直接写 affection ——
##    否则「留棚喂到 10 心」不会触发觉醒。
func add_affection_all(n: int) -> void:
	for a in animals:
		a.gain_affection(n)

# ---------------- 觉醒统计（模块 5 需求 1 / 5）----------------

## 已经觉醒的个体
func awakened_animals() -> Array[AnimalState]:
	var out: Array[AnimalState] = []
	for a in animals:
		if a.awakened:
			out.append(a)
	return out

## 至少有 1 只觉醒的物种（秘密花园按「物种」算，不按个体 —— 9 只全喂到 10 心太苦了）
func awakened_species() -> Array:
	var out: Array = []
	for a in animals:
		if a.awakened and not out.has(a.species):
			out.append(a.species)
	return out

func awakened_species_count() -> int:
	return awakened_species().size()

## 全部物种都觉醒了？（= 秘密花园解锁条件）
func all_species_awakened() -> bool:
	return awakened_species_count() >= AnimalDB.all_ids().size()

## 刚觉醒、还没弹过对话的个体（main 每帧扫一次，弹完清标记）
func pending_awakenings() -> Array[AnimalState]:
	var out: Array[AnimalState] = []
	for a in animals:
		if a.just_awakened:
			out.append(a)
	return out

## 全体跨日，汇总事件；顺带处理生崽与病逝。
## 事件类型：mature / born / birth / hungry / neglect / sick / critical / died / product
func advance_day() -> Array:
	var events: Array = []
	var born: Array = []
	var dead: Array = []
	for a in animals:
		var ev := a.advance_day()
		for e in ev:
			match e["type"]:
				"born":
					born.append(e)
				"died":
					dead.append(e)
		events.append_array(ev)

	# 生崽：落在母亲身边（母亲还在的话），牧场满了就跳过（事件仍广播，主逻辑会提示）
	for e in born:
		var mother := get_by_uid(e["uid"])
		var spot := Vector2(600, 200) if mother == null else mother.pos + Vector2(20, 10)
		var baby := add(e["species"], 0, spot)
		if baby != null:
			baby.days_old = 0
			events.append({"uid": baby.uid, "type": "birth", "species": e["species"]})

	# 病逝：拖满 SICK_DEATH_DAYS 天没用药
	for e in dead:
		remove(e["uid"])

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

# ---------------- 存档（模块 8）----------------

func to_dict() -> Dictionary:
	var arr: Array = []
	for a in animals:
		arr.append(a.to_dict())
	return {"animals": arr, "next_id": _next_id, "rng_state": str(_rng.state)}

## ⚠️ 存档里的物种可能在新版本里被删了（改 animals.csv）。
##    未知物种**跳过**，不让一个旧档把游戏崩掉 —— 少一只动物总比打不开游戏好。
## ⚠️ uid 是主键（animal_node / 订单 / 提示都靠它），_next_id 必须大于所有已存在的编号，
##    否则新买的动物会和读回来的老动物重号，两只动物共用一个 uid。
func from_dict(d: Dictionary) -> void:
	animals.clear()
	var raw_list: Array = d.get("animals", [])
	for raw in raw_list:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var sp := StringName(str(raw.get("species", "")))
		if AnimalDB.get_animal(sp) == null:
			continue
		var a := AnimalState.new(StringName(str(raw.get("uid", ""))), sp, 0)
		a.from_dict(raw)
		animals.append(a)
	_next_id = maxi(1, int(d.get("next_id", 1)))
	for a in animals:
		var tail := str(a.uid).split("_")
		if tail.size() == 2 and tail[1].is_valid_int():
			_next_id = maxi(_next_id, int(tail[1]) + 1)
	var st := int(str(d.get("rng_state", "0")))
	if st != 0:
		_rng.state = st
