extends Node
## 音频表 —— autoload: AudioDB
##
## 读 data/audio.csv，把每一行变成 AudioDef。**不认识播放器**，只回答「这个 id 长什么样」。
## 和 CropDB / ProductDB / BuildingDB 同一套写法：表头按名字取列，加列只改 CSV。
##
## 分组查询（BGM 列表 / 某类别音效）留给 UI 和测试用；
## 真正播放时 AudioManager 只按 id 取一条。

const CSV_PATH := "res://data/audio.csv"

## StringName -> AudioDef
var defs: Dictionary = {}
## 表头名 -> 列下标
var _columns: Dictionary = {}

func _ready() -> void:
	load_csv()

func load_csv() -> void:
	defs.clear()
	_columns.clear()
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		push_error("[AudioDB] 打不开 " + CSV_PATH)
		return
	var header := f.get_csv_line()
	for i in range(header.size()):
		_columns[header[i].strip_edges()] = i
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 3:
			continue
		if row[0].strip_edges() == "":
			continue
		var d: AudioDef = AudioDef.from_row(_columns, row)
		if d.id == &"":
			continue
		defs[d.id] = d
	print("[AudioDB] 载入 %d 条音频定义" % defs.size())

# ---------------- 查询 ----------------

func def_of(id: StringName) -> AudioDef:
	return defs.get(id, null)

func has(id: StringName) -> bool:
	return defs.has(id)

func ids_of_kind(kind: StringName) -> Array:
	var out: Array = []
	for k in defs:
		if (defs[k] as AudioDef).kind == kind:
			out.append(k)
	return out

func ids_of_category(cat: StringName) -> Array:
	var out: Array = []
	for k in defs:
		if (defs[k] as AudioDef).category == cat:
			out.append(k)
	return out

## 缺文件的条目（启动自检 / 测试用）——素材没到位时能一眼看出来
func missing_files() -> Array:
	var out: Array = []
	for k in defs:
		if not (defs[k] as AudioDef).is_available():
			out.append(k)
	return out

func bgm_ids() -> Array:
	return ids_of_kind(&"bgm")

## 「BGM 缺几首」自检：动态 BGM 需要 7 首，缺一首就说明素材没生成全
func bgm_complete() -> bool:
	return bgm_ids().size() >= 7
