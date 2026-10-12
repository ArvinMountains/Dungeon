class_name ActorRig
extends Node3D
## 角色装配体（KayKit Adventurers 骨骼版，CC0）。
## - 模型：KayKit Character Pack: Adventurers 的骨骼角色（41 关节，76 条动画剪辑）。
##   archer=Rogue / warrior=Barbarian / shield=Knight / assassin=Rogue_Hooded / mage=Mage。
## - 动作：由 pose.type 映射到真实剪辑（idle/walk/attack/cast/ultimate/hurt/showcase），
##   一次性动作按游戏内的动作时长自动换算播放速度，保证挥砍/施法在一个动作周期内走完。
## - 武器：按职业显示角色内置武器网格（剑/盾/斧/法杖/弩/匕首），其余武器变体隐藏。
## - 挂点：handslot.r/l、chest、head 上挂 BoneAttachment3D，供武器/火把/粒子复用。
## 脚底原点 (0,0,0)，面朝 +Z（与 KayKit 模型原生朝向一致）。

const CHAR_DIR := "res://assets/models/characters/"
const TARGET_HEIGHT := 2.0      # 归一化身高（与 NPC 1.8m 同量级）
const MODEL_YAW_FIX := 0.0      # KayKit 模型原生朝 +Z（与游戏约定一致，无需额外翻转）
const BLEND := 0.12             # 剪辑交叉淡入时长

## 职业 → 模型文件。
const MODEL_BY_CLASS := {
	"archer": "Rogue.glb",
	"warrior": "Barbarian.glb",
	"shield": "Knight.glb",
	"assassin": "Rogue_Hooded.glb",
	"mage": "Mage.glb",
	"barbarian": "Barbarian.glb",
}

## 职业 → 动作剪辑（KayKit 通用命名）。
const CLIPS := {
	"archer": {"attack": "1H_Ranged_Shoot", "cast": "Spellcast_Shoot", "ultimate": "1H_Ranged_Shoot"},
	"warrior": {"attack": "2H_Melee_Attack_Slice", "cast": "2H_Melee_Attack_Chop", "ultimate": "2H_Melee_Attack_Spin"},
	"shield": {"attack": "1H_Melee_Attack_Slice_Diagonal", "cast": "Block_Attack", "ultimate": "1H_Melee_Attack_Stab"},
	"assassin": {"attack": "Dualwield_Melee_Attack_Slice", "cast": "Dualwield_Melee_Attack_Stab", "ultimate": "Dualwield_Melee_Attack_Chop"},
	"mage": {"attack": "Spellcast_Shoot", "cast": "Spellcast_Raise", "ultimate": "Spellcast_Long"},
}

## idle / walk 剪辑候选名（各角色命名一致，缺失时逐个回退）。
const IDLE_CLIPS := ["Idle", "Unarmed_Idle", "2H_Melee_Idle"]
const WALK_CLIPS := ["Walking_A", "Walking_B", "Walking_C"]
const FALLBACK_IDLE := "Idle"

var class_id := "archer"
var skeleton: Skeleton3D
var hand_r: BoneAttachment3D
var hand_l: BoneAttachment3D
var chest_fx: BoneAttachment3D
var head_fx: BoneAttachment3D
var model_root: Node3D          # 便于调试/测试读取模型

var _pivot: Node3D
var _ap: AnimationPlayer
var _current := ""
var _last_type := ""
var _attack_dur := 0.8
var _idle_clip := FALLBACK_IDLE
var _walk_clip := "Walking_A"
var _own_mats: Array[StandardMaterial3D] = []
var _own_colors := {}
var _mat_copy := {}
var _flash_left := 0.0

func _init(id: String = "archer", _seed_v: int = 741) -> void:
	class_id = id

func _ready() -> void:
	var cd: Dictionary = GameState.CLASS_DATA.get(class_id, {})
	_attack_dur = float(cd.get("attack_duration", 0.8))
	_build()

# ---------------- 装配 ----------------
func _build() -> void:
	var rel: String = MODEL_BY_CLASS.get(class_id, "Knight.glb")
	var ps: PackedScene = load(CHAR_DIR + rel)
	_pivot = Node3D.new()
	_pivot.rotation.y = deg_to_rad(MODEL_YAW_FIX)
	add_child(_pivot)
	if ps == null:
		push_warning("ActorRig 缺少角色模型: " + rel)
		return
	model_root = ps.instantiate()
	_pivot.add_child(model_root)

	# 归一化身高并把脚底对齐到 y=0、水平居中。
	var m := _measure(model_root)
	var s := TARGET_HEIGHT / maxf(m.size.y, 0.001)
	var center: Vector3 = (m.min + m.max) * 0.5
	model_root.scale = Vector3.ONE * s
	model_root.position = Vector3(-center.x * s, -m.min.y * s, -center.z * s)

	skeleton = _first_of_type(model_root, "Skeleton3D") as Skeleton3D
	_ap = _first_of_type(model_root, "AnimationPlayer") as AnimationPlayer
	if _ap == null:
		push_warning("ActorRig 角色缺少 AnimationPlayer: " + rel)
	_resolve_clip_names()
	_apply_weapons(rel)
	_build_attachments()
	_collect_materials()
	_validate_assets(rel)

## 寻找实例内的首个指定类型节点。
func _first_of_type(root: Node, type_name: String) -> Node:
	var found := root.find_children("*", type_name, true, false)
	return found[0] if found.size() > 0 else null

## 量取实例的本地 AABB（遍历 MeshInstance3D，累积变换）。
func _measure(root: Node3D) -> Dictionary:
	var mn := Vector3.INF
	var mx := -Vector3.INF
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var n: Node = e[0]
		var xf: Transform3D = e[1]
		if n is Node3D:
			xf = xf * (n as Node3D).transform
		if n is MeshInstance3D:
			var a: AABB = (n as MeshInstance3D).get_aabb()
			for i in range(8):
				var corner := a.position + Vector3(
					a.size.x * float(i & 1), a.size.y * float((i >> 1) & 1), a.size.z * float((i >> 2) & 1))
				var p: Vector3 = xf * corner
				mn = mn.min(p)
				mx = mx.max(p)
		for c in n.get_children():
			stack.push_back([c, xf])
	if mn == Vector3.INF:
		return {"min": Vector3.ZERO, "max": Vector3.ONE, "size": Vector3.ONE}
	return {"min": mn, "max": mx, "size": mx - mn}

## 解析 idle/walk 的可用剪辑名（不同角色命名略有差异时兜底）。
func _resolve_clip_names() -> void:
	if _ap == null: return
	_idle_clip = _pick_clip(IDLE_CLIPS, FALLBACK_IDLE)
	_walk_clip = _pick_clip(WALK_CLIPS, "Walking_A")

func _pick_clip(cands: Array, fallback: String) -> String:
	for n in cands:
		if _has_clip(String(n)):
			return String(n)
	return fallback

func _has_clip(name: String) -> bool:
	return _ap != null and _ap.has_animation(name)

## 按职业显示/隐藏内置武器变体（KayKit 把全部武器摆在同一手部挂点上，需裁剪）。
func _apply_weapons(rel: String) -> void:
	if model_root == null: return
	AssetLib.prune_weapon_variants(model_root, AssetLib.default_weapons_for_model(rel))

## 资产完整性自检：关键剪辑/骨骼挂点缺失时告警（KayKit 包版本差异的兜底提示）。
func _validate_assets(rel: String) -> void:
	var missing: Array = []
	for t in ["attack", "cast", "ultimate"]:
		var c := String(CLIPS.get(class_id, {}).get(t, ""))
		if c != "" and not _has_clip(c):
			missing.append(c)
	if not _has_clip("Hit_A"): missing.append("Hit_A")
	if not _has_clip("Cheer"): missing.append("Cheer")
	if missing.size() > 0:
		push_warning("ActorRig(%s) 缺少剪辑: %s" % [rel, ", ".join(missing)])
	if hand_r == null or hand_l == null:
		push_warning("ActorRig(%s) 未解析到手部骨骼挂点" % rel)

## 在真实骨骼上建挂点（武器/火把/粒子复用）。
func _build_attachments() -> void:
	if skeleton == null: return
	hand_r = _attach_bone(["handslot.r", "handslot_r", "hand.r", "handslot"], "r")
	hand_l = _attach_bone(["handslot.l", "handslot_l", "hand.l", "handslot"], "l")
	chest_fx = _attach_bone(["chest", "spine.002", "spine"], "")
	head_fx = _attach_bone(["head"], "")

## 按候选名（再按后缀）找骨骼并挂 BoneAttachment3D。
func _attach_bone(cands: Array, suffix: String) -> BoneAttachment3D:
	var idx := -1
	for c in cands:
		for b in skeleton.get_bone_count():
			var bn := skeleton.get_bone_name(b)
			if bn == String(c) or AssetLib.norm_name(bn) == AssetLib.norm_name(String(c)):
				idx = b
				break
		if idx >= 0: break
	if idx < 0 and suffix != "":
		for b in skeleton.get_bone_count():
			var bn2 := skeleton.get_bone_name(b)
			if AssetLib.norm_name(bn2).begins_with("handslot") and AssetLib.norm_name(bn2).ends_with(suffix):
				idx = b
				break
	if idx < 0: return null
	var a := BoneAttachment3D.new()
	a.bone_name = skeleton.get_bone_name(idx)
	skeleton.add_child(a)
	return a

## 收集模型表面材质（每个装配体独立副本，供闪白/淡出）。
func _collect_materials() -> void:
	if model_root == null: return
	var stack: Array = [model_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh == null: continue
			for si in mi.mesh.get_surface_count():
				var src: Material = mi.get_surface_override_material(si)
				if src == null:
					src = mi.mesh.surface_get_material(si)
				if src is StandardMaterial3D:
					var key := src as StandardMaterial3D
					if not _mat_copy.has(key):
						var dup: StandardMaterial3D = key.duplicate()
						_mat_copy[key] = dup
						_own_mats.append(dup)
						_own_colors[dup] = dup.albedo_color
					mi.set_surface_override_material(si, _mat_copy[key])

# ---------------- 动画 ----------------
## 姿态驱动入口。pose: {"type": "idle|walk|attack|cast|ultimate|showcase|hurt", "time": 秒, "speed": 步速系数, "phase": 0..1}
func animate(dt: float, time: float, pose: Dictionary) -> void:
	if _flash_left > 0.0:
		_flash_left -= dt
		if _flash_left <= 0.0:
			for m in _own_mats:
				m.emission_enabled = false
	if _ap == null: return
	var type := String(pose.get("type", "idle"))
	match type:
		"walk":
			_play(_walk_clip, true, float(pose.get("speed", 1.0)))
		"attack", "cast", "ultimate":
			var map: Dictionary = CLIPS.get(class_id, {})
			var clip := String(map.get(type, ""))
			if _last_type != type:
				_play(clip, false, _action_speed(type, clip), true)
		"hurt":
			if _last_type != type:
				_play("Hit_A", false, _action_speed("attack", "Hit_A"), true)
		"guard":
			_play("Blocking", true, 1.0)
		"block_hit":
			_play("Block_Hit", false, 1.8, true)
		"showcase":
			_play("Cheer", true, 1.0)
		_:
			_play(_idle_clip, true, 1.0)
	_last_type = type

## 一次性动作播放速度：让剪辑在游戏内动作时长内走完（避免挥砍被截断）。
func _action_speed(kind: String, clip: String) -> float:
	if _ap == null or clip == "" or not _ap.has_animation(clip):
		return 1.0
	var dur := _ap.get_animation(clip).length
	var target := _attack_dur
	if kind == "cast": target = 0.85
	elif kind == "ultimate": target = 1.05
	return clampf(dur / maxf(target, 0.05), 1.0, 2.4)

## 播放剪辑（相同剪辑且非强制重启时只更新速度）。
func _play(clip: String, loop: bool, speed: float, restart := false) -> void:
	if clip == "" or not _ap.has_animation(clip):
		return
	if clip == _current and not restart:
		_ap.speed_scale = speed
		return
	var a := _ap.get_animation(clip)
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_ap.speed_scale = speed
	_ap.play(clip, BLEND)
	if restart:
		_ap.seek(0.0, true)
	_current = clip

## 将 GPUParticles3D 挂到骨骼（"chest"/"head"/"hand_r"/"hand_l"）。
func attach_effect(p: GPUParticles3D, bone: String = "chest") -> void:
	var t := _attach_target(bone)
	if t == null:
		add_child(p)
		return
	t.add_child(p)

func _attach_target(bone: String) -> Node3D:
	match bone:
		"chest": return chest_fx
		"head": return head_fx
		"hand_r": return hand_r
		"hand_l": return hand_l
	return chest_fx

## 手持火把（木柄 + 火光 + 粒子）。返回挂载节点以便移除。
func hold_torch() -> Node3D:
	var host: Node3D = hand_l if hand_l != null else chest_fx
	if host == null:
		host = self
	var t := Node3D.new()
	host.add_child(t)
	t.position = Vector3(0, 0.06, 0.02)
	GeoBuilder.mesh_instance(t, GeoBuilder.box_geometry(0.05, 0.5, 0.05),
		GeoBuilder.mat(Color(0.3, 0.2, 0.12)), Vector3(0, 0.2, 0))
	var flame := GeoBuilder.octahedron(t, 0.09, Color(1.0, 0.62, 0.2))
	GeoBuilder.mesh_instance(t, flame.mesh,
		GeoBuilder.mat(Color(1.0, 0.62, 0.2), {"emissive": Color(1.0, 0.55, 0.15), "emissive_intensity": 2.2}),
		Vector3(0, 0.52, 0), false)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 6.0
	light.omni_range = 7.5
	light.shadow_enabled = false
	light.position = Vector3(0, 0.56, 0)
	t.add_child(light)
	return t

# ---------------- 反馈 ----------------
func set_opacity(a: float) -> void:
	for m in _own_mats:
		if a >= 0.999:
			m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			m.albedo_color = _own_colors[m]
		else:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.depth_draw_mode = 1  # DEPTH_DRAW_OPAQUE（数值形式，避免版本枚举名差异）
			var c: Color = _own_colors[m]
			m.albedo_color = Color(c.r, c.g, c.b, a)

func flash_hit() -> void:
	for m in _own_mats:
		m.emission_enabled = true
		m.emission = Color(1.0, 0.35, 0.3)
		m.emission_energy_multiplier = 0.9
	_flash_left = 0.09

## 走路脚步声节拍（Walking_A 一个循环两步，约 0.93Hz/循环）。
func footstep_phase(time: float) -> bool:
	return fmod(time * 1.87, 1.0) < 0.12
