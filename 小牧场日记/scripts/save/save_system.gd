class_name SaveSystem
extends RefCounted
## 模块 8 · 存档系统的**底座** —— 只管「把字典安全地变成文件，再安全地读回来」
##
## 职责边界（和 Processor / OrderBoard 一样的分层哲学）：
##   · 本文件**不认识** GameClock / FarmGrid / Herd，一个字段都不碰。
##   · 它负责：槽位路径、JSON 化、原子写入、版本迁移、损坏容错。
##   · 「一局游戏里有哪些系统、各自存什么」是 main.gd 的事（_build_save）。
##
## 为什么要有这一层而不是 main 里两行 FileAccess：
##   1. **JSON 化**：StringName / Color / Vector2 这三位 JSON 都不认。
##      不统一转一次，存档里会出现 "(1, 2)" 这种字符串，读回来是文本不是向量。
##   2. **原子写入**：先写 .tmp → 校验长度 → 旧档挪 .bak → 换名 → 删 .bak。
##      断电 / 崩溃最坏是丢一次存档，不会得到半截 JSON。
##   3. **版本号**：老档进得去、新档不会把老程序毒死（v > VERSION 直接拒）。
##   4. **容错**：坏档返回 {ok:false, error}，绝不让 JSON.parse 的 null 漏进玩法层。
##
## ⚠️ 存进去的所有 id 都会变成 **String**（JSON 的锅）。各系统的 from_dict
##    必须自己 StringName() 回来，否则 GameState.count_item() 用 StringName 查表会全查不到。
##    （模块 7 的 OrderBoard 就踩过这个：订单里的 item 读回来是 String。）

const VERSION := 1

## 槽位：0 = 自动存档（每天 2:00 跨日），1 = 快速存档（F5 / F9），2–3 = 预留给以后的标题页
const SLOT_AUTO := 0
const SLOT_QUICK := 1
const SLOT_MAX := 3

const DEFAULT_DIR := "user://saves"

## 目录做成 static var 而不是 const：测试会把这里改成 user://saves_test，
## 免得跑一次测试就把玩家真存档洗了。
static var save_dir: String = DEFAULT_DIR

static func slot_label(slot: int) -> String:
	match slot:
		SLOT_AUTO:
			return "自动存档"
		SLOT_QUICK:
			return "快速存档"
	return "存档 %d" % slot

static func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [save_dir, slot]

static func exists(slot: int) -> bool:
	if slot < 0 or slot > SLOT_MAX:
		return false
	return FileAccess.file_exists(slot_path(slot))

# ---------------- JSON 化 ----------------

## Variant → 纯 JSON 类型（String / int / float / bool / Array / Dictionary）
##
## 转型规则：
##   StringName      → String
##   Color           → "#RRGGBBAA"
##   Vector2/Vector2i→ [x, y]
##   Dictionary 的键 → 非 String/int 的键一律 str()（JSON 的对象键只能是字符串）
static func jsonify(v: Variant) -> Variant:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return v
		TYPE_STRING_NAME:
			return String(v)
		TYPE_COLOR:
			var c: Color = v
			return "#" + c.to_html(true)
		TYPE_VECTOR2:
			var v2: Vector2 = v
			return [v2.x, v2.y]
		TYPE_VECTOR2I:
			var vi: Vector2i = v
			return [vi.x, vi.y]
		TYPE_ARRAY:
			var arr: Array = []
			for x in (v as Array):
				arr.append(jsonify(x))
			return arr
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			for k in (v as Dictionary):
				var key_out: Variant = jsonify(k)
				if typeof(key_out) != TYPE_STRING and typeof(key_out) != TYPE_INT:
					key_out = str(key_out)
				out[key_out] = jsonify(v[k])
			return out
	# 未知类型一律降级成字符串：宁可存个能看的，也不要让 JSON.stringify 抛错
	return str(v)

# ---------------- 写 ----------------

## 存档。返回 {ok: bool, error: String}
static func save(slot: int, data: Dictionary) -> Dictionary:
	if slot < 0 or slot > SLOT_MAX:
		return {"ok": false, "error": "槽位越界（0–%d）" % SLOT_MAX}
	var derr := DirAccess.make_dir_recursive_absolute(save_dir)
	if derr != OK and derr != ERR_ALREADY_EXISTS:
		return {"ok": false, "error": "建存档目录失败（%d）" % derr}

	var payload: Dictionary = data.duplicate(true)
	payload["version"] = VERSION
	payload["saved_at"] = Time.get_unix_time_from_system()
	payload["saved_at_text"] = Time.get_datetime_string_from_system(false, true)
	var text := JSON.stringify(jsonify(payload), "\t", true, true)

	var path := slot_path(slot)
	var tmp := path + ".tmp"
	var bak := path + ".bak"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "临时文件写不了（%d）" % FileAccess.get_open_error()}
	f.store_string(text)
	f.close()

	# 落盘校验：长度对不上就别动旧档（磁盘满 / 权限怪问题都拦在这）
	if FileAccess.get_file_as_string(tmp).length() != text.length():
		DirAccess.remove_absolute(tmp)
		return {"ok": false, "error": "落盘校验失败（长度不符）"}

	# 旧档挪备份 → 换名 → 删备份。Windows 上 rename 覆盖已存在的文件会失败，
	# 所以必须先把旧档挪走；中途失败还能把旧档挪回来。
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		if DirAccess.rename_absolute(path, bak) != OK:
			DirAccess.remove_absolute(tmp)
			return {"ok": false, "error": "旧档挪备份失败"}
	var rerr := DirAccess.rename_absolute(tmp, path)
	if rerr != OK:
		if FileAccess.file_exists(bak):
			DirAccess.rename_absolute(bak, path)
		DirAccess.remove_absolute(tmp)
		return {"ok": false, "error": "替换存档失败（%d）" % rerr}
	if FileAccess.file_exists(bak):
		DirAccess.remove_absolute(bak)
	return {"ok": true, "error": ""}

# ---------------- 读 ----------------

## 读档。返回 {ok: bool, error: String, data: Dictionary}
## 任何异常都走 ok=false —— 调用方不需要 try，也不该拿到 null 去遍历。
static func load_slot(slot: int) -> Dictionary:
	if slot < 0 or slot > SLOT_MAX:
		return {"ok": false, "error": "槽位越界（0–%d）" % SLOT_MAX, "data": {}}
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "还没有存档", "data": {}}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {"ok": false, "error": "存档是空文件", "data": {}}
	# 用 JSON 实例而不是 JSON.parse_string：parse_string 会在控制台打 ERROR 垃圾，
	# 而「坏档」是本系统**预期内**的结果，不该看起来像引擎出事了。
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false,
			"error": "存档损坏（第 %d 行：%s）" % [json.get_error_line(), json.get_error_message()],
			"data": {}}
	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "存档损坏（不是 JSON 对象）", "data": {}}
	var d: Dictionary = parsed
	var v := int(d.get("version", 0))
	if v > VERSION:
		return {"ok": false, "error": "存档版本太新（v%d > v%d）" % [v, VERSION], "data": {}}
	d = migrate(d, v)
	return {"ok": true, "error": "", "data": d}

## 版本迁移：老档补齐缺失字段。目前只有 v1，留好钩子。
static func migrate(d: Dictionary, from_version: int) -> Dictionary:
	var out := d.duplicate(true)
	if from_version < 1:
		if typeof(out.get("meta")) != TYPE_DICTIONARY:
			out["meta"] = {}
	out["version"] = VERSION
	return out

# ---------------- 杂项 ----------------

## 存档摘要（以后做标题页「继续游戏」用）：不载入整局，只读 meta。
static func info(slot: int) -> Dictionary:
	if not exists(slot):
		return {"exists": false}
	var r := load_slot(slot)
	if not bool(r["ok"]):
		return {"exists": true, "ok": false, "error": str(r["error"])}
	var d: Dictionary = r["data"]
	var meta: Dictionary = d.get("meta", {})
	return {
		"exists": true,
		"ok": true,
		"saved_at_text": str(d.get("saved_at_text", "")),
		"day": int(meta.get("day", 0)),
		"season": int(meta.get("season", 0)),
		"gold": int(meta.get("gold", 0)),
	}

static func delete_slot(slot: int) -> bool:
	if not exists(slot):
		return false
	return DirAccess.remove_absolute(slot_path(slot)) == OK

## 已有档的槽位列表（升序）
static func used_slots() -> Array:
	var out: Array = []
	for i in range(SLOT_MAX + 1):
		if exists(i):
			out.append(i)
	return out
