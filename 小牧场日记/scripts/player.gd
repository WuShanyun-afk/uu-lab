class_name Player
extends CharacterBody2D
## 玩家 —— LPC 4 向行走 + 农具交互（GDD 里程碑 1 / 2）
##
## 精灵来自 lpc-character-mcp：
##   assets/characters/player.png   832×3456, standard 布局, 64px 帧
##   assets/characters/player.tres  SpriteFrames, 16 个动画
##
## ⚠️ 许可证：素材为 CC-BY-SA 3.0 / GPL 3.0 / OGA-BY 3.0。
##    license_check.drm_safe = true（Steam / App Store 可用），但**必须**在致谢页
##    包含 player_credits.txt 里的 statement。

signal tool_used(tool: int, cell: Vector2i)

enum Tool { HOE, CAN, SEED, FEED, HAND }

const TOOL_LABEL := ["锄头", "洒水壶", "种子", "饲料", "手"]
const SPEED := 100.0
const TILE := 32

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

var facing := "down"
var current_tool: int = Tool.HOE
var selected_seed: StringName = &"turnip"

func _physics_process(_delta: float) -> void:
	var dir := _input_dir()
	velocity = dir * SPEED
	move_and_slide()

	if dir != Vector2.ZERO:
		facing = _dir_name(dir)
		_play("walk_" + facing)
	else:
		_play("idle_" + facing)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_set_tool(Tool.HOE)
			KEY_2:
				_set_tool(Tool.CAN)
			KEY_3:
				_set_tool(Tool.SEED)
			KEY_4:
				_set_tool(Tool.FEED)
			KEY_5:
				_set_tool(Tool.HAND)
			KEY_E:
				tool_used.emit(current_tool, target_cell())
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		tool_used.emit(current_tool, target_cell())

func _set_tool(t: int) -> void:
	current_tool = t
	EventBus.tool_changed.emit(t)

## 面朝方向单位向量
func facing_vector() -> Vector2:
	match facing:
		"up":
			return Vector2(0, -1)
		"left":
			return Vector2(-1, 0)
		"right":
			return Vector2(1, 0)
	return Vector2(0, 1)

## 交互点：身前一小段距离（用于够到动物）
func interact_point() -> Vector2:
	return position + facing_vector() * 22.0

## 面朝的格子
func target_cell() -> Vector2i:
	var off := Vector2i.ZERO
	match facing:
		"up":
			off = Vector2i(0, -1)
		"down":
			off = Vector2i(0, 1)
		"left":
			off = Vector2i(-1, 0)
		"right":
			off = Vector2i(1, 0)
	var base := Vector2i(floori(position.x / float(TILE)), floori(position.y / float(TILE)))
	return base + off

func _play(anim: String) -> void:
	if _sprite.animation == anim:
		return
	if _sprite.sprite_frames and _sprite.sprite_frames.has_animation(anim):
		_sprite.play(anim)

func _dir_name(d: Vector2) -> String:
	if absf(d.x) > absf(d.y):
		return "right" if d.x > 0.0 else "left"
	return "down" if d.y > 0.0 else "up"

func _input_dir() -> Vector2:
	var d := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		d.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		d.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		d.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		d.y += 1.0
	return d.normalized() if d != Vector2.ZERO else Vector2.ZERO
