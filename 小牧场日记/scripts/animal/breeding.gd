class_name Breeding
extends RefCounted
## 繁殖规则（模块 5 需求 4）—— **纯逻辑**，不碰节点、不碰 UI、不碰背包
##
## 分层和 RhythmBar 一样：这里只回答两个问题
##   ① `can_breed()` —— 这两只现在能不能配？不能的话，**为什么**（返回枚举，不是 bool）
##   ② `start()`     —— 能配就把妊娠计时器挂到母体上
## 真正的扣钱 / 扣木材 / 造建筑 / 生崽，全在 main.gd 和 Herd.advance_day() 里。
##
## 为什么用枚举而不是 bool：模块 3 的 `plant_reason()` 已经证明，
## 只回 bool 的话「种不下」和「季节不对」在 UI 上分不开，玩家只能干瞪眼。

enum Reason {
	OK,          ## 可以配
	NO_SHED,     ## 繁殖棚还没建
	SAME,        ## 同一只动物（自交）
	SPECIES,     ## 不是同种
	BABY,        ## 有一方未成年
	HEARTS,      ## 好感不到 8 心
	SICK,        ## 有一方生病
	PREGNANT,    ## 有一方正在妊娠
	SPACE,       ## 牧场满了
}

## 门槛（改数值改这里；CSV 只管建筑造价）
const MIN_HEARTS := 8
const FEED_COST := 5        ## 每次繁殖消耗干草饲料
const GOLD_COST := 100      ## 每次繁殖手续费

static func reason_text(r: int) -> String:
	match r:
		Reason.OK:
			return ""
		Reason.NO_SHED:
			return "还没建繁殖棚"
		Reason.SAME:
			return "同一只动物不能和自己配"
		Reason.SPECIES:
			return "要两只同种动物"
		Reason.BABY:
			return "两只都要成年"
		Reason.HEARTS:
			return "两只好感都要 ≥ %d 心" % MIN_HEARTS
		Reason.SICK:
			return "生病中的动物先治好"
		Reason.PREGNANT:
			return "正在妊娠中，等它生完"
		Reason.SPACE:
			return "牧场住满了"
	return "不能繁殖"

## 这两只能不能配？返回 Reason。
## herd_size / max_size 用来判「生下来有没有地方住」。
static func can_breed(a: AnimalState, b: AnimalState, shed_built: bool,
		herd_size: int, max_size: int) -> int:
	if not shed_built:
		return Reason.NO_SHED
	if a == null or b == null:
		return Reason.NO_SHED
	if a.uid == b.uid:
		return Reason.SAME
	if a.species != b.species:
		return Reason.SPECIES
	if not a.is_adult() or not b.is_adult():
		return Reason.BABY
	if a.sick or b.sick:
		return Reason.SICK
	if a.is_pregnant() or b.is_pregnant():
		return Reason.PREGNANT
	if a.hearts() < MIN_HEARTS or b.hearts() < MIN_HEARTS:
		return Reason.HEARTS
	if herd_size >= max_size:
		return Reason.SPACE
	return Reason.OK

## 挂妊娠计时器到母体（a）上。返回是否成功。
static func start(a: AnimalState, b: AnimalState, gestation_days: int) -> bool:
	if a == null or b == null or gestation_days < 1:
		return false
	a.pregnant_days = gestation_days
	a.gestation = gestation_days
	a.partner_species = b.species
	return true

## 一次繁殖的总成本（给 UI 显示 / 给测试断言用）
static func cost_text() -> String:
	return "%dG + 饲料×%d" % [GOLD_COST, FEED_COST]
