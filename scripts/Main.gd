extends Node3D
## Main 场景总控：职业选择 / 主城 / 地下城 / 野外大地图 四世界切换、
## 输入路由、昼夜驱动（SkyDome）、视角模式切换（V）、面板快捷键（B/M/K/J/P）。

signal mode_changed(mode: String)
signal toast_message(text: String)

enum Mode { SELECTION, TOWN, DUNGEON, OVERWORLD }
var mode: Mode = Mode.SELECTION

var selection_world: SelectionWorld
var town_world: TownWorld
var dungeon_world: DungeonWorld
var overworld: Overworld
var camera_rig: CameraRig
var sky_dome: SkyDome
var ui: GameUI

var switching := false

func _ready() -> void:
	_build_world()
	_build_ui()
	_apply_mode(Mode.SELECTION, true)
	if GameState.storage_notice != "":
		toast(GameState.storage_notice)

## 每帧驱动当前世界的 update 与全局蓝条回复。
func _process(delta: float) -> void:
	if switching: return
	match mode:
		Mode.SELECTION: selection_world.update_selection(delta)
		Mode.TOWN: town_world.update_town(delta, camera_rig)
		Mode.DUNGEON: dungeon_world.update_dungeon(delta, camera_rig)
		Mode.OVERWORLD: overworld.update_overworld(delta, camera_rig)
	GameState.regen_mp(delta)
	# 昼夜光照/大气每帧演进（此前 SkyDome 从未被驱动，天空恒为初值）。
	sky_dome.update_from_time(GameState.day_time, GameState.day_factor(), GameState.night_factor(), GameState.horizon_factor())

func _build_world() -> void:
	sky_dome = SkyDome.new()
	add_child(sky_dome)
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
	overworld = Overworld.new()
	overworld.name = "Overworld"
	overworld.visible = false
	add_child(overworld)
	for w: Node3D in [selection_world, town_world, dungeon_world, overworld]:
		w.main = self
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
	town_world.enter_overworld_requested.connect(func(): change_scene(Mode.OVERWORLD))
	town_world.enter_selection_requested.connect(func(): change_scene(Mode.SELECTION))
	dungeon_world.toast_requested.connect(toast)
	dungeon_world.dialog_requested.connect(func(t, c, a, e): ui.open_dialog(t, c, a, e))
	dungeon_world.hud_changed.connect(ui.refresh_hud)
	dungeon_world.exit_requested.connect(func(): change_scene(Mode.TOWN))
	overworld.toast_requested.connect(toast)
	overworld.dialog_requested.connect(func(t, c, a, e): ui.open_dialog(t, c, a, e))
	overworld.hud_changed.connect(ui.refresh_hud)
	overworld.exit_requested.connect(func(): change_scene(Mode.TOWN))
	GameState.toast_requested.connect(toast)  # autoload 的升级/任务/宠物提示此前从未接线，屏幕上不可见
	selection_world.toast_requested.connect(toast)
	mode_changed.connect(ui.set_mode)

## 当前世界的玩家实体（药剂/相机跟随用）。
func active_player() -> Actor:
	match mode:
		Mode.TOWN: return town_world.player
		Mode.DUNGEON: return dungeon_world.player
		Mode.OVERWORLD: return overworld.player
	return null

var _toast_last_text := ""
var _toast_last_ms := -1000000

## 全局 toast 唯一出口：同文案 300ms 窗口内去重（连点/轮询施法时"技能冷却中"等
## 提示会以每秒数十次的频率重发，此前一轮回归累计 5.6 万条，纯浪费 UI 驱动）。
func toast(text: String) -> void:
	var now := Time.get_ticks_msec()
	if text == _toast_last_text and now - _toast_last_ms < 300:
		_toast_last_ms = now  # 刷新窗口：消息流持续期间只算一条
		return
	_toast_last_text = text
	_toast_last_ms = now
	toast_message.emit(text)
	if ui: ui.show_toast(text)

func change_scene(new_mode: Mode) -> void:
	if new_mode == mode or switching: return
	switching = true
	if ui:
		await ui.fade_transition()
	mode = new_mode
	var mode_str := "selection"
	var follow: Node3D = null
	match mode:
		Mode.TOWN:
			mode_str = "town"
			follow = town_world.player
			town_world.on_enter()
		Mode.DUNGEON:
			mode_str = "dungeon"
			follow = dungeon_world.player
			dungeon_world.reset_dungeon()
		Mode.OVERWORLD:
			mode_str = "overworld"
			follow = overworld.player
			overworld.sync_player()  # 血量接续存档（野外此前用基础 30 血，与存档脱节）
		_:
			follow = null
	selection_world.visible = mode == Mode.SELECTION
	town_world.visible = mode == Mode.TOWN
	dungeon_world.visible = mode == Mode.DUNGEON
	overworld.visible = mode == Mode.OVERWORLD
	camera_rig.set_mode(mode_str)
	camera_rig.follow_node = follow
	camera_rig.lock_mode = false
	sky_dome.set_interior(mode == Mode.DUNGEON)  # 地下城转入室内光照氛围
	mode_changed.emit(mode_str)
	switching = false
	if mode == Mode.TOWN: toast("欢迎回到灰烬庇护所。WASD 自由移动，E 与建筑/NPC 交互。")
	if mode == Mode.DUNGEON: toast("左键锁定/移动 · 数字键 1-4 技能 · 按住 R 防御/格挡 · F 药剂 · V 切换视角")
	if mode == Mode.OVERWORLD: toast("野外大地图：北方山地 / 南方森林。按住 R 可挡下野兽扑击，残血动物用捕网（E）驯服。")

func _apply_mode(m: Mode, _init := false) -> void:
	mode = m

# ---------------- 输入 ----------------
var _press_over_ui := false  # 本次左键按下时指针是否位于 HUD 控件上（防点击穿透）

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		var ui_blocked: bool = ui != null and ui.is_dialog_open()
		if event is InputEventMouseButton:
			if event.pressed:
				# 按下瞬间取当前 GUI 悬停靠件：落在按钮/面板上则本次点击不作用于世界。
				_press_over_ui = get_viewport().gui_get_hovered_control() != null
			camera_rig.handle_mouse_button(event)
		elif event is InputEventMouseMotion:
			camera_rig.handle_mouse_motion(event, ui_blocked)
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if _press_over_ui or ui_blocked or not camera_rig.was_click(): return
			if mode == Mode.TOWN:
				town_world.handle_click(camera_rig.camera, event.position)
			elif mode == Mode.DUNGEON:
				dungeon_world.handle_click(camera_rig.camera, event.position)
			elif mode == Mode.OVERWORLD:
				overworld.handle_click(camera_rig.camera, event.position)
		if event is InputEventMouseMotion and mode == Mode.DUNGEON and not ui_blocked:
			dungeon_world.handle_hover(camera_rig.camera, event.position)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if ui and ui.is_dialog_open():
			ui.close_dialog()
		elif ui:
			ui.toggle_help()
		get_viewport().set_input_as_handled()
		return
	# 全局：视角锁定切换。
	if event.is_action_pressed("camera_lock"):
		var m := camera_rig.toggle_lock()
		toast("视角切换：%s" % ("锁定角色" if m == "lock" else "自由跟随"))
		return
	if ui and ui.is_dialog_open():
		return  # 弹窗期间屏蔽世界操作
	# 组队指挥（城镇/野外/地下城通用）：X 阵型 / C 集火 / Z 待命。
	if mode != Mode.SELECTION:
		if event.is_action_pressed("party_formation"):
			var f := GameState.cycle_formation()
			var fdef: Dictionary = NpcBook.FORMATIONS.get(f, {})
			toast("阵型：%s —— %s" % [fdef.get("name", f), fdef.get("desc", "")])
			return
		if event.is_action_pressed("party_focus"):
			GameState.order_focus()
			toast("集火！同伴将扑向你锁定的目标（5 秒）。")
			return
		if event.is_action_pressed("party_hold"):
			var held := GameState.order_hold_toggle()
			toast("同伴待命。" if held else "同伴恢复跟随。")
			return
	match mode:
		Mode.SELECTION:
			if event.is_action_pressed("class_1"): selection_world.request_class("archer")
			elif event.is_action_pressed("class_2"): selection_world.request_class("warrior")
			elif event.is_action_pressed("class_3"): selection_world.request_class("shield")
			elif event.is_action_pressed("class_4"): selection_world.request_class("assassin")
			elif event.is_action_pressed("class_5"): selection_world.request_class("mage")
		Mode.TOWN:
			if event.is_action_pressed("interact"): town_world.interact_near()
			elif event.is_action_pressed("use_potion"): use_potion()
			elif event.is_action_pressed("open_bag"): ui.toggle_panel("bag")
			elif event.is_action_pressed("open_map"): ui.toggle_panel("map")
			elif event.is_action_pressed("panel_growth"): ui.toggle_panel("growth")
			elif event.is_action_pressed("panel_quest"): ui.toggle_panel("quests")
			elif event.is_action_pressed("panel_pet"): ui.toggle_panel("pets")
		Mode.DUNGEON:
			if event.is_action_pressed("attack"): dungeon_world.player_attack()
			elif event.is_action_pressed("use_potion"): use_potion()
			elif event.is_action_pressed("interact"): dungeon_world.interact()
			elif event.is_action_pressed("torch_hold"): dungeon_world.toggle_torch()
			elif event.is_action_pressed("torch_place"): dungeon_world.place_torch()
			elif event.is_action_pressed("open_bag"): ui.toggle_panel("bag")
			elif event.is_action_pressed("panel_quest"): ui.toggle_panel("quests")
		Mode.OVERWORLD:
			if event.is_action_pressed("attack"): overworld.player_attack()
			elif event.is_action_pressed("interact"): overworld.interact()
			elif event.is_action_pressed("use_potion"): use_potion()
			elif event.is_action_pressed("torch_hold"): overworld.toggle_torch()
			elif event.is_action_pressed("torch_place"): overworld.place_torch()
			elif event.is_action_pressed("open_bag"): ui.toggle_panel("bag")

# ---------------- 药剂 ----------------
func use_potion() -> void:
	if GameState.save.potions <= 0:
		toast("没有生命药剂了，前往道具商家补给。")
		return
	var heal := 35
	match mode:
		Mode.TOWN, Mode.SELECTION:
			var cap := int(GameState.total_stats().hp_max)
			if GameState.save.hp >= cap:
				toast("生命充盈，无需消耗药剂。")
				return
			GameState.add_potion(-1)
			GameState.set_hp(mini(cap, GameState.save.hp + heal))
		_:
			var a := active_player()
			if a == null or a.hp >= a.hp_max:
				toast("生命充盈，无需消耗药剂。")
				return
			GameState.add_potion(-1)
			a.heal(heal)
			GameState.set_hp(a.hp)
	AudioBus.play_tone(587, 0.3)
	toast("饮下生命药剂 · 恢复 %d 点生命" % heal)
