class_name ProceduralCharacter
extends Node3D
## 程序化角色：弓箭手/战士。对应 main.js createProceduralCharacter。
## 脚底原点 (0,0,0)，面朝 +Z，高度约 2.7 单位。
## 通过 set_pose(pose) 驱动 idle/walk/showcase/attack/ultimate 动画。

var class_id := "archer"
var is_warrior := false

# Rig nodes (posed every frame).
var rig: Node3D
var torso: Node3D
var head: Node3D
var arm_l_upper: Node3D
var arm_l_lower: Node3D
var arm_l_hand: Node3D
var arm_r_upper: Node3D
var arm_r_lower: Node3D
var arm_r_hand: Node3D
var leg_l_thigh: Node3D
var leg_l_knee: Node3D
var leg_r_thigh: Node3D
var leg_r_knee: Node3D
var weapon: Node3D
var bow_string: Line3D
var arrow_mesh: MeshInstance3D

# Rest pose snapshot.
var _rest: Array = []  # [node, position, rotation]
var _own_mats: Array[Material] = []

var _rng := RandomNumberGenerator.new()

func _init(id: String = "archer", seed: int = 741) -> void:
	class_id = id
	is_warrior = id == "warrior"
	_rng.seed = seed

func _rand() -> float: return _rng.randf()

func _ready() -> void:
	_build()
	_snapshot_rest()

func _group(parent: Node3D, pos: Vector3 = Vector3.ZERO) -> Node3D:
	var g := Node3D.new()
	g.position = pos
	parent.add_child(g)
	return g

func _build() -> void:
	var GB := GeoBuilder
	rig = _group(self)
	torso = _group(rig, Vector3(0, 1.35, 0))
	var palette: Dictionary
	if is_warrior:
		palette = {"cloth": Color(0.34,0.24,0.19), "cloth2": Color(0.24,0.19,0.16), "armor": Color(0.36,0.38,0.35), "edge": Color(0.61,0.53,0.36), "skin": Color(0.71,0.61,0.47), "hair": Color(0.41,0.29,0.21), "leather": Color(0.22,0.18,0.15)}
	else:
		palette = {"cloth": Color(0.20,0.30,0.24), "cloth2": Color(0.14,0.22,0.17), "armor": Color(0.33,0.34,0.27), "edge": Color(0.71,0.62,0.42), "skin": Color(0.77,0.73,0.63), "hair": Color(0.78,0.78,0.72), "leather": Color(0.28,0.24,0.17)}
	var bw: float = 0.76 if is_warrior else 0.54
	var body := GB.cylinder(torso, bw*0.68, bw*0.56, 0.72, palette.cloth, Vector3(0,0.19,0), 6)
	body.rotation.y = PI/6
	GB.box(torso, bw, 0.46, 0.39, palette.armor, Vector3(0,0.34,0.02))
	GB.box(torso, bw*0.66, 0.13, 0.065, palette.edge, Vector3(0,0.47,0.228))
	GB.box(torso, bw+0.02, 0.11, 0.45, palette.leather, Vector3(0,-0.06,0.025))
	GB.box(torso, 0.13, 0.13, 0.055, palette.edge, Vector3(0,-0.06,0.269))
	for x in [-1,1]:
		GB.box(torso, 0.09, 0.11, 0.08, palette.edge, Vector3(x*bw*0.32, 0.42, 0.235))
	if is_warrior:
		GB.box(torso, 0.56, 0.67, 0.09, palette.leather, Vector3(0,-0.28,0.24))
		GB.box(torso, 0.46, 0.045, 0.095, palette.edge, Vector3(0,-0.54,0.25))
		GB.beam(torso, Vector3(-0.24,0.65,0.27), Vector3(0.24,-0.03,0.27), 0.09, 0.05, palette.leather)
		for i in range(4):
			GB.box(torso, 0.04, 0.05, 0.045, palette.edge, Vector3(-0.19+i*0.12, -0.46, 0.302))
	else:
		GB.beam(torso, Vector3(-0.25,0.61,0.25), Vector3(0.23,-0.12,0.25), 0.09, 0.035, palette.leather)
		var cape_mesh := CylinderMesh.new()
		cape_mesh.top_radius = 0.35; cape_mesh.bottom_radius = 0.67; cape_mesh.height = 1.42
		cape_mesh.radial_segments = 5
		var cape := MeshInstance3D.new()
		cape.mesh = cape_mesh
		var cape_mat := GB.mat(palette.cloth2, {"double_sided": true})
		cape.material_override = cape_mat
		cape.position = Vector3(0,-0.07,-0.12)
		cape.rotation.x = -0.12
		torso.add_child(cape)
		var trim := GB.box(torso, 0.07, 1.13, 0.06, palette.edge, Vector3(-0.35,-0.2,-0.25))
		trim.rotation.z = -0.13
		var quiver := GB.cylinder(torso, 0.12, 0.1, 0.77, palette.leather, Vector3(0.3,0.25,-0.35), 6)
		quiver.rotation.z = -0.19
		for i in range(5):
			var arrow := _group(torso, Vector3(0.23+i*0.04, 0.47+(i%2)*0.04, -0.35))
			GB.box(arrow, 0.016, 0.68, 0.016, palette.edge)
			GB.box(arrow, 0.075, 0.12, 0.015, palette.hair, Vector3(0,0.3,0))
			arrow.rotation.z = -0.19
	# Head.
	head = _group(torso, Vector3(0, 0.88, 0.015))
	GB.cylinder(head, 0.12, 0.14, 0.18, palette.skin, Vector3(0,-0.31,0))
	GB.box(head, 0.44, 0.48, 0.41, palette.skin, Vector3(0,-0.025,0.02))
	GB.box(head, 0.075, 0.105, 0.11, palette.skin, Vector3(0,-0.04,0.265))
	for side in [-1,1]:
		GB.box(head, 0.1, 0.041, 0.021, Color(0.15,0.22,0.18), Vector3(side*0.115, 0.035, 0.239))
		GB.box(head, 0.04, 0.028, 0.025, Color(0.71,0.71,0.55) if is_warrior else Color(0.79,0.85,0.73), Vector3(side*0.11, 0.033, 0.25))
		var brow := GB.box(head, 0.12, 0.035, 0.035, palette.hair, Vector3(side*0.112, 0.096, 0.236))
		brow.rotation.z = side * 0.1
	if is_warrior:
		GB.box(head, 0.49, 0.16, 0.46, palette.hair, Vector3(0,0.24,0.01))
		GB.box(head, 0.47, 0.12, 0.08, Color(0.55,0.47,0.31), Vector3(0,0.16,0.245))
		GB.box(head, 0.41, 0.25, 0.12, palette.hair, Vector3(0,-0.23,0.22))
		GB.box(head, 0.27, 0.15, 0.11, palette.hair, Vector3(0,-0.39,0.2))
		for s in [-1,1]:
			GB.box(head, 0.085, 0.2, 0.08, Color(0.53,0.38,0.28), Vector3(s*0.13,-0.28,0.285))
		GB.box(head, 0.08, 0.07, 0.13, palette.edge, Vector3(0,-0.41,0.23))
	else:
		GB.box(head, 0.49, 0.15, 0.46, palette.hair, Vector3(0,0.24,0))
		for side in [-1,1]:
			var hair_side := GB.box(head, 0.105, 0.56, 0.32, palette.hair, Vector3(side*0.247, -0.09, -0.05))
			hair_side.rotation.z = side * 0.06
			var ear_mesh := SphereMesh.new()
			ear_mesh.radius = 0.09; ear_mesh.height = 0.31; ear_mesh.radial_segments = 3; ear_mesh.rings = 1
			var ear := MeshInstance3D.new()
			ear.mesh = ear_mesh
			ear.material_override = GB.mat(palette.skin)
			ear.position = Vector3(side*0.326, 0.03, 0.02)
			ear.rotation.z = side * -1.05
			head.add_child(ear)
			GB.box(head, 0.07, 0.1, 0.04, palette.edge, Vector3(side*0.35, -0.03, 0.09))
		var hood := GB.cylinder(head, 0.21, 0.37, 0.38, palette.cloth, Vector3(0,0.3,-0.095), 5)
		hood.rotation.y = PI/5
		GB.box(head, 0.12, 0.06, 0.035, palette.edge, Vector3(0,0.23,0.27))
	# Arms and legs.
	for side_name in ["left", "right"]:
		var side: float = -1.0 if side_name == "left" else 1.0
		var upper := _group(torso, Vector3(side*(bw/2+0.075), 0.48, 0))
		var uw: float = 0.25 if is_warrior else 0.18
		GB.box(upper, uw, 0.44, 0.24, palette.cloth, Vector3(side*0.015, -0.2, 0))
		var shoulder := GB.cylinder(upper, 0.27 if is_warrior else 0.19, 0.23 if is_warrior else 0.16, 0.22, palette.armor, Vector3(side*0.015, -0.005, 0), 5)
		shoulder.rotation.z = side * 0.12
		GB.box(upper, 0.36 if is_warrior else 0.24, 0.06, 0.29, palette.edge, Vector3(side*0.025, 0.12, 0))
		var lower := _group(upper, Vector3(0, -0.43, 0))
		GB.box(lower, uw*0.92, 0.33, 0.23, palette.leather, Vector3(0,-0.16,0))
		GB.box(lower, uw+0.04, 0.23, 0.26, palette.armor if is_warrior else palette.cloth, Vector3(0,-0.1,0))
		GB.box(lower, uw+0.05, 0.045, 0.27, palette.edge, Vector3(0,-0.235,0))
		GB.box(lower, uw*0.86, 0.15, 0.19, palette.skin, Vector3(0,-0.37,0))
		var hand := _group(lower, Vector3(0, -0.41, 0.025))
		if side_name == "left":
			arm_l_upper = upper; arm_l_lower = lower; arm_l_hand = hand
		else:
			arm_r_upper = upper; arm_r_lower = lower; arm_r_hand = hand
		var thigh := _group(rig, Vector3(side*(0.225 if is_warrior else 0.17), 1.2, 0))
		GB.box(thigh, 0.28 if is_warrior else 0.21, 0.53, 0.28, palette.cloth2, Vector3(0,-0.22,0))
		var knee := _group(thigh, Vector3(0, -0.49, 0))
		GB.box(knee, 0.285 if is_warrior else 0.22, 0.51, 0.28, palette.leather, Vector3(0,-0.23,0))
		GB.box(knee, 0.31 if is_warrior else 0.23, 0.23, 0.3, palette.armor, Vector3(0,-0.02,0.02))
		GB.box(knee, 0.32 if is_warrior else 0.245, 0.22, 0.43, palette.leather, Vector3(0,-0.5,0.07))
		GB.box(knee, 0.33 if is_warrior else 0.25, 0.07, 0.44, Color(0.14,0.16,0.12), Vector3(0,-0.61,0.065))
		if side_name == "left":
			leg_l_thigh = thigh; leg_l_knee = knee
		else:
			leg_r_thigh = thigh; leg_r_knee = knee
	# Weapon.
	weapon = _group(arm_r_hand if is_warrior else arm_l_hand)
	if is_warrior:
		GB.box(weapon, 0.075, 1.25, 0.075, palette.leather, Vector3(0,0.55,0.05))
		for i in range(6):
			GB.box(weapon, 0.09, 0.026, 0.09, palette.edge, Vector3(0, i*0.075+0.18, 0.05))
		var hammer_head := _group(weapon, Vector3(0, 1.18, 0.05))
		GB.box(hammer_head, 0.52, 0.34, 0.34, Color(0.35,0.39,0.35))
		for side in [-1,1]:
			GB.box(hammer_head, 0.1, 0.38, 0.38, Color(0.61,0.54,0.37), Vector3(side*0.28, 0, 0))
		GB.box(hammer_head, 0.17, 0.18, 0.02, palette.edge, Vector3(0,0,0.2))
		weapon.position = Vector3(0.04, -0.02, 0.05)
		weapon.rotation = Vector3(0.05, 0, -0.15)
	else:
		var points := [Vector3(0,-0.82,0), Vector3(-0.2,-0.62,0), Vector3(-0.34,-0.33,0), Vector3(-0.38,0,0), Vector3(-0.34,0.33,0), Vector3(-0.2,0.62,0), Vector3(0,0.82,0)]
		for i in range(points.size()-1):
			GB.beam(weapon, points[i], points[i+1], 0.072, 0.068, palette.edge)
		GB.box(weapon, 0.085, 0.26, 0.085, palette.leather, Vector3(-0.36, 0, 0))
		bow_string = Line3D.new()
		weapon.add_child(bow_string)
		bow_string.set_points([Vector3(0,-0.82,0), Vector3(0,0,0), Vector3(0,0.82,0)])
		bow_string.color = Color(0.84,0.82,0.69)
		weapon.position = Vector3(0.03, -0.02, 0.06)
		weapon.rotation = Vector3(0.05, 0, 0.18)
		arrow_mesh = GB.box(weapon, 1.35, 0.024, 0.024, palette.edge, Vector3(-0.66, 0, 0.025))
		arrow_mesh.visible = false
	# Clone materials for independent dissolve.
	_own_mats.clear()
	for child in find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.material_override:
			mi.material_override = mi.material_override.duplicate()
			if mi.material_override is StandardMaterial3D:
				(mi.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_own_mats.append(mi.material_override)

func _snapshot_rest() -> void:
	_rest.clear()
	for obj in [torso, head, arm_l_upper, arm_l_lower, arm_r_upper, arm_r_lower, leg_l_thigh, leg_r_thigh, leg_l_knee, leg_r_knee, weapon]:
		_rest.append([obj, obj.position, obj.rotation])

func _restore_rest() -> void:
	for r in _rest:
		r[0].position = r[1]
		r[0].rotation = r[2]

func set_opacity(v: float) -> void:
	for m in _own_mats:
		if m is StandardMaterial3D:
			m.albedo_color.a = v
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY if v > 0.7 else BaseMaterial3D.DEPTH_DRAW_DISABLED
	visible = v > 0.005

func _smooth(x: float) -> float:
	x = clamp(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

func _lerp(a: float, b: float, t: float) -> float:
	return a + (b - a) * t

## pose: {"type": "idle"} | {"type":"walk","step":float} | {"type":"showcase","time":float} | {"type":"attack","time":float} | {"type":"ultimate","time":float}
func animate_pose(dt: float, elapsed: float, pose: Dictionary) -> void:
	_restore_rest()
	var t := elapsed
	torso.position.y += sin(t * 1.7) * 0.022
	torso.rotation.z = sin(t * 0.9) * 0.012
	arm_l_upper.rotation.z = 0.12
	arm_r_upper.rotation.z = -0.12
	arm_l_lower.rotation.x = -0.12
	arm_r_lower.rotation.x = -0.12
	head.rotation.y = sin(t * 0.6) * 0.035
	var ptype: String = pose.get("type", "idle")
	if ptype == "walk":
		var s: float = sin(pose.get("step", 0.0))
		var c: float = cos(pose.get("step", 0.0))
		leg_l_thigh.rotation.x = s * 0.55
		leg_r_thigh.rotation.x = -s * 0.55
		leg_l_knee.rotation.x = max(0.0, -c) * 0.45
		leg_r_knee.rotation.x = max(0.0, c) * 0.45
		arm_l_upper.rotation.x = -s * 0.32
		arm_r_upper.rotation.x = s * 0.32
		torso.position.y += abs(s) * 0.038
		torso.rotation.x = 0.06
	elif ptype == "showcase":
		var p: float = pose.get("time", 0.0)
		if not is_warrior:
			var lift: float = _smooth(p / 1.0) * (1.0 - _smooth((p - 3.35) / 0.9))
			var draw: float = _smooth((p - 0.8) / 0.9) * (1.0 - _smooth((p - 2.85) / 0.22))
			torso.rotation.y = -0.4 * lift
			head.rotation.y = -0.45 * lift
			arm_l_upper.rotation.z = 0.12 - 1.57 * lift
			arm_l_lower.rotation.z = -0.08 * lift
			arm_l_lower.rotation.x = -0.12 * (1.0 - lift)
			arm_r_upper.rotation.z = -0.75 * lift
			arm_r_lower.rotation.z = -1.72 * draw
			arm_r_lower.rotation.x = -0.12 * (1.0 - lift)
			weapon.rotation.z = 0.18 + 1.53 * lift
			weapon.rotation.y = (1.0 - lift) * 0.12
			weapon.position.x = _lerp(0.03, -0.05, lift)
			weapon.position.y = _lerp(-0.02, 0.28, lift)
			if bow_string: bow_string.set_middle_x(draw * 0.56)
			arrow_mesh.visible = p > 0.9 and p < 2.98
			arrow_mesh.position.x = -0.66 + draw * 0.56
			leg_r_thigh.rotation.z = -0.08 * lift
		else:
			var plant: float = _smooth(p / 0.85) * (1.0 - _smooth((p - 3.55) / 0.8))
			var salute: float = _smooth((p - 1.8) / 0.38) * (1.0 - _smooth((p - 3.1) / 0.4))
			weapon.rotation.z = -0.15 + (PI - 0.2) * plant
			weapon.position.y += 0.3 * plant
			arm_r_upper.rotation.z = 0.35 * plant
			arm_r_upper.rotation.x = -0.05 * plant
			arm_r_lower.rotation.x = -0.12 * (1.0 - plant)
			arm_l_upper.rotation.z = _lerp(-0.75, -0.45, salute) * plant
			arm_l_lower.rotation.z = _lerp(1.5, 2.7, salute) * plant
			arm_l_upper.rotation.x = -0.1 * salute
			arm_l_lower.rotation.x = -0.48 * salute
			var impact: float = max(0.0, 1.0 - abs(p - 2.36) * 10.0)
			torso.rotation.x = -0.045 * plant + 0.08 * impact
			torso.position.y -= 0.055 * plant
			head.rotation.x = -0.1 * salute
			leg_l_thigh.rotation.z = 0.07 * plant
			leg_r_thigh.rotation.z = -0.07 * plant
	elif ptype == "attack":
		var p: float = pose.get("time", 0.0)
		if not is_warrior:
			var draw: float = _smooth(p / 0.3) * (1.0 - _smooth((p - 0.45) / 0.15))
			var recoil: float = _smooth((p - 0.5) / 0.12) * (1.0 - _smooth((p - 0.7) / 0.3))
			torso.rotation.y = -0.28 * draw
			head.rotation.y = -0.32 * draw
			arm_l_upper.rotation.z = 0.12 - 1.4 * draw
			arm_l_lower.rotation.z = -0.06 * draw
			arm_l_lower.rotation.x = -0.12 * (1.0 - draw)
			arm_r_upper.rotation.z = -0.7 * draw
			arm_r_lower.rotation.z = -1.7 * draw
			weapon.rotation.z = 0.18 + 1.4 * draw
			weapon.position.x = _lerp(0.03, -0.06, draw)
			weapon.position.y = _lerp(-0.02, 0.24, draw)
			if bow_string: bow_string.set_middle_x(draw * 0.56)
			if arrow_mesh:
				arrow_mesh.visible = draw > 0.05 and p < 0.52
				arrow_mesh.position.x = -0.66 + draw * 0.56
			torso.rotation.x = 0.08 * recoil
		else:
			var wind: float = _smooth(p / 0.3)
			var swing: float = _smooth((p - 0.3) / 0.25) * (1.0 - _smooth((p - 0.55) / 0.15))
			var impact: float = max(0.0, 1.0 - abs(p - 0.58) * 14.0)
			arm_r_upper.rotation.x = -1.4 * wind
			arm_r_upper.rotation.z = -0.15 - 0.6 * wind
			arm_r_lower.rotation.x = -0.4 - 0.5 * wind
			weapon.rotation.z = -0.15 - 1.7 * wind + 3.0 * swing
			weapon.position.y += 0.05 * wind - 0.18 * swing
			arm_l_upper.rotation.z = 0.4 * wind
			arm_l_lower.rotation.z = 0.5 * wind
			torso.rotation.x = -0.12 * wind + 0.18 * impact
			torso.position.y -= 0.06 * impact
			head.rotation.x = 0.08 * impact
			leg_l_thigh.rotation.z = 0.1 * impact
			leg_r_thigh.rotation.z = -0.1 * impact
	elif ptype == "ultimate":
		var p: float = pose.get("time", 0.0)
		if not is_warrior:
			var lift: float = _smooth(p / 0.3) * (1.0 - _smooth((p - 1.08) / 0.32))
			var draw: float = _smooth((p - 0.12) / 0.35) * (1.0 - _smooth((p - 0.62) / 0.14))
			var release: float = _smooth((p - 0.62) / 0.1) * (1.0 - _smooth((p - 1.02) / 0.24))
			torso.rotation.y = -0.2 * lift
			torso.rotation.x = -0.12 * lift + 0.1 * release
			head.rotation.x = -0.24 * lift
			arm_l_upper.rotation.z = 0.12 - 1.55 * lift
			arm_l_upper.rotation.x = -0.42 * lift
			arm_l_lower.rotation.z = -0.18 * lift
			arm_r_upper.rotation.z = -0.92 * lift
			arm_r_upper.rotation.x = -0.3 * lift
			arm_r_lower.rotation.z = -1.76 * draw
			weapon.rotation.z = 0.18 + 1.55 * lift
			weapon.rotation.x = 0.05 - 0.28 * lift
			weapon.position.y = _lerp(-0.02, 0.34, lift)
			if bow_string: bow_string.set_middle_x(draw * 0.62)
			if arrow_mesh:
				arrow_mesh.visible = draw > 0.05 and p < 0.68
				arrow_mesh.position.x = -0.66 + draw * 0.62
		else:
			var raise: float = _smooth(p / 0.34)
			var slam: float = _smooth((p - 0.38) / 0.28)
			var recover: float = 1.0 - _smooth((p - 0.86) / 0.32)
			var power: float = min(raise, recover)
			var impact: float = max(0.0, 1.0 - abs(p - 0.68) * 15.0)
			arm_r_upper.rotation.x = -1.65 * power + 2.15 * slam * recover
			arm_r_upper.rotation.z = -0.55 * power
			arm_r_lower.rotation.x = -0.72 * power
			arm_l_upper.rotation.x = -1.25 * power + 1.6 * slam * recover
			arm_l_upper.rotation.z = 0.5 * power
			arm_l_lower.rotation.x = -0.5 * power
			weapon.rotation.z = -0.15 - 2.25 * power + 3.7 * slam * recover
			weapon.position.y += 0.2 * power - 0.25 * slam * recover
			torso.rotation.x = -0.2 * power + 0.3 * impact
			torso.position.y -= 0.1 * impact
			head.rotation.x = -0.12 * power + 0.15 * impact
			leg_l_thigh.rotation.z = 0.13 * power
			leg_r_thigh.rotation.z = -0.13 * power
	else:
		if not is_warrior:
			if bow_string: bow_string.set_middle_x(0.0)
			if arrow_mesh: arrow_mesh.visible = false


## 简单的 3 段线，用于弓弦形变。
class Line3D:
	extends MeshInstance3D
	var _points: Array[Vector3] = []
	var color := Color.WHITE

	func _init() -> void:
		mesh = ImmediateMesh.new()

	func set_points(pts: Array) -> void:
		_points.clear()
		for p in pts:
			_points.append(Vector3(p.x, p.y, p.z))
		_rebuild()

	func set_middle_x(x: float) -> void:
		if _points.size() >= 3:
			_points[1] = Vector3(x, _points[1].y, _points[1].z)
			_rebuild()

	func _rebuild() -> void:
		var im := mesh as ImmediateMesh
		im.clear_surfaces()
		if _points.size() < 2: return
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _make_material())
		for p in _points:
			im.surface_add_vertex(p)
		im.surface_end()

	func _make_material() -> Material:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = color
		return m
