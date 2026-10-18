class_name BgmDirector
extends RefCounted
## 动态 BGM 的**选曲逻辑**（模块 附1）—— 纯函数，不碰播放器
##
## 一句话：**同一时刻该放哪首 BGM，只由「时段 + 天气 + 季节 + 所在场景」决定。**
##
## 优先级（从高到低，改了顺序就改了整局的情绪）：
##   ① 室内：小屋 / 商店 / 矿洞 → bgm_indoor（外面下刀子里面也是暖的）
##   ② 雨 / 雷雨 → bgm_rain（需求 3 的「雨天自动切忧郁 BGM」）
##   ③ 雪 / 暴风雪 → bgm_snow
##   ④ 冬季的白天 → bgm_snow（晴天也要有冬天的味道）
##   ⑤ 时段：清晨 / 白天 / 黄昏 / 夜晚
##
## 为什么选曲不写在 AudioManager 里：
##   这张表要**每次改都能被测试逐格断言**（4 时段 × 5 天气 × 4 季节 × 5 场景的组合里
##   真正会出现的只有几十种），写成纯函数就能一条一条钉死，而不是靠耳朵听。

## 版本号：选曲规则变了就 +1，存档里的「上次听的 BGM」不兼容时直接重算
const RULES_VERSION := 1

const T_MORNING := &"bgm_morning"
const T_DAY := &"bgm_day"
const T_DUSK := &"bgm_dusk"
const T_NIGHT := &"bgm_night"
const T_RAIN := &"bgm_rain"
const T_SNOW := &"bgm_snow"
const T_INDOOR := &"bgm_indoor"

## GameClock.Phase
const P_DAWN := 0
const P_DAY := 1
const P_DUSK := 2
const P_NIGHT := 3

## WeatherSystem.Weather
const W_RAIN := 2
const W_STORM := 3
const W_SNOW := 4

## GameClock.season：0 春 / 1 夏 / 2 秋 / 3 冬
const S_WINTER := 3

## 这几个场景算「室内」：进屋/进店/下矿都换同一首温暖室内曲
const INDOOR_SCENES := [&"house", &"shop", &"mine"]

const TRACK_NAME := {
	T_MORNING: "清晨", T_DAY: "白天", T_DUSK: "黄昏", T_NIGHT: "夜晚",
	T_RAIN: "雨天", T_SNOW: "雪天", T_INDOOR: "室内",
}

## 核心：给一组状态，返回该放的 BGM id
static func choose(phase: int, weather: int, season: int, scene: StringName) -> StringName:
	if INDOOR_SCENES.has(scene):
		return T_INDOOR
	if weather == W_RAIN or weather == W_STORM:
		return T_RAIN
	if weather == W_SNOW:
		return T_SNOW
	if season == S_WINTER and (phase == P_DAWN or phase == P_DAY):
		return T_SNOW
	match phase:
		P_DAWN:
			return T_MORNING
		P_DUSK:
			return T_DUSK
		P_NIGHT:
			return T_NIGHT
	return T_DAY

## 从全局状态现算（AudioManager 用这个；测试传参用上面的 choose）
static func choose_now() -> StringName:
	return choose(GameClock.current_phase(), WeatherSystem.today,
		GameClock.season, SceneRouter.current_id)

## 换曲的交叉淡入时长：天气/室内切换要更慢，免得吵
static func fade_for(from_id: StringName, to_id: StringName) -> float:
	if from_id == to_id:
		return 0.0
	if to_id == T_INDOOR or from_id == T_INDOOR:
		return 1.8
	if to_id == T_RAIN or to_id == T_SNOW:
		return 2.6
	return 1.2

## 调试面板 / 测试用：一句话解释为什么是这首
static func explain(phase: int, weather: int, season: int, scene: StringName) -> String:
	var track := choose(phase, weather, season, scene)
	var why := "时段"
	if INDOOR_SCENES.has(scene):
		why = "室内场景"
	elif weather == W_RAIN or weather == W_STORM:
		why = "雨/雷雨"
	elif weather == W_SNOW:
		why = "下雪"
	elif season == S_WINTER and (phase == P_DAWN or phase == P_DAY):
		why = "冬季白天"
	return "%s（%s）" % [str(TRACK_NAME.get(track, String(track))), why]

func _to_string() -> String:
	return "BgmDirector v%d" % RULES_VERSION
