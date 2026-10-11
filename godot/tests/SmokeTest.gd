extends Node
## Headless 冒烟测试：职业切换 → 进入主城 → A* 寻路 → 委托链 → 地下城战斗 → 大招 → 撤离 → 存档。
## 运行：godot --headless --path . res://tests/SmokeTest.tscn

const MODE_TOWN := 1
const MODE_DUNGEON := 2

var failures: Array[String] = []
var checks: Array[String] = []

func _ready() -> void:
	GameState.save = GameState.fresh_save()
	await get_tree().process_frame
	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(5)
	await _check("Main 就绪（世界+UI+相机）", main.selection_world != null and main.town_world != null and main.dungeon_world != null and main.ui != null and main.camera_rig != null)
	await _check("初始职业 archer", GameState.save.selected == "archer")

	# 1. 职业切换状态机（消散→凝聚→登场）
	main.selection_world.request_class("warrior")
	await _check("切换请求进入 fadingOut", main.selection_world.phase == "fadingOut")
	await _wait_until(func(): return GameState.save.selected == "warrior", 300)
	await _check("职业切换→warrior", GameState.save.selected == "warrior")
	await _wait_until(func(): return main.selection_world.phase != "fadingIn", 300)
	await _check("切换动画收尾", main.selection_world.phase == "idle" or main.selection_world.phase == "showcase")

	# 2. 进入主城
	main.change_scene(MODE_TOWN)
	await _wait_until(func(): return main.mode == MODE_TOWN, 300)
	await _check("进入主城", main.mode == MODE_TOWN)

	# 3. A* 寻路 + 点击行走
	var path: Array[Vector3] = main.town_world.pathfind(Vector3(0, 0, 3), Vector3(-8.9, 0, -3))
	await _check("A* 寻路返回路径", path.size() > 2)
	var pos0: Vector3 = main.town_world.player_position
	var target_poi = null
	for poi in main.town_world.pois:
		if poi.get("id", "") == "board":
			target_poi = poi
			break
	if target_poi == null and main.town_world.pois.size() > 0:
		target_poi = main.town_world.pois[0]
	main.town_world.travel_to_poi(target_poi)
	await _frames(90)
	var moved: float = main.town_world.player_position.distance_to(pos0)
	await _check("沿路径行走（移动 %.2f 米）" % moved, moved > 0.5)

	# 4. 委托链（状态逻辑）
	GameState.set_quest("active")
	for i in range(3):
		GameState.add_ember("ember%d" % i)
	await _check("余火 3/3", GameState.save.embers.size() == 3)
	GameState.set_quest("complete")
	GameState.add_gold(60)
	await _check("委托完成 +60 币（%d）" % GameState.save.gold, GameState.save.quest == "complete" and GameState.save.gold >= 60)

	# 5. 药剂 & 生命（fresh 存档自带 1 瓶药剂）
	var potions0: int = GameState.save.potions
	GameState.add_potion(1)
	GameState.set_hp(40)
	main.use_potion()
	await _check("药剂恢复（hp=%d，药剂 %d→%d）" % [GameState.save.hp, potions0 + 1, GameState.save.potions], GameState.save.hp == 75 and GameState.save.potions == potions0)

	# 6. 进入地下城
	main.change_scene(MODE_DUNGEON)
	await _wait_until(func(): return main.mode == MODE_DUNGEON and main.dungeon_world.enemies.size() > 0, 300)
	await _check("地下城部署 4 名低语者（%d）" % main.dungeon_world.enemies.size(), main.dungeon_world.enemies.size() == 4)

	# 7. 战斗：清空全部 4 名敌人 → 掉落金币 + 净化弹窗
	var gold0: int = GameState.save.gold
	for e in main.dungeon_world.enemies:
		if e.alive:
			main.dungeon_world.damage_enemy(e, 999, main.dungeon_world.player_position, 2.0)
	await _frames(10)
	var alive_count := 0
	for e in main.dungeon_world.enemies:
		if e.alive: alive_count += 1
	await _check("清场 +90 币（%d→%d，剩余敌人 %d）" % [gold0, GameState.save.gold, alive_count], alive_count == 0 and GameState.save.gold >= gold0 + 90)

	# 8. 大招
	var ult: bool = main.dungeon_world.player_ultimate()
	await _frames(40)
	await _check("大招释放（余烬震击）", ult and main.dungeon_world.ultimate_cooldown > 0)

	# 9. 撤离回城
	main.dungeon_world.exit_dungeon()
	await _wait_until(func(): return main.mode == MODE_TOWN, 300)
	await _check("撤离回城", main.mode == MODE_TOWN)

	# 10. 存档
	GameState.persist()
	await _check("存档写入 user://lost-abyss-save-v1.json", FileAccess.file_exists("user://lost-abyss-save-v1.json"))

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

func _check(name: String, ok: bool) -> void:
	if ok:
		checks.append(name)
		print("PASS · " + name)
	else:
		failures.append(name)
		print("FAIL · " + name)
