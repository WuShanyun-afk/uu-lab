class_name AnimalData
extends Resource
## 动物静态数据（GDD §3.1 / §3.2）
##
## 全部数值来自 res://data/animals.csv。代码里不写死任何平衡值。

@export var id: StringName
@export var display_name: String = ""
@export var kind: String = "livestock"     ## livestock 家畜 / poultry 家禽
@export var price: int = 0
@export var product: StringName = &""      ## 每日基础产出
@export var product_min: int = 1
@export var product_max: int = 1
@export var product_high: StringName = &"" ## 高好感（≥8 心）特殊产出
@export var high_chance: float = 0.0       ## 特殊产出概率；0.0 = 必定
@export var feed_freq: int = 1             ## 每天需喂几次
@export var mature_days: int = 3           ## 幼年 → 成年
@export var timed_product: bool = false    ## true = 产出需时间窗口（挤奶 6:00–9:00）

func is_poultry() -> bool:
	return kind == "poultry"
