class_name ItemDef
extends Resource
## 物品定义（模块 7 需求 1 / 输出「物品数据结构（Resource）」）
##
## 为什么是 Resource 而不是 Dictionary：
##   ① 编辑器里能当资源存/读，将来做「物品图鉴」直接 export 一份数组；
##   ② 字段有类型，写错字段名在解析期就报错，不会像 Dictionary 那样静默返回 null；
##   ③ 想在编辑器里手摆一张「测试用物品表」时，Resource 能直接拖进 Inspector。
##
## 但**运行时真源仍然是 CSV**（crops.csv / products.csv / recipes.csv / upgrades.csv）。
## ItemDB 启动时把它们聚合成 ItemDef 实例 —— 数值永远只有一处，改平衡改 CSV。
##
## 一条铁律：**品质不写进 ItemDef**。
## 品质是「同一件物品的不同档」，编码在背包 item id 后缀里（CropQuality），
## ItemDef 只描述基础物品。想知道金星牛奶卖多少钱，用 ItemDB.price_of("milk_gold")。

## 物品大类。UI 分页、商店收售、订单挑货都按它分流。
enum Cat {
	CROP,        ## 作物（可收获物）
	SEED,        ## 种子（消耗品，种下去）
	PRODUCT,     ## 畜产品（牛奶 / 蛋 / 毛）
	CRAFTED,     ## 加工品（奶酪 / 毛线 / 蛋黄酱）
	MATERIAL,    ## 材料（木材）
	CONSUMABLE,  ## 消耗品（饲料 / 药剂 / 肥料）
	TOOL,        ## 工具升级券（不进背包，买了直接生效）
}

const CAT_NAME := ["作物", "种子", "畜产", "加工品", "材料", "消耗", "工具"]

## 背包唯一键（StringName）。品质后缀**不在**这里。
@export var id: StringName = &""
@export var display_name: String = ""
@export var category: int = Cat.MATERIAL
## 基础单价（不含品质倍率 / 季节倍率 / 行情波动）
@export var base_price: int = 0
## 单格堆叠上限。超了就占下一格。
@export var stack_max: int = 99
## 出货箱收不收（饲料 / 药剂 / 肥料 = false，免得顺手全卖掉）
@export var sellable: bool = true
## 商店卖不卖（种子 / 动物由各自商店管，这里只给通用判定用）
@export var buyable: bool = false
## 图标色（没有贴图时 ItemSlot 画的色块）
@export var color: Color = Color("#CCCCCC")
## 一句话说明（背包详情 / 商店备注）
@export var note: String = ""

func cat_name() -> String:
	return CAT_NAME[clampi(category, 0, CAT_NAME.size() - 1)]

## 是不是「能堆叠」的东西（上限 > 1 就算）
func stackable() -> bool:
	return stack_max > 1

## 基础价 + 品质倍率（不含季节 / 行情，那两样属于 Market）
func price_with_quality(q: int) -> int:
	return int(round(float(base_price) * CropQuality.price_mult(q)))

func _to_string() -> String:
	return "ItemDef(%s, %s, %dG)" % [id, display_name, base_price]
