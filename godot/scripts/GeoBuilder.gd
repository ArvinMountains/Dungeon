class_name GeoBuilder
extends RefCounted
## 程序化几何构建工具：box/cylinder/mesh/beam，对应 main.js 的辅助函数。

static var _mat_cache: Dictionary = {}
static var _box_cache: Dictionary = {}

static func mat(color: Color, options: Dictionary = {}) -> StandardMaterial3D:
	var key := str(color) + "|" + str(options.hash())
	if _mat_cache.has(key): return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = options.get("roughness", 0.92)
	m.metallic = options.get("metalness", 0.04)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if options.get("unshaded", false) else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if options.has("emissive"):
		m.emission_enabled = true
		m.emission = options["emissive"]
		m.emission_energy_multiplier = options.get("emissive_intensity", 1.0)
	if options.get("transparent", false):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = options.get("opacity", 1.0)
		if options.get("depth_write", true) == false:
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.no_depth_test = false
	if options.get("double_sided", false):
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_cache[key] = m
	return m

static func box_geometry(w: float, h: float, d: float) -> BoxMesh:
	var key := "b%0.4f,%0.4f,%0.4f" % [w, h, d]
	if _box_cache.has(key): return _box_cache[key]
	var b := BoxMesh.new()
	b.size = Vector3(w, h, d)
	_box_cache[key] = b
	return b

static func mesh_instance(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3 = Vector3.ZERO, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func box(parent: Node3D, w: float, h: float, d: float, color, pos: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m: Material = mat(color) if color is Color or color is int else color
	return mesh_instance(parent, box_geometry(w, h, d), m, pos)

static func cylinder(parent: Node3D, rt: float, rb: float, h: float, color, pos: Vector3 = Vector3.ZERO, n: int = 8) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = n
	var m: Material = mat(color) if color is Color or color is int else color
	return mesh_instance(parent, c, m, pos)

static func beam(parent: Node3D, from: Vector3, to: Vector3, width: float, depth: float, color) -> MeshInstance3D:
	var length := from.distance_to(to)
	var m := box(parent, width, length, depth, color)
	m.position = (from + to) * 0.5
	var dir := (to - from).normalized()
	var up := Vector3.UP
	if abs(dir.dot(up)) > 0.999:
		up = Vector3.RIGHT
	var basis := Basis.looking_at(dir, up)
	# Box local +Y should align with dir. looking_at points -Z at dir; rotate.
	m.basis = Basis.from_euler(Vector3(0, 0, 0))
	var q := Quaternion(Vector3.UP, dir)
	m.quaternion = q
	return m

static func octahedron(parent: Node3D, radius: float, color, pos: Vector3 = Vector3.ZERO, shadows: bool = false) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 4
	s.rings = 2
	var m: Material = mat(color) if color is Color or color is int else color
	return mesh_instance(parent, s, m, pos, shadows)

static func ring(parent: Node3D, inner: float, outer: float, color, pos: Vector3 = Vector3.ZERO, segments: int = 48) -> MeshInstance3D:
	# XZ 平面平环（地面标记/装饰线）。双面三角形，免担心剔除方向。
	var m: Material = mat(color) if color is Color or color is int else color
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var i0 := Vector3(cos(a0) * inner, 0, sin(a0) * inner)
		var i1 := Vector3(cos(a1) * inner, 0, sin(a1) * inner)
		var o0 := Vector3(cos(a0) * outer, 0, sin(a0) * outer)
		var o1 := Vector3(cos(a1) * outer, 0, sin(a1) * outer)
		st.add_vertex(o0); st.add_vertex(o1); st.add_vertex(i1)
		st.add_vertex(o0); st.add_vertex(i1); st.add_vertex(i0)
		st.add_vertex(i1); st.add_vertex(o1); st.add_vertex(o0)
		st.add_vertex(i0); st.add_vertex(i1); st.add_vertex(o0)
	var mesh := st.commit()
	return mesh_instance(parent, mesh, m, pos, false)
