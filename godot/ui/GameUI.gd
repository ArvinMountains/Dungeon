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

# ---- 主城 HUD ----
var gold_label: Label
var potion_label: Label
var health_bar: ColorRect
var health_text: Label
var quest_title: Label
var quest_text: Label
var quest_progress: Label
var track_button: Button
var clock_label: Label
var interact_prompt: Label
var poi_labels := {}   # poi id -> Button

# ---- 地下城 HUD ----
var enemy_count: Label
var dungeon_health_bar: ColorRect
var dungeon_health_text: Label
var dungeon_potion_label: Label
var ultimate_name: Label
var ultimate_cooldown: Label
var ultimate_button: Button

# ---- 全局 ----
var toast_label: Label
var toast_tween: Tween
var hit_flash_rect: ColorRect
var transition_rect: ColorRect
var footer_place: Label

# ---- 弹窗 ----
var modal: PanelContainer
var modal_dim: ColorRect
var modal_eyebrow: Label
var modal_title: Label
var modal_content: RichTextLabel
var modal_actions: VBoxContainer

const COL_BG := Color(0.055, 0.075, 0.065, 0.93)
const COL_BORDER := Color(0.40, 0.35, 0.21)
const COL_GOLD := Color(0.86, 0.71, 0.42)
const COL_TEXT := Color(0.85, 0.83, 0.74)
const COL_DIM := Color(0.52, 0.50, 0.42)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_overlays()
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
	if mode == "town": footer_place.text = "灰烬庇护所 · 本地存档"
	elif mode == "dungeon": footer_place.text = "废弃圣堂 · 第一关"
	else: footer_place.text = "遗忘圣堂"
	if mode != "town": interact_prompt.visible = false
	refresh_hud()

# ---------------- 构建工具 ----------------

func _mk_panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_BG
	sb.border_color = COL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	return p

func _mk_label(text: String, size: int, color := COL_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _mk_button(text: String, cb: Callable, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 14)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.18, 0.14) if not accent else Color(0.30, 0.24, 0.12)
	sb.border_color = COL_GOLD if accent else Color(0.34, 0.33, 0.24)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 12; sb.content_margin_right = 12
	sb.content_margin_top = 6; sb.content_margin_bottom = 6
	var sb_hover := sb.duplicate()
	sb_hover.bg_color = sb.bg_color.lightened(0.12)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb_hover)
	b.add_theme_stylebox_override("pressed", sb_hover)
	b.add_theme_stylebox_override("disabled", sb)
	b.pressed.connect(cb)
	return b

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

	footer_place = _mk_label("遗忘圣堂", 12, COL_DIM)
	footer_place.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	footer_place.position = Vector2(12, -30)
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

	for id in ["archer", "warrior"]:
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

# ---------------- 主城 HUD ----------------

func _build_town_hud() -> void:
	town_panel = Control.new()
	town_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	town_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(town_panel)

	# 委托面板。
	var quest_panel := _mk_panel()
	quest_panel.position = Vector2(12, 12)
	quest_panel.custom_minimum_size = Vector2(280, 0)
	quest_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	town_panel.add_child(quest_panel)
	var qv := VBoxContainer.new()
	quest_panel.add_child(qv)
	qv.add_child(_mk_label("QUEST · 委托", 10, COL_DIM))
	quest_title = _mk_label("庇护所的余火", 15, COL_GOLD)
	qv.add_child(quest_title)
	quest_text = _mk_label("", 12)
	quest_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	qv.add_child(quest_text)
	quest_progress = _mk_label("", 12, COL_DIM)
	qv.add_child(quest_progress)
	track_button = _mk_button("寻路至告示板 →", func(): if main and main.town_world: main.town_world.track_quest())
	qv.add_child(track_button)

	# 资源面板。
	var res_panel := _mk_panel()
	res_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	res_panel.anchor_left = 1.0
	res_panel.anchor_right = 1.0
	res_panel.offset_left = -200
	res_panel.offset_right = -12
	res_panel.offset_top = 12
	res_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	res_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	town_panel.add_child(res_panel)
	var rv := VBoxContainer.new()
	res_panel.add_child(rv)
	clock_label = _mk_label("08:00 ☀ 清晨", 13, COL_GOLD)
	rv.add_child(clock_label)
	var gold_row := HBoxContainer.new()
	gold_row.add_child(_mk_label("余烬币", 12, COL_DIM))
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gold_row.add_child(sp)
	gold_label = _mk_label("0", 14, COL_GOLD)
	gold_row.add_child(gold_label)
	rv.add_child(gold_row)
	var potion_row := HBoxContainer.new()
	potion_row.add_child(_mk_label("生命药剂", 12, COL_DIM))
	var sp2 := Control.new(); sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	potion_row.add_child(sp2)
	potion_label = _mk_label("0", 14, Color(0.85, 0.55, 0.45))
	potion_row.add_child(potion_label)
	rv.add_child(potion_row)
	var hp_row := HBoxContainer.new()
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0.14, 0.09, 0.08)
	hp_bg.custom_minimum_size = Vector2(120, 10)
	hp_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	health_bar = ColorRect.new()
	health_bar.color = Color(0.72, 0.30, 0.22)
	health_bar.custom_minimum_size = Vector2(120, 10)
	hp_bg.add_child(health_bar)
	hp_row.add_child(hp_bg)
	health_text = _mk_label("0 / 100", 12)
	hp_row.add_child(health_text)
	rv.add_child(hp_row)
	var btn_row := HBoxContainer.new()
	btn_row.add_child(_mk_button("行囊 B", func(): show_inventory()))
	btn_row.add_child(_mk_button("地图 M", func(): show_map()))
	btn_row.add_child(_mk_button("药剂 1", func(): main.use_potion()))
	btn_row.add_child(_mk_button("帮助 Esc", func(): toggle_help()))
	rv.add_child(btn_row)

	# 交互提示。
	interact_prompt = _mk_label("", 14, Color(0.94, 0.90, 0.78))
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
		b.text = "%s %s" % [poi.symbol, poi.name]
		b.add_theme_font_size_override("font_size", 12)
		var sb := StyleBoxFlat.new()
		var is_ember: bool = poi.type == "ember"
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
		b.pressed.connect(func(): main.town_world.travel_to_poi(_find_poi(pid)))
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		poi_labels[poi.id] = {"button": b, "poi": poi}
		poi_label_root.add_child(b)

func _find_poi(id: String) -> Dictionary:
	for poi in main.town_world.pois:
		if poi.id == id: return poi
	return {}

func refresh_hud() -> void:
	var save: Dictionary = GameState.save
	gold_label.text = str(save.gold)
	potion_label.text = str(save.potions)
	health_bar.custom_minimum_size.x = 120.0 * save.hp / 100.0
	health_text.text = "%d / 100" % save.hp
	dungeon_health_bar.custom_minimum_size.x = 150.0 * save.hp / 100.0
	dungeon_health_text.text = "%d / 100" % save.hp
	dungeon_potion_label.text = str(save.potions)
	var active: bool = save.quest == "active"
	var complete: bool = save.quest == "complete"
	quest_title.text = "余火重燃" if complete else "庇护所的余火"
	quest_text.text = "祭坛再次燃起。庇护所记住了你的名字。" if complete else ("找回散落在城中的三簇余火，带回中央祭坛。" if active else "前往告示板，听听这座城的请求。")
	quest_progress.text = "✓ 委托已完成 · 获得 60 余烬币" if complete else ("余火碎片 %d / 3" % save.embers.size() if active else "")
	track_button.text = "前往深渊之门 →" if complete else ("寻路至余火祭坛 →" if active and save.embers.size() == 3 else ("寻找下一簇余火 →" if active else "寻路至告示板 →"))

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
	ultimate_button = _mk_button("大招 Q", func(): if main: main.dungeon_world.player_ultimate(), true)
	brow.add_child(ultimate_button)
	var potion_btn := _mk_button("药剂 1", func(): main.use_potion())
	brow.add_child(potion_btn)
	var exit_btn := _mk_button("撤离圣堂 E", func(): if main: main.dungeon_world.exit_dungeon())
	brow.add_child(exit_btn)
	bv.add_child(brow)

# ---------------- 弹窗 ----------------

func _build_modal() -> void:
	modal_dim = ColorRect.new()
	modal_dim.color = Color(0, 0, 0, 0.45)
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
切换职业 / 使用药剂：[color=#9fb3a8]1 / 2[/color]
城中行走：[color=#9fb3a8]W A S D / ↑ ↓ ← →[/color]
奔跑 / 与附近目标交互：[color=#9fb3a8]Shift / E[/color]
地下城索敌 / 攻击：[color=#9fb3a8]鼠标 / 左键[/color]
普通攻击 / 大招：[color=#9fb3a8]空格 J / Q[/color]
行囊 / 城镇地图：[color=#9fb3a8]B / M[/color]
关闭窗口：[color=#9fb3a8]Esc[/color]

拖动画面旋转视角，滚轮缩放。主城点击地面寻路；地下城移动鼠标锁定敌人，红圈表示当前目标，左键发动攻击。"""
	open_dialog("帮助", content, [{"label": "回到旅途", "run": close_dialog}], "A GUIDE FOR THE WANDERER")

# ---------------- 每帧刷新 ----------------

func _process(_delta: float) -> void:
	if main == null: return
	# 时钟。
	clock_label.text = "%s %s %s" % [GameState.clock_text(), GameState.clock_icon(), GameState.day_phase_text()]
	# 地下城 HUD。
	if dungeon_panel.visible:
		var dw = main.dungeon_world
		var alive := 0
		var total: int = dw.enemies.size()
		for e in dw.enemies:
			if e.alive: alive += 1
		enemy_count.text = "低语者 %d / %d" % [alive, maxi(total, 4)]
		var ready: bool = dw.ultimate_cooldown <= 0 and not dw.ultimate_active
		ultimate_name.text = "月蚀箭雨" if GameState.is_archer() else "余烬震击"
		ultimate_cooldown.text = "就绪" if ready else ("释放中" if dw.ultimate_active else "%d 秒" % int(ceil(dw.ultimate_cooldown)))
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
