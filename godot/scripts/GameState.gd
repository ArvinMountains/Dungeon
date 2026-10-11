extends Node
## GameState (autoload)
## 全局游戏状态、存档、昼夜、职业数据。对应原 main.js 的 state/save/CLASS_DATA/persist 部分。

signal class_changed(id: String)
signal gold_changed(v: int)
signal hp_changed(v: int)
signal potions_changed(v: int)
signal quest_changed
signal embers_changed
signal day_time_changed(hours: float)
signal day_paused_changed(paused: bool)

const SAVE_PATH := "user://lost-abyss-save-v1.json"
const SAVE_BACKUP_PATH := "user://lost-abyss-save-v1-backup.json"

const CLASS_DATA := {
	"archer": {
		"name": "精灵弓箭手", "subtitle": "WARDEN OF THE WITHERED WOODS",
		"tags": ["远程", "敏捷", "古林守望者"],
		"description": "旧日森林最后的低语者。以月光为弦，以寂静为誓，在黑暗察觉之前，箭已离弦。",
		"stats": [2, 5, 3], "trait": "寂静猎手", "motto": "风记得每一支箭的归途。", "icon": "bow",
		"accent": Color(0.55, 0.69, 0.5), "walk_speed": 3.2,
		"attack_range": 11.5, "attack_damage": 14, "attack_hit_time": 0.5, "attack_duration": 0.85, "attack_cooldown": 0.15,
		"ultimate_name": "月蚀箭雨", "ultimate_cast_range": 13.5, "ultimate_radius": 4.2, "ultimate_cooldown": 10.0,
		"ultimate_damage": 34, "ultimate_hit_time": 0.68, "ultimate_duration": 1.35,
	},
	"warrior": {
		"name": "铁匠战士", "subtitle": "THE LAST HAMMER OF THE FORGE",
		"tags": ["近战", "坚韧", "余烬铸造者"],
		"description": "王国已化为灰烬，炉火却从未熄灭。他将往日铸进战锤，以血肉之躯，守住最后一道城门。",
		"stats": [5, 2, 5], "trait": "不熄熔心", "motto": "只要炉火尚存，便不向长夜低头。", "icon": "hammer",
		"accent": Color(0.75, 0.57, 0.34), "walk_speed": 2.7,
		"attack_range": 2.4, "attack_damage": 22, "attack_hit_time": 0.55, "attack_duration": 0.8, "attack_cooldown": 0.25,
		"ultimate_name": "余烬震击", "ultimate_cast_range": 0.0, "ultimate_radius": 5.5, "ultimate_cooldown": 10.0,
		"ultimate_damage": 46, "ultimate_hit_time": 0.68, "ultimate_duration": 1.2,
	},
}

var save: Dictionary = {}
var storage_available := true
var storage_notice := ""

# Day / night. 0.6 game-minutes per real second (daySpeed=1/100 hours/sec).
var day_time := 8.0
var day_paused := false
var day_speed := 1.0 / 100.0

func _ready() -> void:
	load_save()
	process_mode = Node.PROCESS_MODE_ALWAYS

func fresh_save() -> Dictionary:
	return {
		"version": 1, "selected": "archer", "gold": 80, "potions": 1, "hp": 74, "upgrade": 0,
		"quest": "new", "embers": [], "training_reward": false, "training_hits": 0, "quality": "pixel",
	}

func valid_save(d) -> bool:
	if typeof(d) != TYPE_DICTIONARY: return false
	if d.get("version") != 1: return false
	if not ["archer", "warrior"].has(d.get("selected")): return false
	if not ["new", "active", "complete"].has(d.get("quest")): return false
	for k in ["gold", "potions", "hp", "upgrade", "training_hits"]:
		if not (d.get(k) is float or d.get(k) is int): return false
		if int(d.get(k)) < 0: return false
	if d.get("gold") > 100000 or d.get("potions") > 999 or d.get("hp") > 100 or d.get("upgrade") > 3 or d.get("training_hits") > 3: return false
	if typeof(d.get("training_reward")) != TYPE_BOOL: return false
	if not ["pixel", "fine"].has(d.get("quality")): return false
	var embers = d.get("embers")
	if typeof(embers) != TYPE_ARRAY or embers.size() > 3: return false
	var seen := {}
	for id in embers:
		if not ["ember0", "ember1", "ember2"].has(id): return false
		if seen.has(id): return false
		seen[id] = true
	return true

func load_save() -> void:
	save = fresh_save()
	if not FileAccess.file_exists(SAVE_PATH): return
	var raw := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed = JSON.parse_string(raw)
	if valid_save(parsed):
		save = parsed
	else:
		# Try backup.
		if FileAccess.file_exists(SAVE_BACKUP_PATH):
			var backup = JSON.parse_string(FileAccess.get_file_as_string(SAVE_BACKUP_PATH))
			if valid_save(backup):
				save = backup
				storage_notice = "已从本地备份恢复旅途记录。"
				return
		storage_available = false
		storage_notice = "本地存档不可读。本次以临时进度游玩，原存档保留。"

func persist() -> void:
	if not storage_available: return
	# Back up previous valid save.
	if FileAccess.file_exists(SAVE_PATH):
		var old_raw := FileAccess.get_file_as_string(SAVE_PATH)
		var old = JSON.parse_string(old_raw)
		if valid_save(old):
			var bf := FileAccess.open(SAVE_BACKUP_PATH, FileAccess.WRITE)
			if bf: bf.store_string(old_raw); bf.close()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(save))
		f.close()
	else:
		storage_available = false

# --- Day / night ---
func _process(delta: float) -> void:
	if not day_paused:
		day_time = fmod(day_time + delta * day_speed, 24.0)
		day_time_changed.emit(day_time)

func set_day_paused(v: bool) -> void:
	day_paused = v
	day_paused_changed.emit(v)

func day_factor() -> float:
	# Sun height: sunrise ~6, noon ~12, sunset ~18, midnight ~0.
	var sun_angle := ((day_time - 6.0) / 24.0) * TAU
	return clamp(sin(sun_angle), 0.0, 1.0)

func night_factor() -> float:
	var sun_angle := ((day_time - 6.0) / 24.0) * TAU
	return clamp(-sin(sun_angle), 0.0, 1.0)

func horizon_factor() -> float:
	var sun_angle := ((day_time - 6.0) / 24.0) * TAU
	return 1.0 - abs(sin(sun_angle))

func clock_text() -> String:
	var h := int(floor(day_time))
	var m := int(floor(fmod(day_time, 1.0) * 60.0))
	return "%02d:%02d" % [h, m]

func clock_icon() -> String:
	if day_factor() > 0.6: return "☀"
	if horizon_factor() > 0.3: return "◐"
	return "☾"

func day_phase_text() -> String:
	var h := day_time
	if h < 5: return "深夜"
	if h < 7: return "黎明"
	if h < 11: return "清晨"
	if h < 14: return "正午"
	if h < 17: return "午后"
	if h < 19: return "黄昏"
	if h < 21: return "暮色"
	return "夜晚"

# --- Save mutations ---
func set_selected(id: String) -> void:
	save.selected = id
	persist()
	class_changed.emit(id)

func add_gold(v: int) -> void:
	save.gold = clampi(int(save.gold) + v, 0, 100000)
	persist()
	gold_changed.emit(save.gold)

func set_hp(v: int) -> void:
	save.hp = clampi(v, 0, 100)
	persist()
	hp_changed.emit(save.hp)

func add_potion(v: int) -> void:
	save.potions = clampi(int(save.potions) + v, 0, 999)
	persist()
	potions_changed.emit(save.potions)

func set_quest(v: String) -> void:
	save.quest = v
	persist()
	quest_changed.emit()

func add_ember(id: String) -> void:
	if save.embers.has(id): return
	save.embers.append(id)
	persist()
	embers_changed.emit()

func class_data() -> Dictionary:
	return CLASS_DATA[save.selected]

func is_archer() -> bool:
	return save.selected == "archer"
