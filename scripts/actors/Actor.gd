class_name Actor
extends Node3D
## 实体基类：玩家角色 / 敌人 / 野兽 / 宠物 / 同伴共用。
## 提供属性框架、状态效果（眩晕/减速/中毒/护盾）、动画状态机、血条、受击反馈。
## 视觉子节点由子类构建（玩家=ActorRig，怪物/野兽=程序化简化模型）。

signal died(actor: Actor)
signal damaged(actor: Actor, amount: int)
signal parried(actor: Actor)   # 完美格挡（招架）成功

var display_name := ""
var faction := "enemy"  # player | enemy | ally | neutral
var rig: ActorRig = null
var visual: Node3D = null  # 非人形视觉根（怪物/野兽）

var hp := 30
var hp_max := 30
var atk := 6
var armor := 0
var crit := 0.05
var move_speed := 2.4
var dead := false

# 防御 / 格挡（招架）：三档战斗动作的最后一块。
# 防御（按住）= 持续减伤；格挡（时机）= 按下后的窗口内受击 → 完全免伤 + 反震 + 反击窗口。
var guarding := false
var guard_window := 0.35       # 招架窗口（秒）：按下防御后的这段时间内受击即完美格挡
var guard_reduction := 0.35    # 防御中受到的伤害倍率（0.35 = 减伤 65%）
var counter_t := 0.0           # 招架成功后的反击窗口（此期间造成的伤害加成）
var _guard_t := 0.0            # 已按住防御的时长
var _block_hit_t := 0.0        # 格挡命中动作计时
var _hit_anim_cd := 0.0        # 受击动作冷却（连打时不反复重播）

# 状态效果。
var stun_t := 0.0
var slow_t := 0.0
var slow_mul := 1.0
var poison_t := 0.0
var poison_dps := 0.0
var shield := 0.0
var temp_buffs := {}  # stat -> {v, t}

# 锁定与移动。
var enemy_target: Node3D = null
var blocked_check: Callable = Callable()  # func(pos: Vector3) -> bool，由世界注入
var _moving := false
var _face_target_yaw := 0.0
var _attack_cd := 0.0

# 动画状态。
var _anim := {"type": "idle", "t": 0.0, "dur": 0.0, "speed": 1.0}
var _hurt_t := 0.0

var _bar_root: Node3D
var _bar_fg: MeshInstance3D
var show_bar := true

func _ready() -> void:
	_build_visual()
	if show_bar:
		_build_bar()

## 子类覆盖：构建视觉。
func _build_visual() -> void:
	pass

func _build_bar() -> void:
	_bar_root = Node3D.new()
	_bar_root.position = Vector3(0, _bar_height(), 0)
	add_child(_bar_root)
	var bg := MeshInstance3D.new()
	var bg_mesh := QuadMesh.new()
	bg_mesh.size = Vector2(1.0, 0.09)
	bg.mesh = bg_mesh
	bg.material_override = GeoBuilder.mat(Color(0.08, 0.05, 0.06), {"unshaded": true})
	bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar_root.add_child(bg)
	_bar_fg = MeshInstance3D.new()
	var fg_mesh := QuadMesh.new()
	fg_mesh.size = Vector2(0.94, 0.055)
	fg_mesh.center_offset = Vector3(0, 0.001, 0)
	_bar_fg.mesh = fg_mesh
	_bar_fg.material_override = GeoBuilder.mat(Color(0.75, 0.25, 0.28), {"unshaded": true})
	_bar_fg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar_root.add_child(_bar_fg)
	for q in [_bar_root.get_child(0), _bar_fg]:
		# 血条 quad 始终面向相机（材质级 billboard，需独享材质避免污染缓存）。
		if q.material_override is StandardMaterial3D:
			var bm: StandardMaterial3D = q.material_override.duplicate()
			bm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			q.material_override = bm
	_refresh_bar()

func _bar_height() -> float:
	return 2.9

func _refresh_bar() -> void:
	if _bar_fg == null: return
	var ratio := clampf(float(hp) / float(maxi(hp_max, 1)), 0.0, 1.0)
	_bar_fg.scale = Vector3(ratio, 1.0, 1.0)
	_bar_fg.position.x = -(1.0 - ratio) * 0.47
	var m: StandardMaterial3D = _bar_fg.material_override
	m.albedo_color = Color(0.45, 0.75, 0.4) if ratio > 0.5 else (Color(0.9, 0.7, 0.25) if ratio > 0.25 else Color(0.8, 0.25, 0.25))

## 动画入口（每帧由世界调用）。
func animate_tick(dt: float, time: float) -> void:
	_attack_cd = maxf(0.0, _attack_cd - dt)
	# 状态效果。
	if stun_t > 0.0: stun_t -= dt
	if slow_t > 0.0:
		slow_t -= dt
		if slow_t <= 0.0: slow_mul = 1.0
	if poison_t > 0.0:
		poison_t -= dt
		take_damage(poison_dps * dt, null, Vector3.ZERO, true)
	for k in temp_buffs.keys():
		temp_buffs[k].t -= dt
		if temp_buffs[k].t <= 0.0: temp_buffs.erase(k)
	if _hurt_t > 0.0:
		_hurt_t -= dt
	if counter_t > 0.0: counter_t -= dt
	if _block_hit_t > 0.0: _block_hit_t -= dt
	if _hit_anim_cd > 0.0: _hit_anim_cd -= dt
	if guarding: _guard_t += dt
	_apply_anim(dt, time)

func _apply_anim(dt: float, time: float) -> void:
	var t: float = _anim.t + dt
	_anim.t = t
	if rig == null: return
	if _block_hit_t > 0.0:
		rig.animate(dt, time, {"type": "block_hit"})
		return
	if _hurt_t > 0.0:
		rig.animate(dt, time, {"type": "hurt", "phase": 1.0 - _hurt_t / 0.35})
		return
	if guarding:
		# 防御姿态：循环 Blocking（有盾举盾，无盾横举武器）。
		rig.animate(dt, time, {"type": "guard"})
		return
	match _anim.type:
		"attack", "cast", "ultimate":
			var p: float = t / maxf(_anim.dur, 0.01)
			rig.animate(dt, time, {"type": _anim.type, "phase": clampf(p, 0.0, 1.0), "time": time})
			if p >= 1.0: _anim.type = "idle"
		_:
			if _moving:
				rig.animate(dt, time, {"type": "walk", "time": time, "speed": _anim.speed})
			else:
				rig.animate(dt, time, {"type": "idle", "time": time})

## 播放动作。
func play_anim(type: String, dur: float) -> void:
	_anim = {"type": type, "t": 0.0, "dur": dur, "speed": 1.0}

func is_busy() -> bool:
	return _anim.type in ["attack", "cast", "ultimate"]

## 防御中无法攻击（需先松开防御键）。
func attack_ready() -> bool:
	return _attack_cd <= 0.0 and not is_busy() and stun_t <= 0.0 and not guarding

func set_attack_cooldown(cd: float) -> void:
	_attack_cd = cd

# ---------------- 防御 / 格挡 ----------------
## 开关防御姿态（按下瞬间开始计算招架窗口）。
func set_guard(on: bool) -> void:
	if on == guarding: return
	guarding = on
	if on:
		_guard_t = 0.0
	elif rig:
		rig.animate(0.0, 0.0, {"type": "idle"})

## 是否处于招架窗口内（按下防御后的一小段时间）。
func guard_parry_active() -> bool:
	return guarding and _guard_t <= guard_window

## 朝向：平滑转向目标 yaw。
func face_towards(point: Vector3, dt: float, rate := 10.0) -> void:
	var d := point - global_position
	if d.length_squared() < 0.0001: return
	var want := atan2(d.x, d.z)
	rotation.y = lerp_angle(rotation.y, want, clampf(rate * dt, 0.0, 1.0))

## 移动一步（世界负责碰撞注入）。
func move_step(delta: float, dir: Vector3, running := false) -> bool:
	if dir.length_squared() < 0.0001 or stun_t > 0.0:
		_moving = false
		return false
	var spd := move_speed * slow_mul * (1.45 if running else 1.0)
	if guarding: spd *= 0.45  # 防御中移动变慢
	var desired := dir.normalized() * spd * delta
	var next := global_position + desired
	next.y = global_position.y
	if blocked_check.is_valid() and blocked_check.call(next):
		# 贴墙滑行：分轴退让，避免斜向巷道/建筑拐角把角色卡死（此前直进受阻即停）。
		var slide_x := global_position + Vector3(desired.x, 0, 0)
		var slide_z := global_position + Vector3(0, 0, desired.z)
		var ok_x: bool = not blocked_check.call(slide_x)
		var ok_z: bool = not blocked_check.call(slide_z)
		if ok_x and absf(desired.x) > 0.0001:
			next = slide_x
		elif ok_z and absf(desired.z) > 0.0001:
			next = slide_z
		else:
			_moving = false
			return false
	global_position = next
	_face_target_yaw = atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, _face_target_yaw, clampf(12.0 * delta, 0.0, 1.0))
	_moving = true
	_anim.speed = 1.0 if not running else 1.25
	return true

func stop_moving() -> void:
	_moving = false

## 有效攻击力（含临时增益）。
func effective_atk() -> int:
	var a := float(atk)
	if temp_buffs.has("atk"): a += temp_buffs["atk"].v
	return int(round(a))

func is_crit_hit() -> bool:
	var c: float = crit + (float(temp_buffs["crit"].v) if temp_buffs.has("crit") else 0.0)
	return randf() < c

## 受击。返回实际伤害。true_dmg 跳过护甲。
## 防御中：招架窗口内 = 完美格挡（免伤 + 反震 + 反击窗口）；否则按 guard_reduction 减伤。
func take_damage(amount: float, from: Node3D, knock_dir: Vector3 = Vector3.ZERO, true_dmg := false) -> int:
	if dead: return 0
	if guarding and not true_dmg:
		if guard_parry_active():
			return _resolve_parry(from)
		amount *= guard_reduction
	var dmg := amount
	if not true_dmg:
		dmg = maxf(1.0, amount - float(armor))
	if temp_buffs.has("armor"): dmg = maxf(1.0, dmg - float(temp_buffs["armor"].v))
	if shield > 0.0:
		var absorbed := minf(shield, dmg)
		shield -= absorbed
		dmg -= absorbed
	var final := int(ceil(dmg))
	hp = maxi(0, hp - final)
	_hurt_t = 0.35
	_refresh_bar()
	damaged.emit(self, final)
	if rig: rig.flash_hit()
	if hp <= 0:
		dead = true
		died.emit(self)
	elif knock_dir.length_squared() > 0.0001:
		var push := knock_dir.normalized() * 0.35
		var next := global_position + push
		next.y = global_position.y
		if not (blocked_check.is_valid() and blocked_check.call(next)):
			global_position = next
	return final

func heal(v: int) -> void:
	hp = mini(hp + v, hp_max)
	_refresh_bar()

## 完美格挡结算：完全免伤 + 打断并反震攻击者 + 开启反击窗口。
func _resolve_parry(from: Node3D) -> int:
	_block_hit_t = 0.45
	counter_t = 1.5
	if rig: rig.animate(0.0, 0.0, {"type": "block_hit"})
	if from != null and from != self and from is Actor:
		var foe := from as Actor
		foe.apply_status("stun", 1.2)
		var away := foe.global_position - global_position
		away.y = 0.0
		if away.length_squared() > 0.001:
			foe.global_position += away.normalized() * 1.0
	parried.emit(self)
	damaged.emit(self, 0)
	return 0

func add_shield(v: float, dur := 0.0) -> void:
	shield += v
	if dur > 0.0:
		# 护盾到期由 temp_buffs 驱动清除。
		temp_buffs["shield_clear"] = {"v": -v, "t": dur, "_shield": v}

func apply_buff(stat: String, v: float, dur: float) -> void:
	temp_buffs[stat] = {"v": v, "t": dur}

func apply_status(kind: String, dur: float, value := 0.0) -> void:
	match kind:
		"stun": stun_t = maxf(stun_t, dur)
		"slow": slow_t = maxf(slow_t, dur); slow_mul = value if value > 0.0 else 0.65
		"poison": poison_t = maxf(poison_t, dur); poison_dps = value

func dispose() -> void:
	queue_free()
