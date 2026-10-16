extends StaticBody2D
## 世界碰撞层 —— 形状全部由 WorldConfig 生成，跟画面用同一份数据。
##
## 两层：
##   1. 地图四边围墙：防止走出场景（相机 limit 之外没东西可看）
##   2. 牧场木栅栏：左边留一个 2 格门洞，玩家从门进去喂牛
##
## ⚠️ 视觉在 main.gd._draw_pen() 里用**同一组矩形**画出来，
##    所以「看着有栅栏」=「真的撞得到」，不会出现看得到却穿过去的情况。

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	for r in WorldConfig.bounds_walls():
		add_wall(r)
	for r in WorldConfig.fence_walls():
		add_wall(r)

## 加一面墙：矩形 → CollisionShape2D（返回出来方便测试断言）
func add_wall(r: Rect2) -> CollisionShape2D:
	var shape := RectangleShape2D.new()
	shape.size = r.size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	cs.position = r.position + r.size * 0.5
	add_child(cs)
	return cs
