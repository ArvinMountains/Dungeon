class_name SelectionWorld
extends Node3D
## 职业选择舞台：石台 + 烛光 + 当前预览职业的 ActorRig 展示。
## GameUI 的职业卡片点击后调 request_class(id)，世界负责换装展示。

signal toast_requested(text: String)

var main = null
var status_text := "待机 · 呼吸"

var _stage: Node3D
var _rig: ActorRig = null
var _time := 0.0
var _showcase := false

func _ready() -> void:
	_build_stage()
	request_class(GameState.save.selected, false)

func _build_stage() -> void:
	_stage = Node3D.new()
	add_child(_stage)
	# 圆形石台。
	GeoBuilder.cylinder(_stage, 2.6, 3.0, 0.5, Color(0.16, 0.18, 0.16), Vector3(0, 0.24, 0), 24)
	GeoBuilder.cylinder(_stage, 2.2, 2.2, 0.06, Color(0.24, 0.26, 0.2), Vector3(0, 0.52, 0), 24)
	GeoBuilder.ring(_stage, 2.35, 2.55, Color(0.55, 0.45, 0.25, 0.85), Vector3(0, 0.56, 0), 32)
	# 环形立柱与烛光。
	for i in range(4):
		var a := TAU * i / 4.0 + 0.8
		Ambience.pillar(_stage, cos(a) * 4.6, sin(a) * 4.6, 4.2)
		Ambience.candelabra(_stage, cos(a + 0.8) * 3.8, sin(a + 0.8) * 3.8, 1.3, true)
	# 氛围。
	Ambience.make_motes(self, 40, 8, Color(0.75, 0.62, 0.5))
	var key := OmniLight3D.new()
	key.light_color = Color(0.85, 0.72, 0.5)
	key.light_energy = 8.0
	key.omni_range = 14.0
	key.position = Vector3(2.5, 5.0, 3.0)
	add_child(key)

## 预览职业（announce=false 时静默切换，用于初始化）。
func request_class(id: String, announce := true) -> void:
	if not GameState.CLASS_DATA.has(id): return
	if GameState.save.selected != id:
		GameState.set_selected(id)
	_show_rig(id)
	_showcase = false
	if announce:
		toast_requested.emit("预览：%s" % GameState.CLASS_DATA[id].name)

func _show_rig(id: String) -> void:
	if _rig: _rig.queue_free()
	_rig = ActorRig.new(id, 741)
	_stage.add_child(_rig)
	_rig.position = Vector3(0, 0.55, 0)

## 进入展示动作（GameUI 点「检视」时调用）。
func start_showcase() -> void:
	_showcase = true

func update_selection(delta: float) -> void:
	_time += delta
	status_text = "展示动作 · 英姿" if _showcase else "待机 · 呼吸"
	if _rig:
		var pose := {"type": "showcase" if _showcase else "idle", "time": _time}
		_rig.animate(delta, _time, pose)
		_rig.rotation.y = sin(_time * 0.35) * 0.45
