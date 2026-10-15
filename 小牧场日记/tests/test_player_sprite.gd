extends Node
## 玩家精灵验收：确认 LPC 产物真的挂上了，而不是"看着像"
## 运行： godot --headless --path <项目> res://tests/test_player_sprite.tscn

var _fails: Array[String] = []

func _check(cond: bool, label: String) -> void:
	if not cond:
		_fails.append(label)
	print(("  [OK] " if cond else "  [FAIL] ") + label)

func _ready() -> void:
	print("=== 玩家精灵验收 ===")

	var frames: SpriteFrames = load("res://assets/characters/player.tres")
	_check(frames != null, "player.tres 可加载")
	if frames:
		var anims := frames.get_animation_names()
		_check(anims.size() == 16, "动画数 = 16（实际 %d）" % anims.size())
		for a in ["walk_up", "walk_down", "walk_left", "walk_right",
				  "idle_up", "idle_down", "idle_left", "idle_right",
				  "slash_down", "run_down"]:
			_check(frames.has_animation(a), "存在动画 %s" % a)
		if frames.has_animation("walk_down"):
			_check(frames.get_frame_count("walk_down") >= 4,
				"walk_down 帧数 >= 4（实际 %d）" % frames.get_frame_count("walk_down"))
			var tex: Texture2D = frames.get_frame_texture("walk_down", 0)
			_check(tex != null and tex.get_width() == 64 and tex.get_height() == 64,
				"帧尺寸 64×64（实际 %s）" % ("null" if tex == null else "%d×%d" % [tex.get_width(), tex.get_height()]))

	var ps: PackedScene = load("res://scenes/player.tscn")
	_check(ps != null, "player.tscn 可加载")
	if ps:
		var p := ps.instantiate()
		var spr: AnimatedSprite2D = p.get_node_or_null("AnimatedSprite2D")
		_check(spr != null, "有 AnimatedSprite2D 节点")
		if spr:
			_check(spr.sprite_frames != null, "AnimatedSprite2D 挂了 sprite_frames")
			_check(spr.position == Vector2(0, -32), "精灵上移 32px（脚对齐原点）")
		var col: CollisionShape2D = p.get_node_or_null("CollisionShape2D")
		_check(col != null, "有 CollisionShape2D（脚部碰撞盒）")
		p.free()

	var ok := _fails.is_empty()
	print("=== 结果：%s ===" % ("全部通过" if ok else "失败 %d 项" % _fails.size()))
	if not ok:
		for f in _fails:
			print("   ! " + f)
	get_tree().quit(0 if ok else 1)
