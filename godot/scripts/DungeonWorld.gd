class_name DungeonWorld
extends Node3D
## 地下城「废弃圣堂」：4 个低语者 AI、箭矢/近战、双职业大招、命中特效。
## 对应 main.js createDungeon / createEnemy / updateDungeon / 战斗函数。

signal toast_requested(text: String)
signal dialog_requested(title: String, content: String, actions: Array, eyebrow: String)
signal dialog_closed
signal hud_changed
signal hit_flash
signal exit_requested

const COMBAT_PROFILE := {
	"archer": {"attack_range": 11.5, "ultimate_cast_range": 13.5, "ultimate_radius": 4.2, "ultimate_cooldown": 10.0},
	"warrior": {"attack_range": 2.4, "ultimate_cast_range": 0.0, "ultimate_radius": 5.5, "ultimate_cooldown": 10.0},
}

var player_position := Vector3(0, 0.05, 12.2)
var player_yaw := PI
var walk_phase := 0.0
var moving := false

var dungeon_obstacles: Array = []
var enemies: Array = []            # Enemy 字典
var projectiles: Array = []        # 特效/投射物字典
var flames: Array = []

var locked_enemy = null
var hovered_enemy = null
var attack_target = null
var attacking := false
var attack_time := 0.0
var attack_hit := false
var attack_cooldown := 0.0
var ultimate_active := false
var ultimate_time := 0.0
var ultimate_hit := false
var ultimate_cooldown := 0.0
var ultimate_target := Vector3.ZERO
var attack_range_time := 0.0
var attack_range_duration := 0.8

var move_marker: MeshInstance3D
var attack_range_marker: MeshInstance3D
var attack_range_mat: StandardMaterial3D
var _ring_mesh_unit: ArrayMesh        # inner .96 outer 1
var _ring_mesh_wide: ArrayMesh        # inner .78 outer 1
var _ring_mesh_target: ArrayMesh      # inner .48 outer .64

var main = null
var _elapsed := 0.0

func _ready() -> void:
	_build_dungeon()
	_build_markers()

# ---------------- 环节构建 ----------------

func _c(r: int, g: int, b: int) -> Color:
	return Color8(r, g, b)

func _d_obstacle(x: float, z: float, w: float, d: float) -> void:
	dungeon_obstacles.append({"x": x, "z": z, "w": w / 2.0, "d": d / 2.0})

func _flame(parent: Node3D, pos: Vector3, radius: float, base := 1.5) -> MeshInstance3D:
	var f := GeoBuilder.octahedron(parent, radius, GeoBuilder.mat(Color(0.82,0.58,0.24), {"emissive": Color(0.91,0.55,0.15), "emissive_intensity": 1.5, "unshaded": true}), pos, false)
	flames.append({"node": f, "phase": randf() * 9.0, "base": base, "light": null})
	return f

func _build_dungeon() -> void:
	Ambience.tiled_floor(self, 30, -0.15)
	# 外墙。
	for side in [-1, 1]:
		var z := -14.4
		while z <= 14.4:
			GeoBuilder.box(self, 0.6, 4.2, 1.4, _c(0x3a,0x41,0x38), Vector3(side * 13.5, 2, z))
			GeoBuilder.box(self, 0.5, 0.4, 1.6, _c(0x5a,0x55,0x41), Vector3(side * 13.6, 4.1, z))
			z += 1.6
	var x := -12.8
	while x <= 12.8:
		GeoBuilder.box(self, 1.6, 4.2, 0.6, _c(0x3a,0x41,0x38), Vector3(x, 2, -14.7))
		GeoBuilder.box(self, 1.6, 0.4, 0.5, _c(0x5a,0x55,0x41), Vector3(x, 4.1, -14.7))
		GeoBuilder.box(self, 1.6, 4.2, 0.6, _c(0x3a,0x41,0x38), Vector3(x, 2, 14.7))
		x += 1.6
	# 中殿柱。
	for side in [-1, 1]:
		for pz in [-9.0, -3.0, 3.0, 9.0]:
			Ambience.pillar(self, side * 4.8, pz, 4.2)
			_d_obstacle(side * 4.8, pz, 1.1, 1.1)
	# 侧翼长椅。
	for side in [-1, 1]:
		var pz := -10.5
		while pz <= 10.5:
			GeoBuilder.box(self, 2.2, 0.55, 0.55, _c(0x3f,0x3a,0x2c), Vector3(side * 9.2, 0.28, pz))
			_d_obstacle(side * 9.2, pz, 2.2, 0.55)
			pz += 3.0
	# 碎石。
	var rng := RandomNumberGenerator.new()
	rng.seed = 743
	var stone: Array[Color] = Ambience._stone_colors
	for i in range(28):
		var rx := (rng.randf() - 0.5) * 24
		var rz := (rng.randf() - 0.5) * 26
		if abs(rx) > 4 and abs(rx) < 7.5: continue
		var r := GeoBuilder.box(self, 0.2 + rng.randf() * 0.5, 0.12 + rng.randf() * 0.25, 0.2 + rng.randf() * 0.5, stone[i % 6], Vector3(rx, 0.05, rz))
		r.rotation.y = rng.randf() * TAU
	# 祭坛。
	var altar := Node3D.new()
	altar.position = Vector3(0, 0, -12.8)
	add_child(altar)
	GeoBuilder.box(altar, 3, 0.6, 1.6, _c(0x4c,0x46,0x33), Vector3(0, 0.3, 0))
	GeoBuilder.box(altar, 2.6, 0.25, 1.2, _c(0x6b,0x61,0x44), Vector3(0, 0.72, 0))
	_flame(altar, Vector3(0, 1.1, 0), 0.28, 2.0)
	var altar_light := OmniLight3D.new()
	altar_light.position = Vector3(0, 1.5, -12.8)
	altar_light.light_color = Color(1.0, 0.54, 0.24)
	altar_light.light_energy = 3.0
	altar_light.omni_range = 9.0
	add_child(altar_light)
	flames.append({"node": null, "phase": 0.0, "base": 0.0, "light": altar_light})
	_d_obstacle(0, -12.8, 3, 1.6)
	# 铁制烛台。
	for pos in [[-7, -12], [7, -12], [-7, 12], [7, 12]]:
		Ambience.candelabra(self, pos[0], pos[1], 1.7, true)
	# 出口铁门。
	var gate := Node3D.new()
	gate.position = Vector3(0, 0, 14.2)
	add_child(gate)
	for gx in [-1.3, 0.0, 1.3]:
		GeoBuilder.box(gate, 0.12, 3.2, 0.12, _c(0x44,0x40,0x30), Vector3(gx, 1.6, 0))
	GeoBuilder.box(gate, 3, 0.12, 0.16, _c(0x6b,0x61,0x44), Vector3(0, 3.1, 0))
	# 雾与尘埃。
	for i in range(4):
		Ambience.make_fog(self, 32, 0.12 + i * 0.3, 0.09)
	Ambience.make_motes(self, 105, 28, Color(0.62,0.69,0.54))

func _make_ring_mesh(inner: float, outer: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var a0 := float(i) / segments * TAU
		var a1 := float(i + 1) / segments * TAU
		var i0 := Vector3(cos(a0) * inner, 0, sin(a0) * inner)
		var o0 := Vector3(cos(a0) * outer, 0, sin(a0) * outer)
		var i1 := Vector3(cos(a1) * inner, 0, sin(a1) * inner)
		var o1 := Vector3(cos(a1) * outer, 0, sin(a1) * outer)
		st.add_vertex(i0); st.add_vertex(o0); st.add_vertex(i1)
		st.add_vertex(i1); st.add_vertex(o0); st.add_vertex(o1)
	return st.commit()

func _effect_material(color: Color, opacity: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.albedo_color.a = opacity
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.2
	return m

func _build_markers() -> void:
	_ring_mesh_unit = _make_ring_mesh(0.96, 1.0, 64)
	_ring_mesh_wide = _make_ring_mesh(0.78, 1.0, 56)
	_ring_mesh_target = _make_ring_mesh(0.48, 0.64, 40)
	attack_range_mat = _effect_material(Color(0.847, 0.741, 0.525), 0.42)
	attack_range_marker = MeshInstance3D.new()
	attack_range_marker.mesh = _ring_mesh_unit
	attack_range_marker.material_override = attack_range_mat
	attack_range_marker.position.y = 0.035
	attack_range_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	attack_range_marker.visible = false
	add_child(attack_range_marker)
	move_marker = MeshInstance3D.new()
	move_marker.mesh = _ring_mesh_unit
	move_marker.material_override = _effect_material(Color(0.85, 0.74, 0.53), 0.8)
	move_marker.position.y = 0.02
	move_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	move_marker.visible = false
	add_child(move_marker)

# ---------------- 敌人 ----------------

func create_enemy(x: float, z: float) -> Dictionary:
	var root := Node3D.new()
	root.position = Vector3(x, 0, z)
	add_child(root)
	var rig := Node3D.new()
	root.add_child(rig)
	var torso := Node3D.new()
	torso.position = Vector3(0, 1.25, 0)
	torso.rotation.x = 0.32
	rig.add_child(torso)
	var mats: Array[Material] = []
	var em := func(color: Color) -> Material:
		var m := GeoBuilder.mat(color).duplicate()
		mats.append(m)
		return m
	GeoBuilder.cylinder(torso, 0.42, 0.5, 0.78, em.call(Color8(0x2b,0x22,0x30)), Vector3(0, 0.05, 0), 6)
	GeoBuilder.box(torso, 0.66, 0.4, 0.45, em.call(Color8(0x3a,0x2d,0x40)), Vector3(0, 0.18, 0.02))
	GeoBuilder.cylinder(torso, 0.34, 0.46, 0.5, em.call(Color8(0x24,0x1a,0x2c)), Vector3(0, 0.52, -0.02), 5)
	var head := Node3D.new()
	head.position = Vector3(0, 0.5, 0.06)
	torso.add_child(head)
	GeoBuilder.box(head, 0.34, 0.3, 0.3, em.call(Color8(0x8a,0x7a,0x8c)), Vector3(0, 0, 0.02))
	for side in [-1, 1]:
		GeoBuilder.box(head, 0.06, 0.05, 0.04, GeoBuilder.mat(Color8(0xff,0x5b,0x3c), {"emissive": Color8(0xff,0x5b,0x3c), "emissive_intensity": 2.0}), Vector3(side * 0.1, -0.02, 0.17))
	var arms := {}
	var legs := {}
	for pair in [["left", -1.0], ["right", 1.0]]:
		var sname: String = pair[0]
		var side: float = pair[1]
		var upper := Node3D.new()
		upper.position = Vector3(side * 0.42, 0.12, 0)
		torso.add_child(upper)
		GeoBuilder.box(upper, 0.2, 0.5, 0.22, em.call(Color8(0x2b,0x22,0x30)), Vector3(0, -0.22, 0))
		var lower := Node3D.new()
		lower.position = Vector3(0, -0.48, 0)
		upper.add_child(lower)
		GeoBuilder.box(lower, 0.19, 0.46, 0.21, em.call(Color8(0x24,0x1a,0x2c)), Vector3(0, -0.2, 0))
		for i in range(3):
			var claw := GeoBuilder.box(lower, 0.02, 0.18, 0.02, em.call(Color8(0xd8,0xc2,0xa0)), Vector3((i - 1) * 0.05, -0.55, 0.05))
			claw.rotation.x = 0.4
		arms[sname] = {"upper": upper, "lower": lower}
		var thigh := Node3D.new()
		thigh.position = Vector3(side * 0.2, 0.85, 0)
		rig.add_child(thigh)
		GeoBuilder.box(thigh, 0.22, 0.5, 0.24, em.call(Color8(0x1f,0x18,0x24)), Vector3(0, -0.22, 0))
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.5, 0)
		thigh.add_child(knee)
		GeoBuilder.box(knee, 0.22, 0.5, 0.24, em.call(Color8(0x1a,0x14,0x1e)), Vector3(0, -0.22, 0))
		legs[sname] = {"thigh": thigh, "knee": knee}
	var eye := OmniLight3D.new()
	eye.position = Vector3(0, 1.62, 0.18)
	eye.light_color = Color8(0xff,0x6a,0x4a)
	eye.light_energy = 1.2
	eye.omni_range = 3.0
	root.add_child(eye)
	# 血条（billboard）。
	var hp_bar_bg := MeshInstance3D.new()
	var bg_quad := QuadMesh.new()
	bg_quad.size = Vector2(0.9, 0.1)
	hp_bar_bg.mesh = bg_quad
	hp_bar_bg.material_override = _effect_material(Color8(0x18,0x10,0x18), 0.9)
	hp_bar_bg.position = Vector3(0, 2.35, 0.35)
	hp_bar_bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(hp_bar_bg)
	var hp_bar := MeshInstance3D.new()
	var hp_quad := QuadMesh.new()
	hp_quad.size = Vector2(0.86, 0.06)
	hp_bar.mesh = hp_quad
	hp_bar.material_override = _effect_material(Color8(0xe0,0x5a,0x4a), 0.95)
	hp_bar.position = Vector3(0, 2.35, 0.36)
	hp_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(hp_bar)
	for bar in [hp_bar_bg, hp_bar]:
		(bar.material_override as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var target_ring := MeshInstance3D.new()
	target_ring.mesh = _ring_mesh_target
	target_ring.material_override = _effect_material(Color8(0xff,0x3f,0x32), 0.9)
	target_ring.position.y = 0.035
	target_ring.visible = false
	target_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(target_ring)
	return {
		"root": root, "rig": rig, "torso": torso, "head": head, "arms": arms, "legs": legs,
		"eye": eye, "hp_bar": hp_bar, "hp_bar_bg": hp_bar_bg, "target_ring": target_ring,
		"mats": mats,
		"hp": 60.0, "max_hp": 60.0, "alive": true,
		"yaw": 0.0, "state": "idle", "state_time": 0.0,
		"attack_cooldown": 0.0, "hit_flash": 0.0, "hit_stun": 0.0, "hit_stun_duration": 0.22,
		"knockback": Vector3.ZERO,
	}

func spawn_enemies() -> void:
	for pos in [[-5.8, 2.0], [5.8, 2.0], [-4.8, -6.5], [4.8, -6.5]]:
		enemies.append(create_enemy(pos[0], pos[1]))

func reset_dungeon() -> void:
	for e in enemies:
		e.root.queue_free()
	enemies.clear()
	_clear_projectiles()
	spawn_enemies()
	player_position = Vector3(0, 0.05, 12.2)
	player_yaw = PI
	locked_enemy = null
	hovered_enemy = null
	attack_target = null
	attacking = false
	attack_time = 0.0
	attack_cooldown = 0.0
	ultimate_active = false
	ultimate_time = 0.0
	ultimate_hit = false
	ultimate_cooldown = 0.0
	attack_range_time = 0.0
	attack_range_marker.visible = false
	move_marker.visible = false
	hud_changed.emit()

# ---------------- 寻路与移动 ----------------

func dungeon_walkable(x: float, z: float) -> bool:
	if x < -13 or x > 13 or z < -14.2 or z > 14.2: return false
	for o in dungeon_obstacles:
		if abs(x - o.x) < o.w + 0.32 and abs(z - o.z) < o.d + 0.32:
			return false
	return true

func set_dungeon_path(target: Vector3) -> void:
	# 本关无复杂迷宫，直线寻路（对应原作 setDungeonPath）。
	var goal := Vector3(target.x, 0, target.z)
	# 朝目标逐步推进时由 dungeon_walkable 阻挡，路径只存终点。
	var dir := goal - player_position
	dir.y = 0
	if dir.length() < 0.1:
		return
	# 检查直线可达；不可达时按轴向绕行插入中间点。
	var steps := int(ceil(dir.length() / 0.4))
	var blocked := false
	for i in range(1, steps + 1):
		var p := player_position + dir * (float(i) / steps)
		if not dungeon_walkable(p.x, p.z):
			blocked = true
			break
	if blocked:
		# 绕中轴走：先到通道 x≈0 或 x≈±7。
		var mid := Vector3(0 if abs(player_position.x) < 7.0 else sign(player_position.x) * 7.0, 0, goal.z)
		if dungeon_walkable(mid.x, mid.z) and _line_clear(player_position, mid) and _line_clear(mid, goal):
			move_marker.position = Vector3(mid.x, 0.02, mid.z)
			move_marker.visible = true
			# 分两段。
			var via := mid
			_pending_path_goal = goal
			_path = [via, goal]
			return
		return
	_path = [goal]
	move_marker.position = Vector3(goal.x, 0.02, goal.z)
	move_marker.visible = true

var _path: Array = []
var _pending_path_goal := Vector3.ZERO

func _line_clear(a: Vector3, b: Vector3) -> bool:
	var dir := b - a
	var steps := int(ceil(dir.length() / 0.4))
	for i in range(1, steps + 1):
		var p := a + dir * (float(i) / steps)
		if not dungeon_walkable(p.x, p.z): return false
	return true

# ---------------- 点击与锁定 ----------------

func handle_click(camera: Camera3D) -> void:
	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	# 若点到敌人则锁定。
	var hit = _ray_pick_enemy(from, dir)
	if hit != null and hit != locked_enemy:
		lock_enemy(hit)
	player_attack()

func handle_hover(camera: Camera3D) -> void:
	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	hovered_enemy = _ray_pick_enemy(from, dir)

func _ray_pick_enemy(from: Vector3, dir: Vector3):
	var best = null
	var best_dist := INF
	for e in enemies:
		if not e.alive: continue
		var center: Vector3 = e.root.position + Vector3(0, 1.1, 0)
		var to := center - from
		var along := to.dot(dir)
		if along < 0: continue
		var perp := (to - dir * along).length()
		if perp < 0.9 and along < best_dist:
			best = e
			best_dist = along
	return best

func lock_enemy(enemy, notify := true) -> void:
	if enemy == null or not enemy.alive: return
	for e in enemies:
		e.target_ring.visible = e == enemy
	locked_enemy = enemy
	if notify:
		toast_requested.emit("锁定：低语者 · 左键攻击")

func nearest_enemy(max_range := INF, front_only := false):
	var forward := Vector3(sin(player_yaw), 0, cos(player_yaw))
	var best = null
	var best_distance: float = max_range
	for e in enemies:
		if not e.alive: continue
		var to: Vector3 = e.root.position - player_position
		to.y = 0
		var distance := to.length()
		if distance > best_distance: continue
		if front_only and to.normalized().dot(forward) < 0.15: continue
		best = e
		best_distance = distance
	return best

func show_attack_range(range_val: float, color: Color, duration := 0.8) -> void:
	attack_range_marker.position = Vector3(player_position.x, 0.035, player_position.z)
	attack_range_marker.scale = Vector3.ONE * range_val
	attack_range_mat.albedo_color = color
	attack_range_mat.albedo_color.a = 0.42
	attack_range_mat.emission = color
	attack_range_duration = duration
	attack_range_time = duration
	attack_range_marker.visible = true

# ---------------- 玩家战斗 ----------------

func player_attack() -> bool:
	var profile: Dictionary = COMBAT_PROFILE[GameState.save.selected]
	var is_archer := GameState.is_archer()
	show_attack_range(profile.attack_range, Color8(0x9f,0xcb,0xb0) if is_archer else Color8(0xd8,0xa3,0x5f))
	if attacking or ultimate_active or attack_cooldown > 0: return false
	var target = locked_enemy
	if (target == null or not target.alive) and is_archer:
		target = nearest_enemy(profile.attack_range, true)
	if target != null and target.alive and target.root.position.distance_to(player_position) > profile.attack_range:
		toast_requested.emit("目标超出弓箭射程" if is_archer else "目标不在战锤攻击范围内")
		return false
	attack_target = target if (target != null and target.alive) else null
	attacking = true
	attack_time = 0.0
	attack_hit = false
	_path.clear()
	move_marker.visible = false
	AudioBus.play_tone(520 if is_archer else 90, 0.18)
	return true

func player_ultimate() -> bool:
	if attacking or ultimate_active: return false
	if ultimate_cooldown > 0:
		toast_requested.emit("大招冷却中 · %d 秒" % int(ceil(ultimate_cooldown)))
		return false
	var is_archer := GameState.is_archer()
	var profile: Dictionary = COMBAT_PROFILE[GameState.save.selected]
	var target = locked_enemy if (locked_enemy != null and locked_enemy.alive) else nearest_enemy(profile.ultimate_cast_range if profile.ultimate_cast_range > 0 else INF)
	if is_archer and target == null:
		toast_requested.emit("月蚀箭雨需要一个目标")
		return false
	if is_archer and target.root.position.distance_to(player_position) > profile.ultimate_cast_range:
		show_attack_range(profile.ultimate_cast_range, Color8(0x79,0xd3,0xc4), 1.0)
		toast_requested.emit("目标超出月蚀箭雨的施法范围")
		return false
	ultimate_target = target.root.position if is_archer else player_position
	ultimate_target.y = 0
	ultimate_active = true
	ultimate_time = 0.0
	ultimate_hit = false
	ultimate_cooldown = profile.ultimate_cooldown
	_path.clear()
	move_marker.visible = false
	show_attack_range(profile.ultimate_cast_range if is_archer and profile.ultimate_cast_range > 0 else profile.ultimate_radius,
		Color8(0x79,0xd3,0xc4) if is_archer else Color8(0xff,0x9b,0x4a), 1.05)
	_spawn_effect_ring(ultimate_target, Color8(0x65,0xc9,0xba) if is_archer else Color8(0xff,0x8b,0x3d), profile.ultimate_radius, 0.72)
	AudioBus.play_tone(420 if is_archer else 72, 0.55, 0.08)
	toast_requested.emit("月蚀箭雨" if is_archer else "余烬震击")
	return true

func do_player_damage() -> void:
	var is_archer := GameState.is_archer()
	var damage: int = (14 if is_archer else 22) + GameState.save.upgrade * 4
	if is_archer:
		var char_node = main.active_character() if main else null
		var from: Vector3 = (char_node.position if char_node else player_position) + Vector3(0, 1.3 * 0.85, 0)
		var range_val: float = COMBAT_PROFILE.archer.attack_range
		var target_enemy = attack_target if (attack_target != null and attack_target.alive) else nearest_enemy(range_val, true)
		var fwd := Vector3(sin(player_yaw), 0, cos(player_yaw))
		var target: Vector3 = target_enemy.root.position if target_enemy else from + fwd * range_val
		target.y = 1.3 * 0.85
		_spawn_arrow(from, target, range_val, damage)
	else:
		var fwd := Vector3(sin(player_yaw), 0, cos(player_yaw))
		var origin := player_position
		var range_val: float = COMBAT_PROFILE.warrior.attack_range
		for e in enemies:
			if not e.alive: continue
			var to: Vector3 = e.root.position - origin
			to.y = 0
			var dist := to.length()
			if dist < range_val and to.normalized().dot(fwd) > 0.1:
				damage_enemy(e, damage, origin, 5.5)
		# 落地尘土。
		var puff := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.3; sphere.height = 0.6; sphere.radial_segments = 6; sphere.rings = 4
		puff.mesh = sphere
		puff.material_override = _effect_material(Color8(0xb9,0xa7,0x7a), 0.5)
		puff.position = origin + fwd * 1.4 + Vector3(0, 0.2, 0)
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(puff)
		projectiles.append({"mesh": puff, "life": 0.35, "total": 0.35, "kind": "puff"})

func do_ultimate_impact() -> void:
	var is_archer := GameState.is_archer()
	var profile: Dictionary = COMBAT_PROFILE[GameState.save.selected]
	var center: Vector3 = ultimate_target if is_archer else player_position
	center.y = 0
	var damage: int = (34 if is_archer else 46) + GameState.save.upgrade * (5 if is_archer else 6)
	for e in enemies:
		if e.alive and e.root.position.distance_to(center) <= profile.ultimate_radius:
			damage_enemy(e, damage, player_position if is_archer else center, 3.2 if is_archer else 8.0)
	if is_archer:
		_spawn_column(center, Color8(0x8d,0xe5,0xd3), 7.0, 0.65)
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for i in range(16):
			var angle := rng.randf() * TAU
			var radius: float = sqrt(rng.randf()) * profile.ultimate_radius
			var arrow := GeoBuilder.box(self, 0.035, 1.05, 0.035, Color8(0xb7,0xf0,0xdf), Vector3(center.x + cos(angle) * radius, 5.5 + rng.randf() * 2.5, center.z + sin(angle) * radius))
			arrow.material_override = _effect_material(Color8(0xb7,0xf0,0xdf), 0.95)
			arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			projectiles.append({"mesh": arrow, "life": 1.0 + i * 0.025, "total": 1.0, "kind": "rain_arrow", "delay": i * 0.025, "velocity": 15.0 + rng.randf() * 5.0})
		_spawn_effect_ring(center, Color8(0x9c,0xe8,0xd6), profile.ultimate_radius, 0.65)
		_spawn_effect_ring(center, Color8(0xd8,0xff,0xf2), profile.ultimate_radius * 0.65, 0.45)
		if main: main.camera_rig.camera_shake = 0.16
		AudioBus.play_tone(760, 0.45, 0.05)
	else:
		_spawn_effect_ring(center, Color8(0xff,0x9a,0x4f), profile.ultimate_radius, 0.7)
		_spawn_effect_ring(center, Color8(0xff,0xcf,0x75), profile.ultimate_radius * 0.72, 0.5)
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for i in range(22):
			var angle := i / 22.0 * TAU + rng.randf() * 0.18
			var ember := GeoBuilder.octahedron(self, 0.09 + rng.randf() * 0.08, _effect_material(Color8(0xff,0xa3,0x3d) if i % 2 else Color8(0xff,0xd1,0x7a), 0.85), Vector3(center.x, 0.15, center.z), false)
			projectiles.append({
				"mesh": ember, "life": 0.55 + rng.randf() * 0.35, "total": 0.9, "kind": "ultimate_ember",
				"velocity": Vector3(cos(angle) * (4 + rng.randf() * 5), 2 + rng.randf() * 4, sin(angle) * (4 + rng.randf() * 5)),
			})
		var light := OmniLight3D.new()
		light.position = Vector3(center.x, 1.2, center.z)
		light.light_color = Color8(0xff,0x7a,0x32)
		light.light_energy = 6.0
		light.omni_range = 13.0
		add_child(light)
		projectiles.append({"mesh": light, "life": 0.45, "total": 0.45, "kind": "ultimate_light"})
		if main: main.camera_rig.camera_shake = 0.32
		AudioBus.play_tone(65, 0.65, 0.12)

func damage_enemy(enemy, damage: int, source := Vector3.ZERO, force := 3.5) -> void:
	if not enemy.alive: return
	var src := source if source != Vector3.ZERO else player_position
	var direction: Vector3 = enemy.root.position - src
	direction.y = 0
	if direction.length_squared() < 0.01:
		direction = Vector3(sin(player_yaw), 0, cos(player_yaw))
	direction = direction.normalized()
	enemy.knockback = direction * force
	enemy.hit_stun = 0.18 + min(force * 0.018, 0.16)
	enemy.hit_stun_duration = enemy.hit_stun
	enemy.hp -= damage
	enemy.hit_flash = 0.18
	var ratio: float = max(0.0, enemy.hp / enemy.max_hp)
	enemy.hp_bar.scale = Vector3(ratio, 1, 1)
	enemy.hp_bar.position.x = -(1.0 - ratio) * 0.43
	_spawn_hit_effect(enemy, direction, force)
	if main: main.camera_rig.camera_shake = max(main.camera_rig.camera_shake, min(0.13, 0.025 + force * 0.012))
	hit_flash.emit()
	AudioBus.play_tone(220, 0.1, 0.05)
	if enemy.hp <= 0:
		enemy.alive = false
		enemy.root.visible = false
		if locked_enemy == enemy: locked_enemy = null
		if hovered_enemy == enemy: hovered_enemy = null
		if attack_target == enemy: attack_target = null
		var left := 0
		for e in enemies:
			if e.alive: left += 1
		hud_changed.emit()
		if left == 0:
			GameState.add_gold(90)
			hud_changed.emit()
			toast_requested.emit("圣堂已净化 · +90 余烬币。按 E 或点击「撤离圣堂」返回庇护所。")
			dialog_requested.emit("圣堂已净化",
				"<p>低语者的呢喃终于消散。祭坛的火光重新亮起，通往庇护所的门已开启。</p>",
				[{"label": "撤离圣堂", "run": func(): dialog_closed.emit(); exit_requested.emit()}],
				"CHAPTER I · CLEARED")
		else:
			toast_requested.emit("低语者倒下 · 剩余 %d" % left)

func enemy_attack(enemy) -> void:
	var dist: float = enemy.root.position.distance_to(player_position)
	if dist < 1.9:
		GameState.set_hp(maxi(0, GameState.save.hp - 7))
		hud_changed.emit()
		hit_flash.emit()
		AudioBus.play_tone(140, 0.18, 0.07)
		if GameState.save.hp <= 0:
			GameState.set_hp(100)
			hud_changed.emit()
			toast_requested.emit("你倒在了圣堂中……被余火送回庇护所。")
			exit_requested.emit()

# ---------------- 特效 ----------------

func _spawn_effect_ring(position: Vector3, color: Color, max_radius: float, duration := 0.7) -> void:
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh_wide
	ring.material_override = _effect_material(color, 0.8)
	ring.position = Vector3(position.x, 0.05, position.z)
	ring.scale = Vector3.ONE * 0.2
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	projectiles.append({"mesh": ring, "life": duration, "total": duration, "kind": "ring", "max_radius": max_radius})

func _spawn_column(center: Vector3, color: Color, height: float, duration: float) -> void:
	var col := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.8
	cyl.bottom_radius = 1.5
	cyl.height = height
	cyl.radial_segments = 16
	cyl.cap_top = false
	cyl.cap_bottom = false
	col.mesh = cyl
	col.material_override = _effect_material(color, 0.32)
	col.position = Vector3(center.x, height / 2.0, center.z)
	col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(col)
	projectiles.append({"mesh": col, "life": duration, "total": duration, "kind": "column"})

func _spawn_arrow(from: Vector3, target: Vector3, max_distance: float, damage: int) -> void:
	var arrow := GeoBuilder.box(self, 0.7, 0.03, 0.03, Color8(0xd7,0xc5,0x94))
	arrow.material_override = _effect_material(Color8(0xd7,0xc5,0x94), 1.0)
	arrow.position = from
	var dir := target - from
	dir.y = 0
	dir = dir.normalized()
	arrow.look_at(from + dir, Vector3.UP)
	arrow.rotate_y(PI / 2)
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	projectiles.append({"mesh": arrow, "damage": damage, "life": max_distance / 18.0, "total": 1.0, "kind": "arrow", "dir": dir})

func _spawn_hit_effect(enemy, direction: Vector3, force: float) -> void:
	var is_archer := GameState.is_archer()
	var color := Color8(0x9f,0xe7,0xcf) if is_archer else Color8(0xff,0xb1,0x5b)
	var center: Vector3 = enemy.root.position
	_spawn_effect_ring(center, color, 0.72 + force * 0.045, 0.25)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(8):
		var angle := rng.randf() * TAU
		var shard := GeoBuilder.octahedron(self, 0.045 + rng.randf() * 0.055, _effect_material(color if i % 2 else Color8(0xff,0xe0,0xa0), 0.9), Vector3(center.x, 0.75 + rng.randf() * 0.75, center.z), false)
		var radial := Vector3(cos(angle), 0.35 + rng.randf() * 0.8, sin(angle))
		var velocity := radial * (1.7 + rng.randf() * 2.2) + direction * (2.2 + force * 0.22)
		projectiles.append({"mesh": shard, "life": 0.32, "total": 0.32, "kind": "shard", "velocity": velocity})
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22; sphere.height = 0.44; sphere.radial_segments = 6; sphere.rings = 4
	flash.mesh = sphere
	flash.material_override = _effect_material(Color8(0xff,0xf0,0xc0), 0.8)
	flash.position = center + Vector3(0, 1.1, 0)
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flash)
	projectiles.append({"mesh": flash, "life": 0.16, "total": 0.16, "kind": "burst"})

func _clear_projectiles() -> void:
	for p in projectiles:
		if p.mesh is Node: p.mesh.queue_free()
	projectiles.clear()

# ---------------- 帧更新 ----------------

func update_dungeon(delta: float, camera_rig: CameraRig) -> void:
	_elapsed += delta
	var is_archer := GameState.is_archer()
	var profile: Dictionary = COMBAT_PROFILE[GameState.save.selected]
	# 攻击范围圈。
	if attack_range_time > 0:
		attack_range_time = max(0.0, attack_range_time - delta)
		attack_range_marker.position = Vector3(player_position.x, 0.035, player_position.z)
		attack_range_mat.albedo_color.a = 0.42 * (attack_range_time / attack_range_duration)
		attack_range_marker.visible = true
	else:
		attack_range_marker.visible = false
	if ultimate_cooldown > 0:
		ultimate_cooldown = max(0.0, ultimate_cooldown - delta)
	# 玩家移动。
	var velocity := Vector3.ZERO
	var ui_blocked: bool = main != null and main.ui != null and main.ui.is_dialog_open()
	if not ui_blocked:
		var up := Input.is_action_pressed("move_up")
		var down := Input.is_action_pressed("move_down")
		var left := Input.is_action_pressed("move_left")
		var right := Input.is_action_pressed("move_right")
		if up or down or left or right:
			_path.clear()
			move_marker.visible = false
			var forward := Vector3(-sin(camera_rig.cam_yaw), 0, -cos(camera_rig.cam_yaw))
			var rightv := Vector3(cos(camera_rig.cam_yaw), 0, -sin(camera_rig.cam_yaw))
			velocity += forward * (float(up) - float(down))
			velocity += rightv * (float(right) - float(left))
		elif not _path.is_empty():
			var wp: Vector3 = _path[0]
			if player_position.distance_to(wp) < 0.12:
				_path.remove_at(0)
				if not _path.is_empty(): wp = _path[0]
			if not _path.is_empty():
				velocity = wp - player_position
			else:
				move_marker.visible = false
	if velocity.length_squared() > 0.001 and not attacking and not ultimate_active:
		var speed: float = GameState.class_data().walk_speed * (1.5 if Input.is_action_pressed("run") else 1.0)
		velocity = velocity.normalized() * min(speed * delta, velocity.length() if not _path.is_empty() else INF)
		var nx := player_position.x + velocity.x
		var nz := player_position.z + velocity.z
		if dungeon_walkable(nx, player_position.z): player_position.x = nx
		if dungeon_walkable(player_position.x, nz): player_position.z = nz
		var target_yaw := atan2(velocity.x, velocity.z)
		player_yaw += atan2(sin(target_yaw - player_yaw), cos(target_yaw - player_yaw)) * min(1.0, delta * 14)
		walk_phase += velocity.length() * 11
		moving = true
	else:
		moving = false
	var active = main.active_character() if main else null
	if active:
		active.position = player_position
		# 锁定敌人时面向敌人。
		if locked_enemy != null and locked_enemy.alive:
			var to: Vector3 = locked_enemy.root.position - player_position
			var face_yaw := atan2(to.x, to.z)
			player_yaw += atan2(sin(face_yaw - player_yaw), cos(face_yaw - player_yaw)) * min(1.0, delta * 10)
		active.rotation.y = player_yaw
		var pose := {"type": "idle"}
		if ultimate_active: pose = {"type": "ultimate", "time": ultimate_time}
		elif attacking: pose = {"type": "attack", "time": attack_time}
		elif moving: pose = {"type": "walk", "step": walk_phase}
		active.animate_pose(delta, _elapsed, pose)
	# 大招时间线。
	if ultimate_active:
		ultimate_time += delta
		if not ultimate_hit and ultimate_time >= 0.68:
			ultimate_hit = true
			do_ultimate_impact()
		if ultimate_time >= (1.35 if is_archer else 1.2):
			ultimate_active = false
			ultimate_time = 0.0
	# 攻击时间线。
	if attacking:
		attack_time += delta
		if not attack_hit and attack_time >= (0.5 if is_archer else 0.55):
			attack_hit = true
			do_player_damage()
		if attack_time >= (0.85 if is_archer else 0.8):
			attacking = false
			attack_cooldown = 0.15 if is_archer else 0.25
			attack_target = null
	elif attack_cooldown > 0:
		attack_cooldown -= delta
	# 敌人 AI。
	for e in enemies:
		if not e.alive: continue
		e.state_time += delta
		e.attack_cooldown -= delta
		if e.hit_flash > 0: e.hit_flash -= delta
		if e.hit_stun > 0: e.hit_stun = max(0.0, e.hit_stun - delta)
		e.torso.rotation.x = 0.32
		e.arms.left.upper.rotation.z = 0
		e.arms.right.upper.rotation.z = 0
		# 击退。
		if e.knockback.length_squared() > 0.0025:
			var step: Vector3 = e.knockback * delta
			var enx: float = e.root.position.x + step.x
			var enz: float = e.root.position.z + step.z
			if dungeon_walkable(enx, e.root.position.z): e.root.position.x = enx
			else: e.knockback.x = 0
			if dungeon_walkable(e.root.position.x, enz): e.root.position.z = enz
			else: e.knockback.z = 0
			e.knockback *= exp(-9.0 * delta)
		else:
			e.knockback = Vector3.ZERO
		var to_player: Vector3 = player_position - e.root.position
		to_player.y = 0
		var dist := to_player.length()
		var target_yaw := atan2(to_player.x, to_player.z)
		e.yaw += atan2(sin(target_yaw - e.yaw), cos(target_yaw - e.yaw)) * min(1.0, delta * 6)
		e.root.rotation.y = e.yaw
		if e.hit_stun > 0:
			var recoil: float = e.hit_stun / e.hit_stun_duration
			e.state = "hit"
			e.attack_cooldown = max(e.attack_cooldown, 0.3)
			e.torso.rotation.x = 0.32 - recoil * 0.48
			e.arms.left.upper.rotation.x = 0.75 * recoil
			e.arms.right.upper.rotation.x = 0.75 * recoil
			e.arms.left.upper.rotation.z = -0.35 * recoil
			e.arms.right.upper.rotation.z = 0.35 * recoil
		elif dist > 1.6:
			var step2: float = min(1.4 * delta, dist - 1.4)
			var dir2: Vector3 = to_player.normalized() * step2
			var n2x: float = e.root.position.x + dir2.x
			var n2z: float = e.root.position.z + dir2.z
			if dungeon_walkable(n2x, n2z):
				e.root.position.x = n2x
				e.root.position.z = n2z
			elif dungeon_walkable(e.root.position.x + dir2.x, e.root.position.z):
				e.root.position.x += dir2.x
			elif dungeon_walkable(e.root.position.x, e.root.position.z + dir2.z):
				e.root.position.z += dir2.z
			e.state = "chase"
			e.arms.left.upper.rotation.x = sin(e.state_time * 8) * 0.4
			e.arms.right.upper.rotation.x = -sin(e.state_time * 8) * 0.4
		else:
			e.state = "attack"
			e.arms.left.upper.rotation.x = -1.1 + sin(e.state_time * 10) * 0.15
			e.arms.right.upper.rotation.x = -1.1 - sin(e.state_time * 10) * 0.15
			if e.attack_cooldown <= 0:
				enemy_attack(e)
				e.attack_cooldown = 1.1
		# 受击闪白。
		for m in e.mats:
			if m is StandardMaterial3D:
				var sm := m as StandardMaterial3D
				if e.hit_flash > 0:
					if not sm.emission_enabled:
						sm.emission_enabled = true
					sm.emission = Color(1.0, 0.33, 0.2)
					sm.emission_energy_multiplier = 1.2
				else:
					sm.emission_enabled = false
					sm.emission_energy_multiplier = 1.0
		e.eye.light_energy = 1.6 if e.state == "attack" else 1.0
		if e.target_ring.visible:
			e.target_ring.scale = Vector3.ONE * (1.0 + sin(_elapsed * 7.0) * 0.1)
	# 火焰闪烁。
	for f in flames:
		var flicker := 1.0 + sin(_elapsed * 11.0 + f.phase) * 0.14 + sin(_elapsed * 23.0 + f.phase * 1.7) * 0.07
		if f.node:
			f.node.scale = Vector3(1, f.base * 0.55 * flicker, 1)
		if f.light:
			f.light.light_energy = 3.0 * flicker
	# 移动标记。
	if move_marker.visible:
		move_marker.scale = Vector3.ONE * (1.0 + sin(_elapsed * 6.0) * 0.12)
	_update_projectiles(delta)

func _update_projectiles(delta: float) -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var p: Dictionary = projectiles[i]
		p.life -= delta
		var kind: String = p.get("kind", "")
		match kind:
			"arrow":
				p.mesh.position += p.dir * 18.0 * delta
				p.mesh.rotate_z(delta * 30.0)
				for e in enemies:
					if not e.alive: continue
					var epos: Vector3 = e.root.position
					epos.y = p.mesh.position.y
					if p.mesh.position.distance_to(epos) < 1.0:
						var impact_source: Vector3 = e.root.position - p.dir
						damage_enemy(e, p.damage, impact_source, 3.8)
						p.life = 0
						break
			"ring":
				var progress: float = clampf(1.0 - p.life / p.total, 0.0, 1.0)
				var s: float = lerpf(0.2, p.max_radius, smoothstep(0.0, 1.0, progress))
				p.mesh.scale = Vector3.ONE * s
				(p.mesh.material_override as StandardMaterial3D).albedo_color.a = max(0.0, p.life / p.total) * 0.8
			"column":
				var ratio: float = max(0.0, p.life / p.total)
				(p.mesh.material_override as StandardMaterial3D).albedo_color.a = ratio * 0.32
				p.mesh.scale.x = 1.0 + (1.0 - ratio) * 0.45
				p.mesh.scale.z = p.mesh.scale.x
			"rain_arrow":
				p.delay -= delta
				p.mesh.visible = p.delay <= 0
				if p.delay <= 0:
					p.mesh.position.y -= p.velocity * delta
					if p.mesh.position.y <= 0.08: p.life = 0
			"ultimate_ember", "shard":
				p.mesh.position += p.velocity * delta
				p.velocity.y -= 8.5 * delta
				p.mesh.rotation.x += delta * 10.0
				p.mesh.rotation.z += delta * 8.0
				(p.mesh.material_override as StandardMaterial3D).albedo_color.a = max(0.0, p.life / p.total)
			"burst":
				var prog: float = clampf(1.0 - p.life / p.total, 0.0, 1.0)
				p.mesh.scale = Vector3.ONE * (1.0 + prog * 2.4)
				(p.mesh.material_override as StandardMaterial3D).albedo_color.a = max(0.0, p.life / p.total) * 0.8
			"ultimate_light":
				p.mesh.light_energy = 6.0 * max(0.0, p.life / p.total)
			"puff":
				p.mesh.scale *= 1.0 + delta * 6.0
				(p.mesh.material_override as StandardMaterial3D).albedo_color.a = max(0.0, p.life / 0.35)
		if p.life <= 0:
			p.mesh.queue_free()
			projectiles.remove_at(i)

func exit_dungeon() -> void:
	exit_requested.emit()
