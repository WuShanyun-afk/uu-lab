extends Node
## 附属模块 1 验收：全局音频与氛围系统
##
## 需求对照：
##   ① 全局 AudioManager（Autoload）：BGM 淡入淡出 / 音量 / SFX 池防爆音
##   ② 音效触发挂载：环境（脚步/雨）· 交互（锄地/浇水/播种/挤奶/捡蛋/剪刀）·
##      动物叫声（靠近随机）· UI（背包/金币/按钮）
##   ③ 动态 BGM：清晨/白天/黄昏/夜晚 + 季节/天气覆盖（雨天忧郁）
##   ④ MCP 工具指导：见 _uu/音频MCP使用指南.md（文档，不进测试）
##
## 运行： godot --headless --path <项目> res://tests/test_module13.tscn
##
## ⚠️ 音量配置写到 user://audio_test13.cfg，不碰玩家真实设置。

var _fails: Array[String] = []
var _n := 0

func _check(cond: bool, label: String) -> void:
	_n += 1
	if not cond:
		_fails.append(label)
	print(("  [OK] " if cond else "  [FAIL] ") + label)

func _ready() -> void:
	print("=== 附属模块 1 验收：全局音频与氛围系统 ===")
	AudioManager.settings_path = "user://audio_test13.cfg"
	AudioManager.reset_state()
	_test_data_table()
	_test_pool()
	_test_director()
	_test_manager()
	_test_events()
	await _test_main_integration()
	AudioManager.reset_state()
	WeatherSystem.today = WeatherSystem.Weather.CLEAR
	SceneRouter.current_id = &"farm"
	var ok := _fails.is_empty()
	print("=== 结果：%s（共 %d 项）===" % ["全部通过" if ok else "失败 %d 项" % _fails.size(), _n])
	if not ok:
		for f in _fails:
			print("   ! " + f)
	get_tree().quit(0 if ok else 1)

# ============================================================================
# 1. 数据表 / 素材完整性
# ============================================================================

func _test_data_table() -> void:
	print("[1] 音频表与素材")
	_check(AudioDB.defs.size() == 35, "音频表 35 条（%d）" % AudioDB.defs.size())
	_check(AudioDB.ids_of_kind(&"sfx").size() == 27, "音效 27 条（%d）" % AudioDB.ids_of_kind(&"sfx").size())
	_check(AudioDB.ids_of_kind(&"bgm").size() == 7, "BGM 7 首（%d）" % AudioDB.ids_of_kind(&"bgm").size())
	_check(AudioDB.ids_of_kind(&"ambience").size() == 1, "环境音 1 条")
	_check(AudioDB.missing_files().is_empty(), "素材文件全在（缺 %d）" % AudioDB.missing_files().size())

	# 分类齐全：脚步 3 / 交互 7 / 动物 9 / 界面 4 / 系统 4
	_check(AudioDB.ids_of_category(&"step").size() == 3, "脚步类 3 条")
	_check(AudioDB.ids_of_category(&"interact").size() == 7, "交互类 7 条")
	_check(AudioDB.ids_of_category(&"animal").size() == 9, "动物类 9 条（9 个物种）")
	_check(AudioDB.ids_of_category(&"ui").size() == 4, "界面类 4 条")
	_check(AudioDB.ids_of_category(&"system").size() == 4, "系统类 4 条")

	# 需求点名的音效必须都在
	for id in [&"step_grass", &"step_dirt", &"hoe", &"water", &"plant", &"milk", &"egg",
			&"shears", &"ui_open", &"ui_click", &"coin"]:
		_check(AudioDB.has(id), "有音效 %s" % String(id))
	for id in [&"animal_cow", &"animal_sheep", &"animal_chicken", &"animal_duck", &"animal_bee"]:
		_check(AudioDB.has(id), "有动物叫 %s" % String(id))

	# 动态 BGM 七首都在，且是 loop
	for id in [&"bgm_morning", &"bgm_day", &"bgm_dusk", &"bgm_night",
			&"bgm_rain", &"bgm_snow", &"bgm_indoor"]:
		var d: AudioDef = AudioDB.def_of(id)
		_check(d != null, "有 BGM %s" % String(id))
		_check(d.loop if d != null else false, "%s 循环" % String(id))

	# 表里的文件能真的 load 成 AudioStream，且长度 > 0
	var bad := 0
	for id in AudioDB.defs:
		var d: AudioDef = AudioDB.def_of(id)
		var s := load(d.file) as AudioStream
		if s == null or s.get_length() <= 0.0:
			bad += 1
	_check(bad == 0, "35 条都能 load 成有声流（坏 %d）" % bad)
	var cow: AudioDef = AudioDB.def_of(&"animal_cow")
	var s_cow := load(cow.file) as AudioStream
	_check(s_cow != null and s_cow.get_length() > 0.5, "牛叫长度 > 0.5s（%.2f）" % s_cow.get_length())
	_check(cow.volume > 0.0 and cow.volume <= 1.0, "牛叫音量在 0–1（%.2f）" % cow.volume)
	_check(cow.pitch_max > cow.pitch_min, "牛叫有音高抖动（防机械感）")

# ============================================================================
# 2. SFX 池（防爆音的纯逻辑）
# ============================================================================

func _make_def(id: StringName, cooldown: float = 0.0, voices: int = 0) -> AudioDef:
	var d := AudioDef.new()
	d.id = id
	d.kind = &"sfx"
	d.cooldown = cooldown
	d.max_voices = voices
	d.volume = 1.0
	d.pitch_min = 1.0
	d.pitch_max = 1.0
	return d

func _test_pool() -> void:
	print("[2] SFX 池：冷却 / 同 id 并发 / 抢槽 / 代数")
	var pool := SfxPool.new(4)
	var a := _make_def(&"a", 0.5, 1)
	_check(pool.busy(0.0) == 0, "空池 busy=0")

	var r1 := pool.try_acquire(a, 0.0, 0.3)
	_check(int(r1["slot"]) >= 0 and r1["reason"] == SfxPool.OK, "第一次放：分配槽 %d" % int(r1["slot"]))
	_check(pool.busy(0.0) == 1, "busy=1")
	_check(pool.active_of(&"a") == 1, "a 的活跃数 1")

	var r2 := pool.try_acquire(a, 0.1, 0.3)
	_check(int(r2["slot"]) < 0 and r2["reason"] == SfxPool.REJECT_COOLDOWN, "0.1s 内再来一声：冷却拦下")

	var r3 := pool.try_acquire(a, 0.6, 0.3)
	_check(int(r3["slot"]) < 0 and r3["reason"] == SfxPool.REJECT_VOICES, "冷却过了但已响着 1 个：并发拦下")

	pool.release(int(r1["slot"]), int(r1["token"]))
	_check(pool.active_of(&"a") == 0, "release 后活跃数清零")
	_check(pool.busy(0.6) == 0, "release 后 busy=0")
	var r4 := pool.try_acquire(a, 0.7, 0.3)
	_check(int(r4["slot"]) >= 0, "释放后再放：成功")

	# 填满池子，然后抢槽
	pool.reset()
	for i in range(4):
		var d := _make_def(StringName("fill%d" % i))
		pool.try_acquire(d, 0.0, 5.0)
	_check(pool.busy(0.1) == 4, "池子填满 4/4")
	var ev := _make_def(&"event")
	var r5 := pool.try_acquire(ev, 0.2, 0.2)
	_check(r5["reason"] == SfxPool.STEAL, "满了就抢最早结束的槽（steal）")
	_check(pool.active_of(&"event") == 1, "抢来后 event 计数 +1")

	# 旧音效的 finished 回调（旧代数）不能把新音效释放掉
	var stolen_slot := int(r5["slot"])
	pool.release(stolen_slot, 1)
	_check(pool.busy(0.2) == 4, "旧代数的 finished 不会误释放新音效")

	var snap := pool.snapshot(0.2)
	_check(snap.size() == 4, "snapshot 4 条")
	_check(str(snap[stolen_slot]["id"]) == "event", "snapshot 里抢来的槽是 event")
	_check(pool.history.size() >= 5, "历史记录有留档")
	pool.reset()
	_check(pool.busy(1.2) == 0 and pool.history.is_empty(), "reset 清空")

# ============================================================================
# 3. 动态 BGM 选曲
# ============================================================================

func _test_director() -> void:
	print("[3] 动态 BGM 选曲（时段 / 天气 / 季节 / 场景）")
	var D := BgmDirector
	_check(D.choose(D.P_DAWN, 0, 0, &"farm") == D.T_MORNING, "清晨 → 清晨曲")
	_check(D.choose(D.P_DAY, 0, 0, &"farm") == D.T_DAY, "白天 → 白天曲")
	_check(D.choose(D.P_DUSK, 0, 0, &"farm") == D.T_DUSK, "黄昏 → 黄昏曲")
	_check(D.choose(D.P_NIGHT, 0, 0, &"farm") == D.T_NIGHT, "夜晚 → 夜晚曲")

	_check(D.choose(D.P_DAY, D.W_RAIN, 0, &"farm") == D.T_RAIN, "雨天覆盖白天 → 忧郁曲")
	_check(D.choose(D.P_NIGHT, D.W_RAIN, 0, &"farm") == D.T_RAIN, "夜雨也是雨曲")
	_check(D.choose(D.P_DAY, D.W_STORM, 0, &"farm") == D.T_RAIN, "雷雨 → 雨曲")
	_check(D.choose(D.P_DAY, D.W_SNOW, 0, &"farm") == D.T_SNOW, "下雪 → 雪曲")
	_check(D.choose(D.P_DAY, 0, D.S_WINTER, &"farm") == D.T_SNOW, "冬季白天 → 雪曲")
	_check(D.choose(D.P_NIGHT, 0, D.S_WINTER, &"farm") == D.T_NIGHT, "冬季夜晚仍是夜曲")

	for scn in [&"house", &"shop", &"mine"]:
		_check(D.choose(D.P_DAY, 0, 0, scn) == D.T_INDOOR, "室内场景 %s → 室内曲" % String(scn))
	_check(D.choose(D.P_DAY, D.W_RAIN, 0, &"house") == D.T_INDOOR, "屋里下雨也不切雨曲（听不见）")
	_check(D.choose(D.P_DAY, D.W_RAIN, 0, &"town") == D.T_RAIN, "镇上露天还是雨曲")
	_check(D.choose(D.P_DAY, 0, 0, &"town") == D.T_DAY, "镇上晴天 = 白天曲")

	_check(is_equal_approx(D.fade_for(D.T_DAY, D.T_RAIN), 2.6), "切到雨曲淡入 2.6s（更长）")
	_check(is_equal_approx(D.fade_for(D.T_DAY, D.T_INDOOR), 1.8), "切到室内 1.8s")
	_check(is_equal_approx(D.fade_for(D.T_MORNING, D.T_DAY), 1.2), "时段切换 1.2s")
	_check(is_equal_approx(D.fade_for(D.T_DAY, D.T_DAY), 0.0), "同一首不淡")

	_check(D.explain(D.P_DAY, D.W_RAIN, 0, &"farm").contains("雨"), "解释里写了「雨」")
	_check(D.explain(D.P_DAY, 0, 0, &"farm").contains("白天"), "解释里写了「白天」")
	_check(str(D.TRACK_NAME[D.T_NIGHT]) == "夜晚", "曲名表有夜晚")

# ============================================================================
# 4. AudioManager：总线 / 音量 / 播放 / 防爆 / 环境音 / 脚步
# ============================================================================

func _test_manager() -> void:
	print("[4] AudioManager：总线 / 音量 / 播放闸门 / 雨声 / 脚步")
	for bus in [&"BGM", &"SFX", &"Amb"]:
		_check(AudioServer.get_bus_index(bus) >= 0, "有总线 %s" % String(bus))

	AudioManager.set_volume(&"bgm", 0.42)
	_check(is_equal_approx(AudioManager.get_volume(&"bgm"), 0.42), "SET/GET bgm 音量 0.42")
	_check(FileAccess.file_exists(AudioManager.settings_path), "音量写进了配置")
	var idx := AudioServer.get_bus_index(&"BGM")
	var db := AudioServer.get_bus_volume_db(idx)
	_check(absf(db - linear_to_db(0.42)) < 0.01, "BGM 总线分贝 = linear_to_db(0.42)（%.2f）" % db)
	AudioManager.set_volume(&"bgm", 0.7)

	# 缺 id / 缺素材：安静地失败，不抛
	_check(not AudioManager.play_sfx(&"no_such_sound"), "不存在的 id → false")
	# 冷却：同一帧连放两声，第二声被拦
	AudioManager.reset_state()
	_check(AudioManager.play_sfx(&"step_grass"), "放 step_grass 成功")
	_check(not AudioManager.play_sfx(&"step_grass"), "同帧再来一声被冷却拦下")
	var st := AudioManager.stats()
	_check(int(st["plays"]) == 1, "统计里只记了 1 声（%d）" % int(st["plays"]))
	_check(int(st["rejects"].get("cooldown", 0)) >= 1, "拦下原因记为 cooldown")

	# BGM：换曲 / 同曲不重启动 / 信号
	AudioManager.reset_state()
	var got: Array = []
	var cb := func(id: StringName) -> void: got.append(id)
	AudioManager.bgm_changed.connect(cb)
	AudioManager.play_bgm(&"bgm_day", 0.0)
	_check(AudioManager.current_bgm() == &"bgm_day", "当前 BGM = bgm_day")
	AudioManager.play_bgm(&"bgm_day", 0.0)
	_check(got.size() == 1, "同一首不会重复发信号（%d）" % got.size())
	AudioManager.play_bgm(&"bgm_dusk", 0.0)
	_check(AudioManager.current_bgm() == &"bgm_dusk" and got.size() == 2, "换到黄昏曲，信号 2 次")
	AudioManager.bgm_changed.disconnect(cb)
	# BGM 流真的开了循环（否则只会响一遍）
	var playing: AudioStream = AudioManager._bgm[AudioManager._bgm_index].stream
	var wav := playing as AudioStreamWAV
	_check(wav != null and wav.loop_mode == AudioStreamWAV.LOOP_FORWARD, "BGM 流是循环模式")

	# 动态：雨天 → 雨曲 + 雨声；进屋 → 室内曲但雨声还在（压低）
	AudioManager.reset_state()
	var old_w := WeatherSystem.today
	var old_scene: StringName = SceneRouter.current_id
	WeatherSystem.today = WeatherSystem.Weather.RAIN
	SceneRouter.current_id = &"farm"
	AudioManager.refresh_bgm()
	_check(AudioManager.current_bgm() == &"bgm_rain", "雨天 refresh 自动切雨曲")
	_check(AudioManager.current_ambience() == &"rain_loop", "雨天开雨声环境音")
	SceneRouter.current_id = &"house"
	AudioManager.refresh_bgm()
	_check(AudioManager.current_bgm() == &"bgm_indoor", "进屋切室内曲")
	_check(AudioManager.current_ambience() == &"rain_loop", "屋里雨声还在（隔雨声）")
	WeatherSystem.today = WeatherSystem.Weather.CLEAR
	SceneRouter.current_id = old_scene
	AudioManager.refresh_bgm()

	# 脚步：地表查询决定用哪个音
	AudioManager.reset_state()
	AudioManager.set_terrain_provider(func(_p: Vector2) -> StringName: return &"dirt")
	_check(AudioManager.footstep(Vector2.ZERO), "泥地脚步声放出来了")
	_check(AudioManager._pool.active_of(&"step_dirt") == 1, "走的是 step_dirt")
	AudioManager.reset_state()
	AudioManager.set_terrain_provider(func(_p: Vector2) -> StringName: return &"wood")
	_check(AudioManager.footstep(Vector2.ZERO), "木地板脚步声")
	_check(AudioManager._pool.active_of(&"step_wood") == 1, "走的是 step_wood")
	AudioManager.reset_state()
	AudioManager.clear_terrain_provider()
	_check(AudioManager.footstep(Vector2.ZERO), "没有地表查询时退回草地")
	_check(AudioManager._pool.active_of(&"step_grass") == 1, "退回 step_grass")

	# 调试面板
	AudioDebugPanel.set_open(true)
	_check(AudioDebugPanel.is_open(), "F3 面板能打开")
	AudioDebugPanel.set_open(false)
	_check(not AudioDebugPanel.is_open(), "F3 面板能关")
	AudioManager.set_volume(&"master", 1.0)
	AudioManager.set_volume(&"bgm", 0.7)
	AudioManager.set_volume(&"sfx", 0.9)
	AudioManager.set_volume(&"amb", 0.8)
	AudioManager.reset_state()
	WeatherSystem.today = old_w

# ============================================================================
# 5. 事件挂载：金币 / UI / 动物叫 / 玩家脚步 / 存档音
# ============================================================================

func _test_events() -> void:
	print("[5] 事件挂载（EventBus）")
	AudioManager.reset_state()
	GameState.gold = 500
	GameState.add_gold(120)
	_check(AudioManager._pool.active_of(&"coin") == 1, "金币入账 → 响 coin")
	AudioManager.reset_state()
	GameState.spend_gold(120)
	_check(AudioManager._pool.active_of(&"coin") == 0, "花钱不响 coin")

	AudioManager.reset_state()
	EventBus.set_ui_modal(true)
	_check(AudioManager._pool.active_of(&"ui_open") == 1, "UI 打开 → ui_open")
	EventBus.set_ui_modal(false)
	_check(AudioManager._pool.active_of(&"ui_close") == 1, "UI 关闭 → ui_close")
	EventBus.ui_modal = false

	AudioManager.reset_state()
	EventBus.animal_vocalized.emit(&"cow", Vector2(100, 100))
	_check(AudioManager._pos_pool.active_of(&"animal_cow") == 1, "动物叫 → 2D 池 animal_cow")
	EventBus.animal_vocalized.emit(&"bee", Vector2(120, 100))
	_check(AudioManager._pos_pool.active_of(&"animal_bee") == 1, "蜜蜂叫 → animal_bee")

	AudioManager.reset_state()
	AudioManager.set_terrain_provider(func(_p: Vector2) -> StringName: return &"grass")
	EventBus.player_stepped.emit(Vector2(64, 64))
	_check(AudioManager._pool.active_of(&"step_grass") == 1, "玩家脚步事件 → 草地脚步")
	AudioManager.clear_terrain_provider()

	AudioManager.reset_state()
	EventBus.room_prop_used.emit(&"save_box", &"save")
	_check(AudioManager._pool.active_of(&"save") == 1, "存档柜 → save 音")
	AudioManager.reset_state()
	EventBus.building_placed.emit(&"barn", Vector2i(3, 3))
	_check(AudioManager._pool.active_of(&"build_place") == 1, "建筑落成 → build_place")

	var st := AudioManager.stats()
	for key in ["bgm", "ambience", "phase", "weather", "scene", "sfx_busy", "plays", "explain"]:
		_check(st.has(key), "stats 有 %s" % key)
	_check(AudioManager.recent_plays(3).size() <= 3, "最近播放最多 3 条")
	AudioManager.reset_state()

# ============================================================================
# 6. 与真实牧场场景的接线（地表查询 / 动物叫 / 起床曲）
# ============================================================================

func _test_main_integration() -> void:
	print("[6] 与 main.tscn 的接线")
	var m := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(m)
	for i in range(3):
		await get_tree().process_frame
	_check(AudioManager._terrain_provider.is_valid(), "main 注册了地表查询")
	AudioManager.reset_state()
	var grassy: Variant = AudioManager._terrain_provider.call(Vector2(3 * 32 + 16, 3 * 32 + 16))
	_check(str(grassy) == "grass", "未锄的地 → 草地（%s）" % str(grassy))
	m._grid.till(Vector2i(3, 3))
	var dirty: Variant = AudioManager._terrain_provider.call(Vector2(3 * 32 + 16, 3 * 32 + 16))
	_check(str(dirty) == "dirt", "锄过的地 → 泥地（%s）" % str(dirty))
	# 锄地时真的会响
	AudioManager.reset_state()
	m._hoe(Vector2i(4, 3))
	_check(AudioManager._pool.active_of(&"hoe") == 1, "main._hoe 触发锄地音效")

	# 收成音按物种分
	_check(m._harvest_sfx(&"cow") == &"milk", "牛 → 挤奶音")
	_check(m._harvest_sfx(&"sheep") == &"shears", "羊 → 剪刀音")
	_check(m._harvest_sfx(&"chicken") == &"egg", "鸡 → 捡蛋音")

	# BGM 与场景/时段对得上（minutes 0 = 06:00：60 = 07:00 清晨 / 900 = 21:00 夜晚）
	AudioManager.reset_state()
	GameClock.minutes = 60
	SceneRouter.current_id = &"farm"
	WeatherSystem.today = WeatherSystem.Weather.CLEAR
	AudioManager.refresh_bgm()
	_check(AudioManager.current_bgm() == &"bgm_morning", "07:00 的牧场是清晨曲（%s）" %
		String(AudioManager.current_bgm()))
	GameClock.minutes = 900
	AudioManager.refresh_bgm()
	_check(AudioManager.current_bgm() == &"bgm_night", "21:00 是夜晚曲（%s）" %
		String(AudioManager.current_bgm()))
	GameClock.minutes = 240

	# 换场信号真的接到了（SceneRouter.scene_entered → 室内曲）。
	# ⚠️ 曾经连到 EventBus.scene_entered（没人 emit 的死信号），进屋不换曲，这条就是防它。
	SceneRouter.suppress_scene_change = true
	AudioManager.reset_state()
	AudioManager.play_bgm(&"bgm_day", 0.0)
	SceneRouter.travel(&"house", &"door")
	await get_tree().process_frame
	_check(SceneRouter.current_id == &"house", "suppress 模式下 current_id 改成 house")
	_check(AudioManager.current_bgm() == &"bgm_indoor", "换场信号 → BGM 切到室内（%s）" %
		String(AudioManager.current_bgm()))
	SceneRouter.suppress_scene_change = false
	SceneRouter.current_id = &"farm"
	AudioManager.refresh_bgm()

	m.queue_free()
	await get_tree().process_frame
