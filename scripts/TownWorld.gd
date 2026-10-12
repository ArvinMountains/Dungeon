class_name TownWorld
extends Node3D
## 灰烬庇护所（真实城镇重构版）：
## - 方形城墙 + 南/北/东三座城门，十字主街 + 中央广场喷泉，街巷两侧布局功能建筑。
## - 建筑用 Kenney Fantasy Town Kit（CC0）墙件/屋顶/烟囱/招牌拼装，装饰件（喷泉、
##   风车、货摊、路灯、树、篱笆、货车）全部来自 CC0 资产库。
## - 碰撞注册制：矩形 AABB（建筑/城墙/货摊）+ 圆形（喷泉/树/路灯/塔），杜绝穿模。
## - 交互：POI 图标点击即达——附近直接弹界面，远处自动寻路、到达后自动打开。
## - NPC 交互：对话 / 送礼 / 好感度 / 招募入队（≤3 人同行）。

signal toast_requested(text: String)
signal dialog_requested(title: String, content: String, actions: Array, eyebrow: String)
signal hud_changed
signal dialog_closed
signal enter_dungeon_requested
signal enter_overworld_requested
signal enter_selection_requested

const TOWN_HALF := 47.0   # 城墙内半宽（正方形城镇）
const WALL_H := 6.2       # 城墙高（加高后更有要塞感）
const GATE_HW := 4.2      # 城门半宽（缺口 8.4m）
const MAIN_HW := 3.6      # 主街半宽
const ALLEY_HW := 2.6     # 环巷半宽
const PLAZA_R := 11.0     # 中央广场半径

# 商店价格表（金币经济：局内掉落 → 主城消费）。
const SHOP_PRICES := {"potion_hp": 25, "potion_mp": 20, "torch": 8, "net": 30}
const SELL_PRICES := {"herb": 6, "pelt": 14, "shard": 30}

var main = null
var player: Actor = null
var followers: Array = []
var npcs: Array = []               # 主城 NPC（KayKit 冒险者 GLB）

var pois: Array = []               # {id, name, symbol, type, position, approach}
var near_poi = null                # 每帧计算：玩家附近可交互的 POI
var pending_interact := ""         # 图标点击后待交互的 POI id（到达自动打开）
var path: Array = []               # 兼容旧 UI
var destination_poi = {}           # 兼容旧 UI
var move_marker: MeshInstance3D
var move_target := Vector3.ZERO
var has_move_target := false
var player_position := Vector3(0, 0, 40)  # 南门入城出生点

# 碰撞注册表：矩形（轴对齐 AABB）与圆形。
var _rects: Array = []             # {x, z, hw, hd}
var _circs: Array = []             # {x, z, r}

var _shop_wares: Array = []        # 武器商在售武器（每次交互刷新）
var _lamps: Array = []             # 夜间点亮的城市暖光源（火盆/路灯/门灯）

func _ready() -> void:
	_define_pois()
	_build_town()
	_build_player()
	_spawn_npcs()
	move_marker = GeoBuilder.ring(self, 0.28, 0.4, Color(0.9, 0.85, 0.6, 0.8), Vector3.ZERO, 24)
	move_marker.visible = false

# ---------------- POI ----------------
func _define_pois() -> void:
	# position=交互点（门前/入口），approach=寻路停靠点（必在可通行区，且与 position 距离 < 3.6m）。
	pois = [
		{"id": "smithy", "name": "武器商家", "symbol": "⚒", "type": "place",
			"position": Vector3(-7.4, 0, 12), "approach": Vector3(-5.0, 0, 12)},
		{"id": "apothecary", "name": "道具商家", "symbol": "⚗", "type": "place",
			"position": Vector3(8.0, 0, 12), "approach": Vector3(5.0, 0, 12)},
		{"id": "guild", "name": "冒险者协会", "symbol": "⚜", "type": "place",
			"position": Vector3(-10.0, 0, -8), "approach": Vector3(-7.0, 0, -8)},
		{"id": "library", "name": "图书馆", "symbol": "✦", "type": "place",
			"position": Vector3(12.8, 0, -6), "approach": Vector3(10.0, 0, -6)},
		{"id": "training", "name": "修炼场", "symbol": "⚔", "type": "place",
			"position": Vector3(-28.0, 0, 31), "approach": Vector3(-25.5, 0, 31)},
		{"id": "abyss_gate", "name": "深渊之门", "symbol": "☉", "type": "place",
			"position": Vector3(0, 0, -43), "approach": Vector3(0, 0, -40.5)},
		{"id": "east_gate", "name": "东郊哨站", "symbol": "➤", "type": "place",
			"position": Vector3(42.5, 0, 0), "approach": Vector3(40.5, 0, 0)},
		{"id": "board", "name": "告示板", "symbol": "❗", "type": "place",
			"position": Vector3(-6.5, 0, 7.0), "approach": Vector3(-4.6, 0, 6.2)},
	]

func poi_pos(id: String) -> Vector3:
	for p in pois:
		if p.id == id: return p.position
	return Vector3.ZERO

## 小地图数据：城墙/建筑（矩形）+ 圆形障碍 + 兴趣点。
func minimap_data() -> Dictionary:
	var marks: Array = []
	for p in pois:
		marks.append({"pos": p.position, "kind": "poi", "id": p.id, "short": _poi_short(p.id)})
	return {"half": TOWN_HALF, "rects": _rects, "circs": _circs, "marks": marks}

## 兴趣点在小地图上的单字标记（中文字形必然有，避免缺字）。
func _poi_short(id: String) -> String:
	match id:
		"smithy": return "锤"
		"apothecary": return "药"
		"guild": return "会"
		"library": return "书"
		"training": return "练"
		"abyss_gate": return "渊"
		"east_gate": return "门"
		"board": return "板"
	return "·"

func _poi_by_id(id: String) -> Dictionary:
	for p in pois:
		if p.id == id: return p
	return {}

# ---------------- 碰撞注册 ----------------
func add_rect_obstacle(cx: float, cz: float, hw: float, hd: float) -> void:
	_rects.append({"x": cx, "z": cz, "hw": hw, "hd": hd})

func add_circ_obstacle(x: float, z: float, r: float) -> void:
	_circs.append({"x": x, "z": z, "r": r})

func _walkable(pos: Vector3) -> bool:
	# 城内正方形边界（城墙内 1.1m 缓冲）。
	if absf(pos.x) > TOWN_HALF - 1.1 or absf(pos.z) > TOWN_HALF - 1.1: return false
	for r in _rects:
		if absf(pos.x - r.x) < r.hw and absf(pos.z - r.z) < r.hd: return false
	for c in _circs:
		if Vector2(pos.x - c.x, pos.z - c.z).length() < c.r: return false
	return true

# ---------------- 场景搭建 ----------------
func _build_town() -> void:
	var Env := Ambience
	Env.tiled_floor(self, int(TOWN_HALF * 2.4), 0.0, 233)
	_build_streets()
	_build_walls()
	_build_buildings()
	_build_plaza()
	_build_decor()
	_build_training_ground()

## 街道：十字主街 + 南/北环巷 + 中央广场石铺（叠在草地之上）。
func _build_streets() -> void:
	var street := Color(0.31, 0.30, 0.28)
	var alley := Color(0.27, 0.27, 0.25)
	# 南北主街 / 东西主街。
	_street(Vector3(0, 0, -46), Vector3(0, 0, 46), MAIN_HW * 2.0, street)
	_street(Vector3(-46, 0, 0), Vector3(46, 0, 0), MAIN_HW * 2.0, street)
	# 南北环巷（连接各街区，形成真实城镇的路网）。
	_street(Vector3(-40, 0, 23.5), Vector3(40, 0, 23.5), ALLEY_HW * 2.0, alley)
	_street(Vector3(-40, 0, -23.5), Vector3(40, 0, -23.5), ALLEY_HW * 2.0, alley)
	# 中央广场石铺 + 外圈石缘。
	GeoBuilder.cylinder(self, PLAZA_R, PLAZA_R + 0.5, 0.06, Color(0.34, 0.32, 0.29), Vector3(0, 0.04, 0), 36)
	GeoBuilder.ring(self, PLAZA_R - 0.32, PLAZA_R + 0.32, Color(0.23, 0.22, 0.20), Vector3(0, 0.078, 0), 40)
	# 主街街缘石。
	for s in [-1.0, 1.0]:
		var cx := GeoBuilder.box(self, 0.26, 0.09, TOWN_HALF * 2.0, Color(0.23, 0.22, 0.21), Vector3(s * (MAIN_HW + 0.16), 0.05, 0))
		var cz := GeoBuilder.box(self, TOWN_HALF * 2.0, 0.09, 0.26, Color(0.23, 0.22, 0.21), Vector3(0, 0.05, s * (MAIN_HW + 0.16)))
		cx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cz.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## 铺一条矩形石板街（a→b，宽 w）。
func _street(a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.01: return
	var strip := GeoBuilder.box(self, w, 0.05, length, col,
		Vector3((a.x + b.x) * 0.5, 0.035, (a.z + b.z) * 0.5))
	strip.rotation.y = atan2(d.x, d.z)
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## 城墙：分段石砌 + 墙顶走沿 + 四角塔楼 + 门楼。同步注册碰撞。
func _build_walls() -> void:
	var stone := Color(0.40, 0.39, 0.36)
	var seg_len := TOWN_HALF - GATE_HW  # 单侧门旁墙段长
	# 南/北墙（z=±47，中间留门洞）。
	for zs in [-1.0, 1.0]:
		for xs in [-1.0, 1.0]:
			var cx: float = xs * (GATE_HW + seg_len * 0.5)
			_segmented_wall(Vector3(cx, 0, zs * TOWN_HALF), Vector3(seg_len, WALL_H, 1.7), true, stone)
			add_rect_obstacle(cx, zs * TOWN_HALF, seg_len * 0.5, 1.2)
	# 东墙（x=47，中间留门洞）。
	for zs in [-1.0, 1.0]:
		var cz: float = zs * (GATE_HW + seg_len * 0.5)
		_segmented_wall(Vector3(TOWN_HALF, 0, cz), Vector3(1.7, WALL_H, seg_len), false, stone)
		add_rect_obstacle(TOWN_HALF, cz, 1.2, seg_len * 0.5)
	# 西墙整段。
	_segmented_wall(Vector3(-TOWN_HALF, 0, 0), Vector3(1.7, WALL_H, TOWN_HALF * 2.0), false, stone)
	add_rect_obstacle(-TOWN_HALF, 0, 1.2, TOWN_HALF)
	# 四角塔楼 + 门侧塔楼（石柱资产加高）。
	for c in [Vector3(-TOWN_HALF, 0, -TOWN_HALF), Vector3(TOWN_HALF, 0, -TOWN_HALF),
			Vector3(-TOWN_HALF, 0, TOWN_HALF), Vector3(TOWN_HALF, 0, TOWN_HALF)]:
		AssetLib.spawn_norm(self, "town/pillar-stone.glb", 7.6, Vector3(c.x, 0, c.z), 0, "y")
		add_circ_obstacle(c.x, c.z, 1.2)
	for g in [Vector3(-GATE_HW, 0, TOWN_HALF), Vector3(GATE_HW, 0, TOWN_HALF),
			Vector3(-GATE_HW, 0, -TOWN_HALF), Vector3(GATE_HW, 0, -TOWN_HALF),
			Vector3(TOWN_HALF, 0, -GATE_HW), Vector3(TOWN_HALF, 0, GATE_HW)]:
		AssetLib.spawn_norm(self, "town/pillar-stone.glb", 6.4, Vector3(g.x, 0, g.z), 0, "y")
		add_circ_obstacle(g.x, g.z, 1.05)
	# 南门/东门门楼木梁（装饰，无门板，可通行）。
	GeoBuilder.box(self, GATE_HW * 2.0 + 2.4, 0.55, 1.1, Color(0.30, 0.24, 0.16), Vector3(0, WALL_H - 0.7, TOWN_HALF))
	GeoBuilder.box(self, 1.1, WALL_H - 0.6, GATE_HW * 2.0 + 2.4, Color(0.30, 0.24, 0.16), Vector3(TOWN_HALF, WALL_H - 0.7, 0))
	# 门楼火盆（夜间门洞照明）。
	for p in [Vector3(-GATE_HW - 0.6, 0, TOWN_HALF - 1.4), Vector3(GATE_HW + 0.6, 0, TOWN_HALF - 1.4),
			Vector3(TOWN_HALF - 1.4, 0, -GATE_HW - 0.6), Vector3(TOWN_HALF - 1.4, 0, GATE_HW + 0.6)]:
		_build_brazier(p)

## 分段石墙：长轴切 3 段做颜色抖动，顶部压走沿，避免大平板感。
func _segmented_wall(center: Vector3, size: Vector3, along_x: bool, col: Color) -> void:
	var long_len := size.x if along_x else size.z
	var step := long_len / 3.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(center.x * 7.0 + center.z * 13.0)
	for i in range(3):
		var off := -long_len * 0.5 + step * (i + 0.5)
		var c := col * (0.9 + rng.randf() * 0.2)
		var pos := center + (Vector3(off, 0, 0) if along_x else Vector3(0, 0, off))
		var w := (step - 0.06) if along_x else size.x
		var d := size.z if along_x else (step - 0.06)
		GeoBuilder.box(self, w, size.y, d, c, pos + Vector3(0, size.y * 0.5, 0))
	# 墙顶走沿（略外扩，压出俯视轮廓）。
	GeoBuilder.box(self, size.x + 0.35, 0.5, size.z + 0.35, col.darkened(0.14), center + Vector3(0, size.y + 0.25, 0))

## 石砌火盆：铁篮 + 火焰 + 暖光（门楼/广场照明）。
func _build_brazier(pos: Vector3) -> void:
	GeoBuilder.cylinder(self, 0.34, 0.5, 0.7, Color(0.20, 0.19, 0.18), pos + Vector3(0, 0.35, 0), 8)
	GeoBuilder.cylinder(self, 0.56, 0.42, 0.22, Color(0.16, 0.15, 0.14), pos + Vector3(0, 0.76, 0), 8)
	var flame := GeoBuilder.octahedron(self, 0.34, GeoBuilder.mat(Color(1.0, 0.62, 0.22), {"emissive": Color(1.0, 0.55, 0.15), "emissive_intensity": 2.6}), pos + Vector3(0, 1.05, 0), false)
	flame.scale = Vector3(0.85, 1.5, 0.85)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.62, 0.28)
	l.light_energy = 3.4
	l.omni_range = 9.0
	l.position = pos + Vector3(0, 1.3, 0)
	add_child(l)
	_lamps.append(l)
	add_circ_obstacle(pos.x, pos.z, 0.55)

## 功能建筑 + 民居（全部注册碰撞）。门朝向街道，形成沿街立面。
func _build_buildings() -> void:
	# 铁匠铺 / 药庐：南主街两侧对望。
	_nordic_house(Vector3(-13, 0, 12), 9, 8, "E", "smithy")
	add_rect_obstacle(-13, 12, 4.2, 3.7)
	_nordic_house(Vector3(13, 0, 12), 8, 8, "W", "apothecary")
	add_rect_obstacle(13, 12, 3.7, 3.7)
	# 冒险者协会：广场西侧大长屋（面向广场）。
	_nordic_house(Vector3(-17, 0, -8), 12, 10, "E", "guild")
	add_rect_obstacle(-17, -8, 5.6, 4.6)
	# 图书馆（石塔）。
	_build_library_tower(Vector3(18, 0, -6))
	add_circ_obstacle(18, -6, 4.5)
	# 民居 ×6（无交互，纯景观，分布在各街区）。
	_nordic_house(Vector3(-24, 0, 10), 7, 7, "E", "")
	add_rect_obstacle(-24, 10, 3.2, 3.2)
	_nordic_house(Vector3(25, 0, 10), 7, 7, "W", "")
	add_rect_obstacle(25, 10, 3.2, 3.2)
	_nordic_house(Vector3(-30, 0, -8), 7, 7, "E", "")
	add_rect_obstacle(-30, -8, 3.2, 3.2)
	_nordic_house(Vector3(30, 0, -10), 7, 7, "W", "")
	add_rect_obstacle(30, -10, 3.2, 3.2)
	_nordic_house(Vector3(-34, 0, 14), 7, 7, "E", "")
	add_rect_obstacle(-34, 14, 3.2, 3.2)
	_nordic_house(Vector3(20, 0, 32), 8, 7, "N", "")
	add_rect_obstacle(20, 32, 3.7, 3.2)
	# 深渊之门（北门）与东郊哨站（东门）。
	_build_abyss_gate(poi_pos("abyss_gate") + Vector3(0, 0, -4))
	_build_east_gate(Vector3(TOWN_HALF, 0, 0))
	# 告示板（广场边）。
	_build_board(poi_pos("board"))
	add_rect_obstacle(-6.5, 7.0, 0.5, 1.4)

## 北欧长屋：石基座 + 木构墙体（门窗件）+ 高坡双坡屋顶 + 烟囱。
## center=建筑中心，w×d=占地，facing=门朝向（N/S/E/W），tag=功能标识（空=民居）。
func _nordic_house(center: Vector3, w: float, d: float, facing: String, tag: String) -> void:
	var b := Node3D.new()
	add_child(b)
	b.position = center
	match facing:
		"N": b.rotation.y = PI
		"E": b.rotation.y = PI * 0.5
		"W": b.rotation.y = -PI * 0.5
		_: b.rotation.y = 0.0
	var base_y := 0.7  # 石基座高度
	# 石基座（北欧长屋的木构多架在石基上）。
	GeoBuilder.box(b, w + 0.5, base_y, d + 0.5, Color(0.43, 0.42, 0.39), Vector3(0, base_y * 0.5, 0))
	# 墙件本地朝向：长度沿 Z、厚度沿 X（实测 AABB 0.10×1.0×1.0）。
	var wsize := AssetLib.size_of("town/wall-wood.glb")
	var cols := maxi(2, ceili(w / 3.0))
	var rows := maxi(2, ceili(d / 3.0))
	var sw := w / float(cols)
	var sd := d / float(rows)
	var s := sw / maxf(wsize.z, 0.01)
	var wall_h := wsize.y * s
	var door_idx := cols / 2
	for i in range(cols):
		var x := -w * 0.5 + sw * (i + 0.5)
		var is_door := i == door_idx
		# 南墙（本地 +Z）：门/窗。北墙（本地 -Z）：背墙。
		var front := "town/wall-wood-door.glb" if is_door else ("town/wall-wood-window-glass.glb" if i % 2 == 1 else "town/wall-wood.glb")
		AssetLib.spawn_wide(b, front, sw, Vector3(x, base_y, d * 0.5), 90.0)
		AssetLib.spawn_wide(b, "town/wall-wood-window-glass.glb" if i % 2 == 1 else "town/wall-wood.glb", sw, Vector3(x, base_y, -d * 0.5), 90.0)
	for j in range(rows):
		var z := -d * 0.5 + sd * (j + 0.5)
		AssetLib.spawn_wide(b, "town/wall-wood-window-shutters.glb", sd, Vector3(-w * 0.5, base_y, z), 0.0)
		AssetLib.spawn_wide(b, "town/wall-wood-window-glass.glb", sd, Vector3(w * 0.5, base_y, z), 0.0)
	# 高坡双坡屋顶（屋脊沿本地 X，山墙在 ±Z 端）。
	var roof_y := base_y + wall_h - 0.12
	AssetLib.spawn_fit(b, "town/roof-high-gable.glb", w + 0.9, d + 0.9, Vector3(0, roof_y, 0))
	AssetLib.spawn_fit(b, "town/roof-high-gable-end.glb", w + 0.92, d + 0.92, Vector3(0, roof_y, 0))
	# 烟囱。
	AssetLib.spawn_norm(b, "town/chimney.glb", 2.6, Vector3(w * 0.26, roof_y + wall_h * 0.35, -d * 0.16), 0, "y")
	# 门口木桶（纯装饰，无碰撞）。
	AssetLib.spawn_norm(b, "dungeon/kay/barrel_small.gltf.glb", 0.85, Vector3(-w * 0.5 + 1.1, base_y, d * 0.5 + 0.8), 0, "y")
	# 功能标识与暖光。
	match tag:
		"smithy":
			AssetLib.spawn_norm(b, "dungeon/kay/keg.gltf.glb", 1.0, Vector3(w * 0.5 - 1.0, base_y, d * 0.5 + 0.9), 0, "y")
			var forge := OmniLight3D.new()
			forge.light_color = Color(1.0, 0.45, 0.15)
			forge.light_energy = 3.0
			forge.omni_range = 6.5
			forge.position = Vector3(1.4, 1.3, d * 0.5 + 1.4)
			b.add_child(forge)
			_lamps.append(forge)
		"apothecary":
			AssetLib.spawn_norm(b, "dungeon/kay/bottle_A_green.gltf.glb", 0.55, Vector3(-1.2, base_y + 0.9, d * 0.5 + 0.7), 0, "y")
			AssetLib.spawn_norm(b, "dungeon/kay/bottle_A_brown.gltf.glb", 0.45, Vector3(-0.7, base_y + 0.9, d * 0.5 + 0.7), 0, "y")
		"guild":
			AssetLib.spawn_wide(b, "town/banner-red.glb", 1.1, Vector3(0, base_y + wall_h - 0.4, d * 0.5 + 0.28))
			var gl := OmniLight3D.new()
			gl.light_color = Color(1.0, 0.78, 0.45)
			gl.light_energy = 2.0
			gl.omni_range = 6.5
			gl.position = Vector3(0, base_y + wall_h * 0.8, d * 0.5 + 0.7)
			b.add_child(gl)
			_lamps.append(gl)

## 图书馆：石塔 + 穹顶（石砌加高 + 西向大门）。
func _build_library_tower(pos: Vector3) -> void:
	var s := Node3D.new()
	add_child(s)
	s.position = pos
	var body := GeoBuilder.cylinder(s, 3.0, 3.4, 7.2, Color(0.40, 0.39, 0.36), Vector3(0, 3.6, 0), 12)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	GeoBuilder.cylinder(s, 0.4, 3.0, 1.6, Color(0.33, 0.32, 0.30), Vector3(0, 8.0, 0), 12)
	GeoBuilder.cylinder(s, 0.05, 2.3, 2.8, Color(0.34, 0.22, 0.16), Vector3(0, 9.6, 0), 12)
	# 西向大门与石阶（面向广场）。
	GeoBuilder.box(s, 1.5, 2.7, 0.35, Color(0.16, 0.13, 0.1), Vector3(-3.3, 1.35, 0))
	GeoBuilder.box(s, 1.8, 0.25, 1.3, Color(0.44, 0.43, 0.40), Vector3(-3.9, 0.12, 0))
	AssetLib.spawn_wide(s, "town/banner-green.glb", 1.0, Vector3(-3.5, 4.8, 0), -90)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(0.72, 0.62, 0.92)
	lamp.light_energy = 3.0
	lamp.omni_range = 8.0
	lamp.position = Vector3(0, 6.4, 0)
	s.add_child(lamp)
	_lamps.append(lamp)

## 中央广场：石砌水井（偏北，让开主街交叉口）+ 四角火盆。
func _build_plaza() -> void:
	_build_well(Vector3(0, 0, -5.8))
	for a in [0.25, 0.75, 1.25, 1.75]:
		_build_brazier(Vector3(cos(a * PI) * 8.4, 0, sin(a * PI) * 8.4))

## 石砌水井：石圈井台 + 木架顶棚 + 吊桶（北欧市集的地标）。
func _build_well(pos: Vector3) -> void:
	var w := Node3D.new()
	add_child(w)
	w.position = pos
	GeoBuilder.cylinder(w, 1.5, 1.62, 0.9, Color(0.44, 0.43, 0.40), Vector3(0, 0.45, 0), 14)
	GeoBuilder.cylinder(w, 1.14, 1.14, 0.16, Color(0.09, 0.11, 0.14), Vector3(0, 0.9, 0), 14)
	for sx in [-1.25, 1.25]:
		GeoBuilder.box(w, 0.18, 2.0, 0.18, Color(0.32, 0.24, 0.15), Vector3(sx, 2.0, 0))
	GeoBuilder.box(w, 2.9, 0.2, 0.22, Color(0.34, 0.25, 0.16), Vector3(0, 3.0, 0))
	var winch := GeoBuilder.cylinder(w, 0.13, 0.13, 2.6, Color(0.30, 0.22, 0.14), Vector3(0, 2.55, 0), 8)
	winch.rotation.z = PI * 0.5
	GeoBuilder.box(w, 0.42, 0.44, 0.42, Color(0.28, 0.21, 0.13), Vector3(0, 2.0, 0))
	AssetLib.spawn_fit(w, "town/roof-gable.glb", 3.7, 2.5, Vector3(0, 3.1, 0))
	add_circ_obstacle(pos.x, pos.z, 1.7)

## 街道装饰：路灯、行道树、市集货摊、货车货箱、风车、篱笆、花丛。
func _build_decor() -> void:
	# 主街路灯（沿人行道，夜间自动点亮）。
	for pos in [Vector3(-4.7, 0, 32), Vector3(4.7, 0, 32), Vector3(-4.7, 0, 20), Vector3(4.7, 0, 20),
			Vector3(-4.7, 0, -20), Vector3(4.7, 0, -20), Vector3(-4.7, 0, -32), Vector3(4.7, 0, -32)]:
		_build_lantern(pos)
	# 广场周边市集货摊（避开主街与寻路通道）。
	AssetLib.spawn_norm(self, "town/stall-red.glb", 1.9, Vector3(-8.2, 0, 8.2), 135, "y")
	add_rect_obstacle(-8.2, 8.2, 1.2, 1.2)
	AssetLib.spawn_norm(self, "town/stall-green.glb", 1.9, Vector3(8.2, 0, -8.2), -45, "y")
	add_rect_obstacle(8.2, -8.2, 1.2, 1.2)
	AssetLib.spawn_norm(self, "town/stall.glb", 1.9, Vector3(8.6, 0, 8.6), -135, "y")
	add_rect_obstacle(8.6, 8.6, 1.2, 1.2)
	# 城门口货车与货箱。
	AssetLib.spawn_norm(self, "town/cart-high.glb", 1.8, Vector3(38, 0, -5.5), -70, "y")
	add_circ_obstacle(38, -5.5, 1.4)
	AssetLib.spawn_norm(self, "dungeon/kay/crates_stacked.gltf.glb", 1.5, Vector3(38.5, 0, 5.4), 20, "y")
	add_circ_obstacle(38.5, 5.4, 1.0)
	AssetLib.spawn_norm(self, "town/cart.glb", 1.7, Vector3(-38, 0, 5.6), 110, "y")
	add_circ_obstacle(-38, 5.6, 1.3)
	# 西北角风车（地标）。
	AssetLib.spawn_norm(self, "town/windmill.glb", 10.0, Vector3(-36, 0, -36), 30, "y")
	add_circ_obstacle(-36, -36, 2.4)
	# 行道树（避开街道与建筑）。
	var tree_rels := ["town/tree-high-round.glb", "town/tree.glb", "town/tree-crooked.glb", "nature/tree_oak.glb"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 8128
	for i in range(22):
		var x := (1.0 if i % 2 == 0 else -1.0) * (16.0 + rng.randf() * 24.0)
		var z := -38.0 + rng.randf() * 76.0
		var pos := Vector3(x, 0, z)
		if not _walkable(pos): continue
		AssetLib.spawn_norm(self, tree_rels[i % tree_rels.size()], 5.0 + rng.randf() * 2.5, pos, rng.randf() * 360.0, "y")
		add_circ_obstacle(pos.x, pos.z, 0.7)
	# 城墙根篱笆与石块。
	for i in range(8):
		var a := TAU * i / 8.0 + 0.4
		var x := cos(a) * 42.0
		var z := sin(a) * 42.0
		if absf(x) < 8.0 or absf(z) < 8.0: continue  # 让开主街
		AssetLib.spawn_norm(self, "town/hedge.glb", 1.3, Vector3(x, 0, z), randf() * 360.0, "y")
		add_circ_obstacle(x, z, 0.8)
	AssetLib.spawn_norm(self, "town/rock-large.glb", 2.6, Vector3(-30, 0, 26), 15, "h")
	add_circ_obstacle(-30, 26, 1.2)
	AssetLib.spawn_norm(self, "town/rock-wide.glb", 2.2, Vector3(31, 0, -31), 40, "h")
	add_circ_obstacle(31, -31, 1.0)
	# 草地花丛点缀（无碰撞）。
	for i in range(34):
		var a2 := rng.randf() * TAU
		var r2 := 13.0 + rng.randf() * 31.0
		var p := Vector3(cos(a2) * r2, 0, sin(a2) * r2)
		if not _walkable(p): continue
		var flower := "nature/flower_yellowA.glb" if i % 2 == 0 else "nature/flower_purpleA.glb"
		AssetLib.spawn_norm(self, flower, 0.4, p, rng.randf() * 360.0, "y")

## 路灯：灯柱 + 灯笼 + 夜间暖光。
func _build_lantern(pos: Vector3) -> void:
	AssetLib.spawn_norm(self, "town/lantern.glb", 3.2, pos, 0, "y")
	add_circ_obstacle(pos.x, pos.z, 0.35)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.80, 0.50)
	l.light_energy = 2.4
	l.omni_range = 7.0
	l.position = pos + Vector3(0, 2.8, 0)
	add_child(l)
	_lamps.append(l)

## 修炼场：木栅围栏（东侧留口）+ 木桩假人。
func _build_training_ground() -> void:
	var c := Vector3(-32, 0, 33)
	var s := Node3D.new()
	add_child(s)
	s.position = c
	GeoBuilder.cylinder(s, 6.0, 6.4, 0.06, Color(0.34, 0.32, 0.29), Vector3(0, 0.03, 0), 26)
	# 围栏（圆形布置，东侧 ±0.55rad 留口，正对城内来路）。
	var n := 20
	for i in range(n):
		var a := TAU * float(i) / float(n)
		if absf(wrapf(a, -PI, PI)) < 0.55: continue  # 东口
		var p := Vector3(cos(a) * 6.2, 0, sin(a) * 6.2)
		AssetLib.spawn_wide(s, "town/fence.glb", 2.1, p, rad_to_deg(-a))  # 长度沿本地 Z，-a 使其切向贴合圆周
		add_circ_obstacle(c.x + p.x, c.z + p.z, 0.85)
	# 木桩假人 ×3（南北排开）。
	for i in range(3):
		var dz := -2.4 + i * 2.4
		GeoBuilder.cylinder(s, 0.16, 0.2, 1.7, Color(0.36, 0.3, 0.22), Vector3(0, 0.85, dz), 8)
		GeoBuilder.cylinder(s, 0.3, 0.3, 0.4, Color(0.3, 0.24, 0.18), Vector3(0, 1.9, dz), 8)
		GeoBuilder.box(s, 1.6, 0.13, 0.13, Color(0.3, 0.24, 0.16), Vector3(0, 1.45, dz))
		add_circ_obstacle(c.x, c.z + dz, 0.45)
	# 武器架。
	GeoBuilder.box(s, 0.1, 1.6, 0.1, Color(0.26, 0.2, 0.14), Vector3(-3.6, 0.8, 0))
	GeoBuilder.box(s, 0.1, 1.6, 0.1, Color(0.26, 0.2, 0.14), Vector3(-3.6, 0.8, 1.4))
	GeoBuilder.box(s, 0.14, 0.14, 1.5, Color(0.3, 0.24, 0.16), Vector3(-3.6, 1.5, 0.7))
	add_circ_obstacle(c.x - 3.6, c.z + 0.7, 0.9)

func _build_abyss_gate(pos: Vector3) -> void:
	var arch := Ambience.gothic_arch(self, 5.2, 6.4, 0.9, Color(0.14, 0.13, 0.17))
	arch.position = pos
	var veil := GeoBuilder.mesh_instance(self, GeoBuilder.box_geometry(3.0, 5.0, 0.08),
		GeoBuilder.mat(Color(0.45, 0.3, 0.8, 0.35), {"transparent": true, "unshaded": true, "depth_write": false}),
		pos + Vector3(0, 2.5, 0), false)
	veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.6, 0.4, 0.95)
	glow.light_energy = 5.0
	glow.omni_range = 9.0
	glow.position = pos + Vector3(0, 2.6, 0)
	add_child(glow)
	add_circ_obstacle(pos.x - 2.6, pos.z, 1.0)
	add_circ_obstacle(pos.x + 2.6, pos.z, 1.0)

func _build_east_gate(center: Vector3) -> void:
	var s := Node3D.new()
	add_child(s)
	s.position = center
	# 木制哨站门（门洞在墙上，两侧柱已在 _build_walls 注册）。
	GeoBuilder.box(s, 0.5, 4.6, 0.5, Color(0.32, 0.26, 0.18), Vector3(0, 2.3, -3.4))
	GeoBuilder.box(s, 0.5, 4.6, 0.5, Color(0.32, 0.26, 0.18), Vector3(0, 2.3, 3.4))
	GeoBuilder.box(s, 0.6, 0.35, 7.6, Color(0.28, 0.22, 0.16), Vector3(0, 4.7, 0))
	# 火盆。
	AssetLib.spawn_norm(s, "dungeon/graveyard/fire-basket.glb", 1.2, Vector3(-1.6, 0, -2.2), 0, "y")

func _build_board(pos: Vector3) -> void:
	var s := Node3D.new()
	add_child(s)
	s.position = pos
	s.rotation.y = PI / 2  # 面朝主街（东侧）
	GeoBuilder.box(s, 0.16, 2.2, 0.16, Color(0.3, 0.24, 0.16), Vector3(-1.0, 1.1, 0))
	GeoBuilder.box(s, 0.16, 2.2, 0.16, Color(0.3, 0.24, 0.16), Vector3(1.0, 1.1, 0))
	GeoBuilder.box(s, 2.4, 1.5, 0.1, Color(0.4, 0.33, 0.22), Vector3(0, 1.6, 0))
	for i in range(3):
		GeoBuilder.box(s, 0.4, 0.55, 0.02, Color(0.75, 0.7, 0.58), Vector3(-0.7 + i * 0.7, 1.6 + (0.1 if i == 1 else 0.0), 0.07))

# ---------------- 玩家 / NPC / 随行 ----------------
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
	player.global_position = player_position

func _spawn_npcs() -> void:
	# NpcBook：rowan 协会 / mira 药摊 / kane 东门 / sylphie 图书馆 / borin 修炼场。
	# NPC 用 KayKit 冒险者 GLB（CC0），站位跟随新建筑门口。
	var spots := {
		"rowan": Vector3(-10.6, 0, -8.6),
		"mira": Vector3(7.6, 0, 12.6),
		"kane": Vector3(40.5, 0, 2.6),
		"sylphie": Vector3(13.2, 0, -3.0),
		"borin": Vector3(-25.0, 0, 32.0),
	}
	for npc_id in spots:
		var def: Dictionary = NpcBook.NPCS[npc_id]
		var a := Actor.new()
		a.faction = "ally"
		a.display_name = def.name
		a.show_bar = false
		add_child(a)
		a.global_position = spots[npc_id]
		a.rotation.y = randf() * TAU
		var vis := Node3D.new()
		a.add_child(vis)
		# NPC 身高归一化（KayKit 原始模型 2.2~3.0m，压到 1.8m 与玩家比例协调）。
		var model_rel := AssetLib.npc_model(def.get("rig", "warrior"))
		AssetLib.spawn_norm(vis, model_rel, 1.8, Vector3.ZERO, 0.0, "y")
		AssetLib.prune_weapon_variants(vis, AssetLib.default_weapons_for_model(model_rel))
		AssetLib.play_clip(vis, AssetLib.ANIM_IDLE, true)
		a.set_meta("npc_id", npc_id)
		a.set_meta("home", spots[npc_id])
		npcs.append(a)

## 同步随行者（出战宠物 + 已招募同伴）。
func _sync_followers() -> void:
	for f in followers: f.dispose()
	followers.clear()
	if GameState.active_pet_valid():
		var pet := Follower.new()
		pet.world = self
		add_child(pet)
		pet.setup_pet()
		pet.follow_slot = followers.size()
		pet.global_position = player.global_position + Vector3(1.5, 0, 1.5)
		pet.blocked_check = _walkable
		followers.append(pet)
	for npc_id in GameState.save.party:
		var comp := Follower.new()
		comp.world = self
		comp.setup_companion(npc_id)  # 必须先定型再入树：_ready→_build_visual 依赖 kind/npc_id
		add_child(comp)
		comp.follow_slot = followers.size()
		comp.global_position = player.global_position + Vector3(-1.5, 0, 1.5)
		comp.blocked_check = _walkable
		followers.append(comp)

func on_enter() -> void:
	if player == null: return
	player.global_position = player_position
	_sync_followers()
	hud_changed.emit()

# ---------------- 寻路 / 移动 ----------------
func handle_click(cam: Camera3D, mouse: Vector2) -> void:
	var plane := Plane(Vector3.UP, 0.0)
	var hit = plane.intersects_ray(cam.project_ray_origin(mouse), cam.project_ray_normal(mouse))
	if hit and absf(hit.x) < TOWN_HALF - 1.0 and absf(hit.z) < TOWN_HALF - 1.0:
		move_target = hit
		has_move_target = true
		pending_interact = ""
		move_marker.global_position = hit
		move_marker.visible = true

## UI 寻路：走向目标 POI（approach 停靠点）。
func travel_to_poi(poi) -> void:
	if poi == null or not poi is Dictionary: return
	destination_poi = poi
	move_target = poi.get("approach", poi.position + Vector3(0, 0, 3.0))
	has_move_target = true
	move_marker.global_position = move_target
	move_marker.visible = true
	path = [move_target]
	toast_requested.emit("启程前往 %s" % poi.get("name", "?"))

## 任务指引：走向告示板。
func track_quest() -> void:
	travel_to_poi(_poi_by_id("board"))

## POI 图标点击：附近直接交互，远处寻路 + 到达自动打开。
func poi_icon_clicked(pid: String) -> void:
	var p := _poi_by_id(pid)
	if p.is_empty(): return
	var d := Vector2(player.global_position.x - p.position.x, player.global_position.z - p.position.z).length()
	if d < 5.0:
		_interact_poi(p)
		return
	pending_interact = pid
	travel_to_poi(p)
	toast_requested.emit("前往 %s（到达后自动打开）" % p.get("name", "?"))

func _walkable_public(pos: Vector3) -> bool:
	return _walkable(pos)

# ---------------- 交互 ----------------
## 每帧：计算附近 POI / NPC。
func _update_near() -> void:
	near_poi = null
	var best_d := 3.6
	for p in pois:
		var d: float = Vector2(player.global_position.x - p.position.x, player.global_position.z - p.position.z).length()
		if d < best_d:
			best_d = d
			near_poi = p

func poi_available(poi) -> bool:
	if poi == null: return false
	return true  # 所有 POI 均可交互

## E 键：优先 POI，其次 NPC。
func interact_near() -> void:
	if near_poi:
		_interact_poi(near_poi)
		return
	# 找最近 NPC。
	var best = null
	var best_d := 3.0
	for n in npcs:
		var d: float = n.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = n
	if best:
		_talk_npc(best)

func _interact_poi(poi: Dictionary) -> void:
	match poi.id:
		"smithy": _dialog_smithy()
		"apothecary": _dialog_apothecary()
		"guild": _dialog_guild()
		"library": _dialog_library()
		"training": _dialog_training()
		"abyss_gate": _confirm_abyss()
		"east_gate": enter_overworld_requested.emit()
		"board": _dialog_board()

func _confirm_abyss() -> void:
	dialog_requested.emit("深渊之门", "门后的黑暗在呼吸。第一层 · 废弃圣堂。\n深渊里失去的血量与金币不可全数带回。", [
		{"label": "推门而入", "run": func(): enter_dungeon_requested.emit()},
		{"label": "再等等", "run": func(): dialog_closed.emit(), "secondary": true},
	], "THE ABYSS WAITS")

# ---- 武器商家 ----
func _dialog_smithy() -> void:
	if _shop_wares.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for i in range(3):
			_shop_wares.append(Items.roll_weapon(rng, GameState.save.selected, 0, 0.2))
	var content := "炉火映着半张脸。「看看货，或者强化你手上的家伙。」\n"
	var actions := []
	for i in range(_shop_wares.size()):
		var w: Dictionary = _shop_wares[i]
		var price: int = 45 + int(w.rarity) * 50 + Items.weapon_atk(w)
		content += "\n%d. [color=#%s]%s[/color] —— %d 金币" % [i + 1,
			Color(0.9, 0.7, 0.3).to_html(false) if int(w.rarity) >= 3 else Color(0.8, 0.8, 0.8).to_html(false),
			Items.item_desc(w).split("\n")[0], price]
		var wi := w
		actions.append({"label": "买 %d（%d金）" % [i + 1, price], "run": func():
			if GameState.spend_gold(price):
				if GameState.pickup_item(wi.duplicate()):
					_shop_wares.erase(wi)
					toast_requested.emit("铁匠用布擦了擦刃口递给你。")
				else:
					GameState.add_gold(price)
					toast_requested.emit("背包满了。")
			else:
				toast_requested.emit("金币不足。")})
	if GameState.save.weapon != null:
		actions.append({"label": "强化武器", "run": func():
			if GameState.upgrade_weapon():
				toast_requested.emit("锤声笃笃——武器强化成功！")
				hud_changed.emit()
			dialog_closed.emit()})
	actions.append({"label": "离开", "run": func(): dialog_closed.emit(), "secondary": true})
	dialog_requested.emit("武器商家 · 铁炉堡", content, actions, "THE SMITHY")

# ---- 道具商家 ----
func _dialog_apothecary() -> void:
	var content := "药草味扑面而来。「要补给，还是有东西要出手？」\n"
	var actions := []
	for id in ["potion_hp", "potion_mp", "torch", "net"]:
		var price: int = SHOP_PRICES[id]
		var inst: Dictionary = Items.stack_item(id)
		content += "\n· [color=#cfcabb]%s[/color] —— %d 金币" % [inst.name, price]
		var iid: String = id
		actions.append({"label": "买 %s" % inst.name, "run": func():
			if GameState.spend_gold(price):
				if not GameState.pickup_item(Items.stack_item(iid)):
					GameState.add_gold(price)
					toast_requested.emit("背包满了。")
				else:
					toast_requested.emit("买下了 %s。" % Items.stack_item(iid).name)
			else:
				toast_requested.emit("金币不足。")})
	for id2 in ["herb", "pelt", "shard"]:
		var iid2: String = id2
		actions.append({"label": "卖 %s（+%d金）" % [Items.stack_item(id2).name, SELL_PRICES[id2]], "run": func():
			if GameState.inventory.count_of(iid2) > 0:
				GameState.inventory.remove(iid2, 1)
				GameState.add_gold(SELL_PRICES[iid2])
				toast_requested.emit("成交。")
			else:
				toast_requested.emit("你没有这个。")})
	actions.append({"label": "离开", "run": func(): dialog_closed.emit(), "secondary": true})
	dialog_requested.emit("道具商家 · 雾角药庐", content, actions, "THE APOTHECARY")

# ---- 冒险者协会 ----
func _dialog_guild() -> void:
	var content := "「冒险者，名单上有你的名字。」\n"
	var actions := []
	for q in QuestBook.SIDE_QUESTS:
		var st = GameState.save.quests.side.get(q.id)
		if st == null:
			actions.append({"label": "接取：" + q.name, "run": func():
				GameState.accept_side_quest(q.id)
				toast_requested.emit("接取支线：%s" % q.name)
				hud_changed.emit()
				dialog_closed.emit()})
		elif bool(st.done) and not bool(st.claimed):
			var rw: Dictionary = q.reward
			var rw_text := ""
			if rw.has("gold"): rw_text += "%d金币 " % int(rw.gold)
			if rw.has("xp"): rw_text += "%d经验 " % int(rw.xp)
			if rw.has("diamonds"): rw_text += "%d钻石" % int(rw.diamonds)
			actions.append({"label": "领取：" + q.name, "run": func():
				if GameState.claim_quest("side", q.id):
					toast_requested.emit("奖励到手：%s" % rw_text)
				hud_changed.emit()
				dialog_closed.emit()})
	var actions2 := actions
	if actions2.is_empty():
		content += "\n（暂无可接取的支线——完成的任务记得来领赏。）"
	actions2.append({"label": "离开", "run": func(): dialog_closed.emit(), "secondary": true})
	dialog_requested.emit("冒险者协会", content, actions2, "ADVENTURERS GUILD")

# ---- 图书馆 ----
func _dialog_library() -> void:
	var quiz: Dictionary = QuestBook.QUIZ_BANK[randi() % QuestBook.QUIZ_BANK.size()]
	var actions := []
	actions.append({"label": "研读典籍（30金 → 20经验）", "run": func():
		if GameState.spend_gold(30):
			GameState.add_xp(20)
			toast_requested.emit("旧书页的沙沙声里，时间过得飞快。")
		else:
			toast_requested.emit("金币不足。")
		hud_changed.emit()})
	for i in range(quiz.a.size()):
		var idx := i
		actions.append({"label": "问答：" + quiz.a[i], "run": func():
			if idx == quiz.correct:
				toast_requested.emit("答对了！" + quiz.hint + " 奖励 25 金币。")
				GameState.add_gold(25)
			else:
				toast_requested.emit("学者摇头：「下次再想想。」")
			dialog_closed.emit()})
	actions.append({"label": "离开", "run": func(): dialog_closed.emit(), "secondary": true})
	dialog_requested.emit("图书馆 · 星檐塔", "「知识是深渊里唯一的灯。」\n（答案自取——选一条作答）", actions, "THE LIBRARY")

# ---- 修炼场 ----
func _dialog_training() -> void:
	dialog_requested.emit("修炼场 · 断剑围栏", "木桩上的刀痕比树纹还密。\n「来两招？闭着眼打也行，肌肉会记住的。」", [
		{"label": "特训一次（+10 经验）", "run": func():
			GameState.add_xp(10)
			GameState.bump_quest("skill", "", 1)
			GameState.save.training_hits = int(GameState.save.training_hits) + 1
			toast_requested.emit("挥汗如雨——力量在悄悄生长。")
			hud_changed.emit()
			dialog_closed.emit()},
		{"label": "重置加点（花费金币）", "run": func():
			if GameState.respec():
				toast_requested.emit("推倒重来，属性点已返还。")
				hud_changed.emit()
			dialog_closed.emit()},
		{"label": "离开", "run": func(): dialog_closed.emit(), "secondary": true},
	], "TRAINING YARD")

# ---- 告示板 ----
func _dialog_board() -> void:
	var q: Dictionary = GameState.save.quests
	var content := "几张羊皮纸被风掀起边角。\n\n[color=#c9b98a]支线（%d）[/color]" % q.side.size()
	for qid in q.side:
		var def: Dictionary = GameState._side_def(qid)
		var st: Dictionary = q.side[qid]
		content += "\n· %s %d/%d%s" % [def.get("name", qid), int(st.progress), int(def.get("objective", {}).get("count", 0)), "（已完成）" if bool(st.done) else ""]
	content += "\n\n[color=#c9b98a]今日日常（%d/3）[/color]" % q.daily.size()
	for d in q.daily:
		var def2: Dictionary = GameState._daily_def(d.id)
		content += "\n· %s %d/%d%s" % [def2.get("name", d.id), int(d.progress), int(def2.get("objective", {}).get("count", 0)), "（已完成）" if bool(d.done) else ""]
	# 可领取的奖励直接在这里领（不用再去协会/J 面板）。
	var actions := []
	for qid in q.side:
		var st: Dictionary = q.side[qid]
		if bool(st.done) and not bool(st.claimed):
			var def: Dictionary = GameState._side_def(qid)
			actions.append({"label": "领取支线：" + def.get("name", qid), "run": func():
				if GameState.claim_quest("side", qid):
					toast_requested.emit("奖励到手。")
				hud_changed.emit()
				dialog_closed.emit()})
	for d in q.daily:
		if bool(d.done) and not bool(d.claimed):
			var def2: Dictionary = GameState._daily_def(d.id)
			actions.append({"label": "领取日常：" + def2.get("name", d.id), "run": func():
				if GameState.claim_quest("daily", d.id):
					toast_requested.emit("奖励到手。")
				hud_changed.emit()
				dialog_closed.emit()})
	if actions.is_empty():
		actions.append({"label": "知道了", "run": func(): dialog_closed.emit(), "secondary": true})
	else:
		actions.append({"label": "关闭", "run": func(): dialog_closed.emit(), "secondary": true})
	dialog_requested.emit("告示板", content, actions, "QUEST BOARD")

# ---- NPC 对话 / 好感 / 招募 ----
func _talk_npc(n: Actor) -> void:
	var npc_id: String = n.get_meta("npc_id")
	var def: Dictionary = NpcBook.NPCS[npc_id]
	var aff := GameState.affinity_of(npc_id)
	var dialog: Array = def.get("dialogs", [])
	var line := "……"
	if dialog.size() > 0:
		line = str(dialog[randi() % dialog.size()])
	var actions := []
	actions.append({"label": "闲聊（好感 +1）", "run": func():
		GameState.add_affinity(npc_id, NpcBook.TALK_AFFINITY)
		toast_requested.emit("%s 好感 %d" % [def.name, GameState.affinity_of(npc_id)])
		dialog_closed.emit()})
	# 送礼：优先送偏好的东西。
	var fav: String = def.get("gift", "")
	if fav != "":
		actions.append({"label": "送 %s（好感 +%d）" % [Items.stack_item(fav).name, NpcBook.GIFT_FAV_AFFINITY], "run": func():
			if GameState.inventory.count_of(fav) > 0:
				GameState.inventory.remove(fav, 1)
				GameState.add_affinity(npc_id, NpcBook.GIFT_FAV_AFFINITY)
				toast_requested.emit("%s 眼睛亮了。好感 %d" % [def.name, GameState.affinity_of(npc_id)])
			else:
				GameState.add_affinity(npc_id, NpcBook.GIFT_AFFINITY)
				toast_requested.emit("没带 %s，随便聊了几句。好感 %d" % [Items.stack_item(fav).name, GameState.affinity_of(npc_id)])
			dialog_closed.emit()})
	if not GameState.save.party.has(npc_id):
		if aff >= 60:
			actions.append({"label": "招募入队", "run": func():
				if GameState.recruit(npc_id):
					toast_requested.emit("%s 加入了队伍！" % def.name)
					_sync_followers()
				dialog_closed.emit()})
		else:
			actions.append({"label": "招募入队（好感 %d/60）" % aff, "run": func():
				toast_requested.emit("%s 摆摆手：「多聊聊，多帮帮忙，自然会熟络。」" % def.name)
				dialog_closed.emit()})
	else:
		actions.append({"label": "请离队伍", "run": func():
			GameState.dismiss(npc_id)
			_sync_followers()
			toast_requested.emit("%s 暂时留在了主城。" % def.name)
			dialog_closed.emit()})
	actions.append({"label": "离开", "run": func(): dialog_closed.emit(), "secondary": true})
	dialog_requested.emit("%s（好感 %d）" % [def.name, aff], "「%s」" % line, actions, def.get("role", "NPC").to_upper())

# ---------------- 主循环 ----------------
func update_town(delta: float, rig: CameraRig) -> void:
	var time := Time.get_ticks_msec() / 1000.0
	# 夜间点亮城市暖光源（火盆/路灯/门灯），白天压暗——避免白天一堆"幽灵灯"。
	var lamp_mul := 0.30 + GameState.night_factor() * 0.95
	for l in _lamps:
		if not is_instance_valid(l): continue
		if not l.has_meta("be"): l.set_meta("be", l.light_energy)
		l.light_energy = float(l.get_meta("be")) * lamp_mul
	# 自由移动（WASD）。
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
		pending_interact = ""
		move_marker.visible = false
		player.move_step(delta, dir, Input.is_action_pressed("run"))
	elif has_move_target:
		var to_t := move_target - player.global_position
		to_t.y = 0
		if to_t.length() < 0.35:
			has_move_target = false
			move_marker.visible = false
			# 图标点击寻路：到达后自动交互。
			if pending_interact != "":
				var pi := _poi_by_id(pending_interact)
				pending_interact = ""
				if not pi.is_empty():
					var d: float = Vector2(player.global_position.x - pi.position.x, player.global_position.z - pi.position.z).length()
					if d < 5.0: _interact_poi(pi)
		else:
			player.move_step(delta, to_t.normalized())
	else:
		player.stop_moving()
	player.animate_tick(delta, time)
	# NPC 待机闲逛（在家附近小幅徘徊）。
	for n in npcs:
		n.animate_tick(delta, time)
		if randf() < delta * 0.3:
			var home: Vector3 = n.get_meta("home")
			var wander := home + Vector3(randf() * 3.0 - 1.5, 0, randf() * 3.0 - 1.5)
			if _walkable(wander):
				n.face_towards(wander, delta)
	# 随行者。
	for f in followers:
		f.ai_tick(delta, time, player)
	# 近处 POI。
	_update_near()
	# 同步玩家位置快照（供 UI/测试读取）。
	player_position = player.global_position
