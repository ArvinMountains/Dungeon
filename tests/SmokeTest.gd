extends Node
## Headless 冒烟测试（v2）：四世界流转 + 新系统联动。
## 职业切换(5) → 主城(POI/对话/面板) → 视角锁定 → 地下城(技能/清场/撤离) → 野外(地形/动物/火把) → 昼夜 → 存档。
## 运行：godot --headless --path . res://tests/SmokeTest.tscn

const MODE_TOWN := 1
const MODE_DUNGEON := 2
const MODE_OVERWORLD := 3

var failures: Array[String] = []
var checks: Array[String] = []

func _ready() -> void:
	GameState.save = GameState.fresh_save()
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(5)
	await _check("Main 就绪（四世界+UI+相机+天空）",
		main.selection_world != null and main.town_world != null and main.dungeon_world != null
		and main.overworld != null and main.ui != null and main.camera_rig != null and main.sky_dome != null)
	await _check("初始职业 archer", GameState.save.selected == "archer")

	# 1. 新职业切换（大盾 → 法师）。
	main.selection_world.request_class("shield")
	await _wait_until(func(): return GameState.save.selected == "shield", 300)
	await _check("切换到大盾守卫", GameState.save.selected == "shield")
	main.selection_world.request_class("mage")
	await _wait_until(func(): return GameState.save.selected == "mage", 300)
	await _check("切换到星辉法师", GameState.save.selected == "mage")

	# 2. 进入主城：3 倍扩建 + 8 个 POI（含 5 功能建筑）。
	main.change_scene(MODE_TOWN)
	await _wait_until(func(): return main.mode == MODE_TOWN, 300)
	await _frames(3)
	var poi_ids: Array = []
	for poi in main.town_world.pois:
		poi_ids.append(poi.id)
	var need := ["smithy", "apothecary", "guild", "library", "training", "abyss_gate", "east_gate", "board"]
	var all_poi := true
	for p in need:
		if not poi_ids.has(p): all_poi = false
	await _check("主城 POI 齐全（%d 个，含 5 功能建筑）" % poi_ids.size(), all_poi and poi_ids.size() >= 8)

	# 3. POI 寻路行走 + 交互弹窗。
	var pos0: Vector3 = main.town_world.player_position
	var board_poi = null
	for poi in main.town_world.pois:
		if poi.id == "board": board_poi = poi; break
	main.town_world.travel_to_poi(board_poi)
	# 等待走到告示板交互半径内（near_poi 判定 3.6 米；headless 帧率高，帧数放宽）。
	var arrived := func() -> bool: return main.town_world.player_position.distance_to(board_poi.position) < 3.4
	await _wait_until(arrived, 3000)
	await _frames(10)
	var moved: float = main.town_world.player_position.distance_to(pos0)
	await _check("主城自由移动/寻路（%.1f 米）" % moved, moved > 5.0)
	main.town_world.interact_near()
	await _frames(5)
	var dialog_open: bool = main.ui.is_dialog_open()
	if dialog_open: main.ui.close_dialog()
	await _check("POI 交互弹窗", dialog_open)

	# 4. 多功能面板（背包/加点/任务/宠物）。
	main.ui.toggle_panel("bag")
	await _frames(2)
	var bag_ok: bool = main.ui.panels != null and main.ui.panels.visible and main.ui.panels._current == "bag"
	main.ui.toggle_panel("growth")
	await _frames(2)
	var growth_ok: bool = main.ui.panels._current == "growth"
	main.ui.toggle_panel("growth")
	await _frames(2)
	await _check("面板：背包/加点开合与互斥", bag_ok and growth_ok and not main.ui.panels.visible)

	# 5. 视角锁定切换 + 自定义参数（相对量断言：目标点 = 跟随目标 + 偏移）。
	var m1: String = main.camera_rig.toggle_lock()
	await _check("视角：V 键锁定切换（%s）" % m1, m1 == "lock")
	main.camera_rig.cam_offset = Vector2(1.5, 0.6)
	main.camera_rig.cam_dist = 17.0
	await _frames(120)  # 等平滑镜头追平移动后的跟随目标
	var fx: float = main.camera_rig.follow_node.global_position.x + main.camera_rig.cam_offset.x
	await _check("视角：自定义偏移生效（target.x=%.2f ≈ %.2f）" % [main.camera_rig._sm_target.x, fx],
		absf(main.camera_rig._sm_target.x - fx) < 0.6)
	main.camera_rig.toggle_lock()

	# 6. 进入地下城：三模式 AI 敌人 + 技能/蓝条。
	GameState.save.mp = float(GameState.total_stats().mp_max)
	main.change_scene(MODE_DUNGEON)
	await _wait_until(func(): return main.mode == MODE_DUNGEON, 400)
	await _frames(10)
	# depth 0 可能掷出 event/treasure 房（无敌人），重掷直至 combat 房。
	var retries := 0
	while main.dungeon_world.enemies.size() == 0 and retries < 6:
		main.dungeon_world.reset_dungeon()
		retries += 1
		await _frames(5)
	await _frames(10)
	var ai_ok := true
	for e in main.dungeon_world.enemies:
		if not Bestiary.AI_MODES.has(e.ai_mode): ai_ok = false
	await _check("地下城：敌人入场（%d 个）且 AI 模式合法" % main.dungeon_world.enemies.size(),
		main.dungeon_world.enemies.size() > 0 and ai_ok)
	var mp0: float = GameState.save.mp
	main.dungeon_world.cast_skill(0)
	await _frames(5)
	await _check("技能：释放消耗蓝条（%.0f→%.0f）" % [mp0, GameState.save.mp],
		GameState.save.mp < mp0 and main.dungeon_world.cooldowns[0] > 0.0)

	# 6.5 敌军小队：列阵 + 组合拳（怪物之间相互配合）。重掷到 2 人以上的房间，避开上一步技能的残留。
	retries = 0
	while main.dungeon_world.squad.get("members", []).size() < 2 and retries < 6:
		main.dungeon_world.reset_dungeon()
		retries += 1
		await _frames(5)
	await _wait_ms(700)
	var sq: Dictionary = main.dungeon_world.squad
	var mem: Array = sq.get("members", [])
	var placed := 0
	for e in mem:
		if e.squad_anchor != Vector3.ZERO: placed += 1
	await _check("敌军列阵（%s · %d 人 · 阵位已下发 %d）" % [
		String(Bestiary.SQUAD_FORMATIONS.get(sq.get("formation", ""), {}).get("name", "—")), mem.size(), placed],
		mem.size() >= 2 and placed == mem.size() and Bestiary.SQUAD_FORMATIONS.has(String(sq.get("formation", ""))))
	var before: int = main.dungeon_world.squad_combos
	var fired: bool = main.dungeon_world.force_squad_combo("volley")
	await _wait_ms(1500)
	await _check("组合拳：前摇→发动（累计 %d 次）" % main.dungeon_world.squad_combos,
		fired and main.dungeon_world.squad_combos >= before + 1)
	var stuck := 0
	for e in main.dungeon_world.squad.get("members", []):
		if e.combo_hold: stuck += 1
	await _check("组合拳：前摇结束已解除蓄势锁（残留 %d）" % stuck, stuck == 0)

	# 7. 清场：击杀全屋 → 金币掉落。
	var gold0: int = GameState.save.gold
	var pack: Array = [9999, false]
	for e in main.dungeon_world.enemies.duplicate():
		if not e.dead:
			main.dungeon_world._deal_to_enemy(e, pack)
	await _frames(15)
	var alive := 0
	for e in main.dungeon_world.enemies:
		if not e.dead: alive += 1
	await _check("地下城：清场（剩余 %d）+ 掉落金币（%d→%d）" % [alive, gold0, GameState.save.gold],
		alive == 0 and GameState.save.gold >= gold0)

	# 8. 终极技（第 4 主动，走 cast_skill(3)）。
	GameState.save.mp = float(GameState.total_stats().mp_max)
	main.dungeon_world.cooldowns = [0.0, 0.0, 0.0, 0.0]
	main.dungeon_world.cast_skill(3)
	await _frames(5)
	var ult_cast: bool = main.dungeon_world.cooldowns[3] > 0.0 or main.dungeon_world.player.has_meta("casting_ult")
	await _check("终极技：释放进入冷却", ult_cast)

	# 9. 撤离回城。
	main.dungeon_world.exit_dungeon()
	await _wait_until(func(): return main.mode == MODE_TOWN, 300)
	await _check("撤离回主城", main.mode == MODE_TOWN)

	# 10. 野外大地图：双地形 + 动物生态 + 火把。
	main.change_scene(MODE_OVERWORLD)
	await _wait_until(func(): return main.mode == MODE_OVERWORLD, 300)
	await _frames(10)
	await _check("野外：北山/南林生物群系",
		main.overworld.biome_at(Vector3(0, 0, -40)) == "mountain" and main.overworld.biome_at(Vector3(0, 0, 40)) == "forest")
	await _check("野外：动物已生成（%d 只）" % main.overworld.animals.size(), main.overworld.animals.size() > 0)
	# 火把：先从道具商视角补充库存（T 手持 / G 放置）。
	GameState.inventory.add(Items.stack_item("torch", 3))
	main.overworld.toggle_torch()
	await _check("火把：手持点亮", main.overworld.held_torch_node != null)
	main.overworld.place_torch()
	await _check("火把：放置光源（%d 处）" % main.overworld.placed_torches.size(), main.overworld.placed_torches.size() >= 1)

	# 11. 昼夜系统（10 分钟一轮）。
	GameState.day_time = 12.0
	var noon: float = GameState.day_factor()
	GameState.day_time = 0.0
	var midnight: float = GameState.night_factor()
	await _check("昼夜：正午/午夜因子", noon > 0.9 and midnight > 0.9)

	# 12. 存档。
	GameState.persist()
	await _check("存档写入 user://lost-abyss-save-v2.json",
		FileAccess.file_exists("user://lost-abyss-save-v2.json") or FileAccess.file_exists("user://lost-abyss-save-v1.json"))

	print("")
	print("========== SMOKE RESULT: %d passed, %d failed ==========" % [checks.size(), failures.size()])
	for f in failures:
		print("FAIL · " + f)
	get_tree().quit(1 if failures.size() > 0 else 0)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _wait_until(pred: Callable, max_frames: int) -> void:
	for i in max_frames:
		if pred.call():
			return
		await get_tree().process_frame

## 真实时间等待（headless 帧率极高，按帧计时不可靠，组合拳前摇/冷却需用毫秒等待）。
func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame

func _check(name: String, ok: bool) -> void:
	if ok:
		checks.append(name)
		print("PASS · " + name)
	else:
		failures.append(name)
		print("FAIL · " + name)
