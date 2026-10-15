class_name AnimalLayer
extends Node2D
## 动物渲染层：把 herd（Herd 纯逻辑）里的动物实例化成 Animal.tscn
##
## 与 FarmLayer 同构：只读数据，不写数据。

const ANIMAL_SCENE := "res://scenes/animal.tscn"

var herd: Herd

func rebuild() -> void:
	for c in get_children():
		c.queue_free()
	if herd == null:
		return
	var ps: PackedScene = load(ANIMAL_SCENE)
	for a in herd.animals:
		var n: AnimalNode = ps.instantiate()
		add_child(n)
		n.setup(a)

func refresh() -> void:
	for c in get_children():
		if c is AnimalNode:
			c.sync_pos()
			c.queue_redraw()

func node_for(uid: StringName) -> AnimalNode:
	for c in get_children():
		if c is AnimalNode and c.state != null and c.state.uid == uid:
			return c
	return null
