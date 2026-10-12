class_name UIPanels
extends Control
## 侧边功能面板集（B 背包 / K 加点 / J 任务 / P 宠物·队伍）。
## - 背包：6x4 网格，支持原生拖拽（合并/交换）、自动堆叠、一键整理、装备 4 槽 + 武器强化。
## - 加点：5 分支 × 10 级，互斥/联动提示，属性点分配。
## - 任务：支线 / 日常 领奖与进度。
## - 宠物：出战切换、队伍管理、好感度总览。

var main = null
var _window: PanelContainer
var _tabs := {}
var _views := {}
var _current := ""

# ---- 背包 ----
var _bag_grid: GridContainer
var _equip_row: HBoxContainer
var _gold_label: Label
var _mp_label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_window()
	# 状态信号 → 面板刷新。
	GameState.inventory_changed.connect(func(): _refresh_if(_current))
	GameState.equipment_changed.connect(func(): _refresh_if(_current))
	GameState.quests_changed.connect(func(): _refresh_if(_current))
	GameState.pets_changed.connect(func(): _refresh_if(_current))
	GameState.party_changed.connect(func(): _refresh_if(_current))
	GameState.gold_changed.connect(func(_v): _refresh_if(_current))
	visible = false

func _refresh_if(name: String) -> void:
	if visible and name != "": _show(name, true)

# ---------------- 窗口骨架 ----------------
func _build_window() -> void:
	_window = UiKit.panel(UiKit.BG, UiKit.BORDER, UiKit.S3)
	# 显式锚点 + 清零 offset：set_anchors_preset 会留下旧 offset，导致窗口缩到左上角。
	_window.anchor_left = 0.60
	_window.anchor_top = 0.08
	_window.anchor_right = 0.97
	_window.anchor_bottom = 0.92
	_window.offset_left = 0.0
	_window.offset_top = 0.0
	_window.offset_right = 0.0
	_window.offset_bottom = 0.0
	_window.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_window.grow_vertical = Control.GROW_DIRECTION_BOTH
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_window)
	var v := VBoxContainer.new()
	_window.add_child(v)
	# 标签行。
	var tabs_row := HBoxContainer.new()
	tabs_row.add_theme_constant_override("separation", int(UiKit.S1))
	v.add_child(tabs_row)
	for t in [["bag", "背包 B"], ["growth", "成长 K"], ["quests", "任务 J"], ["pets", "队伍 P"]]:
		var b := _mk_button(t[1], func(): _show(t[0]))
		tabs_row.add_child(b)
		_tabs[t[0]] = b
	var close := _mk_button("×", func(): _hide_all())
	tabs_row.add_child(close)
	# 四个视图：放进 VBox 里（PanelContainer 会把所有子节点铺满同一区域，直接挂会与标签行重叠）。
	for name in ["bag", "growth", "quests", "pets"]:
		var sv := ScrollContainer.new()
		sv.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sv.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		v.add_child(sv)
		_views[name] = sv
		sv.visible = false

## 显示某个标签（再按同键关闭）。
func toggle(name: String) -> void:
	if visible and _current == name:
		_hide_all()
	else:
		_show(name)

func _show(name: String, rebuild_only := false) -> void:
	visible = true
	_current = name
	for k in _views:
		_views[k].visible = k == name
	for k in _tabs:
		_tabs[k].modulate = Color(1, 0.85, 0.5) if k == name else Color(1, 1, 1)
	match name:
		"bag": _build_bag(_views.bag)
		"growth": _build_growth(_views.growth)
		"quests": _build_quests(_views.quests)
		"pets": _build_pets(_views.pets)

func _hide_all() -> void:
	visible = false
	_current = ""

## 当前显示的标签名（""=全部收起）；供快捷键/探针查询。
func current_panel() -> String:
	return _current if visible else ""

# ---------------- 构建工具 ----------------
func _mk_label(text: String, size: int, color := UiKit.TEXT) -> Label:
	return UiKit.label(text, size, color)

func _mk_button(text: String, cb: Callable, accent := false) -> Button:
	return UiKit.button(text, cb, accent, UiKit.F_SMALL)

func _clear(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()

## 物品稀有度色。
func _rarity_col(r: int) -> Color:
	return Items.RARITY_COLORS[clampi(r, 0, 4)]

## 拖拽预览（跟随鼠标的小标签）。
func _mk_drag_preview(inst: Dictionary) -> Control:
	var l := _mk_label(str(inst.get("name", "?")), 12, _rarity_col(int(inst.get("rarity", 0))))
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.06, 0.9)
	pc.add_theme_stylebox_override("panel", sb)
	pc.add_child(l)
	pc.modulate.a = 0.9
	return pc

# ---------------- 背包 ----------------
func _build_bag(root: ScrollContainer) -> void:
	_clear(root)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	root.add_child(v)
	v.add_child(_mk_label("背包 · %d/%d" % [GameState.inventory.used_count(), Inventory.CAPACITY], 16, Color(0.86, 0.71, 0.42)))
	# 金币 / 钻石 / 蓝条。
	_gold_label = _mk_label("金币 %d　◆ 钻石 %d" % [int(GameState.save.gold), int(GameState.save.diamonds)], 13, Color(0.9, 0.76, 0.35))
	v.add_child(_gold_label)
	_mp_label = _mk_label("法力 %d/%d" % [int(GameState.save.mp), int(GameState.total_stats().mp_max)], 13, Color(0.6, 0.7, 0.95))
	v.add_child(_mp_label)
	# 武器 + 装备槽。
	_equip_row = HBoxContainer.new()
	_equip_row.add_theme_constant_override("separation", 6)
	v.add_child(_equip_row)
	_rebuild_equips()
	# 工具行。
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	v.add_child(tools)
	tools.add_child(_mk_button("一键整理", func():
		GameState.inventory.sort_all()
		_show("bag")))
	tools.add_child(_mk_button("强化武器", func():
		if GameState.upgrade_weapon(): _show("bag")))
	# 网格。
	_bag_grid = GridContainer.new()
	_bag_grid.columns = 6
	_bag_grid.add_theme_constant_override("h_separation", 5)
	_bag_grid.add_theme_constant_override("v_separation", 5)
	v.add_child(_bag_grid)
	_rebuild_grid()

func _rebuild_equips() -> void:
	_clear(_equip_row)
	# 武器。
	var w = GameState.save.weapon
	_equip_row.add_child(_equip_slot("武器", w, func():
		pass  # 武器槽：点击无操作（强化在按钮）
	))
	for slot in Items.SLOTS:
		var inst = GameState.save.equipment.get(slot)
		var slot_name: String = {"head": "头", "body": "躯干", "hands": "手", "trinket": "饰品"}[slot]
		_equip_row.add_child(_equip_slot(slot_name, inst, func():
			var s: String = slot
			GameState.unequip_slot(s)
			_show("bag")))

func _equip_slot(slot_name: String, inst, on_click: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(74, 58)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.11, 0.1)
	sb.border_color = _rarity_col(int(inst.get("rarity", 0))) if inst != null else Color(0.25, 0.26, 0.2)
	sb.set_border_width_all(1 if inst == null else 2)
	sb.set_corner_radius_all(3)
	b.add_theme_stylebox_override("normal", sb)
	var bv := VBoxContainer.new()
	b.add_child(bv)
	bv.add_child(_mk_label(slot_name, 10, Color(0.5, 0.48, 0.4)))
	if inst != null:
		bv.add_child(_mk_label(str(inst.get("name", "?")), 11, _rarity_col(int(inst.get("rarity", 0)))))
		b.tooltip_text = Items.item_desc(inst)
		b.pressed.connect(on_click)
	return b

func _rebuild_grid() -> void:
	_clear(_bag_grid)
	var slots: Array = GameState.inventory.slots
	for i in range(Inventory.CAPACITY):
		var inst = slots[i] if i < slots.size() else null
		var slot := BagSlot.new()
		slot.panel = self
		slot.slot_idx = i
		slot.custom_minimum_size = Vector2(64, 52)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.09, 0.11, 0.1)
		sb.border_color = _rarity_col(int(inst.get("rarity", 0))) if inst != null else Color(0.22, 0.23, 0.19)
		sb.set_border_width_all(1 if inst == null else 2)
		sb.set_corner_radius_all(3)
		slot.add_theme_stylebox_override("normal", sb)
		var sv := VBoxContainer.new()
		slot.add_child(sv)
		if inst != null:
			sv.add_child(_mk_label(str(inst.get("name", "?")), 11, _rarity_col(int(inst.get("rarity", 0)))))
			if inst.get("count", 1) > 1:
				sv.add_child(_mk_label("×%d" % int(inst.count), 10, Color(0.7, 0.68, 0.6)))
			slot.tooltip_text = Items.item_desc(inst)
			slot.pressed.connect(func(): _on_slot_clicked(i))
		_bag_grid.add_child(slot)

## 点击背包格：装备 / 使用；Ctrl+点击 丢弃 1 个。
func _on_slot_clicked(idx: int) -> void:
	var inst = GameState.inventory.slots[idx]
	if inst == null: return
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
		GameState.inventory.remove(str(inst.get("base_id", "")), 1)
		toast("丢弃了 %s。" % inst.get("name", "?"))
		_show("bag")
		return
	match str(inst.get("kind", "")):
		"weapon", "gear":
			GameState.equip_slot(idx)
			toast("装备了 %s。" % inst.get("name", "?"))
			_show("bag")
		"consumable":
			_use_consumable(idx)
		_:
			toast(str(inst.get("name", "?")) + "——" + str(inst.get("desc", "材料，可在道具商出售。")))

func _use_consumable(idx: int) -> void:
	var inst = GameState.inventory.slots[idx]
	var base_id := str(inst.get("base_id", ""))
	match base_id:
		"potion_hp":
			if main: main.use_potion()
		"potion_mp":
			GameState.add_mp(float(GameState.total_stats().mp_max) * 0.5)
			GameState.inventory.remove("potion_mp", 1)
			toast("法力涌动 · 恢复一半法力。")
		_:
			toast(str(inst.get("name", "?")) + "现在用不上。")
	_show("bag")

func toast(t: String) -> void:
	if main: main.toast(t)

# ---------------- 加点 ----------------
func _build_growth(root: ScrollContainer) -> void:
	_clear(root)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	root.add_child(v)
	var pool := int(GameState.save.point_pool)
	v.add_child(_mk_label("成长之路 · 可用属性点 %d" % pool, 16, Color(0.86, 0.71, 0.42)))
	v.add_child(_mk_label("互斥：狂野+坚壁 ≤12　灵巧+贪婪 ≤14", 11, Color(0.55, 0.5, 0.42)))
	for b in Growth.BRANCHES:
		var def: Dictionary = Growth.BRANCHES[b]
		var lv := int(GameState.save.points.get(b, 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		v.add_child(row)
		var bar := ColorRect.new()
		bar.color = Color(def.color.r, def.color.g, def.color.b, 0.16)
		bar.custom_minimum_size = Vector2(0, 64)
		row.add_child(bar)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.add_child(info)
		info.add_child(_mk_label("%s %s · Lv%d/%d" % [def.icon, def.name, lv, Growth.MAX_LEVEL], 13, def.color))
		info.add_child(_mk_label(str(def.desc), 11, Color(0.72, 0.7, 0.62)))
		var plus := _mk_button("+", func():
			var err: String = GameState.allocate_point(b)
			if err != "": toast(err)
			_show("growth"), pool > 0)
		plus.custom_minimum_size = Vector2(30, 30)
		row.add_child(plus)
	# 联动。
	v.add_child(_mk_label("已激活联动：", 12, Color(0.86, 0.71, 0.42)))
	var active: Array = Growth.active_synergies(GameState.save.points)
	if active.is_empty():
		v.add_child(_mk_label("（暂无——尝试 狂野5+坚壁5 / 灵巧5+秘术5 等组合）", 11, Color(0.55, 0.5, 0.42)))
	for sid in active:
		for s in Growth.SYNERGIES:
			if s.id == sid:
				v.add_child(_mk_label("◆ %s：%s" % [s.name, s.desc], 11, Color(0.75, 0.8, 0.55)))

# ---------------- 任务日志 ----------------
## 结构：汇总 → 筛选（全部/进行中/可领赏）→ 分区（支线/日常/已完成）→ 条目
## 条目 = 形状标记 + 名称 + 目标一句话 + 进度条 + 奖励预览 + 追踪/领取。
var _quest_filter := "all"

func _build_quests(root: ScrollContainer) -> void:
	_clear(root)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(UiKit.S2))
	root.add_child(v)
	# 汇总与筛选。
	var counts := {"active": 0, "claim": 0, "done": 0}
	var side_ids: Array = []
	for qid in GameState.save.quests.side:
		side_ids.append(String(qid))
		_tally(counts, GameState.quest_info("side", String(qid)))
	var daily_ids: Array = []
	for d in GameState.save.quests.daily:
		daily_ids.append(String(d.id))
		_tally(counts, GameState.quest_info("daily", String(d.id)))
	v.add_child(_mk_label("任务日志", UiKit.F_TITLE, UiKit.GOLD))
	v.add_child(_mk_label("进行中 %d · 可领赏 %d · 已完成 %d" % [counts.active, counts.claim, counts.done], UiKit.F_TINY, UiKit.TEXT_MUTE))
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", int(UiKit.S1))
	for f in [["all", "全部"], ["active", "进行中"], ["claim", "可领赏"]]:
		var key: String = f[0]
		frow.add_child(_mk_button(String(f[1]), func():
			_quest_filter = key
			_show("quests"), key == _quest_filter))
	v.add_child(frow)
	v.add_child(UiKit.spacer(0, 2))
	# 分区。
	var any: bool = _quest_section(v, "支线任务", "side", side_ids, _quest_filter)
	any = _quest_section(v, "今日日常", "daily", daily_ids, _quest_filter) or any
	if _quest_filter == "all":
		any = _quest_section(v, "已完成 · 支线", "side", side_ids, "done") or any
		any = _quest_section(v, "已完成 · 日常", "daily", daily_ids, "done") or any
	if not any:
		v.add_child(_mk_label("（该筛选下暂无任务）", UiKit.F_TINY, UiKit.TEXT_MUTE))
	# 空状态必须给出下一步。
	if side_ids.is_empty():
		var hint := _mk_label("尚未接取支线——去城里的告示板或冒险者协会看看。", UiKit.F_TINY, UiKit.TEXT_MUTE)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(262, 0)
		v.add_child(hint)
		v.add_child(_mk_button("寻路至告示板 →", func():
			if main and main.town_world and main.mode == main.Mode.TOWN:
				main.town_world.travel_to_poi(main.town_world._poi_by_id("board"))
			_hide_all(), true))
	# 深渊随机事件提示。
	v.add_child(UiKit.section("深渊随机事件"))
	v.add_child(_mk_label("深渊房间里会偶遇：献祭祭坛 / 神秘商贩 / 赌博宝箱 / 月泉 / 学者问答", UiKit.F_TINY, UiKit.TEXT_MUTE))

func _tally(counts: Dictionary, info: Dictionary) -> void:
	if info.is_empty(): return
	if bool(info.claimed): counts.done = int(counts.done) + 1
	elif bool(info.claimable): counts.claim = int(counts.claim) + 1
	elif not bool(info.done): counts.active = int(counts.active) + 1

## 按筛选条件输出一个任务分区；无匹配条目时返回 false（不输出标题）。
func _quest_section(parent: VBoxContainer, title: String, kind: String, ids: Array, mode: String) -> bool:
	var entries: Array = []
	for qid in ids:
		var info: Dictionary = GameState.quest_info(kind, String(qid))
		if info.is_empty(): continue
		var claimed: bool = bool(info.claimed)
		if mode == "done":
			if not claimed: continue
		else:
			if claimed: continue
			if mode == "active" and bool(info.done): continue
			if mode == "claim" and not bool(info.claimable): continue
		entries.append(info)
	if entries.is_empty(): return false
	var head := HBoxContainer.new()
	head.add_child(_mk_label(title, UiKit.F_BODY, UiKit.TEXT_DIM))
	head.add_child(UiKit.hspacer())
	head.add_child(_mk_label(str(entries.size()), UiKit.F_TINY, UiKit.TEXT_MUTE))
	parent.add_child(head)
	for info in entries:
		_quest_entry(parent, info)
	return true

## 单条任务：形状标记优先于颜色；奖励预览放在目标之下（整宽）。
func _quest_entry(parent: VBoxContainer, info: Dictionary) -> void:
	var card := UiKit.panel(UiKit.BG_SOFT, Color(UiKit.BORDER.r, UiKit.BORDER.g, UiKit.BORDER.b, 0.75), UiKit.S2)
	parent.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(UiKit.S1))
	card.add_child(v)
	var claimable: bool = bool(info.claimable)
	var done: bool = bool(info.done)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(UiKit.S1))
	row.add_child(UiKit.marker("claim" if claimable else ("done" if done else ("tracked" if bool(info.tracked) else "idle"))))
	row.add_child(_mk_label(String(info.name), UiKit.F_BODY, UiKit.GOLD if claimable else UiKit.TEXT))
	row.add_child(UiKit.hspacer())
	row.add_child(_mk_label("支线" if String(info.kind) == "side" else "日常", UiKit.F_TINY, UiKit.TEXT_MUTE))
	v.add_child(row)
	var desc := _mk_label(String(info.desc), UiKit.F_TINY, UiKit.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(262, 0)
	v.add_child(desc)
	# 进度条 + 计数。
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", int(UiKit.S2))
	var bar := UiKit.bar(150, 6, UiKit.OK if done else UiKit.GOLD_DIM)
	prow.add_child(bar.bg)
	var fill: ColorRect = bar.fill
	var w := 150.0 * float(info.ratio)
	fill.custom_minimum_size.x = w
	fill.size.x = w
	prow.add_child(_mk_label("%d / %d" % [int(info.progress), int(info.count)], UiKit.F_TINY, UiKit.TEXT_DIM))
	v.add_child(prow)
	# 奖励预览。
	v.add_child(_mk_label("奖励 · %s" % String(info.reward), UiKit.F_TINY, UiKit.TEXT_MUTE))
	if bool(info.claimed):
		v.add_child(_mk_label("已领赏", UiKit.F_TINY, UiKit.TEXT_MUTE))
		return
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", int(UiKit.S1))
	if claimable:
		var kind := String(info.kind)
		var qid := String(info.id)
		var rw := String(info.reward)
		brow.add_child(_mk_button("领取奖励", func():
			if GameState.claim_quest(kind, qid):
				toast("奖励到手：%s" % rw)
			_show("quests"), true))
	if bool(info.tracked):
		brow.add_child(_mk_label("追踪中", UiKit.F_TINY, UiKit.GOLD))
	else:
		var kind2 := String(info.kind)
		var qid2 := String(info.id)
		brow.add_child(_mk_button("追踪", func():
			GameState.set_tracked(kind2, qid2)
			_show("quests")))
	v.add_child(brow)

# ---------------- 队伍 / 宠物 ----------------
func _build_pets(root: ScrollContainer) -> void:
	_clear(root)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(UiKit.S2))
	root.add_child(v)

	# ---- 组队指挥：阵型 + 快捷指令 ----
	v.add_child(UiKit.section("组队指挥"))
	var f := GameState.party_formation()
	var fdef: Dictionary = NpcBook.FORMATIONS.get(f, {})
	v.add_child(_mk_label("阵型 · %s（X 键循环）" % fdef.get("name", f), UiKit.F_BODY, UiKit.GOLD))
	v.add_child(_mk_label(String(fdef.get("desc", "")), UiKit.F_TINY, UiKit.TEXT_MUTE))
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", int(UiKit.S1))
	for fid in NpcBook.FORMATION_ORDER:
		var fk: String = String(fid)
		frow.add_child(_mk_button(String(NpcBook.FORMATIONS[fk].name), func():
			GameState.set_formation(fk)
			_show("pets"), fk == f))
	v.add_child(frow)
	var orow := HBoxContainer.new()
	orow.add_theme_constant_override("separation", int(UiKit.S1))
	orow.add_child(_mk_button("集火 C", func():
		GameState.order_focus()
		_show("pets"), GameState.order_focus_active()))
	orow.add_child(_mk_button("待命 Z" if not GameState.party_hold else "跟随 Z", func():
		GameState.order_hold_toggle()
		_show("pets"), GameState.party_hold))
	orow.add_child(_mk_label("集火 %s · %s" % [
		"生效中" if GameState.order_focus_active() else "就绪",
		"待命中" if GameState.party_hold else "跟随中"], UiKit.F_TINY, UiKit.TEXT_DIM))
	v.add_child(orow)

	# ---- 同伴队伍 ----
	var party: Array = GameState.save.party
	v.add_child(UiKit.section("同伴队伍（%d/3）" % party.size()))
	if party.is_empty():
		var hint := _mk_label("好感度满 60 可在主城招募同伴（闲聊 +1，送礼 +5/+8）。", UiKit.F_TINY, UiKit.TEXT_MUTE)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(262, 0)
		v.add_child(hint)
	for npc_id in party:
		_build_companion_card(v, String(npc_id))

	# ---- 宠物栏 ----
	v.add_child(UiKit.section("宠物栏（%d/6）" % GameState.save.pets.size()))
	if GameState.save.pets.is_empty():
		v.add_child(_mk_label("（野外残血动物用捕网捕获，E 键驯服）", UiKit.F_TINY, UiKit.TEXT_MUTE))
	for i in range(GameState.save.pets.size()):
		var p: Dictionary = GameState.save.pets[i]
		var active := int(GameState.save.active_pet) == i
		var idx := i
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(UiKit.S2))
		v.add_child(row)
		var pdef: Dictionary = Bestiary.ANIMALS.get(String(p.id), {})
		row.add_child(_mk_label("%s %s Lv%d（%d/%d）%s" % [pdef.get("icon", "🐾"), p.name, int(p.level), int(p.xp),
			GameState.pet_xp_needed(int(p.level)), " · 出战中" if active else ""], UiKit.F_SMALL,
			UiKit.GOLD if active else UiKit.TEXT))
		row.add_child(UiKit.hspacer())
		if not active:
			row.add_child(_mk_button("出战", func():
				GameState.set_active_pet(idx)
				_show("pets")))

	# ---- 好感度总览 ----
	v.add_child(UiKit.section("好感度总览"))
	for npc_id in NpcBook.NPCS:
		var def3: Dictionary = NpcBook.NPCS[npc_id]
		var aff := GameState.affinity_of(String(npc_id))
		var joined: bool = GameState.save.party.has(String(npc_id))
		v.add_child(_mk_label("%s · %s —— %d/60%s" % [def3.get("name", npc_id), def3.get("role", ""), aff,
			" · 已入队" if joined else ("（可招募）" if aff >= NpcBook.AFFINITY_RECRUIT_AT else "")], UiKit.F_TINY,
			UiKit.OK if joined else (UiKit.GOLD if aff >= NpcBook.AFFINITY_RECRUIT_AT else UiKit.TEXT_MUTE)))

## 单名同伴的卡片：先手标记 / 光环 / 行为档 / 离队。
func _build_companion_card(parent: VBoxContainer, npc_id: String) -> void:
	var def: Dictionary = NpcBook.NPCS.get(npc_id, {})
	var card := UiKit.panel(UiKit.BG_SOFT, Color(UiKit.BORDER.r, UiKit.BORDER.g, UiKit.BORDER.b, 0.75), UiKit.S2)
	parent.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(UiKit.S1))
	card.add_child(v)
	var row := HBoxContainer.new()
	row.add_child(_mk_label(String(def.get("name", npc_id)), UiKit.F_BODY, UiKit.GOLD))
	row.add_child(UiKit.hspacer())
	row.add_child(_mk_label("好感 %d" % GameState.affinity_of(npc_id), UiKit.F_TINY, UiKit.TEXT_MUTE))
	v.add_child(row)
	v.add_child(_mk_label(String(def.get("role", "")), UiKit.F_TINY, UiKit.TEXT_DIM))
	# 先手标记 + 光环。
	var rig := String(def.get("rig", "warrior"))
	var mk: Dictionary = NpcBook.MARK_BY_RIG.get(rig, {})
	v.add_child(_mk_label("先手标记 · %s（他打中后你补刀即引爆）" % mk.get("name", "破甲"), UiKit.F_TINY,
		mk.get("color", UiKit.TEXT_DIM)))
	var au: Dictionary = def.get("aura", {})
	if not au.is_empty():
		v.add_child(_mk_label("光环 · %s" % String(au.get("desc", "")), UiKit.F_TINY, UiKit.OK))
	# 行为档位。
	var cur := GameState.stance_of(npc_id)
	var strow := HBoxContainer.new()
	strow.add_theme_constant_override("separation", int(UiKit.S1))
	strow.add_child(_mk_label("行为", UiKit.F_TINY, UiKit.TEXT_MUTE))
	for sid in NpcBook.STANCE_ORDER:
		var sk: String = String(sid)
		strow.add_child(_mk_button(String(NpcBook.STANCES[sk].name), func():
			GameState.set_stance(npc_id, sk)
			_show("pets"), sk == cur))
	v.add_child(strow)
	v.add_child(_mk_label(String(NpcBook.STANCES.get(cur, {}).get("desc", "")), UiKit.F_TINY, UiKit.TEXT_MUTE))
	var brow := HBoxContainer.new()
	brow.add_child(_mk_button("请离队伍", func():
		GameState.dismiss(npc_id)
		if main and main.town_world: main.town_world._sync_followers()
		_show("pets")))
	v.add_child(brow)

# ---------------- 背包格（支持拖拽） ----------------
class BagSlot extends Button:
	var panel = null
	var slot_idx := -1

	func _get_drag_data(_pos):
		var inst = GameState.inventory.slots[slot_idx]
		if inst == null or panel == null: return null
		var preview: Control = panel._mk_drag_preview(inst)
		set_drag_preview(preview)
		return {"slot": slot_idx}

	func _can_drop_data(_pos, data) -> bool:
		return typeof(data) == TYPE_DICTIONARY and data.has("slot") and int(data.slot) != slot_idx

	func _drop_data(_pos, data) -> void:
		GameState.inventory.move_slot(int(data.slot), slot_idx)
		if panel: panel._show("bag")
