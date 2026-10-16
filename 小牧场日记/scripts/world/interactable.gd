class_name Interactable
extends Area2D
## 可交互物基类（GDD §10.4 交互系统）
##
## 怎么加一个新的可交互物（**不用改 player.gd / main.gd 一行**）：
##   1. 新脚本 `extends Interactable`，覆盖 prompt() 和 interact()
##   2. 场景里挂一个 CollisionShape2D 当触发范围
##   3. 完事。玩家的 InteractProbe 会自动扫到它
##
## 约定：
##   碰撞层固定 layer 2（玩家探针 mask = 2），自己不用扫别人（monitoring = false）
##   interact(player) 里可以读背包、发 EventBus 信号、播动画，但**不要**直接改 UI

## 靠近时显示的固定文字（子类可以无视它，直接覆盖 prompt()）
@export var prompt_text: String = "查看"
## 关掉后探针会忽略它（例如打烊的商店）
@export var enabled: bool = true

func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	monitoring = false      # 只负责「被扫到」
	monitorable = true
	add_to_group("interactable")

## 提示文字，每帧被玩家探针读一次 —— 要显示数量之类的动态内容就覆盖它
func prompt() -> String:
	return prompt_text

## 按 E（或左键）触发。player 传进来是为了能读朝向 / 播动作
func interact(_player: Node) -> void:
	pass
