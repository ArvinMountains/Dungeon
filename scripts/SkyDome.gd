class_name SkyDome
extends Node3D
## 程序化天空穹顶 + 昼夜光照联动。对应 main.js updateDayNight。

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var hemi: DirectionalLight3D  # 用方向光近似半球补光（Godot 4 无 HemisphereLight，用 WorldEnvironment 处理环境）
var world_env: WorldEnvironment
var env: Environment

const DAY_TOP := Color(0.36, 0.53, 0.72)
const DAY_BOTTOM := Color(0.79, 0.84, 0.81)
const DUSK_TOP := Color(0.43, 0.29, 0.32)
const DUSK_BOTTOM := Color(0.75, 0.54, 0.35)
const NIGHT_TOP := Color(0.05, 0.08, 0.13)
const NIGHT_BOTTOM := Color(0.10, 0.15, 0.20)

const FOG_DAY := Color(0.73, 0.77, 0.74)
const FOG_DUSK := Color(0.43, 0.36, 0.30)
const FOG_NIGHT := Color(0.07, 0.09, 0.12)

func _ready() -> void:
	world_env = WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = NIGHT_BOTTOM
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.77, 0.67)
	env.ambient_light_energy = 1.25
	env.fog_enabled = true
	env.fog_light_color = FOG_NIGHT
	env.fog_density = 0.037
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.35
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.position = Vector3(8, 18, 6)
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.61, 0.73, 0.66)
	moon.light_energy = 2.1
	moon.shadow_enabled = true
	moon.position = Vector3(-5, 12, 6)
	add_child(moon)

	hemi = DirectionalLight3D.new()
	hemi.light_color = Color(0.7, 0.77, 0.67)
	hemi.light_energy = 0.4
	hemi.shadow_enabled = false
	hemi.rotation_degrees = Vector3(-90, 0, 0)
	add_child(hemi)

func update_from_time(hours: float, day_factor: float, night_factor: float, horizon: float) -> void:
	var sun_angle := ((hours - 6.0) / 24.0) * TAU
	var sun_height := sin(sun_angle)
	# Sky / ambient.
	var top: Color = NIGHT_TOP.lerp(DUSK_TOP, horizon * 0.9).lerp(DAY_TOP, day_factor)
	var bottom: Color = NIGHT_BOTTOM.lerp(DUSK_BOTTOM, horizon * 0.85).lerp(DAY_BOTTOM, day_factor)
	env.background_color = bottom
	env.ambient_light_color = Color(0.16,0.21,0.31).lerp(Color(0.7,0.77,0.67), day_factor)
	env.ambient_light_energy = 0.35 + day_factor * 1.25
	# Fog.
	env.fog_light_color = FOG_NIGHT.lerp(FOG_DUSK, horizon * 0.6).lerp(FOG_DAY, day_factor)
	env.fog_density = 0.022 + night_factor * 0.012
	env.tonemap_exposure = 0.75 + day_factor * 0.85
	# Sun / moon.
	sun.position = Vector3(cos(sun_angle) * 20.0, max(sun_height * 20.0, -5.0), 8.0)
	sun.look_at(Vector3.ZERO, Vector3.UP)
	sun.light_energy = day_factor * 2.4
	moon.light_energy = night_factor * 1.9 + 0.15
	moon.position = Vector3(-cos(sun_angle) * 15.0, max(-sun_height * 15.0, 5.0), 6.0)
	moon.look_at(Vector3.ZERO, Vector3.UP)
