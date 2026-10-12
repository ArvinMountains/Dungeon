extends SceneTree
## 一次性材质探针：检查 GLB 实例的 MeshInstance3D 材质（albedo 颜色/贴图/顶点色）。
## 运行：godot --headless --path . --script res://tests/MatProbe.gd

func _init() -> void:
	for rel in ["town/lantern.glb", "town/wall-wood.glb", "town/fountain-round.glb", "enemies/Skeleton_Minion.glb", "characters/Knight.glb", "dungeon/kay/column.gltf.glb"]:
		var ps = load("res://assets/models/" + rel)
		if ps == null:
			print("%-36s LOAD FAIL" % rel)
			continue
		var inst = ps.instantiate()
		var meshes = inst.find_children("*", "MeshInstance3D", true, false)
		print("%-36s meshes=%d" % [rel, meshes.size()])
		var shown = 0
		for m in meshes:
			if shown >= 2: break
			var mi = m as MeshInstance3D
			for si in mi.mesh.get_surface_count():
				var mat = mi.mesh.surface_get_material(si)
				if mat is StandardMaterial3D:
					var sm = mat as StandardMaterial3D
					print("    [%s] surf%d albedo=%s tex=%s vcol=%s" % [mi.name, si, sm.albedo_color, "YES" if sm.albedo_texture != null else "NO", sm.vertex_color_use_as_albedo])
				elif mat != null:
					print("    [%s] surf%d mat_type=%s" % [mi.name, si, mat.get_class()])
				else:
					print("    [%s] surf%d NO MATERIAL" % [mi.name, si])
			shown += 1
		inst.free()
	print("MAT PROBE DONE")
	quit(0)
