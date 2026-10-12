class_name NpcBook
extends RefCounted
## NPC 图鉴：主城功能 NPC 与可招募同伴。好感度满 60 可招募入队（最多 3 人同行）。
## dialogs: 日常对话（轮换）；gift: 偏好礼物（对物品 base id，+8 好感）。

const AFFINITY_RECRUIT_AT := 60
const TALK_AFFINITY := 1      # 每日首次对话
const GIFT_AFFINITY := 5      # 普通礼物
const GIFT_FAV_AFFINITY := 8  # 偏好礼物

# ---------------- 组队列阵（参考 Baldur's Gate II 的一键阵型） ----------------
## 三个预设，X 键循环。offset 为「相对玩家、+Z 朝前」的槽位坐标。
## 槽位间距 ≥1.5m：近战交战半径约 1.0~1.5m，再挤会互相卡位。
const FORMATIONS := {
	"follow": {"name": "纵队跟随", "desc": "排成一路跟在身后，窄道/赶路用"},
	"spread": {"name": "展开横排", "desc": "左右拉开并肩推进，接敌用"},
	"surround": {"name": "两翼包抄", "desc": "绕到前方两翼夹击，围杀用"},
}
const FORMATION_ORDER := ["follow", "spread", "surround"]

## 阵型槽位偏移（local：x=右、z=前）。
static func formation_offset(formation: String, slot: int, count: int) -> Vector3:
	var n: int = maxi(count, 1)
	match formation:
		"spread":
			# 横排：以玩家为中线左右展开，略微靠后。
			var x: float = (float(slot) - (float(n) - 1.0) * 0.5) * 1.7
			return Vector3(x, 0, -1.7)
		"surround":
			# 两翼：玩家前方 ±55° 半径 2.8m 包抄。
			var t: float = 0.0 if n <= 1 else float(slot) / float(n - 1)
			var ang: float = deg_to_rad(-55.0 + t * 110.0)
			return Vector3(sin(ang) * 2.8, 0, cos(ang) * 2.8)
		_:
			# 纵队：正后方一列。
			return Vector3(0, 0, -1.6 - float(slot) * 1.4)

## 行为档位（参考 Dragon Age: Origins 的 behavior 档，收敛为 3 档）。
const STANCES := {
	"passive": {"name": "护航", "desc": "只反击打你的敌人，始终贴在你身边"},
	"normal": {"name": "均衡", "desc": "打你锁定的目标，最远 10m"},
	"aggressive": {"name": "主动", "desc": "主动扑最近的敌人，最远 13m"},
}
const STANCE_ORDER := ["passive", "normal", "aggressive"]

## 技能组合：同伴攻击给敌人挂「先手标记」，玩家命中即引爆（参考 Mass Effect 3 的 prime→detonate）。
## 伤害公式确定：引爆额外伤害 = 本次命中伤害 × DETONATE_RATIO。
const DETONATE_RATIO := 0.4
const MARK_DURATION := 4.0      # 标记存活时间
const MARK_RECAST := 3.0        # 同一敌人两次引爆的最短间隔（防刷）
const MARK_BY_RIG := {
	"warrior": {"id": "sunder", "name": "破甲", "color": Color(1.0, 0.55, 0.35)},
	"shield": {"id": "sunder", "name": "破甲", "color": Color(1.0, 0.55, 0.35)},
	"archer": {"id": "rend", "name": "撕裂", "color": Color(1.0, 0.78, 0.35)},
	"mage": {"id": "shock", "name": "感电", "color": Color(0.70, 0.60, 1.0)},
	"barbarian": {"id": "sunder", "name": "破甲", "color": Color(1.0, 0.55, 0.35)},
}

const NPCS := {
	"rowan": {
		"name": "罗兰", "role": "冒险者协会 · 接待官", "accent": Color(0.55, 0.65, 0.5),
		"rig": "warrior", "combat": {"atk": 10, "hp": 15},
		"aura": {"stat": "crit", "value": 0.03, "desc": "老兵直觉：暴击 +3%"},
		"gift": "pelt",
		"dialogs": [
			"深渊在三百年前吞掉了旧王城。我们守着这里，等愿意下去的人。",
			"协会的规矩：活着的冒险者比死了的英雄有用。量力而行。",
			"灰狼又袭击商路了。悬赏贴在板上，你看着办。",
		],
		"recruit_line": "带上我。你的剑法不错，但你有太多破绽。",
	},
	"mira": {
		"name": "米拉", "role": "药剂摊 · 调药师", "accent": Color(0.6, 0.7, 0.75),
		"rig": "archer", "combat": {"atk": 8, "hp": 10},
		"aura": {"stat": "mp_regen", "value": 0.6, "desc": "药剂支援：法力回复 +0.6/秒"},
		"gift": "herb",
		"dialogs": [
			"月苔草要在黎明前采，露水没干的时候药性最足。",
			"这瓶给你，别喝太快——药剂不是糖水。",
			"你身上的伤又在裂开了。坐下，我看看。",
		],
		"recruit_line": "正好，我需要新鲜的战斗样本……我是说，我需要历练。",
	},
	"kane": {
		"name": "凯恩", "role": "武器商家 · 雇佣护卫", "accent": Color(0.75, 0.57, 0.34),
		"rig": "warrior", "combat": {"atk": 13, "hp": 20},
		"aura": {"stat": "atk", "value": 2, "desc": "开锋：攻击 +2"},
		"gift": "shard",
		"dialogs": [
			"这些武器都是我亲手磨的。钝了的拿回来，免费开锋。",
			"深渊碎片是好东西。武器强化缺不了它。",
			"别用那种廉价货对付精英，会害死你。",
		],
		"recruit_line": "佣金好说。你负责吸引仇恨，我负责收账。",
	},
	"sylphie": {
		"name": "西尔芙", "role": "图书馆 · 星图学者", "accent": Color(0.6, 0.55, 0.9),
		"rig": "mage", "combat": {"atk": 12, "hp": 5},
		"aura": {"stat": "skill_amp", "value": 0.05, "desc": "星图推演：技能伤害 +5%"},
		"gift": "torch",
		"dialogs": [
			"星图显示深渊之门正在松动。时间不多了。",
			"图书馆的禁忌区要凭协会勋章进入。你还没有。",
			"法师的强大不在于蓝多，在于知道该把蓝花在哪。",
		],
		"recruit_line": "我计算过你的生还率。带上我，能提高百分之十七。",
	},
	"borin": {
		"name": "博林", "role": "修炼场 · 教官", "accent": Color(0.58, 0.6, 0.52),
		"rig": "shield", "combat": {"atk": 9, "hp": 30},
		"aura": {"stat": "armor", "value": 1, "desc": "盾墙：护甲 +1"},
		"gift": "potion_hp",
		"dialogs": [
			"木桩不会还手，深渊会。在这里把动作练成本能。",
			"大盾不是躲起来，是让别人知道该往哪站。",
			"今天你也迟到。深渊可不等人。",
		],
		"recruit_line": "行。老头子我陪你走一趟，看看你的训练成果。",
	},
}

## 同伴战斗台词（随机播报）。
const BATTLE_LINES := {
	"rowan": ["交给我！", "稳住阵脚！", "就这？"],
	"mira": ["喝下这个！", "伤口在说话。", "别乱动！"],
	"kane": ["这笔账记下了！", "武器不会说谎！", "开锋的时刻到了！"],
	"sylphie": ["星辰指引。", "计算完毕。", "元素，听从。"],
	"borin": ["站我身后！", "盾墙如山！", "训练场见真章！"],
}
