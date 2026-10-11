class_name TownWorld
extends Node3D
## 主城「灰烬庇护所」：A*寻路、6 设施交互、委托任务链、经济。
## 对应 main.js createTown / pathfind / updateMovement / 各 dialog。

signal toast_requested(text: String)
signal dialog_requested(title: String, content: String, actions: Array, eyebrow: String)
signal dialog_closed
signal hud_changed
signal enter_dungeon_requested
signal enter_selection_requested

const GRID_STEP := 0.4
const GRID_MIN := -13.2
const GRID_COUNT := 67
const PLAYER_RADIUS := 0.29

var player_position := Vector3(0, 0.05, 5.5)
var player_yaw := PI
var walk_phase := 0.0
var moving := false
var path: Array[Vector3] = []
var destination_poi: Dictionary = {}
var near_poi: Dictionary = {}

var obstacles: Array = []          # {x, z, w, d} — w/d 为半宽
var pois: Array[Dictionary] = []
var collectible_meshes := {}       # ember_id -> Node3D
var flames: Array = []             # {node, phase, base, light, shrine}
var dummy_node: Node3D
var move_marker: MeshInstance3D
var town_npcs: Array = []

var main = null                    # Main.gd 实例
var _grid: Array = []              # bool per cell
var _elapsed := 0.0
var _dummy_reset_timer := 0.0

func _ready() -> void:
	_build_town()
	_build_grid()
	_build_move_marker()

func on_enter() -> void:
	refresh_quest_visibility()
	hud_changed.emit()

# ---------------- 构建 ----------------

func _obstacle(x: float, z: float, w: float, d: float) -> void:
	obstacles.append({"x": x, "z": z, "w": w / 2.0, "d": d / 2.0})

func _add_poi(id: String, pname: String, symbol: String, pos: Vector3, dest: Vector2, on_interact: Callable, type := "place") -> Dictionary:
	var poi := {
		"id": id, "name": pname, "symbol": symbol,
		"position": pos, "destination": Vector3(dest.x, 0, dest.y),
		"on_interact": on_interact, "type": type,
	}
	pois.append(poi)
	return poi

func _window_frame(parent: Node3D, x: float, y: float, z: float, w := 0.46, h := 0.85) -> void:
	GeoBuilder.box(parent, w + 0.18, h + 0.18, 0.15, Color(0.17,0.20,0.17), Vector3(x, y, z))
	GeoBuilder.box(parent, w, h, 0.045, GeoBuilder.mat(Color(0.86,0.63,0.31), {"emissive": Color(0.87,0.60,0.22), "emissive_intensity": 0.95}), Vector3(x, y, z + 0.09))
	GeoBuilder.box(parent, 0.045, h, 0.065, Color(0.26,0.24,0.16), Vector3(x, y, z + 0.12))
	GeoBuilder.box(parent, w, 0.06, 0.07, Color(0.26,0.24,0.16), Vector3(x, y + 0.08, z + 0.12))
	GeoBuilder.box(parent, w + 0.26, 0.12, 0.26, Color(0.41,0.38,0.29), Vector3(x, y - h / 2, z + 0.04))

func _building(x: float, z: float, w: float, d: float, h: float, roof_color := Color(0.19,0.23,0.21)) -> Node3D:
	var b := Node3D.new()
	b.position = Vector3(x, 0, z)
	add_child(b)
	GeoBuilder.box(b, w + 0.25, 0.35, d + 0.25, Color(0.25,0.29,0.23), Vector3(0, 0.1, 0))
	GeoBuilder.box(b, w, h, d, Color(0.32,0.33,0.27), Vector3(0, h / 2 + 0.25, 0))
	for i in range(int(h / 0.55)):
		GeoBuilder.box(b, w + 0.03, 0.035, d + 0.03, Color(0.22,0.26,0.22), Vector3(0, 0.4 + i * 0.55, 0))
		for j in range(int(w / 0.7)):
			GeoBuilder.box(b, 0.035, 0.5, 0.035, Color(0.22,0.26,0.22), Vector3(-w / 2 + 0.3 + j * 0.7 + (i % 2) * 0.18, 0.65 + i * 0.55, d / 2 + 0.01))
	for side in [-1, 1]:
		GeoBuilder.box(b, 0.22, h + 0.1, d + 0.12, Color(0.19,0.24,0.19), Vector3(side * (w / 2 - 0.12), h / 2 + 0.25, 0))
	GeoBuilder.box(b, w + 0.36, 0.18, d + 0.35, Color(0.45,0.44,0.35), Vector3(0, h + 0.23, 0))
	# 屋顶：用斜梁近似三.js 的 ExtrudeGeometry 山墙。
	var roof_h := w * 0.52
	for side in [-1, 1]:
		var p0 := Vector3(side * (w / 2 + 0.3), h + 0.31, -d / 2 - 0.24)
		var p1 := Vector3(0, h + 0.31 + roof_h, -d / 2 - 0.24)
		var p2 := Vector3(side * (w / 2 + 0.3), h + 0.31, d / 2 + 0.24)
		var p3 := Vector3(0, h + 0.31 + roof_h, d / 2 + 0.24)
		GeoBuilder.beam(b, p0, p1, 0.1, 0.1, roof_color)
		GeoBuilder.beam(b, p2, p3, 0.1, 0.1, roof_color)
		GeoBuilder.beam(b, p1, p3, 0.1, 0.1, roof_color)
		# 斜面板
		var panel := GeoBuilder.box(b, (p0 - p1).length(), 0.06, d + 0.48, roof_color)
		panel.position = (p0 + p1 + p2 + p3) / 4.0
		panel.rotation.z = side * atan2(roof_h, w / 2 + 0.3)
	for i in range(6):
		var yy := i * roof_h / 6.0
		GeoBuilder.box(b, (w + 0.6) * (1.0 - i / 6.0), 0.04, d + 0.51, Color(0.29,0.32,0.27), Vector3(0, h + 0.32 + yy, 0))
	GeoBuilder.box(b, 0.12, 0.15, d + 0.68, Color(0.47,0.44,0.35), Vector3(0, h + 0.31 + roof_h, 0))
	_obstacle(x, z, w + 0.3, d + 0.3)
	return b

func _crate(x: float, z: float, size := 0.65) -> void:
	GeoBuilder.box(self, size, size, size, Color(0.32,0.27,0.20), Vector3(x, size / 2, z))
	for s in [-1, 1]:
		GeoBuilder.box(self, 0.06, size, size + 0.03, Color(0.45,0.38,0.27), Vector3(x + s * size * 0.36, size / 2, z))
		GeoBuilder.box(self, size + 0.025, 0.06, size + 0.025, Color(0.45,0.38,0.27), Vector3(x, size * (0.5 + s * 0.37), z))

func _dead_tree(x: float, z: float, s := 1.0) -> void:
	var t := Node3D.new()
	t.position = Vector3(x, 0, z)
	t.scale = Vector3.ONE * s
	add_child(t)
	GeoBuilder.beam(t, Vector3(0, 0, 0), Vector3(-0.12, 2.7, 0), 0.18, 0.18, Color(0.20,0.24,0.18))
	GeoBuilder.beam(t, Vector3(-0.06, 1.3, 0), Vector3(-0.85, 2.3, 0.2), 0.11, 0.1, Color(0.26,0.29,0.22))
	GeoBuilder.beam(t, Vector3(-0.85, 2.3, 0.2), Vector3(-1.0, 3, 0.16), 0.055, 0.055, Color(0.26,0.29,0.22))
	GeoBuilder.beam(t, Vector3(-0.09, 1.9, 0), Vector3(0.62, 2.6, -0.25), 0.1, 0.1, Color(0.26,0.29,0.22))
	GeoBuilder.beam(t, Vector3(0.62, 2.6, -0.25), Vector3(1, 2.72, -0.3), 0.05, 0.05, Color(0.26,0.29,0.22))
	_obstacle(x, z, 0.45, 0.45)

func _flame(parent: Node3D, pos: Vector3, radius: float, base := 1.5, shrine := false) -> MeshInstance3D:
	var f := GeoBuilder.octahedron(parent, radius, GeoBuilder.mat(Color(0.82,0.58,0.24), {"emissive": Color(0.91,0.55,0.15), "emissive_intensity": 1.5, "unshaded": true}), pos, false)
	flames.append({"node": f, "phase": randf() * 9.0, "base": base, "light": null, "shrine": shrine})
	return f

func _build_town() -> void:
	Ambience.tiled_floor(self, 30, -0.13)
	for i in range(-13, 14):
		for x in [-3.8, 3.8]:
			GeoBuilder.box(self, 0.16, 0.09, 0.9, Color(0.47,0.44,0.35), Vector3(x, -0.01, i))
	for x in [-14.1, 14.1]:
		GeoBuilder.box(self, 0.55, 1.0, 29, Color(0.26,0.31,0.24), Vector3(x, 0.3, 0))
		var z := -13.2
		while z <= 13.2:
			GeoBuilder.box(self, 0.72, 1.3, 0.6, Color(0.34,0.38,0.30), Vector3(x, 0.48, z))
			z += 1.6
	GeoBuilder.box(self, 29, 1.8, 0.6, Color(0.22,0.27,0.22), Vector3(0, 0.75, -13.7))

	# 铁匠铺
	var forge := _building(-9.2, -8, 4.6, 3.9, 2.7, Color(0.23,0.21,0.19))
	_window_frame(forge, -1.25, 1.65, 2.0, 0.72, 0.75)
	var hearth := Ambience.gothic_arch(forge, 1.35, 1.8, 0.3, Color(0.45,0.39,0.30))
	hearth.position = Vector3(0.7, 0.15, 2.03)
	GeoBuilder.box(forge, 1.24, 1.5, 0.05, Color(0.09,0.11,0.09), Vector3(0.7, 0.9, 2.01))
	for i in range(7):
		_flame(forge, Vector3(0.3 + i * 0.13, 0.4 + randf() * 0.2, 2.14), 0.2, 1.5)
	var forge_light := OmniLight3D.new()
	forge_light.position = Vector3(-8.1, 1.9, -5.4)
	forge_light.light_color = Color(1.0, 0.6, 0.26)
	forge_light.light_energy = 3.0
	forge_light.omni_range = 9.0
	add_child(forge_light)
	GeoBuilder.box(forge, 0.75, 2.3, 0.85, Color(0.23,0.25,0.21), Vector3(-1.15, 4.4, -0.55))
	GeoBuilder.box(forge, 0.9, 0.2, 1, Color(0.42,0.38,0.30), Vector3(-1.15, 5.58, -0.55))
	var anvil := Node3D.new()
	anvil.position = Vector3(-7.1, 0, -3.7)
	add_child(anvil)
	GeoBuilder.box(anvil, 0.65, 0.6, 0.55, Color(0.27,0.23,0.16), Vector3(0, 0.3, 0))
	GeoBuilder.box(anvil, 0.82, 0.22, 0.43, Color(0.46,0.48,0.41), Vector3(0, 0.73, 0))
	GeoBuilder.box(anvil, 0.41, 0.32, 0.36, Color(0.38,0.41,0.35), Vector3(0, 0.6, 0))
	GeoBuilder.beam(anvil, Vector3(0.32, 0.75, 0), Vector3(0.66, 0.8, 0), 0.17, 0.22, Color(0.45,0.47,0.42))
	_obstacle(-7.1, -3.7, 1, 0.9)
	var smith := ProceduralCharacter.new("warrior", 313)
	smith.position = Vector3(-8.9, 0.06, -3)
	smith.scale = Vector3.ONE * 0.67
	smith.rotation.y = 0.4
	add_child(smith)
	town_npcs.append(smith)

	# 旅店
	var inn := _building(8.6, -8.2, 4.5, 4.2, 3.45, Color(0.20,0.24,0.22))
	for x in [-1.3, 1.3]:
		_window_frame(inn, x, 2.65, 2.13)
		_window_frame(inn, x, 1.15, 2.13, 0.54, 0.75)
	GeoBuilder.box(inn, 0.86, 1.6, 0.08, Color(0.13,0.18,0.14), Vector3(0, 0.96, 2.16))
	GeoBuilder.box(inn, 1.0, 0.11, 0.4, Color(0.46,0.44,0.35), Vector3(0, 0.22, 2.28))
	GeoBuilder.beam(inn, Vector3(0.55, 2.5, 2.2), Vector3(0.55, 2.5, 3.05), 0.06, 0.06, Color(0.31,0.30,0.21))
	GeoBuilder.box(inn, 0.76, 0.49, 0.08, Color(0.44,0.38,0.27), Vector3(0.55, 2.16, 3.05))
	GeoBuilder.box(inn, 0.42, 0.045, 0.1, Color(0.76,0.67,0.42), Vector3(0.55, 2.16, 3.1))

	# 教堂 + 深渊之门
	var chapel := _building(0, -12, 4.5, 2.4, 4.1, Color(0.20,0.24,0.22))
	var gate := Ambience.gothic_arch(chapel, 2.1, 3.65, 0.4, Color(0.47,0.45,0.36))
	gate.position.z = 1.38
	GeoBuilder.box(chapel, 1.98, 3.2, 0.07, Color(0.07,0.16,0.12), Vector3(0, 1.6, 1.41))
	var gx := -0.8
	while gx <= 0.8:
		GeoBuilder.box(chapel, 0.055, 2.95, 0.09, Color(0.41,0.41,0.29), Vector3(gx, 1.5, 1.49))
		gx += 0.32
	for side in [-1, 1]:
		var spire := Node3D.new()
		spire.position = Vector3(side * 3.4, 0, -11.9)
		add_child(spire)
		GeoBuilder.box(spire, 0.9, 5.1, 1, Color(0.33,0.35,0.29), Vector3(0, 2.5, 0))
		GeoBuilder.cylinder(spire, 0, 0.73, 2.35, Color(0.20,0.25,0.22), Vector3(0, 6.05, 0), 4)
		GeoBuilder.box(spire, 0.055, 0.8, 0.055, Color(0.58,0.51,0.35), Vector3(0, 7.5, 0))
		GeoBuilder.box(spire, 0.38, 0.055, 0.055, Color(0.58,0.51,0.35), Vector3(0, 7.64, 0))

	# 中央祭坛
	var stone_colors: Array[Color] = Ambience._stone_colors
	for i in range(3):
		GeoBuilder.cylinder(self, 1.35 - i * 0.18, 1.35 - i * 0.18, 0.19, stone_colors[i + 1], Vector3(0, 0.04 + i * 0.19, 0), 10)
	GeoBuilder.cylinder(self, 0.72, 0.45, 0.65, Color(0.31,0.34,0.27), Vector3(0, 0.77, 0), 8)
	GeoBuilder.cylinder(self, 0.84, 0.72, 0.15, Color(0.56,0.52,0.40), Vector3(0, 1.13, 0), 8)
	GeoBuilder.cylinder(self, 0.7, 0.65, 0.06, Color(0.16,0.18,0.13), Vector3(0, 1.2, 0), 8)
	for i in range(9):
		var a := i / 9.0 * TAU
		_flame(self, Vector3(cos(a) * 0.35, 1.4 + randf() * 0.18, sin(a) * 0.35), 0.21, 2.0, true)
	_obstacle(0, 0, 2.6, 2.6)
	var shrine_light := OmniLight3D.new()
	shrine_light.position = Vector3(0, 2, 0)
	shrine_light.light_color = Color(0.94, 0.75, 0.47)
	shrine_light.light_energy = 2.6
	shrine_light.omni_range = 8.0
	add_child(shrine_light)
	flames.append({"node": null, "phase": 0.0, "base": 0.0, "light": shrine_light, "shrine": true})

	# 药剂商摊位
	var stall := Node3D.new()
	stall.position = Vector3(9.6, 0, 2)
	add_child(stall)
	for x in [-1.2, 1.2]:
		for z in [-0.7, 0.7]:
			GeoBuilder.box(stall, 0.08, 2.3, 0.08, Color(0.33,0.30,0.21), Vector3(x, 1.15, z))
	GeoBuilder.box(stall, 2.4, 0.92, 1.25, Color(0.29,0.27,0.20), Vector3(0, 0.46, 0))
	GeoBuilder.box(stall, 2.65, 0.12, 1.4, Color(0.48,0.41,0.31), Vector3(0, 0.98, 0))
	for i in range(7):
		var cloth := GeoBuilder.box(stall, 0.39, 0.065, 1.9, Color(0.38,0.40,0.29) if i % 2 else Color(0.20,0.25,0.20), Vector3(-1.17 + i * 0.39, 2.3, 0))
		cloth.rotation.x = 0.14
		GeoBuilder.box(stall, 0.39, 0.28, 0.05, Color(0.38,0.40,0.29) if i % 2 else Color(0.20,0.25,0.20), Vector3(-1.17 + i * 0.39, 2.02, 0.95))
	for i in range(10):
		var bx := (randf() - 0.5) * 2
		var bz := (randf() - 0.5) * 0.7
		GeoBuilder.cylinder(stall, 0.045, 0.09, 0.22, Color(0.45,0.52,0.36) if i % 3 else Color(0.56,0.40,0.32), Vector3(bx, 1.16, bz), 5)
		GeoBuilder.cylinder(stall, 0.035, 0.035, 0.07, Color(0.70,0.63,0.47), Vector3(bx, 1.3, bz), 5)
	_obstacle(9.6, 2, 2.8, 2.1)
	var merchant := ProceduralCharacter.new("archer", 514)
	merchant.position = Vector3(7.8, 0, 1.9)
	merchant.scale = Vector3.ONE * 0.63
	merchant.rotation.y = -0.9
	add_child(merchant)
	town_npcs.append(merchant)

	# 告示板
	var board := Node3D.new()
	board.position = Vector3(6.6, 0, -3.8)
	add_child(board)
	for x in [-0.58, 0.58]:
		GeoBuilder.box(board, 0.12, 2.0, 0.13, Color(0.32,0.29,0.21), Vector3(x, 1, 0))
	GeoBuilder.box(board, 1.45, 0.91, 0.16, Color(0.25,0.24,0.17), Vector3(0, 1.5, 0))
	GeoBuilder.box(board, 1.66, 0.12, 0.29, Color(0.50,0.44,0.31), Vector3(0, 2.02, 0))
	for i in range(3):
		var note := GeoBuilder.box(board, 0.3, 0.48 - i * 0.04, 0.02, Color(0.62,0.58,0.43) if i % 2 else Color(0.69,0.63,0.48), Vector3(-0.43 + i * 0.42, 1.52, 0.098))
		note.rotation.z = (i - 1) * 0.1
	_obstacle(6.6, -3.8, 1.65, 0.7)

	# 训练木桩
	var dummy := Node3D.new()
	dummy.position = Vector3(-7.3, 0, 6.2)
	add_child(dummy)
	GeoBuilder.cylinder(dummy, 0.07, 0.08, 1.9, Color(0.41,0.38,0.26), Vector3(0, 0.95, 0))
	GeoBuilder.cylinder(dummy, 0.25, 0.27, 0.69, Color(0.60,0.53,0.38), Vector3(0, 1.26, 0), 6)
	GeoBuilder.box(dummy, 1.05, 0.1, 0.12, Color(0.47,0.42,0.31), Vector3(0, 1.5, 0))
	GeoBuilder.cylinder(dummy, 0.2, 0.2, 0.32, Color(0.69,0.63,0.47), Vector3(0, 1.78, 0), 6)
	GeoBuilder.box(dummy, 0.13, 0.13, 0.02, Color(0.35,0.30,0.20), Vector3(0, 1.37, 0.25))
	_obstacle(-7.3, 6.2, 0.8, 0.8)
	dummy_node = dummy

	for pos in [[-4.8, -8], [4.7, -8], [-9.5, 4.5], [5, 6.4]]:
		Ambience.candelabra(self, pos[0], pos[1], 1.6, false)
	for pos in [[-11.2, -3.7], [-10.3, -3.4], [11.7, -3.5], [11.6, 6.2], [-10.6, 9]]:
		_crate(pos[0], pos[1])
	for pos in [[-12.2, 5.2, 1.1], [12.2, 8.8, 1.3], [-10.8, 11.4, 0.9], [11.8, -12.1, 1.2]]:
		_dead_tree(pos[0], pos[1], pos[2])
	for side in [-1, 1]:
		GeoBuilder.box(self, 8.6, 0.13, 0.2, Color(0.38,0.39,0.29), Vector3(side * 8.2, 0.8, 12.8))
		var fx := 4.0
		while fx < 12.5:
			GeoBuilder.box(self, 0.06, 1.4, 0.06, Color(0.22,0.28,0.20), Vector3(side * fx, 0.65, 12.8))
			fx += 0.6
	var rng := RandomNumberGenerator.new()
	rng.seed = 742
	for i in range(72):
		var rx := (rng.randf() - 0.5) * 27
		var rz := (rng.randf() - 0.5) * 26
		if abs(rx) < 3.8: continue
		var rock := GeoBuilder.box(self, 0.09 + rng.randf() * 0.22, 0.06, 0.1 + rng.randf() * 0.18, Color(0.40,0.42,0.31) if i % 3 else Color(0.20,0.31,0.20), Vector3(rx, 0.02, rz))
		rock.rotation.y = rng.randf() * TAU
	for i in range(3):
		Ambience.make_fog(self, 38, 0.1 + 0.28 * i, 0.075)
	Ambience.make_motes(self, 125, 31, Color(0.76,0.72,0.53))

	_add_poi("smith", "铁匠铺", "⚒", Vector3(-8.3, 2.7, -3.2), Vector2(-7.8, -2.2), _smith_dialog)
	_add_poi("board", "告示板", "!", Vector3(6.6, 2.7, -3.8), Vector2(6.5, -2.6), _board_dialog)
	_add_poi("shrine", "余火祭坛", "✦", Vector3(0, 2.6, 0), Vector2(0, 2), _shrine_dialog)
	_add_poi("merchant", "药剂商", "+", Vector3(8.9, 2.6, 2), Vector2(7.6, 2.6), _merchant_dialog)
	_add_poi("dummy", "训练木桩", "†", Vector3(-7.3, 2.6, 6.2), Vector2(-6.1, 6.3), _dummy_dialog)
	_add_poi("gate", "深渊之门", "◇", Vector3(0, 4.3, -10.5), Vector2(0, -9.7), _gate_dialog)
	var locations := [[-4.5, 4.7], [4.5, 7.9], [3.1, -6.5]]
	for i in range(3):
		var x: float = locations[i][0]
		var z: float = locations[i][1]
		var crystal := Node3D.new()
		crystal.position = Vector3(x, 0.55, z)
		add_child(crystal)
		var center := GeoBuilder.octahedron(crystal, 0.19, GeoBuilder.mat(Color(0.90,0.69,0.38), {"emissive": Color(0.85,0.53,0.18), "emissive_intensity": 1.2}), Vector3.ZERO, false)
		center.scale.y = 1.8
		var ring := GeoBuilder.ring(crystal, 0.30, 0.335, Color(0.75,0.57,0.28), Vector3(0, -0.43, 0), 16)
		collectible_meshes["ember%d" % i] = crystal
		_add_poi("ember%d" % i, "拾取余火", "·", Vector3(x, 1.35, z), Vector2(x, z), _collect_ember.bind("ember%d" % i), "ember")

func _build_move_marker() -> void:
	move_marker = GeoBuilder.ring(self, 0.16, 0.26, GeoBuilder.mat(Color(0.85,0.74,0.53), {"emissive": Color(0.85,0.74,0.53), "emissive_intensity": 0.8, "transparent": true, "opacity": 0.8, "depth_write": false, "double_sided": true}), Vector3(0, 0.02, 0), 32)
	move_marker.visible = false

# ---------------- A* ----------------

func _walkable(x: float, z: float) -> bool:
	if x < -13 or x > 13 or z < -13 or z > 12.5: return false
	for o in obstacles:
		if abs(x - o.x) < o.w + PLAYER_RADIUS and abs(z - o.z) < o.d + PLAYER_RADIUS:
			return false
	return true

func _grid_point(v: float) -> int:
	return clampi(int(round((v - GRID_MIN) / GRID_STEP)), 0, GRID_COUNT - 1)

func _world_point(n: int) -> float:
	return n * GRID_STEP + GRID_MIN

func _build_grid() -> void:
	_grid.resize(GRID_COUNT * GRID_COUNT)
	for i in range(GRID_COUNT * GRID_COUNT):
		_grid[i] = _walkable(_world_point(i % GRID_COUNT), _world_point(i / GRID_COUNT))

func _nearest_cell(x: int, z: int) -> Vector2i:
	var idx := func(x: int, z: int) -> int: return z * GRID_COUNT + x
	if _grid[idx.call(x, z)]: return Vector2i(x, z)
	for radius in range(1, 6):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				var xx := x + dx
				var zz := z + dz
				var d := dx * dx + dz * dz
				if xx >= 0 and xx < GRID_COUNT and zz >= 0 and zz < GRID_COUNT and _grid[idx.call(xx, zz)] and d < best_d:
					best = Vector2i(xx, zz); best_d = d
		if best.x >= 0: return best
	return Vector2i(-1, -1)

func pathfind(start: Vector3, end: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var s := _nearest_cell(_grid_point(start.x), _grid_point(start.z))
	var e := _nearest_cell(_grid_point(end.x), _grid_point(end.z))
	if s.x < 0 or e.x < 0: return result
	var idx := func(x: int, z: int) -> int: return z * GRID_COUNT + x
	var start_id: int = idx.call(s.x, s.y)
	var end_id: int = idx.call(e.x, e.y)
	var open: Array[int] = [start_id]
	var closed := {}
	var previous := {}
	var cost := {start_id: 0.0}
	var heuristic := func(id: int) -> float:
		return Vector2(id % GRID_COUNT - e.x, id / GRID_COUNT - e.y).length()
	var iterations := 0
	while open.size() and iterations < GRID_COUNT * GRID_COUNT:
		iterations += 1
		var best := 0
		for i in range(1, open.size()):
			if cost.get(open[i], INF) + heuristic.call(open[i]) < cost.get(open[best], INF) + heuristic.call(open[best]):
				best = i
		var current: int = open[best]
		open.remove_at(best)
		if current == end_id:
			var c := current
			while c != start_id:
				result.append(Vector3(_world_point(c % GRID_COUNT), 0.05, _world_point(c / GRID_COUNT)))
				c = previous[c]
			result.reverse()
			if result.is_empty():
				result.append(Vector3(_world_point(e.x), 0.05, _world_point(e.y)))
			return result
		closed[current] = true
		var cx := current % GRID_COUNT
		var cz := current / GRID_COUNT
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				if dx == 0 and dz == 0: continue
				var nx := cx + dx
				var nz := cz + dz
				if nx < 0 or nx >= GRID_COUNT or nz < 0 or nz >= GRID_COUNT: continue
				var next: int = idx.call(nx, nz)
				if not _grid[next] or closed.has(next): continue
				if dx != 0 and dz != 0 and (not _grid[idx.call(cx + dx, cz)] or not _grid[idx.call(cx, cz + dz)]): continue
				var new_cost: float = cost[current] + (1.4142136 if dx != 0 and dz != 0 else 1.0)
				if new_cost < cost.get(next, INF):
					previous[next] = current
					cost[next] = new_cost
					if not open.has(next): open.append(next)
	return result

func set_path(target: Vector3, poi: Dictionary = {}) -> bool:
	var found := pathfind(player_position, target)
	if found.is_empty():
		toast_requested.emit("那条路已被旧日的残垣封住。")
		return false
	path = found
	destination_poi = poi
	move_marker.position = found[found.size() - 1]
	move_marker.position.y = 0.02
	move_marker.visible = true
	return true

func poi_available(poi: Dictionary) -> bool:
	return poi.type != "ember" or (GameState.save.quest == "active" and not GameState.save.embers.has(poi.id))

func travel_to_poi(poi: Dictionary) -> void:
	if not poi_available(poi): return
	dialog_closed.emit()
	if player_position.distance_to(poi.destination) < 1.0:
		poi.on_interact.call()
		return
	if set_path(poi.destination, poi):
		toast_requested.emit("正在前往%s…" % poi.name)

func track_quest() -> void:
	var save = GameState.save
	var id: String
	if save.quest == "new": id = "board"
	elif save.quest == "complete": id = "gate"
	elif save.embers.size() == 3: id = "shrine"
	else:
		for eid in ["ember0", "ember1", "ember2"]:
			if not save.embers.has(eid): id = eid; break
	for poi in pois:
		if poi.id == id:
			travel_to_poi(poi)
			return

# ---------------- 交互 ----------------

func handle_click(camera: Camera3D) -> void:
	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	if abs(dir.y) < 0.0001: return
	var t := (0.05 - from.y) / dir.y
	if t < 0: return
	var hit := from + dir * t
	set_path(hit)

func interact_near() -> void:
	if near_poi and poi_available(near_poi):
		path.clear()
		destination_poi = {}
		move_marker.visible = false
		near_poi.on_interact.call()

func refresh_quest_visibility() -> void:
	var active: bool = GameState.save.quest == "active"
	for id in collectible_meshes:
		collectible_meshes[id].visible = active and not GameState.save.embers.has(id)

# ---------------- 帧更新 ----------------

func update_town(delta: float, _camera_rig: CameraRig) -> void:
	_elapsed += delta
	if _dummy_reset_timer > 0:
		_dummy_reset_timer -= delta
		if _dummy_reset_timer <= 0 and dummy_node:
			dummy_node.rotation.z = 0
	var ui_blocked: bool = main != null and main.ui != null and main.ui.is_dialog_open()
	var previous := player_position
	var velocity := Vector3.ZERO
	if not ui_blocked:
		var up := Input.is_action_pressed("move_up")
		var down := Input.is_action_pressed("move_down")
		var left := Input.is_action_pressed("move_left")
		var right := Input.is_action_pressed("move_right")
		if up or down or left or right:
			path.clear()
			destination_poi = {}
			move_marker.visible = false
			var forward := Vector3(-0.6, 0, -0.8).normalized()
			var rightv := Vector3(0.8, 0, -0.6).normalized()
			velocity += forward * (float(up) - float(down))
			velocity += rightv * (float(right) - float(left))
		elif not path.is_empty():
			var waypoint := path[0]
			if player_position.distance_to(waypoint) < 0.09:
				path.remove_at(0)
				if not path.is_empty(): waypoint = path[0]
			if not path.is_empty():
				velocity = waypoint - player_position
			else:
				move_marker.visible = false
				var target := destination_poi
				destination_poi = {}
				if target and player_position.distance_to(target.destination) < 1.3:
					target.on_interact.call()
		var remaining := velocity.length()
		if remaining > 0.001:
			var speed: float = GameState.class_data().walk_speed * (1.6 if Input.is_action_pressed("run") else 1.0)
			velocity = velocity.normalized() * min(speed * delta, remaining if not path.is_empty() else INF)
			if _walkable(player_position.x + velocity.x, player_position.z): player_position.x += velocity.x
			if _walkable(player_position.x, player_position.z + velocity.z): player_position.z += velocity.z
	var moved := player_position.distance_to(previous)
	moving = moved > 0.0005
	if moving:
		var direction := player_position - previous
		var target_yaw := atan2(direction.x, direction.z)
		player_yaw += atan2(sin(target_yaw - player_yaw), cos(target_yaw - player_yaw)) * min(1.0, delta * 14)
		walk_phase += moved * 10
	var active = main.active_character() if main else null
	if active:
		active.position = player_position
		active.rotation.y = player_yaw
		active.animate_pose(delta, _elapsed, {"type": "walk", "step": walk_phase} if moving else {"type": "idle"})
	for npc in town_npcs:
		npc.animate_pose(delta, _elapsed, {"type": "idle"})
	# 最近 POI。
	near_poi = {}
	var distance := 1.5
	for poi in pois:
		var d := player_position.distance_to(poi.destination)
		if poi_available(poi) and d < distance:
			near_poi = poi
			distance = d
	# 火焰闪烁。
	for f in flames:
		var flicker := 1.0 + sin(_elapsed * 11.0 + f.phase) * 0.14 + sin(_elapsed * 23.0 + f.phase * 1.7) * 0.07
		if f.node:
			f.node.scale = Vector3(1, f.base * 0.55 * flicker, 1)
			if f.shrine and GameState.save.quest != "complete":
				f.node.scale *= 0.45
		if f.light:
			f.light.light_energy = 2.6 * flicker * (1.0 if GameState.save.quest == "complete" or not f.shrine else 0.4)
	# 余火旋转。
	for id in collectible_meshes:
		var c: Node3D = collectible_meshes[id]
		if c.visible:
			c.rotation.y += delta * 1.2
			c.position.y = 0.55 + sin(_elapsed * 2.0) * 0.06
	# 移动标记脉冲。
	if move_marker.visible:
		move_marker.scale = Vector3.ONE * (1.0 + sin(_elapsed * 6.0) * 0.12)

# ---------------- 对话 ----------------

func _collect_ember(id: String) -> void:
	var save = GameState.save
	if save.quest != "active" or save.embers.has(id): return
	GameState.add_ember(id)
	refresh_quest_visibility()
	hud_changed.emit()
	AudioBus.play_tone(523, 0.5)
	toast_requested.emit("三簇余火已集齐。回到祭坛，点亮长夜。" if save.embers.size() == 3 else "余火已拾取 · %d / 3" % save.embers.size())

func _board_dialog() -> void:
	var save = GameState.save
	if save.quest == "new":
		dialog_requested.emit("庇护所的余火",
			"<p class='dialog-speaker'>一张被雨水打湿的告示</p><p>“中央祭坛的火正在变冷。若还有旅人愿意帮忙，请找回散落在广场的 <b>三簇余火</b>。”</p><p>收集后前往余火祭坛，可获得 <b>60 余烬币</b>，并点亮城中的长夜。</p>",
			[
				{"label": "接下委托", "run": func():
					if GameState.save.quest != "new": return
					GameState.set_quest("active")
					refresh_quest_visibility()
					hud_changed.emit()
					dialog_closed.emit()
					toast_requested.emit("委托已接取 · 三簇余火已在城中标记。")
					AudioBus.play_tone(330, 0.3)},
				{"label": "稍后再来", "run": func(): dialog_closed.emit(), "secondary": true},
			], "A REQUEST IN THE RAIN")
	else:
		var complete: bool = save.quest == "complete"
		dialog_requested.emit("告示板 · 余火已归" if complete else "告示板 · 委托进行中",
			"<p>%s</p>" % ("“谢谢你，陌生人。只要余火还亮着，这里就还是我们的家。”" if complete else "已经找回 <b>%d / 3</b> 簇余火。沿城中的金色标记寻找，完成后回到中央祭坛。" % save.embers.size()),
			[{"label": "继续旅途", "run": func(): dialog_closed.emit()}])

func _shrine_dialog() -> void:
	var save = GameState.save
	var ready: bool = save.quest == "active" and save.embers.size() == 3
	var text := "你掌心的碎片与祭坛共鸣。将它们送回火中，让庇护所再次看见黎明。" if ready else ("金色的火焰轻轻摇曳。旧神的低语在这里短暂远去，你可以安心歇息。" if save.quest == "complete" else "火光微弱，却仍有温度。在此休憩可以恢复所有生命。")
	var actions: Array = []
	if ready:
		actions.append({"label": "归还余火 · 领取 60 余烬币", "run": func():
			if GameState.save.quest != "active" or GameState.save.embers.size() != 3: return
			GameState.set_quest("complete")
			GameState.add_gold(60)
			GameState.set_hp(100)
			refresh_quest_visibility()
			hud_changed.emit()
			dialog_closed.emit()
			AudioBus.play_tone(392, 1.0)
			toast_requested.emit("余火重燃 · 委托完成 · +60 余烬币")})
	actions.append({"label": "在火边休憩", "run": func():
		GameState.set_hp(100)
		hud_changed.emit()
		dialog_closed.emit()
		toast_requested.emit("温暖驱散疲惫 · 生命已全部恢复")})
	actions.append({"label": "离开", "run": func(): dialog_closed.emit(), "secondary": true})
	dialog_requested.emit("余火祭坛", "<p class='dialog-speaker'>石碗中传来微弱的心跳</p><p>%s</p>" % text, actions, "WHERE THE EMBERS REMAIN")

func _smith_dialog() -> void:
	var save = GameState.save
	var cost: int = 30 + save.upgrade * 15
	dialog_requested.emit("铁匠 · 霍尔德",
		"<p class='dialog-speaker'>“火还没灭，就有活可干。”</p><p>当前武器：<b>%s +%d</b></p><p>锻造提升训练伤害，每级增加 4 点。%s</p>" % [
			"古林长弓" if GameState.is_archer() else "旧国战锤", save.upgrade,
			"这件武器已达到本章锻造上限。" if save.upgrade >= 3 else "下一次锻造需要 <b>%d 余烬币</b>。" % cost],
		[
			{"label": "已完成全部锻造" if save.upgrade >= 3 else "锻造武器 · %d 币" % cost, "disabled": save.upgrade >= 3 or save.gold < cost, "run": func():
				var c: int = 30 + GameState.save.upgrade * 15
				if GameState.save.upgrade >= 3 or GameState.save.gold < c: return
				GameState.add_gold(-c)
				GameState.save.upgrade += 1
				GameState.persist()
				hud_changed.emit()
				AudioBus.play_tone(164, 0.2)
				_smith_dialog()
				toast_requested.emit("锻造完成 · 武器 +%d" % GameState.save.upgrade)},
			{"label": "离开铁匠铺", "run": func(): dialog_closed.emit(), "secondary": true},
		], "THE LAST FORGE")

func _merchant_dialog() -> void:
	var save = GameState.save
	dialog_requested.emit("药剂商 · 莫拉",
		"<p class='dialog-speaker'>“把这个带上，别让夜色带走你。”</p><p>生命药剂恢复 <b>35 点生命</b>。可以使用快捷键 <b>1</b> 或右下角药剂栏饮用。</p><p>售价 <b>20 余烬币</b> · 行囊中已有 %d 瓶</p>" % save.potions,
		[
			{"label": "购买药剂 · 20 币", "disabled": save.gold < 20 or save.potions >= 99, "run": func():
				if GameState.save.gold < 20 or GameState.save.potions >= 99: return
				GameState.add_gold(-20)
				GameState.add_potion(1)
				hud_changed.emit()
				AudioBus.play_tone(440, 0.15)
				_merchant_dialog()
				toast_requested.emit("生命药剂已放入行囊。")},
			{"label": "离开", "run": func(): dialog_closed.emit(), "secondary": true},
		], "A SMALL REMEDY")

func _dummy_dialog() -> void:
	var save = GameState.save
	var dmg: int = (12 if GameState.is_archer() else 18) + save.upgrade * 4
	dialog_requested.emit("训练木桩",
		"<p>磨砺手感，试试你手中的武器。</p><p>本次攻击造成 <b>%d 点训练伤害</b>。首次完成三次训练，可获得 <b>20 余烬币</b>。</p><p>%s</p>" % [
			dmg, "✓ 今日初训奖励已领取" if save.training_reward else "训练进度 %d / 3" % save.training_hits],
		[
			{"label": "攻击木桩", "run": func():
				var s = GameState.save
				if not s.training_reward:
					s.training_hits = mini(3, s.training_hits + 1)
					if s.training_hits == 3:
						s.training_reward = true
						GameState.add_gold(20)
				GameState.persist()
				hud_changed.emit()
				dialog_closed.emit()
				if dummy_node:
					dummy_node.rotation.z = -0.16
					_dummy_reset_timer = 0.2
				AudioBus.play_tone(280 if GameState.is_archer() else 100, 0.16)
				var d2: int = (12 if GameState.is_archer() else 18) + s.upgrade * 4
				toast_requested.emit("命中 · %d 伤害%s" % [d2, " · 初训已完成" if s.training_hits == 3 and s.training_reward else " · 训练 %d/3" % s.training_hits])},
			{"label": "离开", "run": func(): dialog_closed.emit(), "secondary": true},
		], "TEMPER YOUR RESOLVE")

func _gate_dialog() -> void:
	var complete: bool = GameState.save.quest == "complete"
	var actions: Array = []
	if complete:
		actions.append({"label": "进入废弃圣堂", "run": func():
			dialog_closed.emit()
			enter_dungeon_requested.emit()})
	actions.append({"label": "留在庇护所", "run": func(): dialog_closed.emit()})
	actions.append({"label": "回到灵魂之契", "run": func(): enter_selection_requested.emit(), "secondary": true})
	dialog_requested.emit("深渊之门",
		"<p>铁门的另一侧，是没有回声的黑暗。</p><p>%s</p>%s" % [
			"余火已被点亮。守门人向你颔首，为你推开了第一重封印。" if complete else "守门人低语：“先去照看城中的余火吧，旅人。”",
			"<p>第一关「废弃圣堂」已开启。清除其中的低语者，可获得 <b>90 余烬币</b>。</p>" if complete else ""],
		actions, "BEYOND THE VEIL")
