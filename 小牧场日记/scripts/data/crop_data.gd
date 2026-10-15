class_name CropData
extends Resource
## 作物静态数据（GDD §4.1）
##
## 全部数值来自 res://data/crops.csv，代码里不写死任何平衡值。
## 改数值 = 改 CSV → 重启，不碰代码。

@export var id: StringName
@export var display_name: String = ""
@export var season: int = 0          ## 0 春 / 1 夏 / 2 秋 / 3 冬
@export var grow_days: int = 4       ## 从播种到成熟所需天数
@export var seed_price: int = 20
@export var sell_price: int = 35
@export var regrow_days: int = 0     ## 0 = 一次性作物；>0 = 收获后 N 天再生
@export var fertilize: int = 0       ## 施肥需求 0 低 / 1 中 / 2 高
@export var stages: int = 4          ## 视觉生长阶段数
