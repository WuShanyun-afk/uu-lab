extends Node
## 村民总表 —— autoload: NpcDB（模块 10 需求 1 / 2 / 3）
##
## 三张 CSV 各管一件事，不要合表：
##   data/npcs.csv          谁（名字 / 身份 / 立绘色 / 送礼三档）
##   data/npc_schedules.csv 几点在哪（一人多行 = 日程表）
##   data/npc_unlocks.csv   几心解锁什么（一人多行 = 解锁表）
##
## 为什么不合表：日程是一对多、解锁也是一对多，硬塞进一行的结果就是
## 「npc_zone1_x1_y1_zone2_x2_y2...」这种列名，加一个时段就要加 5 列。
##
## 对话台词分两套：
##   · 固定台词（自我介绍 / 高好感）写在下面 GREET 表里 —— 是散文，不进 CSV
##   · 剧情台词在 scripts/story/story_data.gd（节点表）
## 这样 CSV 里全是可调数值，改台词不用怕破坏表结构。

const NPCS_CSV := "res://data/npcs.csv"
const SCHEDULE_CSV := "res://data/npc_schedules.csv"
const UNLOCKS_CSV := "res://data/npc_unlocks.csv"

## 解锁种类
const K_PRICE := &"price"      ## 打折：id = 作用域(seed/tool/medicine)，value = 百分比
const K_RECIPE := &"recipe"    ## 秘方：id = data/secret_recipes.csv 的 output
const K_TOOL := &"tool"        ## 工具：id = golden（工具铺开到 Lv3）
const K_PERK := &"perk"        ## 被动：id = GameState.perks 里的键
const K_STORY := &"story"      ## 剧情/许可：id = GameState.story_flags 里的键

## StringName -> NpcDef
var defs: Dictionary = {}
## StringName -> Array[Dictionary{from,to,x,y,action,visible,days}]
var schedules: Dictionary = {}
## StringName -> Array[Dictionary{hearts,kind,id,value,text}]（按 hearts 升序）
var unlocks: Dictionary = {}

func _ready() -> void:
	load_all()

func load_all() -> void:
	_load_npcs()
	_load_schedules()
	_load_unlocks()
	print("[NpcDB] 载入 %d 位村民 / %d 条日程 / %d 条解锁" % [
		defs.size(), _schedule_row_count(), _unlock_row_count()])

func _load_npcs() -> void:
	defs.clear()
	var f := FileAccess.open(NPCS_CSV, FileAccess.READ)
	if f == null:
		push_error("[NpcDB] 打不开 " + NPCS_CSV)
		return
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 4 or row[0].strip_edges() == "":
			continue
		var d := NpcDef.from_row(row)
		defs[d.id] = d

func _load_schedules() -> void:
	schedules.clear()
	var f := FileAccess.open(SCHEDULE_CSV, FileAccess.READ)
	if f == null:
		push_error("[NpcDB] 打不开 " + SCHEDULE_CSV)
		return
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 6 or row[0].strip_edges() == "":
			continue
		var id := StringName(row[0].strip_edges())
		var days: Array[int] = []
		if row.size() > 7 and row[7].strip_edges() != "":
			# 多个用分号分隔：CSV 的逗号是列分隔符，直接写 7,14,21 会被拆成三列
			for s in row[7].split(";"):
				days.append(int(s.strip_edges()))
		var slot := {
			"from": int(row[1]),
			"to": int(row[2]),
			"x": float(row[3]),
			"y": float(row[4]),
			"action": row[5].strip_edges(),
			"visible": int(row[6]) != 0,
			"days": days,
		}
		if not schedules.has(id):
			schedules[id] = []
		(schedules[id] as Array).append(slot)

func _load_unlocks() -> void:
	unlocks.clear()
	var f := FileAccess.open(UNLOCKS_CSV, FileAccess.READ)
	if f == null:
		push_error("[NpcDB] 打不开 " + UNLOCKS_CSV)
		return
	f.get_csv_line()
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 5 or row[0].strip_edges() == "":
			continue
		var id := StringName(row[0].strip_edges())
		var u := {
			"hearts": int(row[1]),
			"kind": StringName(row[2].strip_edges()),
			"id": StringName(row[3].strip_edges()),
			"value": int(row[4]),
			"text": row[5].strip_edges() if row.size() > 5 else "",
		}
		if not unlocks.has(id):
			unlocks[id] = []
		(unlocks[id] as Array).append(u)
	# 按门槛升序：HUD / 提示条按顺序念，才不会出现「先看到 6 心再看到 3 心」
	for id in unlocks:
		(unlocks[id] as Array).sort_custom(func(a, b): return int(a["hearts"]) < int(b["hearts"]))

func _schedule_row_count() -> int:
	var n := 0
	for id in schedules:
		n += (schedules[id] as Array).size()
	return n

func _unlock_row_count() -> int:
	var n := 0
	for id in unlocks:
		n += (unlocks[id] as Array).size()
	return n

# ---------------- 查询 ----------------

func def_of(id: StringName) -> NpcDef:
	return defs.get(id, null)

func has(id: StringName) -> bool:
	return defs.has(id)

func all_ids() -> Array:
	return defs.keys()

func name_of(id: StringName) -> String:
	var d: NpcDef = def_of(id)
	return d.display_name if d != null else str(id)

func title_of(id: StringName) -> String:
	var d: NpcDef = def_of(id)
	return d.title if d != null else ""

func color_of(id: StringName) -> Color:
	var d: NpcDef = def_of(id)
	return d.color if d != null else Color.WHITE

func schedule_of(id: StringName) -> Array:
	return schedules.get(id, [])

func unlocks_of(id: StringName) -> Array:
	return unlocks.get(id, [])

## 已经达到的解锁项（hearts <= 当前心数）
func unlocks_reached(id: StringName, hearts: int) -> Array:
	var out: Array = []
	for u in unlocks_of(id):
		if int(u["hearts"]) <= hearts:
			out.append(u)
	return out

## 下一档还没拿到的解锁（提示条「再聊 1 心解锁 XX」用）；全拿完返回 {}
func next_unlock(id: StringName, hearts: int) -> Dictionary:
	for u in unlocks_of(id):
		if int(u["hearts"]) > hearts:
			return u
	return {}

# ---------------- 台词（散文放脚本，不进 CSV）----------------

## 每人的自我介绍 + 高好感台词
const GREET := {
	&"masa": {
		"intro": ["哟，新来的场主？我是玛莎，杂货铺是我开的。",
			"种子、肥料、饲料，缺什么来找我 —— 别赊账。"],
		"warm": ["你最近来得勤啊。给你留了批好种子，别跟别人说。",
			"我年轻时也想过开牧场。算了，看你的就行。"],
	},
	&"zhou": {
		"intro": ["铁匠老周。你这锄头我看过，钢口太软。",
			"想升级工具就攒钱，别拿石头来糊弄我。"],
		"warm": ["工具这东西，用顺手了就有感情。你那把锄头也是。",
			"哪天你牧场的活干完了，来铺子里坐坐。"],
	},
	&"kui": {
		"intro": ["我是小葵，兽医。动物不舒服就快来找我。",
			"记住：它们不会说话，所以你得学会看。"],
		"warm": ["你照顾动物的样子，我记在心里了。",
			"别硬撑。兽医也会累，场主也会。"],
	},
	&"hai": {
		"intro": ["阿海。天亮就出船，中午回来，风雨不改。",
			"你牧场那些牛……闻起来比海风还重。"],
		"warm": ["今天鱼群很密。要不要跟我出海一趟？",
			"海上有句话：耐心的人，鱼自己会来。"],
	},
	&"lin": {
		"intro": ["林，农学研究所的。我在记录这一带作物的长势。",
			"你要是种出奇怪的变异株，务必告诉我。"],
		"warm": ["你的数据很有价值。真的，不是客套。",
			"我年轻时也觉得自己只需要数据。后来发现还需要有人陪着看。"],
	},
	&"mia": {
		"intro": ["我是米娅！我知道牧场里每只动物的名字！",
			"那只叫布伦希尔德的牛，今天心情不好哦。"],
		"warm": ["今天能带我一起喂动物吗？我保证不吵。",
			"等我长大，也要开一家有好多动物的牧场！"],
	},
	&"chen": {
		"intro": ["老陈。这片牧场以前是我在管，现在归你了。",
			"棚舍要怎么摆，问我就行 —— 我拆过三次。"],
		"warm": ["你把牧场养得比我那时候好。我不说第二遍。",
			"有些话我攒了很多年，等你再熟一点再说。"],
	},
	&"su": {
		"intro": ["苏。旅行商人。每个季节的第 7、14、21 天我会来。",
			"各地的东西我都收，各地的话我都听。"],
		"warm": ["你身上的故事越来越重了。要买本空白册子吗？",
			"我见过很多牧场主。走到最后的，往往不是为了赚钱。"],
	},
}

## 好感分档的通用问候（没到「温暖」档时用）
const TIER_LINES := [
	["……", "你好。"],                                                  # 0-1 心
	["嗯，路过得还行吧？", "牧场最近怎么样。"],                          # 2-3 心
	["你来了。今天天气不错，正适合干活。", "有空就多来坐坐。"],          # 4-5 心
	["又是你啊。", "我这儿给你留着位置呢。"],                          # 6-7 心
	["来了？我刚还想着你会不会来。", "有事没事都可以来。"],              # 8-9 心
]

## 一次对话的台词（含「第一次见面」）
func greeting_lines(id: StringName, state: NpcState) -> Array:
	var g: Dictionary = GREET.get(id, {})
	var lines: Array = []
	if state == null:
		return ["……"]
	if not state.met:
		lines = (g.get("intro", []) as Array).duplicate()
		if lines.is_empty():
			lines = ["第一次见。我是%s。" % name_of(id)]
		return lines
	var h := state.hearts()
	if h >= 6 and g.has("warm"):
		return (g.get("warm", []) as Array).duplicate()
	var tier := clampi((h - 1) / 2, 0, TIER_LINES.size() - 1) if h >= 2 else 0
	return (TIER_LINES[tier] as Array).duplicate()

## 提示条：名字 + 心数 + 日程里正在干什么
func status_text(id: StringName, state: NpcState, action: String) -> String:
	var h := 0 if state == null else state.hearts()
	var hearts := ""
	for i in range(NpcState.MAX_HEARTS):
		hearts += "♥" if i < h else "♡"
	var a := action if action != "" else "在忙"
	return "%s（%s） %s %s" % [name_of(id), title_of(id), hearts, a]
