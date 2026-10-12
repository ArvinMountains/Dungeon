class_name UIMinimap
extends Control
## 小地图（左上常驻）：固定北向 + 以世界中点适配，滚轮缩放，点击标记即寻路。
## - 数据来自各世界的 minimap_data()（矩形障碍=建筑/城墙、圆形障碍、标记点）。
## - 标记分型：兴趣点(方)、敌对(红点)、目标(金环)、玩家(朝向箭头)；超出视野的标记钉在边缘并降透明度。
## - 状态优先用形状表达，颜色只做辅助（文字标记用单字，避免缺字符）。

signal mark_clicked(id: String)

const ZOOM_MIN := 1.0
const ZOOM_MAX := 2.6
const REFRESH := 0.12          # 静态数据（建筑/标记）刷新间隔（秒）

var world = null               # 当前世界的 Node3D（需实现 minimap_data()）
var zoom := 1.0
var _center := Vector2.ZERO    # 视野中心（世界 xz）
var _view_r := 60.0            # 视野半径（米）
var _world_r := 60.0           # 世界半径（米）
var _k := 1.0                  # 像素/米
var _rects: Array = []
var _circs: Array = []
var _zones: Array = []         # 地貌带：[{z_max, color}]，按顺序铺满整个纬度
var _marks: Array = []
var _player := Vector3.ZERO
var _yaw := 0.0
var _tracked := ""
var _t := 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(150, 150)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "小地图：滚轮缩放，点击图标自动前往"

## 切换跟随的世界（Main 在切场景时调用）。
func bind(w) -> void:
	world = w
	_marks.clear()
	_rects.clear()
	_circs.clear()
	_zones.clear()
	_t = REFRESH  # 立即刷新一次

## 高亮当前追踪的任务目标（传兴趣点 id）。
func set_tracked(id: String) -> void:
	_tracked = id

func _process(delta: float) -> void:
	_t += delta
	if world == null:
		queue_redraw()
		return
	if _t >= REFRESH:
		_t = 0.0
		_pull_data()
	# 玩家位置/朝向每帧直读，保证箭头跟手。
	var p = world.get("player")
	if p is Node3D:
		_player = p.global_position
		_yaw = p.rotation.y
	queue_redraw()

func _pull_data() -> void:
	if world == null or not world.has_method("minimap_data"):
		return
	var d: Dictionary = world.minimap_data()
	_world_r = float(d.get("half", 60.0))
	_rects = d.get("rects", [])
	_circs = d.get("circs", [])
	_zones = d.get("zones", [])
	_marks = d.get("marks", [])

## 世界坐标(xz) → 控件坐标。
func _w2m(x: float, z: float) -> Vector2:
	return size * 0.5 + Vector2(x - _center.x, z - _center.y) * _k

## 当前视野中心与比例。
func _update_projection() -> void:
	var half := maxf(_world_r, 1.0)
	_view_r = half / clampf(zoom, ZOOM_MIN, ZOOM_MAX)
	_k = minf(size.x, size.y) * 0.5 / maxf(_view_r, 1.0)
	# 视野不得超出世界边界（放大后跟随玩家，缩小时回到中心）。
	var span := maxf(half - _view_r, 0.0)
	_center = Vector2(clampf(_player.x, -span, span), clampf(_player.z, -span, span))

func _draw() -> void:
	_update_projection()
	# 底板与外框。
	var bg := Rect2(Vector2.ZERO, size)
	draw_rect(bg, Color(0.045, 0.058, 0.052, 0.88), true)
	draw_rect(bg, Color(0.34, 0.30, 0.19, 0.9), false, 1.0)
	# 世界边界。
	var tl := _w2m(-_world_r, -_world_r)
	var br := _w2m(_world_r, _world_r)
	draw_rect(Rect2(tl, br - tl), Color(0.30, 0.34, 0.28, 0.55), false, 1.0)
	# 地貌带（如野外：北山/南林），从北往南依次铺满。
	for z in _zones:
		var z_max := float(z.get("z_max", 0.0))
		var z_min := float(z.get("z_min", -_world_r))
		var za := _w2m(-_world_r, z_min)
		var zb := _w2m(_world_r, z_max)
		draw_rect(Rect2(za, zb - za), z.get("color", Color(0.2, 0.25, 0.2, 0.35)), true)
	# 矩形障碍（建筑/城墙）。
	for r in _rects:
		var a := _w2m(float(r.x) - float(r.hw), float(r.z) - float(r.hd))
		var b := _w2m(float(r.x) + float(r.hw), float(r.z) + float(r.hd))
		draw_rect(Rect2(a, b - a), Color(0.52, 0.50, 0.44, 0.85), true)
	# 圆形障碍（树/岩/灯）。
	for c in _circs:
		var p := _w2m(float(c.x), float(c.z))
		if p.x < -20 or p.y < -20 or p.x > size.x + 20 or p.y > size.y + 20: continue
		draw_circle(p, maxf(float(c.r) * _k, 1.0), Color(0.34, 0.40, 0.32, 0.8))
	# 标记。
	var font := get_theme_default_font()
	for m in _marks:
		var pos: Vector3 = m.get("pos", Vector3.ZERO)
		var p := _w2m(pos.x, pos.z)
		var clamped := false
		var margin := 8.0
		var cp := Vector2(clampf(p.x, margin, size.x - margin), clampf(p.y, margin, size.y - margin))
		if cp != p:
			clamped = true
			p = cp
		var alpha := 0.45 if clamped else 1.0
		match String(m.get("kind", "poi")):
			"enemy":
				draw_circle(p, 2.6, Color(0.85, 0.30, 0.26, alpha))
			"camp":
				draw_circle(p, 3.4, Color(0.98, 0.62, 0.28, alpha))
				draw_circle(p, 6.0, Color(0.98, 0.62, 0.28, alpha * 0.35), false, 1.0)
			"exit":
				var s := 5.0
				draw_rect(Rect2(p - Vector2(s, s), Vector2(s, s) * 2.0), Color(0.60, 0.45, 0.95, alpha), true)
			_:
				# 兴趣点：方块 + 单字。
				var is_tracked: bool = String(m.get("id", "")) == _tracked
				var col := UiKit.GOLD if is_tracked else Color(0.72, 0.66, 0.48)
				draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), Color(col.r, col.g, col.b, alpha), true)
				if is_tracked:
					draw_circle(p, 9.0, Color(col.r, col.g, col.b, alpha * 0.8), false, 1.0)
				var short := String(m.get("short", ""))
				if short != "" and font != null:
					var sz := 9
					var tw := font.get_string_size(short, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
					draw_string(font, p + Vector2(-tw * 0.5, 3.4), short, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0.10, 0.09, 0.07, alpha))
	# 玩家朝向箭头。
	var pc := _w2m(_player.x, _player.z)
	var dir := Vector2(sin(_yaw), cos(_yaw))
	var perp := Vector2(-dir.y, dir.x)
	var tri := PackedVector2Array([pc + dir * 7.5, pc + perp * 5.0 - dir * 4.5, pc - perp * 5.0 - dir * 4.5])
	draw_colored_polygon(tri, Color(0.95, 0.92, 0.80))
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(0.25, 0.20, 0.12), 1.0)
	# 北向标记。
	if font != null:
		draw_string(font, Vector2(size.x * 0.5 - 4.0, 12.0), "北", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UiKit.TEXT_DIM)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom = clampf(zoom + 0.25, ZOOM_MIN, ZOOM_MAX)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom = clampf(zoom - 0.25, ZOOM_MIN, ZOOM_MAX)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var hit := _pick_mark(event.position)
			if hit != "":
				mark_clicked.emit(hit)
			accept_event()

func _pick_mark(local: Vector2) -> String:
	var best := ""
	var best_d := 14.0
	for m in _marks:
		if String(m.get("kind", "poi")) == "enemy": continue
		var pos: Vector3 = m.get("pos", Vector3.ZERO)
		var d := _w2m(pos.x, pos.z).distance_to(local)
		if d < best_d:
			best_d = d
			best = String(m.get("id", ""))
	return best
