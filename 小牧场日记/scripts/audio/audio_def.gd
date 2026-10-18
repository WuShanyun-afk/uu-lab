class_name AudioDef
extends RefCounted
## 一条音频定义 —— 从 data/audio.csv 的一行读出来（模块 附1）
##
## 一行 = 一份素材的「元数据」：放哪、哪条总线、多响、音高抖动范围、
## 同一个 id 两次播放的最小间隔、同一时刻最多几个实例、是不是循环。
##
## 为什么这些要进数据表而不是写死在 AudioManager 里：
##   ① 音量/抖动是要**反复试听调**的数值，调一次不该改代码改到出 bug；
##   ② 「同一音效 0.15 秒内不许再响」这种防爆音参数，每个音效都不一样
##      （金币密集、牛叫稀疏），写在表里一眼能对比；
##   ③ 以后换素材（MCP 生成 vs 程序合成）只换文件，不改逻辑。

## 类别：step 脚步 / interact 交互 / animal 动物 / ui 界面 / system 系统 / amb 环境 / bgm 音乐
const CAT_STEP := &"step"
const CAT_INTERACT := &"interact"
const CAT_ANIMAL := &"animal"
const CAT_UI := &"ui"
const CAT_SYSTEM := &"system"
const CAT_AMB := &"amb"
const CAT_BGM := &"bgm"

var id: StringName = &""
## sfx / ambience / bgm
var kind: StringName = &"sfx"
## res:// 路径
var file: String = ""
var category: StringName = &""
## 线性音量（0–1），播放时乘到播放器上
var volume: float = 1.0
## 音高随机区间：每个实例在 [pitch_min, pitch_max) 里抽一个，避免机械化
var pitch_min: float = 1.0
var pitch_max: float = 1.0
## 同一 id 两次播放的最小间隔（秒）。0 = 不限制
var cooldown: float = 0.0
## 同一 id 同时最多几个实例（0 = 只看池子大小）
var max_voices: int = 1
var loop: bool = false
var note: String = ""

func is_bgm() -> bool:
	return kind == &"bgm"

func is_ambience() -> bool:
	return kind == &"ambience"

func is_sfx() -> bool:
	return kind == &"sfx"

## 这一条能不能播放：缺文件就是缺文件，不要静默播空气
func is_available() -> bool:
	return file != "" and ResourceLoader.exists(file)

static func from_row(columns: Dictionary, row: PackedStringArray) -> AudioDef:
	var out := AudioDef.new()
	out.id = StringName(_cell(columns, row, "id"))
	out.kind = StringName(_cell(columns, row, "kind"))
	out.file = _cell(columns, row, "file")
	out.category = StringName(_cell(columns, row, "category"))
	out.volume = _f(_cell(columns, row, "volume"), 1.0)
	out.pitch_min = _f(_cell(columns, row, "pitch_min"), 1.0)
	out.pitch_max = _f(_cell(columns, row, "pitch_max"), 1.0)
	out.cooldown = _f(_cell(columns, row, "cooldown"), 0.0)
	out.max_voices = _i(_cell(columns, row, "max_voices"), 1)
	out.loop = _cell(columns, row, "loop").to_lower() == "true"
	out.note = _cell(columns, row, "note")
	return out

## 按表头名取单元格（不要按位置取：表加列时下标会全错，模块 4 的教训）
static func _cell(columns: Dictionary, row: PackedStringArray, key: String) -> String:
	var i := int(columns.get(key, -1))
	if i < 0 or i >= row.size():
		return ""
	return row[i].strip_edges()

static func _f(s: String, fallback: float) -> float:
	return s.to_float() if s != "" else fallback

static func _i(s: String, fallback: int) -> int:
	return s.to_int() if s != "" else fallback

func to_dict() -> Dictionary:
	return {
		"id": String(id), "kind": String(kind), "file": file,
		"category": String(category), "volume": volume,
		"pitch_min": pitch_min, "pitch_max": pitch_max,
		"cooldown": cooldown, "max_voices": max_voices, "loop": loop,
	}
