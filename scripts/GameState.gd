extends Node
## GameState (autoload) — v2
## 全局状态与存档：职业、双货币（金币/钻石）、加点、背包/装备、任务、宠物、好感度/队伍、成就、昼夜。
## 昼夜周期：10 分钟一个完整循环（day_speed = 24 小时 / 600 秒）。

signal class_changed(id: String)
signal gold_changed(v: int)
signal diamonds_changed(v: int)
signal hp_changed(v: int)
signal mp_changed(v: float)
signal potions_changed(v: int)
signal quest_changed
signal embers_changed
signal day_time_changed(hours: float)
signal day_paused_changed(paused: bool)
signal xp_changed(level: int, xp: int, need: int)
signal inventory_changed
signal equipment_changed
signal quests_changed
signal pets_changed
signal party_changed
signal achievement_unlocked(id: String, name: String, diamonds: int)
signal toast_requested(text: String)

const SAVE_PATH := "user://lost-abyss-save-v2.json"
const SAVE_BACKUP_PATH := "user://lost-abyss-save-v2-backup.json"
const V1_SAVE_PATH := "user://lost-abyss-save-v1.json"

## 职业战斗/视觉数据（技能表见 SkillBook）。新增：shield 大盾 / assassin 刺客 / mage 法师。
const CLASS_DATA := {
	"archer": {
		"name": "精灵弓箭手", "subtitle": "WARDEN OF THE WITHERED WOODS",
		"tags": ["远程", "敏捷", "古林守望者"],
		"description": "旧日森林最后的低语者。以月光为弦，以寂静为誓，在黑暗察觉之前，箭已离弦。",
		"stats": [2, 5, 3], "trait": "寂静猎手", "motto": "风记得每一支箭的归途。", "icon": "bow",
		"accent": Color(0.55, 0.69, 0.5), "walk_speed": 3.2,
		"guard": {"window": 0.30, "reduction": 0.40},
		"attack_range": 11.5, "attack_damage": 14, "attack_hit_time": 0.5, "attack_duration": 0.85, "attack_cooldown": 0.15,
		"basic": "projectile", "mp_regen": 2.0,
	},
	"warrior": {
		"name": "铁匠战士", "subtitle": "THE LAST HAMMER OF THE FORGE",
		"tags": ["近战", "坚韧", "余烬铸造者"],
		"description": "王国已化为灰烬，炉火却从未熄灭。他将往日铸进战锤，以血肉之躯，守住最后一道城门。",
		"stats": [5, 2, 5], "trait": "不熄熔心", "motto": "只要炉火尚存，便不向长夜低头。", "icon": "hammer",
		"accent": Color(0.75, 0.57, 0.34), "walk_speed": 2.7,
		"guard": {"window": 0.35, "reduction": 0.35},
		"attack_range": 2.4, "attack_damage": 22, "attack_hit_time": 0.55, "attack_duration": 0.8, "attack_cooldown": 0.25,
		"basic": "melee_arc", "mp_regen": 2.0,
	},
	"shield": {
		"name": "大盾守卫", "subtitle": "BULWARK OF THE LAST GATE",
		"tags": ["坦克", "反伤", "不动如山"],
		"description": "城门陷落那夜，他举盾而立。一夜之后，盾上刻满了牙印，城却没有破。",
		"stats": [6, 3, 2], "trait": "巨岩体质", "motto": "我身后，就是家园。", "icon": "shield",
		"accent": Color(0.58, 0.60, 0.52), "walk_speed": 2.3,
		"guard": {"window": 0.50, "reduction": 0.25},  # 坦克：招架窗口最宽、减伤最强
		"attack_range": 2.2, "attack_damage": 14, "attack_hit_time": 0.55, "attack_duration": 0.8, "attack_cooldown": 0.3,
		"basic": "melee_arc", "mp_regen": 2.0,
	},
	"assassin": {
		"name": "暗影刺客", "subtitle": "A KNIFE IN THE QUIET",
		"tags": ["敏捷", "爆发", "影中之刃"],
		"description": "没人见过她的出手，只见过结果。夜色是她的鞘，杀意是她的刃。",
		"stats": [3, 6, 2], "trait": "影遁", "motto": "你听见的，是风声。", "icon": "dagger",
		"accent": Color(0.45, 0.48, 0.62), "walk_speed": 3.6,
		"guard": {"window": 0.30, "reduction": 0.45},
		"attack_range": 2.2, "attack_damage": 16, "attack_hit_time": 0.4, "attack_duration": 0.6, "attack_cooldown": 0.12,
		"basic": "melee_arc", "mp_regen": 2.0,
	},
	"mage": {
		"name": "星辉法师", "subtitle": "READER OF THE FALLEN STAR",
		"tags": ["远程", "法术", "观星者"],
		"description": "她从星图里读出了深渊的坐标。从那天起，星星便是她的箭袋。",
		"stats": [2, 4, 5], "trait": "奥术亲和", "motto": "星辰坠落之处，即为疆界。", "icon": "staff",
		"accent": Color(0.60, 0.55, 0.90), "walk_speed": 2.9,
		"guard": {"window": 0.25, "reduction": 0.45},
		"attack_range": 9.5, "attack_damage": 10, "attack_hit_time": 0.45, "attack_duration": 0.7, "attack_cooldown": 0.2,
		"basic": "projectile", "mp_regen": 2.0,
	},
}

var save: Dictionary = {}
var storage_available := true
var storage_notice := ""
var inventory: Inventory

# Day / night：10 分钟完整昼夜（24h / 600s = 0.04 h per s）。
var day_time := 8.0
var day_paused := false
var day_speed := 0.04

func _ready() -> void:
	inventory = Inventory.new()
	inventory.changed.connect(func(): inventory_changed.emit())
	load_save()
	process_mode = Node.PROCESS_MODE_ALWAYS

## 角色升级所需 XP。
static func xp_needed(level: int) -> int:
	return 60 + level * 40

func fresh_save() -> Dictionary:
	return {
		"version": 2, "selected": "archer", "gold": 80, "diamonds": 0, "potions": 1, "hp": 74, "mp": 40.0,
		"upgrade": 0, "quest": "new", "embers": [], "training_reward": false, "training_hits": 0, "quality": "pixel",
		"char_level": 1, "xp": 0, "point_pool": 0,
		"points": {"brute": 0, "bulwark": 0, "swift": 0, "arcane": 0, "greed": 0},
		"inventory": [], "equipment": {"head": null, "body": null, "hands": null, "trinket": null},
		"weapon": null, "stash": [],
		"quests": {"side": {}, "daily": [], "daily_day": 0},
		"pets": [], "active_pet": -1,
		"affinity": {}, "party": [],
		"party_formation": "follow", "party_stance": {},
		"ach": {}, "kills": 0, "runs": 0, "clears": 0, "daily_done": 0,
		"run_buffs": [],
		"last_location": "town",
	}

func valid_save(d) -> bool:
	if typeof(d) != TYPE_DICTIONARY: return false
	if d.get("version") != 2: return false
	if not CLASS_DATA.has(d.get("selected")): return false
	for k in ["gold", "diamonds", "potions", "hp", "char_level", "xp", "point_pool", "kills", "runs", "clears", "daily_done"]:
		if not (d.get(k) is float or d.get(k) is int): return false
		if int(d.get(k)) < 0: return false
	if d.get("gold") > 999999 or d.get("diamonds") > 9999 or d.get("char_level") > 40: return false
	if typeof(d.get("points")) != TYPE_DICTIONARY: return false
	for b in Growth.BRANCHES:
		var v = d.points.get(b, 0)
		if not (v is int or v is float) or int(v) < 0 or int(v) > Growth.MAX_LEVEL: return false
	if typeof(d.get("inventory")) != TYPE_ARRAY or d.inventory.size() > 24: return false
	if typeof(d.get("equipment")) != TYPE_DICTIONARY: return false
	if typeof(d.get("quests")) != TYPE_DICTIONARY: return false
	if typeof(d.get("pets")) != TYPE_ARRAY or d.pets.size() > 6: return false
	if typeof(d.get("party")) != TYPE_ARRAY or d.party.size() > 3: return false
	if typeof(d.get("run_buffs")) != TYPE_ARRAY: return false
	return true

## v1 存档迁移。
func migrate_v1(v1: Dictionary) -> Dictionary:
	var s := fresh_save()
	for k in ["selected", "gold", "potions", "hp", "upgrade", "quest", "training_reward", "training_hits", "quality"]:
		if v1.has(k): s[k] = v1[k]
	if not CLASS_DATA.has(s.selected): s.selected = "archer"
	s.embers = v1.get("embers", [])
	return s

func load_save() -> void:
	save = fresh_save()
	if FileAccess.file_exists(SAVE_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if valid_save(parsed):
			save = parsed
		else:
			_try_backup_or_v1(parsed != null)
	elif FileAccess.file_exists(V1_SAVE_PATH):
		var v1 = JSON.parse_string(FileAccess.get_file_as_string(V1_SAVE_PATH))
		if typeof(v1) == TYPE_DICTIONARY and v1.get("version") == 1:
			save = migrate_v1(v1)
	inventory.from_array(save.get("inventory", []))
	_ensure_daily()
	_clamp_vitals()

## 载入后把血蓝夹回当前上限（职业特质调整或旧存档可能残留超上限值）。
func _clamp_vitals() -> void:
	var st := total_stats()
	save.hp = clampi(int(save.hp), 0, int(st.hp_max))
	save.mp = clampf(float(save.mp), 0.0, float(st.mp_max))

func _try_backup_or_v1(_corrupt: bool) -> void:
	if FileAccess.file_exists(SAVE_BACKUP_PATH):
		var backup = JSON.parse_string(FileAccess.get_file_as_string(SAVE_BACKUP_PATH))
		if valid_save(backup):
			save = backup
			storage_notice = "已从本地备份恢复旅途记录。"
			return
	if FileAccess.file_exists(V1_SAVE_PATH):
		var v1 = JSON.parse_string(FileAccess.get_file_as_string(V1_SAVE_PATH))
		if typeof(v1) == TYPE_DICTIONARY and v1.get("version") == 1:
			save = migrate_v1(v1)
			storage_notice = "已从旧版存档迁移进度。"
			return
	storage_available = false
	storage_notice = "本地存档不可读。本次以临时进度游玩，原存档保留。"

func persist() -> void:
	if not storage_available: return
	save.inventory = inventory.to_array()
	if FileAccess.file_exists(SAVE_PATH):
		var old_raw := FileAccess.get_file_as_string(SAVE_PATH)
		var old = JSON.parse_string(old_raw)
		if valid_save(old):
			var bf := FileAccess.open(SAVE_BACKUP_PATH, FileAccess.WRITE)
			if bf: bf.store_string(old_raw); bf.close()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save))
		f.close()
	else:
		storage_available = false

# --- 昼夜（10 分钟循环） ---
var _elapsed_days := 0
var _prev_day_time := 8.0

func _process(delta: float) -> void:
	if not day_paused:
		day_time = fmod(day_time + delta * day_speed, 24.0)
		day_time_changed.emit(day_time)
		if day_time < _prev_day_time:  # 跨日：刷新日常
			_elapsed_days += 1
			_ensure_daily()
			quests_changed.emit()
		_prev_day_time = day_time

## 已过的完整天数（日常任务刷新索引）。
func day_index() -> int:
	return _elapsed_days

func set_day_paused(v: bool) -> void:
	day_paused = v
	day_paused_changed.emit(v)

func day_factor() -> float:
	var sun_angle := ((day_time - 6.0) / 24.0) * TAU
	return clamp(sin(sun_angle), 0.0, 1.0)

func night_factor() -> float:
	var sun_angle := ((day_time - 6.0) / 24.0) * TAU
	return clamp(-sin(sun_angle), 0.0, 1.0)

func horizon_factor() -> float:
	var sun_angle := ((day_time - 6.0) / 24.0) * TAU
	return 1.0 - abs(sin(sun_angle))

func clock_text() -> String:
	var h := int(floor(day_time))
	var m := int(floor(fmod(day_time, 1.0) * 60.0))
	return "%02d:%02d" % [h, m]

func clock_icon() -> String:
	if day_factor() > 0.6: return "☀"
	if horizon_factor() > 0.3: return "◐"
	return "☾"

func day_phase_text() -> String:
	var h := day_time
	if h < 5: return "深夜"
	if h < 7: return "黎明"
	if h < 11: return "清晨"
	if h < 14: return "正午"
	if h < 17: return "午后"
	if h < 19: return "黄昏"
	if h < 21: return "暮色"
	return "夜晚"

# --- 汇总属性：职业被动 + 加点 + 装备 + 局内增益 ---
## 返回 {hp_max, mp_max, atk, armor, crit, speed, mp_regen, skill_amp, gold_find, luck, thorns, knockback_res}
func total_stats() -> Dictionary:
	var cd: Dictionary = class_data()
	var st := {"hp_max": 100, "mp_max": 50, "atk": 6, "armor": 0, "crit": 0.05, "speed": 1.0,
		"mp_regen": cd.get("mp_regen", 2.0), "skill_amp": 0.0, "gold_find": 0.0, "luck": 0.0,
		"thorns": 0.0, "knockback_res": 0.0, "execute": 0.0, "leech": 0.0}
	# 武器。
	if save.weapon != null:
		st.atk += Items.weapon_atk(save.weapon)
		st.gold_find += 0.15 * int(save.weapon.affixes.has("greed"))
	# 装备四槽。
	for slot in Items.SLOTS:
		var gear = save.equipment.get(slot)
		if gear != null:
			for k in Items.gear_bonus(gear):
				st[k] = st.get(k, 0.0) + Items.gear_bonus(gear)[k]
	# 被动。
	for k in SkillBook.passive_stats(save.selected):
		st[k] = st.get(k, 0.0) + SkillBook.passive_stats(save.selected)[k]
	for k in SkillBook.passive_hooks(save.selected):
		if k == "on_kill_heal": st["on_kill_heal"] = st.get("on_kill_heal", 0.0) + SkillBook.passive_hooks(save.selected)[k]
	# 加点。
	var gb := Growth.bonuses(save.points)
	for k in gb:
		if st.has(k): st[k] = st[k] + gb[k]
	# 同伴光环（参考 Diablo III 追随者：每名在队同伴提供一条常驻加成）。
	for a in party_auras():
		var ak := String(a.get("stat", ""))
		if ak != "" and st.has(ak):
			st[ak] = st[ak] + a.get("value", 0)
	# 局内增益。
	for b in save.get("run_buffs", []):
		for k in b.get("stats", {}):
			st[k] = st.get(k, 0.0) + b.stats[k]
	return st

# --- 存档变更 ---
func set_selected(id: String) -> void:
	save.selected = id
	# 开局/切职业：无武器时发放该职业的新手武器，并把血蓝重置为满（避免带伤开局）。
	if save.weapon == null:
		save.weapon = Items.starter_weapon(id)
	var st := total_stats()
	save.hp = int(st.hp_max)
	save.mp = float(st.mp_max)
	persist()
	class_changed.emit(id)

func add_gold(v: int) -> void:
	save.gold = clampi(int(save.gold) + v, 0, 999999)
	persist()
	gold_changed.emit(save.gold)

## 消费金币（推进日常任务 spend）。
func spend_gold(v: int) -> bool:
	if int(save.gold) < v: return false
	add_gold(-v)
	bump_quest("spend", "", v)
	return true

func add_diamonds(v: int) -> void:
	save.diamonds = clampi(int(save.diamonds) + v, 0, 9999)
	persist()
	diamonds_changed.emit(save.diamonds)

func set_hp(v: int) -> void:
	save.hp = clampi(v, 0, int(total_stats().hp_max))
	persist()
	hp_changed.emit(save.hp)

func add_mp(v: float) -> void:
	save.mp = clampf(float(save.mp) + v, 0.0, float(total_stats().mp_max))
	mp_changed.emit(save.mp)

func use_mp(cost: float) -> bool:
	if float(save.mp) < cost: return false
	add_mp(-cost)
	return true

func add_potion(v: int) -> void:
	save.potions = clampi(int(save.potions) + v, 0, 999)
	persist()
	potions_changed.emit(save.potions)

func set_quest(v: String) -> void:
	save.quest = v
	persist()
	quest_changed.emit()

func add_ember(id: String) -> void:
	if save.embers.has(id): return
	save.embers.append(id)
	persist()
	embers_changed.emit()

## 把职业的防御参数应用到玩家实体（大盾守卫窗口更宽、减伤更强）。
func apply_class_guard(a: Actor) -> void:
	if a == null: return
	var gd: Dictionary = class_data().get("guard", {})
	a.guard_window = float(gd.get("window", 0.35))
	a.guard_reduction = float(gd.get("reduction", 0.35))

func class_data() -> Dictionary:
	return CLASS_DATA[save.selected]

func is_archer() -> bool:
	return save.selected == "archer"

# --- XP / 等级 / 加点 ---
func add_xp(v: int) -> void:
	save.xp = int(save.xp) + v
	var leveled := false
	while int(save.xp) >= xp_needed(int(save.char_level)) and int(save.char_level) < 30:
		save.xp -= xp_needed(int(save.char_level))
		save.char_level = int(save.char_level) + 1
		save.point_pool = int(save.point_pool) + 1
		leveled = true
	if leveled:
		toast_requested.emit("角色升级！Lv%d · 获得 1 点属性点（K 打开加点）" % int(save.char_level))
		set_hp(int(total_stats().hp_max))
		check_achievements()
	persist()
	xp_changed.emit(int(save.char_level), int(save.xp), xp_needed(int(save.char_level)))

## 加点入口（Growth 校验互斥/上限）。返回错误信息或 ""。
func allocate_point(branch: String) -> String:
	if int(save.point_pool) <= 0: return "没有可用的属性点"
	var err := Growth.allocate(save.points, branch)
	if err == "":
		save.point_pool = int(save.point_pool) - 1
		check_achievements()
		persist()
	return err

func respec() -> bool:
	var cost := Growth.respec_cost(save.points)
	if not spend_gold(cost): return false
	var refund := cost / 20  # 洗点返还已投入的点数
	for b in save.points: save.points[b] = 0
	save.point_pool = int(save.point_pool) + refund
	persist()
	return true

# --- 背包 / 装备 / 武器 ---
## 拾取物品（背包满时返回 false）。
func pickup_item(inst: Dictionary) -> bool:
	var ok := inventory.add(inst)
	if ok:
		persist()
		if inst.kind != "consumable" and inst.rarity == 4:
			award_achievement("ach_legend")
	return ok

func equip_slot(slot_index: int) -> void:
	var inst = inventory.slots[slot_index]
	if inst == null: return
	if inst.kind == "weapon":
		inventory.slots[slot_index] = save.weapon
		save.weapon = inst
	elif inst.kind == "gear":
		var slot: String = inst.slot
		var old = save.equipment.get(slot)
		inventory.slots[slot_index] = old
		save.equipment[slot] = inst
	else:
		return
	inventory.changed.emit()
	equipment_changed.emit()
	persist()

func unequip_slot(slot: String) -> void:
	var inst = save.equipment.get(slot)
	if inst == null: return
	save.equipment[slot] = null
	if not inventory.add(inst):
		save.equipment[slot] = inst  # 背包满则放回
		return
	equipment_changed.emit()
	persist()

## 武器强化：金币 + 深渊碎片。
func upgrade_weapon() -> bool:
	var w = save.weapon
	if w == null: return false
	var cost := Items.upgrade_cost(int(w.level))
	if int(save.gold) < cost.gold or inventory.count_of("shard") < cost.shard:
		toast_requested.emit("强化需要 %d 金币与 %d 枚深渊碎片" % [cost.gold, cost.shard])
		return false
	spend_gold(cost.gold)
	inventory.remove("shard", cost.shard)
	save.weapon.level = int(save.weapon.level) + 1
	persist()
	equipment_changed.emit()
	return true

# --- 任务 ---
## 确保当日日常存在（跨日自动刷新）。
func _ensure_daily() -> void:
	var q: Dictionary = save.quests
	if int(q.get("daily_day", -1)) != day_index() or q.daily.size() == 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var rolled := QuestBook.roll_daily(rng)
		var list := []
		for d in rolled:
			list.append({"id": d.id, "progress": 0, "done": false, "claimed": false})
		q.daily = list
		q.daily_day = day_index()

## 用一个稳定递增的天数索引（见 day_index）。

## 统一任务进度推进。kind/objective 匹配 QuestBook 定义。
func bump_quest(kind: String, target: String, n: int = 1) -> void:
	var any := false
	# 支线。
	for qid in save.quests.side:
		var q: Dictionary = save.quests.side[qid]
		if q.done: continue
		var def := _side_def(qid)
		if def.is_empty(): continue
		if _obj_match(def.objective, kind, target):
			q.progress = mini(int(q.progress) + n, int(def.objective.count))
			if int(q.progress) >= int(def.objective.count):
				q.done = true
				toast_requested.emit("任务完成：%s（到冒险者协会领取奖励）" % def.name)
			any = true
	# 日常。
	for q in save.quests.daily:
		if q.done: continue
		var def := _daily_def(q.id)
		if def.is_empty(): continue
		if _obj_match(def.objective, kind, target):
			q.progress = mini(int(q.progress) + n, int(def.objective.count))
			if int(q.progress) >= int(def.objective.count):
				q.done = true
				save.daily_done = int(save.daily_done) + 1
				toast_requested.emit("日常完成：%s（任务日志领取奖励）" % def.name)
				check_achievements()
			any = true
	if any:
		persist()
		quests_changed.emit()

func _obj_match(obj: Dictionary, kind: String, target: String) -> bool:
	if obj.kind != kind: return false
	if obj.get("target", "") != "" and target != "" and obj.target != target: return false
	return true

# --- 任务追踪（HUD 追踪条与任务日志共用） ---
## 设置当前追踪的任务（kind: side/daily；qid 为空即取消追踪）。
func set_tracked(kind: String, qid: String) -> void:
	if qid == "":
		save["tracked_quest"] = ""
	else:
		save["tracked_quest"] = "%s:%s" % [kind, qid]
	persist()
	quests_changed.emit()

func tracked_key() -> String:
	return String(save.get("tracked_quest", ""))

## 当前该显示在 HUD 上的任务：优先已追踪 → 可领赏 → 进行中的支线 → 进行中的日常。
func tracked_info() -> Dictionary:
	var info := quest_info_by_key(tracked_key())
	if not info.is_empty():
		return info
	for qid in save.quests.side:
		var i: Dictionary = quest_info("side", qid)
		if i.is_empty(): continue
		if bool(i.claimable): return i
	for d in save.quests.daily:
		var i2: Dictionary = quest_info("daily", String(d.id))
		if i2.is_empty(): continue
		if bool(i2.claimable): return i2
	for qid2 in save.quests.side:
		var i3: Dictionary = quest_info("side", qid2)
		if not i3.is_empty() and not bool(i3.done): return i3
	for d2 in save.quests.daily:
		var i4: Dictionary = quest_info("daily", String(d2.id))
		if not i4.is_empty() and not bool(i4.done): return i4
	return {}

func quest_info_by_key(key: String) -> Dictionary:
	if key == "": return {}
	var parts := key.split(":")
	if parts.size() != 2: return {}
	return quest_info(parts[0], parts[1])

## 单个任务的统一展示数据（HUD 追踪条 / 任务日志共用同一份口径）。
func quest_info(kind: String, qid: String) -> Dictionary:
	var st = null
	var def := {}
	if kind == "side":
		if not save.quests.side.has(qid): return {}
		st = save.quests.side[qid]
		def = _side_def(qid)
	else:
		for d in save.quests.daily:
			if String(d.id) == qid: st = d; break
		def = _daily_def(qid)
	if st == null or def.is_empty(): return {}
	var obj: Dictionary = def.get("objective", {})
	var count := int(obj.get("count", 0))
	var prog := int(st.get("progress", 0))
	var done := bool(st.get("done", false))
	var claimed := bool(st.get("claimed", false))
	return {
		"kind": kind, "id": qid,
		"name": String(def.get("name", qid)),
		"desc": String(def.get("desc", "")),
		"giver": String(def.get("giver", "")),
		"progress": prog, "count": count,
		"ratio": clampf(float(prog) / maxf(float(count), 1.0), 0.0, 1.0),
		"done": done, "claimed": claimed,
		"claimable": done and not claimed,
		"tracked": tracked_key() == "%s:%s" % [kind, qid],
		"reward": reward_text(def.get("reward", {})),
	}

## 奖励的可读文本（任务日志与追踪条共用）。
func reward_text(rw: Dictionary) -> String:
	var parts := []
	if rw.has("gold"): parts.append("%d 金币" % int(rw.gold))
	if rw.has("xp"): parts.append("%d 经验" % int(rw.xp))
	if rw.has("diamonds"): parts.append("%d 钻石" % int(rw.diamonds))
	if rw.has("item"): parts.append(Items.stack_item(String(rw.item)).name)
	return " · ".join(parts)

func _side_def(qid: String) -> Dictionary:
	for d in QuestBook.SIDE_QUESTS:
		if d.id == qid: return d
	return {}

func _daily_def(qid: String) -> Dictionary:
	for d in QuestBook.DAILY_POOL:
		if d.id == qid: return d
	return {}

## 接取支线。
func accept_side_quest(qid: String) -> bool:
	if save.quests.side.has(qid): return false
	save.quests.side[qid] = {"progress": 0, "done": false, "claimed": false}
	persist()
	quests_changed.emit()
	return true

## 领取任务奖励。type: "side"/"daily"。
func claim_quest(type: String, qid: String) -> bool:
	var q = null
	var def := {}
	if type == "side":
		if not save.quests.side.has(qid): return false
		q = save.quests.side[qid]
		def = _side_def(qid)
	else:
		q = null
		for d in save.quests.daily:
			if d.id == qid: q = d; break
		def = _daily_def(qid)
	if q == null or def.is_empty(): return false
	if not bool(q.done) or bool(q.claimed): return false
	var rw: Dictionary = def.reward
	if rw.has("gold"): add_gold(int(rw.gold))
	if rw.has("diamonds"): add_diamonds(int(rw.diamonds))
	if rw.has("xp"): add_xp(int(rw.xp))
	if rw.has("item"): pickup_item(Items.stack_item(rw.item))
	q.claimed = true
	if type == "daily":
		save.daily_done = int(save.daily_done)
	persist()
	quests_changed.emit()
	return true

# --- 宠物 ---
## 捕获宠物（species 为 Bestiary.ANIMALS 键）。
func capture_pet(species: String) -> bool:
	if save.pets.size() >= 6:
		toast_requested.emit("宠物栏已满（6 只）")
		return false
	var def: Dictionary = Bestiary.ANIMALS[species]
	var names := ["团子", "豆豆", "煤球", "雪球", "花椒", "阿呜", "布丁", "毛球"]
	var rng := RandomNumberGenerator.new(); rng.randomize()
	save.pets.append({"id": species, "name": names[rng.randi() % names.size()], "level": 1, "xp": 0})
	if save.active_pet < 0: save.active_pet = save.pets.size() - 1
	persist()
	pets_changed.emit()
	toast_requested.emit("驯服成功！%s 加入了你的旅程" % def.name)
	check_achievements()
	return true

static func pet_xp_needed(level: int) -> int:
	return 50 * level

func add_pet_xp(v: int) -> void:
	if save.active_pet < 0 or save.pets.size() == 0: return
	var pet: Dictionary = save.pets[save.active_pet]
	pet.xp = int(pet.xp) + v
	while int(pet.xp) >= pet_xp_needed(int(pet.level)) and int(pet.level) < 10:
		pet.xp -= pet_xp_needed(int(pet.level))
		pet.level = int(pet.level) + 1
		toast_requested.emit("宠物 %s 升到了 Lv%d！" % [pet.name, int(pet.level)])
	persist()
	pets_changed.emit()

## 宠物战斗属性。
func pet_stats() -> Dictionary:
	if save.active_pet < 0 or save.pets.size() == 0: return {}
	var pet: Dictionary = save.pets[save.active_pet]
	var def: Dictionary = Bestiary.ANIMALS[pet.id]
	var lv := int(pet.level)
	return {"dmg": int(round(def.pet_dmg * (1.0 + 0.2 * (lv - 1)))), "hp_max": int(round(def.pet_hp * (1.0 + 0.25 * (lv - 1)))), "name": pet.name, "level": lv}

## 当前出战宠物是否有效。
func active_pet_valid() -> bool:
	return save.pets.size() > 0 and int(save.active_pet) >= 0 and int(save.active_pet) < save.pets.size()

## 出战宠物物种（Bestiary.ANIMALS 键）。
func pet_species() -> String:
	if not active_pet_valid(): return "rabbit"
	return str(save.pets[int(save.active_pet)].get("id", "rabbit"))

## 出战宠物等级。
func pet_level() -> int:
	if not active_pet_valid(): return 1
	return int(save.pets[int(save.active_pet)].get("level", 1))

## 切换出战宠物（宠物栏索引，-1 收回）。
func set_active_pet(idx: int) -> void:
	if idx >= -1 and idx < save.pets.size():
		save.active_pet = idx
		persist()
		pets_changed.emit()

# --- 好感度 / 队伍 ---
func add_affinity(npc_id: String, v: int) -> void:
	save.affinity[npc_id] = clampi(int(save.affinity.get(npc_id, 0)) + v, 0, 100)
	persist()

func affinity_of(npc_id: String) -> int:
	return int(save.affinity.get(npc_id, 0))

## 招募入队（好感度 ≥ 60）。最多 3 名 NPC 同行。
func recruit(npc_id: String) -> bool:
	if affinity_of(npc_id) < 60:
		return false
	if save.party.size() >= 3:
		toast_requested.emit("队伍已满（最多 3 名同伴）")
		return false
	if save.party.has(npc_id): return false
	save.party.append(npc_id)
	persist()
	party_changed.emit()
	check_achievements()
	return true

func dismiss(npc_id: String) -> void:
	save.party.erase(npc_id)
	persist()
	party_changed.emit()

# --- 组队指挥：阵型 / 行为档 / 快捷指令 ---
var party_hold := false              # 待命（原地不动，玩家显式下达）
var party_focus_until := 0.0         # 集火到期时间（秒）

## 当前阵型（存档持久化）。
func party_formation() -> String:
	var f := String(save.get("party_formation", "follow"))
	return f if NpcBook.FORMATIONS.has(f) else "follow"

## 循环切换阵型，返回新阵型（X 键）。
func cycle_formation() -> String:
	var i := NpcBook.FORMATION_ORDER.find(party_formation())
	var nxt: String = NpcBook.FORMATION_ORDER[(i + 1) % NpcBook.FORMATION_ORDER.size()]
	set_formation(nxt)
	return nxt

func set_formation(f: String) -> void:
	if not NpcBook.FORMATIONS.has(f): return
	save["party_formation"] = f
	persist()
	party_changed.emit()

## 某同伴的行为档位（默认「均衡」）。
func stance_of(npc_id: String) -> String:
	var st: Dictionary = save.get("party_stance", {})
	var s := String(st.get(npc_id, "normal"))
	return s if NpcBook.STANCES.has(s) else "normal"

func set_stance(npc_id: String, stance: String) -> void:
	if not NpcBook.STANCES.has(stance): return
	if not save.has("party_stance"): save["party_stance"] = {}
	save["party_stance"][npc_id] = stance
	persist()
	party_changed.emit()

## 集火：5 秒内所有同伴强制攻击玩家当前目标（覆盖各自档位）。
func order_focus() -> void:
	party_focus_until = Time.get_ticks_msec() / 1000.0 + 5.0
	party_hold = false

func order_focus_active() -> bool:
	return Time.get_ticks_msec() / 1000.0 < party_focus_until

## 待命/跟随 切换，返回切换后的待命状态。
func order_hold_toggle() -> bool:
	party_hold = not party_hold
	return party_hold

## 在队同伴的光环加成列表。
func party_auras() -> Array:
	var out: Array = []
	for npc_id in save.get("party", []):
		var def: Dictionary = NpcBook.NPCS.get(String(npc_id), {})
		if def.has("aura"): out.append(def.aura)
	return out

# --- 成就（钻石来源） ---
func award_achievement(id: String) -> void:
	if save.ach.has(id): return
	for a in QuestBook.ACHIEVEMENTS:
		if a.id == id:
			save.ach[id] = true
			add_diamonds(int(a.diamonds))
			toast_requested.emit("成就达成「%s」：钻石 ×%d" % [a.name, int(a.diamonds)])
			persist()
			return

## 全量检查（在击杀/升级/捕获/招募等事件后调用）。
func check_achievements() -> void:
	if int(save.kills) >= 50: award_achievement("ach_kill50")
	if int(save.kills) >= 200: award_achievement("ach_kill200")
	if int(save.char_level) >= 5: award_achievement("ach_level5")
	if int(save.char_level) >= 10: award_achievement("ach_level10")
	if save.pets.size() > 0: award_achievement("ach_pet1")
	if save.party.size() > 0: award_achievement("ach_party")
	if int(save.daily_done) >= 3: award_achievement("ach_daily3")
	for b in save.points:
		if int(save.points[b]) >= Growth.MAX_LEVEL: award_achievement("ach_build")

# --- 局内增益（肉鸽祝福） ---
func add_run_buff(id: String, name: String, stats: Dictionary) -> void:
	for b in save.run_buffs:
		if b.id == id:
			return
	save.run_buffs.append({"id": id, "name": name, "stats": stats})
	persist()

func clear_run_buffs() -> void:
	save.run_buffs = []
	persist()

# --- 击杀统计 ---
func add_kill() -> void:
	save.kills = int(save.kills) + 1
	check_achievements()

## 每帧法力回复（Main 调用）。
func regen_mp(delta: float) -> void:
	if save.mp < float(total_stats().mp_max):
		add_mp(float(total_stats().mp_regen) * delta)
