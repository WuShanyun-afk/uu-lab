extends Node
## 模块 11 截图：**真实**场景切换端到端（牧场 → 屋内 → 牧场 → 镇上 → 商店 → 矿洞）
## 用法： godot --path <项目> res://tests/shot_module11.tscn
##
## ⚠️ 换场会把 current_scene 整个 free 掉 —— 如果驱动逻辑写在 current_scene 上，
##    第一次 travel 之后脚本自己就没了，后面全部拍不到。
##    所以这里把真正的驱动放进一个**挂在 root 上**的 Driver 节点：
##    change_scene_to_file 只替换 current_scene，root 的其它孩子不受影响。
##
## ⚠️ SaveSystem.save_dir 指到 user://saves_shot11，不动玩家真存档。

func _ready() -> void:
	SaveSystem.save_dir = "user://saves_shot11"
	GameState.reset()
	GameClock.day = 12
	GameClock.season = 1
	GameClock.minutes = 240          # 10:00
	GameClock.phase = GameClock.phase_at(GameClock.minutes)
	var driver := Driver.new()
	driver.name = "ShotDriver"
	# ⚠️ _ready 里 root 正在初始化子节点，直接 add_child 会报
	#    "Parent node is busy setting up children" —— 必须延迟一帧加
	get_tree().root.add_child.call_deferred(driver)
	queue_free()                     # 引导节点功成身退（它本来就是 current_scene）

class Driver extends Node:
	func _ready() -> void:
		await get_tree().process_frame
		await _settle(8)
		# ① 牧场
		await _shot("res://_uu/shot_module11_farm.png", "牧场")
		# ② 牧场 → 屋内
		SceneRouter.travel(&"house", &"door")
		await _settle(40)
		await _shot("res://_uu/shot_module11_house.png", "屋内")
		# ③ 屋内 → 出门回牧场（需求 3 第一条链路）
		SceneRouter.travel(&"farm", &"house_door")
		await _settle(40)
		await _shot("res://_uu/shot_module11_back.png", "回到牧场")
		# ④ 牧场 → 镇上
		SceneRouter.travel(&"town", &"from_farm")
		await _settle(40)
		await _shot("res://_uu/shot_module11_town.png", "镇上")
		# ⑤ 镇上 → 商店
		SceneRouter.travel(&"shop", &"from_town")
		await _settle(40)
		await _shot("res://_uu/shot_module11_shop.png", "商店")
		# ⑥ 回镇上 → 回牧场 → 矿洞
		SceneRouter.travel(&"town", &"from_shop")
		await _settle(30)
		SceneRouter.travel(&"farm", &"from_town")
		await _settle(40)
		SceneRouter.travel(&"mine", &"from_farm")
		await _settle(40)
		await _shot("res://_uu/shot_module11_mine.png", "矿洞")
		# ⑦ 多存档位面板
		SavePanel.open()
		await _settle(6)
		print("PANEL_OPEN=%s  SLOTS=%d" % [str(SavePanel.is_open()), SaveSystem.SLOT_MAX + 1])
		await _shot("res://_uu/shot_module11_savepanel.png", "存档面板")
		SavePanel.close()
		print("当前场景=%s  存档目录=%s" % [SceneRouter.current_id, SaveSystem.save_dir])
		get_tree().quit()

	func _settle(frames: int) -> void:
		for i in range(frames):
			await get_tree().physics_frame
			await get_tree().process_frame

	func _shot(res_path: String, label: String) -> void:
		var cur := get_tree().current_scene
		var cur_path := "" if cur == null else cur.scene_file_path
		var img := get_viewport().get_texture().get_image()
		var out := ProjectSettings.globalize_path(res_path)
		print("SHOT[%s] scene=%s %dx%d ok=%s" % [label, cur_path,
			img.get_width(), img.get_height(), str(img.save_png(out))])
