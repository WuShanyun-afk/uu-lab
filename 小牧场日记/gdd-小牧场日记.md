# 《小牧场日记》游戏设计文档 (GDD)

| 字段 | 值 |
|---|---|
| 项目代号 | `ranch-diary` |
| 版本 | v1.0 |
| 引擎 | Godot 4.7.x（最新 stable：**4.7.2-stable**） |
| 平台 | Windows / macOS / Linux（Steam）+ iOS / Android |
| 视角 | 2D 俯视 Top-Down |
| 美术 | 32×32 px 地块，温暖复古调色板，`Nearest` 过滤 + 整数倍缩放 |
| 单次游玩 | 15–30 分钟（= 1–2 个游戏内日） |
| 长线目标 | 112 游戏日（1 年）达成「五星牧场」评级 |
| 商业化 | 买断制，Steam 首发 + 移动端付费下载，无内购 |

---

## 0. 设计支柱

1. **轻压力**：没有任何操作会导致不可逆失败。动物不会真死（默认），作物不会永久枯萎，漏了一天只是「数值变差」，不是「重开」。
2. **节奏可感知**：一天 12 分钟，有清晰的「清晨抢挤奶 → 白天放牧跑腿 → 黄昏特殊窗口 → 夜晚加工钓鱼」四段节奏。
3. **数字可预测**：所有产出、价格、好感变化都是玩家可以心算的确定值。随机只出现在「天气」和「品质」，不藏在黑箱里。
4. **一屏一件事**：单屏最多 3 个待办气泡，不做任务列表轰炸。

---

## 1. 时间系统

### 1.1 昼夜循环参数

| 参数 | 值 | 说明 |
|---|---|---|
| 游戏内 1 日 | 6:00 → 次日 2:00 | 共 20 游戏小时 |
| 现实时长 | **12 分钟**（可调 6/12/24 分钟） | 设置项 `day_length` |
| 1 游戏小时 | 36 现实秒 | 12×60÷20 |
| 1 游戏分钟 | 0.6 现实秒 | |
| 逻辑 tick | **10 游戏分钟 / 6 现实秒** | 全天 120 tick |
| 强制入睡 | 2:00 | 体力归零，自动存档 |
| 体力 | 100 点，6:00 满血 | 见 §1.4 |

### 1.2 时段划分与光照

| 时段 | 时钟 | 环境光 RGB | 覆盖色/混合 | 环境音 | 玩法含义 |
|---|---|---|---|---|---|
| 清晨 | 6:00–9:00 | `#FFD9A0` | 暖橙，multiply 15% | 鸟鸣 | **挤奶黄金窗口**，动物活跃 |
| 白天 | 9:00–17:00 | `#FFFFFF` | 无 | 无 | 商店营业，NPC 外出，放牧 |
| 黄昏 | 17:00–20:00 | `#FF9B5A` | 金红，multiply 25% | 虫鸣 | 部分动物回棚，**特殊事件窗口** |
| 夜晚 | 20:00–2:00 | `#2A3A6B` | 深蓝，multiply 45% | 夜虫/风 | 商店关闭，**钓鱼/采集/室内加工** |

**光照实现**：`CanvasModulate` 节点，颜色用 `Gradient` 关键帧插值（每 10 tick 采样一次），过渡时长 30 现实秒。室内建筑内部用独立 `PointLight2D` + 暖色，不受昼夜影响。

**时段过渡事件**：`EventBus.phase_changed(old, new)` 广播，动物/NPC/商店/BGM 各自订阅。

### 1.3 时间对玩法的影响（数值表）

| 行为 | 最佳时段 | 衰减规则 | 备注 |
|---|---|---|---|
| 挤奶 | 6:00–9:00 | 9:00 后每 2 小时产量 **-10%**（最低 50%） | 16:00 后完全不产 |
| 喂食 | 全天 | 漏喂 1 餐 → 次日好感 **-15** | 每日需喂满 `feed_freq` 次 |
| 放牧 | 9:00–17:00 | 雨天强制放牧 **-3 好感/小时** | 晴天放牧 +5 好感/小时（上限 +20/天） |
| 采集 | 6:00–18:00 | 夜间采集概率 **-50%** | 野莓/蘑菇/木材/石头 |
| 钓鱼 | 17:00–2:00 | 夜间稀有鱼概率 **+30%** | 白天仍可钓，只是稀有池变浅 |
| 商店 | 9:00–17:00 | 非营业时间无法交易 | 门口有告示牌显示营业状态 |
| 加工坊 | 全天 | 无 | 唯一 24 小时可用的产出途径 |
| NPC 拜访 | 9:00–17:00 | 夜间 NPC 全部回屋 | 好感事件固定在黄昏 17:00–20:00 |

### 1.4 体力消耗

| 动作 | 体力 | 备注 |
|---|---|---|
| 挥工具（锄/斧/镐/镰） | -2 | |
| 浇一格水 | -1 | 雨天自动浇水，不耗 |
| 抚摸动物 | -1 | |
| 刷毛/剪毛 | -3 | |
| 挤奶小游戏 | -5 | |
| 钓鱼（一次抛竿） | -4 | |
| 走路 | 0 | **不耗体力**（刻意设计，减少焦虑） |
| 睡觉恢复 | 全满 | 2:00 强制入睡只恢复 70% |
| 吃东西 | +20~+60 | 自家产出的加工品可食用 |

**体力耗尽**：不昏迷，只是所有动作耗时 ×2 且产出品质降一级。**惩罚是「变慢」，不是「停下」**。

---

## 2. 季节与天气系统

### 2.1 季节

| 季节 | 天数 | 草地色 | 树木 | 特殊 |
|---|---|---|---|---|
| 春 | 28 | `#7FC15E` | 嫩绿+粉花 | 多雨，草莓季 |
| 夏 | 28 | `#5FA83C` | 深绿浓密 | 牛产奶 **+20%**，暴风雨多 |
| 秋 | 28 | `#C9A44C` | 橙红落叶 | 南瓜/山药，作物售价 +10% |
| 冬 | 28 | `#E8EDF2` | 光秃+积雪 | 牛产奶 **-15%**，雪天禁放牧，羊驼解锁 |

- 一年 = **112 游戏日**（≈ 22.4 现实小时）
- 第 28 天为**过渡日**：当天不刷天气事件，18:00 触发季节祭典（NPC 聚集，可一次性大量提升好感）
- 冬季户外不可种植（温室除外）

### 2.2 天气概率表（每季每日 5:00 掷骰）

| 天气 | 春 | 夏 | 秋 | 冬 | 效果 |
|---|---|---|---|---|---|
| 晴 | 35% | 55% | 35% | 30% | 正常放牧，浇水照常 |
| 阴 | 25% | 15% | 30% | 30% | 无影响，光照 -10% |
| 雨 | 30% | 20% | 30% | — | **自动浇水**；动物不愿外出，需手动喂食；放牧 -3 好感/h |
| 暴风雨 | 10% | 10% | 5% | — | 雨的全部效果 + 栅栏 5% 概率损坏 + 雷击 3% 概率烧毁 1 格作物 |
| 雪 | — | — | — | **40%** | 草地不可放牧，**消耗储存饲料 ×2**；动物好感 +3/天（在棚内） |

- 暴风雪（雪的 15% 子概率）：当日所有室外活动体力 ×2
- 天气在**前一日 20:00 由电视/收音机预告**，准确率 85%（升级后可到 100%）
- 栅栏损坏：需 `木材 ×2` 修复，未修复期间动物有 20% 概率跑出牧场（次日自动寻回，好感 -5）

### 2.3 天气 × 季节 × 动物的交互矩阵

| 动物 | 晴 | 雨 | 雪 |
|---|---|---|---|
| 奶牛 | 放牧 +5/h | 留棚 +3/天 | 留棚 +3/天，饲料 ×2 |
| 山羊 | 放牧 +5/h | 留棚 +3/天 | 留棚 +3/天 |
| 绵羊 | 放牧 +5/h，羊毛生长 +10% | 留棚 +3/天 | 留棚 +3/天 |
| 猪 | 户外才可能产松露 | 无松露 | 无松露 |
| 鸡/鸭/火鸡 | 户外活动 | 鸭 **鸭毛 ×2** | 留棚 +3/天 |
| 蜜蜂 | 晴天采蜜正常 | 采蜜暂停 | 采蜜暂停 |

---

## 3. 动物系统

### 3.1 动物总表（9 种 / 3 类）

**家畜类**

| 动物 | 购买价 | 每日产出 | 喂食频率 | 特殊互动 | 好感度效果 |
|---|---|---|---|---|---|
| 奶牛 | 800G | 牛奶 ×1–2 | 2 次/天 | 挤奶、刷毛 | ≥8 心：产**大罐牛奶**（售价 ×2） |
| 山羊 | 500G | 羊奶 ×1 | 2 次/天 | 挤奶、刷毛 | ≥6 心：额外产出奶酪原料 |
| 绵羊 | 600G | 羊毛（每 3 天） | 1 次/天 | 剪羊毛、刷毛 | ≥8 心：产**高级羊毛** |
| 猪 | 700G | 松露（户外，概率） | 1 次/天 | 抚摸 | ≥6 心：松露概率 **+30%** |

**家禽类**

| 动物 | 购买价 | 每日产出 | 喂食频率 | 特殊互动 | 好感度效果 |
|---|---|---|---|---|---|
| 鸡 | 200G | 鸡蛋 ×1 | 1 次/天 | 抚摸、抱抱 | ≥8 心：金蛋概率 **+15%** |
| 鸭 | 300G | 鸭蛋 ×1 / 鸭毛 | 1 次/天 | 抚摸 | ≥6 心：雨天产鸭毛 ×2 |
| 火鸡 | 400G | 火鸡蛋（每 2 天） | 1 次/天 | 抚摸 | ≥8 心：节日售价 **+50%** |

**特殊类**

| 动物 | 解锁条件 | 产出 | 特殊互动 |
|---|---|---|---|
| 羊驼 | 第 1 年冬季 | 高级毛线（每 4 天） | 抚摸、刷毛；≥9 心产**彩虹毛线** |
| 蜜蜂 | 购买蜂箱 | 蜂蜜（每 3 天） | 无需喂食，但蜂箱 5 格内需有花田 |

### 3.2 成长阶段

| 动物 | 幼年 → 成年 | 幼年特性 |
|---|---|---|
| 鸡 | 3 天 | 无产出，好感获取 **+50%** |
| 鸭 | 4 天 | 同上 |
| 火鸡 | 5 天 | 同上 |
| 山羊 | 5 天 | 同上 |
| 绵羊 | 5 天 | 同上 |
| 猪 | 5 天 | 同上 |
| 奶牛 | 7 天 | 同上 |
| 羊驼 | 8 天 | 同上 |
| 蜜蜂 | — | 直接成熟 |

- 幼年动物模型为成年的 **70% 缩放**，动画帧率 ×0.8
- 幼年无法繁殖，占用栏位 = 0.5

### 3.3 好感度系统

- 每只动物 **0–10 心**，1 心 = **100 好感点**（满值 1000）

**获取**

| 行为 | 好感 | 上限/限制 |
|---|---|---|
| 正确喂食 | +10 / 次 | 按 `feed_freq` 计次 |
| 抚摸 | +5 / 次 | 每天 2 次 |
| 刷毛 | +8 / 次 | 每天 1 次 |
| 抱抱（家禽专属） | +6 / 次 | 每天 1 次 |
| 放牧（晴天） | +5 / 小时 | 每天上限 +20 |
| 雨天留棚 | +3 / 天 | 自动结算 |
| 雪天留棚 | +3 / 天 | 自动结算 |
| 高级饲料 | +15 / 次 | 取代普通喂食的 +10 |
| 挤奶小游戏 Perfect | +5 | 每次挤奶最多 1 次 |

**衰减**

| 行为 | 好感 |
|---|---|
| 漏喂 1 餐 | **-15** |
| 雨天强制放牧 | **-10** |
| 连续 3 天不互动 | 每天额外 **-5** |
| 生病未治疗 | **-20 / 天** |
| 跑出牧场 | -5 |

**好感等级效果**

| 等级 | 产出 | 概率修正 |
|---|---|---|
| 0–2 心 | 基础品质 | **10% 概率不产出** |
| 3–5 心 | 基础品质 | 稳定产出 |
| 6–8 心 | **银星**（售价 ×1.5） | 解锁特殊互动 |
| 9–10 心 | **金星**（售价 ×2） | 触发专属事件 + 专属台词 |

### 3.4 喂食与产出机制

| 操作 | 触发方式 | 小游戏 | 失败后果 |
|---|---|---|---|
| 喂食 | 手持饲料靠近点击 | 无 | 无 |
| 挤奶 | 6:00–9:00，手持挤奶器长按 | **节奏条**：3 次按准 | 产量 ×0.7，无额外好感 |
| 剪羊毛 | 每 3 天一次，手持剪刀点击 | 无 | 无 |
| 刷毛 | 手持刷子长按 2 秒 | 无 | 无 |
| 捡蛋 | 鸡舍内点击 | 无 | 无 |
| 松露 | 猪在户外自动挖掘 | 无 | 无 |

**挤奶节奏条规则**：判定窗口 40 tick 内出现 3 次；Perfect（±3 帧）→ 产量 +1；Good（±8 帧）→ 正常；Miss → 产量 ×0.7。

### 3.5 繁殖与生病

**繁殖**

| 条件 | 值 |
|---|---|
| 双方好感 | 均 ≥ 7 心 |
| 年龄 | 均为成年 |
| 建筑 | 需**繁殖棚**，且有空栏位 |
| 消耗 | 高级饲料 ×2 |
| 结果 | 次日 6:00 生成幼崽 |
| 冷却 | 该动物 7 天 |

**生病**

| 项 | 值 |
|---|---|
| 触发条件 | 好感 < 3 心 **且** 连续漏喂 ≥ 2 天 |
| 概率 | 每天 15% |
| 症状 | 产出 = 0，好感 -20/天，动画变为趴卧 |
| 治疗 | 药物 300G，1 天痊愈 |
| 恶化 | 3 天不治 → 好感归 0，送往村医（**默认不会死亡**，可在设置开启「硬核模式」） |

---

## 4. 种植系统

### 4.1 作物表（每季 6 种）

| 季节 | 作物 | 成长天数 | 种子价 | 售价 | 再生 | 施肥需求 |
|---|---|---|---|---|---|---|
| 春 | 芜菁 | 4 | 20 | 35 | — | 低 |
| 春 | 土豆 | 6 | 50 | 80 | — | 中 |
| 春 | 菠菜 | 5 | 35 | 60 | — | 低 |
| 春 | 大蒜 | 4 | 40 | 60 | — | 低 |
| 春 | 草莓 | 8 | 100 | 120 | 4 天 | 高 |
| 春 | 花椰菜 | 12 | 80 | 175 | — | 高 |
| 夏 | 小麦 | 4 | 15 | 25 | — | 低 |
| 夏 | 辣椒 | 5 | 30 | 40 | 3 天 | 低 |
| 夏 | 番茄 | 11 | 50 | 60 | 4 天 | 中 |
| 夏 | 蓝莓 | 13 | 80 | 50 | 4 天 | 高 |
| 夏 | 甜瓜 | 12 | 80 | 250 | — | 高 |
| 夏 | 玉米 | 14 | 150 | 50 | 4 天 | 中 |
| 秋 | 甜菜 | 6 | 20 | 100 | — | 低 |
| 秋 | 茄子 | 5 | 20 | 60 | 5 天 | 低 |
| 秋 | 蔓越莓 | 7 | 240 | 75 | 5 天 | 中 |
| 秋 | 向日葵 | 8 | 200 | 80 | — | 中 |
| 秋 | 山药 | 10 | 60 | 160 | — | 中 |
| 秋 | 南瓜 | 13 | 100 | 320 | — | 高 |
| 冬 | 温室：全部作物可用，成长速度 ×0.75 | | | | | |

- 品质分级同动物：基础 / 银星 ×1.5 / 金星 ×2.0
- 施肥：基础肥料 100G（品质概率 +10%），高级肥料 300G（+25%，但生长 +1 天）
- 未浇水 2 天 → 枯萎（浇水可复活）；未浇水 4 天 → 彻底枯死

---

## 5. 经济系统

### 5.1 原料与加工品价格表

| 原料 | 基础价 | 加工品 | 售价 | 加工耗时 | 增值 |
|---|---|---|---|---|---|
| 牛奶 | 100 | 奶酪 | 240 | 2 h | ×2.4 |
| 大罐牛奶 | 200 | 精品奶酪 | 480 | 3 h | ×2.4 |
| 羊奶 | 80 | 山羊奶酪 | 190 | 2 h | ×2.4 |
| 羊毛 | 120 | 毛线 | 280 | 3 h | ×2.3 |
| 高级羊毛 | 240 | 高级毛线 | 560 | 4 h | ×2.3 |
| 羊驼毛线 | 300 | — | — | — | — |
| 彩虹毛线 | 600 | 彩虹织物 | 1500 | 6 h | ×2.5 |
| 鸡蛋 | 50 | 蛋黄酱 | 120 | 2 h | ×2.4 |
| 金蛋 | 150 | 黄金蛋黄酱 | 360 | 3 h | ×2.4 |
| 鸭蛋 | 60 | 鸭蛋酱 | 140 | 2 h | ×2.3 |
| 鸭毛 | 70 | — | — | — | — |
| 火鸡蛋 | 90 | — | — | — | — |
| 松露 | 300 | 松露油 | 700 | 4 h | ×2.3 |
| 蜂蜜 | 150 | 蜂蜜酒 | 380 | 6 h | ×2.5 |

- 品质倍率在**原料**端计算，加工品继承原料品质倍率
- 加工坊槽位：Lv1 = 2 槽，Lv2 = 4 槽，Lv3 = 6 槽

### 5.2 建筑造价表

| 建筑 | 造价 | 容量 | 升级 | 升级价 |
|---|---|---|---|---|
| 鸡舍 | 1200G + 木材×20 | 4 只家禽 | Lv2 → 8 只 + 自动喂食器 | 2400G + 木材×30 |
| 畜棚 | 3000G + 木材×40 + 石×20 | 4 头家畜 | Lv2 → 8 头 + 自动挤奶 | 6000G + 木材×60 |
| 加工坊 | 2500G + 木材×30 | 2 槽 | Lv2 → 4 槽；Lv3 → 6 槽 | 5000G / 10000G |
| 蜂箱 | 600G + 木材×10 | 1 | — | — |
| 繁殖棚 | 4000G + 木材×50 | 1 胎 | — | — |
| 温室 | 8000G + 石×50 | 6 格 | Lv2 → 12 格 | 12000G |
| 仓库 | 1000G + 木材×15 | 容量 ×2 | Lv2 → ×3 | 2000G |

### 5.3 日常开销

| 项目 | 金额 | 周期 |
|---|---|---|
| 牧场维护费 | 50G | 每天 6:00 自动扣 |
| 动物饲料（干草） | 20G / 个 | 按需购买 |
| 高级饲料 | 50G / 个 | 按需购买 |
| 药物 | 300G / 份 | 按需 |
| 工具升级 | 见 §5.4 | 一次性 |

### 5.4 工具升级

| 工具 | Lv1 | Lv2（1500G + 铁×5） | Lv3（4000G + 金×3） |
|---|---|---|---|
| 锄头 | 1 格 | 3 格直线 | 3×3 |
| 洒水壶 | 1 格 | 3 格直线 | 3×3 |
| 斧头 | 小树 | 大树 | 巨型树桩 |
| 镐子 | 小石 | 大石 | 矿脉 |
| 镰刀 | 1 格 | 3 格 | 5 格 |

### 5.5 订单任务

- 每 3 天在信箱刷新 **2 个订单**，14:00 前送达
- 报酬 = 物品基础价 × 1.5 + 好感奖励
- 完成 10 个订单解锁「村中名人」成就与高级配方

---

## 6. 建造系统

| 系统 | 规则 |
|---|---|
| 放置 | 网格吸附（32px），只能放在空地，占位后不可通行 |
| 朝向 | 建筑固定朝向，门必须在南侧 |
| 拆除 | 返还 50% 材料，动物自动迁移到空栏位 |
| 移动 | 不可移动，只能拆+重建 |
| 栅栏 | 按格放置，有耐久 100；暴风雨 -20~-50 |
| 路面 | 泥路 / 石板路，泥路走路速度 +10% |

---

## 7. NPC 系统

| NPC | 身份 | 常驻点 | 营业/活动时间 | 好感解锁 |
|---|---|---|---|---|
| 玛莎 | 杂货店老板娘 | 商店 | 9:00–17:00 | 3 心：种子 9 折；6 心：解锁高级肥料 |
| 老周 | 铁匠 | 铁匠铺 | 9:00–16:00 | 4 心：工具升级 -20%；8 心：黄金工具 |
| 小葵 | 兽医 | 诊所 | 10:00–16:00 | 5 心：药物 -50%；9 心：动物免疫 1 次生病 |
| 阿海 | 渔夫 | 码头 | 6:00–12:00 | 4 心：送鱼饵；7 心：解锁稀有鱼点 |
| 林教授 | 农学家 | 温室 | 13:00–18:00 | 5 心：作物品质 +10%；8 心：解锁杂交种子 |
| 米娅 | 小女孩 | 广场/牧场 | 15:00–19:00 | 3 心：帮遛动物；7 心：动物好感 +5/天 |
| 老陈 | 牧场前辈 | 酒馆 | 18:00–23:00 | 6 心：解锁羊驼；9 心：解锁牧场扩建 |
| 苏 | 旅行商人 | 随机 | 每季第 7/14/21 天 | 出售稀有种子与异国动物 |

- 好感 0–10 心，送礼 +15（喜欢 +25，讨厌 -10），对话 +5（每天 1 次）
- 每周 3 心以上自动触发 1 次剧情事件

---

## 8. 图鉴系统

| 分类 | 条目数 | 完成奖励 |
|---|---|---|
| 动物 | 9 | 50%：高级饲料配方；100%：彩虹毛线配方 |
| 作物 | 24 | 50%：温室折扣；100%：金锄头 |
| 鱼类 | 18 | 50%：高级鱼竿；100%：传说鱼点 |
| 矿物 | 12 | 50%：宝石切割机；100%：无限体力药水 |
| 加工品 | 20 | 50%：加工速度 +20%；100%：加工坊 Lv3 免费 |
| NPC | 8 | 100%：牧场扩建许可 |

- 图鉴 UI：3 列网格，未解锁显示剪影，点击显示来源提示

---

## 9. UI / UX

### 9.1 布局

| 区域 | 位置 | 内容 |
|---|---|---|
| 顶栏 | 顶部 24px | 日期 / 时钟 / 天气 / 金币 / 体力条 |
| 工具栏 | 底部 40px | 10 格快捷栏，数字键 1–0 切换 |
| 交互气泡 | 世界内 | 动物头顶：心数 + 需求图标（🍽 饿 / 🥛 可挤 / 💤 睡） |
| 面板 | 右侧抽屉 | I 背包 / M 地图 / C 图鉴 / J 任务 / Esc 菜单 |

### 9.2 操作

| 平台 | 移动 | 主交互 | 次交互 | 菜单 |
|---|---|---|---|---|
| PC | WASD / 方向键 | 鼠标左键 / E | 鼠标右键 / F | Esc |
| 移动 | 虚拟摇杆 | 点击目标 | 长按 | 顶部按钮 |

### 9.3 无障碍与舒适度

- 字号可调 100% / 125% / 150%
- 色盲友好调色板（红绿替换为蓝黄）
- 可关闭挤奶小游戏（自动按 Good 结算）
- 可关闭天气灾害（暴风雨不再损坏栅栏）
- 自动存档 + 手动存档 3 槽

---

## 10. 技术架构（Godot 4.7）

### 10.1 项目设置

| 设置项 | 值 |
|---|---|
| `display/window/size/viewport_width` | 640 |
| `display/window/size/viewport_height` | 360 |
| `display/window/stretch/mode` | `canvas_items` |
| `display/window/stretch/aspect` | `keep` |
| `display/window/stretch/scale_mode` | **`integer`** |
| `rendering/textures/canvas_textures/default_texture_filter` | `Nearest` |
| 目标缩放 | 1280×720 (2×) / 1920×1080 (3×) / 2560×1440 (4×) |
| 渲染后端 | Forward+（PC）/ Mobile（移动端） |

> 32×32 地块 + 640×360 视口 = 一屏 **20 × 11.25** 格，与《星露谷》在 1280×720 下的视野一致。
> **整数倍缩放是硬要求**——非整数倍会让像素抖动模糊。

### 10.2 Autoload 单例

| 单例 | 职责 |
|---|---|
| `EventBus` | 全局信号总线，零耦合通信 |
| `GameClock` | tick 推进、时段判定、日/季切换 |
| `WeatherSystem` | 天气掷骰、天气效果派发 |
| `GameState` | 全局标志位、解锁进度、统计 |
| `SaveManager` | 存档序列化 / 反序列化 / 迁移 |
| `AudioDirector` | BGM 交叉淡入、SFX 池、时段/季节切换 |
| `DataRegistry` | 启动时加载全部 `.tres` 数据资源，供查询 |

### 10.3 数据驱动（关键）

所有平衡数值**不写进代码**，放在 `res://data/csv/*.csv`，用 godot-mcp-enhanced 的 `csv_to_resources` 转成自定义 Resource：

```
res://data/csv/animals.csv   → res://data/resources/animal_*.tres   (AnimalData)
res://data/csv/crops.csv     → res://data/resources/crop_*.tres     (CropData)
res://data/csv/items.csv     → res://data/resources/item_*.tres     (ItemData)
res://data/csv/recipes.csv   → res://data/resources/recipe_*.tres   (RecipeData)
res://data/csv/buildings.csv → res://data/resources/building_*.tres (BuildingData)
res://data/csv/npcs.csv      → res://data/resources/npc_*.tres      (NPCData)
res://data/csv/tuning.csv    → res://data/resources/tuning.tres     (TuningData)
```

```gdscript
# res://scripts/data/animal_data.gd
class_name AnimalData extends Resource

@export var id: StringName
@export var display_name: String
@export var price: int
@export var feed_freq: int              # 每天需喂食次数
@export var product_id: StringName
@export var product_min: int = 1
@export var product_max: int = 1
@export var product_interval_days: int = 1   # 绵羊=3, 羊驼=4
@export var grow_days: int
@export var category: int               # 0=家畜 1=家禽 2=特殊
@export var spritesheet: Texture2D
```

**收益**：改数值 = 改 CSV → `csv_to_resources` → 重启，不碰代码，不重编译。

### 10.4 场景树

```
Main (Node2D)
├── World (Node2D)
│   ├── GroundLayer (TileMapLayer)        # 草地/泥路/水面，y_sort 底层
│   ├── FarmLayer (TileMapLayer)          # 耕地/浇水状态
│   ├── BuildingLayer (TileMapLayer)      # 建筑占地
│   ├── YSortRoot (Node2D)                # y_sort_enabled = true
│   │   ├── Player (CharacterBody2D)
│   │   ├── Animals (Node2D)  ← Animal.tscn 实例
│   │   ├── NPCs (Node2D)     ← NPC.tscn 实例
│   │   └── Props (Node2D)
│   └── OverlayLayer (TileMapLayer)       # 树冠/屋顶遮挡，z_index 高
├── CanvasModulate (昼夜光照)
├── WeatherVFX (GPUParticles2D 雨/雪)
├── Camera2D (Player 子节点)
└── UI (CanvasLayer)
    ├── HUD (顶栏)
    ├── Hotbar
    ├── InventoryPanel
    ├── CodexPanel
    └── PauseMenu
```

> **Godot 4.3+ 用 `TileMapLayer`，不要再建 `TileMap` 节点**（已弃用）。分层 TileMapLayer 比单节点多 Layer 更利于 y-sort 与渲染批次。

### 10.5 存档格式

```json
{
  "version": 3,
  "meta": { "slot": 1, "saved_at": 1776000000, "playtime_sec": 4210 },
  "clock": { "day": 34, "season": 1, "year": 1, "minutes": 480 },
  "weather": { "today": "rain", "tomorrow": "clear" },
  "player": { "pos": [512, 384], "gold": 4820, "energy": 78,
              "inventory": [{"id":"hay","count":12,"quality":0}] },
  "animals": [
    { "uid": "cow_001", "data": "cow", "name": "小花", "age_days": 12,
      "affection": 640, "fed_today": 1, "sick": false, "sick_days": 0,
      "last_product_day": 33, "pos": [320, 448], "pregnant_until": -1 }
  ],
  "farm": { "tiles": [{"x":10,"y":8,"crop":"turnip","day":2,"watered":true,"fert":0}] },
  "buildings": [{"type":"coop","pos":[15,10],"level":1}],
  "npcs": [{"id":"martha","affection":320,"last_talk_day":33}],
  "codex": {"animals":["cow","chicken"],"crops":["turnip"]},
  "flags": {"llama_unlocked": false}
}
```

- 路径：`user://saves/slot_{n}.json`
- 写入：先写 `slot_{n}.tmp` → `DirAccess.rename()` 原子替换（防断电损坏）
- 自动存档：每天 6:00 与 2:00 强制入睡时

---

## 11. MVP 开发优先级

| # | 里程碑 | 交付物 | **验收标准（可机器断言）** |
|---|---|---|---|
| 1 | 玩家移动 + 时间/昼夜 | `Player.tscn`、`GameClock`、`CanvasModulate` | 角色 4 向行走；`GameClock` 跑满 120 tick 后 day+1；光照色在 4 个时段关键帧正确 |
| 2 | 可耕种土地 + 种植收获 | `FarmLayer`、`CropData`、锄/壶 | 锄地后 tile 变为耕地；浇水后 `watered=true`；4 天后芜菁可收获入背包 |
| 3 | 奶牛 + 鸡 | `Animal.tscn`、喂食/挤奶/捡蛋 | 喂食好感 +10；挤奶在 6:00–9:00 产出牛奶；捡蛋进背包 |
| 4 | 商店 + 背包 | `ShopPanel`、`InventoryPanel` | 9:00–17:00 可交易；非营业时段按钮禁用；金币增减正确 |
| 5 | 季节切换 + 雨天 | `WeatherSystem`、`WeatherVFX` | 第 28 天切季；雨天自动浇水 + 动物留棚好感 +3 |
| 6 | NPC ×1 + 好感 | `NPC.tscn`、玛莎 | 对话好感 +5（每日限 1 次）；3 心解锁 9 折 |
| 7 | 第二动物种类 | 山羊 | 山羊产出羊奶；好感 ≥6 心解锁奶酪原料 |

**MVP 完成定义**：连续玩通 3 个游戏日，无报错，无软锁，`qa` 套件全绿。

---

## 12. 后续路线

| 版本 | 内容 |
|---|---|
| v0.1 MVP | 里程碑 1–7 |
| v0.2 | 猪/绵羊/鸭/火鸡、加工坊、订单、图鉴 |
| v0.3 | 羊驼/蜜蜂、温室、繁殖棚、硬核模式 |
| v0.4 | 8 位 NPC 全量、剧情事件、季节祭典 |
| v1.0 | 成就、Steam 成就 API、云存档、移动端触屏优化、本地化（中/英/日） |

---

## 13. MCP 辅助工具使用方案

> **核实说明**：本章所有工具均已通过 GitHub API / npm registry / PyPI JSON API 实际查询确认存在，
> 版本号为查询时的最新值。查询日期：2026-10-13。

### 13.1 工具核实结果

| 工具（用户原始需求） | 实际形态 | 最新版本 | 真实来源 | 核实状态 |
|---|---|---|---|---|
| `ssyubix-pixelart-mcp` | PyPI 包 | **0.1.2** | `syuaibsyuaib/ssyubix-pixelart-mcp` | ✅ 存在（24 个工具） |
| `pixelforge-mcp` | npm 包 | **0.2.0** | `freema/pixelforge-mcp` | ✅ 存在（MIT） |
| `lpc-character-mcp` | PyPI 包 | **0.5.0** | `kyuza1/lpc-character-mcp` | ✅ 存在（**无 npm 包**） |
| `@pixelbananas/mcp` | npm 包 | **0.2.0** | npm 官方注册表 | ✅ 存在（需 Token） |
| `soundraw-game-bgm` | **仅 GitHub 源码** | — | `yksanjo/soundraw-game-bgm` | ✅ 存在（**无 npm，需付费 API**） |
| `godot-mcp-enhanced` | npm 包 | **0.34.1** | `wgt19861219/godot-mcp-enhanced` | ✅ 存在（46 工具，15 客户端） |

### 13.2 优先级配置清单

**P0 — 必装（阻塞一切后续工作）**

| # | 服务器 | 安装 | MCP 注册 |
|---|---|---|---|
| 1 | `godot-mcp-enhanced` | `npx godot-mcp-enhanced install`（自动下载 Godot 4.7.2-stable 到 `~/.godot-mcp/godot/`） | `claude mcp add -s user godot -- npx -y godot-mcp-enhanced` |
| 2 | `pixelforge-mcp` | `npx -y pixelforge-mcp@latest`（首次自动拉取） | 需 `GEMINI_API_KEY`（aistudio.google.com/apikey） |
| 3 | `lpc-character-mcp` | 先装 uv：`powershell -c "irm https://astral.sh/uv/install.ps1 \| iex"`，再 `uvx lpc-character-mcp --setup` | `claude mcp add lpc --scope user -- uvx lpc-character-mcp` |

**P1 — 强烈建议（决定资源质量）**

| # | 服务器 | 安装 | 备注 |
|---|---|---|---|
| 4 | `ssyubix-pixelart-mcp` | `pip install ssyubix-pixelart-mcp` | 启动 `ssyubix-pixelart-mcp`（stdio） |
| 5 | `@pixelbananas/mcp` | `npx -y @pixelbananas/mcp` | 需 `PIXELBANANAS_TOKEN`（`pba_live_...`） |

**P2 — 可选（有替代方案）**

| # | 服务器 | 风险 |
|---|---|---|
| 6 | `soundraw-game-bgm` | ⚠️ 无 npm 包，需 `git clone` + `npm run build`；需 **DeepSeek + Soundraw B2B 双付费 Key**；仅 1 star。**建议先用 `@pixelbananas/mcp` 的 chiptune BGM，自适应 BGM 留到后期** |

### 13.3 必须设置的 Godot MCP 环境变量

```jsonc
{
  "mcpServers": {
    "godot": {
      "command": "npx",
      "args": ["-y", "godot-mcp-enhanced"],
      "env": {
        // 工具白名单：只允许 AI 操作这个项目
        "ALLOWED_PROJECT_PATHS": "D:/UU的办公室/小牧场日记",
        // Godot 二进制白名单：防止 AI 被诱导 spawn 任意可执行文件
        "GODOT_MCP_ALLOWED_GODOT_PATHS": "C:/Users/32265/.godot-mcp/godot",
        // 默认 basic profile 只暴露 26/46 个工具，我们要 tilemap/asset 组
        "GODOT_MCP_PROFILE": "full",
        // 关闭启动时向 registry.npmjs.org 的外传
        "GODOT_MCP_UPDATE_CHECK": "false",
        // 关闭内嵌 Web GUI（默认开，监听 127.0.0.1）
        "GODOT_MCP_WEB_GUI": "0"
      }
    }
  }
}
```

> ⚠️ **三个必须知道的坑**：
> 1. **默认 profile 只暴露 26/46 个工具**。`tilemap`/`asset`/`physics`/`debug` 等域默认不可见 → 必须 `GODOT_MCP_PROFILE=full`，或运行时用 `manage_tools activate tilemap`。
> 2. **`GODOT_MCP_UPDATE_CHECK` 默认开启**，每次 server 启动会 fetch `registry.npmjs.org`（IP/UA 泄漏）。要零外传必须显式设 `false`。
> 3. **`screenshot` 的 `vision_route=true` + `GODOT_MCP_VISION_KEY`** 会把截图 base64 外传到 `api.groq.com`。**双重 opt-in，默认不外传**——不要手贱打开，除非你接受截图出机器。

### 13.4 每种资源的工具映射与参数

#### A. 地块 / Tileset → `ssyubix-pixelart-mcp`

**为什么不用 AI 生图**：地块必须**严格网格对齐**、**边缘可无缝拼接**。扩散模型做不到，会生成对不齐的 31×33 像素垃圾。

```
1. pixelart_suggest_tilemap_layout
     target_screen: "640x360", tile_size: 32
     → 返回 columns=20, rows=11, total_px=[640, 352]

2. pixelart_generate_palette
     style: "warm retro farm", mood: "cozy", count: 24
     → 得到调色板，后续所有地块共用（保证风格统一）

3. pixelart_create_tileset
     tile_width: 32, tile_height: 32, columns: 20, rows: 11

4. pixelart_set_tile   ← 逐格绘制（这是关键，不是"生成"）
     对每个 tile 槽位调用：
       grass_plain / grass_tuft / grass_flower
       dirt_path / dirt_path_edge_*
       water_shallow / water_deep / water_edge_*
       fence_h / fence_v / fence_corner_*
       soil_tilled / soil_watered

5. pixelart_export_tileset
     → 输出 <name>.png + <name>.json
       json 内含 tile_width / tile_height / ppu  ← 这三个值导入 Godot 时直接读
```

**Godot 导入**：`ssyubix` 默认面向 Unity，没有 Godot 导出器。拿到 PNG + JSON 后走 §13.5 的手动流程。

#### B. 动物精灵与动画 → `pixelforge-mcp`

```
forge_animation(
  description = "a brown and white dairy cow, side view",
  action      = "grazing, head lowering to eat grass",
  frames      = 4,
  size        = 32,                 # 目标像素尺寸（关键：不要生成 1024 再缩，直接要 32）
  style       = "snes",             # retro / snes / gameboy / neon / clean
  outputPrefix = "D:/UU的办公室/小牧场日记/assets/sprites/animals/cow_graze",
  references  = [".../cow_idle_00.png"]   # ★ 传已有帧锁定风格一致性
)
```

**逐动物参数表**

| 动物 | `action` | `frames` | `style` |
|---|---|---|---|
| 奶牛 | `grazing, head down to grass` | 4 | snes |
| 奶牛 | `walking, side view` | 4 | snes |
| 鸡 | `walking, pecking ground` | 3 | snes |
| 鸡 | `idle, flapping wings` | 2 | snes |
| 山羊 | `walking, chewing` | 4 | snes |
| 绵羊 | `idle, wool body` | 2 | snes |
| 猪 | `sniffing ground for truffle` | 4 | snes |
| 鸭 | `walking, waddling` | 3 | snes |
| 火鸡 | `idle, tail fanning` | 3 | snes |
| 羊驼 | `idle, fluffy neck` | 2 | snes |
| 蜜蜂 | `hovering, 3-frame loop` | 3 | clean |

**风格锚定技巧**：先 `forge_sprite` 生成奶牛 `idle` 单帧 → 把它作为 `references` 传给后续所有调用（包括其他动物）。**没有 references 的 AI 生图必然风格漂移**。

**后处理**：
```
optimize_sprite(inputPath=".../cow_raw.png", size=32,
                removeBackground=true, square=true)
process_sprite(inputPath=".../cow_sheet.png", split=true,
               names=["cow_graze_00","cow_graze_01","cow_graze_02","cow_graze_03"],
               threshold=128)
```

#### C. 玩家 / NPC 角色 → `lpc-character-mcp`

```
generate_character(
  items = [
    {"id":"body/body","color":"bronze"},
    {"id":"head/heads/human/heads_human_male"},
    {"id":"hair/short/hair_plain","color":"dark_brown"},
    {"id":"torso/shirts/longsleeve/torso_clothes_longsleeve","color":"white"},
    {"id":"torso/aprons/torso_aprons_overalls","variant":"leather"},
    {"id":"legs/pants/legs_cuffed","color":"white"},
    {"id":"feet/boots/feet_boots_basic","color":"brown"},
    {"id":"tool_watering_can","color":["steel","walnut"]}   # 挤奶/浇水动画
  ],
  body_type  = "male",
  animations = ["walk","idle","slash","watering","emote","sit"],
  layout     = "compact",
  split      = ["animation","frame"],
  export     = "godot",
  licenses   = ["CC0","OGA-BY"],        # ★★★ 见下方授权警告
  output_dir = "D:/UU的办公室/小牧场日记/assets/characters/",
  prefer_complete = true
)
```

- **产出**：`player.png` + **`player.tres`（SpriteFrames）**
- **Godot 挂载**：`player.tres` 直接塞进 `AnimatedSprite2D.sprite_frames`，动画名现成：`walk_down` / `idle_left` / `watering_right` ……
- 官方测试版本 **Godot 4.6**，API 与 4.7 兼容
- `layout: "standard"` 是与官方站点一致的固定行布局（walk 在 y=512，slash 在 y=768）；`compact` 只打包你要的动画，体积更小——**游戏用 compact**

**NPC 批量生成**：
```
generate_batch(count=8, body_types=["male","female"], seed=20261013,
               prefix="npc_", export="godot", licenses=["CC0","OGA-BY"],
               output_dir="D:/UU的办公室/小牧场日记/assets/characters/npcs/")
```

> ### ⚠️⚠️ LPC 授权硬警告（Steam / App Store 必读）
> LPC 美术素材混合了多种许可证（CC-BY-SA 3.0 / OGA-BY 3.0 / GPL 3.0 / CC0）。
> **带 DRM 的平台（Steam、App Store）只能安全使用 CC0 与 OGA-BY。**
> 因此**必须**传 `licenses: ["CC0", "OGA-BY"]`，并检查每次返回的：
> ```json
> "license_check": { "drm_safe": true, "share_alike_required": false }
> ```
> `drm_safe` 为 `false` 的素材**绝对不能**进 Steam 包体。
> 另外每次生成都会写 `<name>_credits.txt` / `_credits.csv`，内含可直接粘贴到游戏致谢页的文本
> ——**发布时务必包含**，这是许可证的强制要求，不是礼貌。

#### D. 音效与 BGM → `@pixelbananas/mcp`

```
generate_sfx(prompt="cow moo, low, friendly, 8-bit", effort=2,
             format="wav",
             outputDir="D:/UU的办公室/小牧场日记/assets/audio/sfx/",
             filename="sfx_cow_moo.wav")

generate_bgm(prompt="cozy morning farm, pentatonic, gentle, slow tempo",
             bars=16, effort=1, format="wav", includeMidi=true,
             outputDir="D:/UU的办公室/小牧场日记/assets/audio/bgm/",
             filename="bgm_morning.wav")
```

**SFX 清单（16 个）**

| 用途 | `prompt` | effort |
|---|---|---|
| 挤奶 | `milking, liquid pour into metal bucket, 8-bit` | 2 |
| 剪羊毛 | `shears snip, cloth cut, 8-bit` | 1 |
| 捡蛋 | `egg picked up, soft chime, 8-bit` | 1 |
| 抚摸 | `animal happy chirp, warm, 8-bit` | 1 |
| 牛叫 | `cow moo, low, friendly, 8-bit` | 2 |
| 鸡叫 | `chicken cluck, short, 8-bit` | 1 |
| 鸭叫 | `duck quack, comedic, 8-bit` | 1 |
| 猪叫 | `pig oink, 8-bit` | 1 |
| 脚步 | `footstep on grass, soft, 8-bit` | 1 |
| 锄地 | `hoe hitting soil, thud, 8-bit` | 1 |
| 浇水 | `watering can pour, splash, 8-bit` | 1 |
| 开门 | `wooden door open, creak, 8-bit` | 1 |
| 收银 | `coin register, cheerful ding, 8-bit` | 1 |
| 升级 | `achievement jingle, ascending notes, 8-bit` | 2 |
| 雷雨 | `thunder rumble, distant, 8-bit` | 2 |
| 钓鱼 | `fishing line cast, reel, 8-bit` | 1 |

**BGM 清单（6 首，按季节×时段）**

| 文件 | `prompt` | bars |
|---|---|---|
| `bgm_spring_day` | `cozy spring farm, pentatonic major, gentle, medium tempo` | 16 |
| `bgm_summer_day` | `bright summer farm, lydian, cheerful, faster tempo` | 16 |
| `bgm_autumn_day` | `mellow autumn farm, dorian, warm, medium tempo` | 16 |
| `bgm_winter_day` | `quiet winter farm, aeolian, sparse, slow tempo` | 16 |
| `bgm_night` | `peaceful night farm, pentatonic, very slow, soft` | 16 |
| `bgm_rain` | `melancholic rain, minor, gentle pads, slow` | 16 |

> **配额警告**：免费档 **20 credits/月**。SFX 1–4 credits/次，BGM 5–20 credits/次。
> 限速：SFX 5 次/分钟，BGM 3 次/分钟。每次成功返回 `creditsRemaining`。
> **先跑 SFX（便宜），BGM 放在最后批量做**。

#### E. 自适应 BGM → `soundraw-game-bgm`（P2，可选）

```
generate_bgm(scene="morning_farm", game_genre="cozy_sim",
             intensity="low", mood="peaceful",
             duration_seconds=90, engine="godot", file_format="wav")
```

- 需 `.env`：`DEEPSEEK_API_KEY` + `SOUNDRAW_API_KEY`
- 输出 `share_link` + `audio_url`，并自动生成 **Godot 集成代码片段**
- **不建议 MVP 阶段使用**：付费 API + 只有 1 star + 需自行 `npm run build`

### 13.5 资源导入 Godot 的标准流程

#### 步骤 1：项目初始化（只做一次）

```bash
npx godot-mcp-enhanced doctor                     # 诊断 Godot 检测 / 客户端配置
npx godot-mcp-enhanced setup                      # 自动检测路径 + 写配置
```
然后让 AI 通过 MCP 执行：
```
create_project(name="小牧场日记", path="D:/UU的办公室/小牧场日记",
               template="2d_pixel")
setup_project_rules()          # 生成 CLAUDE.md / AGENTS.md 项目规则
```

#### 步骤 2：资源落位

```
assets/
├── tilesets/
│   ├── terrain.png          ← ssyubix 导出
│   └── terrain.json         ← 含 tile_width / tile_height / ppu
├── sprites/animals/
│   ├── cow_idle_00.png … cow_idle_03.png    ← pixelforge 逐帧
│   └── chicken_walk_00.png …
├── characters/
│   ├── player.png  +  player.tres            ← lpc 导出（SpriteFrames）
│   └── npcs/npc_00.png + npc_00.tres …
└── audio/
    ├── sfx/*.wav
    └── bgm/*.wav
```

#### 步骤 3：引擎级导入（关键一步）

```
import_resources(directory="res://assets", 
                 extensions=[".png",".wav",".ogg"], recursive=true)
```
这会为所有资源批量生成 `.import` 文件——**不跑这一步，Godot 认不出资源**。

或者用 Web GUI 面板的项目行「⟳」按钮，走 `godot --headless --import` 引擎级重导入。

#### 步骤 4：像素设置（每张纹理都要）

对 `assets/` 下所有 PNG，在 `.import` 中设置：

| 设置项 | 值 | 原因 |
|---|---|---|
| `filter` | `false`（Nearest） | 否则像素被插值成糊的 |
| `compress/mode` | `0`（Lossless） | 防止调色板被压出色偏 |
| `mipmaps/generate` | `false` | 像素画不需要 mipmap |
| `process/fix_alpha_border` | `true` | 消除缩放边缘黑边 |

**替代方案**：直接把项目设置 `rendering/textures/canvas_textures/default_texture_filter = Nearest` 设为默认值，就不用逐张改。

#### 步骤 5：建 TileSet

`ssyubix` 导出的 `terrain.json` 里有 `tile_width` / `tile_height` / `ppu`，直接读：

```
create_scene(path="res://scenes/world/World.tscn")
add_node(parent="World", type="TileMapLayer", name="GroundLayer")
add_node(parent="World", type="TileMapLayer", name="FarmLayer")
add_node(parent="World", type="TileMapLayer", name="OverlayLayer")
```
TileSet 本体在编辑器里配：
1. 新建 `TileSet`，`Tile Size` = **32 × 32**
2. 拖入 `terrain.png` → Godot 自动按 32×32 切片
3. 为草地/泥路/水面建立 **Terrain Set**（自动拼接）——`terrain.json` 里的 edge tile 命名对应关系直接照抄
4. 给 `FarmLayer` 单独建一套耕地/浇水 TileSet（需要 2 状态切换）

> 用 `tilemap` 组工具可以在**运行时**刷格子验证：
> `manage_tools activate tilemap` → 然后 `tilemap` 工具组的 set/get tile action 直接改格子看效果。
> 注意：运行时改动**不持久化到 .tscn**，正式地图还是要 `add_node` + `save_scene`。

#### 步骤 6：角色挂载

```
add_node(parent="YSortRoot", type="CharacterBody2D", name="Player")
add_node(parent="YSortRoot/Player", type="AnimatedSprite2D", name="Sprite")
load_sprite(node_path="YSortRoot/Player/Sprite", texture="res://assets/characters/player.png")
edit_node(node_path="YSortRoot/Player/Sprite",
          properties={"sprite_frames": "res://assets/characters/player.tres"})
```
`lpc` 导出的 `.tres` 已含全部动画，动画名即 `walk_down` / `idle_left` / `watering_right`：
```gdscript
$Sprite.play("walk_" + dir_name)   # dir_name ∈ {"down","left","right","up"}
```

#### 步骤 7：动物挂载

```
quick_scene(path="res://scenes/entities/Animal.tscn",
            root_type="Node2D", script="res://scripts/entities/animal.gd")
add_node(parent="Animal", type="AnimatedSprite2D", name="Sprite")
add_node(parent="Animal", type="Area2D", name="InteractArea")
add_node(parent="Animal", type="Label", name="HeartBubble")
```

```gdscript
# res://scripts/entities/animal.gd
class_name Animal extends Node2D

@export var data: AnimalData

@onready var sprite: AnimatedSprite2D = $Sprite

var affection: int = 500      # 0–1000
var fed_today: int = 0
var sick: bool = false

func _ready() -> void:
    EventBus.phase_changed.connect(_on_phase_changed)
    _refresh_bubble()

func _on_phase_changed(_old: int, new: int) -> void:
    # 6:00 清晨切到活跃动画
    if new == GameClock.Phase.MORNING and not sick:
        sprite.play("idle")
```

#### 步骤 8：音频挂载

```
add_node(parent="Main", type="AudioStreamPlayer", name="BgmPlayer")
add_node(parent="Main", type="AudioStreamPlayer", name="SfxPlayer")
edit_node(node_path="Main/BgmPlayer",
          properties={"stream": "res://assets/audio/bgm/bgm_spring_day.wav",
                      "autoplay": true, "bus": "Music"})
```
- 新建 Audio Bus：`Master → Music` / `SFX` / `Ambient`
- SFX 用 8 个 `AudioStreamPlayer` 轮询池，避免同帧互相打断
- BGM 交叉淡入 1.5 秒，由 `AudioDirector` 单例统一调度

#### 步骤 9：验证闭环（这是 `godot-mcp-enhanced` 的真正价值）

```
validate_project()                                    # 缺失资源 / 无效脚本引用 / 孤立 .import
validate_scripts()                                    # 逐脚本编译验证
run_and_verify(scene="res://scenes/world/World.tscn") # 真跑 + 结构化错误分析
screenshot(action="capture")                          # 截图给用户看效果
qa(run="qa/mvp.qa.md", project=".")                   # 确定性断言（seed 锁随机，可复现）
verify_delivery()                                     # 交付门禁：场景树完整性 + 脚本健康 + 性能
```

**QA 断言示例** `qa/mvp.qa.md`：
```markdown
# MVP 验收
- [ ] 启动 3 秒内进入 World.tscn 无报错
- [ ] playtest.seed 固定为 20261013
- [ ] 快进 120 tick → clock.day 增加 1
- [ ] 对 cow_001 调用 feed() → affection 增加 10
- [ ] 时钟设为 480 分钟（8:00）→ 挤奶产出 product_id == "milk"
- [ ] 时钟设为 1080 分钟（18:00）→ 商店面板按钮 disabled == true
- [ ] 切换天气为 rain → 所有 FarmTile.watered == true
```

### 13.6 完整执行顺序（照抄即可）

```bash
# ① 环境准备
powershell -c "irm https://astral.sh/uv/install.ps1 | iex"   # 装 uv（lpc 必需）
npx godot-mcp-enhanced install                                # 装 Godot 4.7.2-stable
npx godot-mcp-enhanced doctor                                 # 验证
uvx lpc-character-mcp --setup                                 # 拉取 LPC 素材定义（~10s）

# ② 配置 MCP（写进客户端配置，见 §13.3）
#    godot / pixelforge / lpc / pixelart / pixelbananas

# ③ 建项目
npx godot-mcp-enhanced init ranch-diary --template=2048   # 借模板拿目录结构，再改造

# ④ 资源生产（按此顺序，因为风格要逐层锚定）
#    1. ssyubix  → 调色板 + 地块（定风格基线）
#    2. pixelforge → 动物精灵（用 1 的调色板截图做 references）
#    3. lpc       → 玩家 + 8 NPC（licenses 必须传 CC0/OGA-BY）
#    4. pixelbananas → 16 SFX（便宜）→ 6 BGM（贵，最后做）

# ⑤ 导入 + 验证
#    见 §13.5 步骤 3–9

# ⑥ 录 demo GIF 发出去
npx godot-mcp-enhanced gif . --seconds 12 --fps 6
```

### 13.7 工具链风险清单

| 风险 | 影响 | 对策 |
|---|---|---|
| **LPC 授权** | Steam 上架被 DMCA | 强制 `licenses:["CC0","OGA-BY"]`，检查 `drm_safe`，附 `_credits.txt` |
| AI 生图风格漂移 | 动物看着不像一套 | 第一个精灵定调，之后全部传 `references` |
| 地块网格不齐 | 地图出现裂缝 | 地块**只用 `ssyubix` 精确绘制**，绝不用扩散模型 |
| `godot-mcp-enhanced` 默认 profile | 一半工具看不见，AI 说"没这个功能" | `GODOT_MCP_PROFILE=full` |
| MCP 启动外传 | IP/UA 泄漏到 npmjs | `GODOT_MCP_UPDATE_CHECK=false` |
| `vision_route` 外传 | 截图 base64 上传 groq | 保持默认关闭 |
| PixelBananas 额度 | 20 credits/月，BGM 一首 5–20 | 先 SFX 后 BGM，`list_generations` 查余额 |
| `soundraw-game-bgm` | 1 star + 付费 API + 无 npm 包 | 降级为 P2，MVP 不用 |
| Python 3.14 太新 | 部分包无 wheel | `ssyubix` 是 `py3-none-any`，安全；`lpc` 走 uvx 自带 Python，不受影响 |

### 13.8 本机现状（2026-10-13 实测）

| 依赖 | 状态 | 动作 |
|---|---|---|
| Node.js | ✅ v24.20.0（≥20 满足 pixelforge 要求） | — |
| npm | ✅ 11.19.0 | — |
| Python | ✅ 3.14.6 | — |
| Git | ✅ 2.56.0.windows.2 | — |
| **uv / uvx** | ❌ **缺失** | `irm https://astral.sh/uv/install.ps1 \| iex` |
| **Godot** | ❌ **缺失**（`~/.godot-mcp` 不存在） | `npx godot-mcp-enhanced install` |
| `D:\UU的办公室\小牧场日记` | ❌ 未创建 | 步骤 ③ |

---

## 附录 A：核心循环数值速查

```
一天 12 分钟 → 120 tick
早起（6:00-9:00）:
  挤奶 奶牛×N（每头 -5 体力，黄金窗口产量 100%）
  捡蛋、剪毛（若有）
白天（9:00-17:00）:
  放牧（+5 好感/h，晴天）
  浇水 / 收获 / 送货 / 找 NPC
  商店买卖
黄昏（17:00-20:00）:
  特殊事件窗口
  部分动物自动回棚
夜晚（20:00-2:00）:
  加工坊放料（24h 可用）
  钓鱼（稀有鱼 +30%）
  采集（概率 -50%）
2:00 强制入睡 → 结算 → 自动存档

每日结算顺序:
  1. 天气效果（自动浇水 / 栅栏损坏判定）
  2. 动物好感（漏喂 -15 / 生病判定 15%）
  3. 动物产出（好感决定品质与"不产出"概率）
  4. 作物生长（浇水判定）
  5. 加工坊完成
  6. 牧场维护费 -50G
  7. 季节日计数 +1（第 28 天 → 过渡日）
```

## 附录 B：平衡性预算（第 1 年收入目标）

| 阶段 | 游戏日 | 目标金币 | 主要来源 |
|---|---|---|---|
| 开局 | 1–7 | 0 → 1500 | 鸡蛋 + 少量作物 |
| 起步 | 8–28 | 1500 → 8000 | 牛奶 + 奶酪 + 订单 |
| 扩张 | 29–56 | 8000 → 30000 | 多动物 + 加工坊 Lv2 + 温室 |
| 成熟 | 57–112 | 30000 → 100000 | 高好感金星产出 + 彩虹毛线 |

**设计校验**：单日纯利润不应超过「当前总资产 × 10%」，否则节奏崩坏。
