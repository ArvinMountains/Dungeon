class_name WildAnimal
extends Actor
## 野外动物：巡逻 / 受惊逃跑 / 被激怒反击 三段行为。可被捕兽网驯服为宠物。

var species := "rabbit"
var mode := "flee"  # Bestiary.ANIMALS.mode: flee | hostile
var provoked := false
var captured := false
var world = null

var _state := "patrol"  # patrol | graze | flee | chase
var _wander_target := Vector3.ZERO
var _wander_wait := 0.0
var _flee_t := 0.0
var _bite_cd := 0.0

func setup(id: String) -> void:
	species = id
	var def: Dictionary = Bestiary.ANIMALS[id]
	display_name = def.name
	mode = def.mode
	hp_max = def.hp
	hp = hp_max
	move_speed = def.speed
	atk = int(def.pet_dmg * 0.6)
	show_bar = false  # 平时隐藏，受伤后显示

func _build_visual() -> void:
	visual = Node3D.new()
	add_child(visual)
	# Kenney cube-pets GLB（CC0）：按种类归一化到真实感身高（原始模型 1.5~2.0m 偏大）。
	var rel := AssetLib.animal_model(species)
	var h := 0.8
	match species:
		"rabbit": h = 0.55
		"deer": h = 1.35
		"boar": h = 0.95
		"wolf": h = 0.8
		"pig": h = 0.7
		_: h = 0.8
	AssetLib.spawn_norm(visual, rel, h, Vector3.ZERO, 0.0, "y")
	visual.set_meta("legs", true)
	# 动物没有死亡剪辑：用整体倒地作为死亡动作。
	died.connect(_on_died)

## 死亡动作：侧倒 + 压低下沉。
func _on_died(_a: Actor = null) -> void:
	if visual == null: return
	_cur_clip = "dead"
	visual.rotation.z = PI * 0.5
	visual.position.y = 0.1

func _bar_height() -> float:
	return 1.5

func ai_tick(delta: float, time: float, player: Actor) -> void:
	if dead or captured:
		_moving = false
		return
	_bite_cd = maxf(0.0, _bite_cd - delta)
	var dist := (player.global_position - global_position).length()
	# 受惊判定：flee 类始终怕人；hostile 类被打过才敌对。
	if mode == "flee" and dist < 5.0 and _state != "flee":
		_state = "flee"
		_flee_t = 2.5
	if mode == "hostile" and not provoked and dist < 2.2:
		provoked = true
	match _state:
		"patrol":
			_patrol(delta, time)
		"graze":
			_wander_wait -= delta
			_moving = false
			if _wander_wait <= 0.0: _state = "patrol"
		"flee":
			_flee_t -= delta
			var away := (global_position - player.global_position).normalized()
			if not move_step(delta, away, true):
				# 被挡住：侧移绕开。
				move_step(delta, away.cross(Vector3.UP), true)
			if _flee_t <= 0.0 and dist > 7.0:
				_state = "patrol"
		"chase":
			if not provoked or dead:
				_state = "patrol"; return
			var to_p := player.global_position - global_position
			if dist > 1.4:
				move_step(delta, to_p.normalized(), true)
			elif _bite_cd <= 0.0:
				_bite_cd = 1.4
				_action_t = 0.55
				_set_clip("attack", AssetLib.ANIM_A_NEG, false)
				world.animal_bite(self, atk)
			if dist > 12.0:
				provoked = false
				_state = "patrol"

func _patrol(delta: float, time: float) -> void:
	if _wander_wait > 0.0:
		_wander_wait -= delta
		_moving = false
		if _wander_wait <= 0.0 and randf() < 0.3:
			_state = "graze"
			_wander_wait = 1.5 + randf() * 2.0
		return
	if _wander_target == Vector3.ZERO or (global_position - _wander_target).length() < 0.5:
		var a := randf() * TAU
		var r := 3.0 + randf() * 6.0
		_wander_target = global_position + Vector3(cos(a) * r, 0, sin(a) * r)
		_wander_wait = 0.8 + randf() * 2.2
		return
	if not move_step(delta, (_wander_target - global_position).normalized(), false):
		_wander_target = Vector3.ZERO

## 被玩家攻击 → 激怒（hostile）或加深恐惧（flee）。
func on_hurt_by_player() -> void:
	show_bar = true
	if mode == "hostile":
		provoked = true
		_state = "chase"
	else:
		_state = "flee"
		_flee_t = 3.5

## 尝试捕获（需 hp < 30%）。成功则转宠物并返回 true。
func try_capture() -> bool:
	if dead or captured: return false
	if float(hp) > float(hp_max) * 0.3: return false
	var chance: float = Bestiary.ANIMALS[species].net_chance
	if randf() < chance:
		captured = true
		GameState.capture_pet(species)
		return true
	# 失败：挣脱并逃跑。
	_state = "flee"
	_flee_t = 4.0
	return false

func _play_body_anim_stub() -> void:
	pass

var _cur_clip := ""      # 当前动物动画
var _action_t := 0.0     # 一次性动作锁（扑咬/威吓期间不被覆盖）

func animate_tick(dt: float, time: float) -> void:
	super.animate_tick(dt, time)
	if visual and not dead:
		_update_clip(dt)
		if _moving:
			visual.position.y = absf(sin(time * 11.0)) * 0.05
		else:
			visual.position.y = lerpf(visual.position.y, 0.0, 0.1)

## 动画状态机：把 AI 状态映射到动物节点动画（关节活动）。
func _update_clip(dt: float) -> void:
	if _action_t > 0.0:
		_action_t -= dt
		return
	if _state == "graze":
		_set_clip("eat", AssetLib.ANIM_A_EAT, true)
	elif _state == "flee" or (_state == "chase" and _moving):
		_set_clip("run", AssetLib.ANIM_A_RUN, true)
	elif _moving:
		_set_clip("walk", AssetLib.ANIM_A_WALK, true)
	else:
		_set_clip("idle", AssetLib.ANIM_A_IDLE, true)

func _set_clip(want: String, names: Array, loop: bool) -> void:
	if _cur_clip == want: return
	_cur_clip = want
	AssetLib.play_clip(visual, names, loop)
