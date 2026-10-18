class_name Player
extends CharacterBody2D
## 玩家 —— 8 方向移动 + LPC 4 向立绘 + 交互探针 + 农具切换（模块 1）
##
## 移动：输入向量归一化后按 45° 量化成 8 向（facing8），立绘取主轴（facing）。
##       LPC 素材只有 4 向，所以「斜着走」用主轴那张图，手感是标准的 8 向移动。
##
## 两套精灵图集，按当前工具切换：
##   assets/characters/player.tres      walk / idle / run / slash（空手·锄头·种子）
##   assets/characters/player_can.tres  walk / thrust / watering（洒水壶）
##
## ⚠️ LPC 的洒水壶素材只存在于 walk 和 thrust 两条动画行（equipment_only_in），
##    没有独立的 idle 行。所以「拿着壶站着」用 thrust 的第 0 帧定格。
##
## ⚠️ 许可证：素材 CC-BY-SA 3.0 / GPL / OGA-BY 3.0，license_check.drm_safe = true。
##    发布时**必须**在致谢页粘贴 player_credits.txt / player_can_credits.txt 里的 statement。

signal tool_used(tool: int, cell: Vector2i)
## 聚焦的可交互物变化时广播提示文字（"" = 附近没东西可交互）
signal prompt_changed(text: String)
## 换种子（模块 3）
signal seed_changed(seed_id: StringName)

enum Tool { HOE, CAN, SEED, FEED, HAND, FERT, FERT_HIGH }

const TOOL_LABEL := ["锄头", "洒水壶", "种子", "饲料", "手", "基础肥", "高级肥"]
## 肥料工具的按键数（1 起）
const KEY_COUNT := 7
const SPEED := 100.0
const TILE := 32

## 8 方向扇区表：索引 = atan2(dy, dx) / 45° 取整（0 = 右，屏幕 y 轴向下所以顺时针为正）
const DIR8 := ["right", "down_right", "down", "down_left", "left", "up_left", "up", "up_right"]

const FRAMES_PLAIN: SpriteFrames = preload("res://assets/characters/player.tres")
const FRAMES_CAN: SpriteFrames = preload("res://assets/characters/player_can.tres")

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _probe: Area2D = $InteractProbe

## 立绘朝向（LPC 只有 4 向）
var facing := "down"
## 逻辑朝向（8 向）—— 交互点、瞄准都用它
var facing8 := "down"
var current_tool: int = Tool.HOE
var selected_seed: StringName = &"turnip"
## 当前聚焦的可交互物（null = 没有）
var focus: Interactable = null
## 一次性动作（浇水 / 锄地）播放中，期间锁移动
var _busy := false
var _last_prompt := ""

func _ready() -> void:
	# 探针只扫「可交互物」层（layer 2），自己不上任何层
	_probe.collision_layer = 0
	_probe.collision_mask = 2
	_probe.monitoring = true
	_probe.monitorable = false

func _physics_process(_delta: float) -> void:
	# 商店 / 小游戏弹着的时候冻结玩家（模块 4）。
	# 玩家只认 EventBus.ui_modal 这一个开关，不需要知道是谁弹的 UI。
	if EventBus.ui_modal:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if _busy:
		velocity = Vector2.ZERO
		move_and_slide()
		_scan_interactables()
		return
	var dir := _input_dir()
	velocity = dir * SPEED
	move_and_slide()

	if dir != Vector2.ZERO:
		facing8 = dir8_of(dir)
		facing = cardinal_of(facing8)
		_play("walk_" + facing)
	else:
		_idle()
	_scan_interactables()

func _unhandled_input(event: InputEvent) -> void:
	# 模块 9：建造模式下工具键（1-7 / E / 滚轮）要让位给「选建筑 / 放置 / 拆除」。
	# 只挡**输入**，不挡移动 —— 玩家要能走着看位置；这是和 ui_modal 的区别。
	if EventBus.ui_modal or EventBus.build_mode:
		return
	if _busy:
		return
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
			KEY_6:
				_set_tool(Tool.FERT)
			KEY_7:
				_set_tool(Tool.FERT_HIGH)
			KEY_TAB:
				cycle_seed(-1 if event.shift_pressed else 1)
			KEY_E:
				_confirm()
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_confirm()
			MOUSE_BUTTON_WHEEL_UP:
				_cycle_tool(-1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_cycle_tool(1)

## E / 左键：有可交互物就交互它，否则把工具用在面前的格子上
func _confirm() -> void:
	if focus != null and focus.enabled:
		focus.interact(self)
	else:
		tool_used.emit(current_tool, target_cell())

func _set_tool(t: int) -> void:
	current_tool = t
	EventBus.tool_changed.emit(t)

## 滚轮循环换工具（7 → 1 绕回）
func _cycle_tool(step: int) -> void:
	_set_tool(posmod(current_tool + step, TOOL_LABEL.size()))

## 循环切换种子（Tab / Shift+Tab）。
## 顺序 = CropDB 的季节顺序（春 6 → 夏 6 → 秋 6 → 冬 6），所以一按就知道有什么可种。
## 这里**不做季节过滤**：让玩家能看到并选中当季以外的作物，再由 main 拒绝并解释原因，
## 比「列表里悄悄少了几项」更像在教玩家季节规则。
func cycle_seed(step: int) -> void:
	var ids := CropDB.ordered_ids()
	if ids.is_empty():
		return
	var i := ids.find(selected_seed)
	i = 0 if i < 0 else posmod(i + step, ids.size())
	set_seed(ids[i])

func set_seed(id: StringName) -> void:
	if id == selected_seed:
		return
	selected_seed = id
	seed_changed.emit(id)
	EventBus.seed_changed.emit(id)

## 当前种子的展示文本（含季节），给 HUD 用
func seed_label() -> String:
	var c: CropData = CropDB.get_crop(selected_seed)
	if c == null:
		return str(selected_seed)
	return "%s(%s)" % [c.display_name, c.season_name()]

# ---------------- 交互探针 ----------------

## 每物理帧扫一次探针范围，挑离交互点最近的那个
func _scan_interactables() -> void:
	var best: Interactable = null
	var best_d := INF
	var probe := interact_point()
	if _probe != null:
		for a in _probe.get_overlapping_areas():
			if a is Interactable and (a as Interactable).enabled:
				var d: float = a.global_position.distance_to(probe)
				if d < best_d:
					best_d = d
					best = a
	focus = best
	var text := "" if best == null else best.prompt()
	if text != _last_prompt:
		_last_prompt = text
		prompt_changed.emit(text)

# ---------------- 一次性动作 ----------------

## 浇水：洒水壶图集的 watering 行，播完自动回位
func play_watering() -> void:
	_play_once("watering_", FRAMES_CAN)

## 锄地：空手图集的 slash 行当挥锄
func play_hoe() -> void:
	_play_once("slash_", FRAMES_PLAIN)

## 施肥：同样借 slash 行（撒肥的动作），只是工具不同
func play_fertilize() -> void:
	_play_once("slash_", FRAMES_PLAIN)

func _play_once(prefix: String, frames: SpriteFrames) -> void:
	if _busy or frames == null:
		return
	var anim := prefix + facing
	if not frames.has_animation(anim):
		return
	_busy = true
	_sprite.sprite_frames = frames
	_sprite.play(anim)
	if not _sprite.animation_finished.is_connected(_on_action_done):
		_sprite.animation_finished.connect(_on_action_done)

func _on_action_done() -> void:
	_busy = false

# ---------------- 朝向 ----------------

## 把任意输入向量量化到 8 方向名
static func dir8_of(d: Vector2) -> String:
	if d == Vector2.ZERO:
		return "down"
	var idx := posmod(int(round(atan2(d.y, d.x) / (PI / 4.0))), 8)
	return DIR8[idx]

## 8 向 → LPC 立绘的 4 向（取主轴）
static func cardinal_of(d8: String) -> String:
	return d8.split("_")[0]

## 8 向单位向量
func facing_vector8() -> Vector2:
	var v := Vector2.ZERO
	for p in facing8.split("_"):
		match p:
			"up":
				v.y -= 1.0
			"down":
				v.y += 1.0
			"left":
				v.x -= 1.0
			"right":
				v.x += 1.0
	return v.normalized() if v != Vector2.ZERO else Vector2(0, 1)

## 面朝方向单位向量（4 向版，种地/判格用）
func facing_vector() -> Vector2:
	match facing:
		"up":
			return Vector2(0, -1)
		"left":
			return Vector2(-1, 0)
		"right":
			return Vector2(1, 0)
	return Vector2(0, 1)

## 交互点：身前一小段距离（够到动物 / 可交互物）
func interact_point() -> Vector2:
	return position + facing_vector8() * 20.0

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

# ---------------- 动画 ----------------

## 当前工具对应的图集
func active_frames() -> SpriteFrames:
	return FRAMES_CAN if current_tool == Tool.CAN else FRAMES_PLAIN

func _idle() -> void:
	if current_tool == Tool.CAN:
		# 拎着壶站着：thrust 第 0 帧就是「手垂在身侧握着壶」的姿势
		_hold("thrust_" + facing, FRAMES_CAN)
	else:
		_play("idle_" + facing)

## 循环播放
func _play(anim: String) -> void:
	if _busy:
		return
	var sf := active_frames()
	if not sf.has_animation(anim):
		sf = FRAMES_PLAIN
		if not sf.has_animation(anim):
			return
	if _sprite.sprite_frames != sf:
		_sprite.sprite_frames = sf
		_sprite.animation = anim
		_sprite.play()
		return
	if _sprite.animation != anim:
		_sprite.play(anim)
	elif not _sprite.is_playing():
		_sprite.play()

## 定格在第 0 帧
func _hold(anim: String, frames: SpriteFrames) -> void:
	if _busy or not frames.has_animation(anim):
		return
	if _sprite.sprite_frames != frames:
		_sprite.sprite_frames = frames
	_sprite.animation = anim
	_sprite.frame = 0
	_sprite.pause()

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

# ---------------- 存档（模块 8）----------------
# 只存「玩家自己的东西」：位置 / 朝向 / 当前工具 / 当前种子。
# 背包、金币、工具等级都在 GameState，跟玩家节点无关。

func to_dict() -> Dictionary:
	return {
		"x": global_position.x,
		"y": global_position.y,
		"facing": facing,
		"facing8": facing8,
		"tool": current_tool,
		"seed": String(selected_seed),
	}

func from_dict(d: Dictionary) -> void:
	global_position = Vector2(float(d.get("x", 704.0)), float(d.get("y", 288.0)))
	facing = str(d.get("facing", "down"))
	facing8 = str(d.get("facing8", "down"))
	current_tool = clampi(int(d.get("tool", 0)), 0, TOOL_LABEL.size() - 1)
	selected_seed = StringName(str(d.get("seed", "turnip")))
