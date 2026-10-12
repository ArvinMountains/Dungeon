class_name Overworld
extends Node3D
## 野外大地图（主城外）：
## - 两种生物群系：北方山地（岩石/灰狼）与南方森林（树木/鹿兔/野猪）。
## - 昼夜光照由 Main 的 SkyDome 全局驱动；夜幕下火把（T 手持 / G 放置）是主要光源。
## - 动物生态：巡逻/觅食/受惊逃跑/激怒反击；残血可用捕网驯服为宠物。
## - 回城：西端哨站回主城。

signal toast_requested(text: String)
signal dialog_requested(title: String, content: String, actions: Array, eyebrow: String)
signal hud_changed
signal exit_requested  # 返回主城

const WORLD_R := 60.0        # 野外半径
const BIOME_LINE := 0.0      # z < 0 山地 / z > 0 森林
const ANIMAL_CAP := 10
const RESPAWN_T := 24.0

var main = null
var player: Actor = null
var animals: Array = []      # WildAnimal
var placed_torches: Array = []
var held_torch_node: Node3D = null

var move_target := Vector3.ZERO
var has_move_target := false
var move_marker: MeshInstance3D
var _respawn_t := RESPAWN_T
var _obstacles: Array = []   # Vector3(x, z, r) 圆形障碍

func _ready() -> void:
	_build_terrain()
	_build_player()
	_spawn_animals(true)
	move_marker = GeoBuilder.ring(self, 0.28, 0.4, Color(0.9, 0.85, 0.6, 0.8), Vector3.ZERO, 24)
	move_marker.visible = false

# ---------------- 地形 ----------------
func biome_at(pos: Vector3) -> String:
	return "mountain" if pos.z < BIOME_LINE else "forest"

## 小地图数据：营地（回城点）+ 动物 + 大型障碍（树木/岩石只留大的，免得糊成一团）。
func minimap_data() -> Dictionary:
	var marks: Array = []
	marks.append({"pos": Vector3(-WORLD_R + 7.0, 0, 0), "kind": "camp", "id": "camp", "short": "营"})
	for a in animals:
		if is_instance_valid(a) and not a.dead and not a.captured:
			marks.append({"pos": a.global_position, "kind": "enemy", "id": "", "short": ""})
	var circs: Array = []
	for b in _obstacles:
		if float(b.z) >= 1.2:
			circs.append({"x": b.x, "z": b.y, "r": b.z * 0.6})
	# 地貌带：北山（灰）／南林（绿），给出即时方位感。
	var zones: Array = [
		{"z_min": -WORLD_R, "z_max": BIOME_LINE, "color": Color(0.24, 0.25, 0.24, 0.45)},
		{"z_min": BIOME_LINE, "z_max": WORLD_R, "color": Color(0.15, 0.24, 0.14, 0.45)},
	]
	return {"half": WORLD_R, "rects": [], "circs": circs, "zones": zones, "marks": marks}

func _build_terrain() -> void:
	var Env := Ambience
	Env.tiled_floor(self, int(WORLD_R * 2.2), 0.0, 71)
	# 地貌底色：北侧灰岩山地 / 南侧深绿针叶林。
	GeoBuilder.cylinder(self, WORLD_R, WORLD_R, 0.06, Color(0.26, 0.27, 0.25), Vector3(0, 0.02, -WORLD_R * 0.62), 44)
	GeoBuilder.cylinder(self, WORLD_R, WORLD_R, 0.06, Color(0.14, 0.22, 0.12), Vector3(0, 0.02, WORLD_R * 0.62), 44)
	# 过渡带草径 + 石径。
	GeoBuilder.box(self, WORLD_R * 2.0, 0.04, 7.0, Color(0.24, 0.26, 0.19), Vector3(0, 0.05, 0))
	_build_path()

	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	# ---------------- 北方山地：岩群 / 悬崖 / 岩脊 ----------------
	var rock_rels := ["nature/rock_largeA.glb", "nature/rock_largeB.glb", "nature/rock_largeC.glb",
		"nature/cliff_rock.glb", "nature/cliff_stone.glb", "nature/rock_tallA.glb"]
	for i in range(30):
		var a := rng.randf() * PI
		var r := 9.0 + rng.randf() * (WORLD_R - 13.0)
		var pos := Vector3(cos(a) * r, 0, -sin(a) * r)
		if _near_path(pos): continue
		# 扁平/宽体岩石按占地归一化（"h"=最大水平边），避免"y"归一化把占地放大成巨板。
		var foot := 2.4 + rng.randf() * 3.6
		AssetLib.spawn_norm(self, rock_rels[i % rock_rels.size()], foot, pos, rng.randf() * 360.0, "h")
		_obstacles.append(Vector3(pos.x, pos.z, foot * 0.42))
	# 山脊巨岩带（北缘，形成地形边界）。
	for i in range(7):
		var pos := Vector3(-WORLD_R * 0.78 + i * WORLD_R * 0.26, 0, -WORLD_R * 0.84)
		var c := GeoBuilder.cylinder(self, 2.2, 3.6, 6.0 + rng.randf() * 4.0, Color(0.28, 0.29, 0.31), pos, 7)
		c.rotation.y = rng.randf() * TAU
		_obstacles.append(Vector3(pos.x, pos.z, 3.8))
	# 山地零星松树。
	for i in range(12):
		var a2 := rng.randf() * PI
		var r2 := 14.0 + rng.randf() * (WORLD_R - 20.0)
		var p2 := Vector3(cos(a2) * r2, 0, -sin(a2) * r2)
		if _near_path(p2): continue
		_pine(p2, rng, 5.0 + rng.randf() * 3.5)

	# ---------------- 南方森林：密集针叶林 + 林下植被 ----------------
	for i in range(84):
		var a3 := rng.randf() * PI
		var r3 := 11.0 + rng.randf() * (WORLD_R - 15.0)
		var p3 := Vector3(cos(a3) * r3, 0, sin(a3) * r3)
		if _near_path(p3): continue
		# 林间空地（动物聚集区，也是测试狩猎点 (0,0,40) 附近）。
		if Vector2(p3.x, p3.z - 40.0).length() < 9.0: continue
		_pine(p3, rng, 5.5 + rng.randf() * 3.8)
	# 倒木与树桩（无碰撞，纯景观）。
	var log_rels := ["nature/log.glb", "nature/log_large.glb", "nature/log_stack.glb"]
	for i in range(14):
		var a4 := rng.randf() * PI
		var r4 := 12.0 + rng.randf() * (WORLD_R - 18.0)
		var p4 := Vector3(cos(a4) * r4, 0, sin(a4) * r4)
		if _near_path(p4): continue
		AssetLib.spawn_norm(self, log_rels[i % log_rels.size()], 1.4 + rng.randf() * 1.4, p4, rng.randf() * 360.0, "h")
	# 林下植被（草丛/灌木/蘑菇/花，无碰撞）。
	for i in range(96):
		var a5 := rng.randf() * TAU
		var r5 := 6.0 + rng.randf() * (WORLD_R - 9.0)
		var p5 := Vector3(cos(a5) * r5, 0, sin(a5) * r5)
		var side_forest := p5.z > BIOME_LINE
		var rel := ""
		if side_forest:
			match i % 5:
				0: rel = "nature/grass_large.glb"
				1: rel = "nature/plant_bushLarge.glb"
				2: rel = "nature/mushroom_red.glb"
				3: rel = "nature/flower_purpleA.glb"
				_: rel = "nature/grass.glb"
		else:
			match i % 3:
				0: rel = "nature/grass.glb"
				1: rel = "nature/rock_smallA.glb"
				_: rel = "nature/plant_bushSmall.glb"
		AssetLib.spawn_norm(self, rel, 0.5 + rng.randf() * 0.6, p5, rng.randf() * 360.0, "h")

	# ---------------- 西端营地（回城哨站） ----------------
	_build_camp()
	# 氛围：浮尘（不做雾，视角拉远也要看清全地形）。
	Env.make_motes(self, 50, 10, Color(0.6, 0.7, 0.5))

## 石径：营地 → 山坳 → 森林空地（浅色石板铺面，纯视觉）。
func _build_path() -> void:
	var segs := [
		[Vector3(-WORLD_R + 4.0, 0, 0), Vector3(-2.0, 0, 0)],
		[Vector3(-2.0, 0, 0), Vector3(0, 0, 40.0)],
	]
	for s in segs:
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		var d := b - a
		var length := d.length()
		if length < 0.01: continue
		var strip := GeoBuilder.box(self, 3.4, 0.05, length, Color(0.38, 0.36, 0.32),
			Vector3((a.x + b.x) * 0.5, 0.06, (a.z + b.z) * 0.5))
		strip.rotation.y = atan2(d.x, d.z)
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## 石径留白判定：树/岩不落在营地与森林之间的必经通道上。
func _near_path(p: Vector3) -> bool:
	if p.x < 2.0 and p.x > -WORLD_R and absf(p.z) < 4.0: return true
	if absf(p.x) < 4.0 and p.z > -4.0 and p.z < 46.0: return true
	if Vector2(p.x, p.z - 6.0).length() < 7.0: return true  # 出生点空地
	return false

## 针叶树：墓园包的松树（CC0），高度按 y 归一化。
func _pine(pos: Vector3, rng: RandomNumberGenerator, h: float) -> void:
	var rels := ["dungeon/graveyard/pine.glb", "dungeon/graveyard/pine-crooked.glb"]
	var rel: String = rels[rng.randi() % rels.size()]
	if AssetLib.size_of(rel).y > 0.001 and AssetLib.load_model(rel) != null:
		AssetLib.spawn_norm(self, rel, h, pos, rng.randf() * 360.0, "y")
	else:
		# 后备：程序化松树（资产缺失时兜底）。
		var t := Node3D.new()
		add_child(t)
		t.position = pos
		var trunk_h := h * 0.4
		GeoBuilder.cylinder(t, 0.16, 0.30, trunk_h, Color(0.28, 0.20, 0.13), Vector3(0, trunk_h * 0.5, 0), 7)
		var green := Color(0.13, 0.26, 0.13).lightened(rng.randf() * 0.08)
		for k in range(3):
			GeoBuilder.cylinder(t, 0.05, 1.5 - k * 0.4, h * 0.32, green, Vector3(0, trunk_h + h * 0.16 + k * h * 0.2, 0), 8)
	_obstacles.append(Vector3(pos.x, pos.z, 0.75))

## 营地：营火 + 石圈 + 原木坐凳 + 补给箱 + 指路木牌。
func _build_camp() -> void:
	var c := Vector3(-WORLD_R + 7.0, 0, 0)
	AssetLib.spawn_norm(self, "nature/campfire_logs.glb", 0.9, c, 0, "h")
	AssetLib.spawn_norm(self, "nature/campfire_stones.glb", 1.7, c, 0, "h")
	# 原木坐凳。
	for off in [Vector3(1.8, 0, 0.9), Vector3(-1.6, 0, 1.1), Vector3(0.2, 0, -2.0)]:
		AssetLib.spawn_norm(self, "nature/log.glb", 0.6, c + off, randf() * 360.0, "h")
	# 补给与木牌。
	AssetLib.spawn_norm(self, "dungeon/kay/crates_stacked.gltf.glb", 1.2, c + Vector3(2.6, 0, -1.8), 24, "y")
	AssetLib.spawn_norm(self, "nature/sign.glb", 2.0, c + Vector3(3.6, 0, 1.6), 200, "y")
	var camp := OmniLight3D.new()
	camp.light_color = Color(1.0, 0.6, 0.3)
	camp.light_energy = 3.4
	camp.omni_range = 8.0
	camp.position = c + Vector3(0, 1.2, 0)
	add_child(camp)
	_obstacles.append(Vector3(c.x, c.z, 1.1))

func _build_player() -> void:
	player = Actor.new()
	player.faction = "player"
	player.display_name = "你"
	player.name = "Player"
	player.show_bar = false
	add_child(player)
	var rig := ActorRig.new(GameState.save.selected, 741)
	player.add_child(rig)
	player.rig = rig
	player.global_position = Vector3(0, 0, 6.0)

## 进入野外：玩家血量接续存档（上限取汇总属性），与地下城 reset_dungeon 的同步一致。
## 此前从未同步 —— 玩家带着 107 血进野外，实际只有基础 30 血，会被低级动物反杀。
func sync_player() -> void:
	if player == null: return
	player.hp_max = int(GameState.total_stats().hp_max)
	player.hp = clampi(int(GameState.save.hp), 1, player.hp_max)
	player.armor = int(GameState.total_stats().armor)
	GameState.apply_class_guard(player)

# ---------------- 动物 ----------------
func _spawn_animals(initial: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for side in ["mountain", "forest"]:
		var table := Bestiary.animal_table(rng, side)
		for spec in table:
			if animals.size() >= ANIMAL_CAP: return
			_spawn_animal(spec, side, rng)

func _spawn_animal(species: String, side: String, rng: RandomNumberGenerator) -> void:
	var a := WildAnimal.new()
	a.world = self
	add_child(a)
	a.setup(species)
	var z_sign := -1.0 if side == "mountain" else 1.0
	var pos := Vector3.ZERO
	for attempt in range(8):
		var ang := rng.randf() * PI
		var r := 8.0 + rng.randf() * (WORLD_R - 12.0)
		pos = Vector3(cos(ang) * r, 0, z_sign * sin(ang) * r)
		if _walkable(pos): break
	a.global_position = pos
	a.blocked_check = _walkable
	a.died.connect(_on_animal_died)
	animals.append(a)

func _on_animal_died(actor: Actor) -> void:
	var a := actor as WildAnimal
	animals.erase(a)
	# 掉落：兽皮/药草。
	var drop := "pelt" if a.species in ["wolf", "boar", "deer"] else "herb"
	var node := Node3D.new()
	add_child(node)
	node.global_position = a.global_position
	GeoBuilder.mesh_instance(node, GeoBuilder.box_geometry(0.3, 0.2, 0.3),
		GeoBuilder.mat(Color(0.7, 0.6, 0.4), {"emissive": Color(0.5, 0.4, 0.2), "emissive_intensity": 0.6}),
		Vector3(0, 0.3, 0), false)
	set_meta("drop_" + str(node.get_instance_id()), drop)
	node.set_meta("drop_item", drop)
	node.name = "AnimalDrop"
	# 计时后由 _update_pickups 拾取逻辑简化：靠近自动拾取。
	set_meta("simple_drops", true)
	toast_requested.emit("%s 倒下了，留下战利品。" % a.display_name)
	GameState.add_xp(2)

## E 键：拾取动物掉落 / 捕获残血动物 / 回城。
func interact() -> void:
	# 捕获：最近的残血动物。
	for a in animals:
		if not a.dead and not a.captured and a.hp < a.hp_max * 0.3 and a.global_position.distance_to(player.global_position) < 2.4:
			if GameState.inventory.count_of("net") <= 0:
				toast_requested.emit("需要捕兽网（道具商有售）。")
				return
			GameState.inventory.remove("net", 1)
			if a.try_capture():
				a.captured = true
				a.queue_free()
				animals.erase(a)
				toast_requested.emit("驯服成功！宠物已加入队伍。")
			else:
				toast_requested.emit("它挣脱了！再试试。")
			return
	# 掉落拾取。
	for d in get_children():
		if d.name == "AnimalDrop" and d is Node3D and (d as Node3D).global_position.distance_to(player.global_position) < 2.2:
			var drop: String = d.get_meta("drop_item")
			GameState.pickup_item(Items.stack_item(drop))
			toast_requested.emit("拾取 %s。" % Items.stack_item(drop).name)
			d.queue_free()
			return
	# 回城点（西端哨站）：靠近营火 (-WORLD_R+7,0) 4m 内即触发；
	# 旧判定 length > WORLD_R-6 覆盖不到营火（长度仅 53），站在火边按 E 无效。
	var camp := Vector3(-WORLD_R + 7.0, 0, 0)
	if player.global_position.distance_to(camp) < 4.0 or \
			(player.global_position.length() > WORLD_R - 8.0 and player.global_position.x < -WORLD_R * 0.4):
		exit_requested.emit()
		return
	toast_requested.emit("这里没有什么可做的。残血动物可用捕网（E）驯服。")

# ---------------- 战斗 ----------------
## 玩家攻击（野外动物）：自动索敌范围内最近动物并转向，远程职业射程更远。
func player_attack() -> void:
	if player == null or player.dead or not player.attack_ready(): return
	var cd: Dictionary = GameState.class_data()
	player.set_attack_cooldown(float(cd.attack_duration) + float(cd.attack_cooldown))
	player.play_anim("attack", float(cd.attack_duration))
	var st: Dictionary = GameState.total_stats()
	var dmg := int(round(float(st.atk) * (1.0 + float(st.skill_amp))))
	var crit := randf() < float(st.crit)
	if crit: dmg = int(round(dmg * 1.6))
	var reach: float = 7.0 if cd.basic == "projectile" else float(cd.attack_range) + 0.4
	# 索敌：范围内最近的活动物。
	var cands: Array = []
	for a in animals:
		if is_instance_valid(a) and not a.dead and not a.captured \
				and a.global_position.distance_to(player.global_position) <= reach:
			cands.append(a)
	if not cands.is_empty():
		cands.sort_custom(func(x, y):
			return x.global_position.distance_squared_to(player.global_position) < y.global_position.distance_squared_to(player.global_position))
		var t: WildAnimal = cands[0]
		player.rotation.y = atan2(t.global_position.x - player.global_position.x, t.global_position.z - player.global_position.z)
		var final: int = t.take_damage(float(dmg), player, (t.global_position - player.global_position).normalized() * 0.4)
		t.on_hurt_by_player()
		_popup(t.global_position, str(final) + ("!" if crit else ""), Color(1, 0.85, 0.4) if crit else Color(1, 1, 1))
	AudioBus.play_tone(440 if cd.basic == "projectile" else 220, 0.08, 0.04)

# ---------------- 火把 ----------------
func toggle_torch() -> void:
	if held_torch_node:
		held_torch_node.queue_free()
		held_torch_node = null
		toast_requested.emit("收起了火把。")
	elif GameState.inventory.count_of("torch") > 0:
		held_torch_node = player.rig.hold_torch()
		toast_requested.emit("点燃火把（G 放置于地面）。")
	else:
		toast_requested.emit("没有火把了——道具商有售。")

func place_torch() -> void:
	if held_torch_node == null: return
	if GameState.inventory.count_of("torch") <= 0:
		toast_requested.emit("火把用完了。")
		held_torch_node.queue_free()
		held_torch_node = null
		return
	GameState.inventory.remove("torch", 1)
	held_torch_node.queue_free()
	held_torch_node = null
	var t := Node3D.new()
	add_child(t)
	t.global_position = player.global_position
	GeoBuilder.mesh_instance(t, GeoBuilder.box_geometry(0.06, 1.1, 0.06), GeoBuilder.mat(Color(0.3, 0.2, 0.12)), Vector3(0, 0.55, 0))
	var flame := SphereMesh.new()
	flame.radius = 0.1
	flame.height = 0.2
	flame.radial_segments = 4
	flame.rings = 2
	GeoBuilder.mesh_instance(t, flame, GeoBuilder.mat(Color(1, 0.6, 0.2), {"emissive": Color(1, 0.55, 0.15), "emissive_intensity": 2.4}), Vector3(0, 1.2, 0), false)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.25)
	l.light_energy = 7.0
	l.omni_range = 9.0
	l.position = Vector3(0, 1.25, 0)
	t.add_child(l)
	placed_torches.append({"node": t, "light": l, "t": 300.0})
	toast_requested.emit("火把插在地上，火光摇曳（燃烧 5 分钟）。")

# ---------------- 世界查询 ----------------
func handle_click(cam: Camera3D, mouse: Vector2) -> void:
	var plane := Plane(Vector3.UP, 0.0)
	var hit = plane.intersects_ray(cam.project_ray_origin(mouse), cam.project_ray_normal(mouse))
	if hit and Vector2(hit.x, hit.z).length() < WORLD_R - 2.0:
		move_target = hit
		has_move_target = true
		move_marker.global_position = hit
		move_marker.visible = true

func player_actor() -> Actor:
	return player

func _walkable(pos: Vector3) -> bool:
	if Vector2(pos.x, pos.z).length() > WORLD_R - 1.5: return false
	for b in _obstacles:
		if Vector2(pos.x - b.x, pos.z - b.y).length() < b.z: return false
	return true

## 动物咬人（WildAnimal 调用）。
func animal_bite(a: WildAnimal, dmg: int) -> void:
	var final := player.take_damage(float(dmg), a)
	_popup(player.global_position, "-" + str(final), Color(1, 0.35, 0.35))
	GameState.set_hp(player.hp)
	if player.hp <= 0:
		# 野外倒下：送回主城，扣少量金币。
		var lost := int(GameState.save.gold) * 1 / 10
		GameState.add_gold(-lost)
		player.hp = maxi(1, int(GameState.total_stats().hp_max) / 2)
		GameState.set_hp(player.hp)
		player.global_position = Vector3(0, 0, 6.0)
		toast_requested.emit("被野兽击倒——醒来时已在庇护所门口（遗失 %d 金币）。" % lost)

var _popups: Array = []
func _popup(pos: Vector3, text: String, color := Color(1, 0.9, 0.6)) -> void:
	if _popups.is_empty():
		for i in range(8):
			var l := Label3D.new()
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.no_depth_test = true
			l.font_size = 40
			l.pixel_size = 0.008
			l.outline_size = 8
			l.outline_modulate = Color(0.05, 0.03, 0.03)
			l.visible = false
			add_child(l)
			_popups.append({"label": l, "t": 0.0})
	for p in _popups:
		if p.t <= 0.0:
			p.t = 0.8
			var l: Label3D = p.label
			l.text = text
			l.modulate = color
			l.position = pos + Vector3(0, 2.0, 0)
			l.visible = true
			return

# ---------------- 主循环 ----------------
func update_overworld(delta: float, rig: CameraRig) -> void:
	var time := Time.get_ticks_msec() / 1000.0
	# 自由移动。
	var iv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var cam_fwd := -rig.camera.global_transform.basis.z
	cam_fwd.y = 0.0
	cam_fwd = cam_fwd.normalized()
	var cam_right := rig.camera.global_transform.basis.x
	cam_right.y = 0.0
	cam_right = cam_right.normalized()
	var dir := (cam_fwd * -iv.y + cam_right * iv.x)
	if dir.length_squared() > 0.001:
		has_move_target = false
		move_marker.visible = false
		player.move_step(delta, dir, Input.is_action_pressed("run"))
	elif has_move_target:
		var to_t := move_target - player.global_position
		to_t.y = 0
		if to_t.length() < 0.35:
			has_move_target = false
			move_marker.visible = false
		else:
			player.move_step(delta, to_t.normalized())
	else:
		player.stop_moving()
	# 防御：按住 R（野外同样可用，用于扛住野兽扑击）。
	player.set_guard(Input.is_action_pressed("guard") and not player.is_busy() and player.stun_t <= 0.0)
	player.animate_tick(delta, time)
	# 动物生态。
	for a in animals.duplicate():
		if is_instance_valid(a) and not a.dead:
			a.ai_tick(delta, time, player)
	# 掉落淡出（简化：30 秒后消失）。
	for d in get_children():
		if d.name == "AnimalDrop" and d.has_meta("born_t"):
			if time - float(d.get_meta("born_t")) > 30.0:
				d.queue_free()
		elif d.name == "AnimalDrop":
			d.set_meta("born_t", time)
	# 伤害数字。
	for p in _popups:
		if p.t > 0.0:
			p.t -= delta
			var l: Label3D = p.label
			l.position.y += delta * 0.9
			if p.t <= 0.0:
				l.visible = false
	# 放置火把燃烧。
	for pt in placed_torches.duplicate():
		pt.t -= delta
		if pt.t <= 0.0:
			pt.node.queue_free()
			placed_torches.erase(pt)
	# 动物重生。
	_respawn_t -= delta
	if _respawn_t <= 0.0:
		_respawn_t = RESPAWN_T
		if animals.size() < ANIMAL_CAP:
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			var side := "mountain" if player.global_position.z < 0 else "forest"
			var table := Bestiary.animal_table(rng, side)
			_spawn_animal(table[rng.randi() % table.size()], side, rng)
	hud_changed.emit()
