extends SceneTree
## 一次性尺寸抽查：打印关键 GLB 的静态 AABB，校验 spawn_norm/spawn_wide 归一化比例。
## 运行：godot --headless --path . --script res://tests/SizeProbe.gd

func _init() -> void:
	var targets := [
		# 城镇墙件（段长 3m 归一化用）。
		"town/wall-wood.glb",
		"town/wall-wood-door.glb",
		"town/wall-wood-window-glass.glb",
		"town/wall-wood-window-shutters.glb",
		"town/roof-gable.glb",
		"town/roof-gable-end.glb",
		"town/chimney.glb",
		"town/pillar-stone.glb",
		"town/lantern.glb",
		"town/fountain-round.glb",
		"town/windmill.glb",
		"town/banner-green.glb",
		"town/stall.glb",
		"town/fence.glb",
		"town/tree-high-round.glb",
		"town/hedge.glb",
		# 敌人/NPC/宠物。
		"enemies/Skeleton_Minion.glb",
		"enemies/Skeleton_Warrior.glb",
		"enemies/Skeleton_Rogue.glb",
		"enemies/Skeleton_Mage.glb",
		"characters/Knight.glb",
		"characters/Mage.glb",
		"characters/Rogue.glb",
		"characters/Rogue_Hooded.glb",
		"characters/Barbarian.glb",
		"pets/animal-bunny.glb",
		"pets/animal-deer.glb",
		"pets/animal-dog.glb",
		"pets/animal-hog.glb",
		"pets/animal-pig.glb",
		# 地下城/野外。
		"dungeon/kay/column.gltf.glb",
		"dungeon/kay/torch_lit.gltf.glb",
		"dungeon/kay/chest_gold.glb",
		"dungeon/kay/chest.glb",
		"dungeon/kay/table_medium.gltf.glb",
		"dungeon/graveyard/altar-stone.glb",
		"nature/tree_oak.glb",
		"nature/tree_pineTallA.glb",
		"nature/rock_largeA.glb",
		"nature/campfire_logs.glb",
		"nature/grass.glb",
	]
	for rel in targets:
		var sz := AssetLib.size_of(rel)
		print("%-42s size=(%.2f, %.2f, %.2f)  bottom_y=%.2f" % [rel, sz.x, sz.y, sz.z, 0.0])
	print("SIZE PROBE DONE")
	quit(0)
