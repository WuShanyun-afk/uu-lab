class_name AnimalData
extends Resource
## 动物静态数据（GDD §3.1 / §3.2 / 模块 4）
##
## 全部数值来自 res://data/animals.csv。代码里不写死任何平衡值。
## 加一种动物 = 在 CSV 里加一行（+ products.csv 加产物），不碰任何脚本。
##
## 表结构（17 列）：
##   id,name,kind,housing,price,product,product_min,product_max,product_high,
##   high_chance,feed_freq,mature_days,produce_action,produce_window,
##   produce_period,brushable,pet_limit

## 互动方式 → 中文（产出口令）
const ACTION_NAME := {
	"milk": "挤奶",
	"shear": "剪毛",
	"gather": "捡拾",
	"honey": "采蜜",
}

## 棚舍 → 中文
const HOUSING_NAME := {
	"barn": "畜舍",
	"coop": "禽舍",
	"hive": "蜂箱",
}

@export var id: StringName
@export var display_name: String = ""
@export var kind: String = "livestock"     ## livestock 家畜 / poultry 家禽 / special 特殊
@export var housing: String = "barn"       ## barn / coop / hive
@export var price: int = 0                 ## 购买价（模块 4 需求 2）
@export var product: StringName = &""      ## 每日基础产出
@export var product_min: int = 1
@export var product_max: int = 1
@export var product_high: StringName = &"" ## 高好感（≥8 心）特殊产出
@export var high_chance: float = 0.0       ## 特殊产出概率；<= 0.0 = 必定
@export var feed_freq: int = 1             ## 每天需喂几次
@export var mature_days: int = 3           ## 幼年 → 成年
@export var produce_action: String = "gather"  ## 需求 5 的互动方式
@export var produce_window: int = 0        ## 产出时间窗口（分钟，从 6:00 起算；0 = 全天）
@export var produce_period: int = 1        ## 每几天产出一次（羊毛 3 天 / 蜂王浆 4 天）
@export var brushable: bool = false        ## 能不能刷毛
@export var pet_limit: int = 2             ## 每天可抚摸次数（0 = 不让摸）
@export var timed_product: bool = false    ## produce_window > 0 的派生标志

func is_poultry() -> bool:
	return kind == "poultry"

func is_special() -> bool:
	return kind == "special"

## 这种动物的产出要不要走节奏条小游戏（需求 4）
func needs_minigame() -> bool:
	return produce_action == "milk" or produce_action == "shear"

## 产出口令的中文名（"挤奶" / "剪毛" / "捡拾" / "采蜜"）
func action_name() -> String:
	return ACTION_NAME.get(produce_action, "采集")

func housing_name() -> String:
	return HOUSING_NAME.get(housing, housing)

## 这种动物身上存在「可做的好感互动」吗？
## 蜜蜂：不能摸、不能刷、不是家禽 → 只喂食就够，不会因为「没摸」被判定冷落。
func can_be_pampered() -> bool:
	return pet_limit > 0 or brushable or is_poultry()

## 产出窗口的中文描述（"06:00–09:00" / "全天"）
func window_text() -> String:
	if produce_window <= 0:
		return "全天"
	var h0 := 6 + produce_window / 60
	var m0 := produce_window % 60
	return "06:00–%02d:%02d" % [h0, m0]

## 产出周期描述（"每天" / "每 3 天"）
func period_text() -> String:
	return "每天" if produce_period <= 1 else "每 %d 天" % produce_period
