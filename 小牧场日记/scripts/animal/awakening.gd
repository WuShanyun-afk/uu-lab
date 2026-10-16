class_name Awakening
extends RefCounted
## 动物觉醒事件表（模块 5 需求 1）—— **纯数据 + 纯查询**，不碰节点、不碰 UI
##
## 觉醒 = 好感封顶 10 心那一刻，动物「醒过来」，开始说人话。
## 每只觉醒的动物：
##   ① 有一个拟人化名字 + 称号（persona / title）
##   ② 有 2–3 句自己的台词（lines），由 DialogueUI 逐句播放
##   ③ 每天产出时，有 30% 概率把当天的产出换成**觉醒专属产物**（gift）
##   ④ 从此不会生病、不会因为漏喂掉好感（它自己会觅食）—— 见 AnimalState
##
## 事件数据结构（`event()` 的返回值，也是 EventBus / DialogueUI / 存档之间的契约）：
##
##   {
##     "species":   StringName,   # 物种 id，与 animals.csv 一致
##     "persona":   String,       # 拟人化名字（对话框标题左半）
##     "title":     String,       # 称号（对话框标题右半）
##     "portrait":  Color,        # 立绘色块（UI 画一个方形头像，零素材）
##     "lines":     Array[String],# 拟人化对话，逐句推进
##     "gift":      StringName,   # 觉醒专属产物 id（必须在 products.csv 里）
##     "gift_name": String,       # 产物中文名（提示条文案用）
##   }
##
## ⚠️ gift 的 id **不能**以 `_silver` / `_gold` 结尾 —— CropQuality.split() 会把
##    它当成品质后缀，ProductDB 查不到（模块 4 踩过一次：duck_egg_gold）。
##
## 加第 10 种动物 = 这里加一条 + animals.csv 加一行 + products.csv 加一行产物。

const EVENTS := {
	"cow": {
		"persona": "布伦希尔德", "title": "牧场之母",
		"portrait": Color("#F2F0EA"),
		"lines": [
			"……你终于听见我说话了？",
			"我是这片牧场的第一个住客。你可以叫我布伦希尔德。",
			"从今天起，我给你星光牛奶 —— 只给配得上的人。",
		],
		"gift": &"starlight_milk", "gift_name": "星光牛奶",
	},
	"goat": {
		"persona": "梅菲", "title": "悬崖上的学者",
		"portrait": Color("#D8D3C6"),
		"lines": [
			"咩。别问我为什么会说人话，我也不知道。",
			"你每天准时挤两次奶的样子，比我导师还认真。",
			"月光羊奶，拿去。记得冷藏。",
		],
		"gift": &"moonlight_goat_milk", "gift_name": "月光羊奶",
	},
	"sheep": {
		"persona": "弗洛拉", "title": "云朵编织者",
		"portrait": Color("#F7F3E6"),
		"lines": [
			"我一直在等有人把我剪得这么舒服。",
			"现在，我身上的毛会自己变成云。",
			"云绒给你 —— 轻一点拿，它会飘。",
		],
		"gift": &"cloud_wool", "gift_name": "云绒",
	},
	"alpaca": {
		"persona": "帕科", "title": "高原的守夜人",
		"portrait": Color("#D9B98A"),
		"lines": [
			"我的祖先在雪线之上看星星。",
			"现在我看的是你的牧场。也不差。",
			"晚霞羊驼绒，只在黄昏纺得出来。",
		],
		"gift": &"sunset_alpaca_wool", "gift_name": "晚霞羊驼绒",
	},
	"pig": {
		"persona": "葛蕾特", "title": "泥土的哲人",
		"portrait": Color("#F0A8AE"),
		"lines": [
			"你踩过的每一寸土，我都闻过。",
			"松露会撒谎，我不会。",
			"真言松露。吃一口，说不出假话。",
		],
		"gift": &"truffle_of_truth", "gift_name": "真言松露",
	},
	"chicken": {
		"persona": "小春", "title": "黎明的报时鸟",
		"portrait": Color("#FFF6E0"),
		"lines": [
			"咯咯！我等你起床等了好久。",
			"从明天起我叫你起床，你不用设闹钟了。",
			"黎明蛋，只在下第一声鸡鸣时下。",
		],
		"gift": &"dawn_egg", "gift_name": "黎明蛋",
	},
	"duck": {
		"persona": "涟漪", "title": "池塘的歌者",
		"portrait": Color("#F6F1DC"),
		"lines": [
			"水面上的圈，都是我写给你的信。",
			"你从来没读过，但我还是每天写。",
			"涟漪鸭蛋，蛋壳上有水的纹路。",
		],
		"gift": &"ripple_egg", "gift_name": "涟漪鸭蛋",
	},
	"turkey": {
		"persona": "余烬", "title": "炉边的守卫",
		"portrait": Color("#A9744F"),
		"lines": [
			"我嗓门大，是因为牧场太安静了。",
			"以后有我在，没人敢动你的鸡。",
			"余烬火鸡蛋，摸上去还是温的。",
		],
		"gift": &"ember_egg", "gift_name": "余烬火鸡蛋",
	},
	"bee": {
		"persona": "金冠", "title": "花田的会计",
		"portrait": Color("#F2C14E"),
		"lines": [
			"我数过了，你一共有 1287 朵花。",
			"这个数字每天都变，所以我每天都重新数。",
			"黄金蜜，是花的账本。",
		],
		"gift": &"golden_honey", "gift_name": "黄金蜜",
	},
}

## 全部觉醒（= 秘密花园解锁）时的对话
const GARDEN_UNLOCK := {
	"persona": "秘密花园", "title": "牧场东侧",
	"portrait": Color("#8FC96A"),
	"lines": [
		"九种动物，全都醒过来了。",
		"牧场东边的藤蔓门，刚刚开了。",
		"门后有一圈石碑 —— 你唤醒的每一位，都刻在上面。",
	],
	"gift": &"", "gift_name": "",
}

## 物种 → 事件（未定义返回 {}）
static func event(species: StringName) -> Dictionary:
	return EVENTS.get(String(species), {})

static func has(species: StringName) -> bool:
	return EVENTS.has(String(species))

## 拟人化名字（对话框标题）
static func persona(species: StringName) -> String:
	return str(event(species).get("persona", String(species)))

static func title_of(species: StringName) -> String:
	return str(event(species).get("title", ""))

## 觉醒专属产物 id
static func gift(species: StringName) -> StringName:
	return event(species).get("gift", &"")

static func gift_name(species: StringName) -> String:
	return str(event(species).get("gift_name", ""))

static func lines(species: StringName) -> Array:
	return event(species).get("lines", [])

static func portrait(species: StringName) -> Color:
	return event(species).get("portrait", Color.WHITE)

## 表里定义的物种数（测试用来钉「觉醒表和动物表一样长」）
static func count() -> int:
	return EVENTS.size()

static func species_ids() -> Array:
	return EVENTS.keys()

## 对话框标题（"布伦希尔德 · 牧场之母"）
static func speaker(species: StringName) -> String:
	var t := title_of(species)
	return persona(species) if t == "" else "%s · %s" % [persona(species), t]
