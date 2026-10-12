class_name Enemy
extends Actor
## 敌人：三种行为模式（Bestiary.AI_MODES）+ 精英词缀。
## charger 突进猎手：追击 → 蓄力前摇 → 扑击
## kiter   游猎射手：保持 5.5-8.5 距离放风筝，间歇放箭
## summoner 腐唤术士：远程拉扯，周期召唤眷属

var def_id := "whisper"
var ai_mode := "charger"
var elite := ""  # 精英词缀 id，"" 为普通
var level := 1
var world = null  # DungeonWorld，注入

var _state := "patrol"  # patrol | engage | windup | lunge | recover
var _windup := 0.0
var _shoot_cd := 0.0
var _summon_cd := 0.0
var _strafe := 1.0
var _aggro_r := 9.0
var _home := Vector3.ZERO
var _skel_ap: AnimationPlayer = null  # 骨骼动画缓存
var _cur_clip := ""
var _guard_cd := 0.0    # 精英格挡的决策冷却
var _guard_left := 0.0  # 精英格挡剩余时间

# 小队协同：由 DungeonWorld 的战术指挥每帧注入（列阵推进 + 组合拳）。
var squad_driven := false         # true 时按阵位走位，而不是直线扑向玩家
var squad_role := "front"         # front 近战 / back 远程 / rear 术士
var squad_rank := 0               # 同角色组内的序号（决定横向站位）
var squad_rank_total := 1
var squad_gidx := 0               # 全队序号（环形阵按全队均匀分角）
var squad_anchor := Vector3.ZERO  # 本帧阵位（世界计算并下发）
var combo_hold := false           # 组合拳前摇：原地蓄势，等指挥统一唤醒出手

func setup(id: String, elite_affix: String = "", depth: int = 0) -> void:
	def_id = id
	elite = elite_affix
	var def: Dictionary = Bestiary.ENEMIES[id]
	ai_mode = def.ai
	display_name = def.name
	guard_window = 0.0        # 完美格挡是玩家的特权：敌人只会减伤格挡，不会反震玩家
	guard_reduction = 0.5     # 举盾格挡时受到的伤害减半
	var hp_mul := 1.0 + depth * 0.25
	var atk_mul := 1.0 + depth * 0.12
	move_speed = def.speed
	if elite != "":
		var e: Dictionary = Bestiary.ELITES[elite]
		hp_mul *= e.hp_mul
		atk_mul *= e.atk_mul
		move_speed *= e.speed_mul
		display_name = e.name + "·" + def.name
	hp_max = int(round(def.hp * hp_mul))
	hp = hp_max
	atk = int(round(def.atk * atk_mul))
	show_bar = true

func _build_visual() -> void:
	visual = Node3D.new()
	add_child(visual)
	# KayKit 骷髅 GLB（CC0）：按 AI 类型区分兵种（CC0 资产，含骨骼动画）。
	# spawn_norm 内部已挂到 visual，无需再 add_child。
	_model_node()
	# 精英：脚下光环 + 放大。
	if elite != "":
		GeoBuilder.ring(visual, 0.5, 0.62, Color(0.95, 0.75, 0.3, 0.85), Vector3(0, 0.03, 0), 24)
		visual.scale = Vector3.ONE * 1.15
	# 死亡时播放倒地动画。
	died.connect(_play_death_anim)
	# 缓存骨骼动画播放器。
	_skel_ap = visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
	# 简易行走摆动数据。
	set_meta("walk_phase", randf() * TAU)

## 兵种 → 模型路径。
func _model_node() -> Node3D:
	# 骷髅模型原始 2.2~2.6m，统一归一化到 1.9m（精英再整体放大 1.15）。
	var rel := "enemies/Skeleton_Warrior.glb"
	match def_id:
		"minion": rel = "enemies/Skeleton_Minion.glb"
		_:
			match ai_mode:
				"charger": rel = "enemies/Skeleton_Warrior.glb"
				"kiter": rel = "enemies/Skeleton_Rogue.glb"
				"summoner": rel = "enemies/Skeleton_Mage.glb"
	return AssetLib.spawn_norm(visual, rel, 1.9, Vector3.ZERO, 0.0, "y")

## 死亡动画（骨架模型）+ 程序化倒地兜底。died 信号带触发者参数。
func _play_death_anim(_src = null) -> void:
	if visual == null: return
	if not AssetLib.play_clip(visual, AssetLib.ANIM_DEATH, false):
		visual.rotation.x = -PI / 2.0  # 无骨架动画时整体倒地

func _bar_height() -> float:
	return 2.5

## 每帧 AI。player: 玩家 Actor。
func ai_tick(delta: float, time: float, player: Actor) -> void:
	if dead or player.dead:
		_moving = false
		_play_body_anim(time)
		return
	var to_player := player.global_position - global_position
	var dist := to_player.length()
	_shoot_cd = maxf(0.0, _shoot_cd - delta)
	_summon_cd = maxf(0.0, _summon_cd - delta)
	_guard_cd = maxf(0.0, _guard_cd - delta)
	if _state == "patrol":
		# 小队协同：整队一起接敌（单人时用各自的仇恨半径）。
		var aggro: float = maxf(_aggro_r, 14.0) if squad_driven else _aggro_r
		if dist < aggro:
			_state = "engage"
		else:
			_moving = false
			_play_body_anim(time)
			return
	if stun_t > 0.0:
		# 被招架/击晕：举盾也会被打断。
		if guarding: set_guard(false)
		combo_hold = false
		_moving = false
		_play_body_anim(time)
		return
	# 组合拳前摇：原地蓄势（给玩家读招与格挡的窗口），期间不移动也不出手。
	if combo_hold:
		_moving = false
		face_towards(player.global_position, delta, 8.0)
		_combo_pose(time)
		return
	# 精英格挡：每隔一段时间有机会举盾减伤（给玩家一个"读招式"的节奏）。
	if _state == "guard":
		_guard_left -= delta
		_moving = false
		if _guard_left <= 0.0:
			set_guard(false)
			_state = "engage"
		_play_body_anim(time)
		return
	if elite != "" and _state == "engage" and _guard_cd <= 0.0 and attack_ready() and dist < 5.0:
		_guard_cd = 6.0
		if randf() < 0.45:
			_state = "guard"
			_guard_left = 1.2
			set_guard(true)
			_play_guard_clip()
			_play_body_anim(time)
			return
	match ai_mode:
		"charger": _ai_charger(delta, time, player, dist, to_player)
		"kiter": _ai_kiter(delta, time, player, dist, to_player)
		"summoner": _ai_summoner(delta, time, player, dist, to_player)
	_play_body_anim(time)

func _dir_norm(v: Vector3) -> Vector3:
	var n := v
	n.y = 0.0
	return n.normalized() if n.length_squared() > 0.0001 else Vector3.ZERO

## 推进：受小队指挥时走阵位（前排压上、远程居后），否则直取玩家。
## 阵位由世界每帧算好（相对玩家、按阵型展开），因此「列阵」在移动中也保持。
func _step_towards(delta: float, to_player: Vector3, running := false) -> bool:
	var dir := _dir_norm(to_player)
	if squad_driven:
		var to_a := squad_anchor - global_position
		to_a.y = 0.0
		if to_a.length() > 0.7:
			dir = to_a.normalized()
	return move_step(delta, dir, running)

## 组合拳前摇姿态：远程张弓、术士抬手、近战压低重心蓄势（都有实际关节活动）。
func _combo_pose(time: float) -> void:
	if visual == null: return
	var want := "combo_" + squad_role
	if _cur_clip != want:
		_cur_clip = want
		match squad_role:
			"back": AssetLib.play_clip(visual, ["1H_Ranged_Aim", "1H_Ranged_Shoot"], false)
			"rear": AssetLib.play_clip(visual, ["Spellcast_Raise", "Spellcast_Shoot"], true)
			_: AssetLib.play_clip(visual, AssetLib.ANIM_IDLE, true)
	if squad_role == "front":
		visual.rotation.x = -0.16 + sin(time * 16.0) * 0.03
		visual.position.y = absf(sin(time * 16.0)) * 0.03

## 执行组合拳（前摇结束时由小队指挥统一唤醒）：同一拍出手，形成"组合拳"。
func execute_combo(name: String) -> void:
	combo_hold = false
	if dead: return
	match name:
		"volley":
			if squad_role != "back": return
			_shoot_cd = 2.6
			play_anim("attack", 0.7)
			_play_attack_clip()
			world.spawn_enemy_projectile(self, atk)
		"charge":
			if squad_role != "front": return
			_state = "lunge"
			_windup = 0.45
			play_anim("attack", 1.0)
			_play_attack_clip()
		"swarm":
			if squad_role != "rear": return
			_summon_cd = 8.0
			play_anim("cast", 0.9)
			_play_attack_clip("Spellcast_Summon")
			world.spawn_minions(self, 3)

func _ai_charger(delta: float, time: float, player: Actor, dist: float, to_player: Vector3) -> void:
	var rng := 1.9
	if _state == "windup":
		_windup -= delta
		face_towards(player.global_position, delta)
		_moving = false
		if _windup <= 0.0:
			_state = "lunge"
			_windup = 0.4
		return
	if _state == "lunge":
		_windup -= delta
		var dir := _dir_norm(to_player)
		move_step(delta, dir, true)
		if dist < rng + 0.3:
			world.enemy_hit_player(self)
			_state = "engage"
			set_attack_cooldown(1.6)
		elif _windup <= 0.0:
			_state = "engage"
			set_attack_cooldown(1.2)
		return
	# 常态接近。
	if attack_ready():
		if dist > rng + 0.5:
			_step_towards(delta, to_player)
		else:
			_state = "windup"
			_windup = 0.55
			play_anim("attack", 1.1)
			_play_attack_clip()
	else:
		_moving = false

func _ai_kiter(delta: float, time: float, player: Actor, dist: float, to_player: Vector3) -> void:
	var dir := _dir_norm(to_player)
	if squad_driven:
		# 阵法走位：远程站到阵位上点射（不再自行进退/环绕，位置由阵型决定）。
		var to_a := squad_anchor - global_position
		to_a.y = 0.0
		if to_a.length() > 1.1:
			move_step(delta, to_a.normalized(), to_a.length() > 4.0)
		else:
			_moving = false
	elif dist < 5.0:
		move_step(delta, -dir)  # 后撤
	elif dist > 8.5:
		move_step(delta, dir)
	else:
		# 环绕走位。
		var perp := Vector3(-dir.z, 0, dir.x) * _strafe
		if not move_step(delta, perp):
			_strafe = -_strafe
	if _shoot_cd <= 0.0 and attack_ready() and dist < 10.5:
		_shoot_cd = 2.4
		play_anim("attack", 0.7)
		_play_attack_clip()
		world.spawn_enemy_projectile(self, atk)

func _ai_summoner(delta: float, time: float, player: Actor, dist: float, to_player: Vector3) -> void:
	var dir := _dir_norm(to_player)
	if squad_driven:
		# 术士待在最后阵，由前排挡枪。
		var to_a := squad_anchor - global_position
		to_a.y = 0.0
		if to_a.length() > 1.2:
			move_step(delta, to_a.normalized(), to_a.length() > 5.0)
		else:
			_moving = false
	elif dist < 6.0:
		move_step(delta, -dir)
	elif dist > 10.0:
		move_step(delta, dir)
	else:
		_moving = false
	if _summon_cd <= 0.0 and attack_ready():
		_summon_cd = 8.0
		play_anim("cast", 0.9)
		_play_attack_clip("Spellcast_Summon")
		world.spawn_minions(self, 2)
	elif _shoot_cd <= 0.0 and attack_ready() and dist < 12.0:
		_shoot_cd = 3.2
		play_anim("cast", 0.8)
		_play_attack_clip("Spellcast_Shoot")
		world.spawn_enemy_projectile(self, atk)

## 程序化身体摆动（叠加在骨架动画之上：移动/待机播骨骼剪辑，攻击保留程序化前倾）。
func _play_body_anim(time: float) -> void:
	if visual == null: return
	# 骨骼剪辑切换（带缓存，避免每帧 find_child / play）。
	if _skel_ap and _anim.type != "attack" and _anim.type != "cast":
		var want := "walk" if _moving else "idle"
		if _cur_clip != want:
			_cur_clip = want
			var ok := AssetLib.play_clip(visual, AssetLib.ANIM_WALK if _moving else AssetLib.ANIM_IDLE, true)
			if not ok: _skel_ap = null  # 无可用动画则停用骨骼层
	var phase: float = get_meta("walk_phase", 0.0)
	if _moving:
		visual.rotation.z = sin(time * 9.0 + phase) * 0.05
		visual.position.y = absf(sin(time * 9.0 + phase)) * 0.06
		visual.rotation.x = 0.06
	else:
		visual.rotation.z = lerpf(visual.rotation.z, 0.0, 0.1)
		visual.position.y = sin(time * 1.7 + phase) * 0.02
		visual.rotation.x = lerpf(visual.rotation.x, 0.0, 0.1)
	if _skel_ap == null:
		# 无骨骼动画时的兜底：用整体前倾代替攻击/施法动作。
		if _anim.type == "attack":
			var p := clampf(_anim.t / maxf(_anim.dur, 0.01), 0.0, 1.0)
			visual.rotation.x = sin(p * PI) * -0.35
		elif _anim.type == "cast":
			var p2 := clampf(_anim.t / maxf(_anim.dur, 0.01), 0.0, 1.0)
			visual.rotation.x = sin(p2 * PI) * -0.2

## 攻击/施法动作：播放真实骨骼剪辑（关节活动），取代整体前倾。
func _play_attack_clip(clip := "") -> void:
	if _skel_ap == null: return
	if clip == "": clip = _default_attack_clip()
	_cur_clip = "action"   # 占位：动作结束后移动/待机层会重新接管
	AssetLib.play_clip(visual, [clip], false)

func _default_attack_clip() -> String:
	match ai_mode:
		"kiter": return "1H_Ranged_Shoot"
		"summoner": return "Spellcast_Shoot"
	return "1H_Melee_Attack_Chop"

## 举盾格挡动作（循环）。
func _play_guard_clip() -> void:
	if _skel_ap == null: return
	_cur_clip = "guard"
	AssetLib.play_clip(visual, ["Blocking"], true)

## 受击：播放 Hit 剪辑（带冷却，连打时不反复重播）。
func take_damage(amount: float, from: Node3D, knock_dir: Vector3 = Vector3.ZERO, true_dmg := false) -> int:
	var dealt := super.take_damage(amount, from, knock_dir, true_dmg)
	if dealt > 0 and not dead and _skel_ap != null and _hit_anim_cd <= 0.0 and not guarding and _anim.type != "attack":
		_hit_anim_cd = 0.5
		_cur_clip = "hit"
		AssetLib.play_clip(visual, AssetLib.ANIM_HIT, false)
	return dealt

## 精英掉落倍率。
func loot_mult() -> float:
	return 2.0 if elite != "" else 1.0
