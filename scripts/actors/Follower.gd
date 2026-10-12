class_name Follower
extends Actor
## 随行者：宠物（捕获的动物）与同伴（招募的 NPC）统一为跟随战斗单位。
## 跟随队形：以玩家为锚的偏移槽位；玩家锁定敌人时协同进攻；倒地 12 秒后自行恢复。

var kind := "pet"  # pet | companion
var npc_id := ""   # companion 时为 NPC id
var follow_slot := 0
var downed := false
var _revive_t := 0.0
var _stuck_t := 0.0   # 槽位够不到的累计时间（超过阈值传送归队）
var world = null
var _skel_ap: AnimationPlayer = null  # 骨骼动画缓存（同伴）
var _cur_clip := ""

func setup_pet() -> void:
	kind = "pet"
	var ps: Dictionary = GameState.pet_stats()
	display_name = ps.get("name", "宠物")
	hp_max = int(ps.hp_max)
	hp = hp_max
	atk = int(ps.dmg)
	move_speed = 3.6
	show_bar = false

func setup_companion(id: String) -> void:
	kind = "companion"
	npc_id = id
	# NPC 定义见 NPCs 模块（同伴专精决定属性成长）。
	var def: Dictionary = NpcBook.NPCS[id]
	display_name = def.name
	hp_max = 55 + int(def.combat.get("hp", 0))
	hp = hp_max
	atk = int(def.combat.get("atk", 8))
	move_speed = 3.4
	show_bar = false

func _build_visual() -> void:
	if kind == "companion":
		# 同伴：KayKit 冒险者 GLB（CC0），身高归一化到 1.8m。
		visual = Node3D.new()
		add_child(visual)
		AssetLib.spawn_norm(visual, AssetLib.npc_model(NpcBook.NPCS[npc_id].get("rig", "warrior")), 1.8, Vector3.ZERO, 0.0, "y")
		_skel_ap = visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
	else:
		# 宠物：Kenney cube-pets GLB + 项圈与信任徽记粒子，按成长放大。
		visual = Node3D.new()
		add_child(visual)
		var species := "rabbit"
		if GameState.active_pet_valid():
			species = GameState.pet_species()
		var lv := GameState.pet_level()
		# 宠物身高 0.5m 起步，每级 +0.03m（原始模型 1.5~2.0m 偏大）。
		AssetLib.spawn_norm(visual, AssetLib.animal_model(species), 0.5 + 0.03 * lv, Vector3.ZERO, 0.0, "y")
		# 项圈（标记为宠物）。
		GeoBuilder.ring(visual, 0.13, 0.17, Color(0.9, 0.75, 0.3), Vector3(0, 0.5, 0.28), 12)
		# 信任徽记粒子。
		var p := GPUParticles3D.new()
		p.amount = 6
		p.lifetime = 1.6
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.4
		pm.gravity = Vector3(0, 0.5, 0)
		pm.initial_velocity_min = 0.05
		pm.initial_velocity_max = 0.15
		p.process_material = pm
		var pmesh := QuadMesh.new()
		pmesh.size = Vector2(0.07, 0.07)
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.95, 0.85, 0.5, 0.8)
		pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		pmesh.material = pmat  # 粒子材质挂在 draw_pass 网格上
		p.mesh = pmesh
		visual.add_child(p)
		p.position = Vector3(0, 0.9, 0)

func _bar_height() -> float:
	return 1.6 if kind == "pet" else 2.9

func ai_tick(delta: float, time: float, player: Actor) -> void:
	if dead:
		return
	if downed:
		_revive_t -= delta
		if _revive_t <= 0.0:
			downed = false
			hp = maxi(1, hp_max / 3)
			if visual: visual.rotation.x = 0.0
			if rig: rig.set_opacity(1.0)
		return
	# 待命指令（玩家显式下达）：原地不动、不主动进攻。
	if GameState.party_hold:
		_moving = false
		_tick_anim()
		return
	var anchor := _formation_anchor(player)
	# 卡位兜底：槽位长期够不到就归队，避免队友卡地形（参考 Vermintide 的 leash/teleport）。
	if global_position.distance_to(anchor) > 6.0:
		_stuck_t += delta
		if _stuck_t > 2.5:
			_stuck_t = 0.0
			global_position = anchor
	else:
		_stuck_t = 0.0
	var to_anchor := anchor - global_position
	var target = _pick_target(player)
	if target != null:
		var to_t: Vector3 = target.global_position - global_position
		if to_t.length() > 1.5:
			move_step(delta, to_t.normalized(), true)
		elif attack_ready():
			set_attack_cooldown(1.2)
			play_anim("attack" if kind == "companion" else "idle", 0.5)
			world.follower_hit(self, effective_atk())
	elif to_anchor.length() > 0.8:   # 就位判定 0.8m（半个身位内即视为到位）
		move_step(delta, to_anchor.normalized(), to_anchor.length() > 4.0)
	else:
		_moving = false
	_tick_anim()
	# 缓慢回血。
	if hp < hp_max and randf() < delta * 0.5:
		heal(1)

## 队形锚点：按当前阵型取槽位；槽位不可通行（窄道/墙内）时降级为纵队。
func _formation_anchor(player: Actor) -> Vector3:
	var count: int = GameState.save.get("party", []).size()
	if GameState.active_pet_valid(): count += 1
	count = maxi(count, 1)
	var off: Vector3 = NpcBook.formation_offset(GameState.party_formation(), follow_slot, count)
	var basis := player.global_transform.basis
	var anchor: Vector3 = player.global_position + basis.x * off.x + basis.z * off.z
	if blocked_check.is_valid() and blocked_check.call(anchor):
		off = NpcBook.formation_offset("follow", follow_slot, count)
		anchor = player.global_position + basis.x * off.x + basis.z * off.z
	return anchor

## 目标选择：档位（护航/均衡/主动）+ 集火指令覆盖。
func _pick_target(player: Actor):
	var pv = player.enemy_target
	if GameState.order_focus_active():
		if pv and not pv.dead: return pv
	var stance := GameState.stance_of(npc_id) if kind == "companion" else "normal"
	match stance:
		"aggressive":
			if world and world.has_method("nearest_enemy"):
				var near = world.nearest_enemy(global_position, 13.0)
				if near and not near.dead: return near
			if pv and not pv.dead and global_position.distance_to(pv.global_position) < 13.0: return pv
		"passive":
			# 护航：只打已经贴近的、玩家正在打的目标（不追击）。
			if pv and not pv.dead and global_position.distance_to(pv.global_position) < 6.5: return pv
		_:
			if pv and not pv.dead and global_position.distance_to(pv.global_position) < 10.0: return pv
	return null

## 同伴/宠物动作：同伴播骨骼剪辑，宠物播动物节点动画（都有实际关节活动）。
func _tick_anim() -> void:
	if visual == null: return
	var want := "walk" if _moving else "idle"
	if _cur_clip == want: return
	_cur_clip = want
	if kind == "pet":
		AssetLib.play_clip(visual, AssetLib.ANIM_A_WALK if _moving else AssetLib.ANIM_A_IDLE, true)
	elif _skel_ap != null:
		AssetLib.play_clip(visual, AssetLib.ANIM_WALK if _moving else AssetLib.ANIM_IDLE, true)

func down() -> void:
	downed = true
	_revive_t = 12.0
	# 倒地姿势（GLB 不支持 modulate，用整体旋转躺平）。
	if visual: visual.rotation.x = -PI / 2.0
	if rig: rig.set_opacity(0.4)

## 覆盖受击：随行者倒地而非死亡。
func take_damage(amount: float, from: Node3D, knock_dir: Vector3 = Vector3.ZERO, true_dmg := false) -> int:
	var dealt := super.take_damage(amount, from, knock_dir, true_dmg)
	if dead and not downed:
		dead = false
		hp = 0
		down()
	return dealt
