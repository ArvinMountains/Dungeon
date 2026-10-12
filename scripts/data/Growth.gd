class_name Growth
extends RefCounted
## 加点系统：5 分支 × 10 级，含互斥与联动规则，支撑差异化 build。
## 点数来源：角色升级（击杀/任务 XP，每级 +1）与钻石特权礼包。
## 分支: brute 狂野(攻击) / bulwark 坚壁(生存) / swift 灵巧(暴击速度) / arcane 秘术(法力技能) / greed 贪婪(经济掉落)

const MAX_LEVEL := 10
const TOTAL_POINTS_CAP := 24  # 总投入上限，防止堆满所有分支

const BRANCHES := {
	"brute": {
		"name": "狂野", "icon": "⚔", "color": Color(0.85, 0.42, 0.34),
		"desc": "每级：攻击 +2。10 级觉醒「狂暴」：生命低于 40% 时伤害 +30%。",
	},
	"bulwark": {
		"name": "坚壁", "icon": "🛡", "color": Color(0.55, 0.65, 0.75),
		"desc": "每级：生命上限 +3、护甲 +1。10 级觉醒「荆棘」：受击反弹 4 点伤害。",
	},
	"swift": {
		"name": "灵巧", "icon": "🌀", "color": Color(0.52, 0.82, 0.58),
		"desc": "每级：暴击率 +1.5%，每 2 级移速 +2%。10 级觉醒「疾风步」：暴击后移速爆发。",
	},
	"arcane": {
		"name": "秘术", "icon": "✦", "color": Color(0.62, 0.52, 0.92),
		"desc": "每级：法力上限 +8、技能伤害 +4%。10 级觉醒「法力回流」：击杀回蓝 8 点。",
	},
	"greed": {
		"name": "贪婪", "icon": "◈", "color": Color(0.9, 0.76, 0.35),
		"desc": "每级：金币获取 +5%、掉落寻获 +3%。10 级觉醒「寻宝者」：宝箱位多掉 1 件。",
	},
}

## 互斥规则：分支总级约束。违反时无法加点。
## brute+bulwark ≤ 12（狂战与铁壁不可兼得）；swift+greed ≤ 14（修行与敛财难两全）。
const EXCLUSIONS := [
	{"a": "brute", "b": "bulwark", "cap": 12, "text": "狂野与坚壁的等级之和不可超过 12"},
	{"a": "swift", "b": "greed", "cap": 14, "text": "灵巧与贪婪的等级之和不可超过 14"},
]

## 联动规则（被动觉醒，仅提示用；数值由 bonuses 计算）。
const SYNERGIES := [
	{"req": {"brute": 5, "bulwark": 5}, "id": "warcry", "name": "战意", "desc": "击杀回复 3 点生命"},
	{"req": {"swift": 5, "arcane": 5}, "id": "arcspeed", "name": "奥术迅捷", "desc": "技能冷却 -15%"},
	{"req": {"arcane": 3, "brute": 3}, "id": "spellblade", "name": "魔剑", "desc": "普攻附加 4 点秘术伤害"},
]

## 三种推荐 build（供一键预览，不自动加点）。
const BUILDS := {
	"berserker": {"name": "血怒狂战士", "desc": "放弃护甲，把每一滴血都换成伤害。低血高斩杀，狂暴收割。",
		"points": {"brute": 10, "bulwark": 2, "swift": 4, "arcane": 0, "greed": 0}},
	"spellblade": {"name": "奥术魔剑士", "desc": "秘术与灵巧交织，冷却飞快、蓝量充盈，技能永动机。",
		"points": {"brute": 3, "bulwark": 3, "swift": 6, "arcane": 10, "greed": 0}},
	"treasure": {"name": "深渊寻宝人", "desc": "金币翻倍、掉落琳琅，靠装备与经济碾压深渊。",
		"points": {"brute": 4, "bulwark": 4, "swift": 5, "arcane": 0, "greed": 10}},
}

## 由加点派生的属性加成。点数表: {"brute":int,...}
static func bonuses(points: Dictionary) -> Dictionary:
	var b := {"atk": 0, "hp_max": 0, "armor": 0, "crit": 0.0, "speed": 0.0, "mp_max": 0, "skill_amp": 0.0, "gold_find": 0.0, "luck": 0.0}
	b.atk += int(points.get("brute", 0)) * 2
	var bul := int(points.get("bulwark", 0))
	b.hp_max += bul * 3
	b.armor += bul
	var sw := int(points.get("swift", 0))
	b.crit += sw * 0.015
	b.speed += float(int(sw / 2.0)) * 0.02
	var ar := int(points.get("arcane", 0))
	b.mp_max += ar * 8
	b.skill_amp += ar * 0.04
	var gr := int(points.get("greed", 0))
	b.gold_find += gr * 0.05
	b.luck += gr * 0.03
	return b

## 已激活的联动觉醒 id 列表。
static func active_synergies(points: Dictionary) -> Array:
	var ids := []
	for s in SYNERGIES:
		var ok := true
		for k in s.req:
			if int(points.get(k, 0)) < s.req[k]: ok = false; break
		if ok: ids.append(s.id)
	return ids

## 尝试加点：返回 "" 成功，否则返回失败原因。
static func allocate(points: Dictionary, branch: String) -> String:
	if not BRANCHES.has(branch): return "未知分支"
	var cur := int(points.get(branch, 0))
	if cur >= MAX_LEVEL: return "该分支已满级"
	if cur >= 1 and int(points.get(branch, 0)) - 1 >= cur and cur > 0: return "需先升级低级节点"  # 顺序节点约束
	var total := 0
	for k in points: total += int(points[k])
	if total >= TOTAL_POINTS_CAP: return "总点数已达上限 %d" % TOTAL_POINTS_CAP
	var next := points.duplicate()
	next[branch] = cur + 1
	for rule in EXCLUSIONS:
		var sum := int(next.get(rule.a, 0)) + int(next.get(rule.b, 0))
		if sum > rule.cap: return rule.text
	points[branch] = cur + 1
	return ""

static func respec_available(points: Dictionary) -> bool:
	var total := 0
	for k in points: total += int(points[k])
	return total > 0

## 全部重置（洗点，消耗金币）。
static func respec_cost(points: Dictionary) -> int:
	var total := 0
	for k in points: total += int(points[k])
	return total * 20
