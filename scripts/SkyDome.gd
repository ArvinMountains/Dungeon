class_name SkyDome
extends Node3D
## 电影级光照与大气系统（上古卷轴风格）：
## - 自定义 sky shader：天空梯度 + 太阳盘/光晕 + 月盘 + 星空，随昼夜实时演进。
## - Environment：天空环境光（跟随天空色温）+ 体积雾（丁达尔阳光）+ 高度雾（大气透视）
##   + SSAO/SSIL 接触阴影 + 辉光 + ACES 色调映射与色彩分级。
## - 太阳/月亮方向光：低角度长投影、PCF 软阴影、体积光能量（god rays）。
## - 地下城等室内场景：set_interior(true) 自动压低环境光、加浓体积雾，保住幽暗氛围。

# 天空着色器（内联，避免额外资源依赖）：EYEDIR 为视线方向。
const SKY_CODE := """
shader_type sky;

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float day_mix = 1.0;
uniform float night_mix = 0.0;
uniform float horizon_mix = 0.0;
uniform float sun_strength = 1.0;
uniform float star_amount = 0.0;
uniform vec3 zenith_col = vec3(0.20, 0.38, 0.66);
uniform vec3 horizon_col = vec3(0.80, 0.83, 0.80);
uniform vec3 night_zenith = vec3(0.02, 0.04, 0.09);
uniform vec3 night_horizon = vec3(0.06, 0.09, 0.15);
uniform vec3 dusk_col = vec3(0.95, 0.42, 0.18);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = dir.y;

	vec3 zenith = mix(night_zenith, zenith_col, day_mix);
	vec3 horiz = mix(night_horizon, horizon_col, day_mix);
	// 黄昏：地平线附近的暖橙带。
	float dusk_band = horizon_mix * pow(clamp(1.0 - abs(h) * 2.2, 0.0, 1.0), 1.4);
	horiz = mix(horiz, dusk_col, clamp(dusk_band * 0.85, 0.0, 0.85));

	// 天顶 → 地平线梯度。
	float t = pow(clamp(h, 0.0, 1.0), 0.42);
	vec3 col = mix(horiz, zenith, t);

	// 太阳盘 + 多层光晕。
	float sd = clamp(dot(dir, normalize(sun_dir)), -1.0, 1.0);
	float disk = smoothstep(0.99950, 0.99985, sd);
	float halo = pow(max(sd, 0.0), 900.0) * 1.0 + pow(max(sd, 0.0), 24.0) * 0.12 + pow(max(sd, 0.0), 6.0) * 0.02;
	vec3 sun_col = mix(vec3(1.0, 0.40, 0.12), vec3(1.0, 0.95, 0.85), 1.0 - horizon_mix);
	col += sun_col * (halo + disk * 6.0) * sun_strength;

	// 月亮 + 月晕。
	float md = clamp(dot(dir, normalize(moon_dir)), -1.0, 1.0);
	float mdisk = smoothstep(0.99960, 0.99990, md);
	col += vec3(0.72, 0.78, 0.92) * (mdisk * 4.0 + pow(max(md, 0.0), 1400.0) * 0.6) * night_mix;

	// 星空（夜间、地平线以上）。
	if (star_amount > 0.001 && h > 0.02) {
		vec3 sp = floor(dir * 160.0);
		float n = hash13(sp);
		float star = smoothstep(0.9972, 1.0, n);
		float tw = 0.6 + 0.4 * hash13(sp + 11.7);
		col += vec3(0.9, 0.93, 1.0) * star * tw * star_amount * 2.4;
	}

	// 地面方向的雾色回填（避免地平线以下出现空洞）。
	col = mix(col, vec3(0.58, 0.60, 0.58) * (0.25 + day_mix * 0.75), clamp(-h * 2.5, 0.0, 1.0));

	COLOR = col;
}
"""

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var world_env: WorldEnvironment
var env: Environment
var sky: Sky
var sky_mat: ShaderMaterial

var _interior := false

func _ready() -> void:
	_build_environment()
	_build_lights()
	# 首帧先按当前时间落一次参数，避免启动瞬间出现过曝/全黑。
	update_from_time(GameState.day_time, GameState.day_factor(), GameState.night_factor(), GameState.horizon_factor())

# ---------------- 环境 ----------------
func _build_environment() -> void:
	var sh := Shader.new()
	sh.code = SKY_CODE
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = sh
	sky = Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# 环境光取自天空（色温随昼夜自然变化），并叠加接触阴影。
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.65
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.background_energy_multiplier = 1.0
	# 色调映射与分级（ACES + 对比/饱和提升，靠拢上古卷轴的暖调）。
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.10
	env.adjustment_saturation = 1.15
	# 辉光：火光/魔法/水面高光的泛光（克制，避免整体发糊）。
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.3
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	# 接触阴影（屏幕空间）。
	env.ssao_enabled = true
	env.ssao_radius = 1.7
	env.ssao_intensity = 1.5
	env.ssao_power = 1.5
	env.ssao_detail = 0.5
	env.ssil_enabled = true
	env.ssil_intensity = 0.55
	env.ssil_radius = 2.0
	# 不做雾：视角拉远时也必须看清全场，深度雾与体积雾全部关闭。
	env.fog_enabled = false
	env.volumetric_fog_enabled = false

	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

# ---------------- 方向光 ----------------
func _build_lights() -> void:
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 3.0
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.8
	sun.shadow_blur = 1.6
	sun.light_angular_distance = 1.2  # 太阳张角 → 阴影半影柔和
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 1.5
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.62, 0.72, 0.90)
	moon.light_energy = 0.6
	moon.shadow_enabled = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 110.0
	moon.shadow_blur = 2.0
	moon.light_angular_distance = 1.6
	add_child(moon)

# ---------------- 室内/室外 ----------------
## 地下城等室内场景：压低环境光、降低曝光，维持幽暗氛围（不做雾）。
func set_interior(v: bool) -> void:
	_interior = v

# ---------------- 每帧驱动 ----------------
func update_from_time(hours: float, day: float, night: float, horizon: float) -> void:
	var sun_angle := ((hours - 6.0) / 24.0) * TAU
	var sun_height := sin(sun_angle)
	# 太阳方向（略微偏北，长影子更自然），月亮取反向。
	var sd := Vector3(cos(sun_angle), sun_height, -0.35).normalized()
	var md := -sd

	# —— 天空 ——
	var dusk := clampf(horizon - day * 0.25, 0.0, 1.0)
	sky_mat.set_shader_parameter("sun_dir", sd)
	sky_mat.set_shader_parameter("moon_dir", md)
	sky_mat.set_shader_parameter("day_mix", day)
	sky_mat.set_shader_parameter("night_mix", night)
	sky_mat.set_shader_parameter("horizon_mix", dusk)
	sky_mat.set_shader_parameter("sun_strength", clampf(day * 1.2 + dusk * 0.7, 0.0, 1.8))
	sky_mat.set_shader_parameter("star_amount", clampf(night - 0.15, 0.0, 1.0))
	sky_mat.set_shader_parameter("zenith_col", Color(0.05, 0.08, 0.14).lerp(Color(0.20, 0.38, 0.66), day))
	sky_mat.set_shader_parameter("horizon_col", Color(0.10, 0.14, 0.20).lerp(Color(0.80, 0.83, 0.80), day))

	# —— 环境光 ——
	var amb := 0.22 + day * 0.72
	if _interior: amb *= 0.38
	env.ambient_light_energy = amb

	# —— 太阳 ——
	sun.position = sd * 60.0
	sun.look_at(Vector3.ZERO, Vector3.UP)
	sun.light_color = Color(1.0, 0.52, 0.22).lerp(Color(1.0, 0.96, 0.89), clampf(sun_height * 1.6, 0.0, 1.0))
	sun.light_energy = day * 2.8 + dusk * 0.4
	# 室内（地下城）屏蔽日月方向光，只保留火把/烛光，维持幽暗氛围。
	sun.visible = (not _interior) and sun_height > -0.08

	# —— 月亮 ——
	moon.position = md * 60.0
	moon.look_at(Vector3.ZERO, Vector3.UP)
	moon.light_energy = night * 0.85 + 0.04
	moon.visible = (not _interior) and night > 0.02

	# —— 曝光（不驱动雾：全局已关闭深度雾与体积雾）——
	env.tonemap_exposure = (0.95 + day * 0.15) * (0.90 if _interior else 1.0)
	env.background_energy_multiplier = (0.85 + day * 0.30) * (0.35 if _interior else 1.0)
