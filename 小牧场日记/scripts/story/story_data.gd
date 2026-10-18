class_name StoryData
extends RefCounted
## 剧情节点表（模块 10 需求 4）—— **纯数据**，不碰节点、不碰 UI
##
## 三条主线（需求 4）+ 一条隐藏结局（需求 5）：
##   A 爷爷的遗信     letter  6 幕  五块日记碎片散在五位村民手里
##   B 小镇的秘密     secret  5 幕  旧矿区 + 会说话的机器
##   C 季节之神       season  5 幕  四季精灵的四场试炼 + 收束
##   隐藏结局         heart_of_ranch（牧场之心）
##
## 节点结构（StorySystem 就是照这个跑的）：
##
##   {
##     id:        StringName      唯一 id，也是存档里的键
##     quest:     StringName      &"letter" / &"secret" / &"season" / &"ending"
##     act:       int             第几幕（同一 quest 必须从 1 连续推进）
##     speaker:   String          对话框标题
##     npc:       StringName      说话人（取立绘颜色用；&"" = 旁白）
##     lines:     Array[String]   逐句台词
##     auto:      bool            true = 条件一满足就自己播（不用去找人）
##     requires:  Array[String]   触发条件（见 StorySystem.check 的语法）
##     effects:   Dictionary      {gold, item, count, flag, quota, unlock_recipe, perk}
##     ending:    bool            结局节点（播完进入「已通关」状态）
##   }
##
## 为什么剧情表用 GDScript 而不是 CSV：
##   这里是**散文**（一段段台词），不是可调数值。CSV 里塞多行台词要靠 `|` 或 `\n`
##   转义，改一句台词就得数引号 —— 模块 3 的作物表只有 8 列就已经很难读了。
##   数值表（NPC / 日程 / 解锁 / 秘方）依然在 CSV，分工是按「数据性质」而不是按模块。
##
## 交织设计（需求 5）：
##   · A 的碎片 2 在 B 的老周手里（两人是旧识）
##   · C 的春之试炼要给 B 的机器送蜂蜜（机器是季节之神留下的）
##   · 三条线都必须过 → 牧场之心；只过一条 → 各自的结局分支
##   所以玩家不会「先清完 A 再去 B」，而是被好感度门禁推着交叉推进。

## 三条主线 + 隐藏线的元信息
const QUESTS := {
	&"letter": {
		"name": "爷爷的遗信", "color": Color("#C9A227"),
		"bridge": "第 1 幕由老陈交给你；之后五块碎片分散在五位村民手里。",
	},
	&"secret": {
		"name": "小镇的秘密", "color": Color("#7A5AA0"),
		"bridge": "矿区在牧场西边的旧路尽头；会说话的机器只在老周在场时开口。",
	},
	&"season": {
		"name": "季节之神", "color": Color("#3F8F6A"),
		"bridge": "每换一季，花园喷泉上就多一位精灵；四位都见过才算一场试炼。",
	},
	&"ending": {
		"name": "牧场之心", "color": Color("#E8C05A"),
		"bridge": "三条线全部走完，再回秘密花园的喷泉。",
	},
}

## 节点表。顺序 = 同一帧内多节点同时可触发时的播报优先级（从上往下）
const NODES: Array = [
	# ================= A · 爷爷的遗信 =================
	{
		"id": &"letter_1", "quest": &"letter", "act": 1,
		"speaker": "老陈", "npc": &"chen", "auto": false,
		"requires": ["day>=2", "hearts:chen>=1"],
		"lines": [
			"你站住。你爷爷走之前，把一样东西放在我这儿。",
			"他说：等那孩子把牧场重新开起来，再给他。",
			"一封信。没有信封，只有一张纸 —— 他写字从来不肯写完整。",
		],
		"effects": {"flag": "letter_started"},
	},
	{
		"id": &"letter_2", "quest": &"letter", "act": 2,
		"speaker": "玛莎", "npc": &"masa", "auto": true,
		"requires": ["quest:letter:act>=1", "hearts:masa>=2"],
		"lines": [
			"（你提到那封信，玛莎翻出一本旧记账本。）",
			"你爷爷每年都在我这儿赊种子。最后一笔……一直没结。",
			"他把一页纸夹在账本里，说是「抵账」。",
		],
		"effects": {"quota": "letter_frag", "quota_count": 1, "item": "wood", "count": 10},
	},
	{
		"id": &"letter_3", "quest": &"letter", "act": 3,
		"speaker": "老周", "npc": &"zhou", "auto": true,
		"requires": ["quest:letter:act>=2", "hearts:zhou>=2"],
		"lines": [
			"（老周把工具箱倒过来敲了两下，掉出一张折痕很深的纸。）",
			"你爷爷的工具全是我打的。他要求高，脾气更差。",
			"这张纸他塞在工具垫下面，说「等有人把锄头用坏再来拿」。",
		],
		"effects": {"quota": "letter_frag", "quota_count": 1},
	},
	{
		"id": &"letter_4", "quest": &"letter", "act": 4,
		"speaker": "林教授", "npc": &"lin", "auto": true,
		"requires": ["quest:letter:act>=3", "hearts:lin>=2"],
		"lines": [
			"（林从一份泛黄的记录副本里抽出一页。）",
			"这份土壤记录是你爷爷送的。他说「有人在替我看这些，我就放心了」。",
			"纸的背面写着一行字：『水从哪里来，答案在机器里。』",
		],
		"effects": {"quota": "letter_frag", "quota_count": 1},
	},
	{
		"id": &"letter_5", "quest": &"letter", "act": 5,
		"speaker": "苏", "npc": &"su", "auto": true,
		"requires": ["quest:letter:act>=4", "hearts:su>=2"],
		"lines": [
			"（苏从货车上拿下一个用布包着的小包。）",
			"十年前我在别的镇上收过一页纸，卖我的人说「是给一个牧场的」。",
			"我一直在等这个牧场出现。现在它出现了。",
		],
		"effects": {"quota": "letter_frag", "quota_count": 1, "gold": 300},
	},
	{
		"id": &"letter_6", "quest": &"letter", "act": 6,
		"speaker": "阿海", "npc": &"hai", "auto": true,
		"requires": ["quest:letter:act>=5", "quota:letter_frag>=4", "hearts:hai>=2"],
		"lines": [
			"（阿海从船底摸出一个防水油布包。）",
			"你爷爷每次出海都问我：『海的那边也有牧场吗？』",
			"最后那页纸，他让我替他扔进海里。我没扔。",
			"（五页纸拼起来，是一句话：「牧场会记得每一个对它好的人。」）",
		],
		"effects": {"flag": "quest_letter_done", "gold": 800, "item": "wood", "count": 20},
	},

	# ================= B · 小镇的秘密 =================
	{
		"id": &"secret_1", "quest": &"secret", "act": 1,
		"speaker": "老周", "npc": &"zhou", "auto": true,
		"requires": ["stage>=3", "hearts:zhou>=2"],
		"lines": [
			"牧场最近来了不少人。你没发现吗？",
			"西边那条旧路，尽头有个区 —— 矿早废了，但路还在。",
			"晚上别去。这话我说过三次，没人听。",
		],
		"effects": {"flag": "secret_mine_known"},
	},
	{
		"id": &"secret_2", "quest": &"secret", "act": 2,
		"speaker": "老陈", "npc": &"chen", "auto": true,
		"requires": ["quest:secret:act>=1", "hearts:chen>=3"],
		"lines": [
			"你爷爷年轻时在矿区干过两年。",
			"他说矿底下不是矿，是「一台睡着的东西」。",
			"我当他是累糊涂了。直到他走的那年，矿区封了。",
		],
		"effects": {"flag": "secret_mine_open"},
	},
	{
		"id": &"secret_3", "quest": &"secret", "act": 3,
		"speaker": "？", "npc": &"zhou", "auto": true,
		"requires": ["quest:secret:act>=2", "flag:secret_mine_open", "hearts:zhou>=4"],
		"lines": [
			"（矿区深处，一台锈迹斑斑的机器突然亮起一格灯。）",
			"「……有人在吗。」",
			"「上一次有人来，是三十七年前。他答应过我一样东西。」",
			"「蜂蜜。还有牛奶。他说那是最诚实的两样。」",
		],
		"effects": {"flag": "secret_machine_awake"},
	},
	{
		"id": &"secret_4", "quest": &"secret", "act": 4,
		"speaker": "会说话的机器", "npc": &"zhou", "auto": false,
		"requires": ["quest:secret:act>=3", "item:honey>=2", "item:milk_large>=1"],
		"lines": [
			"「蜂蜜。牛奶。你带来了。」",
			"「那我告诉你一件事：这座小镇不是建的，是被『记』下来的。」",
			"「我记了三十七年。现在交给你。」",
		],
		"effects": {"flag": "quest_secret_done", "gold": 1200, "item": "mead", "count": 1},
	},
	{
		"id": &"secret_5", "quest": &"secret", "act": 5,
		"speaker": "老周", "npc": &"zhou", "auto": true,
		"requires": ["quest:secret:act>=4", "flag:quest_secret_done", "hearts:zhou>=6"],
		"lines": [
			"（老周听完，很久没说话。）",
			"我在这镇子上打了四十年铁。原来铁会记得。",
			"谢了。以后你的工具，我不收钱。",
		],
		"effects": {"gold": 500},
	},

	# ================= C · 季节之神 =================
	{
		"id": &"season_1", "quest": &"season", "act": 1,
		"speaker": "春之精灵", "npc": &"lin", "auto": true,
		"requires": ["stage>=2", "season==0"],
		"lines": [
			"（花园喷泉上浮起一团淡绿色的光。）",
			"「你种下的第一颗种子，我看见了。」",
			"「春之试炼：让这片地上同时活着十株作物。做到了再来。」",
		],
		"effects": {"quota": "season_trial", "quota_count": 1, "flag": "season_spring"},
	},
	{
		"id": &"season_2", "quest": &"season", "act": 2,
		"speaker": "夏之精灵", "npc": &"hai", "auto": true,
		"requires": ["quest:season:act>=1", "season==1"],
		"lines": [
			"（喷泉的水忽然变得滚烫。）",
			"「暴晒、暴雨、干旱 —— 夏天是最不客气的季节。」",
			"「夏之试炼：在最热的一天里，让你的动物全都吃饱。」",
		],
		"effects": {"quota": "season_trial", "quota_count": 1, "flag": "season_summer"},
	},
	{
		"id": &"season_3", "quest": &"season", "act": 3,
		"speaker": "秋之精灵", "npc": &"masa", "auto": true,
		"requires": ["quest:season:act>=2", "season==2"],
		"lines": [
			"（喷泉上漂满金色的落叶。）",
			"「收获之后，人会开始想：这一年值得吗。」",
			"「秋之试炼：卖出一百件东西。让这镇子记住你的名字。」",
		],
		"effects": {"quota": "season_trial", "quota_count": 1, "flag": "season_autumn"},
	},
	{
		"id": &"season_4", "quest": &"season", "act": 4,
		"speaker": "冬之精灵", "npc": &"chen", "auto": true,
		"requires": ["quest:season:act>=3", "season==3"],
		"lines": [
			"（喷泉结了一层薄冰，冰下有光在走。）",
			"「什么都长不出来的时候，你还来吗？」",
			"「冬之试炼：在最冷的日子里，去看一眼你所有的动物。」",
		],
		"effects": {"quota": "season_trial", "quota_count": 1, "flag": "season_winter"},
	},
	{
		"id": &"season_5", "quest": &"season", "act": 5,
		"speaker": "四季", "npc": &"", "auto": true,
		"requires": ["quest:season:act>=4", "quota:season_trial>=4"],
		"lines": [
			"（四团光同时落在喷泉里，水面平静得像一面镜子。）",
			"「四个试炼，你一个都没跳。」",
			"「牧场不是土地。是有人愿意每天回来。」",
			"「—— 去把另外两件事做完。然后回来。」",
		],
		"effects": {"flag": "quest_season_done", "gold": 1500},
	},

	# ================= 结局分支 =================
	{
		"id": &"ending_letter", "quest": &"ending", "act": 1,
		"speaker": "爷爷的遗信", "npc": &"chen", "auto": true, "ending": true,
		"requires": ["flag:quest_letter_done", "!flag:quest_secret_done", "!flag:quest_season_done"],
		"lines": [
			"（信纸在灯下泛着旧黄。）",
			"「孩子：牧场会记得每一个对它好的人。」",
			"（你把信压回抽屉。明天还要早起喂牛。）",
		],
		"effects": {},
	},
	{
		"id": &"ending_secret", "quest": &"ending", "act": 2,
		"speaker": "小镇的记忆", "npc": &"zhou", "auto": true, "ending": true,
		"requires": ["flag:quest_secret_done", "!flag:quest_letter_done", "!flag:quest_season_done"],
		"lines": [
			"（机器最后一声响，是一句没人听得懂的话。）",
			"（老周说：它在说谢谢。）",
			"（小镇的灯，一盏一盏亮到天亮。）",
		],
		"effects": {},
	},
	{
		"id": &"ending_season", "quest": &"ending", "act": 3,
		"speaker": "季节之神", "npc": &"", "auto": true, "ending": true,
		"requires": ["flag:quest_season_done", "!flag:quest_letter_done", "!flag:quest_secret_done"],
		"lines": [
			"（喷泉的光落回水里，四位精灵都不再说话。）",
			"（你知道它们还在。只是换了一个季节。）",
			"（牧场又安静下来了。）",
		],
		"effects": {},
	},
	{
		"id": &"heart_of_ranch", "quest": &"ending", "act": 4,
		"speaker": "牧场之心", "npc": &"", "auto": true, "ending": true,
		"requires": ["flag:quest_letter_done", "flag:quest_secret_done",
			"flag:quest_season_done", "stage>=5"],
		"lines": [
			"（三条线在喷泉底下接上了。）",
			"（爷爷的信、会记得的机器、四个季节 —— 它们说的是同一件事。）",
			"「牧场会记得每一个对它好的人。」",
			"（从今天起，这座牧场有了心。）",
			"——「牧场之心」END ——",
		],
		"effects": {"flag": "heart_of_ranch", "gold": 5000},
	},
]

## 按 id 索引（一次建好，别每次线性扫 —— 剧情每帧都在问「这个节点完了没」）
static func node(id: StringName) -> Dictionary:
	for n in NODES:
		if n["id"] == id:
			return n
	return {}

static func nodes_of_quest(quest: StringName) -> Array:
	var out: Array = []
	for n in NODES:
		if n["quest"] == quest:
			out.append(n)
	return out

## 三条主线的 id（结局不参与）
static func main_quests() -> Array:
	return [&"letter", &"secret", &"season"]

## 剧情里用到的物品（启动时校验一遍，写错 id 当场报错而不是玩到一半才崩）
static func referenced_items() -> Array:
	var out: Array = []
	for n in NODES:
		var e: Dictionary = n.get("effects", {})
		if e.has("item"):
			out.append(StringName(str(e["item"])))
	return out
