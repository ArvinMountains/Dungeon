class_name Bestiary
extends RefCounted
## 图鉴：敌人（三种 AI 行为模式）/ 野生动物 / Boss / 精英词缀 / 掉落表。
## AI 模式: charger(突进猎手：追击→蓄力→扑击) / kiter(游猎射手：保持距离放风筝) / summoner(腐唤术士：远程召唤)

const AI_MODES := ["charger", "kiter", "summoner"]

const ENEMIES := {
	"whisper": {"name": "兜帽低语者", "ai": "charger", "hp": 34, "atk": 7, "speed": 2.2, "range": 1.9, "gold": [4, 9],
		"tint": Color(0.17, 0.13, 0.19), "desc": "深渊边缘最常见的东西，像被抽空了的人。"},
	"stalker": {"name": "游猎暗影", "ai": "kiter", "hp": 26, "atk": 8, "speed": 2.6, "range": 8.0, "gold": [5, 11],
		"tint": Color(0.12, 0.17, 0.15), "desc": "在你拉弓之前，它已经退进了黑暗。"},
	"cultist": {"name": "腐唤术士", "ai": "summoner", "hp": 30, "atk": 6, "speed": 1.8, "range": 9.0, "gold": [8, 14],
		"tint": Color(0.22, 0.15, 0.24), "desc": "它低声呼唤的名字，你不敢听完。"},
	"minion": {"name": "腐化眷属", "ai": "charger", "hp": 12, "atk": 4, "speed": 3.0, "range": 1.6, "gold": [1, 3],
		"tint": Color(0.15, 0.18, 0.13), "desc": "由咒语拼凑出来的粗糙造物。"},
}

## 精英词缀（前缀 + 强化规则）。
const ELITES := {
	"swift": {"name": "迅捷", "speed_mul": 1.5, "hp_mul": 1.0, "atk_mul": 1.0},
	"tough": {"name": "坚韧", "speed_mul": 0.9, "hp_mul": 2.2, "atk_mul": 1.0},
	"vampiric": {"name": "汲血", "speed_mul": 1.0, "hp_mul": 1.5, "atk_mul": 1.2, "leech": 0.2},
}

## 野生动物：mode 决定遭遇行为（flee 受惊逃跑 / hostile 可被激怒）。
const ANIMALS := {
	"rabbit": {"name": "灰穴兔", "mode": "flee", "hp": 8, "speed": 3.4, "net_chance": 0.85, "pet_dmg": 3, "pet_hp": 20, "tint": Color(0.72, 0.68, 0.60)},
	"deer": {"name": "雾角鹿", "mode": "flee", "hp": 18, "speed": 3.8, "net_chance": 0.6, "pet_dmg": 6, "pet_hp": 40, "tint": Color(0.62, 0.52, 0.40)},
	"wolf": {"name": "灰狼", "mode": "hostile", "hp": 26, "speed": 3.2, "net_chance": 0.35, "pet_dmg": 9, "pet_hp": 55, "tint": Color(0.45, 0.45, 0.44)},
	"boar": {"name": "岩背野猪", "mode": "hostile", "hp": 40, "speed": 2.4, "net_chance": 0.3, "pet_dmg": 12, "pet_hp": 80, "tint": Color(0.38, 0.32, 0.26)},
}

## 第一层 Boss：深渊守望者。
const BOSS := {"id": "abyss_warden", "name": "深渊守望者", "hp": 320, "atk": 14, "speed": 2.0, "range": 3.0, "gold": [90, 140],
	"tint": Color(0.13, 0.10, 0.22), "desc": "第一层的看门人。它守着的不是门，是门后的事。"}

# ---------------- 敌人小队：列阵 + 组合拳 ----------------
## 阵型（参考 Dragon Age: Origins 的敌方阵型与 Bannerlord 的编队推进）。
## 站位是「相对玩家」的极坐标：角度 0° = 小队所在的一侧（也就是玩家背后），半径越大越靠后。
const SQUAD_FORMATIONS := {
	"line": {"name": "横列阵", "desc": "近战一字排开压上，远程居后点射"},
	"wedge": {"name": "楔形阵", "desc": "近战成箭镞突入，远程两翼展开"},
	"pincer": {"name": "钳形阵", "desc": "左右两翼张开，掐死侧向退路"},
	"ring": {"name": "环形阵", "desc": "全员收口围住，没有死角"},
}
const SQUAD_FORMATION_ORDER := ["line", "wedge", "pincer", "ring"]

## 组合拳（小队协同技）。telegraph = 前摇秒数（留给玩家读招与格挡的窗口），
## hold = 阵型保持时长，cool = 下次组合拳的冷却基准。
const SQUAD_COMBOS := {
	"volley": {"name": "齐射", "telegraph": 0.9, "hold": 1.0, "cool": 8.5,
		"warn": "射手同时在张弓——齐射将落！"},
	"charge": {"name": "合击冲锋", "telegraph": 0.75, "hold": 1.6, "cool": 9.5,
		"warn": "近战同时压上——合击冲锋！"},
	"flank": {"name": "散开合围", "telegraph": 0.7, "hold": 3.0, "cool": 13.0,
		"warn": "小队散开绕行——小心背后！"},
	"swarm": {"name": "召唤突袭", "telegraph": 1.1, "hold": 2.5, "cool": 16.0,
		"warn": "术士开始吟唱——眷属将至！"},
}

## AI 模式 → 阵位角色：近战前排 / 远程后排 / 术士后阵。
static func squad_role(ai_mode: String) -> String:
	match ai_mode:
		"kiter": return "back"
		"summoner": return "rear"
	return "front"

## 角色 → [角度中心(度), 角度跨度(度), 半径(米)]。跨度 360 表示绕玩家一圈。
static func squad_sector(formation: String, role: String) -> Array:
	match formation:
		"pincer":
			match role:
				"front": return [78.0, 66.0, 2.5]
				"back": return [96.0, 58.0, 5.7]
				_: return [0.0, 0.0, 8.4]
		"ring":
			return [0.0, 360.0, 2.4 if role == "front" else (3.9 if role == "back" else 5.8)]
		"wedge":
			match role:
				"front": return [0.0, 24.0, 1.8]
				"back": return [0.0, 104.0, 5.5]
				_: return [0.0, 0.0, 8.6]
		_:
			match role:
				"front": return [0.0, 62.0, 2.0]
				"back": return [0.0, 92.0, 5.9]
				_: return [0.0, 0.0, 8.6]

## 阵位局部坐标（x = 横向右移，z = 沿「玩家 → 小队」方向的纵深）。
## idx/of：同角色组内的序号与总数；环形阵改传全队序号与全队人数（由世界决定）。
static func squad_slot(formation: String, role: String, idx: int, of: int) -> Vector3:
	var sec: Array = squad_sector(formation, role)
	var center := deg_to_rad(float(sec[0]))
	var span := deg_to_rad(float(sec[1]))
	var r := float(sec[2])
	var t := 0.0 if of <= 1 else (float(idx) / float(of - 1) - 0.5)
	var a := center + t * span
	return Vector3(sin(a) * r, 0, cos(a) * r)

## 依兵种构成选基础阵型（有术士 → 楔形护住后阵；远程多 → 横列对射）。
static func squad_formation(roles: Dictionary) -> String:
	if int(roles.get("rear", 0)) > 0 and int(roles.get("front", 0)) >= 1: return "wedge"
	if int(roles.get("back", 0)) >= 2: return "line"
	if int(roles.get("front", 0)) + int(roles.get("back", 0)) < 2: return SQUAD_FORMATION_ORDER[0]
	return "wedge"

## 依构成挑一记打得出来的组合拳（返回 "" 表示这一队暂时无招）。
static func pick_combo(rng: RandomNumberGenerator, roles: Dictionary) -> String:
	var pool: Array = []
	if int(roles.get("back", 0)) >= 2: pool.append("volley")
	if int(roles.get("front", 0)) >= 2: pool.append("charge")
	if int(roles.get("rear", 0)) >= 1: pool.append("swarm")
	if int(roles.get("front", 0)) + int(roles.get("back", 0)) >= 3: pool.append("flank")
	if pool.is_empty(): return ""
	return pool[rng.randi() % pool.size()]

## 房间生成权重（随深度加深偏向战斗）。
static func room_roll(rng: RandomNumberGenerator, depth: int) -> String:
	var r := rng.randf()
	if depth == 0: return "combat" if r < 0.7 else "event"
	if depth == 1: return "combat" if r < 0.55 else ("event" if r < 0.8 else "treasure")
	return "combat" if r < 0.5 else ("event" if r < 0.75 else "treasure")

## 敌人生成表：depth 决定构成与数量。返回 [{id, elite}...]
static func spawn_table(rng: RandomNumberGenerator, depth: int, room_kind: String) -> Array:
	var out := []
	var n := 2 + depth + (rng.randi() % 2)
	if room_kind == "treasure": n = mini(n, 2)
	var pool := ["whisper", "stalker"]
	if depth >= 1: pool.append("cultist")
	for i in range(n):
		var e := {"id": pool[rng.randi() % pool.size()], "elite": ""}
		if depth >= 1 and rng.randf() < 0.12 + depth * 0.06:
			var keys := ELITES.keys()
			e.elite = keys[rng.randi() % keys.size()]
		out.append(e)
	return out

## 掉落表：返回 {gold, items[...] }
static func loot(rng: RandomNumberGenerator, def: Dictionary, elite: String, luck: float, class_id: String) -> Dictionary:
	var gold_lo: int = def.gold[0]
	var gold_hi: int = def.gold[1]
	var gold := rng.randi_range(gold_lo, gold_hi)
	if elite != "": gold = int(gold * 2.5)
	gold = int(gold * (1.0 + luck))
	var items := []
	if elite != "" or rng.randf() < 0.10 + luck * 0.5:
		if rng.randf() < 0.55:
			items.append(Items.roll_weapon(rng, class_id, 0, luck + (0.5 if elite != "" else 0.0)))
		else:
			items.append(Items.roll_gear(rng, luck + (0.5 if elite != "" else 0.0)))
	if rng.randf() < 0.18: items.append(Items.stack_item("potion_hp"))
	if rng.randf() < 0.12: items.append(Items.stack_item("potion_mp"))
	if rng.randf() < 0.10: items.append(Items.stack_item("shard"))
	if rng.randf() < 0.14: items.append(Items.stack_item("herb"))
	if rng.randf() < 0.08: items.append(Items.stack_item("torch"))
	if rng.randf() < 0.06: items.append(Items.stack_item("pelt"))
	return {"gold": gold, "items": items}

## 野外刷怪：地形决定动物组合。
static func animal_table(rng: RandomNumberGenerator, biome: String) -> Array:
	var pool := ["rabbit", "deer"] if biome == "forest" else ["rabbit", "wolf"]
	if biome == "forest" and rng.randf() < 0.25: pool.append("boar")
	if biome == "mountain" and rng.randf() < 0.3: pool.append("wolf")
	var n := 3 + (rng.randi() % 3)
	var out := []
	for i in range(n):
		out.append(pool[rng.randi() % pool.size()])
	return out
