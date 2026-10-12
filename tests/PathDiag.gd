extends Node
## 寻路诊断：主城内依次 travel_to_poi 四个远处 POI，逐步打印玩家位置快照与真实位置。
## 定位 PlaythroughTest 中 apothecary/abyss_gate 寻路超时的根因。

const MODE_TOWN := 1

var tw = null

func _ready() -> void:
	GameState.save = GameState.fresh_save()
	await _frames(5)
	var main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(40)
	tw = main.town_world
	main.selection_world.request_class("warrior")
	await _wait_until(func() -> bool: return GameState.save.selected == "warrior", 400)
	main.change_scene(MODE_TOWN)
	await _wait_until(func() -> bool: return main.mode == MODE_TOWN, 400)
	await _frames(20)

	for id in ["board", "apothecary", "abyss_gate", "east_gate"]:
		var poi = null
		for p in tw.pois:
			if p.id == id: poi = p; break
		var target: Vector3 = poi.position + Vector3(0, 0, 3.0)
		print("[DIAG] → %s 目标 %s" % [id, target])
		tw.travel_to_poi(poi)
		var guard := 0
		while guard < 4500:
			guard += 1
			if guard % 300 == 0:
				print("[DIAG]   it=%d 快照=%s 真实=%s has_target=%s move_target=%s" % [
					guard, tw.player_position, tw.player.global_position, tw.has_move_target, tw.move_target])
			if tw.player_position.distance_to(target) < 1.2:
				break
			await _frames(1)
		tw.has_move_target = false
		var ok: bool = tw.player_position.distance_to(target) < 1.2
		print("[DIAG] %s %s（it=%d，近POI=%s，玩家-POI距离=%.1f）" % [id,
			"到达" if ok else "超时", guard,
			str(tw.near_poi.get("id", "无") if tw.near_poi != null else "无"),
			tw.player.global_position.distance_to(poi.position)])
		await _frames(5)
	print("[DIAG] DONE")
	get_tree().quit()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _wait_until(pred: Callable, max_frames: int) -> void:
	for i in max_frames:
		if pred.call():
			return
		await get_tree().process_frame
