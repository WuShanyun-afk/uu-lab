extends StaticBody2D
## 秘密花园的碰撞层（模块 5）
##
## ⚠️ 为什么另起一个 StaticBody2D，而不是塞进 WorldCollision：
##    模块 1 的测试断言 WorldCollision 的子节点数 == fence_walls() + bounds_walls()。
##    往那个节点里加 4 面花园墙会把它撑爆。分开挂，两边各自干净。

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	for r in WorldConfig.garden_walls():
		add_wall(r)

func add_wall(r: Rect2) -> CollisionShape2D:
	var shape := RectangleShape2D.new()
	shape.size = r.size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = r.position + r.size * 0.5
	add_child(cs)
	return cs
