class_name DungeonWorld
extends Node3D
## 深渊第一层（肉鸽重构版）。
## 结构：5 个房间的推进链 [战斗, 战斗, 事件, 战斗/宝箱, Boss]，清场后三选一祝福，
## 走入石门进入下一间；击败深渊守望者后开启回归之门。
## 战斗：职业基础攻击 + 4 主动技能（蓝耗/冷却）+ 暴击/词缀特效/局部伤害数字。
## 掉落：金币自动吸附；物品以稀有度颜色光柱落地，走近拾取。

signal toast_requested(text: String)
signal dialog_requested(title: String, content: String, actions: Array, eyebrow: String)
signal hud_changed
signal dialog_closed
signal hit_flash
signal exit_requested

const ROOM_COUNT := 5
const ARENA_R := 15.0
const BLESSINGS := [
	{"id": "b_atk", "name": "深渊之力", "desc": "攻击 +15%（本局有效）", "stats": {"atk": 3}},
	{"id": "b_speed", "name": "影风疾行", "desc": "移速 +12%（本局有效）", "stats": {"speed": 0.12}},
	{"id": "b_armor", "name": "石肤", "desc": "护甲 +3（本局有效）", "stats": {"armor": 3}},
	{"id": "b_hp", "name": "旺盛生命", "desc": "生命上限 +20 并回满（本局有效）", "stats": {"hp_max": 20}},
	{"id": "b_mp", "name": "秘泉", "desc": "法力上限 +25、回复 +1（本局有效）", "stats": {"mp_max": 25, "mp_regen": 1.0}},
	{"id": "b_crit", "name": "弱点直觉", "desc": "暴击率 +10%（本局有效）", "stats": {"crit": 0.10}},
	{"id": "b_gold", "name": "点金之手", "desc": "金币获取 +25%（本局有效）", "stats": {"gold_find": 0.25}},
	{"id": "b_leech", "name": "汲血契约", "desc": "造成伤害的 8% 转化为生命（本局有效）", "stats": {"leech": 0.08}},
]

var main = null
var camera_rig: CameraRig = null
var player: Actor = null
var followers: Array = []          # Follower（宠物+同伴）
var enemies: Array = []            # Enemy
var projectiles: Array = []        # 飞行物
var pickups: Array = []            # 掉落物
var placed_torches: Array = []     # 放置的火把
var fx_list: Array = []            # 一次性特效
var popups: Array = []             # 伤害数字池

var depth := 0
var room_kind := "combat"
var state := "fighting"            # fighting | cleared | transition | complete | dead
var run_rng := RandomNumberGenerator.new()
var cooldowns := [0.0, 0.0, 0.0, 0.0]
var move_target := Vector3.ZERO
var has_move_target := false
var held_torch_node: Node3D = null
var _hud_t := 0.0
var player_position := Vector3.ZERO
var combo_detonations := 0   # 本局「同伴先手 → 玩家引爆」的触发次数（可观测指标）

# 敌人小队（列阵 + 组合拳）：把一批敌人当作一个战术单位指挥。
var squad := {}              # {formation, base_formation, roles, members, combo, phase, t, cool, dir}
var squad_combos := 0        # 本局累计组合拳次数（可观测指标）
var _squad_warn_t := 0.0     # 播报节流（防 toast 刷屏）

# 兼容旧 UI 引用。
var move_marker: MeshInstance3D
var _path: Array = []
var target_ring: MeshInstance3D = null  # 敌人选中红圈

## 小地图数据：竞技场范围 + 出口石门 + 存活敌人。
func minimap_data() -> Dictionary:
	var marks: Array = []
	marks.append({"pos": Vector3(0, 0, -ARENA_R + 2.0), "kind": "exit", "id": "exit", "short": "门"})
	for e in enemies:
		if is_instance_valid(e) and not e.dead:
			marks.append({"pos": e.global_position, "kind": "enemy", "id": "", "short": ""})
	return {"half": ARENA_R + 2.0, "rects": [], "circs": [], "marks": marks}

func _ready() -> void:
	run_rng.randomize()
	_build_arena()
	_build_player()
	_build_popups()
	move_marker = GeoBuilder.ring(self, 0.28, 0.4, Color(0.9, 0.85, 0.6, 0.8), Vector3.ZERO, 24)
	move_marker.visible = false
	# 敌人选中标记：脚底红圈（每帧跟随 enemy_target）。
	target_ring = GeoBuilder.ring(self, 0.55, 0.72, Color(1.0, 0.25, 0.2, 0.85), Vector3.ZERO, 28)
	target_ring.visible = false

# ---------------- 场景构建 ----------------
func _build_arena() -> void:
	var Env := Ambience
	Env.tiled_floor(self, ARENA_R * 2 + 4, -0.01, 991)
	# 外墙（八角形）。
	for i in range(8):
		var a := TAU * i / 8.0 + TAU / 16.0
		var wall_len := ARENA_R * 0.78
		var wall := GeoBuilder.box(self, wall_len, 4.2, 0.7, Color(0.13, 0.14, 0.13),
			Vector3(cos(a) * ARENA_R, 2.0, sin(a) * ARENA_R))
		wall.rotation.y = -a + PI / 2
	# 环柱（KayKit 石柱资产）。
	for i in range(8):
		var a := TAU * i / 8.0
		if absf(a - PI * 0.5) < 0.01 or i == 2:  # 北侧留门
			continue
		AssetLib.spawn_norm(self, "dungeon/kay/column.gltf.glb", 5.2,
			Vector3(cos(a) * (ARENA_R - 2.5), 0, sin(a) * (ARENA_R - 2.5)), rad_to_deg(-a), "y")
	# 火把与烛台（KayKit 点燃火把资产，含火光造型）。
	for i in range(4):
		var a2 := TAU * i / 4.0 + PI / 4.0
		AssetLib.spawn_norm(self, "dungeon/kay/torch_lit.gltf.glb", 2.0,
			Vector3(cos(a2) * 9.0, 0, sin(a2) * 9.0), rad_to_deg(-a2), "y")
	# 出口石门（北侧）。
	var arch := Env.gothic_arch(self, 4.6, 5.4, 0.8, Color(0.22, 0.26, 0.24))
	arch.position = Vector3(0, 0, -ARENA_R + 0.9)
	var door := GeoBuilder.box(self, 3.6, 4.6, 0.3, Color(0.10, 0.11, 0.11), Vector3(0, 2.3, -ARENA_R + 1.2))
	door.name = "RoomDoor"
	# MultiMesh 碎石（实例化渲染示范）。
	var mm := MultiMeshInstance3D.new()
	var mmes := MultiMesh.new()
	mmes.transform_format = MultiMesh.TRANSFORM_3D
	var rock_mesh := BoxMesh.new()
	rock_mesh.size = Vector3(0.3, 0.18, 0.36)
	mmes.mesh = rock_mesh
	mmes.instance_count = 36
	for i in range(36):
		var a := run_rng.randf() * TAU
		var r := 3.0 + run_rng.randf() * (ARENA_R - 5.0)
		var xf := Transform3D(Basis.from_euler(Vector3(0, run_rng.randf() * TAU, 0.2 * run_rng.randf())),
			Vector3(cos(a) * r, 0.04, sin(a) * r))
		mmes.set_instance_transform(i, xf)
	mm.multimesh = mmes
	mm.material_override = GeoBuilder.mat(Color(0.17, 0.18, 0.16))
	add_child(mm)
	Env.make_motes(self, 60, 12, Color(0.7, 0.6, 0.75))
	# 氛围灯。
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 6, 0)
	lamp.light_color = Color(0.75, 0.6, 0.55)
	lamp.light_energy = 14.0
	lamp.omni_range = 22.0
	add_child(lamp)

func _build_player() -> void:
	player = Actor.new()
	player.faction = "player"
	player.display_name = "你"
	player.name = "Player"
	player.died.connect(_on_player_actor_died)
	player.parried.connect(_on_player_parried)
	add_child(player)
	_rebuild_player_rig()

## 战斗期血量真值在 Actor 上，统一回写存档（UI 读存档字段）。
func _sync_hp() -> void:
	GameState.set_hp(player.hp)

func _on_player_actor_died(_a: Actor) -> void:
	_on_player_dead()

func _rebuild_player_rig() -> void:
	if player.rig:
		player.rig.queue_free()
	held_torch_node = null  # 旧火把随旧 rig 释放
	var rig := ActorRig.new(GameState.save.selected, 741)
	player.add_child(rig)
	player.rig = rig
	rig.position = Vector3.ZERO

func _build_popups() -> void:
	for i in range(16):
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.font_size = 42
		l.pixel_size = 0.008
		l.outline_size = 8
		l.modulate = Color(1, 0.9, 0.6)
		l.outline_modulate = Color(0.05, 0.03, 0.03)
		l.visible = false
		add_child(l)
		popups.append({"label": l, "t": 0.0})

func _popup(pos: Vector3, text: String, color := Color(1, 0.9, 0.6)) -> void:
	for p in popups:
		if p.t <= 0.0:
			p.t = 0.8
			var l: Label3D = p.label
			l.text = text
			l.modulate = color
			l.position = pos + Vector3(randf() * 0.4 - 0.2, 2.2, 0)
			l.visible = true
			return

# ---------------- 房间流程 ----------------
func reset_dungeon() -> void:
	depth = 0
	state = "fighting"
	cooldowns = [0.0, 0.0, 0.0, 0.0]
	combo_detonations = 0
	squad = {}
	squad_combos = 0
	_squad_warn_t = 0.0
	has_move_target = false
	move_marker.visible = false
	if held_torch_node:
		held_torch_node.queue_free()
		held_torch_node = null
	GameState.clear_run_buffs()
	# 血量同步：以存档血量开局，上限取汇总属性。
	player.hp_max = int(GameState.total_stats().hp_max)
	player.hp = clampi(int(GameState.save.hp), 1, player.hp_max)
	# 护甲同步：装备/加点/职业特质的护甲此前从未写入角色（只有技能 buff 生效）。
	player.armor = int(GameState.total_stats().armor)
	# 职业防御参数（招架窗口 / 减伤）。
	GameState.apply_class_guard(player)
	for f in followers: f.dispose()
	followers.clear()
	_spawn_followers()
	_enter_room(0)
	player_position = player.global_position

func _spawn_followers() -> void:
	if GameState.active_pet_valid():
		var pet := Follower.new()
		pet.world = self
		add_child(pet)
		pet.setup_pet()
		pet.follow_slot = followers.size()
		pet.global_position = player.global_position + Vector3(1.5, 0, 2.0)
		pet.blocked_check = _walkable
		followers.append(pet)
	for npc_id in GameState.save.party:
		var comp := Follower.new()
		comp.world = self
		comp.setup_companion(npc_id)  # 必须先定型再入树：_ready→_build_visual 依赖 kind/npc_id
		add_child(comp)
		comp.follow_slot = followers.size()
		comp.global_position = player.global_position + Vector3(-1.5, 0, 2.0)
		comp.blocked_check = _walkable
		followers.append(comp)

func _enter_room(d: int) -> void:
	depth = d
	state = "fighting"
	_clear_room_actors()
	player.global_position = Vector3(0, 0, ARENA_R - 3.0)
	player.enemy_target = null
	for f in followers:
		f.global_position = player.global_position + Vector3(1.2 + f.follow_slot, 0, 2.0)
	# 房间类型。
	var roll := Bestiary.room_roll(run_rng, d)
	room_kind = "boss" if d == ROOM_COUNT - 1 else roll
	# 装饰重掷：地面符文颜色提示。
	match room_kind:
		"combat":
			_spawn_wave(d)
			toast_requested.emit("第 %d 间 · 敌意逼近" % (d + 1))
		"treasure":
			_spawn_wave(d)
			_spawn_chest()
			toast_requested.emit("第 %d 间 · 有宝箱的气息" % (d + 1))
		"event":
			_spawn_event()
			toast_requested.emit("第 %d 间 · 气氛古怪" % (d + 1))
		"boss":
			_spawn_boss()
			toast_requested.emit("深渊守望者 · 苏醒")
	var door: MeshInstance3D = get_node_or_null("RoomDoor")
	if door: door.visible = true
	_form_squad()
	hud_changed.emit()

func _clear_room_actors() -> void:
	squad = {}
	for e in enemies: e.dispose()
	enemies.clear()
	for pk in pickups: pk.node.queue_free()
	pickups.clear()
	for pr in projectiles: pr.mesh.queue_free()
	projectiles.clear()
	for fx in fx_list: fx.node.queue_free()
	fx_list.clear()

func _spawn_wave(d: int) -> void:
	var table := Bestiary.spawn_table(run_rng, d, room_kind)
	# 列阵入场：先按兵种算出阵型与阵位，再落位（替代随机环，一进场就看得出编队）。
	var roles := {"front": 0, "back": 0, "rear": 0}
	for spec0 in table:
		var r0: String = Bestiary.squad_role(String(Bestiary.ENEMIES[spec0.id].ai))
		roles[r0] = int(roles[r0]) + 1
	var formation: String = Bestiary.squad_formation(roles)
	var fwd: Vector3 = Vector3.ZERO - player.global_position
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3(0, 0, -1)
	var right := Vector3(-fwd.z, 0, fwd.x)
	var idx := {"front": 0, "back": 0, "rear": 0}
	for i in range(table.size()):
		var spec: Dictionary = table[i]
		var e := Enemy.new()
		e.world = self
		add_child(e)
		e.setup(spec.id, spec.elite, d)
		var role: String = Bestiary.squad_role(e.ai_mode)
		var k: int = int(idx[role])
		idx[role] = k + 1
		var off: Vector3 = Bestiary.squad_slot(formation, role, k, maxi(int(roles[role]), 1))
		# 入场纵深：近战 8.5m / 远程 10.5m / 术士 11.5m；横向按阵位展开。
		var depth: float = 11.5 if role == "rear" else (10.5 if role == "back" else 8.5)
		var pos: Vector3 = player.global_position + right * off.x + fwd * depth
		if not _walkable(pos):
			pos = player.global_position + fwd * depth + right * off.x * 0.5
		if not _walkable(pos):
			var a := run_rng.randf() * TAU
			var r := 6.0 + run_rng.randf() * 3.0
			pos = Vector3(cos(a) * r, 0, sin(a) * r)
		e.global_position = pos
		e.blocked_check = _walkable
		e.died.connect(_on_enemy_died)
		enemies.append(e)

# ---------------- 敌人小队指挥（列阵 + 组合拳） ----------------
## 编队：按兵种构成分派阵位角色、选阵型；阵型决定它们站哪、谁在前谁在后。
func _form_squad() -> void:
	squad = {"formation": "", "base_formation": "line", "roles": {"front": 0, "back": 0, "rear": 0},
		"members": [], "combo": "", "phase": "idle", "t": 0.0, "cool": 3.0, "dir": Vector3.ZERO}
	_refresh_squad()
	squad.base_formation = Bestiary.squad_formation(squad.roles)
	squad.formation = squad.base_formation

## 重算小队成员与角色计数（成员死亡、术士召唤后调用）。
## Boss 不参与编队（单人 boss 战不套阵型）。
func _refresh_squad() -> void:
	if squad.is_empty(): return
	var m: Array = []
	for e in enemies:
		if not is_instance_valid(e) or e.dead: continue
		if e.has_meta("is_boss"): continue
		m.append(e)
	var roles := {"front": 0, "back": 0, "rear": 0}
	var idx := {"front": 0, "back": 0, "rear": 0}
	for i in range(m.size()):
		var e = m[i]
		var role: String = Bestiary.squad_role(e.ai_mode)
		e.squad_role = role
		e.squad_rank = int(idx[role])
		e.squad_gidx = i
		idx[role] = int(idx[role]) + 1
		roles[role] = int(roles[role]) + 1
	for e2 in m:
		e2.squad_rank_total = maxi(int(roles[e2.squad_role]), 1)
		e2.squad_driven = m.size() >= 2
	squad.members = m
	squad.roles = roles

func _squad_centroid() -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for g in squad.get("members", []):
		if is_instance_valid(g) and not g.dead:
			c += g.global_position
			n += 1
	return c / float(n) if n > 0 else player.global_position

## 每帧战术指挥：下发阵位（列阵推进/合围）+ 驱动组合拳状态机。
func _update_squad(delta: float) -> void:
	if squad.is_empty(): return
	_refresh_squad()
	var m: Array = squad.members
	if m.size() < 2:
		# 编队散伙：清掉前摇锁，免得残留的幸存者僵在原地。
		for g in m:
			if is_instance_valid(g): g.combo_hold = false
		squad.phase = "idle"
		squad.formation = squad.base_formation
		return
	# 阵型朝向 = 玩家 → 小队质心（平滑：玩家绕圈时不甩头；全员合围时质心≈玩家，沿用上一帧方向）。
	var live: Vector3 = _squad_centroid() - player.global_position
	live.y = 0.0
	if live.length() > 0.8:
		var want: Vector3 = live.normalized()
		squad.dir = want if squad.dir == Vector3.ZERO else squad.dir.lerp(want, clampf(delta * 1.2, 0.0, 1.0)).normalized()
	if squad.dir == Vector3.ZERO: squad.dir = Vector3(0, 0, 1)
	var fwd: Vector3 = squad.dir
	var right := Vector3(-fwd.z, 0, fwd.x)
	var formation: String = String(squad.formation)
	if formation == "": formation = String(squad.base_formation)
	var ring: bool = formation == "ring"
	# 下发阵位。
	for g in m:
		var e = g
		if not is_instance_valid(e) or e.dead: continue
		var idx: int = e.squad_gidx if ring else e.squad_rank
		var of: int = m.size() if ring else maxi(e.squad_rank_total, 1)
		var off: Vector3 = Bestiary.squad_slot(formation, e.squad_role, idx, of)
		e.squad_anchor = player.global_position + right * off.x + fwd * off.z
		e.squad_driven = true
	# 组合拳状态机：idle（冷却）→ telegraph（前摇）→ strike（同时出手 / 保持阵型）。
	match String(squad.phase):
		"telegraph":
			squad.t -= delta
			if squad.t <= 0.0: _strike_squad_combo()
		"strike":
			squad.t -= delta
			if squad.t <= 0.0:
				squad.phase = "idle"
				squad.formation = squad.base_formation
				var c: Dictionary = Bestiary.SQUAD_COMBOS.get(squad.combo, {})
				squad.cool = float(c.get("cool", 9.0)) * randf_range(0.85, 1.25)
		_:
			squad.cool = maxf(0.0, float(squad.cool) - delta)
			if squad.cool <= 0.0: _try_squad_combo()

## 冷却结束时尝试起手：离玩家太远就先列阵推进，不急着打组合拳。
func _try_squad_combo() -> void:
	if squad.members.size() < 2: return
	if player.global_position.distance_to(_squad_centroid()) > 14.0: return
	var id: String = Bestiary.pick_combo(run_rng, squad.roles)
	if id == "": return
	_begin_squad_combo(id)

## 起手：全员原地蓄势 + 地面预警 + 播报（前摇就是留给玩家格挡/走位的窗口）。
func _begin_squad_combo(id: String) -> void:
	var c: Dictionary = Bestiary.SQUAD_COMBOS[id]
	squad.combo = id
	squad.phase = "telegraph"
	squad.t = float(c.telegraph)
	# 合击冲锋换成钳形、散开合围换成环形：阵型的切换本身就是这一招的"形"。
	squad.formation = "pincer" if id == "charge" else ("ring" if id == "flank" else squad.base_formation)
	for g in squad.members:
		if is_instance_valid(g) and not g.dead: g.combo_hold = true
	squad_combos += 1
	_fx_ring(player.global_position, 5.6, Color(1.0, 0.46, 0.34))
	AudioBus.play_tone(300, 0.16, 0.05)
	if camera_rig: camera_rig.camera_shake = 0.07
	_warn_squad(String(c.warn))
	print("[SQUAD] 组合拳「%s」前摇 %.2fs（%d 人列阵）" % [String(c.name), float(c.telegraph), squad.members.size()])

## 前摇结束：同一拍出手（齐射 / 合击冲锋 / 召唤突袭），并由阵型保持一会儿。
func _strike_squad_combo() -> void:
	var id: String = String(squad.combo)
	var c: Dictionary = Bestiary.SQUAD_COMBOS.get(id, {})
	squad.phase = "strike"
	squad.t = float(c.get("hold", 1.0))
	var joined := 0
	for g in squad.members:
		if not is_instance_valid(g) or g.dead: continue
		g.combo_hold = false   # 不在射程内的也要解锁，否则会僵住
		if player.global_position.distance_to(g.global_position) <= 15.0:
			g.execute_combo(id)
			joined += 1
	if camera_rig: camera_rig.camera_shake = 0.14
	_fx_impact(player.global_position + Vector3(0, 0.5, 0), Color(1.0, 0.5, 0.34), 1.4)
	print("[SQUAD] 组合拳「%s」发动（参与 %d 人）" % [String(c.get("name", id)), joined])

## 小队播报：节流 4 秒，避免组合拳密集时刷屏 toast。
func _warn_squad(text: String) -> void:
	if _squad_warn_t > 0.0: return
	_squad_warn_t = 4.0
	toast_requested.emit("敌军 · " + text)

## 调试/测试入口：跳过冷却与距离判定，立即起手一记组合拳。
func force_squad_combo(id: String) -> bool:
	if squad.is_empty() or not Bestiary.SQUAD_COMBOS.has(id): return false
	_refresh_squad()
	if squad.members.size() < 2: return false
	_begin_squad_combo(id)
	return true

func _spawn_chest() -> void:
	var chest := Node3D.new()
	add_child(chest)
	chest.position = Vector3(0, 0, -6.0)
	chest.name = "Chest"
	# KayKit 金色宝箱（CC0）。
	AssetLib.spawn_norm(chest, "dungeon/kay/chest_gold.glb", 1.0, Vector3.ZERO, 12, "y")
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.9, 0.75, 0.4)
	glow.light_energy = 2.0
	glow.omni_range = 3.0
	glow.position = Vector3(0, 1.0, 0)
	chest.add_child(glow)

func _spawn_event() -> void:
	var ev: Dictionary = QuestBook.EVENTS[run_rng.randi() % QuestBook.EVENTS.size()]
	set_meta("room_event", ev)
	var node := Node3D.new()
	add_child(node)
	node.name = "EventProp"
	node.position = Vector3(0, 0, -6.0)
	match ev.id:
		"ev_shrine":
			# 墓园石祭坛（KayKit，扁平件按占地归一化）+ 悬浮符文。
			AssetLib.spawn_norm(node, "dungeon/graveyard/altar-stone.glb", 1.3, Vector3.ZERO, 0, "h")
			GeoBuilder.octahedron(node, 0.3, Color(0.6, 0.45, 0.9)).position = Vector3(0, 1.9, 0)
			var l := OmniLight3D.new(); l.light_color = Color(0.6, 0.45, 0.95); l.light_energy = 2.5; l.omni_range = 4.0; l.position = Vector3(0, 2.0, 0)
			node.add_child(l)
		"ev_merchant":
			# 黑市摊位：木桌 + 货箱 + 摇曳烛光。
			AssetLib.spawn_norm(node, "dungeon/kay/table_medium.gltf.glb", 1.0, Vector3.ZERO, 0, "y")
			AssetLib.spawn_norm(node, "dungeon/kay/box_stacked.gltf.glb", 1.0, Vector3(1.3, 0, 0.3), 25, "y")
			AssetLib.spawn_norm(node, "dungeon/kay/candle_lit.gltf.glb", 0.5, Vector3(-0.5, 0.9, 0.1), 0, "y")
			var lm := OmniLight3D.new(); lm.light_color = Color(1.0, 0.7, 0.4); lm.light_energy = 1.6; lm.omni_range = 4.0; lm.position = Vector3(0, 1.6, 0)
			node.add_child(lm)
		"ev_chest":
			AssetLib.spawn_norm(node, "dungeon/kay/chest.glb", 0.9, Vector3.ZERO, 0, "y")
		"ev_fountain":
			# 喷泉为扁平盆状，按占地归一化。
			AssetLib.spawn_norm(node, "town/fountain-square.glb", 2.2, Vector3.ZERO, 0, "h")
			var l2 := OmniLight3D.new(); l2.light_color = Color(0.5, 0.7, 0.95); l2.light_energy = 2.0; l2.omni_range = 5.0; l2.position = Vector3(0, 0.8, 0)
			node.add_child(l2)
		"ev_scholar":
			# 流浪学者营地：书架 + 凳子 + 烛台。
			AssetLib.spawn_norm(node, "dungeon/kay/shelf_small.gltf.glb", 1.6, Vector3(0, 0, -0.4), 0, "y")
			AssetLib.spawn_norm(node, "dungeon/kay/stool.gltf.glb", 0.5, Vector3(0.6, 0, 0.5), 30, "y")
			AssetLib.spawn_norm(node, "dungeon/kay/candle_triple.gltf.glb", 0.4, Vector3(-0.4, 0, 0.4), 0, "y")

func _spawn_boss() -> void:
	var boss := Enemy.new()
	boss.world = self
	add_child(boss)
	boss.setup("whisper", "tough", 3)
	boss.display_name = Bestiary.BOSS.name
	boss.hp_max = Bestiary.BOSS.hp
	boss.hp = boss.hp_max
	boss.atk = Bestiary.BOSS.atk
	boss.move_speed = Bestiary.BOSS.speed
	boss.ai_mode = "charger"
	boss._aggro_r = 14.0
	boss.visual.scale = Vector3.ONE * 1.9
	# Boss 特征：暗紫光照氛围由下方灯光承担（GLB 不响应 modulate）。
	boss.set_meta("is_boss", true)
	boss.global_position = Vector3(0, 0, -8.0)
	boss.blocked_check = _walkable
	boss.died.connect(_on_enemy_died)
	enemies.append(boss)
	var l := OmniLight3D.new()
	l.light_color = Color(0.6, 0.4, 0.9)
	l.light_energy = 4.0
	l.omni_range = 8.0
	l.position = Vector3(0, 3, -8)
	add_child(l)
	boss.set_meta("boss_light", l)

# ---------------- 掉落 ----------------
func _on_enemy_died(actor: Actor) -> void:
	var e := actor as Enemy
	enemies.erase(e)
	if e.has_meta("boss_light"):
		e.get_meta("boss_light").queue_free()
	var is_boss: bool = e.has_meta("is_boss")
	# 经验与统计。
	GameState.add_kill()
	var xp := 3 + depth * 2 + (6 if e.elite != "" else 0) + (25 if is_boss else 0)
	GameState.add_xp(xp)
	GameState.add_pet_xp(2)
	GameState.bump_quest("kill", "", 1)
	if e.elite != "": GameState.bump_quest("elite", "", 1)
	if e.def_id == "wolf": GameState.bump_quest("kill_kind", "wolf", 1)
	# 掉落。
	var st: Dictionary = GameState.total_stats()
	var loot := Bestiary.loot(run_rng, Bestiary.ENEMIES[e.def_id] if not is_boss else Bestiary.BOSS, e.elite, st.gold_find + st.luck, GameState.save.selected)
	if is_boss:
		loot.gold = int(loot.gold * 3)
		loot.items.append(Items.roll_gear(run_rng, 1.5))
		loot.items.append(Items.roll_weapon(run_rng, GameState.save.selected, 2, 1.0))
	_drop_loot(e.global_position, loot, is_boss)
	# 击杀特效。
	_fx_impact(e.global_position + Vector3(0, 1, 0), Color(0.5, 0.3, 0.6), 1.0 if not is_boss else 2.0)
	AudioBus.play_tone(180, 0.18, 0.05)
	if is_boss:
		_on_boss_dead()
	else:
		_check_room_clear()

func _drop_loot(pos: Vector3, loot: Dictionary, spread: bool) -> void:
	var gold: int = loot.gold
	if gold > 0:
		_spawn_pickup(pos + Vector3(0, 0, 0.5), {"kind": "gold", "gold": gold})
	for i in range(loot.items.size()):
		var off := Vector3((i - loot.items.size() / 2.0) * 0.9, 0, randf() * 0.8 - 0.4) if spread else Vector3.ZERO
		_spawn_pickup(pos + off, loot.items[i])

func _spawn_pickup(pos: Vector3, item) -> void:
	var node := Node3D.new()
	add_child(node)
	node.position = pos
	var color := Color(0.9, 0.8, 0.5)
	if item is Dictionary and item.get("kind") in ["weapon", "gear"]:
		color = Items.RARITY_COLORS[item.rarity]
	var orb := SphereMesh.new()
	orb.radius = 0.18
	orb.height = 0.36
	orb.radial_segments = 4
	orb.rings = 2
	GeoBuilder.mesh_instance(node, orb, GeoBuilder.mat(color, {"emissive": color, "emissive_intensity": 1.4}), Vector3(0, 0.55, 0), false)
	# 光柱。
	GeoBuilder.mesh_instance(node, GeoBuilder.box_geometry(0.06, 2.2, 0.06),
		GeoBuilder.mat(Color(color.r, color.g, color.b, 0.35), {"transparent": true, "unshaded": true, "depth_write": false}),
		Vector3(0, 1.1, 0), false)
	pickups.append({"node": node, "item": item, "t": 0.0})

# ---------------- 事件交互 ----------------
func _trigger_event() -> void:
	var ev: Dictionary = get_meta("room_event")
	match ev.id:
		"ev_shrine":
			dialog_requested.emit(ev.name, "祭坛的低语钻进耳朵：<b>献祭 15% 当前生命，换取一份深渊祝福。</b>", [
				{"label": "献祭", "run": func():
					player.hp = maxi(1, int(player.hp * 0.85))
					_sync_hp()
					_apply_blessing(BLESSINGS[run_rng.randi() % BLESSINGS.size()])
					_room_done()},
				{"label": "离开", "run": func(): _room_done(), "secondary": true},
			], "WHISPERS BELOW")
		"ev_merchant":
			var wares := []
			for i in range(3):
				wares.append(Items.roll_weapon(run_rng, GameState.save.selected, depth, 0.3) if run_rng.randf() < 0.5 else Items.roll_gear(run_rng, 0.3))
			var content := "斗篷下伸出三只手，各托着一件货物：\n"
			var actions := []
			for i in range(wares.size()):
				var w: Dictionary = wares[i]
				var price: int = 40 + int(w.rarity) * 45 + (0 if w.kind != "weapon" else Items.weapon_atk(w))
				var price_col: String = Color(0.9, 0.7, 0.3).to_html(false) if int(w.rarity) >= 3 else Color(0.8, 0.8, 0.8).to_html(false)
				content += "\n%d. [color=#%s]%s[/color] —— %d 金币" % [i + 1, price_col, Items.item_desc(w).split("\n")[0], price]
				var wi := w
				actions.append({"label": "买 %d（%d金）" % [i + 1, price], "run": func():
					if GameState.spend_gold(price):
						GameState.pickup_item(wi.duplicate())
						toast_requested.emit("成交。")
					else:
						toast_requested.emit("金币不足。")})
			actions.append({"label": "离开", "run": func(): _room_done(), "secondary": true})
			dialog_requested.emit(ev.name, content, actions, "SHADOW TRADE")
		"ev_chest":
			var roll := run_rng.randf()
			if roll < 0.6:
				_drop_loot(Vector3(0, 0, -6.0), {"gold": run_rng.randi_range(30, 70), "items": [Items.roll_gear(run_rng, 0.6)]}, true)
				toast_requested.emit("宝箱开了：财物无恙。")
				_room_done()
			elif roll < 0.85:
				player.take_damage(18.0, null, Vector3.ZERO, true)
				_sync_hp()
				toast_requested.emit("毒针！失去 18 点生命。")
				_room_done()
			else:
				toast_requested.emit("箱盖弹开——里面是个精英！")
				var e := Enemy.new()
				e.world = self
				add_child(e)
				e.setup("stalker", "vampiric", depth)
				e.global_position = Vector3(0, 0, -6.0)
				e.blocked_check = _walkable
				e.died.connect(_on_enemy_died)
				enemies.append(e)
				set_meta("room_event", {})
		"ev_fountain":
			player.heal(int(int(GameState.total_stats().hp_max) * 0.3))
			_sync_hp()
			GameState.add_mp(float(GameState.total_stats().mp_max))
			toast_requested.emit("泉水涤荡疲惫：生命恢复，法力全满。")
			_room_done()
		"ev_scholar":
			var quiz: Dictionary = QuestBook.QUIZ_BANK[run_rng.randi() % QuestBook.QUIZ_BANK.size()]
			var actions2 := []
			for i in range(quiz.a.size()):
				var idx := i
				actions2.append({"label": quiz.a[i], "run": func():
					if idx == quiz.correct:
						toast_requested.emit(quiz.hint + " 赞助：40 金币。")
						GameState.add_gold(40)
					else:
						toast_requested.emit("学者摇了摇头：「回去多读点书。」")
					_room_done()})
			dialog_requested.emit(ev.name, quiz.q, actions2, "A QUESTION")
	set_meta("room_event", {})

func _room_done() -> void:
	if state == "fighting":
		state = "cleared"
	_toast_door_open()

func _check_room_clear() -> void:
	if state != "fighting" or enemies.size() > 0: return
	state = "cleared"
	GameState.bump_quest("clear", "", 1)
	GameState.save.clears = int(GameState.save.clears) + 1
	# 宝箱房清场 → 开箱。
	var chest := get_node_or_null("Chest")
	if chest:
		_drop_loot(chest.position, {"gold": run_rng.randi_range(40, 90), "items": [Items.roll_weapon(run_rng, GameState.save.selected, depth, 0.5)]}, true)
		chest.queue_free()
	if depth < ROOM_COUNT - 1:
		_offer_blessings()
	else:
		_toast_door_open()

func _offer_blessings() -> void:
	var pool := BLESSINGS.duplicate()
	pool.shuffle()
	var picks := pool.slice(0, 3)
	var actions := []
	for b in picks:
		var bb: Dictionary = b
		actions.append({"label": bb.name, "run": func():
			_apply_blessing(bb)
			_toast_door_open()})
	dialog_requested.emit("深渊的馈赠", "清场的瞬间，石门上的符文亮起。选择一份祝福（仅本局有效）：", actions, "CHOOSE YOUR BOON")

func _apply_blessing(b: Dictionary) -> void:
	GameState.add_run_buff(b.id, b.name, b.stats)
	if b.id == "b_hp":
		player.hp_max = int(GameState.total_stats().hp_max)
		player.hp = mini(player.hp + 20, player.hp_max)
		_sync_hp()
	toast_requested.emit("祝福「%s」已注入血脉。" % b.name)
	hud_changed.emit()

func _toast_door_open() -> void:
	var door: MeshInstance3D = get_node_or_null("RoomDoor")
	if door: door.visible = false
	toast_requested.emit("石门开启——走上前去，继续深入。")

func _on_boss_dead() -> void:
	state = "complete"
	GameState.award_achievement("ach_first_clear")
	GameState.save.runs = int(GameState.save.runs) + 1
	# 回归之门。
	var portal := Node3D.new()
	add_child(portal)
	portal.name = "ExitPortal"
	portal.position = Vector3(0, 0, -ARENA_R + 2.6)
	GeoBuilder.ring(portal, 1.2, 1.5, Color(0.7, 0.5, 1.0, 0.9), Vector3(0, 0.05, 0), 32)
	GeoBuilder.mesh_instance(portal, GeoBuilder.box_geometry(1.6, 3.6, 0.06),
		GeoBuilder.mat(Color(0.6, 0.45, 1.0, 0.4), {"transparent": true, "unshaded": true, "depth_write": false}),
		Vector3(0, 1.8, 0), false)
	var l := OmniLight3D.new()
	l.light_color = Color(0.7, 0.5, 1.0)
	l.light_energy = 5.0
	l.omni_range = 7.0
	l.position = Vector3(0, 1.6, 0)
	portal.add_child(l)
	toast_requested.emit("守望者倒下了。回归之门已开启——走近并按 E。")
	dialog_requested.emit("第一层 · 肃清", "深渊守望者化为齑粉。\n战利品已散落在地。回归之门在北端静静旋转。", [
		{"label": "继续搜刮", "run": func(): pass, "secondary": true},
	], "FLOOR ONE CLEARED")

# ---------------- 世界查询 ----------------
func _walkable(pos: Vector3) -> bool:
	if Vector2(pos.x, pos.z).length() > ARENA_R - 0.9: return false
	# 柱子。
	for i in range(8):
		var a := TAU * i / 8.0
		if absf(a - PI * 0.5) < 0.01 or i == 2: continue
		if Vector2(pos.x - cos(a) * (ARENA_R - 2.5), pos.z - sin(a) * (ARENA_R - 2.5)).length() < 0.75: return false
	# 祭坛/宝箱/事件物。
	var chest := get_node_or_null("Chest")
	if chest and Vector2(pos.x - chest.position.x, pos.z - chest.position.z).length() < 0.9: return false
	var prop := get_node_or_null("EventProp")
	if prop and Vector2(pos.x - prop.position.x, pos.z - prop.position.z).length() < 1.0: return false
	return true

func player_actor() -> Actor:
	return player

func alive_enemies() -> Array:
	return enemies

func nearest_enemy(pos: Vector3, max_d := 99.0) -> Enemy:
	var best: Enemy = null
	var bd := max_d
	for e in enemies:
		if e.dead: continue
		var d: float = e.global_position.distance_to(pos)
		if d < bd: bd = d; best = e
	return best

## 射线拾取敌人（与目标锁定/悬停共用）。
func _ray_pick_enemy(cam: Camera3D, mouse: Vector2) -> Enemy:
	var origin := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var best: Enemy = null
	var best_d := 0.9
	for e in enemies:
		if e.dead: continue
		var c: Vector3 = e.global_position + Vector3(0, 1.2, 0)
		var to_c: Vector3 = c - origin
		var t: float = to_c.dot(dir)
		if t < 0.0: continue
		var perp: Vector3 = to_c - dir * t
		if perp.length() < best_d:
			best_d = perp.length()
			best = e
	return best

# ---------------- 输入与战斗 ----------------
func handle_click(cam: Camera3D, mouse: Vector2) -> void:
	var picked := _ray_pick_enemy(cam, mouse)
	if picked:
		player.enemy_target = picked
		toast_requested.emit("锁定：%s" % picked.display_name)
		return
	var plane := Plane(Vector3.UP, 0.0)
	var hit = plane.intersects_ray(cam.project_ray_origin(mouse), cam.project_ray_normal(mouse))
	if hit and Vector2(hit.x, hit.z).length() < ARENA_R - 1.0:
		move_target = hit
		has_move_target = true
		move_marker.global_position = hit
		move_marker.visible = true

func handle_hover(cam: Camera3D, mouse: Vector2) -> void:
	var picked := _ray_pick_enemy(cam, mouse)
	if camera_rig:
		camera_rig.hover_target = picked

func player_attack() -> void:
	if player == null or player.dead or not player.attack_ready(): return
	var cd: Dictionary = GameState.class_data()
	player.set_attack_cooldown(cd.attack_duration + cd.attack_cooldown)
	player.play_anim("attack", cd.attack_duration)
	var dmg := _player_damage(1.0)
	if cd.basic == "projectile":
		var dir := _aim_dir()
		_spawn_projectile(player.global_position + Vector3(0, 1.5, 0) + dir * 0.8, dir, 18.0, dmg, "arrow", false, false)
	else:
		_melee_hit(dmg, cd.attack_range, 2.0)
	AudioBus.play_tone(440 if cd.basic == "projectile" else 220, 0.08, 0.04)

func _aim_dir() -> Vector3:
	var t = player.enemy_target  # enemy_target 声明为 Node3D，此处动态访问战斗字段
	if t and not t.dead:
		return (t.global_position + Vector3(0, 1.2, 0) - (player.global_position + Vector3(0, 1.5, 0))).normalized()
	return Vector3(sin(player.rotation.y), 0, cos(player.rotation.y))

func _player_damage(mult: float) -> Array:
	var st: Dictionary = GameState.total_stats()
	var dmg := float(st.atk) * mult * (1.0 + float(st.skill_amp))
	if player.counter_t > 0.0: dmg *= 1.5   # 招架成功后的反击窗口
	var crit := run_rng.randf() < float(st.crit)
	if crit: dmg *= 1.6
	return [int(round(dmg)), crit]

func _deal_to_enemy(e: Enemy, dmg_pack, knock := true) -> void:
	var dmg: int = dmg_pack[0]
	var crit: bool = dmg_pack[1]
	var w = GameState.save.weapon
	# 武器词缀特效。
	if w != null:
		for a in w.affixes:
			match a:
				"fire": e.apply_status("poison", 3.0, 2.0 + w.level * 2.0)
				"frost": e.apply_status("slow", 1.5, 0.65)
				"chain":
					if run_rng.randf() < 0.2:
						var near := nearest_enemy(e.global_position + Vector3(randf() - 0.5, 0, randf() - 0.5), 5.0)
						if near and near != e:
							_fx_beam(e.global_position + Vector3(0, 1.2, 0), near.global_position + Vector3(0, 1.2, 0), Color(0.6, 0.8, 1.0))
							_deal_to_enemy(near, [int(dmg * 0.5), false], false)
				"leech": pass  # 大招路径处理
	var final := e.take_damage(dmg, player, e.global_position - player.global_position if knock else Vector3.ZERO)
	_popup(e.global_position, str(final) + ("!" if crit else ""), Color(1, 0.85, 0.4) if crit else Color(1, 1, 1))
	# 技能组合 · 引爆：命中带标记的目标追加固定比例伤害。
	_detonate_mark(e, dmg)
	# 汲血。
	var st: Dictionary = GameState.total_stats()
	var leech: float = float(st.get("leech", 0.0)) + (0.12 if (w != null and w.affixes.has("leech") and _is_ult_cast()) else 0.0)
	if leech > 0.0:
		player.heal(int(final * leech))
		_sync_hp()
	# 刺客处决。
	if e.hp > 0 and st.get("execute", 0.0) > 0.0 and e.hp < e.hp_max * 0.25:
		e.take_damage(999, player)
	if e.hp > 0 and e.has_meta("marked"):
		e.take_damage(int(dmg * 0.5), player)

func _is_ult_cast() -> bool:
	return player.has_meta("casting_ult")

func _melee_hit(dmg_pack, range_v: float, arc: float) -> void:
	var forward := Vector3(sin(player.rotation.y), 0, cos(player.rotation.y))
	for e in enemies.duplicate():
		if e.dead: continue
		var to_e: Vector3 = e.global_position - player.global_position
		if to_e.length() > range_v: continue
		if forward.angle_to(to_e.normalized()) > arc * 0.5: continue
		_deal_to_enemy(e, dmg_pack)
	_fx_slash(player.global_position + forward * 1.2 + Vector3(0, 1.2, 0))

func cast_skill(idx: int) -> void:
	if player == null or player.dead: return
	if idx < 0 or idx > 3: return
	if cooldowns[idx] > 0.0:
		toast_requested.emit("技能冷却中…")
		return
	var skill: Dictionary = SkillBook.actives(GameState.save.selected)[idx]
	var st: Dictionary = GameState.total_stats()
	if not GameState.use_mp(float(skill.mp)):
		toast_requested.emit("法力不足（需要 %d）" % int(skill.mp))
		return
	var cd_mul: float = 1.0 - (0.08 if GameState.save.weapon != null and GameState.save.weapon.affixes.has("swift") else 0.0) \
		- (0.15 if Growth.active_synergies(GameState.save.points).has("arcspeed") else 0.0)
	cooldowns[idx] = float(skill.cd) * cd_mul
	var is_ult: bool = skill.get("ult", false)
	if is_ult: player.set_meta("casting_ult", true)
	player.play_anim("ultimate" if is_ult else "cast", float(skill.get("dur", 0.9)) if skill.effect == "rain" else 0.85)
	GameState.bump_quest("skill", "", 1)
	match skill.effect:
		"melee_arc":
			var hits: int = skill.get("hits", 1)
			var pack := _player_damage(float(skill.dmg) / 12.0 / hits)
			for h in range(hits):
				_melee_hit(pack, float(skill.radius), float(skill.get("arc", 1.8)))
			if skill.has("stun"):
				for e in enemies: 
					if not e.dead and e.global_position.distance_to(player.global_position) < skill.radius: e.apply_status("stun", skill.stun)
			if skill.has("poison"):
				for e2 in enemies:
					if not e2.dead and e2.global_position.distance_to(player.global_position) < skill.radius: e2.apply_status("poison", skill.dur, float(skill.poison))
		"projectile":
			var base_dir := _aim_dir()
			var n: int = skill.get("count", 1)
			for i in range(n):
				var spread := (float(i) - float(n - 1) / 2.0) * 0.14
				var dir := base_dir.rotated(Vector3.UP, spread)
				_spawn_projectile(player.global_position + Vector3(0, 1.5, 0) + dir * 0.8, dir, float(skill.speed), _player_damage(float(skill.dmg) / 12.0), "magic" if GameState.save.selected == "mage" else "arrow", skill.get("pierce", false), skill.get("homing", false))
		"nova":
			var pack2 := _player_damage(float(skill.dmg) / 12.0)
			var r: float = skill.radius
			_fx_ring(player.global_position, r, Color(0.9, 0.5, 0.3) if GameState.save.selected == "warrior" else Color(0.5, 0.7, 1.0))
			for e in enemies.duplicate():
				if e.dead: continue
				if e.global_position.distance_to(player.global_position) <= r:
					_deal_to_enemy(e, pack2)
					if skill.has("slow"): e.apply_status("slow", 2.5, 1.0 - skill.slow)
			if skill.has("shield"):
				player.add_shield(float(skill.shield))
			if is_ult: _fx_quake(player.global_position, r)
		"rain":
			var target = player.enemy_target
			var center: Vector3 = (target.global_position if target and not target.dead else player.global_position + _aim_dir() * float(skill.range)) 
			var pack3 := _player_damage(float(skill.dmg) / 12.0)
			_fx_rain(center, float(skill.radius), pack3, GameState.save.selected == "mage")
		"dash":
			var back: bool = GameState.save.selected == "archer"
			var d3 := _aim_dir() * (-1.0 if back else 1.0)
			var pack4 := _player_damage(float(skill.dmg) / 12.0)
			var dest := player.global_position + d3 * float(skill.dist)
			if _walkable(dest): player.global_position = dest
			for e in enemies.duplicate():
				if not e.dead and e.global_position.distance_to(player.global_position) < float(skill.dist) + 1.5:
					_deal_to_enemy(e, pack4)
					if skill.has("taunt"): e.enemy_target = player
			_fx_dash(player.global_position, Color(0.6, 0.9, 0.7) if back else Color(0.8, 0.8, 0.6))
		"blink_strike":
			var t2 = player.enemy_target
			if t2 == null or t2.dead:
				t2 = nearest_enemy(player.global_position, float(skill.range))
			if t2 == null:
				toast_requested.emit("没有可袭击的目标。")
				cooldowns[idx] = 0.5
				GameState.add_mp(float(skill.mp))  # 退款
				return
			var behind: Vector3 = t2.global_position - (t2.global_position - player.global_position).normalized() * 1.2
			if _walkable(behind): player.global_position = behind
			player.face_towards(t2.global_position, 1.0, 30.0)
			_deal_to_enemy(t2, _player_damage(float(skill.dmg) / 12.0))
			_fx_dash(player.global_position, Color(0.4, 0.45, 0.7))
		"buff":
			for k in skill.buff:
				player.apply_buff(k, skill.buff[k], float(skill.dur))
			if skill.buff.has("thorns"):
				player.set_meta("thorns", skill.buff.thorns)
			_fx_ring(player.global_position, 2.0, Color(0.5, 0.8, 0.6))
		"mark":
			var t3 = player.enemy_target if player.enemy_target and not player.enemy_target.dead else nearest_enemy(player.global_position, 14.0)
			if t3:
				t3.set_meta("marked", 8.0)
				t3.set_meta("execute_flag", skill.execute)
				_popup(t3.global_position, "☠ 死亡印记", Color(0.9, 0.3, 0.4))
				_fx_ring(t3.global_position, 1.5, Color(0.9, 0.3, 0.4))
		"chain":
			var jumped := {}
			var cur := nearest_enemy(player.global_position, float(skill.range))
			var prev_pos: Vector3 = player.global_position + Vector3(0, 1.5, 0)
			for j in range(int(skill.jumps)):
				if cur == null: break
				_fx_beam(prev_pos, cur.global_position + Vector3(0, 1.2, 0), Color(0.65, 0.85, 1.0))
				_deal_to_enemy(cur, _player_damage(float(skill.dmg) / 12.0))
				jumped[cur] = true
				prev_pos = cur.global_position + Vector3(0, 1.2, 0)
				cur = nearest_enemy(prev_pos, 6.0)
				if cur and jumped.has(cur): cur = null
	if is_ult: player.remove_meta("casting_ult")
	AudioBus.play_tone(520 + idx * 60, 0.15, 0.05)
	hud_changed.emit()

# ---------------- 怪物对玩家的作用 ----------------
func enemy_hit_player(e: Enemy) -> void:
	if player.dead: return
	var dmg := maxf(2.0, float(e.atk))  # 护甲减免统一在 Actor.take_damage 内处理
	var final := player.take_damage(dmg, e)
	_sync_hp()
	_popup(player.global_position, "-" + str(final), Color(1, 0.35, 0.35))
	# 荆棘反伤。
	var thorns: float = float(GameState.total_stats().get("thorns", 0.0)) + float(player.get_meta("thorns", 0.0) if player.has_meta("thorns") else 0.0)
	if thorns > 0.0 and not e.dead:
		e.take_damage(thorns, player)
	flash_hud_hit()

func spawn_enemy_projectile(e: Enemy, dmg: int) -> void:
	var dir := (player.global_position + Vector3(0, 1.2, 0) - (e.global_position + Vector3(0, 1.5, 0))).normalized()
	_spawn_projectile(e.global_position + Vector3(0, 1.5, 0), dir, 9.0, [dmg, false], "enemy_bolt", false, false)

func spawn_minions(e: Enemy, n: int) -> void:
	var alive := 0
	for en in enemies:
		if en.def_id == "minion" and not en.dead: alive += 1
	for i in range(mini(n, 4 - alive)):
		var m := Enemy.new()
		m.world = self
		add_child(m)
		m.setup("minion", "", depth)
		m.global_position = e.global_position + Vector3(randf() * 2 - 1, 0, randf() * 2 - 1)
		m.blocked_check = _walkable
		m.died.connect(_on_enemy_died)
		enemies.append(m)
	# 眷属并入小队：补进前排，阵型随之重算（术士留在后阵被前排挡枪）。
	_refresh_squad()
	if not squad.is_empty():
		squad.base_formation = Bestiary.squad_formation(squad.roles)
		if String(squad.phase) == "idle": squad.formation = squad.base_formation
	toast_requested.emit("腐唤术士召唤了眷属！")

func animal_bite(a: WildAnimal, dmg: int) -> void:
	pass  # 野外世界处理

func follower_hit(f: Follower, dmg: int) -> void:
	var t = player.enemy_target
	if t and not t.dead:
		t.take_damage(dmg, f)
		_popup(t.global_position, str(dmg), Color(0.7, 0.9, 1.0))
		# 技能组合 · 先手：同伴命中即挂标记，玩家命中可引爆。
		var rig := "archer"
		if f.kind == "companion":
			rig = String(NpcBook.NPCS.get(f.npc_id, {}).get("rig", "warrior"))
		_apply_combo_mark(t, rig)
		if NpcBook.BATTLE_LINES.has(f.npc_id) and randf() < 0.3:
			var lines: Array = NpcBook.BATTLE_LINES[f.npc_id]
			toast_requested.emit("%s：%s" % [f.display_name, lines[randi() % lines.size()]])

# ---------------- 技能组合（同伴先手 → 玩家引爆，参考 Mass Effect 3） ----------------
## 同伴命中给目标挂「先手标记」。同一目标只保留一个标记（后覆盖前，避免多层叠加难预期）。
func _apply_combo_mark(e, rig: String) -> void:
	if e == null or e.dead: return
	if e.has_meta("combo_mark"):
		var old: Dictionary = e.get_meta("combo_mark")
		var on = old.get("node")
		if on != null and is_instance_valid(on): on.queue_free()
	var mk: Dictionary = NpcBook.MARK_BY_RIG.get(rig, NpcBook.MARK_BY_RIG["warrior"])
	var now := Time.get_ticks_msec() / 1000.0
	e.set_meta("combo_mark", {
		"id": mk.id, "name": mk.name, "color": mk.color,
		"until": now + NpcBook.MARK_DURATION,
		"node": _spawn_mark_visual(e, mk.color),
	})

## 头顶标记（billboard 小方片）：让玩家一眼看出「这个可以引爆」。
func _spawn_mark_visual(e, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.3, 0.3)
	mi.mesh = q
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.add_child(mi)
	mi.position = Vector3(0, 2.2, 0)
	return mi

## 玩家命中带标记的目标 → 引爆：额外伤害 = 本次伤害 × DETONATE_RATIO（公式确定，不靠随机）。
func _detonate_mark(e, base_dmg: int) -> void:
	if e == null or e.dead or not e.has_meta("combo_mark"): return
	var now := Time.get_ticks_msec() / 1000.0
	var mk: Dictionary = e.get_meta("combo_mark")
	if now >= float(mk.get("until", 0.0)): return
	if now < float(e.get_meta("combo_next", 0.0)): return   # 冷却窗口内不重复引爆
	var col: Color = mk.get("color", Color(1, 0.8, 0.4))
	e.remove_meta("combo_mark")
	e.set_meta("combo_next", now + NpcBook.MARK_RECAST)
	var node = mk.get("node")
	if node != null and is_instance_valid(node): node.queue_free()
	var bonus: int = maxi(1, int(round(float(base_dmg) * NpcBook.DETONATE_RATIO)))
	var dealt: int = e.take_damage(bonus, player)
	combo_detonations += 1
	_popup(e.global_position + Vector3(0, 0.6, 0), "%s 引爆 +%d" % [mk.get("name", "标记"), dealt], col)
	_fx_impact(e.global_position + Vector3(0, 1.0, 0), col, 2.6)
	if camera_rig: camera_rig.camera_shake = 0.12

## 标记过期清理。
func _update_combo_marks() -> void:
	if enemies.is_empty(): return
	var now := Time.get_ticks_msec() / 1000.0
	for e in enemies:
		if not is_instance_valid(e) or not e.has_meta("combo_mark"): continue
		var mk: Dictionary = e.get_meta("combo_mark")
		if now < float(mk.get("until", 0.0)): continue
		e.remove_meta("combo_mark")
		var node = mk.get("node")
		if node != null and is_instance_valid(node): node.queue_free()
# ---------------- 格挡反馈 ----------------
## 完美格挡成功：火花 + 音效 + 轻震屏 + 提示（反击窗口已在 Actor 内开启）。
func _on_player_parried(_a: Actor) -> void:
	var fwd := Vector3(sin(player.rotation.y), 0, cos(player.rotation.y))
	_fx_impact(player.global_position + Vector3(0, 1.3, 0) + fwd * 0.7, Color(1.0, 0.94, 0.62), 2.2)
	AudioBus.play_tone(920, 0.12, 0.05)
	if camera_rig: camera_rig.camera_shake = 0.18
	toast_requested.emit("完美格挡！反击窗口已开启（伤害 +50%）")

# ---------------- 玩家死亡 ----------------
func _on_player_dead() -> void:
	if state == "dead": return
	state = "dead"
	var lost := int(GameState.save.gold) * 3 / 10
	GameState.add_gold(-lost)
	GameState.clear_run_buffs()
	dialog_requested.emit("你倒在了深渊里", "黑暗将你托了回来。\n遗失了 %d 金币与所有本局祝福。" % lost, [
		{"label": "回到庇护所", "run": func(): exit_requested.emit()},
	], "DEFEAT")

# ---------------- 飞行物 / 特效 ----------------
## 克隆共享缓存材质到特效实例，避免淡出时污染全局材质。
func _own_mat(mi: MeshInstance3D) -> void:
	if mi and mi.material_override:
		mi.material_override = mi.material_override.duplicate()

func _spawn_projectile(pos: Vector3, dir: Vector3, speed: float, dmg_pack, kind: String, pierce: bool, homing: bool) -> void:
	var node := Node3D.new()
	add_child(node)
	node.position = pos
	var color := Color(0.9, 0.85, 0.6)
	var size := Vector3(0.05, 0.05, 0.5)
	match kind:
		"magic": color = Color(0.6, 0.5, 1.0); size = Vector3(0.14, 0.14, 0.14)
		"enemy_bolt": color = Color(0.85, 0.35, 0.3); size = Vector3(0.12, 0.12, 0.34)
	var mesh := GeoBuilder.mesh_instance(node, GeoBuilder.box_geometry(size.x, size.y, size.z), GeoBuilder.mat(color, {"emissive": color, "emissive_intensity": 1.2}), Vector3.ZERO, false)
	projectiles.append({"mesh": node, "dir": dir, "speed": speed, "dmg": dmg_pack, "from": "player" if kind != "enemy_bolt" else "enemy", "pierce": pierce, "homing": homing, "hit": {}, "life": 3.0, "kind": kind})

func _fx_ring(pos: Vector3, radius: float, color: Color) -> void:
	var node := Node3D.new()
	add_child(node)
	node.position = pos
	_own_mat(GeoBuilder.ring(node, 0.85, 1.0, Color(color.r, color.g, color.b, 0.85), Vector3.ZERO, 32))
	fx_list.append({"node": node, "t": 0.0, "dur": 0.45, "kind": "ring", "radius": radius})

func _fx_impact(pos: Vector3, color: Color, scale_v: float) -> void:
	var node := Node3D.new()
	add_child(node)
	node.position = pos
	var p := GPUParticles3D.new()
	p.amount = int(14 * scale_v)
	p.lifetime = 0.5
	p.one_shot = true
	p.explosiveness = 0.9
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 70.0
	pm.initial_velocity_min = 2.0 * scale_v
	pm.initial_velocity_max = 5.0 * scale_v
	pm.gravity = Vector3(0, -8, 0)
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.1, 0.1)
	var pm2 := StandardMaterial3D.new()
	pm2.albedo_color = color
	pm2.emission_enabled = true
	pm2.emission = color
	pm2.emission_energy_multiplier = 1.6
	pm2.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	pm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.material = pm2  # GPUParticles3D 的材质必须挂在 draw_pass 网格上
	p.draw_pass_1 = qm
	node.add_child(p)
	p.emitting = true
	fx_list.append({"node": node, "t": 0.0, "dur": 0.7, "kind": "burst"})

func _fx_beam(a: Vector3, b: Vector3, color: Color) -> void:
	var node := GeoBuilder.beam(self, a, b, 0.07, 0.07, GeoBuilder.mat(color, {"emissive": color, "emissive_intensity": 1.8}))
	_own_mat(node)
	fx_list.append({"node": node, "t": 0.0, "dur": 0.18, "kind": "fade"})

func _fx_slash(pos: Vector3) -> void:
	var node := Node3D.new()
	add_child(node)
	node.position = pos
	node.rotation.y = player.rotation.y
	var arc := GeoBuilder.ring(node, 0.8, 1.05, Color(1, 1, 1, 0.75), Vector3.ZERO, 20)
	arc.rotation.x = PI / 2
	_own_mat(arc)
	fx_list.append({"node": node, "t": 0.0, "dur": 0.2, "kind": "fade"})

func _fx_dash(pos: Vector3, color: Color) -> void:
	_fx_ring(pos, 1.6, color)
	_fx_impact(pos + Vector3(0, 0.5, 0), color, 0.6)

func _fx_rain(center: Vector3, radius: float, dmg_pack, magic: bool) -> void:
	for i in range(16):
		var a := run_rng.randf() * TAU
		var r := run_rng.randf() * radius
		var pos := center + Vector3(cos(a) * r, 0, sin(a) * r)
		var node := GeoBuilder.mesh_instance(self, GeoBuilder.box_geometry(0.06, 0.9, 0.06),
			GeoBuilder.mat(Color(1.0, 0.9, 0.5) if not magic else Color(0.7, 0.55, 1.0), {"emissive": Color(0.9, 0.8, 0.4) if not magic else Color(0.6, 0.5, 1.0), "emissive_intensity": 1.5}),
			pos + Vector3(0, 9.0 + i * 0.35, 0), false)
		fx_list.append({"node": node, "t": 0.0, "dur": 0.55 + i * 0.05, "kind": "fall", "target": pos, "dmg": dmg_pack})

func _fx_quake(pos: Vector3, r: float) -> void:
	if camera_rig: camera_rig.camera_shake = 0.3
	_fx_ring(pos, r, Color(0.9, 0.55, 0.3))
	_fx_impact(pos + Vector3(0, 0.8, 0), Color(0.9, 0.5, 0.25), 2.0)

func flash_hud_hit() -> void:
	if main and main.ui: main.ui.flash_hit()

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
		toast_requested.emit("没有火把了——武器商有售。")

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

# ---------------- 主循环 ----------------
func update_dungeon(delta: float, rig: CameraRig) -> void:
	camera_rig = rig
	_update_combo_marks()
	_squad_warn_t = maxf(0.0, _squad_warn_t - delta)
	_update_squad(delta)
	var time := Time.get_ticks_msec() / 1000.0
	# 玩家移动。
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
	else:
		player.stop_moving()
	# 防御：按住 R 进入防御姿态（攻击/施法/眩晕期间不生效；松开即退出）。
	player.set_guard(Input.is_action_pressed("guard") and not player.is_busy() and player.stun_t <= 0.0)
	if has_move_target:
		var to_t := move_target - player.global_position
		to_t.y = 0
		if to_t.length() < 0.35:
			has_move_target = false
			move_marker.visible = false
		else:
			player.move_step(delta, to_t.normalized())
	# 技能键。
	for i in range(4):
		cooldowns[i] = maxf(0.0, cooldowns[i] - delta)
		if Input.is_action_just_pressed("skill_%d" % (i + 1)):
			cast_skill(i)
	# 玩家动画 + 法力回复。
	player.animate_tick(delta, time)
	GameState.regen_mp(delta)
	# 随行者。
	for f in followers:
		f.ai_tick(delta, time, player)
	# 敌人。
	for e in enemies.duplicate():
		if is_instance_valid(e) and not e.dead:
			e.ai_tick(delta, time, player)
	# 选中红圈：跟随锁定的敌人脚底。
	if target_ring:
		var t = player.enemy_target
		var valid: bool = t != null and is_instance_valid(t) and not t.dead
		target_ring.visible = valid
		if valid:
			target_ring.global_position = t.global_position + Vector3(0, 0.04, 0)
			target_ring.rotate_y(delta * 1.2)
	# 拾取。
	_update_pickups(delta)
	# 投射物。
	_update_projectiles(delta)
	# 特效。
	_update_fx(delta)
	# 门与传送。
	_update_triggers()
	# 放置火把燃烧。
	for pt in placed_torches.duplicate():
		pt.t -= delta
		if pt.t <= 0.0:
			pt.node.queue_free()
			placed_torches.erase(pt)
	# HUD 节流刷新。
	_hud_t -= delta
	if _hud_t <= 0.0:
		_hud_t = 0.12
		hud_changed.emit()
	# 同步玩家位置快照（供 UI/测试读取）。
	if player: player_position = player.global_position

func _update_pickups(delta: float) -> void:
	for pk in pickups.duplicate():
		pk.t += delta
		var node: Node3D = pk.node
		node.rotate_y(delta * 2.4)
		var d := node.global_position.distance_to(player.global_position)
		if d < 2.2:
			var item = pk.item
			if item is Dictionary and item.kind == "gold":
				var g := int(item.gold)
				GameState.add_gold(g)
				_popup(node.global_position, "+%d 金币" % g, Color(1, 0.85, 0.4))
			else:
				if not GameState.pickup_item(item):
					toast_requested.emit("背包已满！")
					continue
				_popup(node.global_position, "获得 " + item.name, Items.RARITY_COLORS[item.get("rarity", 0)])
			AudioBus.play_tone(660, 0.1, 0.04)
			node.queue_free()
			pickups.erase(pk)

func _update_projectiles(delta: float) -> void:
	for pr in projectiles.duplicate():
		pr.life -= delta
		var node: Node3D = pr.mesh
		if pr.homing:
			var t = nearest_enemy(node.global_position, 8.0)
			if t:
				pr.dir = ((t.global_position + Vector3(0, 1.2, 0)) - node.global_position).normalized()
		node.position += pr.dir * pr.speed * delta
		if pr.kind == "arrow": node.look_at(node.position + pr.dir, Vector3.UP)
		var hit_something := false
		if pr.from == "player":
			for e in enemies:
				if e.dead or pr.hit.has(e): continue
				if node.global_position.distance_to(e.global_position + Vector3(0, 1.2, 0)) < 0.85:
					_deal_to_enemy(e, pr.dmg, false)
					pr.hit[e] = true
					hit_something = true
					if not pr.pierce: break
		else:
			if node.global_position.distance_to(player.global_position + Vector3(0, 1.2, 0)) < 0.9:
				var final := player.take_damage(float(pr.dmg[0]), null)
				_sync_hp()
				_popup(player.global_position, "-" + str(final), Color(1, 0.35, 0.35))
				hit_something = true
		if hit_something and not pr.pierce or pr.life <= 0.0 or Vector2(node.position.x, node.position.z).length() > ARENA_R + 2:
			node.queue_free()
			projectiles.erase(pr)

func _update_fx(delta: float) -> void:
	for fx in fx_list.duplicate():
		fx.t += delta
		var node: Node3D = fx.node
		var p: float = fx.t / fx.dur
		match fx.kind:
			"ring":
				node.scale = Vector3.ONE * (0.3 + p * float(fx.radius))
				for child in node.get_children():
					if child is MeshInstance3D and child.material_override is StandardMaterial3D:
						(child.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
						(child.material_override as StandardMaterial3D).albedo_color.a = 0.85 * (1.0 - p)
			"fade":
				for child in node.get_children():
					if child is MeshInstance3D and child.material_override is StandardMaterial3D:
						(child.material_override as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
						(child.material_override as StandardMaterial3D).albedo_color.a = maxf(0.0, 1.0 - p)
			"burst": pass
			"fall":
				node.position.y = maxf(fx.target.y + 0.05, node.position.y - 14.0 * delta)
				if p >= 1.0:
					var pack = fx.get("dmg")
					if pack:
						for e in enemies.duplicate():
							if not e.dead and e.global_position.distance_to(fx.target) < 2.2:
								_deal_to_enemy(e, pack)
								break
					_fx_impact(fx.target, Color(1, 0.8, 0.4), 0.8)
		if p >= 1.0:
			node.queue_free()
			fx_list.erase(fx)

func _update_triggers() -> void:
	if state == "cleared" and depth < ROOM_COUNT - 1:
		# 走到北门 → 下一间。
		if player.global_position.z < -ARENA_R + 2.6:
			has_move_target = false
			move_marker.visible = false
			_enter_room(depth + 1)
	elif state == "complete":
		var portal := get_node_or_null("ExitPortal")
		if portal and player.global_position.distance_to(portal.position) < 2.0:
			state = "transition"
			exit_requested.emit()

## 旧 UI 兼容：大招 = 第 4 技能；主动撤离。
func player_ultimate() -> void:
	cast_skill(3)

func exit_dungeon() -> void:
	exit_requested.emit()

## E 键交互（宝箱/事件）。
func interact() -> void:
	var prop := get_node_or_null("EventProp")
	if prop and player.global_position.distance_to(prop.position) < 2.2 and state == "fighting" and enemies.size() == 0 and get_meta("room_event", {}) != {}:
		_trigger_event()
		return
	var chest := get_node_or_null("Chest")
	if chest and player.global_position.distance_to(chest.position) < 2.2:
		_drop_loot(chest.position, {"gold": run_rng.randi_range(40, 90), "items": [Items.roll_weapon(run_rng, GameState.save.selected, depth, 0.5), Items.stack_item("potion_hp")]}, true)
		chest.queue_free()
		return
	var portal := get_node_or_null("ExitPortal")
	if portal and player.global_position.distance_to(portal.position) < 2.5 and state == "complete":
		exit_requested.emit()
