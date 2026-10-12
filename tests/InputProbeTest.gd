extends Node
## 输入管线探针：用 Input.parse_input_event 走真实管线，
## 验证 ① 键盘动作能否触发面板 ② 点击 HUD 按钮是否穿透到世界行走。

var main: Node3D
var results: Array = []
var unhandled_keys: Array = []  # 诊断：_unhandled_input 是否收到按键

class KeySpy extends Node:
	var hits: Array = []
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed:
			hits.append(event.physical_keycode)

func _ready() -> void:
	var scene: PackedScene = load("res://scenes/Main.tscn")
	main = scene.instantiate()
	get_tree().root.add_child.call_deferred(main)
	await _frames(5)
	main.change_scene(main.Mode.TOWN)
	await _frames(40)  # 等转场结束

	# ---- 探针 0：诊断动作匹配与 _unhandled_input 通路 ----
	var spy := KeySpy.new()
	add_child(spy)
	var ev_match := InputEventKey.new()
	ev_match.physical_keycode = KEY_B
	ev_match.keycode = KEY_B
	ev_match.pressed = true
	var matched: bool = InputMap.event_is_action(ev_match, "open_bag")
	var has_act: bool = InputMap.has_action("open_bag")
	var ev_list: Array = InputMap.action_get_events("open_bag") if has_act else []
	var ev_desc := ""
	for e2 in ev_list:
		ev_desc += "%s phys=%s key=%s | " % [e2.get_class(), e2.physical_keycode, e2.keycode]
	results.append({"probe": "diag_action_match", "ok": matched, "detail": "has=%s events=[%s]" % [has_act, ev_desc]})
	spy.queue_free()
	await _frames(3)
	var bag_open: bool = false
	var p = main.ui.panels
	if p != null and p.current_panel() == "bag":
		bag_open = true
	results.append({"probe": "keyboard_B_bag", "ok": bag_open, "detail": "panels=%s" % (p.current_panel() if p else "null")})
	if p: p.toggle("bag")  # 还原
	await _frames(5)

	# ---- 探针 2：键盘 V 切换视角（有 toast 反馈）----
	var toast_before: String = _last_toast()
	_send_key(KEY_V)
	await _frames(10)
	results.append({"probe": "keyboard_V_lock", "ok": main.camera_rig.lock_mode, "detail": "toast=%s" % _last_toast()})
	_send_key(KEY_V)
	await _frames(5)

	# ---- 探针 3：点击 HUD「行囊 B」按钮是否穿透到世界行走 ----
	main.ui.show_inventory()  # 不行——直接点按钮。先关弹窗。
	main.ui.close_dialog()
	await _frames(5)
	# 找到 HUD 资源面板里的「行囊」按钮：遍历 hud_root 的按钮找文本。
	var btn := _find_button_by_text(main.ui.hud_root, "行囊")
	if btn == null:
		results.append({"probe": "hud_click_through", "ok": false, "detail": "按钮未找到"})
	else:
		var center: Vector2 = btn.get_global_rect().get_center()
		var walking_before: bool = main.town_world.has_move_target
		await _send_click(center)
		await _frames(15)
		var walked: bool = main.town_world.has_move_target or main.town_world.move_marker.visible
		var bag2: bool = main.ui.is_dialog_open()
		results.append({"probe": "hud_click_through", "ok": not walked, "detail": "walking=%s bag_dialog=%s before=%s" % [walked, bag2, walking_before]})
		if bag2: main.ui.close_dialog()

	# ---- 探针 4：POI 标签按钮点击（点击穿透同类问题）----
	var poi_btn := _find_button_by_text(main.ui.poi_label_root, "告示板")
	if poi_btn and poi_btn.visible:
		var center2: Vector2 = poi_btn.get_global_rect().get_center()
		await _send_click(center2)
		await _frames(15)
		var walked2: bool = main.town_world.has_move_target or main.town_world.move_marker.visible
		results.append({"probe": "poi_label_click", "ok": not walked2, "detail": "walking=%s" % walked2})
	else:
		results.append({"probe": "poi_label_click", "ok": true, "detail": "按钮不可见，跳过"})

	_finish()

func _last_toast() -> String:
	return main.ui.toast_label.text if main.ui.toast_label.visible else ""

func _send_key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	var ev2 := InputEventKey.new()
	ev2.physical_keycode = code
	ev2.keycode = code
	ev2.pressed = false
	Input.parse_input_event(ev2)

func _send_click(pos: Vector2) -> void:
	# 先发一次鼠标移动，确保 GUI 悬停状态刷新（与真实鼠标行为一致）。
	var mv := InputEventMouseMotion.new()
	mv.position = pos
	mv.global_position = pos
	Input.parse_input_event(mv)
	await get_tree().process_frame
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)
	var ev2 := InputEventMouseButton.new()
	ev2.button_index = MOUSE_BUTTON_LEFT
	ev2.pressed = false
	ev2.position = pos
	ev2.global_position = pos
	Input.parse_input_event(ev2)

func _find_button_by_text(root: Node, text: String) -> Button:
	if root is Button and root.text.contains(text):
		return root
	for c in root.get_children():
		var r := _find_button_by_text(c, text)
		if r: return r
	return null

func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame

func _finish() -> void:
	print("=== INPUT PROBE REPORT ===")
	var fails := 0
	for r in results:
		print("%s [%s] %s" % [r.probe, "PASS" if r.ok else "FAIL", r.detail])
		if not r.ok: fails += 1
	print("=== %d/%d PASS ===" % [results.size() - fails, results.size()])
	get_tree().quit(0 if fails == 0 else 1)
