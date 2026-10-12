extends Node
## 完整游玩模拟：以真实玩家的方式跑通一个完整游戏循环。
## 战士开局 → 主城首访（任务/购物/NPC）→ 第一层地下城全流程（战斗/事件/宝箱/Boss/祝福）
## → 回城消费（卖材料/强化/领奖/加点）→ 野外探索（动物/捕宠/火把/夜景）→ 第二层对比进度。
## 全程记录 [PLAY] 数据行：经济收支、战斗行为、蓝量饥饿、弹窗/toast 统计、FPS。
## 运行（非 headless）：godot --path . res://tests/PlaythroughTest.tscn

const OUT_DIR := "E:/个人文件/各类尝试/Dungeon Game/_explore"
const MODE_TOWN := 1
const MODE_DUNGEON := 2
const MODE_OVERWORLD := 3

var main = null
var tw = null
var dw = null
var ow = null

# 弹窗 / toast 拦截。
var pending_dialog: Dictionary = {}
var dialog_total := 0
var toast_total := 0
var toast_unique: Array = []

# 统计。
var mp_starved := 0
var basic_attacks := 0
var skill_casts := 0
var potions_used := 0
var deaths := 0
var room_log: Array = []
var snap_log: Array = []
var findings: Array = []

# FPS 分段。
var _marks := {}
var _fps_frames := 0
var _fps_time := 0.0
var cur_phase := ""

func _process(delta: float) -> void:
	_fps_frames += 1
	_fps_time += delta

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	GameState.save = GameState.fresh_save()
	await _frames(5)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(40)
	tw = main.town_world
	dw = main.dungeon_world
	ow = main.overworld
	# 拦截三个世界的弹窗与全局 toast。
	tw.dialog_requested.connect(_on_dialog)
	dw.dialog_requested.connect(_on_dialog)
	ow.dialog_requested.connect(_on_dialog)
	main.toast_message.connect(func(t: String) -> void:
		toast_total += 1
		if not toast_unique.has(t): toast_unique.append(t))

	# ---------- P0 选职业（战士：近战最能暴露问题） ----------
	_phase("selection")
	main.selection_world.request_class("warrior")
	await _wait_until(func() -> bool: return GameState.save.selected == "warrior", 400)
	await _frames(10)
	_snap("选人")

	# ---------- P1 主城首访 ----------
	_phase("town_first")
	main.change_scene(MODE_TOWN)
	await _wait_until(func() -> bool: return main.mode == MODE_TOWN, 400)
	await _frames(20)
	# 告示板看一眼。
	await _goto_poi("board")
	await _poi_interact()
	await _choose_dialog("close")
	# 协会：接全部支线。
	await _goto_poi("guild")
	await _poi_interact()
	await _run_actions_loop("接取", "协会支线")
	await _choose_dialog("close")
	# 道具商：买 1 药剂 + 1 捕兽网（开局 80 金的分配决策）。
	await _goto_poi("apothecary")
	await _poi_interact()
	await _buy_items(["potion_hp", "net"])
	await _choose_dialog("close")
	# 武器商：记录开局购买力（战士出生没有武器）。
	await _goto_poi("smithy")
	await _poi_interact()
	await _smithy_probe()
	await _choose_dialog("close")
	# 找最近 NPC 聊一次。
	await _talk_nearest_npc()
	_snap("主城消费后")
	await _shot("play_1_town")

	# ---------- P2 第一层完整通关 ----------
	_phase("dungeon_run1")
	await _goto_poi("abyss_gate")
	await _poi_interact()
	await _choose_dialog(0)  # 推门而入
	await _wait_until(func() -> bool: return main.mode == MODE_DUNGEON, 400)
	await _frames(10)
	var run1_gold0: int = GameState.save.gold
	for d in range(dw.ROOM_COUNT):
		var d0: int = dw.depth
		await _play_room(d)
		# 房间推进校验：防止 depth 卡住后读到过期房间类型的级联错位。
		if d < dw.ROOM_COUNT - 1 and dw.depth == d0:
			findings.append("房间 %d 未推进到下一间（state=%s）" % [d + 1, dw.state])
			break
	var run1_income: int = GameState.save.gold - run1_gold0
	print("[PLAY] 第一层总金币收入 = %d（含击杀+宝箱+事件）" % run1_income)
	_snap("第一层通关")

	# ---------- P3 回城消费 ----------
	_phase("town_after_run")
	await _wait_until(func() -> bool: return main.mode == MODE_TOWN, 600)
	await _frames(20)
	# 卖光材料。
	await _goto_poi("apothecary")
	await _poi_interact()
	await _sell_materials()
	await _choose_dialog("close")
	# 补给药剂。
	await _poi_interact_again()
	await _buy_items(["potion_hp", "potion_hp"])
	await _choose_dialog("close")
	# 铁匠：强化或买武器。
	await _goto_poi("smithy")
	await _poi_interact()
	await _smithy_upgrade_or_buy()
	await _choose_dialog("close")
	# 协会领赏。
	await _goto_poi("guild")
	await _poi_interact()
	await _run_actions_loop("领取", "协会领赏")
	await _choose_dialog("close")
	# 告示板：日常任务领取。
	await _goto_poi("board")
	await _poi_interact()
	await _run_actions_loop("领取", "告示板日常")
	await _choose_dialog("close")
	# 加点 + 穿装备。
	await _spend_points()
	_equip_best()
	_snap("回城消费后")
	await _shot("play_4_town_after")

	# ---------- P4 野外探索 ----------
	_phase("overworld")
	await _goto_poi("east_gate")
	await _poi_interact()
	await _wait_until(func() -> bool: return main.mode == MODE_OVERWORLD, 400)
	await _frames(20)
	# 去南方森林。
	var forest_pos := Vector3(0, 0, 40)
	print("[PLAY] biome@(0,0,40) = %s" % ow.biome_at(forest_pos))
	await _walk_overworld(forest_pos, 2400)
	# 找一只动物，验证狩猎/捕获链路（野外攻击为本次迭代新增）。
	var animal = null
	for a in ow.animals:
		if not a.dead: animal = a; break
	if animal:
		await _hunt_and_capture(animal)
	else:
		findings.append("野外没有遇到动物（密度或刷新问题）")
	# 夜晚 + 火把。
	GameState.day_time = 22.0
	ow.toggle_torch()
	await _frames(15)
	ow.place_torch()
	await _frames(40)
	await _shot("play_5_overworld_night")
	_snap("野外")

	# ---------- P5 第二层首房（进度对比） ----------
	_phase("dungeon_run2")
	# 走向西端回城哨站营火 (-WORLD_R+7,0)=(-53,0)（注意：野外移动半径上限 58.5，目标点必须在内）。
	await _walk_overworld(Vector3(-53, 0, 0), 3000)
	if ow.player.global_position.distance_to(Vector3(-53, 0, 0)) > 2.5:
		findings.append("野外回程未到位（距哨站 %.1fm）" % ow.player.global_position.distance_to(Vector3(-53, 0, 0)))
	ow.interact()  # 哨站按 E 回城（游戏设计：E 键交互触发 exit_requested）
	await _wait_until(func() -> bool: return main.mode == MODE_TOWN, 600)
	await _frames(15)
	await _goto_poi("abyss_gate")
	await _poi_interact()
	await _choose_dialog(0)
	await _wait_until(func() -> bool: return main.mode == MODE_DUNGEON, 400)
	await _frames(10)
	await _play_room(0)
	dw.exit_dungeon()  # 见好就收（真实玩法）
	await _wait_until(func() -> bool: return main.mode == MODE_TOWN, 600)
	_snap("二刷首房后")

	# ---------- 最终报告 ----------
	_phase("end")
	_marks[cur_phase] = [_fps_frames, _fps_time]
	await _frames(30)
	_report()
	get_tree().quit()

# ---------------- 弹窗 / toast ----------------
func _on_dialog(title: String, _content: String, actions: Array, _eyebrow: String) -> void:
	pending_dialog = {"title": title, "actions": actions}
	dialog_total += 1
	var labels: Array = []
	for a in actions: labels.append(String(a.label))
	print("[PLAY] 弹窗 #%d 「%s」选项[%s]" % [dialog_total, title, ", ".join(labels)])

func _dialog_wait(max_frames: int = 900) -> void:
	var guard := 0
	while pending_dialog.is_empty() and guard < max_frames:
		guard += 1
		await _frames(1)

func _choose_dialog(which) -> void:
	# which = int 下标 / "close" 找离开 / "any" 选第一个。
	await _dialog_wait()
	if pending_dialog.is_empty():
		findings.append("等待弹窗超时（choose=%s）" % str(which))
		return
	var acts: Array = pending_dialog.get("actions", [])
	if typeof(which) == TYPE_STRING:
		if which == "close":
			for a in acts:
				if bool(a.get("secondary", false)):
					a.run.call()
					pending_dialog = {}
					return
			# 兜底：常见关闭文案。
			for a in acts:
				if String(a.label) in ["离开", "知道了", "关闭"]:
					a.run.call()
					pending_dialog = {}
					return
			pending_dialog = {}  # 无关闭按钮就直接清（等价 Esc）
			return
		which = 0
	var idx: int = which
	if idx >= acts.size(): idx = acts.size() - 1
	if idx < 0: return
	acts[idx].run.call()
	pending_dialog = {}

## 循环执行以 prefix 开头的动作（每次执行后弹窗会关闭，需重新打开）。
func _run_actions_loop(prefix: String, what: String) -> void:
	var n := 0
	var guard := 0
	while guard < 12:
		guard += 1
		await _dialog_wait()
		if pending_dialog.is_empty(): break
		var found = null
		for a in pending_dialog.get("actions", []):
			if String(a.label).begins_with(prefix): found = a; break
		if found == null: break
		found.run.call()
		n += 1
		pending_dialog = {}
		await _frames(5)
		if main.mode == MODE_TOWN: tw.interact_near()  # 重新打开
	print("[PLAY] %s：执行 %d 次「%s」" % [what, n, prefix])
	if n == 0 and what.contains("领赏"):
		findings.append("第一层通关后无可领取奖励（任务进度没接上？）")

# ---------------- 主城操作 ----------------
func _goto_poi(id: String) -> void:
	var poi = null
	for p in tw.pois:
		if p.id == id: poi = p; break
	if poi == null:
		findings.append("POI 不存在：%s" % id)
		return
	var target: Vector3 = poi.position + Vector3(0, 0, 3.0)
	tw.travel_to_poi(poi)
	var guard := 0
	while guard < 4500:
		guard += 1
		# 等游戏自己停下（0.35m 判定后 has_move_target 置 false），不要提前冻结玩家。
		if not tw.has_move_target or tw.player_position.distance_to(target) < 0.45:
			break
		await _frames(2)
	if guard >= 4500:
		tw.has_move_target = false
		findings.append("寻路超时：%s（%d 帧，剩余 %.1fm）" % [id, guard, tw.player_position.distance_to(target)])
	await _frames(5)

func _poi_interact() -> void:
	await _frames(3)
	tw.interact_near()
	await _dialog_wait()

func _poi_interact_again() -> void:
	tw.interact_near()
	await _dialog_wait()

func _buy_items(ids: Array) -> void:
	await _dialog_wait()
	if pending_dialog.is_empty():
		findings.append("商店弹窗未打开")
		return
	for id in ids:
		var nm: String = Items.stack_item(id).name
		var found = null
		for a in pending_dialog.get("actions", []):
			if String(a.label) == "买 " + nm: found = a; break
		if found == null:
			findings.append("商店没有商品：%s" % nm)
			continue
		var g0: int = GameState.save.gold
		var c0: int = GameState.inventory.count_of(id)
		found.run.call()
		await _frames(3)
		if GameState.inventory.count_of(id) <= c0:
			findings.append("买不起 %s（身上 %d 金）" % [nm, g0])
		else:
			print("[PLAY] 购买 %s：- %d 金" % [nm, g0 - GameState.save.gold])

func _smithy_probe() -> void:
	await _dialog_wait()
	if pending_dialog.is_empty(): return
	# 记录在售武器价格（兼容全角括号），检查开局购买力。
	var labels: Array = []
	for a in pending_dialog.get("actions", []): labels.append(String(a.label))
	var cheapest := 999999
	for l in labels:
		var lab := String(l)
		if lab.begins_with("买 "):
			var s: PackedStringArray = lab.replace("（", "(").replace("）", ")").split("(")
			if s.size() > 1:
				var num := String(s[1]).replace("金)", "").replace(")", "")
				if num.is_valid_int(): cheapest = mini(cheapest, int(num))
	if GameState.save.weapon == null:
		print("[PLAY] 开局武器：无 · 最便宜武器 %d 金 · 身上 %d 金 → %s" % [
			cheapest, GameState.save.gold, "买得起" if GameState.save.gold >= cheapest else "买不起"])
		if GameState.save.gold < cheapest:
			findings.append("开局无武器且买不起任何武器（第一层徒手通关）")
		# 无武器才尝试购买（买不起会 toast）。
		for a in pending_dialog.get("actions", []):
			if String(a.label).begins_with("买 "):
				a.run.call()
				await _frames(3)
				break
	else:
		print("[PLAY] 开局武器：%s Lv%d（新手保底）· 最便宜店货 %d 金 · 身上 %d 金" % [
			GameState.save.weapon.name, int(GameState.save.weapon.level), cheapest, GameState.save.gold])

func _smithy_upgrade_or_buy() -> void:
	await _dialog_wait()
	if pending_dialog.is_empty(): return
	if GameState.save.weapon != null:
		for a in pending_dialog.get("actions", []):
			if String(a.label) == "强化武器":
				var g0: int = GameState.save.gold
				a.run.call()
				await _frames(3)
				print("[PLAY] 强化武器：- %d 金 → Lv%d" % [g0 - GameState.save.gold, int(GameState.save.weapon.level)])
				return
	# 没武器就买最便宜的。
	for a in pending_dialog.get("actions", []):
		if String(a.label).begins_with("买 "):
			var g0: int = GameState.save.gold
			a.run.call()
			await _frames(3)
			if GameState.save.weapon != null:
				print("[PLAY] 购买武器：%s（- %d 金）" % [GameState.save.weapon.name, g0 - GameState.save.gold])
			else:
				findings.append("通关后仍买不起武器（%d 金）" % g0)
			return

func _talk_nearest_npc() -> void:
	var best = null
	var bd := 9999.0
	for n in tw.npcs:
		var d: float = n.global_position.distance_to(tw.player.global_position)
		if d < bd: bd = d; best = n
	if best == null:
		findings.append("主城没有 NPC")
		return
	var guard := 0
	while guard < 2400:
		guard += 1
		if best.global_position.distance_to(tw.player.global_position) < 2.4: break
		tw.move_target = best.global_position
		tw.has_move_target = true
		await _frames(2)
	tw.has_move_target = false
	await _frames(5)
	tw.interact_near()
	await _dialog_wait()
	if pending_dialog.is_empty():
		findings.append("走近 NPC 却没触发对话（距离 %0.1f）" % bd)
	else:
		print("[PLAY] NPC「%s」对话选项 %d 个" % [pending_dialog.title, pending_dialog.get("actions", []).size()])
		await _choose_dialog("close")

func _sell_materials() -> void:
	await _dialog_wait()
	if pending_dialog.is_empty(): return
	var earned := 0
	# shard（深渊碎片）留给武器强化，只卖 herb / pelt。
	for m in ["herb", "pelt"]:
		var nm: String = Items.stack_item(m).name
		var guard := 0
		while GameState.inventory.count_of(m) > 0 and guard < 20:
			guard += 1
			var found = null
			for a in pending_dialog.get("actions", []):
				if String(a.label).begins_with("卖") and String(a.label).contains(nm): found = a; break
			if found == null: break
			var g0: int = GameState.save.gold
			found.run.call()
			earned += GameState.save.gold - g0
			await _frames(2)
	if earned > 0:
		print("[PLAY] 卖出材料 + %d 金" % earned)
	else:
		print("[PLAY] 没有可卖的材料")

func _spend_points() -> void:
	var pool: int = GameState.save.point_pool
	if pool <= 0:
		print("[PLAY] 无可加点（point_pool=0，Lv%d）" % int(GameState.save.char_level))
		return
	var n := 0
	for i in range(pool):
		var err: String = GameState.allocate_point("brute")
		if err != "":
			findings.append("加点被拒：%s（已加 %d/%d）" % [err, n, pool])
			break
		n += 1
	print("[PLAY] 加点：蛮力 +%d（池 %d）" % [n, pool])

func _equip_best() -> void:
	var n := 0
	for i in range(24):
		var inst = GameState.inventory.slots[i]
		if inst != null and (inst.kind == "weapon" or (inst.kind == "gear" and String(inst.get("slot", "")) != "")):
			GameState.equip_slot(i)
			n += 1
	if n > 0: print("[PLAY] 穿戴/换装 %d 件" % n)

# ---------------- 地下城 ----------------
func _play_room(d: int) -> void:
	await _frames(5)
	var kind: String = dw.room_kind
	var hp0: int = _php()
	var g0: int = GameState.save.gold
	var pot0: int = GameState.save.potions
	var t0: int = _fps_frames
	print("[PLAY] —— 房间 %d · %s（HP %d）——" % [d + 1, kind, hp0])
	if kind == "event":
		await _do_event_room()
	else:
		await _fight_until_clear(kind == "boss")
		await _collect_pickups()
	# 祝福（Boss 房没有；事件房走 _room_done 路径，同样不发祝福）。
	if d < dw.ROOM_COUNT - 1:
		if kind != "event":
			await _choose_blessing()
		await _walk_north_door()
	else:
		# Boss 房：肃清弹窗 + 回归之门。
		await _choose_dialog("any")
		await _walk_to_portal()
	var frames_used: int = _fps_frames - t0
	var hp_loss: int = maxi(0, hp0 - _php())
	room_log.append({"d": d + 1, "kind": kind, "sec": frames_used, "hp_loss": hp_loss,
		"gold": GameState.save.gold - g0, "potion": pot0 - GameState.save.potions})
	print("[PLAY] 房间 %d 完成：%d 帧 · 掉血 %d · 金币 +%d · 药剂 %d" % [d + 1, frames_used, hp_loss, GameState.save.gold - g0, pot0 - GameState.save.potions])

func _fight_until_clear(boss: bool) -> void:
	var guard := 0
	var shot_done := false
	while guard < 9000:
		guard += 1
		if main.mode != MODE_DUNGEON: return
		if dw.player.dead:
			deaths += 1
			findings.append("玩家死亡于房间 %d（HP 归零）" % (dw.depth + 1))
			await _choose_dialog("any")
			return
		if dw.state == "cleared": return
		var alive: Array = []
		for e in dw.enemies:
			if not e.dead: alive.append(e)
		if alive.is_empty():
			await _frames(2)
			if dw.state == "cleared": return
			continue
		# 选最近目标。
		var target = alive[0]
		var bd := 99999.0
		for e in alive:
			var dd: float = e.global_position.distance_to(dw.player.global_position)
			if dd < bd: bd = dd; target = e
		dw.player.enemy_target = target
		var atk_range: float = float(GameState.class_data().attack_range)
		if bd > atk_range * 0.85:
			dw.move_target = target.global_position
			dw.has_move_target = true
			await _frames(2)
			continue
		# 进攻距离：面向目标再打。
		var to_t: Vector3 = target.global_position - dw.player.global_position
		dw.player.rotation.y = atan2(to_t.x, to_t.z)
		dw.has_move_target = false
		if boss and not shot_done and guard > 50:
			shot_done = true
			await _shot("play_3_boss")
		# 技能优先（1→2→3→4），蓝不够才普攻。
		var acts: Array = SkillBook.actives(GameState.save.selected)
		var casted := false
		for i in range(4):
			var cdi: float = dw.cooldowns[i]
			var mpc: float = float(acts[i].mp)
			if cdi <= 0.0 and GameState.save.mp >= mpc:
				dw.cast_skill(i)
				skill_casts += 1
				casted = true
				break
		if not casted:
			for i in range(4):
				if float(dw.cooldowns[i]) <= 0.0 and GameState.save.mp < float(acts[i].mp):
					mp_starved += 1
					break
			dw.player_attack()
			basic_attacks += 1
		# 残血喝药。
		if dw.player.hp < int(dw.player.hp_max * 0.35) and GameState.save.potions > 0:
			main.use_potion()
			potions_used += 1
		await _frames(2)
	findings.append("战斗超时未清场（房间 %d，9000 帧）" % (dw.depth + 1))

func _collect_pickups() -> void:
	var guard := 0
	while dw.pickups.size() > 0 and guard < 2400:
		guard += 1
		var pk = dw.pickups[0]
		if not is_instance_valid(pk.node):
			await _frames(2)
			continue
		var pos: Vector3 = pk.node.global_position
		if dw.player.global_position.distance_to(pos) < 1.8:
			dw.has_move_target = false
		else:
			dw.move_target = pos
			dw.has_move_target = true
		await _frames(2)
	dw.has_move_target = false

func _do_event_room() -> void:
	var prop: Node3D = dw.get_node_or_null("EventProp")
	if prop == null:
		findings.append("事件房没有 EventProp 节点")
		return
	await _walk_dw(prop.global_position + Vector3(0, 0, 1.0), 900)
	dw.interact()
	await _dialog_wait()
	if pending_dialog.is_empty():
		# 宝箱/泉水类事件自动结算（无弹窗）：仅当房间仍未完成才算问题。
		if dw.state != "cleared":
			findings.append("事件交互后没有弹窗且房间未完成（E 交互没接上？）")
		return
	# 同一弹窗两步走：先试第一个选项（买/献祭/答题，覆盖事件链路），
	# 再用「离开/次级」按钮收尾——行商类事件只有离开才会 _room_done。
	var acts: Array = pending_dialog.get("actions", [])
	if acts.size() > 0: acts[0].run.call()
	for a in acts:
		if bool(a.get("secondary", false)) or String(a.label) in ["离开", "知道了", "关闭"]:
			a.run.call()
			break
	pending_dialog = {}
	await _frames(10)

func _choose_blessing() -> void:
	await _dialog_wait()
	if pending_dialog.is_empty():
		findings.append("清场后没弹祝福三选一（房间 %d）" % (dw.depth + 1))
		return
	var acts: Array = pending_dialog.get("actions", [])
	var pick := 0
	for i in range(acts.size()):
		if String(acts[i].label) in ["深渊之力", "弱点直觉", "点金之手"]:
			pick = i; break
	print("[PLAY] 祝福选择 → 「%s」" % String(acts[pick].label))
	acts[pick].run.call()
	pending_dialog = {}

func _walk_north_door() -> void:
	var d0: int = dw.depth
	dw.move_target = Vector3(0, 0, -13.6)
	dw.has_move_target = true
	var guard := 0
	# 严格等 depth 变化（游戏在 z < -ARENA_R+2.6 且 state=cleared 时才会进下一间），
	# 不再提前用 z 判定 break——那会比游戏触发线早一步，读到过期房间类型。
	while dw.depth == d0 and guard < 1800:
		guard += 1
		if dw.player.global_position.z > -12.0:
			dw.move_target = Vector3(0, 0, -13.6)
			dw.has_move_target = true
		await _frames(2)
	dw.has_move_target = false
	if dw.depth == d0:
		findings.append("北门触发失败（房间 %d，state=%s）" % [d0 + 1, dw.state])

func _walk_to_portal() -> void:
	var guard := 0
	while main.mode == MODE_DUNGEON and guard < 1200:
		guard += 1
		dw.move_target = Vector3(0, 0, -13.0)
		dw.has_move_target = true
		await _frames(2)
	dw.has_move_target = false

func _walk_dw(pos: Vector3, max_frames: int) -> void:
	dw.move_target = pos
	dw.has_move_target = true
	var guard := 0
	while guard < max_frames:
		guard += 1
		if dw.player.global_position.distance_to(pos) < 0.9: break
		await _frames(2)
	dw.has_move_target = false

func _walk_overworld(pos: Vector3, max_frames: int) -> void:
	ow.move_target = pos
	ow.has_move_target = true
	var guard := 0
	while guard < max_frames:
		guard += 1
		if ow.player.global_position.distance_to(pos) < 1.5: break
		await _frames(2)
	ow.has_move_target = false

## 狩猎一只动物：攻击至残血（<30%）→ 捕网捕获。覆盖野外攻击、激怒反击、捕宠。
func _hunt_and_capture(animal) -> void:
	print("[PLAY] 遭遇 %s（%s / %s）HP %d/%d" % [animal.display_name, animal.species, animal.mode, animal.hp, animal.hp_max])
	var hp_player0: int = ow.player.hp
	var guard := 0
	var hits := 0
	var dmg_total := 0
	while guard < 1800:
		guard += 1
		if not is_instance_valid(animal) or animal.dead: break
		if animal.hp <= animal.hp_max * 0.28: break  # 已残血，停止攻击
		var dist: float = animal.global_position.distance_to(ow.player.global_position)
		if dist > 2.1:
			ow.move_target = animal.global_position
			ow.has_move_target = true
			await _frames(2)
			continue
		ow.has_move_target = false
		var hp0: int = animal.hp
		ow.player_attack()
		await _frames(4)
		if is_instance_valid(animal) and animal.hp < hp0:
			hits += 1
			dmg_total += hp0 - animal.hp
	ow.has_move_target = false
	var p_now: int = ow.player.hp if is_instance_valid(ow.player) else 0
	print("[PLAY] 狩猎：命中 %d · 总伤害 %d · 玩家受伤 %d（%d→%d）· toast：%s" % [
		hits, dmg_total, hp_player0 - p_now, hp_player0, p_now, _last_toast()])
	if not is_instance_valid(animal) or animal.dead:
		print("[PLAY] 目标被击杀——掉落已生成。")
		return
	if animal.hp > animal.hp_max * 0.3:
		findings.append("1800 帧内没能把 %s 打到残血（当前 %d/%d）" % [animal.display_name, animal.hp, animal.hp_max])
		return
	# 残血 → 贴近后用捕网捕获。
	var pets0: int = GameState.save.pets.size()
	var nets0: int = GameState.inventory.count_of("net")
	var cg := 0
	while cg < 600 and is_instance_valid(animal) and not animal.dead \
			and animal.global_position.distance_to(ow.player.global_position) > 2.2:
		cg += 1
		ow.move_target = animal.global_position
		ow.has_move_target = true
		await _frames(2)
	ow.has_move_target = false
	ow.interact()
	await _frames(10)
	var got: bool = GameState.save.pets.size() > pets0
	print("[PLAY] 捕获尝试：网 %d→%d · 宠物 %d→%d · toast：%s" % [
		nets0, GameState.inventory.count_of("net"), pets0, GameState.save.pets.size(), _last_toast()])
	if got:
		print("[PLAY] ✓ 捕宠成功 → " + str(GameState.save.pets.back()))

# ---------------- 工具 ----------------
func _php() -> int:
	if main.mode == MODE_DUNGEON and dw.player: return dw.player.hp
	if main.mode == MODE_OVERWORLD and ow.player: return ow.player.hp
	return int(GameState.save.hp)

func _last_toast() -> String:
	return str(toast_unique.back()) if toast_unique.size() > 0 else "（无）"

func _snap(label: String) -> void:
	var s: Dictionary = GameState.save
	var st: Dictionary = GameState.total_stats()
	var wtxt: String = "无" if s.weapon == null else "%s+Lv%d" % [s.weapon.name, int(s.weapon.level)]
	print("[PLAY] SNAP %-8s | 金 %4d 钻 %d | Lv%d xp%d/%d 池%d | HP %d/%d 蓝 %d | 药 %d | 武器 %s" % [
		label, int(s.gold), int(s.diamonds), int(s.char_level), int(s.xp),
		int(GameState.xp_needed(int(GameState.save.char_level))), int(s.point_pool), int(s.hp), int(st.hp_max),
		int(s.mp), int(s.potions), wtxt])
	snap_log.append({"label": label, "gold": int(s.gold), "lv": int(s.char_level)})

func _phase(nm: String) -> void:
	if cur_phase != "": _marks[cur_phase] = [_fps_frames, _fps_time]
	cur_phase = nm

func _report() -> void:
	print("")
	print("========== PLAYTHROUGH REPORT ==========")
	print("· 阶段快照：")
	for s in snap_log:
		print("   %s → 金币 %d (Lv%d)" % [s.label, s.gold, s.lv])
	print("· 房间日志：")
	for r in room_log:
		print("   房%d %s: %d帧 掉血%d 金+%d 药%d" % [r.d, r.kind, r.sec, r.hp_loss, r.gold, r.potion])
	print("· 战斗行为：技能 %d · 普攻 %d · 蓝饥饿 %d · 药剂 %d · 死亡 %d" % [skill_casts, basic_attacks, mp_starved, potions_used, deaths])
	print("· 敌军协同：末局列阵 %s · 组合拳累计 %d 次" % [
		String(Bestiary.SQUAD_FORMATIONS.get(dw.squad.get("formation", ""), {}).get("name", "—")), dw.squad_combos])
	print("· 弹窗 %d 个 · toast %d 次 / 去重 %d 种" % [dialog_total, toast_total, toast_unique.size()])
	var prev := ""
	print("· FPS 分段：")
	for k in _marks.keys():
		var cur: Array = _marks[k]
		var f0 := 0
		var t0 := 0.0
		if prev != "":
			f0 = _marks[prev][0]
			t0 = _marks[prev][1]
		var fps: float = float(cur[0] - f0) / maxf(cur[1] - t0, 0.0001)
		print("   %-16s %6.1f FPS %s" % [prev + "→" + k, fps, "OK" if fps >= 55.0 else "LOW"])
		prev = k
	var total_fps: float = float(_fps_frames) / maxf(_fps_time, 0.0001)
	print("   全程平均：%.1f FPS" % total_fps)
	print("· 发现的问题（%d）：" % findings.size())
	var seen: Array = []
	for f in findings:
		if seen.has(f): continue
		seen.append(f)
		print("   [!] " + f)
	if findings.is_empty():
		print("   （无）")

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _wait_until(pred: Callable, max_frames: int) -> void:
	for i in max_frames:
		if pred.call():
			return
		await get_tree().process_frame

func _shot(nm: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/shot_%s.png" % [OUT_DIR, nm])
	print("SHOT · " + nm)
