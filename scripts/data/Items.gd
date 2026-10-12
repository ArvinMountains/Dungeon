class_name Items
extends RefCounted
## 物品数据库与生成器：武器/装备/消耗品/材料。
## 稀有度: 0普通 1精良 2稀有 3史诗 4传说。武器实例 = 基础类型 + 等级养成 + 词缀特效。

const RARITY_NAMES := ["普通", "精良", "稀有", "史诗", "传说"]
const RARITY_COLORS := [
	Color(0.82, 0.82, 0.82), Color(0.45, 0.80, 0.45), Color(0.42, 0.62, 0.95),
	Color(0.68, 0.45, 0.90), Color(0.95, 0.78, 0.30),
]
const RARITY_MULT := [1.0, 1.18, 1.42, 1.75, 2.2]
const RARITY_WEIGHT := [52, 26, 14, 6, 2]  # 掉落权重
const RARITY_AFFIX_COUNT := [0, 0, 1, 1, 2]  # 词缀数量

## 词缀表：与技能联动（命中触发）。atk 为百分比攻击加成。
const AFFIXES := {
	"fire": {"name": "烈焰", "desc": "技能命中点燃：3 秒内灼烧 6+等级x2", "atk": 0.04},
	"frost": {"name": "寒霜", "desc": "技能命中减速 35%，持续 1.5 秒", "atk": 0.03},
	"leech": {"name": "汲血", "desc": "大招命中吸血 12% 伤害", "atk": 0.05},
	"chain": {"name": "连锁", "desc": "技能命中 20% 概率电弧弹射 2 目标", "atk": 0.04},
	"greed": {"name": "贪婪", "desc": "金币掉落 +15%", "atk": 0.0},
	"swift": {"name": "迅捷", "desc": "技能冷却 -8%", "atk": 0.0},
}

## 武器基础类型：per class。dmg 为基础攻击。
const WEAPONS := {
	"bow": {"name": "长弓", "classes": ["archer"], "dmg": 12},
	"hammer": {"name": "战锤", "classes": ["warrior"], "dmg": 18},
	"shieldblade": {"name": "壁垒剑盾", "classes": ["shield"], "dmg": 15},
	"daggers": {"name": "双影匕", "classes": ["assassin"], "dmg": 14},
	"staff": {"name": "星辉法杖", "classes": ["mage"], "dmg": 13},
}

## 装备槽位与部位词缀池：head 头部 / body 躯干 / hands 手部 / trinket 饰品。
const SLOTS := ["head", "body", "hands", "trinket"]
const SLOT_NAMES := {"head": "头部", "body": "躯干", "hands": "手部", "trinket": "饰品"}
const GEAR_POOL := {
	"head": [
		{"id": "iron_helm", "name": "铁盔", "bonus": {"hp_max": 10}},
		{"id": "rune_circlet", "name": "符文头环", "bonus": {"mp_max": 12}},
		{"id": "shadow_hood", "name": "暗影兜帽", "bonus": {"crit": 0.03}},
	],
	"body": [
		{"id": "chain_mail", "name": "锁子甲", "bonus": {"armor": 2, "hp_max": 6}},
		{"id": "wander_cloak", "name": "旅者斗篷", "bonus": {"speed": 0.04}},
		{"id": "ember_plate", "name": "余烬胸甲", "bonus": {"armor": 3}},
	],
	"hands": [
		{"id": "leather_gloves", "name": "皮护手", "bonus": {"atk": 2}},
		{"id": "arcane_gauntlet", "name": "奥术护腕", "bonus": {"mp_max": 8, "atk": 1}},
		{"id": "hunter_grips", "name": "猎手握腕", "bonus": {"crit": 0.02, "atk": 1}},
	],
	"trinket": [
		{"id": "ember_charm", "name": "余火吊坠", "bonus": {"hp_max": 8, "armor": 1}},
		{"id": "moon_ring", "name": "月辉戒指", "bonus": {"mp_max": 15}},
		{"id": "coin_tooth", "name": "兽齿钱串", "bonus": {"gold_find": 0.08}},
		{"id": "wind_brooch", "name": "疾风胸针", "bonus": {"speed": 0.05}},
	],
}

## 消耗品与材料（可堆叠，堆叠上限 STACK_MAX）。
const STACK_MAX := 99
const CONSUMABLES := {
	"potion_hp": {"name": "生命药剂", "desc": "恢复 35 点生命", "price": 25, "stack": true},
	"potion_mp": {"name": "法力药剂", "desc": "恢复 30 点法力", "price": 30, "stack": true},
	"torch": {"name": "火把", "desc": "手持照明；E 放置于地面，燃烧 5 分钟", "price": 12, "stack": true},
	"net": {"name": "捕兽网", "desc": "对重伤(<30%生命)的野兽使用，尝试驯服为宠物", "price": 45, "stack": true},
	"herb": {"name": "月苔草", "desc": "任务材料，协会收购", "price": 8, "stack": true},
	"pelt": {"name": "兽皮", "desc": "任务材料，可出售", "price": 14, "stack": true},
	"shard": {"name": "深渊碎片", "desc": "武器强化的必需材料", "price": 22, "stack": true},
}

## 武器升级消耗：金币 + 碎片。每级成长 15% 基础攻击。
static func upgrade_cost(level: int) -> Dictionary:
	return {"gold": 30 + level * 25, "shard": level}

static func weapon_atk(inst: Dictionary) -> int:
	var base: int = WEAPONS[inst.base].dmg
	return int(round(base * (1.0 + 0.15 * (inst.level - 1)) * RARITY_MULT[inst.rarity]))

static func affix_atk_bonus(inst: Dictionary) -> float:
	var total := 0.0
	for a in inst.get("affixes", []):
		total += AFFIXES[a].atk
	return total

## 生成武器实例。weight_rarity: 运气加成偏好高稀有。
static func roll_weapon(rng: RandomNumberGenerator, class_id: String, depth: int = 0, luck: float = 0.0) -> Dictionary:
	var pool: Array = []
	for base in WEAPONS:
		if WEAPONS[base].classes.has(class_id):
			pool.append(base)
	var base: String = pool[rng.randi() % pool.size()]
	var rarity := roll_rarity(rng, luck)
	var affixes: Array = []
	var n: int = RARITY_AFFIX_COUNT[rarity]
	var keys := AFFIXES.keys()
	keys.shuffle()
	for i in range(mini(n, keys.size())):
		affixes.append(keys[i])
	var w := int(clampf(depth * 0.5 + rng.randf() * 2.0, 1.0, 5.0))
	var prefix: String = ["", "精工·", "秘银·", "符文·", "龙语·"][rarity]
	return {"kind": "weapon", "base": base, "name": prefix + WEAPONS[base].name, "rarity": rarity, "level": w, "affixes": affixes, "stack": false, "count": 1}

## 新手武器：稀有度 0、无词缀、1 级的保底武器（开局体验保障，按职业发放）。
static func starter_weapon(class_id: String) -> Dictionary:
	for base in WEAPONS:
		if WEAPONS[base].classes.has(class_id):
			return {"kind": "weapon", "base": base, "name": WEAPONS[base].name, "rarity": 0, "level": 1, "affixes": [], "stack": false, "count": 1}
	return {"kind": "weapon", "base": "bow", "name": WEAPONS["bow"].name, "rarity": 0, "level": 1, "affixes": [], "stack": false, "count": 1}

static func roll_gear(rng: RandomNumberGenerator, luck: float = 0.0) -> Dictionary:
	var slot: String = SLOTS[rng.randi() % SLOTS.size()]
	var pool: Array = GEAR_POOL[slot]
	var def: Dictionary = pool[rng.randi() % pool.size()]
	var rarity := roll_rarity(rng, luck)
	var g := {"kind": "gear", "slot": slot, "base": def.id, "name": def.name, "rarity": rarity, "level": 1, "affixes": [], "stack": false, "count": 1, "bonus": def.bonus.duplicate()}
	# 稀有度提升主属性。
	for k in g.bonus:
		g.bonus[k] = g.bonus[k] * (1.0 + 0.25 * rarity) if typeof(g.bonus[k]) == TYPE_FLOAT else int(round(g.bonus[k] * (1.0 + 0.25 * rarity)))
	return g

static func roll_rarity(rng: RandomNumberGenerator, luck: float = 0.0) -> int:
	var weights := []
	for i in range(RARITY_WEIGHT.size()):
		var w: float = RARITY_WEIGHT[i] * (1.0 + luck * i * 0.6)
		weights.append(w)
	var total := 0.0
	for w in weights: total += w
	var pick := rng.randf() * total
	for i in range(weights.size()):
		pick -= weights[i]
		if pick <= 0.0: return i
	return 0

## 消耗品/材料实例。
static func stack_item(id: String, count: int = 1) -> Dictionary:
	return {"kind": "consumable", "base": id, "name": CONSUMABLES[id].name, "rarity": 0, "level": 0, "affixes": [], "stack": true, "count": count}

## 装备部位加成汇总（含稀有度成长）。
static func gear_bonus(gear: Dictionary) -> Dictionary:
	var bonus: Dictionary = {}
	if not gear.has("bonus"): return bonus
	for k in gear.bonus:
		bonus[k] = gear.bonus[k]
	return bonus

static func item_desc(inst: Dictionary) -> String:
	if inst.kind == "weapon":
		var s := "%s · %s Lv%d\n攻击 +%d" % [inst.name, RARITY_NAMES[inst.rarity], inst.level, weapon_atk(inst)]
		for a in inst.affixes:
			s += "\n◆ %s：%s" % [AFFIXES[a].name, AFFIXES[a].desc]
		return s
	if inst.kind == "gear":
		var s := "%s · %s\n槽位：%s" % [inst.name, RARITY_NAMES[inst.rarity], SLOT_NAMES[inst.slot]]
		var parts := []
		for k in inst.bonus:
			parts.append(_stat_name(k) + " +" + str(inst.bonus[k]))
		if parts.size() > 0: s += "\n" + "  ".join(parts)
		return s
	return CONSUMABLES[inst.base].desc

static func _stat_name(k: String) -> String:
	match k:
		"hp_max": return "生命上限"
		"mp_max": return "法力上限"
		"armor": return "护甲"
		"crit": return "暴击率"
		"speed": return "移速"
		"gold_find": return "寻获金币"
		"atk": return "攻击"
	return k
