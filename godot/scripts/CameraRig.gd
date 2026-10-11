class_name CameraRig
extends Node3D
## 轨道相机：拖拽旋转偏航/俯仰、滚轮缩放、三预设、跟随目标。对应 main.js updateCamera。

signal preset_changed(name: String)

var cam_yaw := 0.0
var cam_pitch := 0.55
var cam_dist := 22.0
var cam_zoom := 1.0
var target := Vector3.ZERO
var follow_node: Node3D
var camera_shake := 0.0
var camera: Camera3D

var presets := {
	"selection": {"yaw": 0.3, "pitch": 0.62, "dist": 9.0, "ty": 1.3},
	"town": {"yaw": 0.5, "pitch": 0.75, "dist": 22.0, "ty": 1.05},
	"dungeon": {"yaw": 0.0, "pitch": 0.95, "dist": 14.0, "ty": 1.1},
}
var preset_offsets := {
	"low": {"pitch": 0.55, "dist_mul": 0.72},
	"classic": {"pitch": 0.0, "dist_mul": 1.0},
	"eye": {"pitch": 1.0, "dist_mul": 1.15},
}
var current_preset := "classic"
var current_mode := "selection"

var _dragging := false
var _drag_last := Vector2.ZERO
var _drag_distance := 0.0
var _elapsed := 0.0

func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 48.0
	camera.near = 0.1
	camera.far = 220.0
	add_child(camera)
	camera.current = true

func set_mode(mode: String) -> void:
	current_mode = mode
	reset()

func reset() -> void:
	var p: Dictionary = presets.get(current_mode, presets.town)
	var off: Dictionary = preset_offsets.get(current_preset, preset_offsets.classic)
	cam_yaw = p.yaw
	cam_pitch = clamp(p.pitch + off.pitch, 0.12, 1.48)
	cam_dist = p.dist * off.dist_mul

func set_preset(name: String) -> void:
	if not preset_offsets.has(name): return
	current_preset = name
	reset()
	preset_changed.emit(name)

func nudge_yaw(d: float) -> void: cam_yaw += d
func nudge_pitch(d: float) -> void: cam_pitch = clamp(cam_pitch + d, 0.12, 1.48)
func nudge_zoom(mult: float) -> void: cam_dist = clamp(cam_dist * mult, 4.0, 55.0)

func handle_mouse_button(event: InputEventMouseButton) -> bool:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		nudge_zoom(0.88); return true
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		nudge_zoom(1.12); return true
	if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_dragging = true
			_drag_last = event.position
			_drag_distance = 0.0
		else:
			_dragging = false
		return false  # Let click through for selection.
	return false

func handle_mouse_motion(event: InputEventMouseMotion, ui_blocked: bool) -> void:
	if _dragging and not ui_blocked:
		var d := event.position - _drag_last
		_drag_distance += abs(d.x) + abs(d.y)
		cam_yaw += d.x * 0.005
		cam_pitch = clamp(cam_pitch + d.y * 0.004, 0.12, 1.48)
		_drag_last = event.position

func was_click() -> bool:
	return _drag_distance < 7.0

func _process(delta: float) -> void:
	_elapsed += delta
	var base_target := Vector3.ZERO
	var p: Dictionary = presets.get(current_mode, presets.town)
	base_target.y = p.ty
	if follow_node:
		base_target += follow_node.global_position
	target = base_target
	var breath := sin(_elapsed * 0.45) * 0.06
	var shake := camera_shake
	var pitch: float = clamp(cam_pitch, 0.12, 1.48)
	var dist: float = clamp(cam_dist, 4.0, 55.0)
	var x: float = sin(cam_yaw) * cos(pitch) * dist
	var y: float = sin(pitch) * dist + breath
	var z: float = cos(cam_yaw) * cos(pitch) * dist
	camera.global_position = Vector3(
		target.x + x + sin(_elapsed * 83.0) * shake,
		target.y + y + sin(_elapsed * 71.0) * shake * 0.45,
		target.z + z + cos(_elapsed * 79.0) * shake
	)
	camera.look_at(target, Vector3.UP)
	if camera_shake > 0.0:
		camera_shake = max(0.0, camera_shake - delta)
