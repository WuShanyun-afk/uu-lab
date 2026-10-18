# 模块 10（你的清单里叫「模块 8」）· NPC 与剧情

> 完成于 2026-10-18。前置：模块 1（核心框架）、模块 6（棚舍与美术）✅
> 验收：`tests/test_module10.gd` —— **370 项断言全绿**；全量 15 个套件无回归。
> 存档升 **v3**（`npcs` + `story` 两段）。

## 1. 需求对照

| # | 需求 | 落在哪 |
|---|---|---|
| 1 | 6–8 位村民 + 好感度系统 | `data/npcs.csv` 8 位（GDD §7 原班人马）· `NpcDef` / `NpcState` / `NpcRegistry` |
| 2 | 每个 NPC 有日程表（按时段移动） | `data/npc_schedules.csv` 23 行 · `NpcSchedule`（纯逻辑）· `NpcNode`（走过去） |
| 3 | 好感度解锁配方 / 工具 / 剧情 | `data/npc_unlocks.csv` 16 条 · `data/secret_recipes.csv` 3 条秘方 |
| 4 | 三条主线（遗信 / 小镇秘密 / 季节之神） | `scripts/story/story_data.gd` 20 个节点 · `StorySystem` |
| 5 | 三线交织 → 「牧场之心」隐藏结局 | 结局节点 + 取反条件 + 阶段/许可双闸 |

## 2. NPC 数据结构

### 2.1 `data/npcs.csv`（谁）

```
id,name,title,color,loved,liked,hated
```

| id | 名字 | 身份 | 送礼（喜欢 / 普通 / 讨厌） | 日程 |
|---|---|---|---|---|
| masa | 玛莎 | 杂货店老板娘 | 蜂蜜 +25 / 鸡蛋 +15 / 牛奶 −10 | 9–17 看店 |
| zhou | 老周 | 铁匠 | 精品奶酪 / 奶酪 / 蜂蜜 | 9–16 打铁 |
| kui | 小葵 | 兽医 | 牛奶 / 蛋黄酱 / 松露 | 10–16 看诊 |
| hai | 阿海 | 渔夫 | 上品松露 / 鸡蛋 / 奶酪 | 6–12 打渔 |
| lin | 林教授 | 农学家 | 羊驼毛 / 羊毛 / 鸡蛋 | 13–18 记录作物 |
| mia | 米娅 | 小女孩 | 蜂蜜 / 蛋黄酱 / 松露 | 15–19 在牧场玩 |
| chen | 老陈 | 牧场前辈 | 蜂蜜酒 / 奶酪 / 牛奶 | 18–23 喝酒 |
| su | 苏 | 旅行商人 | 松露 / 精品奶酪 / 羊毛 | 每季第 7/14/21 天 8–20 摆摊 |

### 2.2 四个类

| 类 | 位置 | 管什么 |
|---|---|---|
| `NpcDef` | `scripts/npc/npc_def.gd` | CSV 一行的强类型壳：名字 / 身份 / 立绘色 / 送礼三档 |
| `NpcState` | `scripts/npc/npc_state.gd` | **好感点数**（0–500）+ 见过面没 + 上次聊天/送礼日期 |
| `NpcRegistry` | `scripts/npc/npc_registry.gd` | 8 个人一张表 + 解锁汇总（折扣 / 秘方 / 被动 / 许可） |
| `NpcNode` | `scripts/npc/npc_node.gd` | 纯视图：`_draw()` 画人 + `move_toward` 走过去 + 被 E 到 |

### 2.3 好感数值（GDD §7）

| 动作 | 点数 | 说明 |
|---|---|---|
| 对话 | **+5** | 每个游戏日只算一次 |
| 普通礼物 | **+15** | 一天最多 2 份 |
| 喜欢的礼物 | **+25** | `loved` |
| 讨厌的礼物 | **−10** | `hated`，显式写，不靠「不喜欢＝讨厌」推 |
| 满心 | 500 点 = **10 心** | 50 点 / 心 |

为什么存点数而不是心数：一次送礼 +15 点 = 0.3 心，直接存整数心永远进不了位。
纯聊天满心要 100 天；聊天 + 送礼约 17 天 —— 一季 28 天，节奏刚好。

### 2.4 好感解锁表 `data/npc_unlocks.csv`

```
npc,hearts,kind,id,value,text
```

| kind | 含义 | 落地效果 |
|---|---|---|
| `price` | 折扣（`id` = seed / tool / medicine，`value` = 百分比） | 商店货架与**成交价同时**打折（同一个 `_discounted()`） |
| `recipe` | 秘方（`id` = `secret_recipes.csv` 的 output） | `GameState.unlock_recipe` → 加工坊出现该配方 |
| `tool` | 工具许可（`id` = golden） | 工具铺 Lv3 解锁（之前是灰的 + 写明原因） |
| `perk` | 被动（`id` = GameState.perks 的键） | 如 `immune_once`：跨日自动治好第一只病畜并消耗 |
| `story` | 剧情 / 许可（`id` = story_flags 的键） | `permit_expansion` 直接卡住第 5 阶段「小镇」 |

实际清单：16 条（玛莎 3/6、老周 4/8、小葵 5/9、阿海 4/7、林教授 5/8、米娅 3/7、老陈 6/9、苏 3/6）。

## 3. 日程表设计

### 3.1 `data/npc_schedules.csv`

```
npc,from_hour,to_hour,x,y,action,visible,days
```

- **小时是连续的 6.0–26.0**：`hour_of(minutes) = 6 + minutes / 60`（分钟 0 = 6:00，1200 = 次日 2:00）。
  别在别处再写一遍 +6，写两遍就会有一处忘。
- `visible = 0` 表示「人在家 / 收摊」——**不是删节点**。删了会把好感一起丢掉。
- `days` 是「本季第几天」白名单（分号分隔，如 `7;14;21`）——苏只在每季第 7/14/21 天出现。
  ⚠️ 别用逗号：CSV 的逗号是列分隔符，`7,14,21` 会被拆成三列（这个坑真踩过）。
- 匹配顺序 = CSV 行序，先匹配先赢：带 `days` 的专门行必须写在全天兜底行**前面**。
- 规则校验：测试断言每个人 23 行合计铺满 6:00–2:00（不带 days 的行），否则会「凭空消失」。

### 3.2 表现

`main._update_npcs()` 每帧把 `(目标位置, 在场吗, 在干什么)` 喂给 `NpcNode`，
节点自己 `move_toward` 走过去（速度 34 px/s）—— 看得见「玛莎从后门走到柜台」才叫日程表；
瞬移只会像 bug。开局 / 读档走 `snap_to()` 直接落位。

## 4. 对话系统设计

### 4.1 复用模块 5 的 `DialogueUI`（0 行改动）

`EventBus.dialogue_requested.emit(speaker, lines, color)` → 对话框逐句推进（E / 空格 / 回车，Esc 跳过）。
它只负责显示，**不生产内容**，所以 NPC 对话 / 剧情 / 觉醒三条来源共用一只框。

### 4.2 台词分两套放

| 类型 | 位置 | 为什么 |
|---|---|---|
| 村民日常台词 | `NpcDB.GREET`（脚本里的散文表） | 台词不是数值，塞 CSV 要转义引号，改一句要数逗号 |
| 剧情台词 | `StoryData.NODES[].lines` | 同上，而且要和节点条件写在一起才看得懂 |

日常台词分四档：**第一次见面**（`intro`，2 句）→ 0–1 心 → 2–3 心 → 4–5 心 → **6 心以上**（`warm`，2 句）。
`NpcDB.greeting_lines()` 只依赖「见没见过 + 几心」，没有随机 —— 测试能断言。

### 4.3 交互

| 键 | 行为 | 说明 |
|---|---|---|
| E | 说话 | 当天首次 +5 点，播台词；台词播完可能接一段剧情（见 §5.2 `pick_manual`） |
| G | 送礼面板 | 复用 `ShopUI`（价格 0、效果是好感），货架 = 背包里所有能送的东西，喜欢的东西排最前 |

送礼的每日上限在 **UI 与 `_give_gift()` 两处都判** —— 面板会灰掉，但连点 / 改存档都可能绕过去。

## 5. 剧情系统

### 5.1 节点结构（`StoryData.NODES`，共 20 个）

```gdscript
{
  id, quest, act, speaker, npc, lines, auto, requires, effects, ending
}
```

- `act` **必须从 1 连续推进**：`available()` 只放行「act == 已完成幕 + 1」的节点，
  否则会出现「第 3 幕先播、第 2 幕永远播不到」。
- `auto = false` 只能靠**找对人说话**触发（`pick_manual(ctx, npc_id)`）——
  老陈把信塞给你这种事，路过就自己弹会让玩家不知道是谁给的。
- `effects`：`gold` / `item` + `count` / `flag` / `quota` + `quota_count`。

### 5.2 条件 DSL（`StorySystem.check`）

| 写法 | 含义 |
|---|---|
| `flag:x` / `!flag:x` | 剧情标记（取反可用在任何条件前） |
| `hearts:masa>=3` | 某村民好感 |
| `quest:letter:act>=2` / `quest:letter:done` | 主线进度 |
| `quota:letter_frag>=4` | 计数器（日记碎片 / 试炼场次） |
| `stage>=5` `day>=2` `season==1` `gold>=1000` | 全局 |
| `item:honey>=2` | 背包数量（走 `ctx["count_item"]` 回调，本类不认识 GameState） |
| `perk:immune_once` / `met:chen` / `all_quests` | 被动 / 见过面 / 三线全通 |

### 5.3 剧情节点表

**A 爷爷的遗信（letter，6 幕，5 块碎片）**

| 幕 | 节点 | 触发条件 | 关键节点 |
|---|---|---|---|
| 1 | letter_1 | `day>=2` + `hearts:chen>=1` + **找老陈说话** | 拿到信，`letter_started` |
| 2 | letter_2 | `act>=1` + `hearts:masa>=2` | 玛莎账本里夹着碎片 1，+木材×10 |
| 3 | letter_3 | `act>=2` + `hearts:zhou>=2` | 老周工具箱里碎片 2 |
| 4 | letter_4 | `act>=3` + `hearts:lin>=2` | 林教授档案里碎片 3，引出「答案在机器里」（**接 B 线**） |
| 5 | letter_5 | `act>=4` + `hearts:su>=2` | 苏十年前收的碎片 4，+300G |
| 6 | letter_6 | `act>=5` + `quota:letter_frag>=4` + `hearts:hai>=2` | 阿海船底最后一块 → 拼出「牧场会记得每一个对它好的人」，+800G +木材×20，`quest_letter_done` |

**B 小镇的秘密（secret，5 幕）**

| 幕 | 节点 | 触发条件 | 关键节点 |
|---|---|---|---|
| 1 | secret_1 | `stage>=3` + `hearts:zhou>=2` | 老周提旧矿区，`secret_mine_known` |
| 2 | secret_2 | `act>=1` + `hearts:chen>=3` | 老陈说矿底下是「一台睡着的东西」，`secret_mine_open` |
| 3 | secret_3 | `act>=2` + `flag:secret_mine_open` + `hearts:zhou>=4` | 机器醒：「我要蜂蜜和牛奶」 |
| 4 | secret_4 | `act>=3` + `item:honey>=2` + `item:milk_large>=1` + **找老周说话** | 交出蜂蜜牛奶 → 小镇是被「记」下来的，+1200G +蜂蜜酒×1 |
| 5 | secret_5 | `act>=4` + `flag:quest_secret_done` + `hearts:zhou>=6` | 老周「原来铁会记得」，+500G |

**C 季节之神（season，5 幕，一季一幕）**

| 幕 | 节点 | 触发条件 | 试炼内容 |
|---|---|---|---|
| 1 | season_1 | `stage>=2` + `season==0` | 春：地里同时活十株作物 |
| 2 | season_2 | `act>=1` + `season==1` | 夏：最热的一天动物全吃饱 |
| 3 | season_3 | `act>=2` + `season==2` | 秋：累计卖出 100 件 |
| 4 | season_4 | `act>=3` + `season==3` | 冬：最冷的日子去看所有动物 |
| 5 | season_5 | `act>=4` + `quota:season_trial>=4` | 四季归位，+1500G，`quest_season_done` |

**结局分支（4 个）**

| 节点 | 触发条件 | 结果 |
|---|---|---|
| ending_letter | `quest_letter_done` + 另两条**未**完成 | 「爷爷的遗信」END |
| ending_secret | `quest_secret_done` + 另两条未完成 | 「小镇的记忆」END |
| ending_season | `quest_season_done` + 另两条未完成 | 「季节之神」END |
| **heart_of_ranch** | 三条主线全通 + `stage>=5` | **「牧场之心」隐藏结局**，+5000G，`heart_of_ranch` |

> 「三条线交织」不是文案修辞，是**数据上的咬合**：
> A 的第 4 幕把玩家推向 B 的机器；B 的第 3 幕要的蜂蜜牛奶正好是 C 的春之试炼产物；
> C 的收束台词直接点名「去把另外两件事做完」；而 A 线第 1 幕又卡在 `day>=2` + 老陈 1 心。
> 所以玩家不会「先清完 A 再去 B」，而是被好感度门禁推着交叉推进。

### 5.4 三条线的交织点

```
letter_4 ──「答案在机器里」──▶ secret_1..3（矿区 / 机器）
secret_3 ──「要蜂蜜和牛奶」──▶ 存档里的蜂蜜 + 大罐牛奶（春之试炼 / 牧场产出）
season_5 ──「去做完另外两件」──▶ 回到 A / B
三条全通 + stage 5 ──▶ heart_of_ranch
```

## 6. 存档 v3

- `SaveSystem.VERSION` 2 → **3**，新增两段：
  - `npcs`：`{masa: {id, points, met, talk_day, gift_day, gifts}, ...}`
  - `story`：`{done: {...}, acts: {letter: 3, ...}, counters: {...}, endings: [...]}`
- `migrate()` 2→3：老档补空段（谁都没见过、一段剧情没播）—— 语义正确，不用写特例。
- 只存真源：心数、解锁汇总、折扣全部读档后**现算**。
- 读档顺序：数据（`_npcs.from_dict` / `_story.from_dict`）→ 整批重建 `NpcNode` → 按日程 `snap_to` 落位。

## 7. 键位 / HUD

| 键 | 作用 |
|---|---|
| E | 说话 / 交互（村民优先于工具） |
| G | 对着村民开送礼面板 |
| E / 空格 / 回车 | 对话下一句；Esc 跳过 |

HUD 第二行末尾多了 `♥总心数 剧情已播节点数`；村民头顶名牌 = 名字 + ♥心数 + `（正在干什么）`。

## 8. 踩过的坑

1. **CSV 里 `days=7,14,21` 会被逗号拆列** → 改用分号 `7;14;21`。多值列一定要选一个不与 CSV 分隔符冲突的字符。
2. **带 `days` 的行必须排在兜底行前面**，否则苏永远不出现（先匹配先赢）。
3. **`bool("字符串")` 在 GDScript 里是运行时报错**（`Nonexistent 'bool' constructor`）——
   判空/判真要用 `str(x) == ""` 或 `x != null`，别拿 bool() 套字符串。
4. **`var x := 未标注类型的表达式`**（比如 `m._npcs`，因为 `m` 是 untyped 的 `instantiate()` 结果）
   会报 `Cannot infer the type`。测试里必须写 `var x: int = ...`（模块 9 踩过，这次又踩了 5 处）。
5. **“不报错就算过”是幻觉**：Python 测试脚本 300 秒没退出 = GDScript 解析失败导致场景没 quit，
   一定要把输出重定向到文件再 grep（管道会吃掉增量输出）。
6. **阶段 5 与老陈 9 心咬在一起**：`_refresh_stage()` 里没有 `permit_expansion` 就把阶段压回 4。
   好处是两条系统互相引用；坏处是**纯逻辑测试**仍在测 `RanchStage.next_stage(4, ...) == 5`（规则没变，
   闸门在主循环这一层）—— 所以模块 9 的测试不用改。
7. **秘方不能塞进 `RecipeDB.all_ids()`**：模块 7 的验收把那里钉死成 11 条。
   新增 `all_ids_all()` / `available_ids()` / `is_secret()`，老口径一字不动。
8. **`_give_gift()` 要二次校验每日上限**：UI 灰掉不等于数据层拦得住。
9. **`endgame()` 要跳过 `endings_seen`**，不能只看 `done` —— 读档后两者可能只登记了一个。
10. **每帧只播一个剧情节点**：三线交织时同一帧可能同时满足 3 个节点，
    全塞进对话框队列会让玩家一口气读 15 句还分不清是哪条线。

## 9. 文件清单

新增：

```
data/npcs.csv                     8 位村民
data/npc_schedules.csv            23 行日程
data/npc_unlocks.csv              16 条好感解锁
data/secret_recipes.csv           3 条秘方（好感解锁）
scripts/npc/npc_def.gd            NpcDef
scripts/npc/npc_state.gd          NpcState（好感点数 / 每日上限）
scripts/npc/npc_registry.gd       NpcRegistry（8 人一张表 + 解锁汇总）
scripts/npc/npc_schedule.gd       NpcSchedule（纯逻辑）
scripts/npc/npc_node.gd           NpcNode（画面 + 碰撞 + 走动）
scripts/data/npc_db.gd            NpcDB（autoload，三张表 + 台词表）
scripts/story/story_data.gd       StoryData（20 节点 + 4 主线元信息）
scripts/story/story_system.gd     StorySystem（条件 DSL / 幕推进 / 结局）
tests/test_module10.gd / .tscn    370 项断言
tests/shot_module10.gd / .tscn    5 张截图
_uu/模块10-NPC与剧情.md            本文档
```

改动：

```
project.godot                     + NpcDB autoload
data/products.csv                 + 3 个秘方产物（蜂蜜黄油 / 香草奶酪 / 烟熏奶酪）
scripts/data/recipe_db.gd         秘方表：all_ids() 仍 11 条，新增 available_ids()
scripts/game_state.gd             story_flags / perks / secret_recipes（+ 进存档）
scripts/save/save_system.gd       VERSION 3 + migrate 2→3
scripts/event_bus.gd              npc_* / story_* 信号
scripts/player.gd                 （无改动：村民就是 Interactable，探针自动扫）
scripts/main.gd                   村民生成 / 日程 / 对话 / 送礼 / 解锁 / 剧情 / 折扣 / 存档
scenes/main.tscn                  + NpcRoot（YSortRoot 下）
_uu/run_tests.py                  注册模块 10 套件
```

## 10. 还没做的（下一批）

- 对话选项分支（现在是「条件决定分支」，没有玩家选项按钮）
- 立绘真素材（现在是纯色块 + 名字牌）
- NPC 走路动画（现在只有位置插值）
- 每周 3 心以上「自动触发一次剧情事件」（GDD §7 原话）——节点表已经能表达，缺一个周计数器
- 图鉴里的 NPC 分类（8/8 → 牧场扩建许可）与节日 / 生日事件
