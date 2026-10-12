class_name CameraRig
extends Node3D
## 轨道相机 v2：
## - 两种视角模式（V 键切换）：follow 自由环绕跟随 / lock 锁定角色背身视角。
## - 所有镜头参数（目标点/偏航/俯仰/距离）经 0.25s 指数平滑插值，切换无跳变。
## - 支持自定义视角距离 cam_dist 与屏幕偏移 cam_offset（横向/纵向），滚轮缩放联动。
## - 保留低视角/经典/越肩三预设与拖拽旋转、震屏。

signal preset_changed(name: String)

const SMOOTH_TIME := 0.25  # 平滑过渡时长（秒），处于 0.2-0.3 区间

var cam_yaw := 0.0            # follow 模式：用户控制的环绕偏航
var cam_pitch := 0.55
var cam_dist := 14.0          # 自定义视角距离（滚轮可调）
var cam_offset := Vector2(0.0, 0.0)  # 自定义屏幕偏移：x=横向世界偏移, y=目标高度增量
var lock_mode := false        # false=follow 跟随角色（自由环绕）, true=lock 锁定背身视角
var hover_target: Node3D = null  # 鼠标悬停的敌人（世界写入）
var camera_shake := 0.0
var camera: Camera3D
var follow_node: Node3D = null  # 跟随目标（Main 写入）

var presets := {
	"selection": {"yaw": 0.3, "pitch": 0.62, "dist": 9.0, "ty": 1.3},
	"town": {"yaw": 0.5, "pitch": 0.75, "dist": 22.0, "ty": 1.05},
	"dungeon": {"yaw": 0.0, "pitch": 0.95, "dist": 14.0, "ty": 1.1},
	"overworld": {"yaw": 0.4, "pitch": 0.72, "dist": 18.0, "ty": 1.1},
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
# 平滑状态（实际渲染值，逐帧逼近期望值）。
var _sm_target := Vector3.ZERO
var _sm_yaw := 0.0
var _sm_pitch := 0.55
var _sm_dist := 14.0

func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 48.0
	camera.near = 0.1
	camera.far = 260.0
	add_child(camera)
	camera.current = true
	_sm_yaw = cam_yaw
	_sm_pitch = cam_pitch
	_sm_dist = cam_dist

func set_mode(mode: String) -> void:
	current_mode = mode
	reset()

func reset() -> void:
	var p: Dictionary = presets.get(current_mode, presets.town)
	var off: Dictionary = preset_offsets.get(current_preset, preset_offsets.classic)
	cam_yaw = p.yaw
	cam_pitch = clamp(p.pitch + off.pitch, 0.12, 1.48)
	cam_dist = p.dist * off.dist_mul

## 视角模式切换（V 键）。返回切换后的模式名。
func toggle_lock() -> String:
	lock_mode = not lock_mode
	return "lock" if lock_mode else "follow"

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
		return false  # 让点击穿透用于选中。
	return false

func handle_mouse_motion(event: InputEventMouseMotion, ui_blocked: bool) -> void:
	if _dragging and not ui_blocked:
		var d := event.position - _drag_last
		_drag_distance += abs(d.x) + abs(d.y)
		if not lock_mode:
			cam_yaw += d.x * 0.005
		else:
			cam_yaw += d.x * 0.002  # 锁定视角下允许微调朝向补偿
		cam_pitch = clamp(cam_pitch + d.y * 0.004, 0.12, 1.48)
		_drag_last = event.position

func was_click() -> bool:
	return _drag_distance < 7.0

## 指数平滑：帧率无关，SMOOTH_TIME 内完成 ~95% 过渡。
func _smooth(current: float, want: float, delta: float) -> float:
	var k := 1.0 - exp(-delta / SMOOTH_TIME)
	return lerp(current, want, k)

func _smooth_angle(current: float, want: float, delta: float) -> float:
	var k := 1.0 - exp(-delta / SMOOTH_TIME)
	return lerp_angle(current, want, k)

func _process(delta: float) -> void:
	_elapsed += delta
	var p: Dictionary = presets.get(current_mode, presets.town)
	var base_target := Vector3.ZERO
	base_target.y = p.ty
	if follow_node:
		base_target += follow_node.global_position
	# 期望参数。
	var want_yaw := cam_yaw
	var want_dist := clampf(cam_dist, 4.0, 55.0)
	var want_pitch := clampf(cam_pitch, 0.12, 1.48)
	if lock_mode and follow_node:
		# 锁定视角：偏航贴住角色背身方向，距离收近。
		want_yaw = follow_node.rotation.y + PI
		want_dist = clamp(want_dist * 0.62, 3.5, 30.0)
		want_pitch = 0.68
	# 平滑逼近（0.25s 过渡，无跳变）。
	_sm_yaw = _smooth_angle(_sm_yaw, want_yaw, delta)
	_sm_pitch = _smooth_angle(_sm_pitch, want_pitch, delta)
	_sm_dist = _smooth(_sm_dist, want_dist, delta)
	_sm_target = _sm_target.lerp(base_target + Vector3(cam_offset.x, cam_offset.y, 0.0), 1.0 - exp(-delta / SMOOTH_TIME))
	# 呼吸感 + 震屏。
	var breath := sin(_elapsed * 0.45) * 0.06
	var shake := camera_shake
	var x: float = sin(_sm_yaw) * cos(_sm_pitch) * _sm_dist
	var y: float = sin(_sm_pitch) * _sm_dist + breath
	var z: float = cos(_sm_yaw) * cos(_sm_pitch) * _sm_dist
	camera.global_position = Vector3(
		_sm_target.x + x + sin(_elapsed * 83.0) * shake,
		_sm_target.y + y + sin(_elapsed * 71.0) * shake * 0.45,
		_sm_target.z + z + cos(_elapsed * 79.0) * shake
	)
	camera.look_at(_sm_target, Vector3.UP)
	if camera_shake > 0.0:
		camera_shake = max(0.0, camera_shake - delta)
