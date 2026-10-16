class_name CropData
extends Resource
## 作物静态数据（GDD §4.1 / 模块 3）
##
## 全部数值来自 res://data/crops.csv，代码里不写死任何平衡值。
## 改数值 = 改 CSV → 重启，不碰代码。
##
## 表结构（9 列）：
##   id,name,season,grow_days,seed_price,sell_price,regrow_days,fertilize,color

@export var id: StringName
@export var display_name: String = ""
@export var season: int = 0          ## 0 春 / 1 夏 / 2 秋 / 3 冬
@export var grow_days: int = 4       ## 从播种到成熟所需天数（未施肥）
@export var seed_price: int = 20
@export var sell_price: int = 35     ## 普通品质单价（银星 / 金星按 CropQuality 倍率放大）
@export var regrow_days: int = 0     ## 0 = 一次性作物；>0 = 收获后 N 天再生
@export var fertilize: int = 0       ## 肥料亲和度 0 不吃肥 / 1 只吃基础肥 / 2 基础+高级都能吃
@export var color: String = "#79C455"  ## 果实色（CropLayer 程序化占位用）

## 季节名（"春" / "夏" / "秋" / "冬"）
func season_name() -> String:
	return CropDB.SEASON_NAME[season]

## 是不是一次性作物
func is_single_harvest() -> bool:
	return regrow_days <= 0

## 单株理论收益（普通品质，不含季节倍率）
func profit() -> int:
	return sell_price - seed_price

## 每天平均收益 —— 用来横向比较作物性价比，数值策划排表用
func profit_per_day() -> float:
	return float(profit()) / maxf(1.0, float(grow_days))
