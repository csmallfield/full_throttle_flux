@tool
extends Node
class_name UtopiaSkyController
## One place to drive the Utopia sky: sun position/colour, cloud deck, wind,
## cirrus, fog/ambient sync, and god rays. Every export applies live in the
## editor. In game, call transition_to("storm_light", 8.0) to blend presets.
##
## Presets are plain dictionaries in PRESETS below: copy one, tweak, add.
## Picking a preset overwrites the individual exports; tweak them afterwards
## for one-offs (they're saved with the scene).

@export var world_environment: NodePath
@export var sun: NodePath
@export var sky_fill: NodePath

@export_enum("golden_afternoon", "clear_noon", "fair_cumulus", "storm_light", "overcast", "dusk", "night", "high_altitude") var preset := "golden_afternoon":
	set(v):
		preset = v
		if _ready_done:
			apply_preset(v)

@export_group("Sun")
@export_range(0.0, 360.0) var sun_azimuth := 215.0:   ## compass deg the light comes FROM (0 = -Z north, 90 = +X east)
	set(v): sun_azimuth = v; _apply()
@export_range(-5.0, 89.0) var sun_elevation := 23.0:
	set(v): sun_elevation = v; _apply()
@export_range(0.0, 8.0) var sun_energy := 3.0:
	set(v): sun_energy = v; _apply()
@export var sun_tint := Color(1, 1, 1):
	set(v): sun_tint = v; _apply()

@export_group("Atmosphere")
@export var zenith_color := Color(0.15, 0.29, 0.52):
	set(v): zenith_color = v; _apply()
@export var horizon_color := Color(0.93, 0.75, 0.58):
	set(v): horizon_color = v; _apply()
@export var fog_color := Color(0.74, 0.70, 0.68):
	set(v): fog_color = v; _apply()
@export_range(0.0, 0.002, 0.00001) var fog_density := 0.00014:
	set(v): fog_density = v; _apply()
@export_range(0.0, 2.0) var ambient_energy := 0.36:
	set(v): ambient_energy = v; _apply()
@export_range(0.1, 3.0) var exposure := 0.92:
	set(v): exposure = v; _apply()
## How much darker than the fog the sky is below the horizon. 0.5 suits
## grounded tracks; ~0 for sky-high tracks where you look DOWN into haze.
@export_range(0.0, 1.0) var ground_darken := 0.5:
	set(v): ground_darken = v; _apply()

@export_group("Cloud quality")
## low     = quarter-res clouds, 20 steps, 2 light taps   (cheapest)
## medium  = half-res clouds,    32 steps, 3 light taps   (v4 behaviour)
## high    = full-res clouds,    40 steps, 4 light taps   (default)
## ultra   = full-res clouds,    64 steps, 6 light taps   (screenshots)
@export_enum("low", "medium", "high", "ultra") var cloud_quality := "high":
	set(v): cloud_quality = v; _apply()
## Per-pixel dither of the cloud march. 0 = clean but can show stepping
## "slices" in thick cloud; higher = smoother volumes with fine grain.
@export_range(0.0, 1.0) var cloud_dither := 0.4:
	set(v): cloud_dither = v; _apply()

@export_group("Night")
## Stars in the dark sky (0 = none).
@export_range(0.0, 4.0) var star_intensity := 0.0:
	set(v): star_intensity = v; _apply()
## Light pollution: horizon band + lit cloud bases.
@export var city_glow_color := Color(1.0, 0.45, 0.25):
	set(v): city_glow_color = v; _apply()
@export_range(0.0, 4.0) var city_glow := 0.0:
	set(v): city_glow = v; _apply()

@export_group("Clouds")
@export_range(0.0, 1.0) var coverage := 0.52:
	set(v): coverage = v; _apply()
@export_range(0.0, 4.0) var cloud_density := 1.0:
	set(v): cloud_density = v; _apply()
@export_range(0.1, 8.0) var cloud_absorption := 1.6:
	set(v): cloud_absorption = v; _apply()
@export var cloud_bottom := 1400.0:
	set(v): cloud_bottom = v; _apply()
@export var cloud_thickness := 900.0:
	set(v): cloud_thickness = v; _apply()
@export var cloud_shadow_color := Color(0.36, 0.40, 0.52):
	set(v): cloud_shadow_color = v; _apply()
@export_range(0.0, 1.0) var cirrus_amount := 0.3:
	set(v): cirrus_amount = v; _apply()
@export_range(0.0, 360.0) var wind_direction_deg := 40.0:
	set(v): wind_direction_deg = v; _apply()
@export_range(0.0, 120.0) var wind_speed := 18.0:
	set(v): wind_speed = v; _apply()
## How much the cloud deck slides past as the camera travels (0 = painted dome).
@export_range(0.0, 1.0) var cloud_parallax := 1.0:
	set(v): cloud_parallax = v; _apply()
## Size of the individual billows (larger = bigger, smoother cloud masses).
@export_range(0.3, 3.0) var billow_size := 1.0:
	set(v): billow_size = v; _apply()
## How much fine erosion eats into the cloud edges.
@export_range(0.0, 1.0) var cloud_detail := 0.45:
	set(v): cloud_detail = v; _apply()
## 0 = crisp, hard-edged cumulus  ...  1 = soft, wispy.
@export_range(0.05, 1.0) var edge_softness := 0.4:
	set(v): edge_softness = v; _apply()
## Dim the sun when it is behind dense cover (approximate, global).
@export_range(0.0, 1.0) var cover_dims_sun := 0.6:
	set(v): cover_dims_sun = v; _apply()

@export_group("God rays")
## Screen-space shafts (CompositorEffect on the WorldEnvironment). Cheap and
## stable at race speed; needs the sun in or near frame.
@export var god_rays := true:
	set(v): god_rays = v; _apply()
@export_range(0.0, 4.0) var god_ray_intensity := 0.45:
	set(v): god_ray_intensity = v; _apply()
## True volumetric shafts through the architecture (Forward+ volumetric fog).
## Heavier, and its temporal reprojection smears at full race speed -- great
## for menus, replays and photo mode.
@export var volumetric_shafts := false:
	set(v): volumetric_shafts = v; _apply()
@export_range(0.0, 0.1, 0.0005) var volumetric_density := 0.01:
	set(v): volumetric_density = v; _apply()

const PRESETS := {
	"night": {"sun_azimuth": 150.0, "sun_elevation": 38.0, "sun_energy": 0.32, "sun_tint": Color(0.62, 0.74, 1.0),
		"zenith_color": Color(0.008, 0.012, 0.035), "horizon_color": Color(0.05, 0.045, 0.09), "fog_color": Color(0.09, 0.075, 0.13),
		"fog_density": 0.0006, "ambient_energy": 0.2, "exposure": 1.3, "ground_darken": 0.5,
		"coverage": 0.35, "cloud_density": 0.8, "cloud_absorption": 1.8, "cloud_shadow_color": Color(0.03, 0.03, 0.06),
		"cirrus_amount": 0.0, "wind_speed": 12.0, "god_ray_intensity": 0.0,
		"star_intensity": 1.2, "city_glow": 0.45, "city_glow_color": Color(0.95, 0.5, 0.35)},
	"golden_afternoon": {"sun_azimuth": 215.0, "sun_elevation": 23.0, "sun_energy": 3.0, "sun_tint": Color(1, 1, 1),
		"zenith_color": Color(0.15, 0.29, 0.52), "horizon_color": Color(0.93, 0.75, 0.58), "fog_color": Color(0.74, 0.70, 0.68),
		"fog_density": 0.00014, "ambient_energy": 0.36, "exposure": 0.92, "ground_darken": 0.5,
		"coverage": 0.52, "cloud_density": 1.1, "cloud_absorption": 1.8, "cloud_shadow_color": Color(0.38, 0.40, 0.52),
		"cirrus_amount": 0.2, "wind_speed": 18.0, "god_ray_intensity": 0.45, "star_intensity": 0.0, "city_glow": 0.0},
	"clear_noon": {"sun_azimuth": 200.0, "sun_elevation": 62.0, "sun_energy": 3.4, "sun_tint": Color(1, 1, 1),
		"zenith_color": Color(0.09, 0.28, 0.66), "horizon_color": Color(0.70, 0.81, 0.94), "fog_color": Color(0.72, 0.79, 0.88),
		"fog_density": 0.00012, "ambient_energy": 0.45, "exposure": 0.85, "ground_darken": 0.5,
		"coverage": 0.28, "cloud_density": 0.9, "cloud_absorption": 1.4, "cloud_shadow_color": Color(0.45, 0.52, 0.65),
		"cirrus_amount": 0.15, "wind_speed": 12.0, "god_ray_intensity": 0.2, "star_intensity": 0.0, "city_glow": 0.0},
	"fair_cumulus": {"sun_azimuth": 220.0, "sun_elevation": 42.0, "sun_energy": 3.2, "sun_tint": Color(1, 1, 1),
		"zenith_color": Color(0.11, 0.31, 0.64), "horizon_color": Color(0.78, 0.85, 0.94), "fog_color": Color(0.74, 0.80, 0.88),
		"fog_density": 0.00013, "ambient_energy": 0.42, "exposure": 0.88, "ground_darken": 0.5,
		"coverage": 0.55, "cloud_density": 1.2, "cloud_absorption": 1.8, "cloud_shadow_color": Color(0.42, 0.47, 0.60),
		"cirrus_amount": 0.1, "wind_speed": 22.0, "god_ray_intensity": 0.35, "star_intensity": 0.0, "city_glow": 0.0},
	"storm_light": {"sun_azimuth": 230.0, "sun_elevation": 14.0, "sun_energy": 3.6, "sun_tint": Color(1, 0.95, 0.9),
		"zenith_color": Color(0.17, 0.20, 0.28), "horizon_color": Color(0.82, 0.60, 0.44), "fog_color": Color(0.52, 0.50, 0.50),
		"fog_density": 0.0002, "ambient_energy": 0.24, "exposure": 1.0, "ground_darken": 0.5,
		"coverage": 0.8, "cloud_density": 1.7, "cloud_absorption": 2.6, "cloud_shadow_color": Color(0.20, 0.22, 0.30),
		"cirrus_amount": 0.0, "wind_speed": 40.0, "god_ray_intensity": 1.0, "star_intensity": 0.0, "city_glow": 0.0},
	"overcast": {"sun_azimuth": 215.0, "sun_elevation": 35.0, "sun_energy": 0.7, "sun_tint": Color(0.95, 0.97, 1.0),
		"zenith_color": Color(0.52, 0.56, 0.62), "horizon_color": Color(0.74, 0.75, 0.77), "fog_color": Color(0.70, 0.71, 0.73),
		"fog_density": 0.0003, "ambient_energy": 0.95, "exposure": 1.05, "ground_darken": 0.5,
		"coverage": 1.0, "cloud_density": 1.3, "cloud_absorption": 2.0, "cloud_shadow_color": Color(0.50, 0.52, 0.58),
		"cirrus_amount": 0.0, "wind_speed": 14.0, "god_ray_intensity": 0.0, "star_intensity": 0.0, "city_glow": 0.0},
	# Swoopy: thin, clean air high above a hazy city. Deep zenith, pale
	# horizon, fair-weather cumulus up high, crisp sun.
	"high_altitude": {"sun_azimuth": 205.0, "sun_elevation": 33.0, "sun_energy": 3.3, "sun_tint": Color(1, 0.98, 0.95),
		"zenith_color": Color(0.05, 0.20, 0.52), "horizon_color": Color(0.74, 0.82, 0.92), "fog_color": Color(0.70, 0.78, 0.88),
		"fog_density": 0.00016, "ambient_energy": 0.42, "exposure": 0.86, "ground_darken": 0.04,
		"coverage": 0.42, "cloud_density": 1.0, "cloud_absorption": 1.6, "cloud_shadow_color": Color(0.44, 0.50, 0.64),
		"cirrus_amount": 0.3, "wind_speed": 26.0, "god_ray_intensity": 0.3, "star_intensity": 0.0, "city_glow": 0.0},
	"dusk": {"sun_azimuth": 250.0, "sun_elevation": 4.0, "sun_energy": 1.8, "sun_tint": Color(1, 0.9, 0.85),
		"zenith_color": Color(0.09, 0.11, 0.28), "horizon_color": Color(1.0, 0.50, 0.28), "fog_color": Color(0.56, 0.40, 0.38),
		"fog_density": 0.00018, "ambient_energy": 0.22, "exposure": 1.1, "ground_darken": 0.5,
		"coverage": 0.35, "cloud_density": 1.0, "cloud_absorption": 1.6, "cloud_shadow_color": Color(0.25, 0.20, 0.32),
		"cirrus_amount": 0.35, "wind_speed": 10.0, "god_ray_intensity": 0.8, "star_intensity": 0.0, "city_glow": 0.0},
}

const SKY_DIR := "res://scenes/tracks/utopia/sky/"
## quality -> [shader variant, march steps, light steps]
const QUALITY := {
	"low": ["quarter", 20, 2],
	"medium": ["half", 32, 3],
	"high": ["full", 40, 4],
	"ultra": ["full", 64, 6],
}

var _ready_done := false
var _suspend := false
var _tween: Tween

func _ready() -> void:
	_ready_done = true
	_apply()

## Snap to a preset.
func apply_preset(name: String) -> void:
	if not PRESETS.has(name):
		push_warning("UtopiaSkyController: unknown preset " + name)
		return
	_suspend = true
	for k in PRESETS[name]:
		set(k, PRESETS[name][k])
	_suspend = false
	_apply()

## Blend to a preset over `seconds` (runtime weather changes).
func transition_to(name: String, seconds := 6.0) -> void:
	if not PRESETS.has(name):
		return
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	for k in PRESETS[name]:
		_tween.tween_property(self, k, PRESETS[name][k], seconds)

## Light colour for a sun elevation: deep orange at the horizon -> near white.
static func sun_color_for(elev: float) -> Color:
	var keys := [[-2.0, Color(0.9, 0.3, 0.15)], [4.0, Color(1.0, 0.5, 0.27)], [12.0, Color(1.0, 0.68, 0.46)],
		[23.0, Color(1.0, 0.80, 0.60)], [40.0, Color(1.0, 0.91, 0.80)], [70.0, Color(1.0, 0.97, 0.93)]]
	if elev <= keys[0][0]:
		return keys[0][1]
	for i in range(keys.size() - 1):
		if elev <= keys[i + 1][0]:
			var t: float = (elev - keys[i][0]) / (keys[i + 1][0] - keys[i][0])
			return (keys[i][1] as Color).lerp(keys[i + 1][1], t)
	return keys[-1][1]

func sun_direction() -> Vector3:
	## Unit vector pointing TOWARD the sun.
	var az := deg_to_rad(sun_azimuth)
	var el := deg_to_rad(sun_elevation)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)).normalized()

func _apply() -> void:
	if _suspend or not is_inside_tree():
		return
	var to_sun := sun_direction()
	var cover_dim := 1.0 - cover_dims_sun * smoothstep(0.55, 1.0, coverage)
	var s := get_node_or_null(sun) as DirectionalLight3D
	if s:
		s.transform = Transform3D(Basis.looking_at(-to_sun, Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD), s.transform.origin)
		s.light_color = sun_color_for(sun_elevation) * sun_tint
		s.light_energy = sun_energy * cover_dim * smoothstep(-4.0, 3.0, sun_elevation)
		s.light_volumetric_fog_energy = 1.4 if volumetric_shafts else 0.0
	var f := get_node_or_null(sky_fill) as DirectionalLight3D
	if f:
		var fill_from := Vector3(-to_sun.x, 0.6, -to_sun.z).normalized()
		f.transform = Transform3D(Basis.looking_at(-fill_from, Vector3.UP), f.transform.origin)
		f.light_color = zenith_color.lerp(Color(0.6, 0.7, 0.95), 0.5)
		f.light_energy = 0.16 + 0.25 * coverage
	var we := get_node_or_null(world_environment) as WorldEnvironment
	if we == null or we.environment == null:
		return
	var env := we.environment
	env.fog_light_color = fog_color
	env.fog_density = fog_density
	env.ambient_light_energy = ambient_energy
	env.tonemap_exposure = exposure
	env.volumetric_fog_enabled = volumetric_shafts
	env.volumetric_fog_density = volumetric_density
	env.volumetric_fog_albedo = fog_color
	env.volumetric_fog_length = 450.0
	env.volumetric_fog_anisotropy = 0.7
	env.volumetric_fog_ambient_inject = 1.0     # lit by the sky too, so it never just darkens
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_detail_spread = 1.5
	var mat := env.sky.sky_material as ShaderMaterial if env.sky else null
	if mat:
		var q: Array = QUALITY[cloud_quality]
		var sh: Shader = load(SKY_DIR + "utopia_sky_%s.gdshader" % q[0])
		if mat.shader != sh:
			mat.shader = sh
		mat.set_shader_parameter("march_steps", q[1])
		mat.set_shader_parameter("light_steps", q[2])
		mat.set_shader_parameter("jitter", cloud_dither)
		mat.set_shader_parameter("shape_noise", load(SKY_DIR + "cloud_shape_128.res"))
		mat.set_shader_parameter("detail_noise", load(SKY_DIR + "cloud_detail_64.res"))
		mat.set_shader_parameter("weather_map", load(SKY_DIR + "cloud_weather.tres"))
		mat.set_shader_parameter("shape_scale", 0.00045 / billow_size)
		mat.set_shader_parameter("detail_scale", 0.0021 / billow_size)
		mat.set_shader_parameter("detail_strength", cloud_detail)
		mat.set_shader_parameter("edge_softness", edge_softness)
	if mat:
		mat.set_shader_parameter("zenith_color", zenith_color)
		mat.set_shader_parameter("horizon_color", horizon_color)
		mat.set_shader_parameter("ground_color", fog_color.darkened(ground_darken))
		mat.set_shader_parameter("coverage", coverage)
		mat.set_shader_parameter("density", cloud_density)
		mat.set_shader_parameter("cloud_absorption", cloud_absorption)
		mat.set_shader_parameter("cloud_bottom", cloud_bottom)
		mat.set_shader_parameter("cloud_thickness", cloud_thickness)
		mat.set_shader_parameter("cloud_shadow_color", cloud_shadow_color)
		mat.set_shader_parameter("cloud_light_color", Color(1, 0.95, 0.9))
		mat.set_shader_parameter("cirrus_amount", cirrus_amount)
		var wd := deg_to_rad(wind_direction_deg)
		mat.set_shader_parameter("wind_direction", Vector2(sin(wd), -cos(wd)))
		mat.set_shader_parameter("wind_speed", wind_speed)
		mat.set_shader_parameter("parallax", cloud_parallax)
		mat.set_shader_parameter("star_intensity", star_intensity)
		mat.set_shader_parameter("city_glow", city_glow)
		mat.set_shader_parameter("city_glow_color", city_glow_color)
	if we.compositor:
		for e in we.compositor.compositor_effects:
			if e is UtopiaGodRays:
				e.enabled = god_rays and god_ray_intensity > 0.0
				e.intensity = god_ray_intensity
				e.sun_direction = to_sun
				e.tint = sun_color_for(sun_elevation) * sun_tint
