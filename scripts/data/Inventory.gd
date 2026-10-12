class_name Inventory
extends RefCounted
## 网格背包：24 格（6x4），消耗品/材料自动堆叠，支持拖拽移动、一键整理。
## 物品实例结构见 Items.gd：{kind, base, name, rarity, level, affixes, stack, count, ...}

const CAPACITY := 24

signal changed

var slots: Array = []  # 24 项：null 或物品 Dictionary

func _init() -> void:
	slots.resize(CAPACITY)
	slots.fill(null)

## 添加物品（自动堆叠/找空位）。返回是否成功。
func add(inst: Dictionary) -> bool:
	if inst.get("stack", false):
		var remain: int = inst.count
		for i in range(CAPACITY):
			var s = slots[i]
			if s and s.kind == "consumable" and s.base == inst.base:
				var space: int = Items.STACK_MAX - int(s.count)
				if space > 0:
					var move: int = mini(space, remain)
					slots[i].count = int(slots[i].count) + move
					remain -= move
					if remain <= 0:
						changed.emit(); return true
		if remain > 0:
			inst = inst.duplicate(); inst.count = remain
	# 找空位。
	for i in range(CAPACITY):
		if slots[i] == null:
			slots[i] = inst
			changed.emit(); return true
	return false

## 按物品 id 与类型移除 count 个（消耗品/材料）。返回是否成功。
func remove(base_id: String, count: int = 1) -> bool:
	var have := count_of(base_id)
	if have < count: return false
	var need := count
	for i in range(CAPACITY):
		if need <= 0: break
		var s = slots[i]
		if s and s.base == base_id:
			var take: int = mini(int(s.count), need)
			slots[i].count = int(s.count) - take
			need -= take
			if int(slots[i].count) <= 0: slots[i] = null
	changed.emit()
	return true

func count_of(base_id: String) -> int:
	var n := 0
	for s in slots:
		if s and s.base == base_id: n += int(s.count)
	return n

## 已占用格数（UI 标题显示 x/24）。
func used_count() -> int:
	var n := 0
	for s in slots:
		if s != null: n += 1
	return n

## 是否拥有某类型物品（如武器按 kind）。
func has_kind(k: String) -> bool:
	for s in slots:
		if s and s.kind == k: return true
	return false

## 拖拽：从 a 格移到 b 格。目标为空则移动；同类可堆叠则合并；否则交换。
func move_slot(a: int, b: int) -> void:
	if a == b or a < 0 or b < 0 or a >= CAPACITY or b >= CAPACITY: return
	var src = slots[a]
	var dst = slots[b]
	if src == null: return
	if dst and dst.stack and src.stack and dst.base == src.base:
		var space: int = Items.STACK_MAX - int(dst.count)
		var mv: int = mini(space, int(src.count))
		dst.count = int(dst.count) + mv
		src.count = int(src.count) - mv
		if int(src.count) <= 0: slots[a] = null
	else:
		slots[a] = dst
		slots[b] = src
	changed.emit()

## 一键整理：非空物品前置 + 按类型/稀有度排序 + 堆叠合并。
func sort_all() -> void:
	var items: Array = []
	for s in slots:
		if s: items.append(s)
	items.sort_custom(func(x, y):
		var ka := _sort_key(x)
		var kb := _sort_key(y)
		if ka != kb: return ka < kb
		return x.name < y.name)
	# 尝试再次合并可堆叠项。
	var merged: Array = []
	for it in items:
		if it.stack:
			var done := false
			for m in merged:
				if m.base == it.base and int(m.count) < Items.STACK_MAX:
					var space: int = Items.STACK_MAX - int(m.count)
					var mv: int = mini(space, int(it.count))
					m.count = int(m.count) + mv
					it.count = int(it.count) - mv
					if int(it.count) <= 0: done = true; break
			if done: continue
		merged.append(it)
	slots.fill(null)
	for i in range(merged.size()):
		slots[i] = merged[i]
	changed.emit()

func _sort_key(it: Dictionary) -> int:
	match it.kind:
		"weapon": return 0
		"gear": return 1
		"consumable": return 2
	return 3

## 存档序列化。
func to_array() -> Array:
	var arr := []
	for i in range(CAPACITY):
		if slots[i]: arr.append({"slot": i, "item": slots[i]})
	return arr

func from_array(arr: Array) -> void:
	slots.fill(null)
	for e in arr:
		if typeof(e) == TYPE_DICTIONARY and e.has("slot") and e.has("item"):
			var idx := int(e.slot)
			if idx >= 0 and idx < CAPACITY: slots[idx] = e.item
	changed.emit()
