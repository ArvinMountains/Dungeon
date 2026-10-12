class_name QuestBook
extends RefCounted
## 任务系统：支线 / 日常 / 随机事件 三类。暂无主线。
## objective.kind: kill(击杀x) / kill_kind(击杀指定种族) / collect(收集材料) / clear(通关房间)
##                / capture(捕获宠物) / skill(使用技能x次) / spend(消费金币x) / elite(击杀精英x)
## 进度由 GameState.bump_quest(kind, target, n) 统一推进；协会/任务日志界面领奖。

const SIDE_QUESTS := [
	{"id": "side_wolves", "name": "山林狼患", "desc": "森林边缘的狼群袭击了商路。猎杀 5 匹灰狼。", "giver": "guild",
		"objective": {"kind": "kill_kind", "target": "wolf", "count": 5}, "reward": {"gold": 60, "xp": 40}},
	{"id": "side_herbs", "name": "月苔与晨露", "desc": "药剂师需要 3 株月苔草熬制防疫合剂。", "giver": "guild",
		"objective": {"kind": "collect", "target": "herb", "count": 3}, "reward": {"gold": 45, "xp": 30, "item": "potion_hp"}},
	{"id": "side_elite", "name": "悬赏：碎颅者", "desc": "一只佩戴骸骨项链的精英低语者在深渊游荡。讨伐它。", "giver": "guild",
		"objective": {"kind": "elite", "target": "", "count": 1}, "reward": {"gold": 120, "xp": 80, "diamonds": 2}},
	{"id": "side_pet", "name": "毛茸茸的邻居", "desc": "协会学者想研究驯兽。捕获 1 只野外动物。", "giver": "guild",
		"objective": {"kind": "capture", "target": "", "count": 1}, "reward": {"gold": 50, "xp": 50, "item": "net"}},
	{"id": "side_shards", "name": "深渊的回响", "desc": "收集 5 枚深渊碎片，铁匠愿意出个好价钱。", "giver": "guild",
		"objective": {"kind": "collect", "target": "shard", "count": 5}, "reward": {"gold": 110, "xp": 60}},
	{"id": "side_rooms", "name": "开拓者", "desc": "深入第一层，肃清 6 个危险区域。", "giver": "guild",
		"objective": {"kind": "clear", "target": "", "count": 6}, "reward": {"gold": 150, "xp": 120, "diamonds": 3}},
]

## 日常任务池：每游戏日从池中随机 3 条，当日有效。
const DAILY_POOL := [
	{"id": "d_kill", "name": "日常巡猎", "desc": "击杀任意敌人 10 次", "objective": {"kind": "kill", "target": "", "count": 10}, "reward": {"gold": 40, "xp": 30}},
	{"id": "d_skill", "name": "熟能生巧", "desc": "使用主动技能 15 次", "objective": {"kind": "skill", "target": "", "count": 15}, "reward": {"gold": 35, "xp": 30}},
	{"id": "d_spend", "name": "散财免灾", "desc": "在商店消费 80 金币", "objective": {"kind": "spend", "target": "", "count": 80}, "reward": {"gold": 30, "xp": 20, "item": "potion_mp"}},
	{"id": "d_potion", "name": "炼金学徒", "desc": "使用 2 瓶药剂", "objective": {"kind": "use", "target": "potion", "count": 2}, "reward": {"gold": 25, "xp": 20}},
	{"id": "d_clear", "name": "扫荡者", "desc": "肃清 3 个深渊区域", "objective": {"kind": "clear", "target": "", "count": 3}, "reward": {"gold": 45, "xp": 35}},
	{"id": "d_elite", "name": "精英猎人", "desc": "击杀 1 只精英敌人", "objective": {"kind": "elite", "target": "", "count": 1}, "reward": {"gold": 60, "xp": 40}},
]

## 随机事件（局内遭遇，由关卡生成器投放）。
const EVENTS := [
	{"id": "ev_shrine", "name": "低语祭坛", "desc": "献祭 15% 当前生命，换取力量。", "type": "choice"},
	{"id": "ev_merchant", "name": "神秘行商", "desc": "一位裹着斗篷的商贩在阴影里等待。", "type": "shop"},
	{"id": "ev_chest", "name": "锈蚀宝箱", "desc": "开箱有惊喜——也可能是一根毒针。", "type": "gamble"},
	{"id": "ev_fountain", "name": "月泉", "desc": "泉水恢复了你的法力与生命。", "type": "heal"},
	{"id": "ev_scholar", "name": "流浪学者", "desc": "回答正确即可获得他的研究赞助。", "type": "quiz"},
]
const QUIZ_BANK := [
	{"q": "深渊在城下延伸了多少年？", "a": ["七十年", "三百年", "无人知晓"], "correct": 2, "hint": "「无人知晓」——学者满意地点头。"},
	{"q": "余火水晶为何物？", "a": ["死者的执念", "城火的余烬", "深渊的眼泪"], "correct": 1, "hint": "「城火的余烬」——正是如此。"},
	{"q": "深渊之门的钥匙共有几枚？", "a": ["一枚", "三枚", "七枚"], "correct": 1, "hint": "「三枚」——传说如此。"},
]

## 成就（钻石来源，局外）。check 由 GameState 检查。
const ACHIEVEMENTS := [
	{"id": "ach_first_clear", "name": "初探深渊", "desc": "首次通关第一层", "diamonds": 5},
	{"id": "ach_kill50", "name": "百战之躯", "desc": "累计击杀 50 个敌人", "diamonds": 3},
	{"id": "ach_kill200", "name": "深渊收割者", "desc": "累计击杀 200 个敌人", "diamonds": 8},
	{"id": "ach_pet1", "name": "驯兽新人", "desc": "捕获第一只宠物", "diamonds": 3},
	{"id": "ach_party", "name": "志同道合", "desc": "首次招募同伴", "diamonds": 3},
	{"id": "ach_level5", "name": "崭露头角", "desc": "角色达到 5 级", "diamonds": 3},
	{"id": "ach_level10", "name": "身经百战", "desc": "角色达到 10 级", "diamonds": 6},
	{"id": "ach_legend", "name": "传说之握", "desc": "获得一件传说品质装备", "diamonds": 5},
	{"id": "ach_daily3", "name": "勤勉冒险者", "desc": "完成 3 个日常任务", "diamonds": 3},
	{"id": "ach_build", "name": "自成一派", "desc": "单分支加点达到 10 级", "diamonds": 4},
]

## 随机挑选当日 3 个日常。
static func roll_daily(rng: RandomNumberGenerator) -> Array:
	var pool := DAILY_POOL.duplicate()
	pool.shuffle()
	return pool.slice(0, 3)
