extends Node
## 场景路由 + 跨场景存读档（模块 11 需求 3 / 4 / 5）—— autoload: SceneRouter
##
## 一句话：**它是唯一知道「现在在哪个场景」和「离开前那一局是什么」的地方。**
##
## 为什么需要它（而不是每个场景自己 new 一遍数据）：
##   项目里 99% 的玩法状态（农田 / 牧群 / 建筑 / 订单 / 加工槽 / 好感 / 剧情）
##   现在都住在 main.gd 的成员变量里。`change_scene_to_file` 会把 main 整个 free 掉，
##   所以离开牧场那一刻必须有人把那一局**接住**，回来时再塞回去。
##
## 数据流（两段式，和模块 8 的三层存档一脉相承）：
##
##   牧场(main) ──capture()──▶ carry ──▶ 房间场景（只读全局 autoload + carry 原样带着）
##        ▲                                   │
##        └──────── apply(carry) ◀── 回牧场 ───┘
##
##   carry = 牧场那一局的**完整存档字典**（正是 main._build_save() 的产物）。
##   房间场景手里没有农场数据，也不该有 —— 它们只读 GameState / GameClock / WeatherSystem
##   这些 autoload（这些本来就不属于任何场景）。
##
## 存读档（需求 1 / 2 / 5）：
##   任何场景里存档 = carry（农场那一局）+ scene 块（在哪个场景、哪个入口、坐标）+ meta
##   读档 = 先把全局 autoload 灌回去，再看 scene.id：
##     · 和当前场景一样 → 原地 apply（模块 8 的老行为，F9 秒回）
##     · 不一样 → 带着 carry 切到目标场景，由目标场景自己在 _ready 里接住
##
## ⚠️ change_scene_to_file 是**下一帧**才生效的。所以 travel/load 里只改状态 +
##    call_deferred，绝不能在这之后还按老场景的节点指针干活（模块 8 踩过 free 后访问）。

## 场景注册表：id → 路径 / 显示名。加场景只改这里 + 建一个 .tscn。
const SCENES := {
	&"farm": {"path": "res://scenes/main.tscn", "name": "牧场", "room": false},
	&"house": {"path": "res://scenes/house.tscn", "name": "小屋", "room": true},
	&"town": {"path": "res://scenes/town.tscn", "name": "小镇", "room": true},
	&"shop": {"path": "res://scenes/shop.tscn", "name": "杂货铺", "room": true},
	&"mine": {"path": "res://scenes/mine.tscn", "name": "矿洞", "room": true},
}

## 换场完成（新场景 _ready 之后由新场景发）
signal scene_entered(id: StringName)
## 换场请求（出发前一刻，旧的场景还活着 —— 用来收尾 UI / 停时钟）
signal leaving_scene(id: StringName)
signal save_finished(slot: int, ok: bool)
signal load_finished(slot: int, ok: bool)

## 当前场景 id
var current_id: StringName = &"farm"
## 目标场景的入口名（房间场景用它决定出生点）
var pending_entry: StringName = &""
## 读档后要落位的坐标（Vector2；has_pending_pos = false 时用入口默认点）
var pending_pos: Vector2 = Vector2.ZERO
var has_pending_pos: bool = false
## 牧场那一局的完整存档（离开牧场时 capture 出来的）
var carry: Dictionary = {}
## 场景栈（"返回上一处"用）
var history: Array = []
## 正在换场（防止连点传送门换两次）
var busy: bool = false
## **只给测试用**：置 true 时 travel / 读档只改状态、不真的 change_scene_to_file。
## 单元测试没法在「自己的场景被换掉」之后继续断言，所以留这个开关。
## 运行时永远是 false（没有任何游戏代码会写它）。
var suppress_scene_change: bool = false

## 当前场景注册的四个回调（牧场注册全套，房间只注册位置相关）
var _capture := Callable()
var _apply := Callable()
var _get_pos := Callable()
var _set_pos := Callable()

# ---------------- 注册表查询 ----------------

func has_scene(id: StringName) -> bool:
	return SCENES.has(id)

func scene_path(id: StringName) -> String:
	return str(SCENES.get(id, {}).get("path", ""))

func scene_name(id: StringName) -> String:
	return str(SCENES.get(id, {}).get("name", String(id)))

func is_room(id: StringName) -> bool:
	return bool(SCENES.get(id, {}).get("room", false))

## 能不能去（注册表里有 + 不是正在换场 + 不是原地）
func can_travel(target: StringName) -> bool:
	return SCENES.has(target) and not busy and target != current_id \
		and FileAccess.file_exists(scene_path(target))

## 场景显示名（存读档 UI 的「在哪个场景」那一列）
func current_scene_name() -> String:
	return scene_name(current_id)

# ---------------- 场景注册 ----------------

## 场景在 _ready 里注册自己。牧场传全套；房间捕获留空（carry 原样带着）。
func register_scene(id: StringName, capture: Callable, apply: Callable,
		get_pos: Callable, set_pos: Callable) -> void:
	current_id = id
	_capture = capture
	_apply = apply
	_get_pos = get_pos
	_set_pos = set_pos
	busy = false
	scene_entered.emit(id)

func _clear_hooks() -> void:
	_capture = Callable()
	_apply = Callable()
	_get_pos = Callable()
	_set_pos = Callable()

## 当前场景注册了吗（测试 / 诊断用）
func has_hooks() -> bool:
	return _set_pos.is_valid()

# ---------------- 换场 ----------------

## 去另一个场景。entry 是给目标场景的出生点名字（"door" / "from_town" …）
func travel(target: StringName, entry: StringName = &"") -> bool:
	if not can_travel(target):
		return false
	busy = true
	leaving_scene.emit(current_id)
	# ① 让当前场景交出那一局（牧场交出完整存档；房间不交，carry 保持）
	if _capture.is_valid():
		var snap: Variant = _capture.call()
		if typeof(snap) == TYPE_DICTIONARY and not (snap as Dictionary).is_empty():
			carry = snap
	# ② 记历史（最多 8 层，够「屋里→牧场→镇上→商店」来回跳）
	history.append(current_id)
	while history.size() > 8:
		history.pop_front()
	# ③ 收掉所有模态 UI：新场景里不能还挂着旧场景的商店 / 建造模式
	EventBus.set_ui_modal(false)
	EventBus.set_build_mode(false)
	# ④ 切场景（下一帧生效 —— 之后别再碰旧节点）
	current_id = target
	pending_entry = entry
	has_pending_pos = false
	_clear_hooks()
	call_deferred("_change_scene")
	return true

## 返回上一个场景（门内 → 门外）
func back(entry: StringName = &"") -> bool:
	if history.is_empty():
		return false
	var prev: StringName = history.pop_back()
	return travel(prev, entry)

func _change_scene() -> void:
	if suppress_scene_change:
		busy = false
		scene_entered.emit(current_id)
		return
	var path := scene_path(current_id)
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("[SceneRouter] 换场景失败（%d）：%s" % [err, path])
	busy = false

## 目标场景在 _ready 里调这个收下 carry（取走后清空：新开一局时 carry 必须是空的）
func take_carry() -> Dictionary:
	var d := carry.duplicate(true)
	carry.clear()
	return d

func carry_size() -> int:
	return carry.size()

# ---------------- 全局状态（任何场景都通用的那几段）----------------

## GameState / 时钟 / 天气是 autoload，不属于任何场景 —— 换场 / 读档都要先灌它们
func apply_global_state(d: Dictionary) -> void:
	GameState.from_dict(d.get("state", {}))
	GameClock.from_dict(d.get("clock", {}))
	WeatherSystem.from_dict(d.get("weather", {}))

func capture_global_state() -> Dictionary:
	return {
		"state": GameState.to_dict(),
		"clock": GameClock.to_dict(),
		"weather": WeatherSystem.to_dict(),
	}

# ---------------- 组盘存读档（需求 1 / 2 / 5）----------------

## 组装一份完整存档：牧场那一局 + 当前场景块 + meta
## 在牧场里 = 现 capture；在房间里 = 复用 carry（离开牧场时抓到的）
func build_payload() -> Dictionary:
	var payload: Dictionary
	if _capture.is_valid():
		var snap: Variant = _capture.call()
		payload = snap if typeof(snap) == TYPE_DICTIONARY else {}
	else:
		payload = carry.duplicate(true)
	# carry 可能是空的（比如直接在编辑器里跑房间场景）—— 至少把全局状态带上，
	# 否则读档会把玩家的金币/背包清空，比「没存档」还糟。
	if payload.is_empty():
		payload = capture_global_state()
	var pos: Vector2 = pending_pos if has_pending_pos else Vector2.ZERO
	if _get_pos.is_valid():
		pos = _get_pos.call()
	payload["scene"] = {
		"id": String(current_id),
		"entry": String(pending_entry),
		"pos": [pos.x, pos.y],
	}
	var meta: Dictionary = payload.get("meta", {})
	# 时间 / 金币在房间场景里也在走 —— meta 必须现算，不能照抄离开牧场那一刻的
	meta["day"] = GameClock.day
	meta["season"] = GameClock.season
	meta["year"] = GameClock.year
	meta["clock"] = GameClock.clock_text()
	meta["weather"] = WeatherSystem.weather_name()
	meta["gold"] = GameState.gold
	meta["scene"] = String(current_id)
	meta["scene_name"] = current_scene_name()
	payload["meta"] = meta
	return payload

## 存档到某个槽位。返回 SaveSystem 的结果字典（{ok, error}）
func save_session(slot: int) -> Dictionary:
	var res := SaveSystem.save(slot, build_payload())
	save_finished.emit(slot, bool(res["ok"]))
	return res

## 读某个槽。返回 {ok, error, switched}
func load_session(slot: int) -> Dictionary:
	var res := SaveSystem.load_slot(slot)
	if not bool(res["ok"]):
		load_finished.emit(slot, false)
		return {"ok": false, "error": str(res["error"]), "switched": false}
	var d: Dictionary = res["data"]
	# ① 全局状态先灌（换不换场都得灌）
	apply_global_state(d)
	# ② carry 换成本档里的农场那一局
	carry = d.duplicate(true)
	# ③ 目标场景 / 落点
	var scn: Dictionary = d.get("scene", {})
	var target := StringName(str(scn.get("id", "farm")))
	if not SCENES.has(target):
		target = &"farm"
	pending_entry = StringName(str(scn.get("entry", "")))
	var raw: Array = scn.get("pos", [])
	pending_pos = Vector2(float(raw[0]), float(raw[1])) if raw.size() >= 2 else Vector2.ZERO
	has_pending_pos = raw.size() >= 2
	load_finished.emit(slot, true)
	# ④ 同一个场景：原地灌（模块 8 的 F9 秒回）
	if target == current_id:
		if _apply.is_valid():
			_apply.call(d, pending_pos if has_pending_pos else null)
		elif _set_pos.is_valid() and has_pending_pos:
			_set_pos.call(pending_pos)
		return {"ok": true, "error": "", "switched": false}
	# ⑤ 不同场景：带着 carry 切过去，目标场景 _ready 自己接
	busy = true
	EventBus.set_ui_modal(false)
	EventBus.set_build_mode(false)
	current_id = target
	_clear_hooks()
	call_deferred("_change_scene")
	return {"ok": true, "error": "", "switched": true}

## 有档就载：优先快速槽 → 自动槽 → 手动槽里最新的一个
func latest_slot() -> int:
	if SaveSystem.exists(SaveSystem.SLOT_QUICK):
		return SaveSystem.SLOT_QUICK
	if SaveSystem.exists(SaveSystem.SLOT_AUTO):
		return SaveSystem.SLOT_AUTO
	var best := -1
	for s in SaveSystem.used_slots():
		if s >= SaveSystem.SLOT_MANUAL_START:
			best = maxi(best, s)
	return best

func has_any_save() -> bool:
	return latest_slot() >= 0

## 存档摘要一行（存读档 UI 用）："第 12 天 春 · 1234G · 牧场"
func slot_summary(slot: int) -> String:
	var info := SaveSystem.info(slot)
	if not bool(info.get("exists", false)):
		return "（空档）"
	if not bool(info.get("ok", true)):
		return "（损坏：%s）" % str(info.get("error", ""))
	var season_name: String = GameClock.SEASON_NAME[clampi(int(info["season"]), 0, 3)]
	return "第 %d 天 %s · %dG · %s" % [int(info["day"]), season_name,
		int(info["gold"]), str(info.get("scene_name", "牧场"))]

## 清空（注销场景 / 新开一局）
func reset_session() -> void:
	carry.clear()
	history.clear()
	pending_entry = &""
	pending_pos = Vector2.ZERO
	has_pending_pos = false
	busy = false
	current_id = &"farm"
	_clear_hooks()
