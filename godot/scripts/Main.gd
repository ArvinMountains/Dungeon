extends Node3D
## Main scene controller. 对应 main.js 的场景切换、输入路由、渲染循环。

signal mode_changed(mode: String)
signal toast_message(text: String)

enum Mode { SELECTION, TOWN, DUNGEON }
var mode: Mode = Mode.SELECTION

var selection_world: SelectionWorld
var town_world: TownWorld
var dungeon_world: DungeonWorld
var camera_rig: CameraRig
var sky_dome: SkyDome
var ui: GameUI
var transition_rect: ColorRect
var transition_tween: Tween

var switching := false
var characters: Dictionary = {}  # id -> ProceduralCharacter

func _ready() -> void:
	_build_world()
	_build_ui()
	_apply_mode(Mode.SELECTION, true)
	if GameState.storage_notice != "":
		toast(GameState.storage_notice)

func _build_world() -> void:
	# Sky + lights (shared across worlds).
	sky_dome = SkyDome.new()
	add_child(sky_dome)
	# Worlds.
	selection_world = SelectionWorld.new()
	selection_world.name = "SelectionWorld"
	add_child(selection_world)
	town_world = TownWorld.new()
	town_world.name = "TownWorld"
	town_world.visible = false
	add_child(town_world)
	dungeon_world = DungeonWorld.new()
	dungeon_world.name = "DungeonWorld"
	dungeon_world.visible = false
	add_child(dungeon_world)
	for w: Node3D in [selection_world, town_world, dungeon_world]:
		w.main = self
	# Characters (both classes, only one visible at a time).
	for id in ["archer", "warrior"]:
		var c := ProceduralCharacter.new(id, 741)
		c.visible = id == GameState.save.selected
		characters[id] = c
	selection_world.add_child(characters["archer"])
	selection_world.add_child(characters["warrior"])
	for id in characters:
		characters[id].position = Vector3(0, 0.47, 0)
	# Camera rig.
	camera_rig = CameraRig.new()
	add_child(camera_rig)
	camera_rig.set_mode("selection")

func _build_ui() -> void:
	ui = load("res://ui/GameUI.tscn").instantiate()
	add_child(ui)
	ui.main = self
	ui.toast_requested.connect(func(t): toast(t))
	ui.late_init()
	# 世界 → UI/Main 信号接线。
	town_world.toast_requested.connect(toast)
	town_world.dialog_requested.connect(func(t, c, a, e): ui.open_dialog(t, c, a, e))
	town_world.hud_changed.connect(ui.refresh_hud)
	town_world.enter_dungeon_requested.connect(func(): change_scene(Mode.DUNGEON))
	town_world.enter_selection_requested.connect(func(): change_scene(Mode.SELECTION))
	dungeon_world.toast_requested.connect(toast)
	dungeon_world.dialog_requested.connect(func(t, c, a, e): ui.open_dialog(t, c, a, e))
	dungeon_world.hud_changed.connect(ui.refresh_hud)
	dungeon_world.exit_requested.connect(func(): change_scene(Mode.TOWN))
	mode_changed.connect(ui.set_mode)

func active_character() -> ProceduralCharacter:
	return characters[GameState.save.selected]

func toast(text: String) -> void:
	toast_message.emit(text)
	if ui: ui.show_toast(text)

func change_scene(new_mode: Mode) -> void:
	if new_mode == mode or switching: return
	switching = true
	# Fade transition.
	if ui:
		await ui.fade_transition()
	mode = new_mode
	# Move characters to the right world.
	var world: Node3D = selection_world
	var mode_str := "selection"
	if mode == Mode.TOWN:
		world = town_world; mode_str = "town"
	elif mode == Mode.DUNGEON:
		world = dungeon_world; mode_str = "dungeon"
	for id in characters:
		var c: ProceduralCharacter = characters[id]
		c.get_parent().remove_child(c)
		world.add_child(c)
		c.visible = id == GameState.save.selected
		c.set_opacity(1.0)
		c.scale = Vector3.ONE if mode == Mode.SELECTION else Vector3.ONE * 0.85
		if mode == Mode.TOWN:
			c.position = town_world.player_position
		elif mode == Mode.DUNGEON:
			c.position = dungeon_world.player_position
		else:
			c.position = Vector3(0, 0.47, 0)
	selection_world.visible = mode == Mode.SELECTION
	town_world.visible = mode == Mode.TOWN
	dungeon_world.visible = mode == Mode.DUNGEON
	camera_rig.set_mode(mode_str)
	camera_rig.follow_node = active_character() if mode != Mode.SELECTION else null
	if mode == Mode.DUNGEON:
		dungeon_world.reset_dungeon()
	if mode == Mode.TOWN:
		town_world.on_enter()
	mode_changed.emit(mode_str)
	switching = false
	if mode == Mode.TOWN: toast("欢迎来到灰烬庇护所。点击地面或使用 WASD 移动。")
	if mode == Mode.DUNGEON: toast("移动鼠标索敌 · 左键攻击 · Q 释放大招")

func _apply_mode(m: Mode, _init := false) -> void:
	mode = m

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		var ui_blocked: bool = ui != null and ui.is_dialog_open()
		if event is InputEventMouseButton:
			camera_rig.handle_mouse_button(event)
		elif event is InputEventMouseMotion:
			camera_rig.handle_mouse_motion(event, ui_blocked)
		# Click-to-move / attack.
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if ui_blocked: return
			if not camera_rig.was_click(): return
			if mode == Mode.TOWN:
				town_world.handle_click(camera_rig.camera)
			elif mode == Mode.DUNGEON:
				dungeon_world.handle_click(camera_rig.camera)
		if event is InputEventMouseMotion and mode == Mode.DUNGEON and not ui_blocked:
			dungeon_world.handle_hover(camera_rig.camera)

func _process(delta: float) -> void:
	sky_dome.update_from_time(GameState.day_time, GameState.day_factor(), GameState.night_factor(), GameState.horizon_factor())
	match mode:
		Mode.SELECTION:
			selection_world.update_selection(delta)
		Mode.TOWN:
			town_world.update_town(delta, camera_rig)
		Mode.DUNGEON:
			dungeon_world.update_dungeon(delta, camera_rig)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if ui and ui.is_dialog_open():
			ui.close_dialog()
		elif ui:
			ui.toggle_help()
		get_viewport().set_input_as_handled()
		return
	match mode:
		Mode.SELECTION:
			if event.is_action_pressed("class_1"): selection_world.request_class("archer")
			elif event.is_action_pressed("class_2"): selection_world.request_class("warrior")
		Mode.TOWN:
			if event.is_action_pressed("interact"): town_world.interact_near()
			elif event.is_action_pressed("use_potion"): use_potion()
			elif event.is_action_pressed("open_bag"): ui.show_inventory()
			elif event.is_action_pressed("open_map"): ui.show_map()
		Mode.DUNGEON:
			if event.is_action_pressed("attack"): dungeon_world.player_attack()
			elif event.is_action_pressed("ultimate"): dungeon_world.player_ultimate()
			elif event.is_action_pressed("use_potion"): use_potion()
			elif event.is_action_pressed("interact"): dungeon_world.exit_dungeon()

func use_potion() -> void:
	if GameState.save.hp >= 100:
		toast("生命充盈，无需消耗药剂。")
		return
	if GameState.save.potions <= 0:
		toast("没有生命药剂了，前往药剂商补给。")
		return
	GameState.add_potion(-1)
	GameState.set_hp(mini(100, GameState.save.hp + 35))
	AudioBus.play_tone(587, 0.3)
	toast("饮下生命药剂 · 恢复 35 点生命")
