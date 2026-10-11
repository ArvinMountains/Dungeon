extends Node
## 渲染验证巡游：自动走完 职业选择→主城→地下城→大招，逐场景截图到 _explore/。
## 运行（非 headless）：godot --path . res://tests/DemoTour.tscn

const OUT_DIR := "E:/个人文件/各类尝试/Dungeon Game/_explore"
const MODE_TOWN := 1
const MODE_DUNGEON := 2

func _ready() -> void:
	GameState.save = GameState.fresh_save()
	await _frames(5)
	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(45)
	await _shot("1_selection_archer")

	main.selection_world.request_class("warrior")
	await _wait_until(func(): return GameState.save.selected == "warrior", 400)
	await _frames(45)
	await _shot("2_selection_warrior")

	main.change_scene(MODE_TOWN)
	await _wait_until(func(): return main.mode == MODE_TOWN, 400)
	await _frames(40)
	var target = null
	for poi in main.town_world.pois:
		if poi.get("id", "") == "board":
			target = poi
			break
	if target:
		main.town_world.travel_to_poi(target)
	await _frames(150)
	await _shot("3_town")

	main.change_scene(MODE_DUNGEON)
	await _wait_until(func(): return main.mode == MODE_DUNGEON, 400)
	await _frames(50)
	var nearest = main.dungeon_world.nearest_enemy(999.0, false)
	if nearest:
		main.dungeon_world.lock_enemy(nearest)
	await _frames(20)
	await _shot("4_dungeon_locked")

	main.dungeon_world.player_ultimate()
	await _frames(26)
	await _shot("5_ultimate")

	await _frames(30)
	get_tree().quit()

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
