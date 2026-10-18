class_name SfxPool
extends RefCounted
## 音效池的**纯逻辑**部分（模块 附1）—— 不碰 AudioStreamPlayer，只决定「这一声放不放、放哪个槽」
##
## 为什么要把「分配」单独抽出来：
##   音效最容易出的两个 bug 都是**分配问题**，不是播放问题：
##     ① 爆音：同一帧里十几个金币音叠在一起，总线直接削波（听起来像破音）；
##     ② 吃掉：一个 0.8 秒的竣工音占着唯一的槽，玩家踩了 8 步一点脚步声都没有。
##   而这两条都不需要真的出声就能验证 —— 所以逻辑放这里，headless 能断言，
##   AudioManager 只负责「按给出的槽去 play()」。
##
## 三条闸门（按顺序）：
##   1. 冷却：同一 id 距上次播放 < def.cooldown → 拒（金币连爆就是靠它压住的）
##   2. 同 id 并发：已经响着 def.max_voices 个 → 拒（牛叫不会二重唱）
##   3. 槽位：优先空闲槽；全忙就**抢最早该结束的那个**（Steal），
##      因为「切掉一个快播完的音」比「完全不播新音」听感损失小。

## 拒/放的原因码（不要用 bool，调用方 / 测试 / 调试面板都要知道为什么）
const OK := &"ok"
const REJECT_COOLDOWN := &"cooldown"
const REJECT_VOICES := &"voices"
const STEAL := &"steal"
const REJECT_NO_DEF := &"no_def"

## 池子大小（AudioManager 建几个播放器就是几个）
var size: int = 12

## 每个槽预计释放的时间（秒，用 Time.get_ticks_msec()/1000.0 的时间轴）
var _slot_until: PackedFloat64Array = PackedFloat64Array()
## 每个槽当前装的 id（诊断用）
var _slot_id: Array = []
## 每个槽的代数：同一个槽被复用后代数 +1，旧音效的 finished 回调不能误释放新音效
var _slot_token: PackedInt32Array = PackedInt32Array()
var _next_token: int = 1

## id -> 上次播放时间
var _last_played: Dictionary = {}
## id -> 正在响的实例数（用计数而不是遍历，分配是每帧可能调用的热路径）
var _active: Dictionary = {}
## 最近放过的（调试面板 / 测试用）：[{id, slot, at}]
var history: Array = []
const HISTORY_MAX := 24

func _init(pool_size: int = 12) -> void:
	size = maxi(1, pool_size)
	_slot_until.resize(size)
	_slot_token.resize(size)
	for i in range(size):
		_slot_until[i] = 0.0
		_slot_token[i] = 0
		_slot_id.append(&"")

## 申请一个槽。
## def: AudioDef；now: 当前秒数；duration: 这次实际会响多久（已被 pitch 换算过）
## 返回 {slot: int, token: int, reason: StringName}；slot = -1 表示不放
func try_acquire(def: AudioDef, now: float, duration: float) -> Dictionary:
	if def == null:
		return {"slot": -1, "token": 0, "reason": REJECT_NO_DEF}

	# 1) 冷却
	var last := float(_last_played.get(def.id, -9999.0))
	if def.cooldown > 0.0 and now - last < def.cooldown:
		return {"slot": -1, "token": 0, "reason": REJECT_COOLDOWN}

	# 2) 同 id 并发上限
	if def.max_voices > 0 and int(_active.get(def.id, 0)) >= def.max_voices:
		return {"slot": -1, "token": 0, "reason": REJECT_VOICES}

	# 3) 找槽：空闲优先，否则抢最早结束的
	var slot := -1
	var reason := OK
	for i in range(size):
		if _slot_until[i] <= now:
			slot = i
			break
	if slot < 0:
		slot = 0
		for i in range(1, size):
			if _slot_until[i] < _slot_until[slot]:
				slot = i
		reason = STEAL
		# 被抢的那个实例的并发计数要减掉，否则同一 id 会被永久占满
		var stolen: StringName = _slot_id[slot]
		if stolen != &"":
			_active[stolen] = maxi(0, int(_active.get(stolen, 0)) - 1)

	# 落账
	if _slot_id[slot] != &"" and reason == OK:
		_active[_slot_id[slot]] = maxi(0, int(_active.get(_slot_id[slot], 0)) - 1)
	_slot_id[slot] = def.id
	_slot_until[slot] = now + maxf(0.02, duration)
	_slot_token[slot] = _next_token
	_next_token += 1
	_active[def.id] = int(_active.get(def.id, 0)) + 1
	_last_played[def.id] = now
	history.append({"id": def.id, "slot": slot, "at": now})
	while history.size() > HISTORY_MAX:
		history.pop_front()
	return {"slot": slot, "token": _slot_token[slot], "reason": reason}

## 播放器 finished 回调：只有「还是同一代」才释放（防止旧音效回调误伤新音效）
func release(slot: int, token: int) -> void:
	if slot < 0 or slot >= size:
		return
	if _slot_token[slot] != token:
		return
	if _slot_id[slot] != &"":
		_active[_slot_id[slot]] = maxi(0, int(_active.get(_slot_id[slot], 0)) - 1)
	_slot_id[slot] = &""
	_slot_until[slot] = 0.0

## 现在有几声在响（距上次快照之后自然结束的不算，按时间估）
func busy(now: float) -> int:
	var n := 0
	for i in range(size):
		if _slot_until[i] > now:
			n += 1
	return n

func active_of(id: StringName) -> int:
	return int(_active.get(id, 0))

## 诊断用：每个槽现在是什么 / 还剩多久
func snapshot(now: float) -> Array:
	var out: Array = []
	for i in range(size):
		out.append({
			"slot": i,
			"id": String(_slot_id[i]),
			"left": maxf(0.0, _slot_until[i] - now),
		})
	return out

func reset() -> void:
	for i in range(size):
		_slot_until[i] = 0.0
		_slot_token[i] = 0
		_slot_id[i] = &""
	_last_played.clear()
	_active.clear()
	history.clear()
