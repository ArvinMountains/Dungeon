class_name SkillBook
extends RefCounted
## 技能数据库：5 职业 × 4 主动 + 2 被动。
## 主动技能由战斗层按 effect 类型执行；键位 1/2/3/4（Q 等效 4）。
## effect 类型: melee_arc / projectile / nova / aoe_target / dash / blink_strike / buff / rain / mark / chain

## 被动字段: stats 静态加成；hooks 触发型 {on_kill_heal, thorns, mp_on_kill, stealth, execute}
const CLASSES := {
	"archer": {
		"name": "精灵弓箭手", "accent": Color(0.55, 0.69, 0.5),
		"actives": [
			{"key": "s1", "name": "疾风连射", "effect": "projectile", "mp": 8, "cd": 3.0, "dmg": 9, "count": 3, "speed": 17.0, "desc": "连射三支箭"},
			{"key": "s2", "name": "穿云箭", "effect": "projectile", "mp": 12, "cd": 5.0, "dmg": 18, "count": 1, "speed": 24.0, "pierce": true, "desc": "贯穿直线的所有敌人"},
			{"key": "s3", "name": "风行后跃", "effect": "dash", "mp": 10, "cd": 6.0, "dmg": 8, "dist": 5.0, "desc": "向后闪避并对路径敌人造成伤害"},
			{"key": "s4", "name": "月蚀箭雨", "effect": "rain", "mp": 30, "cd": 12.0, "dmg": 34, "radius": 4.2, "range": 13.5, "dur": 1.35, "ult": true, "desc": "天降箭雨轰击目标区域"},
		],
		"passives": [
			{"name": "静默步", "stats": {"speed": 0.06}, "desc": "移速 +6%"},
			{"name": "鹰眼", "stats": {"crit": 0.05}, "desc": "暴击率 +5%"},
		],
	},
	"warrior": {
		"name": "铁匠战士", "accent": Color(0.75, 0.57, 0.34),
		"actives": [
			{"key": "s1", "name": "重锤猛击", "effect": "melee_arc", "mp": 6, "cd": 2.5, "dmg": 26, "radius": 2.8, "arc": 2.0, "desc": "正面扇形重击"},
			{"key": "s2", "name": "熔岩震波", "effect": "nova", "mp": 14, "cd": 6.0, "dmg": 20, "radius": 4.5, "desc": "以自身为中心的熔岩环"},
			{"key": "s3", "name": "铁壁姿态", "effect": "buff", "mp": 12, "cd": 10.0, "dur": 5.0, "buff": {"armor": 6, "speed": -0.1}, "desc": "5 秒内护甲 +6，移速 -10%"},
			{"key": "s4", "name": "余烬震击", "effect": "nova", "mp": 30, "cd": 12.0, "dmg": 46, "radius": 5.5, "ult": true, "desc": "余烬爆裂震慑四周"},
		],
		"passives": [
			{"name": "不熄熔心", "stats": {"armor": 1}, "desc": "护甲 +1"},
			{"name": "锻造之魂", "stats": {"atk": 2}, "desc": "攻击 +2"},
		],
	},
	"shield": {
		"name": "大盾守卫", "subtitle": "BULWARK OF THE LAST GATE", "tags": ["坦克", "反伤", "不动如山"],
		"description": "城门陷落那夜，他举盾而立。一夜之后，盾上刻满了牙印，城却没有破。",
		"trait": "巨岩体质", "motto": "我身后，就是家园。", "icon": "shield", "accent": Color(0.58, 0.60, 0.52), "walk_speed": 2.3,
		"actives": [
			{"key": "s1", "name": "盾击", "effect": "melee_arc", "mp": 5, "cd": 2.0, "dmg": 16, "radius": 2.4, "arc": 1.6, "stun": 0.8, "desc": "盾牌猛击，短暂眩晕"},
			{"key": "s2", "name": "荆棘反甲", "effect": "buff", "mp": 12, "cd": 9.0, "dur": 6.0, "buff": {"thorns": 8, "armor": 3}, "desc": "6 秒内受击反弹 8 点伤害"},
			{"key": "s3", "name": "守护冲锋", "effect": "dash", "mp": 14, "cd": 7.0, "dmg": 18, "dist": 7.0, "taunt": true, "desc": "向前冲锋，嘲讽路径敌人"},
			{"key": "s4", "name": "山岳不动", "effect": "nova", "mp": 30, "cd": 14.0, "dmg": 40, "radius": 5.0, "shield": 25, "ult": true, "desc": "大地轰鸣：范围重击并获得 25 点护盾"},
		],
		"passives": [
			{"name": "巨岩体质", "stats": {"armor": 2}, "desc": "护甲 +2"},
			{"name": "稳如磐石", "stats": {"knockback_res": 1.0}, "desc": "免疫击退"},
		],
	},
	"assassin": {
		"name": "暗影刺客", "subtitle": "A KNIFE IN THE QUIET", "tags": ["敏捷", "爆发", "影中行走的刀"],
		"description": "没人见过她的出手，只见过结果。夜色是她的鞘，杀意是她的刃。",
		"trait": "影遁", "motto": "你听见的，是风声。", "icon": "dagger", "accent": Color(0.45, 0.48, 0.62), "walk_speed": 3.6,
		"actives": [
			{"key": "s1", "name": "影袭", "effect": "blink_strike", "mp": 10, "cd": 4.0, "dmg": 22, "range": 8.0, "desc": "闪现至目标身后突刺"},
			{"key": "s2", "name": "毒刃", "effect": "melee_arc", "mp": 8, "cd": 3.0, "dmg": 12, "radius": 2.5, "arc": 1.8, "poison": 5, "dur": 3.0, "desc": "淬毒攻击，3 秒共 15 点毒伤"},
			{"key": "s3", "name": "疾影连斩", "effect": "melee_arc", "mp": 12, "cd": 5.0, "dmg": 10, "hits": 3, "radius": 2.6, "arc": 2.2, "desc": "三段快速连斩"},
			{"key": "s4", "name": "死亡印记", "effect": "mark", "mp": 28, "cd": 13.0, "dmg": 30, "execute": 0.25, "ult": true, "desc": "标记目标：8 秒内对标记目标伤害 +50%，低于 25% 生命直接处决"},
		],
		"passives": [
			{"name": "嗜血", "hooks": {"on_kill_heal": 6}, "desc": "击杀回复 6 点生命"},
			{"name": "先手威慑", "stats": {"crit": 0.08}, "desc": "暴击率 +8%"},
		],
	},
	"mage": {
		"name": "星辉法师", "subtitle": "READER OF THE FALLEN STAR", "tags": ["远程", "法术", "观星者"],
		"description": "她从星图里读出了深渊的坐标。从那天起，星星便是她的箭袋。",
		"trait": "奥术亲和", "motto": "星辰坠落之处，即为疆界。", "icon": "staff", "accent": Color(0.60, 0.55, 0.90), "walk_speed": 2.9,
		"actives": [
			{"key": "s1", "name": "奥术飞弹", "effect": "projectile", "mp": 7, "cd": 1.8, "dmg": 11, "count": 2, "speed": 15.0, "homing": true, "desc": "两枚追踪飞弹"},
			{"key": "s2", "name": "冰霜新星", "effect": "nova", "mp": 14, "cd": 5.0, "dmg": 16, "radius": 4.0, "slow": 0.35, "desc": "冰环扩散，减速敌人"},
			{"key": "s3", "name": "连锁闪电", "effect": "chain", "mp": 16, "cd": 6.0, "dmg": 15, "jumps": 3, "range": 7.0, "desc": "电弧在 3 个目标间跳跃"},
			{"key": "s4", "name": "星辰坠落", "effect": "rain", "mp": 32, "cd": 14.0, "dmg": 38, "radius": 4.5, "range": 12.0, "dur": 1.6, "ult": true, "desc": "召唤星陨轰击目标区域"},
		],
		"passives": [
			{"name": "奥术亲和", "stats": {"mp_regen": 1.5}, "desc": "法力回复 +1.5/秒"},
			{"name": "元素共鸣", "stats": {"skill_amp": 0.08}, "desc": "技能伤害 +8%"},
		],
	},
}

static func actives(class_id: String) -> Array:
	return CLASSES[class_id].actives

static func passives(class_id: String) -> Array:
	return CLASSES[class_id].passives

## 汇总被动静态加成。
static func passive_stats(class_id: String) -> Dictionary:
	var out := {}
	for p in CLASSES[class_id].passives:
		for k in p.get("stats", {}):
			out[k] = out.get(k, 0.0) + p.stats[k]
	return out

static func passive_hooks(class_id: String) -> Dictionary:
	var out := {}
	for p in CLASSES[class_id].passives:
		for k in p.get("hooks", {}):
			out[k] = out.get(k, 0.0) + p.hooks[k]
	return out
