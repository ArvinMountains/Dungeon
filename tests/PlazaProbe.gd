extends SceneTree
## 排查广场周围的白色柱状物：列出 TownWorld 原点 14m 内的节点。
## 运行：godot --headless --path . --script res://tests/PlazaProbe.gd

func _init() -> void:
	var ps = load("res://scripts/TownWorld.gd")
	var tw = ps.new()
	root.add_child(tw)
	await process_frame
	await process_frame
	_walk(tw)
	quit(0)

func _walk(tw: Node) -> void:
	var stack: Array = [[tw, ""]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var n: Node = e[0]
		var path: String = e[1]
		for c in n.get_children():
			var p := path + "/" + c.name
			if c is Node3D:
				var n3 := c as Node3D
				var gxz := Vector2(n3.global_position.x, n3.global_position.z)
				if gxz.length() < 14.0 and n3.global_position.y < 20.0:
					print("%-60s pos=(%.1f, %.1f, %.1f) scale=%.2f" % [p, n3.global_position.x, n3.global_position.y, n3.global_position.z, n3.scale.x])
			stack.push_back([c, p])
