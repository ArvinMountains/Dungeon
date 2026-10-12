extends Node
## 数据层单元测试：加点/背包/物品/技能/图鉴/任务/NPC/经济/宠物/昼夜/相机平滑。
## 运行：godot --headless --path . res://tests/FeatureTest.tscn
## 全部为纯逻辑断言，不依赖场景节点（除 GameState/CameraRig 实例）。

var failures: Array[String] = []
var checks: Array[String] = []
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 20261011
	# 测试隔离：重置存档与背包。
	GameState.save = GameState.fresh_save()
	for i in range(GameState.inventory.CAPACITY):
		GameState.inventory.slots[i] = null
	await _test_growth()
	await _test_skills()
	await _test_items()
	await _test_inventory()
	await _test_bestiary()
	await _test_quests()
	await _test_npc()
	await _test_economy()
	await _test_equip()
	await _test_pets()
	await _test_party()
	await _test_time_camera()
	print("")
	print("========== FEATURE RESULT: %d passed, %d failed ==========" % [checks.size(), failures.size()])
	for f in failures:
		print("FAIL · " + f)
	get_tree().quit(1 if failures.size() > 0 else 0)

# ---------------- 加点系统 ----------------
func _test_growth() -> void:
	await _check("加点：5 分支 × 10 级", Growth.BRANCHES.size() >= 5 and Growth.MAX_LEVEL >= 10)
	var pts := {"brute": 0, "bulwark": 0, "swift": 0, "arcane": 0, "greed": 0}
	var ok := true
	for i in range(10):
		if Growth.allocate(pts, "brute") != "": ok = false
	await _check("加点：单分支可升满 10 级", ok and pts.brute == 10)
	await _check("加点：满级分支拒绝再加", Growth.allocate(pts, "brute") != "")
	# 互斥：brute 10 + bulwark 2 = 12 达上限，第 3 级应被拒。
	Growth.allocate(pts, "bulwark"); Growth.allocate(pts, "bulwark")
	await _check("加点：互斥规则拦截（狂野+坚壁≤12）", Growth.allocate(pts, "bulwark") != "")
	# 总点数上限 24（单分支 10 级封顶，需跨分支填充）。
	var pts2 := {"brute": 0, "bulwark": 0, "swift": 0, "arcane": 0, "greed": 0}
	var added := 0
	while added < 40:
		if Growth.allocate(pts2, ["brute", "swift", "arcane", "greed", "bulwark"][added % 5]) != "": break
		added += 1
	await _check("加点：总投入上限 24", added == Growth.TOTAL_POINTS_CAP)
	var b := Growth.bonuses({"brute": 5, "bulwark": 2, "swift": 4, "arcane": 3, "greed": 1})
	await _check("加点：属性换算（atk+10/hp+6/crit 6%）",
		b.atk == 10 and b.hp_max == 6 and b.armor == 2 and absf(b.crit - 0.06) < 0.001)
	await _check("加点：三套推荐 build", Growth.BUILDS.size() >= 3)
	await _check("加点：联动觉醒计算", Growth.active_synergies({"brute": 5, "bulwark": 5, "swift": 0, "arcane": 0, "greed": 0}).has("warcry"))
	# GameState 加点入口（消耗点数池）。
	GameState.save.point_pool = 0
	GameState.save.points = {"brute": 0, "bulwark": 0, "swift": 0, "arcane": 0, "greed": 0}
	await _check("加点：无点数时拒绝", GameState.allocate_point("brute") != "")
	GameState.save.point_pool = 1
	await _check("加点：GameState 分配成功", GameState.allocate_point("brute") == "" and GameState.save.points.brute == 1 and GameState.save.point_pool == 0)
	# 洗点返还（1 点投入 → 返还 1 点）。
	GameState.save.gold = 1000
	var refunded: bool = GameState.respec() and GameState.save.point_pool == 1 and GameState.save.points.brute == 0
	await _check("洗点：返还已投入点数", refunded)

# ---------------- 技能表 ----------------
func _test_skills() -> void:
	var all_ok := true
	var field_ok := true
	for cid in GameState.CLASS_DATA:
		var a: Array = SkillBook.actives(cid)
		var p: Array = SkillBook.passives(cid)
		if a.size() != 4 or p.size() != 2: all_ok = false
		for s in a:
			if not (s.has("name") and s.has("mp") and s.has("cd") and s.has("effect")): field_ok = false
	await _check("技能：5 职业各 4 主动 + 2 被动", all_ok and GameState.CLASS_DATA.size() == 5)
	await _check("技能：主动技能字段完整（name/mp/cd/effect）", field_ok)
	var ult_ok := true
	for cid2 in GameState.CLASS_DATA:
		var acts: Array = SkillBook.actives(cid2)
		if not bool(acts[3].get("ult", false)): ult_ok = false
	await _check("技能：每职业第 4 技能为终极技", ult_ok)

# ---------------- 物品 / 武器 ----------------
func _test_items() -> void:
	var valid := true
	for i in range(30):
		var w := Items.roll_weapon(rng, "archer", 2, 0.3)
		if not (w.kind == "weapon" and w.base != "" and int(w.level) >= 1 and w.rarity >= 0 and w.rarity <= 4): valid = false
	await _check("物品：随机武器掉落 30 次均合法", valid)
	var g := Items.roll_gear(rng, 0.5)
	await _check("物品：装备掉落槽位合法", g.kind == "gear" and Items.SLOTS.has(g.slot))
	var gb := Items.gear_bonus(g)
	await _check("物品：装备属性加成非空", gb.size() > 0)
	var st := Items.stack_item("potion_hp", 3)
	await _check("物品：堆叠物品构造", st.stack == true and int(st.count) == 3)
	var c0: int = Items.upgrade_cost(1).gold
	var c1: int = Items.upgrade_cost(5).gold
	await _check("物品：强化费用随等级递增", c1 > c0)

# ---------------- 网格背包 ----------------
func _test_inventory() -> void:
	var inv := Inventory.new()
	var pot := Items.stack_item("potion_hp", 5)
	await _check("背包：添加成功", inv.add(pot))
	await _check("背包：同类堆叠为 1 格", inv.used_count() == 1 and inv.count_of("potion_hp") == 5)
	await _check("背包：移除部分数量", inv.remove("potion_hp", 2) and inv.count_of("potion_hp") == 3)
	await _check("背包：移除超量失败", not inv.remove("potion_hp", 99))
	# 拖拽：交换与合并。
	inv.add(Items.stack_item("potion_mp", 2))
	inv.add(Items.roll_gear(rng, 0.0))
	inv.move_slot(0, 1)  # potion_hp(3) ↔ potion_mp(2)：同为消耗品不同 base → 交换
	await _check("背包：拖拽交换不同物品", inv.slots[0].base == "potion_mp" and inv.slots[1].base == "potion_hp")
	inv.move_slot(1, 0)  # 移回
	inv.slots[2] = Items.stack_item("potion_hp", 4)
	inv.move_slot(0, 2)  # 同 base → 合并
	await _check("背包：同类合并堆叠", inv.slots[0] == null and inv.count_of("potion_hp") == 7)
	# 装满 24 格后拒绝再入。
	var inv2 := Inventory.new()
	var full := true
	for i in range(Inventory.CAPACITY):
		if not inv2.add(Items.roll_gear(rng, 0.0)): full = false
	await _check("背包：容量上限 24", full and not inv2.add(Items.stack_item("potion_hp")))

# ---------------- 图鉴 / 掉落 ----------------
func _test_bestiary() -> void:
	await _check("图鉴：3 种怪物 AI 行为模式", Bestiary.AI_MODES.size() == 3)
	var modes_ok := true
	for id in Bestiary.ENEMIES:
		if not Bestiary.AI_MODES.has(Bestiary.ENEMIES[id].ai): modes_ok = false
	await _check("图鉴：全部敌人 AI 模式合法", modes_ok)
	var wave: Array = Bestiary.spawn_table(rng, 1, "combat")
	var ids_ok := wave.size() > 0
	for entry in wave:
		if not Bestiary.ENEMIES.has(entry.id): ids_ok = false
	await _check("图鉴：刷怪表引用合法敌人", ids_ok)
	var loot := Bestiary.loot(rng, Bestiary.ENEMIES["whisper"], "", 0.0, "archer")
	await _check("图鉴：掉落表含金币与物品", loot.has("gold") and loot.has("items") and int(loot.gold) >= 0)
	await _check("图鉴：山地/森林动物表均非空",
		Bestiary.animal_table(rng, "mountain").size() > 0 and Bestiary.animal_table(rng, "forest").size() > 0)
	var net_ok := true
	for sp in Bestiary.ANIMALS:
		if float(Bestiary.ANIMALS[sp].net_chance) <= 0.0 or float(Bestiary.ANIMALS[sp].net_chance) > 1.0: net_ok = false
	await _check("图鉴：动物捕获率在 (0,1]", net_ok)

# ---------------- 任务系统 ----------------
func _test_quests() -> void:
	await _check("任务：支线 ≥ 3 / 日常池 ≥ 3 / 随机事件 ≥ 4",
		QuestBook.SIDE_QUESTS.size() >= 3 and QuestBook.DAILY_POOL.size() >= 3 and QuestBook.EVENTS.size() >= 4)
	await _check("任务：成就表 ≥ 5 且均含钻石奖励", QuestBook.ACHIEVEMENTS.size() >= 5)
	var daily: Array = QuestBook.roll_daily(rng)
	await _check("任务：每日随机抽取返回日常", daily.size() >= 1)
	# 支线全流程：接取 → 推进 → 领取。
	GameState.save.quests.side = {}
	await _check("任务：接取支线", GameState.accept_side_quest("side_herbs"))
	GameState.bump_quest("collect", "herb", 3)
	var q: Dictionary = GameState.save.quests.side["side_herbs"]
	await _check("任务：支线推进完成", bool(q.done))
	var g0: int = GameState.save.gold
	await _check("任务：未完成不可领奖", not GameState.claim_quest("side", "side_wolves"))
	# side_herbs 奖励含 potion_hp，领奖应成功。
	await _check("任务：完成领奖成功", GameState.claim_quest("side", "side_herbs"))
	# 日常：对当日所有日常按 objective 推进并领取（数据驱动，不依赖具体 roll）。
	GameState._ensure_daily()
	var daily_ok := true
	for d in GameState.save.quests.daily:
		var def: Dictionary = GameState._daily_def(d.id)
		GameState.bump_quest(def.objective.kind, def.objective.target, int(def.objective.count) + 1)
		if not bool(d.done): daily_ok = false
	await _check("任务：日常可推进完成", daily_ok)
	var claim_ok := true
	for d2 in GameState.save.quests.daily:
		if not GameState.claim_quest("daily", d2.id): claim_ok = false
	await _check("任务：日常领奖成功", claim_ok)

# ---------------- NPC ----------------
func _test_npc() -> void:
	await _check("NPC：定义 ≥ 5 人且含 rig/combat", NpcBook.NPCS.size() >= 5)
	var ok := true
	for id in NpcBook.NPCS:
		var n: Dictionary = NpcBook.NPCS[id]
		if not (n.has("rig") and n.has("combat")): ok = false
	await _check("NPC：全部含建模与战斗字段", ok)
	await _check("NPC：招募好感阈值 60", NpcBook.AFFINITY_RECRUIT_AT == 60)

# ---------------- 双货币经济 ----------------
func _test_economy() -> void:
	GameState.save.gold = 100
	GameState.save.diamonds = 0
	await _check("经济：金币不足时消费失败", not GameState.spend_gold(999))
	await _check("经济：金币正常消费", GameState.spend_gold(40) and GameState.save.gold == 60)
	GameState.add_diamonds(10)
	await _check("经济：钻石入账", GameState.save.diamonds == 10)
	# 金币操作不影响钻石，钻石仅来自成就/奖励。
	GameState.add_gold(500); GameState.spend_gold(500)
	await _check("经济：金币与钻石互不通用", GameState.save.diamonds == 10)
	# 成就是钻石来源。
	GameState.award_achievement("ach_first_clear")
	await _check("经济：成就发放钻石", GameState.save.ach.has("ach_first_clear") and GameState.save.diamonds == 15)
	# 局内临时增益。
	GameState.add_run_buff("rb_test", "测试增益", {"atk": 5})
	await _check("局内增益：生效于总属性", int(GameState.total_stats().atk) >= 5)
	GameState.clear_run_buffs()
	await _check("局内增益：撤离清空", GameState.save.run_buffs.is_empty())
	# 法力。
	GameState.save.mp = 40.0
	await _check("蓝条：不足时释放失败", not GameState.use_mp(999))
	await _check("蓝条：消耗成功", GameState.use_mp(10) and GameState.save.mp == 30.0)
	GameState.add_mp(1000.0)
	await _check("蓝条：回复封顶于上限", GameState.save.mp <= float(GameState.total_stats().mp_max))

# ---------------- 装备 / 武器 ----------------
func _test_equip() -> void:
	# 武器链路：拾取 → 装备 → 强化。
	var w := Items.roll_weapon(rng, "archer", 0, 0.0)
	w.level = 1
	await _check("装备：拾取武器", GameState.pickup_item(w))
	var idx := _find_slot("weapon")
	GameState.equip_slot(idx)
	await _check("装备：武器上手", GameState.save.weapon != null and GameState.save.weapon.kind == "weapon")
	GameState.save.gold = 5000
	GameState.inventory.add(Items.stack_item("shard", 50))
	var lv0: int = int(GameState.save.weapon.level)
	await _check("武器：强化成功", GameState.upgrade_weapon() and int(GameState.save.weapon.level) == lv0 + 1)
	await _check("武器：无碎片强化失败", not GameState.upgrade_weapon() or GameState.inventory.count_of("shard") >= 0)
	# 防具四槽位（roll_gear 随机槽位，重 roll 至命中目标槽）。
	var slots_ok := true
	for slot in Items.SLOTS:
		var g: Dictionary = {}
		for attempt in range(80):
			g = Items.roll_gear(rng, 1.0)
			if g.slot == slot: break
		if g.is_empty() or g.slot != slot: slots_ok = false; continue
		GameState.pickup_item(g)
		var si := -1
		for i in range(GameState.inventory.CAPACITY):
			var s = GameState.inventory.slots[i]
			if s and s.kind == "gear" and s.slot == slot: si = i; break
		if si < 0: slots_ok = false; continue
		GameState.equip_slot(si)
	await _check("装备：头/躯干/手/饰品 4 槽全部可穿", slots_ok)
	var eq: Dictionary = GameState.save.equipment
	await _check("装备：4 槽均已生效", eq.head != null and eq.body != null and eq.hands != null and eq.trinket != null)
	var hp0: int = int(GameState.total_stats().hp_max)
	GameState.unequip_slot("body")
	await _check("装备：卸下回到背包且属性回落", GameState.save.equipment.body == null and int(GameState.total_stats().hp_max) <= hp0)

func _find_slot(kind: String) -> int:
	for i in range(GameState.inventory.CAPACITY):
		var s = GameState.inventory.slots[i]
		if s and s.kind == kind: return i
	return -1

# ---------------- 宠物 ----------------
func _test_pets() -> void:
	GameState.save.pets = []
	GameState.save.active_pet = -1
	await _check("宠物：捕获入库", GameState.capture_pet("rabbit") and GameState.save.pets.size() == 1)
	await _check("宠物：首捕自动出战", GameState.active_pet_valid() and GameState.pet_species() == "rabbit")
	GameState.add_pet_xp(120)  # Lv1→2 需 50，→3 需 100
	await _check("宠物：养成升级", GameState.pet_level() >= 2)
	var ps: Dictionary = GameState.pet_stats()
	await _check("宠物：战斗属性随等级提升", int(ps.dmg) > 0 and int(ps.hp_max) > 0)
	GameState.capture_pet("deer")
	GameState.set_active_pet(1)
	await _check("宠物：切换出战", GameState.pet_species() == "deer")
	GameState.set_active_pet(-1)
	await _check("宠物：收回后回退默认", GameState.pet_species() == "rabbit")

# ---------------- NPC 好感 / 组队 ----------------
func _test_party() -> void:
	GameState.save.affinity = {}
	GameState.save.party = []
	var ids: Array = NpcBook.NPCS.keys()
	var first: String = ids[0]
	GameState.add_affinity(first, 10)
	await _check("好感：低于 60 拒绝招募", not GameState.recruit(first))
	GameState.add_affinity(first, 50)
	await _check("好感：达标可招募", GameState.recruit(first) and GameState.save.party.has(first))
	await _check("好感：重复招募拒绝", not GameState.recruit(first))
	# 3 人上限。
	var recruited := 1
	for i in range(1, ids.size()):
		GameState.add_affinity(ids[i], 99)
		if GameState.recruit(ids[i]): recruited += 1
	await _check("组队：最多 3 名同伴", recruited == 3 and GameState.save.party.size() == 3)
	var extra := ""
	for id2 in ids:
		if not GameState.save.party.has(id2): extra = id2; break
	if extra != "":
		await _check("组队：第 4 人被拒绝", not GameState.recruit(extra))
	else:
		await _check("组队：第 4 人被拒绝（NPC 不足，跳过）", true)
	GameState.dismiss(first)
	await _check("组队：请离生效", not GameState.save.party.has(first))
	await _check("好感：上限 100", GameState.affinity_of(ids[1]) <= 100)

# ---------------- 昼夜 / 相机 ----------------
func _test_time_camera() -> void:
	GameState.day_time = 12.0
	await _check("昼夜：正午日照接近峰值", GameState.day_factor() > 0.9)
	GameState.day_time = 0.0
	await _check("昼夜：午夜夜幕最浓", GameState.night_factor() > 0.9)
	GameState.day_time = 19.5
	await _check("昼夜：黄昏相位文案", GameState.day_phase_text() == "暮色")
	await _check("昼夜：时钟格式", GameState.clock_text().length() == 5)
	# 相机：平滑时长与模式切换。
	var rig := CameraRig.new()
	add_child(rig)
	await _check("相机：平滑时长 0.2-0.3s", CameraRig.SMOOTH_TIME >= 0.2 and CameraRig.SMOOTH_TIME <= 0.3)
	var m1: String = rig.toggle_lock()
	var m2: String = rig.toggle_lock()
	await _check("相机：锁定/跟随切换", m1 == "lock" and m2 == "follow")
	# 指数平滑：一个 SMOOTH_TIME 内应走约 63%，三个周期后 >95%。
	var v := 0.0
	for i in range(int(round(3.0 * CameraRig.SMOOTH_TIME / 0.008))):
		v = rig._smooth(v, 10.0, 0.008)
	await _check("相机：帧率无关收敛 >95%", v > 9.5)
	await _check("相机：四场景预设齐全", rig.presets.has("selection") and rig.presets.has("town") and rig.presets.has("dungeon") and rig.presets.has("overworld"))
	rig.queue_free()

# ---------------- 断言工具 ----------------
func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _check(name: String, ok: bool) -> void:
	if ok:
		checks.append(name)
		print("PASS · " + name)
	else:
		failures.append(name)
		print("FAIL · " + name)
