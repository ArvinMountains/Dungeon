class_name AssetLib
extends Object
## CC0 资产加载器（Kenney / KayKit GLB）：
## - load_model(rel)：按相对路径加载 PackedScene，进程内缓存（含缺失标记，避免重复 IO）。
## - spawn()：实例化并挂到父节点（Y 轴旋转、统一缩放）。
## - spawn_norm()：按 AABB 归一化尺寸并自动贴地（axis="y" 以高度为准 / "x" 以最大水平边为准）。
## - size_of()：返回资产原始 AABB 尺寸（缓存），供摆放与碰撞体注册参考。
## - play_clip()：查找实例内的 AnimationPlayer 并优先播放可用剪辑（KayKit 骨骼动画）。
## 所有路径相对 res://assets/models/，例如 "town/fountain-round.glb"。

const BASE := "res://assets/models/"

static var _scenes: Dictionary = {}   # rel -> PackedScene | null（null=缺失）
static var _sizes: Dictionary = {}    # rel -> Vector3（AABB size）
static var _uid := 0                  # 自增序号：保证节点名唯一（同名兄弟会被 Godot 自动改名，妨碍调试）

## 生成唯一节点名（AL_ 前缀 + 序号 + 文件名）。
static func _node_name(rel: String) -> String:
	_uid += 1
	return "AL%d_%s" % [_uid, rel.get_file().replace(".glb", "").replace(".gltf", "")]

# ---------------- 加载 ----------------
static func load_model(rel: String) -> PackedScene:
	if _scenes.has(rel):
		return _scenes[rel]
	var path := BASE + rel
	if not ResourceLoader.exists(path):
		push_warning("AssetLib 缺失资产: " + path)
		_scenes[rel] = null
		return null
	var ps: PackedScene = load(path)
	_scenes[rel] = ps
	return ps

# ---------------- Kenney 白模调色板 ----------------
## Kenney 系列 GLB 无内嵌贴图（白模渲染），按模型名关键词上色。
## 只作用于「纯白 albedo + 无贴图 + 无顶点色」的表面；KayKit 等带贴图模型不受影响。
static func _palette_for(rel: String) -> Color:
	var f := rel.get_file().to_lower()
	# 屋顶/山墙。
	if f.begins_with("roof-gable-end") or f.begins_with("roof-gable-top") or f.begins_with("roof-high-gable-end"): return Color(0.66, 0.60, 0.50)
	if f.begins_with("roof"): return Color(0.58, 0.32, 0.25)
	# 墙件（木墙暖棕 / 石墙灰白）。
	if f.begins_with("wall-wood-door"): return Color(0.42, 0.28, 0.17)
	if f.begins_with("wall-wood-window"): return Color(0.55, 0.38, 0.22)
	if f.begins_with("wall-wood"): return Color(0.65, 0.48, 0.30)
	if f.begins_with("wall"): return Color(0.74, 0.70, 0.61)
	if f.begins_with("planks"): return Color(0.60, 0.44, 0.27)
	# 街景家具。
	if f.begins_with("lantern") or f.begins_with("lightpost"): return Color(0.22, 0.21, 0.20)
	if f.begins_with("fountain"): return Color(0.58, 0.57, 0.54)
	if f.begins_with("pillar"): return Color(0.62, 0.60, 0.55)
	if f.begins_with("fence") or f.begins_with("gate"): return Color(0.50, 0.37, 0.23)
	if f.begins_with("cart"): return Color(0.58, 0.42, 0.26)
	if f.begins_with("windmill") or f.begins_with("watermill"): return Color(0.82, 0.76, 0.63)
	if f.begins_with("banner-red"): return Color(0.75, 0.26, 0.22)
	if f.begins_with("banner-green"): return Color(0.30, 0.55, 0.32)
	if f.begins_with("banner"): return Color(0.36, 0.46, 0.70)
	if f.begins_with("stall-red"): return Color(0.72, 0.30, 0.26)
	if f.begins_with("stall-green"): return Color(0.32, 0.56, 0.34)
	if f.begins_with("stall"): return Color(0.70, 0.58, 0.40)
	if f.begins_with("chimney"): return Color(0.50, 0.34, 0.27)
	if f.begins_with("hedge"): return Color(0.28, 0.46, 0.26)
	if f.begins_with("stairs"): return Color(0.55, 0.53, 0.50)
	if f.begins_with("balcony") or f.begins_with("overhang"): return Color(0.55, 0.40, 0.25)
	if f.begins_with("wheel"): return Color(0.45, 0.32, 0.20)
	# 自然/植被。
	if f.begins_with("tree") or f.begins_with("pine") or f.begins_with("bush") or f.begins_with("plant") or f.begins_with("grass"): return Color(0.30, 0.50, 0.28)
	if f.begins_with("flower"): return Color(0.85, 0.45, 0.55)
	if f.begins_with("mushroom"): return Color(0.73, 0.26, 0.22)
	if f.begins_with("cactus"): return Color(0.36, 0.55, 0.30)
	if f.begins_with("rock") or f.begins_with("stone") or f.begins_with("cliff"): return Color(0.52, 0.52, 0.50)
	if f.begins_with("log") or f.begins_with("stump") or f.begins_with("campfire") or f.begins_with("trunk") or f.begins_with("debris") or f.begins_with("bench") or f.begins_with("shovel"): return Color(0.45, 0.32, 0.20)
	if f.begins_with("path"): return Color(0.60, 0.56, 0.50)
	if f.begins_with("tent"): return Color(0.68, 0.56, 0.38)
	if f.begins_with("sign") or f.begins_with("platform"): return Color(0.52, 0.38, 0.24)
	if f.begins_with("statue"): return Color(0.62, 0.62, 0.58)
	# 墓园套件。
	if f.begins_with("gravestone") or f.begins_with("altar") or f.begins_with("crypt") or f.begins_with("coffin") or f.begins_with("cross") or f.begins_with("column") or f.begins_with("urn") or f.begins_with("iron"): return Color(0.56, 0.57, 0.55)
	if f.begins_with("pumpkin"): return Color(0.86, 0.46, 0.14)
	if f.begins_with("candle"): return Color(0.88, 0.83, 0.66)
	if f.begins_with("character-ghost"): return Color(0.80, 0.88, 0.90)
	if f.begins_with("character-vampire"): return Color(0.35, 0.20, 0.30)
	if f.begins_with("character-keeper"): return Color(0.30, 0.35, 0.40)
	if f.begins_with("character"): return Color(0.60, 0.58, 0.55)
	# 宠物/动物（cube-pets）。
	if f.begins_with("animal-bunny") or f.begins_with("animal-polar") or f.begins_with("animal-sheep") or f.begins_with("animal-panda"): return Color(0.88, 0.86, 0.82)
	if f.begins_with("animal-deer") or f.begins_with("animal-giraffe"): return Color(0.64, 0.44, 0.27)
	if f.begins_with("animal-dog") or f.begins_with("animal-fox") or f.begins_with("animal-monkey") or f.begins_with("animal-beaver") or f.begins_with("animal-koala"): return Color(0.70, 0.50, 0.30)
	if f.begins_with("animal-hog") or f.begins_with("animal-pig") or f.begins_with("animal-crab"): return Color(0.88, 0.62, 0.62)
	if f.begins_with("animal-cat") or f.begins_with("animal-lion") or f.begins_with("animal-tiger") or f.begins_with("animal-caterpillar"): return Color(0.82, 0.58, 0.32)
	if f.begins_with("animal-cow"): return Color(0.92, 0.90, 0.88)
	if f.begins_with("animal-bee"): return Color(0.92, 0.76, 0.20)
	if f.begins_with("animal-chick"): return Color(0.96, 0.86, 0.42)
	if f.begins_with("animal-penguin"): return Color(0.26, 0.27, 0.31)
	if f.begins_with("animal-parrot"): return Color(0.42, 0.66, 0.86)
	if f.begins_with("animal-fish"): return Color(0.46, 0.66, 0.86)
	if f.begins_with("animal-elephant"): return Color(0.62, 0.64, 0.68)
	return Color(0.72, 0.66, 0.58)

## 为实例内的白模表面覆盖调色板材质（带轻微明度抖动避免大面平色）。
static func _apply_palette(inst: Node, rel: String) -> void:
	var col := _palette_for(rel)
	var stack: Array = [inst]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			for si in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(si)
				var need := true
				if mat is StandardMaterial3D:
					var sm := mat as StandardMaterial3D
					need = sm.albedo_texture == null and not sm.vertex_color_use_as_albedo \
						and sm.albedo_color.r > 0.93 and sm.albedo_color.g > 0.93 and sm.albedo_color.b > 0.93
				if need:
					var ov := StandardMaterial3D.new()
					var jitter := 1.0 + (float(hash(rel) % 100) / 100.0 - 0.5) * 0.06
					ov.albedo_color = Color(minf(col.r * jitter, 1.0), minf(col.g * jitter, 1.0), minf(col.b * jitter, 1.0))
					ov.roughness = 0.9
					mi.set_surface_override_material(si, ov)

## 测量实例化后的本地 AABB（需已入树，遍历所有 MeshInstance3D）。
static func _measure(root: Node3D) -> AABB:
	var total := AABB()
	var first := true
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var aabb: AABB = mi.get_aabb()
			# 变换到 root 局部空间。
			var xf: Transform3D = root.global_transform.affine_inverse() * mi.global_transform
			var corners := [
				xf * (aabb.position), xf * (aabb.position + Vector3(aabb.size.x, 0, 0)),
				xf * (aabb.position + Vector3(0, aabb.size.y, 0)), xf * (aabb.position + Vector3(0, 0, aabb.size.z)),
				xf * (aabb.position + Vector3(aabb.size.x, aabb.size.y, 0)),
				xf * (aabb.position + Vector3(aabb.size.x, 0, aabb.size.z)),
				xf * (aabb.position + Vector3(0, aabb.size.y, aabb.size.z)),
				xf * (aabb.position + aabb.size),
			]
			for p in corners:
				if first:
					total = AABB(p, Vector3.ZERO)
					first = false
				else:
					total = total.expand(p)
	return total

## 原始尺寸（旋转前、缩放前）。未入树时内部临时实例化测量。
static func size_of(rel: String) -> Vector3:
	if _sizes.has(rel):
		return _sizes[rel]
	var ps := load_model(rel)
	if ps == null:
		_sizes[rel] = Vector3.ONE
		return Vector3.ONE
	var inst := ps.instantiate()
	var aabb := _measure_static(inst)
	inst.free()
	_sizes[rel] = aabb.size
	return aabb.size

## 静态测量：不入树，用局部变换链推导（假设线性层级，Kenney/KayKit GLB 均满足）。
static func _measure_static(root: Node3D) -> AABB:
	var total := AABB()
	var first := true
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var n: Node = entry[0]
		var xf: Transform3D = entry[1]
		if n is Node3D:
			xf = xf * (n as Node3D).transform
		if n is MeshInstance3D:
			var aabb: AABB = (n as MeshInstance3D).get_aabb()
			var corners := [
				xf * aabb.position, xf * (aabb.position + Vector3(aabb.size.x, 0, 0)),
				xf * (aabb.position + Vector3(0, aabb.size.y, 0)), xf * (aabb.position + Vector3(0, 0, aabb.size.z)),
				xf * (aabb.position + Vector3(aabb.size.x, aabb.size.y, 0)),
				xf * (aabb.position + Vector3(aabb.size.x, 0, aabb.size.z)),
				xf * (aabb.position + Vector3(0, aabb.size.y, aabb.size.z)),
				xf * (aabb.position + aabb.size),
			]
			for p in corners:
				if first:
					total = AABB(p, Vector3.ZERO)
					first = false
				else:
					total = total.expand(p)
		for c in n.get_children():
			stack.push_back([c, xf])
	return total

# ---------------- 实例化 ----------------
## 基础生成：uniform 缩放 + Y 轴旋转（角度制）。
static func spawn(parent: Node3D, rel: String, pos := Vector3.ZERO, rot_y_deg := 0.0, scl := 1.0) -> Node3D:
	var ps := load_model(rel)
	if ps == null or parent == null:
		return null
	var inst := ps.instantiate() as Node3D
	_apply_palette(inst, rel)
	parent.add_child(inst)
	inst.name = _node_name(rel)  # Godot 节点名禁止 : / 等字符，统一用下划线
	inst.position = pos
	inst.rotation.y = deg_to_rad(rot_y_deg)
	inst.scale = Vector3.ONE * scl
	return inst

## 归一化生成：沿 axis（"y"=高度 / "x"=最大水平边）缩放到 target 尺寸，底面贴合 pos.y。
## 返回包裹节点（模型挂在 wrapper 下，wrapper 位于 pos，可再整体旋转）。
static func spawn_norm(parent: Node3D, rel: String, target: float, pos := Vector3.ZERO, rot_y_deg := 0.0, axis := "y") -> Node3D:
	var ps := load_model(rel)
	if ps == null or parent == null:
		return null
	var inst := ps.instantiate() as Node3D
	_apply_palette(inst, rel)
	var sz := _measure_static(inst)
	# axis="x"/"z" 取该轴；"h" 取最大水平边（扁平模型如岩石/营火按占地归一化）。
	var cur: float
	match axis:
		"y": cur = sz.size.y
		"x": cur = sz.size.x
		"z": cur = sz.size.z
		_: cur = maxf(sz.size.x, sz.size.z)
	if cur < 0.0001:
		cur = 1.0
	var s := target / cur
	# 包裹层：旋转与贴地在外层做，缩放在内层模型上。
	var wrapper := Node3D.new()
	wrapper.name = _node_name(rel)
	parent.add_child(wrapper)
	wrapper.position = pos
	wrapper.rotation.y = deg_to_rad(rot_y_deg)
	inst.scale = Vector3.ONE * s
	# 底部对齐：min.y 抬到 0。
	var bottom := sz.position.y * s
	inst.position = Vector3(-sz.get_center().x * s, -bottom, -sz.get_center().z * s)
	wrapper.add_child(inst)
	return wrapper

## 指定段长生成（取最大水平边），常用于墙体/围栏拼装：段长对齐目标值，底面贴地。
## 注意：不能用单轴 "x"——Kenney 墙件厚度仅 0.10m（长度在 Z），按 X 归一化会放大 30 倍。
static func spawn_wide(parent: Node3D, rel: String, target_len: float, pos := Vector3.ZERO, rot_y_deg := 0.0) -> Node3D:
	return spawn_norm(parent, rel, target_len, pos, rot_y_deg, "h")

## 水平双向拟合：X/Z 分别缩放到 tx/tz（非均匀），底面贴地。用于屋顶覆盖矩形占地。
static func spawn_fit(parent: Node3D, rel: String, tx: float, tz: float, pos := Vector3.ZERO, rot_y_deg := 0.0) -> Node3D:
	var ps := load_model(rel)
	if ps == null or parent == null:
		return null
	var inst := ps.instantiate() as Node3D
	_apply_palette(inst, rel)
	var sz := _measure_static(inst)
	var sx := tx / maxf(sz.size.x, 0.01)
	var szc := tz / maxf(sz.size.z, 0.01)
	var wrapper := Node3D.new()
	wrapper.name = _node_name(rel)
	parent.add_child(wrapper)
	wrapper.position = pos
	wrapper.rotation.y = deg_to_rad(rot_y_deg)
	inst.scale = Vector3(sx, maxf(sx, szc), szc)
	inst.position = Vector3(-sz.get_center().x * sx, -sz.position.y * maxf(sx, szc), -sz.get_center().z * szc)
	wrapper.add_child(inst)
	return wrapper

# ---------------- 动画 ----------------
## 在实例内查找 AnimationPlayer，按优先级播放第一个存在的剪辑。返回是否成功。
static func play_clip(node: Node, names: Array, loop := true, blend := 0.2) -> bool:
	if node == null:
		return false
	var ap := node.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		return false
	for n in names:
		if ap.has_animation(n):
			var anim := ap.get_animation(n)
			anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
			ap.play(n, blend)
			return true
	# 兜底：播放第一个剪辑。
	if ap.get_animation_list().size() > 0:
		var first: StringName = ap.get_animation_list()[0]
		ap.get_animation(first).loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
		ap.play(first, blend)
		return true
	return false

## KayKit 骨架动画名常量（全角色共享同一套命名）。
const ANIM_IDLE := ["Idle", "Idle_B", "Idle_C"]
const ANIM_WALK := ["Walking_A", "Walking_B"]
const ANIM_RUN := ["Running_A", "Running_B"]
const ANIM_HIT := ["Hit_A", "Hit_B"]
const ANIM_DEATH := ["Death_A", "Death_B", "Death_C"]

# 动物（Kenney Animated Animals）：无骨骼，用节点动画（腿/头是独立节点，同样有"关节活动"）。
const ANIM_A_IDLE := ["idle", "static"]
const ANIM_A_WALK := ["walk"]
const ANIM_A_RUN := ["run"]
const ANIM_A_EAT := ["eat"]
const ANIM_A_NEG := ["gesture-negative", "idle"]   # 威吓/扑咬动作
const ANIM_A_POS := ["gesture-positive", "idle"]

## NPC/同伴职业 → KayKit 冒险者模型（CC0，Character Pack: Adventurers）。
static func npc_model(rig_id: String) -> String:
	match rig_id:
		"warrior", "shield": return "characters/Knight.glb"
		"mage": return "characters/Mage.glb"
		"archer": return "characters/Rogue.glb"
		"assassin": return "characters/Rogue_Hooded.glb"
		"barbarian": return "characters/Barbarian.glb"
	return "characters/Knight.glb"

# ---------------- KayKit 角色武器变体 ----------------
## 角色模型内置的全部武器/法器变体（归一化名）。帽子/披风等身体配件不在此列。
const WEAPON_VARIANT_NODES := [
	"1hswordoffhand", "badgeshield", "rectangleshield", "roundshield", "spikeshield", "1hsword", "2hsword",
	"1haxeoffhand", "barbarianroundshield", "1haxe", "2haxe", "mug",
	"spellbook", "spellbookopen", "1hwand", "2hstaff",
	"knifeoffhand", "1hcrossbow", "2hcrossbow", "knife", "throwable",
]

## 归一化节点名：忽略大小写与 _ . - 分隔符（Godot 导入会改动分隔符）。
static func norm_name(s: String) -> String:
	return s.to_lower().replace("_", "").replace(".", "").replace("-", "")

## 模型文件的默认武器配置（归一化名列表）。
static func default_weapons_for_model(rel: String) -> Array:
	var f := rel.get_file().to_lower()
	if f.begins_with("knight"): return ["1hsword", "rectangleshield"]
	if f.begins_with("barbarian"): return ["2haxe"]
	if f.begins_with("mage"): return ["2hstaff"]
	if f.begins_with("rogue_hooded"): return ["knife", "knifeoffhand"]
	if f.begins_with("rogue"): return ["1hcrossbow"]
	return []

## 隐藏角色模型中未选中的武器变体（KayKit 把全部武器都摆在同一个手部挂点上，
## 不裁剪会出现多把武器叠在一起）。
static func prune_weapon_variants(root: Node, keep: Array) -> void:
	if root == null: return
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is VisualInstance3D:
			var key := norm_name(n.name)
			if WEAPON_VARIANT_NODES.has(key):
				(n as VisualInstance3D).visible = keep.has(key)

## 动物种类 → Kenney cube-pets 模型（CC0）。
static func animal_model(species: String) -> String:
	match species:
		"rabbit": return "pets/animal-bunny.glb"
		"deer": return "pets/animal-deer.glb"
		"wolf": return "pets/animal-dog.glb"
		"boar": return "pets/animal-hog.glb"
	return "pets/animal-pig.glb"
