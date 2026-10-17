extends Node
## 模块 7 截图：背包网格 / 工具铺 / 订单板 / 加工坊 / 杂货铺回收页
## 用法： godot --path <项目> res://tests/shot_module7.tscn

func _ready() -> void:
	var ps: PackedScene = load("res://scenes/main.tscn")
	var main := ps.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().physics_frame
	var p = main.get_node_or_null("World/YSortRoot/Player")

	# 先塞点东西，让背包 / 订单 / 加工坊都有内容
	GameState.add_item(&"milk", 4)
	GameState.add_item(&"milk_gold", 2)
	GameState.add_item(&"egg", 6)
	GameState.add_item(&"wool", 3)
	GameState.add_item(&"turnip_gold", 2)
	GameState.add_item(&"cheese", 1)
	main._refresh_hud()
	main._refresh_toolbar()

	# ---------- ① 背包网格：8×5 格 + 品质星 + 数量 ----------
	_place(p, Vector2(384, 224), "down")
	var inv: InventoryUI = main.get_node("UI/InventoryPanel")
	inv.open()
	inv.set_cursor(0)
	main._say("I 键开背包：8 列网格 · 拖拽换位/合并 · E 使用 · X 丢 1 个")
	await _settle(14)
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module7_bag.png")
	inv.close()
	await _settle(4)

	# ---------- ② 工具铺：6 行升级，钱不够/缺木材的变灰 ----------
	GameState.gold = 1200
	main._shop_kind = &"tool"
	EventBus.shop_requested.emit(&"tool")
	_place(p, Vector2(352, 356), "up")
	await _settle(10)
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module7_tool.png")
	main._shop.close()
	await _settle(4)

	# ---------- ③ 订单板：两张 NPC 委托，一张现在就能交 ----------
	var o: Dictionary = main._orders.active_orders()[0]
	GameState.add_item(o["item"], int(o["count"]))
	main._refresh_orders()
	_place(p, Vector2(416, 356), "up")
	EventBus.shop_requested.emit(&"order")
	await _settle(10)
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module7_order.png")
	main._shop.close()
	await _settle(4)

	# ---------- ④ 加工坊：放料 → 倒计时 → 取货 ----------
	_place(p, Vector2(480, 356), "up")
	main._on_craft_start(&"cheese@0")
	main._advance_workshop(60)
	main._say("加工坊 2 槽 · 牛奶×2 → 奶酪（2 小时）· 品质继承原料")
	EventBus.shop_requested.emit(&"craft")
	await _settle(10)
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module7_craft.png")
	main._shop.close()
	await _settle(4)

	# ---------- ⑤ 杂货铺回收页：单价 + 行情涨跌 + 合计 ----------
	_place(p, Vector2(480, 212), "up")
	EventBus.shop_requested.emit(&"supply")
	await _settle(6)
	main._on_mode_toggle()
	main._say("杂货铺按 T 切回收页：单价 · 行情涨跌 · 合计，Shift+E 整叠卖")
	await _settle(10)
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module7_sell.png")
	main._shop.close()
	await _settle(4)

	# ---------- ⑥ 全景：三个新建筑（工具铺 / 订单板 / 加工坊）----------
	_place(p, Vector2(384, 300), "down")
	main._say("新建筑：工具铺（左）· 订单板（中）· 加工坊（右）")
	await _settle(20)
	await RenderingServer.frame_post_draw
	_shot("res://_uu/shot_module7_world.png")

	get_tree().quit()

func _place(p, pos: Vector2, dir: String) -> void:
	if p == null:
		return
	p.global_position = pos
	p.facing = dir
	p.facing8 = dir

func _settle(frames: int) -> void:
	for i in range(frames):
		await get_tree().physics_frame
		await get_tree().process_frame

func _shot(res_path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path(res_path)
	print("SHOT %dx%d %s %s" % [img.get_width(), img.get_height(), img.save_png(out), out])
