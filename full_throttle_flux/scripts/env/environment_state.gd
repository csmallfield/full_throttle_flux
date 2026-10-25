extends Node
class_name EnvironmentState
## The race's single source of truth for weather and surface condition (v35).
##
## ModeBase installs one right after loading the track. It owns:
##   wetness, frost, dust, precipitation (0..1), wind (direction + m/s),
##   dust colour
## and publishes them every frame as GLOBAL SHADER UNIFORMS (declared in
## project.godot [shader_globals]), so any shader can react with no plumbing:
##   global uniform float env_wetness;  env_frost;  env_dust;  env_precip;
##   global uniform vec4  env_wind;     // xy = unit direction (world X, Z), z = m/s
##   global uniform vec4  env_dust_color;
##
## It also drives the WEATHER part of the track's UtopiaSkyController (cloud
## cover, density, absorption, cloud shadow, cirrus, cloud wind, god rays and
## the fog densities); sun position, colours and exposure stay the track's.
##
## Ships read it through their ShipEnvProbe, which adds TrackFxZones (covered
## spans, dust stretches...) to get the LOCAL surface under each ship.
##
## Visual only: nothing here touches handling.

const GROUP := "environment_state"

const U_WETNESS := &"env_wetness"
const U_FROST := &"env_frost"
const U_DUST := &"env_dust"
const U_PRECIP := &"env_precip"
const U_WIND := &"env_wind"
const U_DUST_COLOR := &"env_dust_color"
const U_TRACK_MASK := &"env_track_mask"
const U_TRACK_LENGTH := &"env_track_length"
const U_LINE_GLOW := &"env_line_glow"
## Wet roads only sell with reflections: SSR on above this wetness (it is off
## in the authored lighting), where FxSettings allows it.
const SSR_WETNESS := 0.15

## Sky controller properties a weather may change. Everything else on the
## controller (sun azimuth/elevation/energy, colours, exposure) is time of day
## and stays as the track authored it.
const SKY_WEATHER_KEYS := ["coverage", "cloud_density", "cloud_absorption",
	"cloud_shadow_color", "cirrus_amount", "wind_speed", "god_ray_intensity"]
const SKY_FOG_KEYS := ["fog_density", "volumetric_density"]
## Phase 4: the sky's mood, blended toward the preset by WeatherPreset.sky_mood
## (colours and ambient), and the sun's energy for sun_scale.
const SKY_MOOD_KEYS := ["zenith_color", "horizon_color", "fog_color", "ambient_energy"]
const SKY_SUN_KEYS := ["sun_energy"]
## WorldEnvironment height fog (not driven by the sky controller).
const ENV_FOG_KEYS := ["fog_height_density", "fog_height", "fog_sky_affect"]

## Cycled by the debug overlay when the track lists no allowed_weather.
const DEBUG_PRESETS := [
	"res://resources/weather/clear.tres",
	"res://resources/weather/rain_light.tres",
	"res://resources/weather/rain_medium.tres",
	"res://resources/weather/rain_heavy.tres",
	"res://resources/weather/snow_light.tres",
	"res://resources/weather/snow_medium.tres",
	"res://resources/weather/snow_heavy.tres",
	"res://resources/weather/fog_light.tres",
	"res://resources/weather/fog_medium.tres",
	"res://resources/weather/fog_heavy.tres",
	"res://resources/weather/dust_storm_light.tres",
	"res://resources/weather/dust_storm_medium.tres",
	"res://resources/weather/dust_storm_heavy.tres",
]

const DEFAULT_DUST_COLOR := Color(0.62, 0.52, 0.38)

signal weather_changed(preset: WeatherPreset)

# --- Track context (set by install / discovered in _ready) -------------------
var track_root: Node
var track_environment: TrackEnvironment
var main_spline: Path3D
var spline_length: float = 0.0
## groundGeo's own transform on the four circuits (see SplineTracker.road_xf).
var road_xf := Transform3D.IDENTITY
## Average height of the road (height fog sits relative to it).
var road_mean_y: float = 0.0
## Every enabled zone: TrackEnvironment zones + sets, TrackFxZones nodes.
var zones: Array[TrackFxZone] = []
var sky: UtopiaSkyController
var world_env: WorldEnvironment
## Phase 4: what EnvSurfaces made weather-aware, and the zone mask it reads.
var surfaces: EnvSurfaces.Report
var track_mask: ImageTexture
var _ssr_authored: bool = false

# --- Current values (what the uniforms show) ---------------------------------
var weather: WeatherPreset
var wetness: float = 0.0
var frost: float = 0.0
var dust: float = 0.0
var precipitation: float = 0.0
var line_glow: float = 0.0
## Moisture in the air, 0..1 (not a shader global; read by ship FX).
var humidity: float = 0.3
## Unit direction the wind blows TOWARD, in world X/Z (sky controller convention).
var wind_direction := Vector2(0.0, -1.0)
## m/s near the road.
var wind_speed: float = 0.0
var dust_color := DEFAULT_DUST_COLOR

# --- Targets -------------------------------------------------------------------
var _t_wetness: float = 0.0
var _t_frost: float = 0.0
var _t_dust: float = 0.0
var _t_precip: float = 0.0
var _t_line_glow: float = 0.0
var _t_humidity: float = 0.3
var _t_wind_dir := Vector2(0.0, -1.0)
var _t_wind_speed: float = 0.0
var _change_time: float = 20.0

var _sky_base := {}          # the track's authored values of the sky keys
var _env_base := {}          # ...and of the WorldEnvironment fog keys
var _env_tween: Tween
var _sky_tween: Tween
var _published := {}         # uniform name -> last value sent
var _debug_index: int = -1


## Finds the race's EnvironmentState, or null (menus, training tools).
static func find(tree: SceneTree) -> EnvironmentState:
	if tree == null:
		return null
	return tree.get_first_node_in_group(GROUP) as EnvironmentState


## Adds an EnvironmentState under `parent` for a track that is already in the
## tree. `profile` may be null (clean track, clear weather).
static func install(parent: Node, p_track_root: Node, profile: TrackProfile) -> EnvironmentState:
	var e := EnvironmentState.new()
	e.name = "EnvironmentState"
	e.track_root = p_track_root
	e.track_environment = profile.environment if profile else null
	parent.add_child(e)
	return e


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	_discover()
	_snapshot_sky()
	_install_surfaces()
	var wfx := WeatherFx.new()
	wfx.name = "WeatherFx"
	wfx.env = self
	add_child(wfx)
	var start: WeatherPreset = track_environment.default_weather if track_environment else null
	apply_weather(start, true)
	if OS.is_debug_build():
		var overlay := EnvDebugOverlay.new()
		overlay.name = "EnvDebugOverlay"
		add_child(overlay)
	print("EnvironmentState: weather=%s dust=%.2f zones=%d spline=%.0f m sky=%s surfaces=%d mats (%d nodes, %d conflicts) mask=%s" % [
		weather.display_name, dust, zones.size(), spline_length,
		"yes" if sky else "no", surfaces.materials, surfaces.nodes, surfaces.conflicts,
		"yes" if track_mask else "no"])


func _exit_tree() -> void:
	if _sky_tween and _sky_tween.is_valid():
		_sky_tween.kill()
	if _env_tween and _env_tween.is_valid():
		_env_tween.kill()
	_restore_env_fog()
	# Globals outlive the scene: leave menus and the next track dry and clean.
	wetness = 0.0
	frost = 0.0
	dust = 0.0
	precipitation = 0.0
	line_glow = 0.0
	wind_speed = 0.0
	dust_color = DEFAULT_DUST_COLOR
	_publish(true)
	RenderingServer.global_shader_parameter_set(U_TRACK_LENGTH, 0.0)
	if world_env and world_env.environment:
		world_env.environment.ssr_enabled = _ssr_authored


func _process(delta: float) -> void:
	var step := delta / maxf(_change_time, 0.01)
	wetness = move_toward(wetness, _t_wetness, step)
	frost = move_toward(frost, _t_frost, step)
	dust = move_toward(dust, _t_dust, step)
	precipitation = move_toward(precipitation, _t_precip, step)
	line_glow = move_toward(line_glow, _t_line_glow, delta / maxf(weather.sky_transition_time if weather else 6.0, 0.01))
	humidity = move_toward(humidity, _t_humidity, step)
	var w := ShipController._smooth(1.0, delta)
	wind_direction = wind_direction.lerp(_t_wind_dir, w).normalized()
	wind_speed = lerpf(wind_speed, _t_wind_speed, w)
	_publish(false)
	_update_ssr()


# ============================================================================
# WEATHER
# ============================================================================

## Switches weather. `instant` snaps surface and sky (race start); otherwise
## the surface moves over preset.surface_change_time and the sky blends over
## preset.sky_transition_time. Null = clear.
func apply_weather(preset: WeatherPreset, instant := false) -> void:
	if preset == null:
		preset = WeatherPreset.new()   # defaults are clear weather
	weather = preset
	var base_dust: float = track_environment.dust if track_environment else 0.0
	_t_wetness = preset.wetness
	_t_frost = preset.frost
	_t_dust = clampf(base_dust + preset.dust_add, 0.0, 1.0)
	_t_precip = preset.precipitation
	_t_line_glow = preset.line_glow
	_t_humidity = preset.humidity
	_change_time = preset.surface_change_time
	_t_wind_dir = _wind_dir_for(preset)
	_t_wind_speed = preset.ground_wind
	_apply_sky(preset, instant)
	if instant:
		wetness = _t_wetness
		frost = _t_frost
		dust = _t_dust
		precipitation = _t_precip
		line_glow = _t_line_glow
		humidity = _t_humidity
		wind_direction = _t_wind_dir
		wind_speed = _t_wind_speed
		_publish(true)
	weather_changed.emit(preset)


## Debug: next / previous weather. Track's allowed_weather if it lists any,
## else the stock presets in DEBUG_PRESETS.
func cycle_weather(step := 1, instant := false) -> void:
	var list := weather_choices()
	if list.is_empty():
		return
	if _debug_index < 0:
		_debug_index = maxi(list.find(weather), 0)
	_debug_index = posmod(_debug_index + step, list.size())
	apply_weather(list[_debug_index], instant)


func weather_choices() -> Array[WeatherPreset]:
	var out: Array[WeatherPreset] = []
	if track_environment:
		if track_environment.default_weather:
			out.append(track_environment.default_weather)
		for p in track_environment.allowed_weather:
			if p and not out.has(p):
				out.append(p)
	if out.size() <= 1:
		for path in DEBUG_PRESETS:
			var p := load(path) as WeatherPreset
			if p and not out.has(p):
				out.append(p)
	return out


func _wind_dir_for(preset: WeatherPreset) -> Vector2:
	var deg := 40.0
	if preset.override_wind_direction:
		deg = preset.wind_direction_deg
	elif sky:
		deg = sky.wind_direction_deg
	var r := deg_to_rad(deg)
	# Same vector the sky shader gets (sky_controller.gd: wind_direction).
	return Vector2(sin(r), -cos(r))


# ============================================================================
# SKY
# ============================================================================

func _snapshot_sky() -> void:
	_sky_base.clear()
	_env_base.clear()
	if world_env and world_env.environment:
		for k in ENV_FOG_KEYS:
			_env_base[k] = world_env.environment.get(k)
	if sky == null:
		return
	for k in SKY_WEATHER_KEYS + SKY_FOG_KEYS + SKY_MOOD_KEYS + SKY_SUN_KEYS:
		_sky_base[k] = sky.get(k)


func _restore_env_fog() -> void:
	if world_env and world_env.environment:
		for k in _env_base:
			world_env.environment.set(k, _env_base[k])


func _apply_sky(preset: WeatherPreset, instant: bool) -> void:
	_apply_env_fog(preset, instant)
	if sky == null:
		return
	var target := _sky_base.duplicate()
	if preset.sky_preset != "":
		var src: Dictionary = UtopiaSkyController.PRESETS.get(preset.sky_preset, {})
		if src.is_empty():
			push_warning("EnvironmentState: unknown sky preset '%s'" % preset.sky_preset)
		for k in SKY_WEATHER_KEYS:
			if src.has(k):
				target[k] = src[k]
		if preset.sky_mood > 0.0:
			for k in SKY_MOOD_KEYS:
				if src.has(k) and target.has(k):
					if target[k] is Color:
						target[k] = (target[k] as Color).lerp(src[k], preset.sky_mood)
					else:
						target[k] = lerpf(float(target[k]), float(src[k]), preset.sky_mood)
	var tint := preset.fog_tint
	if preset.fog_tint_dust:
		tint = Color(dust_color.r, dust_color.g, dust_color.b, maxf(tint.a, 0.85))
	if tint.a > 0.0 and target.has("fog_color"):
		var fc := (target["fog_color"] as Color).lerp(Color(tint.r, tint.g, tint.b), tint.a)
		target["fog_color"] = fc
		if preset.fog_tint_dust and target.has("horizon_color"):
			target["horizon_color"] = (target["horizon_color"] as Color).lerp(fc, tint.a * 0.7)
	if target.has("sun_energy"):
		target["sun_energy"] = float(target["sun_energy"]) * preset.sun_scale
	if preset.sky_coverage >= 0.0:
		target["coverage"] = preset.sky_coverage
	if preset.fog_density >= 0.0:
		target["fog_density"] = preset.fog_density
	if preset.volumetric_density >= 0.0:
		target["volumetric_density"] = preset.volumetric_density

	if _sky_tween and _sky_tween.is_valid():
		_sky_tween.kill()
	if instant or preset.sky_transition_time <= 0.0:
		for k in target:
			sky.set(k, target[k])
		return
	_sky_tween = sky.create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	for k in target:
		_sky_tween.tween_property(sky, k, target[k], preset.sky_transition_time)


# ============================================================================
# ZONES / LOCAL SURFACE (used by ShipEnvProbe; precipitation and the surface
# shader will use the same formulas so everything agrees under a roof)
# ============================================================================

func make_spline_tracker() -> SplineTracker:
	return SplineTracker.new(main_spline, road_xf) if main_spline else null


func sample_zones(distance: float, out: TrackFxZones.Sample = null) -> TrackFxZones.Sample:
	return TrackFxZones.sample_zones(zones, distance, spline_length, out)


func local_wetness(z: TrackFxZones.Sample) -> float:
	var open := wetness * (1.0 - z.covered)
	return clampf(open * (1.0 + z.standing_water), 0.0, 1.0)


func local_frost(z: TrackFxZones.Sample) -> float:
	var open := frost * (1.0 - z.covered)
	return clampf(open * (1.0 + z.snow_drift), 0.0, 1.0)


## Dust lying on the road here. Whether a wet road still kicks it up is the
## dust FX's call, not this one's.
func local_dust(z: TrackFxZones.Sample) -> float:
	return clampf(dust * z.dust_scale, 0.0, 1.0)


func local_precipitation(z: TrackFxZones.Sample) -> float:
	return precipitation * (1.0 - z.covered)


# ============================================================================
# INTERNALS
# ============================================================================

func _discover() -> void:
	zones.clear()
	if track_environment:
		TrackFxZones.collect(track_environment.zones, track_environment.zone_sets, zones)
		dust_color = track_environment.dust_color
	var zone_node: TrackFxZones = null
	for n in get_tree().get_nodes_in_group(TrackFxZones.GROUP):
		if track_root and not track_root.is_ancestor_of(n):
			continue
		var tz := n as TrackFxZones
		TrackFxZones.collect(tz.zones, tz.zone_sets, zones)
		if zone_node == null:
			zone_node = tz
	if zone_node:
		main_spline = zone_node.get_spline()
	if main_spline == null and track_root:
		main_spline = track_root.find_child("MainSpline", true, false) as Path3D
	if main_spline and main_spline.curve:
		spline_length = main_spline.curve.get_baked_length()
		# Same rule as UtopiaKit: the extruded road under MainSpline carries its
		# own node transform on the circuits; identity everywhere else.
		var gg := main_spline.get_node_or_null("groundGeo") as Node3D
		if gg:
			road_xf = gg.transform
		var pts := main_spline.curve.get_baked_points()
		var sum := 0.0
		for q in pts:
			sum += (road_xf * (main_spline.global_transform * q)).y
		road_mean_y = sum / maxf(pts.size(), 1)
	if track_root:
		sky = _find_sky(track_root)
		world_env = _find_world_env(track_root)
	if world_env and world_env.environment:
		_ssr_authored = world_env.environment.ssr_enabled


## Road and walls react to the weather; covered spans etc. come from the
## per-distance zone mask (only where the road's UVs map to MainSpline).
func _install_surfaces() -> void:
	surfaces = EnvSurfaces.adopt(track_root, main_spline)
	var length := 0.0
	if surfaces.road_u_scale > 0.0 and spline_length > 0.0:
		track_mask = EnvSurfaces.build_mask(zones, spline_length)
		RenderingServer.global_shader_parameter_set(U_TRACK_MASK, track_mask)
		length = spline_length
	RenderingServer.global_shader_parameter_set(U_TRACK_LENGTH, length)


func _update_ssr() -> void:
	if world_env == null or world_env.environment == null:
		return
	var want := _ssr_authored or (wetness > SSR_WETNESS and bool(FxSettings.active().pick(false, true, true)))
	var e := world_env.environment
	if e.ssr_enabled != want:
		e.ssr_enabled = want
		if want and not _ssr_authored:
			e.ssr_max_steps = int(FxSettings.active().pick(32, 48, 64))
			e.ssr_fade_in = 0.15
			e.ssr_fade_out = 2.0
			e.ssr_depth_tolerance = 0.3


static func _find_world_env(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node
	for c in node.get_children():
		var w := _find_world_env(c)
		if w:
			return w
	return null


static func _find_sky(node: Node) -> UtopiaSkyController:
	if node is UtopiaSkyController:
		return node
	for c in node.get_children():
		var s := _find_sky(c)
		if s:
			return s
	return null


func _apply_env_fog(preset: WeatherPreset, instant: bool) -> void:
	if world_env == null or world_env.environment == null or _env_base.is_empty():
		return
	var e := world_env.environment
	var target := _env_base.duplicate()
	if preset.height_fog_density >= 0.0:
		target["fog_height_density"] = preset.height_fog_density
		target["fog_height"] = road_mean_y + preset.height_fog_top
	if preset.fog_sky_affect >= 0.0:
		target["fog_sky_affect"] = preset.fog_sky_affect
	if _env_tween and _env_tween.is_valid():
		_env_tween.kill()
	if instant or preset.sky_transition_time <= 0.0:
		for k in target:
			e.set(k, target[k])
		return
	_env_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	for k in target:
		_env_tween.tween_property(e, k, target[k], preset.sky_transition_time)


func _publish(force: bool) -> void:
	_set_global(U_LINE_GLOW, line_glow, force)
	_set_global(U_WETNESS, wetness, force)
	_set_global(U_FROST, frost, force)
	_set_global(U_DUST, dust, force)
	_set_global(U_PRECIP, precipitation, force)
	_set_global(U_WIND, Vector4(wind_direction.x, wind_direction.y, wind_speed, 0.0), force)
	_set_global(U_DUST_COLOR, dust_color, force)


func _set_global(uniform: StringName, value: Variant, force: bool) -> void:
	if not force and _published.has(uniform):
		var old: Variant = _published[uniform]
		if typeof(value) == TYPE_FLOAT:
			if absf(float(old) - float(value)) < 0.0005:
				return
		elif old == value:
			return
	_published[uniform] = value
	RenderingServer.global_shader_parameter_set(uniform, value)
