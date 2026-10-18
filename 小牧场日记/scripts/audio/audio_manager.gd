extends Node
## 全局音频管理器 —— autoload: AudioManager（模块 附1：全局音频与氛围系统）
##
## 一句话：**游戏里所有声音都从这一个门进来。**
##   · BGM：两路播放器交叉淡入淡出（换曲不爆、不中断）
##   · SFX：固定大小的播放器池 + 三条闸门（冷却 / 同 id 并发 / 抢槽），
##          保证「一堆金币同时入账」不会削波、「竣工音」不会独霸唯一通道
##   · 环境音：雨声单独一路，跟天气/室内状态淡入淡出
##   · 音量：Master / BGM / SFX / Amb 四条总线，改完写 user:// 配置
##
## 分工（和项目其它模块一致：逻辑与播放分离）：
##   BgmDirector —— 选哪首曲（纯函数，可测）
##   SfxPool     —— 这一声放不放、放哪个槽（纯逻辑，可测）
##   AudioManager（本文件）—— 只做「照分配结果去 play()」+ 订阅事件 + 总线/配置
##
## 音效触发点有两类：
##   ① 表现层直接调（锄地/浇水/挤奶……发生在 main 的交互分支里，直接 play_sfx 最好读）；
##   ② 跨系统事件走 EventBus（金币、动物叫声、UI 开关、玩家脚步），避免 main 到处埋音效。
##
## ⚠️ 音量用线性 0–1 存（用户能理解），设到总线上时才换成分贝（linear_to_db）。
## ⚠️ 缺素材不是错误：def.is_available() 为 false 就静默跳过并计入 stats()，
##    这样素材没生成全时游戏照样能跑，而不是一进游戏就弹满报错。

signal bgm_changed(id: StringName)

const SETTINGS_PATH := "user://audio_settings.cfg"
## SFX 池大小：12 足够「脚步 + 动物 + 金币 + UI」同帧叠放；再多就是互相抢
const SFX_VOICES := 12
## 2D（有方位）池：动物叫 / 建造落点这类需要左右声像的声音
const POS_VOICES := 6
const BUS_NAMES := [&"BGM", &"SFX", &"Amb"]

var master_volume: float = 1.0
var bgm_volume: float = 0.7
var sfx_volume: float = 0.9
var amb_volume: float = 0.8

## 测试会把这里改到 user:// 下的临时文件，别洗玩家的真实音量设置
var settings_path: String = SETTINGS_PATH

var _pool := SfxPool.new(SFX_VOICES)
var _pos_pool := SfxPool.new(POS_VOICES)
var _sfx: Array[AudioStreamPlayer] = []
var _sfx_tokens: PackedInt32Array = PackedInt32Array()
var _pos: Array[AudioStreamPlayer2D] = []
var _pos_tokens: PackedInt32Array = PackedInt32Array()
var _streams: Dictionary = {}          ## path -> AudioStream（只 load 一次）
var _bgm: Array[AudioStreamPlayer] = []
var _bgm_index: int = 0
var _bgm_id: StringName = &""
var _amb: AudioStreamPlayer
var _amb_id: StringName = &""
var _amb_wanted: StringName = &""
var _bgm_tween: Tween
var _rng := RandomNumberGenerator.new()
## 脚步/动物叫的音量来源：main 注册「世界坐标 → 地表类型」，房间场景注册「木地板」
var _terrain_provider: Callable = Callable()
## 统计（调试面板用）
var _plays_total: int = 0
var _rejects: Dictionary = {}          ## reason -> 次数
var _missing_warned: Dictionary = {}   ## id -> true（缺文件只 warn 一次）

func _ready() -> void:
	_rng.randomize()
	_ensure_buses()
	_load_settings()
	_build_players()
	_connect_events()
	# 等一帧：其它 autoload（GameClock/Weather/SceneRouter）都就位了再选曲
	call_deferred("refresh_bgm")

# ---------------- 总线 ----------------

## 用代码建总线而不是提交 .tres 布局文件：
##   ① 版本控制里少一个二进制样式的资源；
##   ② 测试环境（headless）也能建，跑到哪都是四条总线；
##   ③ 缺总线时不会静默把所有声音丢进 Master。
func _ensure_buses() -> void:
	for bus_name in BUS_NAMES:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, String(bus_name))
		AudioServer.set_bus_send(idx, &"Master")
	_apply_bus_volumes()

func _bus_index(bus_name: StringName) -> int:
	return AudioServer.get_bus_index(bus_name)

func _apply_bus_volumes() -> void:
	_set_bus_linear(&"Master", master_volume)
	_set_bus_linear(&"BGM", bgm_volume)
	_set_bus_linear(&"SFX", sfx_volume)
	_set_bus_linear(&"Amb", amb_volume)

func _set_bus_linear(bus_name: StringName, linear: float) -> void:
	var idx := _bus_index(bus_name)
	if idx < 0:
		return
	var v := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.001, v)))

# ---------------- 播放器 ----------------

func _build_players() -> void:
	# 普通 SFX 池
	for i in range(SFX_VOICES):
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		p.bus = &"SFX"
		add_child(p)
		p.finished.connect(_on_sfx_finished.bind(i))
		_sfx.append(p)
	_sfx_tokens.resize(SFX_VOICES)

	# 2D SFX 池（动物叫 / 建造）
	for i in range(POS_VOICES):
		var q := AudioStreamPlayer2D.new()
		q.name = "SfxPos%d" % i
		q.bus = &"SFX"
		q.max_distance = 460.0
		q.attenuation = 1.6
		q.panning_strength = 1.0
		add_child(q)
		q.finished.connect(_on_pos_finished.bind(i))
		_pos.append(q)
	_pos_tokens.resize(POS_VOICES)

	# BGM：两路交叉淡入淡出
	for i in range(2):
		var b := AudioStreamPlayer.new()
		b.name = "Bgm%d" % i
		b.bus = &"BGM"
		add_child(b)
		_bgm.append(b)

	# 环境音：雨声
	_amb = AudioStreamPlayer.new()
	_amb.name = "Ambience"
	_amb.bus = &"Amb"
	add_child(_amb)

# ---------------- 资源加载 ----------------

func _load_stream(path: String, loop: bool) -> AudioStream:
	var key := path + ("|loop" if loop else "")
	if _streams.has(key):
		return _streams[key]
	if path == "" or not ResourceLoader.exists(path):
		return null
	var s := load(path) as AudioStream
	if s == null:
		return null
	# WAV 的循环点在导入设置里，这里兜底：数据表说 loop 但资源没开循环，运行时补上。
	# （程序生成的 WAV 没有 .import 里的 loop 标记，这一步是必须的，否则 BGM 只响一遍）
	# ⚠️ loop_end 用「时长 × 采样率」换算成帧，**不要**用 data.size() 算字节：
	#    Godot 默认把 WAV 导成 QOA 压缩流（compress/mode=2），那样的字节数根本不是帧数。
	if loop and s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		if w.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = maxi(1, int(round(w.get_length() * float(w.mix_rate))))
	_streams[key] = s
	return s

# ---------------- 音效 ----------------

func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

## 放一个音效。返回是否真的放出来了（被闸门拦下 / 缺素材 = false）
## opts.pitch 可强制指定音高（测试用）；opts.volume 额外音量系数
func play_sfx(id: StringName, opts: Dictionary = {}) -> bool:
	var def := AudioDB.def_of(id)
	if def == null or not def.is_available():
		_warn_missing(id)
		return false
	var stream := _load_stream(def.file, def.loop)
	if stream == null:
		_warn_missing(id)
		return false
	var pitch: float = float(opts.get("pitch", 0.0))
	if pitch <= 0.0:
		pitch = _roll_pitch(def)
	var dur := stream.get_length() / pitch
	var res := _pool.try_acquire(def, _now(), dur)
	if int(res["slot"]) < 0:
		_count_reject(str(res["reason"]))
		return false
	var p := _sfx[int(res["slot"])]
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = linear_to_db(maxf(0.001, def.volume * float(opts.get("volume", 1.0))))
	if def.loop:
		p.max_polyphony = 1
	_sfx_tokens[int(res["slot"])] = int(res["token"])
	p.play()
	_plays_total += 1
	return true

## 有方位地放（动物叫 / 建造落点）：音量随距离衰减、左右声像由 AudioStreamPlayer2D 算
func play_sfx_at(id: StringName, world_pos: Vector2, opts: Dictionary = {}) -> bool:
	var def := AudioDB.def_of(id)
	if def == null or not def.is_available():
		_warn_missing(id)
		return false
	var stream := _load_stream(def.file, def.loop)
	if stream == null:
		_warn_missing(id)
		return false
	var pitch: float = float(opts.get("pitch", 0.0))
	if pitch <= 0.0:
		pitch = _roll_pitch(def)
	var res := _pos_pool.try_acquire(def, _now(), stream.get_length() / pitch)
	if int(res["slot"]) < 0:
		_count_reject(str(res["reason"]))
		return false
	var q := _pos[int(res["slot"])]
	q.stream = stream
	q.pitch_scale = pitch
	q.volume_db = linear_to_db(maxf(0.001, def.volume * float(opts.get("volume", 1.0))))
	q.global_position = world_pos
	_pos_tokens[int(res["slot"])] = int(res["token"])
	q.play()
	_plays_total += 1
	return true

## UI 音 = 普通音效（但语义上单独一个入口，方便以后接 UI 总线 / 静音开关）
func play_ui(id: StringName) -> bool:
	return play_sfx(id)

func _roll_pitch(def: AudioDef) -> float:
	if def.pitch_max > def.pitch_min:
		return _rng.randf_range(def.pitch_min, def.pitch_max)
	return def.pitch_min if def.pitch_min > 0.0 else 1.0

func _on_sfx_finished(index: int) -> void:
	_pool.release(index, _sfx_tokens[index])

func _on_pos_finished(index: int) -> void:
	_pos_pool.release(index, _pos_tokens[index])

func _count_reject(reason: String) -> void:
	_rejects[reason] = int(_rejects.get(reason, 0)) + 1

func _warn_missing(id: StringName) -> void:
	if _missing_warned.has(id):
		return
	_missing_warned[id] = true
	push_warning("[AudioManager] 缺少素材或定义：%s" % String(id))

# ---------------- BGM ----------------

func play_bgm(id: StringName, fade: float = -1.0) -> void:
	if id == &"":
		stop_bgm()
		return
	var def := AudioDB.def_of(id)
	if def == null:
		_warn_missing(id)
		return
	# 同一首正在响就什么都不做（每帧 refresh 也不会重启动）
	if id == _bgm_id and _bgm[_bgm_index].playing:
		return
	var stream := _load_stream(def.file, true)
	if stream == null:
		_warn_missing(id)
		return
	if fade < 0.0:
		fade = BgmDirector.fade_for(_bgm_id, id)
	var old_index := _bgm_index
	var old := _bgm[old_index]
	_bgm_index = 1 - old_index
	var next := _bgm[_bgm_index]
	var target_db := linear_to_db(maxf(0.001, def.volume))
	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()
	if fade <= 0.01:
		old.stop()
		next.stream = stream
		next.volume_db = target_db
		next.play()
	else:
		next.stream = stream
		next.volume_db = -60.0
		next.play()
		_bgm_tween = create_tween().set_parallel(true)
		_bgm_tween.tween_property(old, "volume_db", -60.0, fade)
		_bgm_tween.tween_property(next, "volume_db", target_db, fade)
		_bgm_tween.chain().tween_callback(old.stop)
	_bgm_id = id
	bgm_changed.emit(id)

func stop_bgm(fade: float = 0.8) -> void:
	if _bgm_id == &"":
		return
	var old := _bgm[_bgm_index]
	_bgm_id = &""
	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()
	if fade <= 0.01:
		old.stop()
	else:
		_bgm_tween = create_tween()
		_bgm_tween.tween_property(old, "volume_db", -60.0, fade)
		_bgm_tween.tween_callback(old.stop)

func current_bgm() -> StringName:
	return _bgm_id

## 根据「时段 / 天气 / 季节 / 场景」重算该放哪首。任何一项变化都调它。
func refresh_bgm() -> void:
	var want := BgmDirector.choose_now()
	if want != _bgm_id:
		play_bgm(want)
	_refresh_ambience()

## 环境音：下雨 / 雷雨时开雨声；室内压低（隔着一层屋顶）
func _refresh_ambience() -> void:
	var wet := WeatherSystem.today == WeatherSystem.Weather.RAIN \
		or WeatherSystem.today == WeatherSystem.Weather.STORM
	var indoor: bool = BgmDirector.INDOOR_SCENES.has(SceneRouter.current_id)
	_amb_wanted = &"rain_loop" if wet else &""
	var target := amb_volume
	var def := AudioDB.def_of(&"rain_loop")
	if def != null:
		target *= def.volume
	if indoor:
		target *= 0.45
	if _amb_id == _amb_wanted and _amb.playing:
		_fade_amb(target)
		return
	if _amb_wanted == &"":
		stop_ambience(1.4)
		return
	var stream: AudioStream = _load_stream(def.file, true) if def != null else null
	if stream == null:
		_warn_missing(&"rain_loop")
		return
	_amb_id = _amb_wanted
	_amb.stream = stream
	_amb.volume_db = -60.0
	_amb.play()
	_fade_amb(target, 1.6)

func _fade_amb(target_linear: float, fade: float = 0.8) -> void:
	var t := create_tween()
	t.tween_property(_amb, "volume_db", linear_to_db(maxf(0.001, target_linear)), fade)

func stop_ambience(fade: float = 1.0) -> void:
	if _amb_id == &"" or not _amb.playing:
		return
	_amb_id = &""
	var t := create_tween()
	t.tween_property(_amb, "volume_db", -60.0, fade)
	t.tween_callback(_amb.stop)

func current_ambience() -> StringName:
	return _amb_id

# ---------------- 场景地表（脚步音）----------------

## main 注册：世界坐标 → &"grass" / &"dirt"；房间场景注册：恒 &"wood"
func set_terrain_provider(cb: Callable) -> void:
	_terrain_provider = cb

func clear_terrain_provider() -> void:
	_terrain_provider = Callable()

## 玩家走一步：按脚下地表选音效（草地 / 泥地 / 木地板）
func footstep(world_pos: Vector2) -> bool:
	var terrain: StringName = &"grass"
	if _terrain_provider.is_valid():
		var r: Variant = _terrain_provider.call(world_pos)
		if typeof(r) == TYPE_STRING_NAME or typeof(r) == TYPE_STRING:
			terrain = StringName(r)
	match terrain:
		&"dirt":
			return play_sfx(&"step_dirt")
		&"wood":
			return play_sfx(&"step_wood")
	return play_sfx(&"step_grass")

# ---------------- 音量 / 配置 ----------------

## bus_name: master / bgm / sfx / amb
func set_volume(bus_name: StringName, linear: float) -> void:
	var v := clampf(linear, 0.0, 1.0)
	match bus_name:
		&"master":
			master_volume = v
		&"bgm":
			bgm_volume = v
		&"sfx":
			sfx_volume = v
		&"amb":
			amb_volume = v
		_:
			return
	_apply_bus_volumes()
	_save_settings()

func get_volume(bus_name: StringName) -> float:
	match bus_name:
		&"master":
			return master_volume
		&"bgm":
			return bgm_volume
		&"sfx":
			return sfx_volume
		&"amb":
			return amb_volume
	return 1.0

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("volume", "master", master_volume)
	cfg.set_value("volume", "bgm", bgm_volume)
	cfg.set_value("volume", "sfx", sfx_volume)
	cfg.set_value("volume", "amb", amb_volume)
	cfg.save(settings_path)

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return
	master_volume = float(cfg.get_value("volume", "master", master_volume))
	bgm_volume = float(cfg.get_value("volume", "bgm", bgm_volume))
	sfx_volume = float(cfg.get_value("volume", "sfx", sfx_volume))
	amb_volume = float(cfg.get_value("volume", "amb", amb_volume))

# ---------------- 事件挂载（跨系统音效）----------------

func _connect_events() -> void:
	EventBus.phase_changed.connect(_on_phase_changed)
	EventBus.weather_changed.connect(_on_weather_changed)
	EventBus.season_changed.connect(_on_season_changed)
	EventBus.day_advanced.connect(_on_day_advanced)
	# ⚠️ 换场信号在 SceneRouter 上，不是 EventBus：EventBus.scene_entered 是模块 11
	#    留下的死信号（没人 emit）。这里连错的话，进屋/进店 BGM 就不会换。
	SceneRouter.scene_entered.connect(_on_scene_entered)
	EventBus.ui_modal_changed.connect(_on_ui_modal_changed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.animal_vocalized.connect(_on_animal_vocalized)
	EventBus.player_stepped.connect(_on_player_stepped)
	EventBus.shop_purchased.connect(_on_shop_purchased)
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.building_built.connect(_on_building_built)
	EventBus.housing_upgraded.connect(_on_housing_upgraded)
	EventBus.tool_upgraded.connect(_on_tool_upgraded)
	EventBus.room_prop_used.connect(_on_room_prop_used)

func _on_phase_changed(_old: int, _new: int) -> void:
	refresh_bgm()

func _on_weather_changed(_today: int, _previous: int) -> void:
	refresh_bgm()

func _on_season_changed(_season: int) -> void:
	refresh_bgm()

func _on_day_advanced(_day: int, _season: int, _year: int) -> void:
	refresh_bgm()

func _on_scene_entered(_id: StringName) -> void:
	refresh_bgm()

func _on_ui_modal_changed(open: bool) -> void:
	play_ui(&"ui_open" if open else &"ui_close")

## 金币入账：涨钱才响（花钱是「买」的反馈，另算 shop_purchased）
func _on_gold_changed(delta: int, _total: int) -> void:
	if delta > 0:
		play_sfx(&"coin")

func _on_shop_purchased(_shop_id: StringName, _entry_id: StringName, _price: int) -> void:
	play_ui(&"ui_click")

func _on_building_placed(_def_id: StringName, _cell: Vector2i) -> void:
	play_sfx(&"build_place")

func _on_building_built(_building_id: StringName) -> void:
	play_sfx(&"build_done")

func _on_housing_upgraded(_housing_id: StringName, _level: int) -> void:
	play_sfx(&"build_done")

func _on_tool_upgraded(_tool: StringName, _level: int) -> void:
	play_sfx(&"build_done")

func _on_room_prop_used(_prop_id: StringName, action: StringName) -> void:
	match action:
		&"save":
			play_ui(&"save")
		&"shop", &"machine":
			play_ui(&"ui_click")
		&"bed":
			play_ui(&"ui_open")

## 动物叫：只有「在镜头附近」才响，避免全牧场 9 只动物此起彼伏（也省 2D 池）
func _on_animal_vocalized(species: StringName, pos: Vector2) -> void:
	var id := StringName("animal_" + String(species))
	if AudioDB.has(id):
		play_sfx_at(id, pos)

func _on_player_stepped(pos: Vector2) -> void:
	footstep(pos)

# ---------------- 诊断 ----------------

## 调试面板用：最近几声响了什么（新的在前）
func recent_plays(n: int = 3) -> Array:
	var out: Array = []
	var now := _now()
	var h := _pool.history
	var start := maxi(0, h.size() - n)
	for i in range(h.size() - 1, start - 1, -1):
		var e: Dictionary = h[i]
		out.append("%s · %.1fs 前 · 槽 %d" % [String(e["id"]), now - float(e["at"]), int(e["slot"])])
	return out

## 调试面板 / 测试用：一次性把当前音频状态捏成一个字典
func stats() -> Dictionary:
	return {
		"bgm": String(_bgm_id),
		"bgm_name": str(BgmDirector.TRACK_NAME.get(_bgm_id, "—")),
		"ambience": String(_amb_id),
		"phase": GameClock.phase_name(),
		"weather": WeatherSystem.weather_name(),
		"scene": String(SceneRouter.current_id),
		"sfx_busy": _pool.busy(_now()),
		"sfx_voices": SFX_VOICES,
		"pos_busy": _pos_pool.busy(_now()),
		"pos_voices": POS_VOICES,
		"plays": _plays_total,
		"rejects": _rejects.duplicate(),
		"master": master_volume, "bgm_vol": bgm_volume,
		"sfx_vol": sfx_volume, "amb_vol": amb_volume,
		"missing": AudioDB.missing_files().size(),
		"explain": BgmDirector.explain(GameClock.current_phase(), WeatherSystem.today,
			GameClock.season, SceneRouter.current_id),
	}

## 测试用：清空池子/停止一切（不动总线与设置）
func reset_state() -> void:
	_pool.reset()
	_pos_pool.reset()
	for p in _sfx:
		p.stop()
	for q in _pos:
		q.stop()
	for b in _bgm:
		b.stop()
	_bgm_id = &""
	_bgm_index = 0
	if _amb != null:
		_amb.stop()
	_amb_id = &""
	_amb_wanted = &""
	_plays_total = 0
	_rejects.clear()
	_missing_warned.clear()
