class_name GameUI
extends Control
## 全部 2D 界面：职业选择面板、主城 HUD（委托/资源/POI 标签/时钟）、
## 地下城 HUD（敌人数/血条/大招）、对话弹窗、背包、地图、帮助、Toast、命中闪红、转场。
## 对应原 index.html + main.js UI 部分。

signal toast_requested(text: String)

var main = null

# ---- 面板 ----
var selection_panel: PanelContainer
var town_panel: Control
var dungeon_panel: Control
var poi_label_root: Control

# ---- 选择面板控件 ----
var class_cards := {}
var anim_status: Label
var class_desc: Label
var trait_desc: Label
var stat_bars := {}
var stat_values := {}

# ---- 全局 HUD（小地图 + 资源，城镇/野外/地下城通用） ----
var hud_root: Control
var minimap: UIMinimap
var res_panel: PanelContainer

# ---- 任务追踪（HUD 左下） ----
var quest_track: PanelContainer
var _qt_title: Label
var _qt_meta: Label
var _qt_desc: Label
var _qt_progress: Label
var _qt_bar: ColorRect
var _qt_reward: Label
var _qt_action: Button
var _qt_marker: Label

# ---- 主城 HUD ----
var gold_label: Label
var diamond_label: Label
var potion_label: Label
var guard_status: Label
var health_bar: ColorRect
var health_ghost: ColorRect
var health_text: Label
var mp_text: Label
var clock_label: Label
var interact_prompt: Label
var poi_labels := {}   # poi id -> Button
var _hp_ghost := 1.0
var _hp_hold := 0.0

# ---- 地下城 HUD ----
var enemy_count: Label
var dungeon_health_bar: ColorRect
var dungeon_health_text: Label
var dungeon_potion_label: Label
var ultimate_name: Label
var ultimate_cooldown: Label
var ultimate_button: Button
var _party_hint: Label
var _enemy_hint: Label

# ---- 全局 ----
var toast_label: Label
var toast_tween: Tween
var hit_flash_rect: ColorRect
var transition_rect: ColorRect
var footer_place: Label

# ---- 多功能面板（背包/加点/任务/宠物，Panels.gd） ----
var panels: UIPanels = null

# ---- 弹窗 ----
var modal: PanelContainer
var modal_dim: ColorRect
var modal_eyebrow: Label
var modal_title: Label
var modal_content: RichTextLabel
var modal_actions: VBoxContainer

const COL_BG := UiKit.BG
const COL_BORDER := UiKit.BORDER
const COL_GOLD := UiKit.GOLD
const COL_TEXT := UiKit.TEXT
const COL_DIM := UiKit.TEXT_DIM

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_overlays()
	_build_hud_layer()
	_build_selection_panel()
	_build_town_hud()
	_build_dungeon_hud()
	_build_modal()
	set_mode("selection")

func late_init() -> void:
	# main 已赋值后调用：连接信号、构建 POI 标签。
	GameState.gold_changed.connect(func(_v): refresh_hud())
	GameState.hp_changed.connect(func(_v): refresh_hud())
	GameState.potions_changed.connect(func(_v): refresh_hud())
	GameState.quest_changed.connect(func(): refresh_hud())
	GameState.quests_changed.connect(func(): refresh_hud())
	GameState.embers_changed.connect(func(): refresh_hud())
	if main.town_world:
		main.town_world.dialog_closed.connect(close_dialog)
		main.dungeon_world.dialog_closed.connect(close_dialog)
		main.dungeon_world.hit_flash.connect(flash_hit)
		_build_poi_labels()
	refresh_hud()

func set_mode(mode: String) -> void:
	selection_panel.visible = mode == "selection"
	town_panel.visible = mode == "town"
	dungeon_panel.visible = mode == "dungeon"
	poi_label_root.visible = mode == "town"
	# 一级常驻 HUD（小地图 + 资源）在城镇/野外/地下城都显示；选人界面留白。
	if hud_root: hud_root.visible = mode != "selection"
	if mode == "town": footer_place.text = "灰烬庇护所 · 本地存档"
	elif mode == "dungeon": footer_place.text = "废弃圣堂 · 第一关"
	elif mode == "overworld": footer_place.text = "荒野 · 北山与南林"
	else: footer_place.text = "遗忘圣堂"
	if mode != "town": interact_prompt.visible = false
	# 任务追踪条：城镇与野外常驻（地下城让位给战斗 HUD）。
	if quest_track: quest_track.visible = mode == "town" or mode == "overworld"
	# 小地图跟随当前世界。
	if main and minimap:
		var w = null
		match mode:
			"town": w = main.town_world
			"dungeon": w = main.dungeon_world
			"overworld": w = main.overworld
		minimap.bind(w)
	refresh_hud()

# ---------------- 构建工具 ----------------

func _mk_panel() -> PanelContainer:
	return UiKit.panel(COL_BG, COL_BORDER, UiKit.S3)

func _mk_label(text: String, size: int, color := COL_TEXT) -> Label:
	return UiKit.label(text, size, color)

func _mk_button(text: String, cb: Callable, accent := false) -> Button:
	return UiKit.button(text, cb, accent, UiKit.F_BODY)

func _vs(height: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, height)
	return s

# ---------------- 覆盖层 ----------------

func _build_overlays() -> void:
	hit_flash_rect = ColorRect.new()
	hit_flash_rect.color = Color(0.75, 0.1, 0.05, 0.0)
	hit_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hit_flash_rect)

	toast_label = _mk_label("", 15, Color(0.92, 0.88, 0.76))
	toast_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast_label.anchor_top = 0.76
	toast_label.anchor_bottom = 0.76
	toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var toast_sb := StyleBoxFlat.new()
	toast_sb.bg_color = Color(0.05, 0.07, 0.06, 0.88)
	toast_sb.border_color = COL_BORDER
	toast_sb.set_border_width_all(1)
	toast_sb.set_corner_radius_all(3)
	toast_sb.content_margin_left = 16; toast_sb.content_margin_right = 16
	toast_sb.content_margin_top = 8; toast_sb.content_margin_bottom = 8
	toast_label.add_theme_stylebox_override("normal", toast_sb)
	toast_label.visible = false
	add_child(toast_label)

	transition_rect = ColorRect.new()
	transition_rect.color = Color(0.02, 0.03, 0.02, 0.0)
	transition_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(transition_rect)

	footer_place = UiKit.label("遗忘圣堂", UiKit.F_TINY, UiKit.TEXT_MUTE)
	footer_place.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	footer_place.anchor_left = 1.0
	footer_place.anchor_right = 1.0
	footer_place.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	footer_place.position = Vector2(-12, -26)
	footer_place.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(footer_place)

func show_toast(text: String) -> void:
	toast_label.text = text
	toast_label.visible = true
	toast_label.modulate.a = 1.0
	if toast_tween: toast_tween.kill()
	toast_tween = create_tween()
	toast_tween.tween_interval(2.4)
	toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.7)
	toast_tween.tween_callback(func(): toast_label.visible = false)

func flash_hit() -> void:
	hit_flash_rect.color.a = 0.28
	var tw := create_tween()
	tw.tween_property(hit_flash_rect, "color:a", 0.0, 0.22)

func fade_transition() -> void:
	transition_rect.color.a = 0.0
	transition_rect.visible = true
	var tw := create_tween()
	tw.tween_property(transition_rect, "color:a", 1.0, 0.22)
	tw.tween_interval(0.12)
	tw.tween_property(transition_rect, "color:a", 0.0, 0.24)
	await tw.finished
	transition_rect.visible = false

# ---------------- 职业选择面板 ----------------

func _build_selection_panel() -> void:
	selection_panel = _mk_panel()
	selection_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	selection_panel.anchor_left = 0.03
	selection_panel.anchor_top = 0.06
	selection_panel.anchor_bottom = 0.94
	selection_panel.anchor_right = 0.03
	selection_panel.custom_minimum_size = Vector2(320, 0)
	selection_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	selection_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(selection_panel)
	var v := VBoxContainer.new()
	selection_panel.add_child(v)

	v.add_child(_mk_label("FORGED IN ASHES", 11, COL_DIM))
	v.add_child(_mk_label("失落的深渊", 26, COL_GOLD))
	v.add_child(_mk_label("THE LOST ABYSS · 2.5D", 11, COL_DIM))
	v.add_child(_vs(10))

	for id in ["archer", "warrior", "shield", "assassin", "mage"]:
		var data: Dictionary = GameState.CLASS_DATA[id]
		var card := Button.new()
		card.add_theme_font_size_override("font_size", 14)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.09, 0.12, 0.10)
		sb.border_color = Color(0.25, 0.26, 0.20)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 10; sb.content_margin_right = 10
		sb.content_margin_top = 8; sb.content_margin_bottom = 8
		var sb_sel := sb.duplicate()
		sb_sel.bg_color = Color(0.14, 0.18, 0.13)
		sb_sel.border_color = COL_GOLD
		sb_sel.set_border_width_all(2)
		card.add_theme_stylebox_override("normal", sb)
		card.add_theme_stylebox_override("hover", sb_sel)
		card.add_theme_stylebox_override("pressed", sb_sel)
		card.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var cv := VBoxContainer.new()
		var name_row := HBoxContainer.new()
		name_row.add_child(_mk_label(data.name, 17, COL_GOLD))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_row.add_child(spacer)
		name_row.add_child(_mk_label(" ".join(data.tags), 11, COL_DIM))
		cv.add_child(name_row)
		card.add_child(cv)
		card.custom_minimum_size = Vector2(0, 52)
		card.pressed.connect(func(): main.selection_world.request_class(id))
		class_cards[id] = {"card": card, "normal": sb, "selected": sb_sel}
		v.add_child(card)
		v.add_child(_vs(4))

	v.add_child(_vs(6))
	class_desc = _mk_label("", 13)
	class_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(class_desc)
	v.add_child(_vs(8))
	# 三维属性。
	var stat_names := {"strength": "力量", "agility": "敏捷", "resilience": "坚韧"}
	for key in stat_names:
		var row := HBoxContainer.new()
		row.add_child(_mk_label(stat_names[key], 12, COL_DIM))
		row.custom_minimum_size = Vector2(0, 16)
		var bar_bg := ColorRect.new()
		bar_bg.color = Color(0.13, 0.15, 0.12)
		bar_bg.custom_minimum_size = Vector2(120, 6)
		bar_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bar := ColorRect.new()
		bar.color = COL_GOLD
		bar.custom_minimum_size = Vector2(0, 6)
		bar_bg.add_child(bar)
		row.add_child(bar_bg)
		var val := _mk_label("00", 12, COL_TEXT)
		row.add_child(val)
		v.add_child(row)
		stat_bars[key] = bar
		stat_values[key] = val
	v.add_child(_vs(8))
	v.add_child(_mk_label("特质", 11, COL_DIM))
	v.add_child(_mk_label("", 14, COL_GOLD))
	v.add_child(_vs(2))
	trait_desc = _mk_label("", 12, COL_DIM)
	trait_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(trait_desc)
	var spacer2 := Control.new()
	spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer2)
	anim_status = _mk_label("待机 · 呼吸", 12, COL_DIM)
	v.add_child(anim_status)
	v.add_child(_vs(6))
	var replay := _mk_button("重现仪式", func():
		if main.selection_world.has_method("start_showcase"):
			main.selection_world.start_showcase())
	v.add_child(replay)
	v.add_child(_vs(4))
	var enter := _mk_button("步入灰烬庇护所 →", func(): main.change_scene(main.Mode.TOWN), true)
	v.add_child(enter)
	refresh_class_ui()

func refresh_class_ui() -> void:
	var data: Dictionary = GameState.class_data()
	class_desc.text = data.description
	trait_desc.text = data.motto
	for id in class_cards:
		var sel: bool = id == GameState.save.selected
		class_cards[id].card.add_theme_stylebox_override("normal", class_cards[id].selected if sel else class_cards[id].normal)
	var keys := ["strength", "agility", "resilience"]
	for i in range(3):
		var key: String = keys[i]
		stat_bars[key].custom_minimum_size.x = 120.0 * data.stats[i] / 5.0
		stat_values[key].text = "%02d" % data.stats[i]

# ---------------- 全局 HUD（小地图 + 资源） ----------------

## 三个世界通用的一级常驻信息：左上小地图、右上资源与快捷入口。
func _build_hud_layer() -> void:
	hud_root = Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud_root)

	# 左上：小地图。
	var mm_frame := UiKit.panel(UiKit.BG, UiKit.BORDER, UiKit.S1)
	mm_frame.position = Vector2(12, 12)
	mm_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_root.add_child(mm_frame)
	minimap = UIMinimap.new()
	minimap.custom_minimum_size = Vector2(150, 150)
	minimap.mark_clicked.connect(_on_minimap_click)
	mm_frame.add_child(minimap)

	# 右上：资源与快捷入口。
	res_panel = UiKit.panel()
	res_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	res_panel.anchor_left = 1.0
	res_panel.anchor_right = 1.0
	res_panel.offset_left = -212
	res_panel.offset_right = -12
	res_panel.offset_top = 12
	res_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	res_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_root.add_child(res_panel)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", int(UiKit.S1))
	res_panel.add_child(rv)
	clock_label = UiKit.label("08:00 ☀ 清晨", UiKit.F_SMALL, UiKit.GOLD)
	rv.add_child(clock_label)
	# 生命条（含伤害延迟层）。
	var hp_row := HBoxContainer.new()
	var hp_box := Control.new()
	hp_box.custom_minimum_size = Vector2(124, 11)
	health_ghost = ColorRect.new()
	health_ghost.color = UiKit.HP_GHOST
	health_ghost.size = Vector2(124, 11)
	hp_box.add_child(health_ghost)
	health_bar = ColorRect.new()
	health_bar.color = UiKit.HP
	health_bar.size = Vector2(124, 11)
	hp_box.add_child(health_bar)
	hp_row.add_child(hp_box)
	hp_row.add_child(UiKit.spacer(UiKit.S1, 0))
	health_text = UiKit.label("100 / 100", UiKit.F_TINY, UiKit.TEXT_DIM)
	hp_row.add_child(health_text)
	rv.add_child(hp_row)
	# 法力 / 货币 / 药剂。
	rv.add_child(_stat_row("法力", func() -> Label:
		mp_text = UiKit.label("0 / 0", UiKit.F_SMALL, UiKit.MP)
		return mp_text))
	rv.add_child(_stat_row("余烬币", func() -> Label:
		gold_label = UiKit.label("0", UiKit.F_LABEL, UiKit.GOLD)
		return gold_label))
	rv.add_child(_stat_row("钻石", func() -> Label:
		diamond_label = UiKit.label("0", UiKit.F_SMALL, Color(0.72, 0.82, 0.92))
		return diamond_label))
	rv.add_child(_stat_row("生命药剂", func() -> Label:
		potion_label = UiKit.label("0", UiKit.F_SMALL, Color(0.85, 0.55, 0.45))
		return potion_label))
	# 防御状态（按住 R）。
	guard_status = UiKit.label("按住 R 防御 · 招架窗口内可完美格挡", UiKit.F_TINY, UiKit.TEXT_MUTE)
	rv.add_child(guard_status)
	# 快捷入口。
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", int(UiKit.S1))
	btn_row.add_child(UiKit.button("行囊", func(): toggle_panel("bag")))
	btn_row.add_child(UiKit.button("任务", func(): toggle_panel("quests")))
	btn_row.add_child(UiKit.button("地图", func(): show_map()))
	btn_row.add_child(UiKit.button("药剂", func(): main.use_potion()))
	btn_row.add_child(UiKit.button("帮助", func(): toggle_help()))
	rv.add_child(btn_row)

## 「标签 —— 数值」行；make 返回数值 Label，便于外部刷新。
func _stat_row(name: String, make: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(UiKit.label(name, UiKit.F_TINY, UiKit.TEXT_MUTE))
	row.add_child(UiKit.hspacer())
	row.add_child(make.call())
	return row

## 左下：任务追踪条（当前追踪任务的一句话目标 + 计数 + 奖励 + 下一步动作）。
func _build_quest_tracker() -> void:
	quest_track = UiKit.panel(UiKit.BG, UiKit.BORDER, UiKit.S3)
	quest_track.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	quest_track.anchor_top = 1.0
	quest_track.anchor_bottom = 1.0
	quest_track.offset_left = 12
	quest_track.offset_top = -184
	quest_track.grow_vertical = Control.GROW_DIRECTION_BEGIN
	quest_track.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_root.add_child(quest_track)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(UiKit.S1))
	quest_track.add_child(v)
	v.add_child(UiKit.section("任务 · 追踪"))
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 2)
	_qt_marker = UiKit.label("▌", UiKit.F_SMALL, UiKit.GOLD)
	title_row.add_child(_qt_marker)
	_qt_title = UiKit.label("", UiKit.F_LABEL, UiKit.GOLD)
	title_row.add_child(_qt_title)
	title_row.add_child(UiKit.hspacer())
	_qt_meta = UiKit.label("", UiKit.F_TINY, UiKit.TEXT_MUTE)
	title_row.add_child(_qt_meta)
	v.add_child(title_row)
	_qt_desc = UiKit.label("", UiKit.F_SMALL, UiKit.TEXT)
	_qt_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_qt_desc.custom_minimum_size = Vector2(252, 0)
	v.add_child(_qt_desc)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", int(UiKit.S2))
	var bar := UiKit.bar(168, 6, UiKit.GOLD_DIM)
	prow.add_child(bar.bg)
	_qt_bar = bar.fill
	_qt_progress = UiKit.label("", UiKit.F_SMALL, UiKit.TEXT_DIM)
	prow.add_child(_qt_progress)
	v.add_child(prow)
	_qt_reward = UiKit.label("", UiKit.F_TINY, UiKit.TEXT_MUTE)
	v.add_child(_qt_reward)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", int(UiKit.S1))
	_qt_action = UiKit.button("前往告示板 →", func(): _quest_track_primary())
	brow.add_child(_qt_action)
	brow.add_child(UiKit.button("任务日志", func(): toggle_panel("quests")))
	v.add_child(brow)

## 追踪条主按钮：城镇内可领赏/寻路；其它场景打开任务日志（空状态必有下一步）。
func _quest_track_primary() -> void:
	if main == null or main.mode != main.Mode.TOWN:
		toggle_panel("quests")
		return
	var info: Dictionary = GameState.tracked_info()
	if not info.is_empty() and bool(info.claimable):
		if GameState.claim_quest(String(info.kind), String(info.id)):
			if main: main.toast("奖励到手：%s" % String(info.reward))
		return
	_quest_track_guide()

## 寻路到接取/领奖点。
func _quest_track_guide() -> void:
	if main == null or main.town_world == null: return
	var info: Dictionary = GameState.tracked_info()
	var poi_id := "board"
	if not info.is_empty() and String(info.get("giver", "")) == "guild":
		poi_id = "guild"
	main.town_world.travel_to_poi(main.town_world._poi_by_id(poi_id))

func _on_minimap_click(id: String) -> void:
	if main == null: return
	if main.mode == main.Mode.TOWN and main.town_world:
		main.town_world.poi_icon_clicked(id)
	elif id == "camp" and main.overworld:
		main.overworld.move_target = Vector3(-main.overworld.WORLD_R + 7.0, 0, 0)
		main.overworld.has_move_target = true

# ---------------- 主城 HUD ----------------

func _build_town_hud() -> void:
	town_panel = Control.new()
	town_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	town_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(town_panel)

	# 任务追踪条（真正的支线/日常任务，替代旧的余火主线面板）。
	_build_quest_tracker()

	# 交互提示。
	interact_prompt = UiKit.label("", UiKit.F_BODY, Color(0.94, 0.90, 0.78))
	interact_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	interact_prompt.anchor_top = 0.72
	interact_prompt.anchor_bottom = 0.72
	interact_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	interact_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interact_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interact_prompt.visible = false
	town_panel.add_child(interact_prompt)

	# POI 标签容器。
	poi_label_root = Control.new()
	poi_label_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	poi_label_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(poi_label_root)

func _build_poi_labels() -> void:
	for poi in main.town_world.pois:
		var b := Button.new()
		b.text = "%s %s" % [poi.get("symbol", "◈"), poi.name]
		b.add_theme_font_size_override("font_size", 12)
		var sb := StyleBoxFlat.new()
		var is_ember: bool = poi.get("type", "") == "ember"
		sb.bg_color = Color(0.28, 0.22, 0.08, 0.9) if is_ember else Color(0.05, 0.07, 0.06, 0.85)
		sb.border_color = COL_GOLD if is_ember else Color(0.35, 0.34, 0.25)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 10; sb.content_margin_right = 10
		sb.content_margin_top = 3; sb.content_margin_bottom = 3
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb.duplicate())
		b.add_theme_stylebox_override("pressed", sb.duplicate())
		var pid: String = poi.id
		# 图标点击即达：附近直接打开交互界面，远处自动寻路后到达即开。
		b.pressed.connect(func(): main.town_world.poi_icon_clicked(pid))
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		poi_labels[poi.id] = {"button": b, "poi": poi}
		poi_label_root.add_child(b)

func _find_poi(id: String) -> Dictionary:
	for poi in main.town_world.pois:
		if poi.id == id: return poi
	return {}

func refresh_hud() -> void:
	var save: Dictionary = GameState.save
	var st: Dictionary = GameState.total_stats()
	gold_label.text = str(save.gold)
	if diamond_label: diamond_label.text = str(save.diamonds)
	potion_label.text = str(save.potions)
	var hp_max: float = maxf(float(st.get("hp_max", 100)), 1.0)
	var mp_max: float = maxf(float(st.get("mp_max", 50)), 1.0)
	health_text.text = "%d / %d" % [int(save.hp), int(hp_max)]
	if mp_text: mp_text.text = "%d / %d" % [int(save.mp), int(mp_max)]
	_set_bar(health_bar, 124.0, float(save.hp) / hp_max)
	dungeon_health_bar.custom_minimum_size.x = 150.0 * save.hp / hp_max
	dungeon_health_text.text = "%d / %d" % [int(save.hp), int(hp_max)]
	dungeon_potion_label.text = str(save.potions)
	_refresh_quest_track()

## 设置进度条宽度（同时改 min 与 size——父节点不是容器，只改 min 不会缩短）。
func _set_bar(rect: ColorRect, full: float, ratio: float) -> void:
	if rect == null: return
	var w: float = maxf(full * clampf(ratio, 0.0, 1.0), 0.0)
	rect.custom_minimum_size.x = w
	rect.size.x = w

## 任务追踪条刷新：形状标记优先，颜色辅助；无任务时给出明确的下一步。
func _refresh_quest_track() -> void:
	if quest_track == null: return
	var info: Dictionary = GameState.tracked_info()
	if info.is_empty():
		_qt_marker.text = "·"
		_qt_marker.add_theme_color_override("font_color", UiKit.TEXT_MUTE)
		_qt_title.text = "暂无追踪任务"
		_qt_meta.text = ""
		_qt_desc.text = "告示板或冒险者协会可接取支线；日常每天刷新。"
		_qt_progress.text = ""
		_set_bar(_qt_bar, 168.0, 0.0)
		_qt_reward.text = ""
		_qt_action.text = "前往告示板 →" if (main != null and main.mode == main.Mode.TOWN) else "打开任务日志"
		_qt_action.disabled = false
		return
	var claimable: bool = bool(info.claimable)
	var done: bool = bool(info.done)
	_qt_title.text = String(info.name)
	if claimable:
		_qt_marker.text = "◆"
		_qt_marker.add_theme_color_override("font_color", UiKit.GOLD)
	elif done:
		_qt_marker.text = "✓"
		_qt_marker.add_theme_color_override("font_color", UiKit.TEXT_MUTE)
	else:
		_qt_marker.text = "▌"
		_qt_marker.add_theme_color_override("font_color", UiKit.GOLD)
	_qt_meta.text = "支线" if String(info.kind) == "side" else "日常"
	_qt_desc.text = String(info.desc)
	_qt_progress.text = "%d / %d" % [int(info.progress), int(info.count)]
	_set_bar(_qt_bar, 168.0, float(info.ratio))
	_qt_bar.color = UiKit.TEXT_MUTE if done else UiKit.GOLD_DIM
	var in_town: bool = main != null and main.mode == main.Mode.TOWN
	if claimable:
		_qt_reward.text = "可领赏 · %s" % String(info.reward)
		_qt_action.text = "领取奖励" if in_town else "打开任务日志"
		_qt_action.disabled = false
	else:
		_qt_reward.text = "奖励 · %s" % String(info.reward)
		_qt_action.text = "前往接取点 →" if in_town else "打开任务日志"
		_qt_action.disabled = false

# ---------------- 地下城 HUD ----------------

func _build_dungeon_hud() -> void:
	dungeon_panel = Control.new()
	dungeon_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	dungeon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dungeon_panel)

	var top := _mk_panel()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.anchor_left = 0.5; top.anchor_right = 0.5
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 12
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	dungeon_panel.add_child(top)
	var tv := VBoxContainer.new()
	top.add_child(tv)
	tv.add_child(_mk_label("DUNGEON I · 废弃圣堂", 10, COL_DIM))
	enemy_count = _mk_label("4 / 4", 18, Color(0.90, 0.55, 0.40))
	tv.add_child(enemy_count)

	var bottom := _mk_panel()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.anchor_left = 0.5; bottom.anchor_right = 0.5
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.anchor_top = 1.0; bottom.anchor_bottom = 1.0
	bottom.offset_top = -150
	bottom.offset_bottom = -12
	bottom.mouse_filter = Control.MOUSE_FILTER_STOP
	dungeon_panel.add_child(bottom)
	var bv := VBoxContainer.new()
	bottom.add_child(bv)
	var hp_row := HBoxContainer.new()
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0.14, 0.09, 0.08)
	hp_bg.custom_minimum_size = Vector2(150, 12)
	hp_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dungeon_health_bar = ColorRect.new()
	dungeon_health_bar.color = Color(0.72, 0.30, 0.22)
	dungeon_health_bar.custom_minimum_size = Vector2(150, 12)
	hp_bg.add_child(dungeon_health_bar)
	hp_row.add_child(hp_bg)
	dungeon_health_text = _mk_label("0 / 100", 12)
	hp_row.add_child(dungeon_health_text)
	bv.add_child(hp_row)
	var pot_row := HBoxContainer.new()
	pot_row.add_child(_mk_label("药剂", 12, COL_DIM))
	dungeon_potion_label = _mk_label("0", 13, Color(0.85, 0.55, 0.45))
	pot_row.add_child(dungeon_potion_label)
	bv.add_child(pot_row)
	ultimate_name = _mk_label("月蚀箭雨", 14, COL_GOLD)
	bv.add_child(ultimate_name)
	ultimate_cooldown = _mk_label("就绪", 12, COL_DIM)
	bv.add_child(ultimate_cooldown)
	var brow := HBoxContainer.new()
	var atk := _mk_button("攻击 左键", func(): if main: main.dungeon_world.player_attack())
	brow.add_child(atk)
	ultimate_button = _mk_button("大招 4", func(): if main: main.dungeon_world.player_ultimate(), true)
	brow.add_child(ultimate_button)
	var potion_btn := _mk_button("药剂 F", func(): main.use_potion())
	brow.add_child(potion_btn)
	var exit_btn := _mk_button("撤离圣堂 E", func(): if main: main.dungeon_world.exit_dungeon())
	brow.add_child(exit_btn)
	bv.add_child(brow)
	# 组队指挥提示（阵型 / 集火 / 待命）。
	_party_hint = UiKit.label("", UiKit.F_TINY, UiKit.TEXT_MUTE)
	bv.add_child(_party_hint)
	# 敌方小队提示（阵型 / 组合拳预警）。
	_enemy_hint = UiKit.label("", UiKit.F_TINY, UiKit.TEXT_MUTE)
	bv.add_child(_enemy_hint)

# ---------------- 弹窗 ----------------

func _build_modal() -> void:
	modal_dim = ColorRect.new()
	modal_dim.color = UiKit.BG_DIM  # off-black 遮罩（不用纯黑）
	modal_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_dim.visible = false
	add_child(modal_dim)
	modal = _mk_panel()
	modal.set_anchors_preset(Control.PRESET_CENTER)
	modal.grow_horizontal = Control.GROW_DIRECTION_BOTH
	modal.grow_vertical = Control.GROW_DIRECTION_BOTH
	modal.custom_minimum_size = Vector2(460, 0)
	modal.visible = false
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_dim.add_child(modal)
	var v := VBoxContainer.new()
	modal.add_child(v)
	modal_eyebrow = _mk_label("ASHEN SANCTUARY", 10, COL_DIM)
	v.add_child(modal_eyebrow)
	modal_title = _mk_label("", 20, COL_GOLD)
	v.add_child(modal_title)
	v.add_child(_vs(6))
	modal_content = RichTextLabel.new()
	modal_content.bbcode_enabled = true
	modal_content.fit_content = true
	modal_content.add_theme_font_size_override("normal_font_size", 14)
	modal_content.add_theme_font_size_override("bold_font_size", 14)
	modal_content.add_theme_color_override("default_color", COL_TEXT)
	v.add_child(modal_content)
	v.add_child(_vs(10))
	modal_actions = VBoxContainer.new()
	modal_actions.add_theme_constant_override("separation", 6)
	v.add_child(modal_actions)
	v.add_child(_vs(4))
	var close_row := HBoxContainer.new()
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_row.add_child(sp)
	close_row.add_child(_mk_button("关闭 Esc", close_dialog))
	v.add_child(close_row)

func _html_to_bbcode(html: String) -> String:
	var s := html
	s = s.replace("<p class='dialog-speaker'>", "[i][color=#c9a86a]").replace("<p class=\"dialog-speaker\">", "[i][color=#c9a86a]")
	s = s.replace("<p>", "").replace("<p style='margin-top:14px'>", "\n").replace("<p style=\"margin-bottom:16px\">", "")
	s = s.replace("</p>", "\n")
	s = s.replace("<b>", "[b]").replace("<strong>", "[b]").replace("</b>", "[/b]").replace("</strong>", "[/b]")
	s = s.replace("<kbd>", "[color=#9fb3a8]").replace("</kbd>", "[/color]")
	s = s.replace("<br>", "\n")
	# 移除剩余标签。
	var regex := RegEx.new()
	regex.compile("<[^>]+>")
	s = regex.sub(s, "", true)
	s = s.replace("&nbsp;", " ")
	return s.strip_edges()

func open_dialog(title: String, content_html: String, actions: Array, eyebrow := "ASHEN SANCTUARY") -> void:
	# 打开弹窗时清除移动意图。
	if main:
		if main.town_world:
			main.town_world.path.clear()
			main.town_world.destination_poi = {}
			main.town_world.move_marker.visible = false
		if main.dungeon_world:
			main.dungeon_world._path.clear()
			main.dungeon_world.move_marker.visible = false
	modal_eyebrow.text = eyebrow
	modal_title.text = title
	modal_content.text = _html_to_bbcode(content_html)
	for child in modal_actions.get_children():
		child.queue_free()
	for action in actions:
		var b := _mk_button(action.label, action.run, not action.get("secondary", false))
		b.disabled = action.get("disabled", false)
		modal_actions.add_child(b)
	modal.visible = true
	modal_dim.visible = true

func close_dialog() -> void:
	modal.visible = false
	modal_dim.visible = false

func is_dialog_open() -> bool:
	return modal.visible

# ---------------- 背包 / 地图 / 帮助 ----------------

## 多功能面板开关（Main 的 B/M/K/J/P 快捷键路由到这里）。
## map 转发到旧版地图弹窗，其余四类由 UIPanels 统一管理（互斥显示）。
func toggle_panel(panel_name: String) -> void:
	match panel_name:
		"map":
			show_map()
		"bag", "growth", "quests", "pets":
			if panels == null:
				panels = UIPanels.new()
				panels.main = main
				add_child(panels)
			panels.toggle(panel_name)

func show_inventory() -> void:
	var save: Dictionary = GameState.save
	var weapon := "古林长弓" if GameState.is_archer() else "旧国战锤"
	var content := "<p>%s</p>".format([
		"<b>行囊清单</b>\n余烬币：<b>%d</b>\n生命药剂：<b>%d 瓶</b>\n余火碎片：<b>%s</b>\n%s：<b>+%d</b>\n\n旅途进度保存在本机存档中。" % [
			save.gold, save.potions,
			"已归还" if save.quest == "complete" else "%d / 3" % save.embers.size(),
			weapon, save.upgrade]])
	var actions: Array = [
		{"label": "使用生命药剂", "disabled": save.potions == 0 or save.hp >= 100, "run": func(): main.use_potion(); show_inventory()},
		{"label": "收起行囊", "run": close_dialog, "secondary": true},
	]
	open_dialog("旅人的行囊", content, actions, "WHAT YOU CARRY")

func show_map() -> void:
	if not main or not main.town_world: return
	open_dialog("庇护所 · 地图", "<p>选择地标，自动寻路前往。途中按方向键可接管移动。</p>", [], "KNOW THESE QUIET STREETS")
	for child in modal_actions.get_children():
		child.queue_free()
	for poi in main.town_world.pois:
		if poi.type != "place": continue
		var pid: String = poi.id
		var row := Button.new()
		row.text = "%s    自动寻路 ↗" % poi.name
		row.add_theme_font_size_override("font_size", 14)
		row.pressed.connect(func():
			close_dialog()
			main.town_world.travel_to_poi(_find_poi(pid)))
		modal_actions.add_child(row)

func toggle_help() -> void:
	if is_dialog_open():
		close_dialog()
		return
	var content := """[b]黑暗中的指引[/b]
切换职业：[color=#9fb3a8]1 - 5[/color]（登场界面）
主动技能 / 大招：[color=#9fb3a8]1 2 3 4[/color]
城中行走：[color=#9fb3a8]W A S D / ↑ ↓ ← →[/color]
奔跑 / 与附近目标交互：[color=#9fb3a8]Shift / E[/color]
药剂 / 手持火把 / 放置火把：[color=#9fb3a8]F / T / G[/color]
视角锁定切换：[color=#9fb3a8]V[/color]
背包 / 地图：[color=#9fb3a8]B / M[/color]
加点 / 任务 / 队伍：[color=#9fb3a8]K / J / P[/color]
关闭窗口：[color=#9fb3a8]Esc[/color]

拖动画面旋转视角，滚轮缩放。主城点击地面寻路；地下城移动鼠标锁定敌人，红圈表示当前目标，左键发动攻击。野外捕捉残血动物可驯服为宠物。"""
	open_dialog("帮助", content, [{"label": "回到旅途", "run": close_dialog}], "A GUIDE FOR THE WANDERER")

# ---------------- 每帧刷新 ----------------

func _process(delta: float) -> void:
	if main == null: return
	# 生命条伤害延迟层：受击后先停住，再缓慢回落，让玩家读得出这一击掉了多少。
	var ratio: float = clampf(float(GameState.save.hp) / maxf(float(GameState.total_stats().get("hp_max", 100)), 1.0), 0.0, 1.0)
	if ratio < _hp_ghost:
		_hp_hold = 0.35
	if _hp_hold > 0.0:
		_hp_hold -= delta
	else:
		_hp_ghost = maxf(ratio, _hp_ghost - delta * 0.9)
	if health_ghost:
		_set_bar(health_ghost, 124.0, _hp_ghost)
	# 防御 / 格挡状态。
	if guard_status:
		var ap: Actor = main.active_player()
		if ap != null and ap.counter_t > 0.0:
			guard_status.text = "反击窗口 · 伤害 +50%（趁机出招）"
			guard_status.add_theme_color_override("font_color", UiKit.OK)
		elif ap != null and ap.guarding:
			if ap.guard_parry_active():
				guard_status.text = "招架窗口！此刻受击必完美格挡"
				guard_status.add_theme_color_override("font_color", UiKit.GOLD)
			else:
				guard_status.text = "防御中 · 减伤 %d%%" % int(round((1.0 - ap.guard_reduction) * 100.0))
				guard_status.add_theme_color_override("font_color", UiKit.TEXT_DIM)
		else:
			guard_status.text = "按住 R 防御 · 按下瞬间受击可完美格挡"
			guard_status.add_theme_color_override("font_color", UiKit.TEXT_MUTE)
	# 小地图高亮当前追踪任务的接取点。
	if minimap:
		var info: Dictionary = GameState.tracked_info()
		minimap.set_tracked("guild" if (not info.is_empty() and String(info.get("giver", "")) == "guild" and bool(info.get("claimable", false))) else "board" if bool(info.get("claimable", false)) else "")
	# 时钟。
	clock_label.text = "%s %s %s" % [GameState.clock_text(), GameState.clock_icon(), GameState.day_phase_text()]
	# 地下城 HUD。
	if dungeon_panel.visible:
		var dw = main.dungeon_world
		var alive := 0
		var total: int = dw.enemies.size()
		for e in dw.enemies:
			if not e.dead: alive += 1
		enemy_count.text = "深渊敌人 %d / %d" % [alive, maxi(total, 4)]
		# 组队指挥提示。
		if _party_hint:
			var fname: String = String(NpcBook.FORMATIONS.get(GameState.party_formation(), {}).get("name", "纵队跟随"))
			_party_hint.text = "阵型 %s（X）· 集火 C · 待命 Z · 同伴 %d 人" % [fname, GameState.save.party.size()]
		# 敌方小队：阵型名 + 组合拳状态（前摇时高亮预警，这是玩家该格挡的时刻）。
		if _enemy_hint:
			var sq: Dictionary = dw.squad
			var members: Array = sq.get("members", [])
			if members.size() < 2:
				_enemy_hint.text = "敌军各自为战"
				_enemy_hint.add_theme_color_override("font_color", UiKit.TEXT_MUTE)
			else:
				var fname2: String = String(Bestiary.SQUAD_FORMATIONS.get(sq.get("formation", ""), {}).get("name", "—"))
				var cname: String = String(Bestiary.SQUAD_COMBOS.get(sq.get("combo", ""), {}).get("name", ""))
				if String(sq.get("phase", "idle")) == "telegraph":
					_enemy_hint.text = "敌军 %s · 组合拳「%s」蓄势——准备格挡！" % [fname2, cname]
					_enemy_hint.add_theme_color_override("font_color", UiKit.DANGER)
				else:
					_enemy_hint.text = "敌军列阵 %s · 组合拳 %d 次" % [fname2, dw.squad_combos]
					_enemy_hint.add_theme_color_override("font_color", UiKit.TEXT_DIM)
		# 终极技 = 第 4 主动技能：显示冷却与蓝耗状态。
		if GameState.save.selected != "" and SkillBook.actives(GameState.save.selected).size() >= 4:
			var ult: Dictionary = SkillBook.actives(GameState.save.selected)[3]
			var cd3: float = dw.cooldowns[3]
			var ready: bool = cd3 <= 0.0 and GameState.save.mp >= float(ult.mp)
			ultimate_name.text = str(ult.name)
			ultimate_cooldown.text = "就绪" if ready else ("冷却 %d 秒" % int(ceil(cd3)) if cd3 > 0.0 else "法力不足")
			ultimate_button.disabled = not ready
	# 交互提示。
	if town_panel.visible and not is_dialog_open():
		var near = main.town_world.near_poi
		if near and main.town_world.poi_available(near):
			interact_prompt.text = "按 E 与「%s」交互" % near.name
			interact_prompt.visible = true
		else:
			interact_prompt.visible = false
	elif interact_prompt:
		interact_prompt.visible = false
	# POI 标签跟随 3D 位置。
	if poi_label_root.visible and main.camera_rig:
		var cam: Camera3D = main.camera_rig.camera
		for id in poi_labels:
			var entry: Dictionary = poi_labels[id]
			var poi: Dictionary = entry.poi
			var avail: bool = main.town_world.poi_available(poi)
			if not avail:
				entry.button.visible = false
				continue
			var gpos: Vector3 = main.town_world.to_global(poi.position)
			if cam.is_position_behind(gpos):
				entry.button.visible = false
				continue
			var sp := cam.unproject_position(gpos)
			var vp_size := poi_label_root.size
			if sp.x < -60 or sp.x > vp_size.x + 60 or sp.y < -40 or sp.y > vp_size.y + 40:
				entry.button.visible = false
				continue
			entry.button.visible = true
			entry.button.position = sp - entry.button.size / 2.0 - Vector2(0, 40)
	# 动画状态行。
	if anim_status and selection_panel and selection_panel.visible and main.selection_world:
		anim_status.text = main.selection_world.status_text if main.selection_world.get("status_text") != null else "待机 · 呼吸"
