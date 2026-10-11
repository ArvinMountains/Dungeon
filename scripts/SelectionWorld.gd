class_name SelectionWorld
extends Node3D
## 职业选择舞台。对应 main.js createSelectionWorld + updateSelection + requestClass。

signal class_ui_changed

var phase := "idle"  # idle | showcase | fadingOut | fadingIn
var status_text := "待机 · 呼吸"
var pending_class: String = ""
var transition_time := 0.0
var showcase_time := 0.0
var yaw := 0.12
var smoke_root: Node3D
var smoke_particles: Array = []
var main: Node

func _ready() -> void:
	main = get_tree().current_scene
	_build_stage()

func _build_stage() -> void:
	var GB := GeoBuilder
	var Env := Ambience
	Env.tiled_floor(self, 26, -0.2, 741)
	for i in range(3):
		GB.cylinder(self, 2.7 - i * 0.18, 2.7 - i * 0.18, 0.19, Color(0.26,0.29,0.23), Vector3(0, -0.04 + i * 0.19, 0), 12)
	var rim_mat := GB.mat(Color(0.63,0.55,0.32), {"metalness": 0.5, "roughness": 0.7})
	var rim := GB.ring(self, 2.225, 2.25, rim_mat, Vector3(0, 0.45, 0), 64)
	var inner := GB.ring(self, 2.047, 2.07, rim_mat, Vector3(0, 0.451, 0), 64)
	for i in range(24):
		var a := i / 24.0 * TAU
		var tile := GB.box(self, 0.12, 0.014, 0.23, Color(0.63,0.55,0.34), Vector3(cos(a) * 2.05, 0.449, sin(a) * 2.05))
		tile.rotation.y = -a
	var rng := RandomNumberGenerator.new(); rng.seed = 999
	for i in range(11):
		var a := rng.randf() * TAU
		var r := rng.randf() * 1.8
		var tile := GB.box(self, 0.03, 0.014, 0.25 + rng.randf() * 0.4, Color(0.20,0.24,0.20), Vector3(cos(a) * r, 0.452, sin(a) * r))
		tile.rotation.y = rng.randf() * TAU
	Env.pillar(self, -4.2, -0.8, 5.8)
	Env.pillar(self, 4.7, -0.8, 5.8)
	Env.pillar(self, -4.2, -5, 6.1)
	Env.pillar(self, 4.7, -5, 6.1)
	Env.pillar(self, -7, 2.2, 3.1, true)
	Env.pillar(self, 7.5, 2, 3.8, true)
	var arch := Env.gothic_arch(self, 4.2, 6.6, 0.8, Color(0.25,0.29,0.24))
	arch.position = Vector3(0, -0.1, -5.6)
	GB.box(self, 4.1, 7.7, 0.2, Color(0.05,0.09,0.07), Vector3(0, 3.7, -5.9))
	var x := -1.5
	while x <= 1.5:
		GB.box(self, 0.06, 4.2, 0.06, Color(0.22,0.24,0.17), Vector3(x, 2.0, -5.63))
		var cone := ConeMarker.new(self, Vector3(x, 4.22, -5.63))
		x += 0.5
	for y in [1.1, 2.4, 3.3]:
		GB.box(self, 3.3, 0.05, 0.08, Color(0.28,0.29,0.21), Vector3(0, y, -5.62))
	for side in [-1, 1]:
		for i in range(7):
			GB.box(self, 4.4, 0.8, 0.9, Ambience._stone_colors[i % 6], Vector3(side * 4.4, i * 0.85 + 0.3, -6.2))
		var side_arch := Env.gothic_arch(self, 2.5, 4.3, 0.3, Color(0.20,0.25,0.20))
		side_arch.position = Vector3(side * 6.9, -0.2, -4.8)
		GB.box(self, 2.3, 4.3, 0.1, Color(0.05,0.10,0.07), Vector3(side * 6.9, 1.9, -5))
		Env.candelabra(self, side * 3.35, -0.3, 1.55, true)
		Env.candle(self, side * 2.2, 0.47, 0.85, 1.0)
		Env.candle(self, side * 2.02, 0.47, 1.17, 0.72)
		Env.candle(self, side * 2.42, 0.28, 1.24, 0.87)
	for i in range(50):
		var angle := rng.randf() * TAU
		var radius := 3.8 + rng.randf() * 6.0
		var rock := GB.box(self, 0.15 + rng.randf() * 0.35, 0.08 + rng.randf() * 0.2, 0.2 + rng.randf() * 0.4, Ambience._stone_colors[i % 6], Vector3(cos(angle) * radius, -0.08, sin(angle) * radius))
		rock.rotation = Vector3(rng.randf() * 0.3, rng.randf() * TAU, rng.randf() * 0.3)
	for i in range(5):
		Env.make_fog(self, 25, 0.08 + i * 0.23, 0.1, 741 + i)
	Env.make_motes(self, 85, 15, Color(0.76,0.71,0.54))
	# Fill light.
	var fill := OmniLight3D.new()
	fill.position = Vector3(1, 4, -3)
	fill.light_color = Color(0.65,0.77,0.68)
	fill.light_energy = 17.0
	fill.omni_range = 11.0
	add_child(fill)
	# Smoke particles for dissolve.
	smoke_root = Node3D.new()
	smoke_root.position = Vector3(0, 0.47, 0)
	add_child(smoke_root)
	var smoke_mesh := SphereMesh.new()
	smoke_mesh.radius = 0.13; smoke_mesh.height = 0.26; smoke_mesh.radial_segments = 6; smoke_mesh.rings = 4
	for i in range(58):
		var m := MeshInstance3D.new()
		m.mesh = smoke_mesh
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.09,0.15,0.11, 0.0)
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.material_override = sm
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		smoke_root.add_child(m)
		smoke_particles.append({
			"mesh": m, "angle": rng.randf() * TAU, "y": rng.randf() * 2.7,
			"radius": 0.2 + rng.randf() * 0.8, "speed": 0.6 + rng.randf()
		})

class ConeMarker:
	extends MeshInstance3D
	func _init(parent: Node3D, pos: Vector3) -> void:
		var c := CylinderMesh.new()
		c.top_radius = 0.0; c.bottom_radius = 0.11; c.height = 0.26; c.radial_segments = 4
		mesh = c
		material_override = GeoBuilder.mat(Color(0.44,0.38,0.27))
		position = pos
		parent.add_child(self)

func _update_smoke(amount: float, time: float) -> void:
	smoke_root.visible = amount > 0.001
	for s in smoke_particles:
		var a: float = s.angle + time * s.speed
		s.mesh.position = Vector3(cos(a) * s.radius * (1.2 - amount * 0.25), fmod(s.y + time * 0.65, 3.1), sin(a) * s.radius)
		s.mesh.scale = Vector3.ONE * (0.6 + amount * 1.6)
		s.mesh.material_override.albedo_color.a = amount * 0.7
		s.mesh.rotation = Vector3(a, a * 0.7, a * 0.4)

func request_class(id: String) -> void:
	if not GameState.CLASS_DATA.has(id): return
	if phase == "fadingOut" or phase == "fadingIn":
		pending_class = id
		return
	if id == GameState.save.selected:
		start_showcase()
		return
	pending_class = id
	phase = "fadingOut"
	transition_time = 0.0
	class_ui_changed.emit()
	AudioBus.play_tone(130, 0.32, 0.07)

func start_showcase() -> void:
	if phase == "fadingOut" or phase == "fadingIn": return
	phase = "showcase"
	showcase_time = 0.0
	class_ui_changed.emit()

func update_selection(dt: float) -> void:
	var chars: Dictionary = main.characters
	var active: ProceduralCharacter = chars[GameState.save.selected]
	active.rotation.y = yaw
	var time: float = Time.get_ticks_msec() / 1000.0
	if phase == "fadingOut":
		transition_time += dt
		var p: float = clamp(transition_time / 0.6, 0.0, 1.0)
		active.set_opacity(1.0 - _smooth(p))
		_update_smoke(sin(p * PI / 2.0), time)
		if p >= 1.0:
			active.visible = false
			GameState.set_selected(pending_class)
			pending_class = ""
			phase = "fadingIn"
			transition_time = 0.0
			active = chars[GameState.save.selected]
			active.position = Vector3(0, 0.47, 0)
			active.set_opacity(0.0)
			active.visible = true
			class_ui_changed.emit()
	elif phase == "fadingIn":
		transition_time += dt
		var p: float = clamp(transition_time / 0.75, 0.0, 1.0)
		active.set_opacity(_smooth(p))
		_update_smoke(1.0 - _smooth(p), time)
		if p >= 1.0:
			active.set_opacity(1.0)
			phase = "idle"
			start_showcase()
	else:
		_update_smoke(0.0, time)
		if phase == "showcase":
			showcase_time += dt
			if showcase_time >= 4.4:
				phase = "idle"
				class_ui_changed.emit()
	match phase:
		"fadingOut": status_text = "灵魂消散"
		"fadingIn": status_text = "灵魂凝聚"
		"showcase": status_text = "月下引弓" if GameState.is_archer() else "余烬之誓"
		_: status_text = "待机 · 呼吸"
	var pose: Dictionary = {"type": "showcase", "time": showcase_time} if phase == "showcase" else {"type": "idle"}
	active.animate_pose(dt, time, pose)

func _smooth(x: float) -> float:
	x = clamp(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)
