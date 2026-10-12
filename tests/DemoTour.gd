extends Node
## 渲染验证巡游 v2：职业展示(5)→主城寻路→地下城战斗/大招→野外夜景火把，逐场景截图到 _explore/。
## 每阶段统计渲染帧率，结束时输出分段 FPS 报告（60FPS 目标核查）。
## 运行（非 headless）：godot --path . res://tests/DemoTour.tscn

const OUT_DIR := "E:/个人文件/各类尝试/Dungeon Game/_explore"
const MODE_TOWN := 1
const MODE_DUNGEON := 2
const MODE_OVERWORLD := 3

var _fps_frames := 0
var _fps_time := 0.0
var _marks := {}   # 阶段名 -> [frames, time]

func _process(delta: float) -> void:
	_fps_frames += 1
	_fps_time += delta

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	GameState.save = GameState.fresh_save()
	await _frames(5)
	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(40)
	await _shot("1_selection_archer")

	main.selection_world.request_class("shield")
	await _wait_until(func(): return GameState.save.selected == "shield", 400)
	await _frames(40)
	await _shot("2_selection_shield")

	main.selection_world.request_class("mage")
	await _wait_until(func(): return GameState.save.selected == "mage", 400)
	await _frames(40)
	_mark("selection")
	await _shot("3_selection_mage")

	# 主城：广场全景（喷泉/街景/建筑）。传送到广场中心保证视野可控。
	main.change_scene(MODE_TOWN)
	await _wait_until(func(): return main.mode == MODE_TOWN, 400)
	main.town_world.player.global_position = Vector3(0, 0, 10)
	main.town_world.player_position = Vector3(0, 0, 10)
	await _frames(40)
	await _shot("4_town_plaza")
	# 寻路横穿主城到告示板，再绕到武器商家门口拍建筑近景。
	var board = null
	for poi in main.town_world.pois:
		if poi.id == "board": board = poi; break
	main.town_world.travel_to_poi(board)
	var near_board := func() -> bool: return main.town_world.player_position.distance_to(board.position) < 3.4
	await _wait_until(near_board, 3000)
	_mark("town")
	await _shot("5_town_board")
	# 任务系统 UI：接一个支线并追踪，打开任务日志面板截图。
	GameState.accept_side_quest("side_wolves")
	GameState.set_tracked("side", "side_wolves")
	main.ui.toggle_panel("quests")
	await _frames(25)
	await _shot("6_town_quest_log")
	main.ui.toggle_panel("quests")
	await _frames(10)
	# 组队系统：招募 3 名同伴 + 切到「展开横排」，用于验证列阵与技能组合。
	GameState.add_affinity("rowan", 100)
	GameState.add_affinity("mira", 100)
	GameState.add_affinity("kane", 100)
	GameState.recruit("rowan")
	GameState.recruit("mira")
	GameState.recruit("kane")
	GameState.set_formation("spread")
	await _frames(15)
	main.ui.toggle_panel("pets")
	await _frames(25)
	await _shot("8_party_panel")
	main.ui.toggle_panel("pets")
	await _frames(10)
	main.town_world.travel_to_poi(main.town_world.poi_pos("smithy"))
	await _wait_until(func(): return main.town_world.player_position.distance_to(main.town_world.poi_pos("smithy")) < 5.0, 3000)
	await _frames(20)
	await _shot("7_town_smithy")

	# 地下城：combat 房 + 技能 + 大招。
	main.change_scene(MODE_DUNGEON)
	await _wait_until(func(): return main.mode == MODE_DUNGEON, 400)
	await _frames(10)
	var retries := 0
	while main.dungeon_world.enemies.size() == 0 and retries < 6:
		main.dungeon_world.reset_dungeon()
		retries += 1
		await _frames(5)
	GameState.save.mp = float(GameState.total_stats().mp_max)
	main.dungeon_world.cast_skill(0)
	await _frames(20)
	main.dungeon_world.cast_skill(2)
	await _frames(15)
	_mark("dungeon_fight")
	await _shot("9_dungeon_skill")

	# 敌军小队：列阵 + 组合拳（截图验证"怪物相互配合"）。
	var _dw0 = main.dungeon_world
	var _sr := 0
	while _dw0.squad.get("members", []).size() < 2 and _sr < 6:
		_dw0.reset_dungeon()
		_sr += 1
		await _frames(5)
	await _frames(90)   # 等小队按阵型各就各位
	_mark("enemy_formation")
	await _shot("9b_enemy_formation")
	var _cid: String = Bestiary.pick_combo(_dw0.run_rng, _dw0.squad.get("roles", {}))
	if _cid == "": _cid = "flank"
	_dw0.force_squad_combo(_cid)
	await _frames(16)   # 前摇中段：全员蓄势 + 地面预警环
	_mark("enemy_combo")
	await _shot("9c_enemy_combo")
	print("[DEMO] 敌军小队：阵型 %s · 组合拳 %s · 成员 %d 人" % [
		_dw0.squad.get("formation", "-"), _cid, _dw0.squad.get("members", []).size()])
	# 视角拉远：验证无雾后全场可辨（相机拉到接近最远）。
	var _cam = main.camera_rig
	var _d0: float = _cam.cam_dist
	_cam.cam_dist = 48.0
	await _frames(100)
	await _shot("9d_dungeon_wide")
	_cam.cam_dist = _d0

	# 组队战斗：同伴先手挂标记 → 玩家补刀引爆（用引爆计数器验证，比看 meta 可靠）。
	var dw = main.dungeon_world
	var en = null
	for e in dw.enemies:
		if is_instance_valid(e) and not e.dead and (en == null or e.hp > en.hp):
			en = e   # 挑血最厚的目标：避免一击秒杀导致跳过引爆
	var marked := false
	var det0: int = dw.combo_detonations
	if en != null:
		dw.player.global_position = en.global_position + Vector3(0, 0, 2.5)
		dw.player.enemy_target = en
		# 演示用：同伴按阵型安置到玩家身边（真实游玩中他们会自己跑过来）。
		var cnt: int = maxi(dw.followers.size(), 1)
		for i in range(dw.followers.size()):
			var off: Vector3 = NpcBook.formation_offset(GameState.party_formation(), i, cnt)
			dw.followers[i].global_position = dw.player.global_position + Vector3(off.x, 0, off.z)
		for i in range(200):
			for e in dw.enemies:
				if is_instance_valid(e) and e.has_meta("combo_mark"):
					marked = true
					break
			if marked: break
			await _frames(1)
		# 等玩家当前动作（施法动画/攻击冷却）结束再补刀。
		for i in range(240):
			if dw.player.attack_ready(): break
			await _frames(1)
		dw.player.global_position = en.global_position + Vector3(0, 0, 2.0)
		dw.player.enemy_target = en
		dw.player_attack()
		for i in range(150):
			if dw.combo_detonations > det0: break
			await _frames(1)
	print("[DEMO] 技能组合：同伴先手标记=%s → 玩家引爆=%s（引爆 %d 次 · 同伴 %d 人 · 阵型 %s · 档位 %s · 目标存活=%s）" % [
		"已挂上" if marked else "未挂上",
		"成功" if dw.combo_detonations > det0 else "未触发",
		dw.combo_detonations, dw.followers.size(), GameState.party_formation(),
		GameState.stance_of(String(GameState.save.party[0])) if GameState.save.party.size() > 0 else "-",
		is_instance_valid(en) and not en.dead])
	await _shot("10_dungeon_party_combo")

	# ---- 防御 / 格挡 验证（固定 20 点伤害，排除 AI 干扰）----
	var pw = dw.player
	var foe = dw.nearest_enemy(pw.global_position, 60.0)
	# 等玩家当前动作结束（防御在攻击/施法期间不可进入）。
	for i in range(240):
		if not pw.is_busy(): break
		await _frames(1)
	Input.action_press("guard")
	await _frames(3)
	var parry_dealt: int = pw.take_damage(20.0, foe)
	await _frames(2)
	var stunned: bool = foe != null and is_instance_valid(foe) and foe.stun_t > 0.0
	var counter_ok: bool = pw.counter_t > 0.0
	await _frames(30)   # 等招架窗口关闭（法师 0.25s）
	var guard_dealt: int = pw.take_damage(20.0, null)
	await _frames(2)
	print("[DEMO] 防御/格挡：招架实收 %d（期望 0）· 反震硬直=%s · 反击窗口=%s · 防御中受 20 点实收 %d"
		% [parry_dealt, "是" if stunned else "否", "开启" if counter_ok else "无", guard_dealt])
	Input.action_release("guard")
	await _frames(6)

	# 大招前补满蓝量并清冷却（演示用途）。
	GameState.save.mp = float(GameState.total_stats().mp_max)
	main.dungeon_world.cooldowns = [0.0, 0.0, 0.0, 0.0]
	main.dungeon_world.player_ultimate()
	await _frames(26)
	_mark("dungeon_ult")
	await _shot("11_dungeon_ultimate")

	# 野外：夜晚 + 手持火把（暗光渲染压力场景）。
	main.change_scene(MODE_OVERWORLD)
	await _wait_until(func(): return main.mode == MODE_OVERWORLD, 400)
	GameState.day_time = 22.0
	GameState.inventory.add(Items.stack_item("torch", 3))
	main.overworld.toggle_torch()
	await _frames(60)
	_mark("overworld_night")
	await _shot("12_overworld_night_torch")

	# FPS 报告。
	print("")
	print("========== FPS REPORT（60FPS 目标） ==========")
	var order: Array = _marks.keys()
	var prev_name := ""
	for k in order:
		var cur: Array = _marks[k]
		var f0 := 0
		var t0 := 0.0
		if prev_name != "":
			f0 = _marks[prev_name][0]
			t0 = _marks[prev_name][1]
		var fps: float = float(cur[0] - f0) / maxf(cur[1] - t0, 0.0001)
		print("  %-18s %6.1f FPS %s" % [prev_name + "→" + k, fps, "OK" if fps >= 55.0 else "LOW"])
		prev_name = k
	var total_fps: float = float(_fps_frames) / maxf(_fps_time, 0.0001)
	print("  全程平均：%.1f FPS" % total_fps)
	await _frames(20)
	get_tree().quit()

func _mark(name: String) -> void:
	_marks[name] = [_fps_frames, _fps_time]

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _wait_until(pred: Callable, max_frames: int) -> void:
	for i in max_frames:
		if pred.call():
			return
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/shot_%s.png" % [OUT_DIR, name])
	print("SHOT · " + name)
