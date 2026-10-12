class_name Ambience
extends Node3D
## 环境构建工具库：tiledFloor, pillar, gothicArch, candle, candelabra, fog, motes。

static var _rng := RandomNumberGenerator.new()
static var _stone_colors: Array[Color] = [
	Color(0.27,0.29,0.25), Color(0.33,0.33,0.28), Color(0.25,0.28,0.24),
	Color(0.31,0.32,0.27), Color(0.31,0.32,0.26), Color(0.25,0.29,0.24)
]
static var _warm_mat: Material
static var _candle_mat: Material

static func _warm_material() -> Material:
	if _warm_mat == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.82,0.58,0.24)
		m.emission_enabled = true
		m.emission = Color(0.91,0.55,0.15)
		m.emission_energy_multiplier = 1.5
		m.roughness = 0.92
		m.metallic = 0.04
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_warm_mat = m
	return _warm_mat

static func _candle_material() -> Material:
	if _candle_mat == null:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.84,0.77,0.58)
		m.roughness = 0.92
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_candle_mat = m
	return _candle_mat

static func tiled_floor(parent: Node3D, size: int, y: float = 0.0, seed: int = 741) -> void:
	_rng.seed = seed
	var base := BoxMesh.new()
	base.size = Vector3(size + 1.0, 0.55, size + 1.0)
	var base_mi := MeshInstance3D.new()
	base_mi.mesh = base
	base_mi.material_override = GeoBuilder.mat(Color(0.13,0.17,0.14))
	base_mi.position = Vector3(0, y - 0.38, 0)
	parent.add_child(base_mi)
	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(0.96, 0.13, 0.96)
	for x in range(size):
		for z in range(size):
			var mi := MeshInstance3D.new()
			mi.mesh = tile_mesh
			var col := _stone_colors[_rng.randi_range(0, _stone_colors.size()-1)]
			col *= 0.75 + _rng.randf() * 0.3
			mi.material_override = GeoBuilder.mat(col)
			mi.position = Vector3(
				x - (size - 1.0) / 2.0,
				y - _rng.randf() * 0.026,
				z - (size - 1.0) / 2.0
			)
			mi.rotation.y = (_rng.randf() - 0.5) * 0.025
			mi.scale = Vector3(0.96 + _rng.randf()*0.04, 1.0, 0.96 + _rng.randf()*0.04)
			parent.add_child(mi)

static func pillar(parent: Node3D, x: float, z: float, height: float = 5.3, broken: bool = false) -> Node3D:
	_rng.seed = int(x * 100 + z * 37 + int(height))
	var p := Node3D.new()
	p.position = Vector3(x, 0, z)
	parent.add_child(p)
	GeoBuilder.box(p, 1.03, 0.25, 1.03, Color(0.33,0.34,0.28), Vector3(0,0.1,0))
	GeoBuilder.box(p, 0.82, 0.24, 0.82, Color(0.25,0.27,0.22), Vector3(0,0.34,0))
	var n := 6
	for i in range(n):
		var piece := GeoBuilder.cylinder(p, 0.31, 0.34, (height - 0.65) / n - 0.025, _stone_colors[i], Vector3(0, 0.63 + i * ((height - 0.65) / n), 0), 6)
		if broken and i == 5:
			piece.rotation.z = 0.1
			piece.position.x = 0.08
	for dx in [-0.25, 0.25]:
		for dz in [-0.25, 0.25]:
			GeoBuilder.box(p, 0.11, height - 0.45, 0.11, Color(0.33,0.34,0.27), Vector3(dx, height/2, dz))
	if not broken:
		GeoBuilder.box(p, 0.8, 0.18, 0.8, Color(0.40,0.39,0.31), Vector3(0,height,0))
		GeoBuilder.box(p, 1.04, 0.2, 1.04, Color(0.25,0.29,0.24), Vector3(0,height+0.18,0))
	return p

static func gothic_arch(parent: Node3D, width: float = 4.2, height: float = 6.0, depth: float = 0.5, col: Color = Color(0.31,0.32,0.27)) -> Node3D:
	var a := Node3D.new()
	parent.add_child(a)
	var spring := height * 0.53
	for side in [-1, 1]:
		GeoBuilder.box(a, 0.45, spring, depth, col, Vector3(side * width / 2, spring / 2, 0))
		GeoBuilder.box(a, 0.7, 0.24, depth + 0.2, Color(0.41,0.38,0.29), Vector3(side * width / 2, 0.12, 0))
		GeoBuilder.box(a, 0.58, 0.22, depth + 0.12, Color(0.40,0.38,0.29), Vector3(side * width / 2, spring, 0))
		var p0 := Vector3(side * width / 2, spring, 0)
		var p1 := Vector3(side * width / 2, height * 0.83, 0)
		var p2 := Vector3(0, height, 0)
		# Draw along the curve with simple segments.
		var steps := 10
		for i in range(steps):
			var t0 := float(i) / steps
			var t1 := float(i + 1) / steps
			var q0 := p0.lerp(p1, t0).lerp(p1.lerp(p2, t0), t0)
			var q1 := p0.lerp(p1, t1).lerp(p1.lerp(p2, t1), t1)
			GeoBuilder.beam(a, q0, q1, 0.43, depth, col if i % 3 != 0 else Color(0.41,0.38,0.30))
		# Thin ribs.
		for i in range(steps):
			var t0 := float(i) / steps
			var t1 := float(i + 1) / steps
			var q0 := p0.lerp(p1, t0).lerp(p1.lerp(p2, t0), t0)
			var q1 := p0.lerp(p1, t1).lerp(p1.lerp(p2, t1), t1)
			q0.x *= 0.91; q1.x *= 0.91
			q0.z += depth / 2 + 0.035; q1.z += depth / 2 + 0.035
			GeoBuilder.beam(a, q0, q1, 0.045, 0.06, Color(0.54,0.50,0.39))
	return a

static func candle(parent: Node3D, x: float, y: float, z: float, scale: float = 1.0) -> void:
	var c := Node3D.new()
	c.position = Vector3(x, y, z)
	c.scale = Vector3.ONE * scale
	parent.add_child(c)
	GeoBuilder.cylinder(c, 0.08, 0.075, 0.36, _candle_material(), Vector3(0, 0.18, 0))
	GeoBuilder.box(c, 0.015, 0.065, 0.015, Color(0.20,0.16,0.14), Vector3(0,0.38,0))
	var flame := GeoBuilder.octahedron(c, 0.1, _warm_material(), Vector3(0,0.46,0), false)
	flame.scale = Vector3(0.65, 1.8, 0.65)

static func candelabra(parent: Node3D, x: float, z: float, height: float = 1.6, light: bool = true) -> void:
	var c := Node3D.new()
	c.position = Vector3(x, 0, z)
	parent.add_child(c)
	GeoBuilder.cylinder(c, 0.22, 0.4, 0.2, Color(0.14,0.17,0.15), Vector3(0,0.12,0))
	GeoBuilder.cylinder(c, 0.065, 0.11, height, Color(0.22,0.23,0.18), Vector3(0,height/2,0))
	GeoBuilder.cylinder(c, 0.16, 0.13, 0.15, Color(0.44,0.38,0.27), Vector3(0,height*0.7,0))
	for side in [-1, 1]:
		GeoBuilder.beam(c, Vector3(0,height-0.3,0), Vector3(side*0.45,height-0.13,0), 0.045, 0.045, Color(0.31,0.29,0.20))
		GeoBuilder.beam(c, Vector3(side*0.45,height-0.13,0), Vector3(side*0.45,height+0.08,0), 0.045, 0.045, Color(0.31,0.29,0.20))
		GeoBuilder.cylinder(c, 0.14, 0.11, 0.045, Color(0.53,0.45,0.30), Vector3(side*0.45,height+0.1,0))
		candle(c, side*0.45, height+0.11, 0, 0.83)
	GeoBuilder.cylinder(c, 0.16, 0.12, 0.045, Color(0.53,0.45,0.30), Vector3(0,height+0.05,0))
	candle(c, 0, height+0.07, 0, 1.13)
	if light:
		var pl := OmniLight3D.new()
		pl.position = Vector3(0, height + 0.5, 0)
		pl.light_color = Color(1.0, 0.74, 0.41)
		pl.light_energy = 12.0
		pl.omni_range = 7.0
		c.add_child(pl)

static func make_motes(parent: Node3D, count: int, radius: float, col: Color) -> GPUParticles3D:
	var gp := GPUParticles3D.new()
	gp.amount = count
	gp.lifetime = 7.0
	gp.preprocess = 7.0
	gp.emitting = true
	gp.draw_pass_1 = BoxMesh.new()
	gp.draw_pass_1.size = Vector3(0.027, 0.027, 0.027)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.65
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	gp.draw_pass_1.material = mat
	var p := ParticleProcessMaterial.new()
	p.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.gravity = Vector3(0, 0.065, 0)
	p.turbulence_noise_strength = 0.3
	p.color = col
	gp.process_material = p
	parent.add_child(gp)
	return gp
