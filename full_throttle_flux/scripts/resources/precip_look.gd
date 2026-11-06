@tool
extends Resource
class_name PrecipLook
## How one kind of falling weather looks: rain, snow or dust-storm grit. Shared
## by every weather of that kind and every track; the weather preset's
## `precipitation` sets how much of it falls. WeatherFx reads it.
##
## One file per kind in res://resources/weather/precip (precip_rain.tres,
## precip_snow.tres, precip_dust_storm.tres). A missing file falls back to
## builtin(), which is the look WeatherFx had before these files existed (v35).

const DIR := "res://resources/weather/precip"

@export_group("Fall")
## Metres per second straight down.
@export_range(0.0, 40.0, 0.1, "suffix:m/s") var fall_speed: float = 11.0
## How much of the ground wind it's carried by (1 = moves with the wind).
@export_range(0.0, 2.0, 0.05) var wind_carry: float = 0.6
## Each particle's fall speed varies by up to this fraction.
@export_range(0.0, 1.0, 0.01) var fall_spread: float = 0.15
## Metres of side-to-side drift, for flakes.
@export_range(0.0, 3.0, 0.05, "suffix:m") var sway: float = 0.0
## Share of the particles shown at full precipitation. Snow reads denser than
## rain at the same rate, so it's thinned.
@export_range(0.0, 1.0, 0.01) var density_scale: float = 1.0

@export_group("Near streaks")
## Streak width.
@export_range(0.002, 0.2, 0.001, "suffix:m") var width: float = 0.012
## Shortest streak, however slowly it moves past the camera.
@export_range(0.0, 2.0, 0.005, "suffix:m") var min_length: float = 0.25
## Longest streak, however fast it moves.
@export_range(0.0, 8.0, 0.05, "suffix:m") var max_length: float = 3.5
## Seconds of motion one streak shows: the camera's "shutter".
@export_range(0.0, 0.1, 0.001, "suffix:s") var shutter: float = 0.025
## 0 = a streak with soft sides, 1 = a soft dot.
@export_range(0.0, 1.0, 0.01) var roundness: float = 0.0
@export_range(0.0, 1.0, 0.01) var opacity: float = 0.32
## Fades out this close to the camera, so nothing smears across the lens.
@export_range(0.0, 5.0, 0.05, "suffix:m") var near_fade: float = 0.6

@export_group("Far layer")
## Pattern cells per metre on the cylinder round the camera (around, up).
@export var far_cells := Vector2(1.4, 0.06)
## Metres per second the pattern moves (around, down).
@export var far_scroll := Vector2(0.0, 11.0)
## Higher = sparser.
@export_range(0.0, 1.0, 0.01) var far_threshold: float = 0.62
@export_range(0.0, 1.0, 0.01) var far_sharpness: float = 0.08
@export_range(0.0, 1.0, 0.01) var far_opacity: float = 0.08

@export_group("Colour")
## The track's fog colour, pushed toward this by tint_mix.
@export var tint_target := Color(0.85, 0.88, 0.92)
@export_range(0.0, 1.0, 0.01) var tint_mix: float = 0.3
## Use the track's dust colour as the target instead (dust storms).
@export var tint_from_dust: bool = false

static var _cache := {}


## The kind's file name stem, or "" for kinds where nothing falls.
static func stem(kind: int) -> String:
	match kind:
		WeatherPreset.Kind.RAIN:
			return "rain"
		WeatherPreset.Kind.SNOW:
			return "snow"
		WeatherPreset.Kind.DUST_STORM:
			return "dust_storm"
	return ""


static func path_for(kind: int) -> String:
	var s := stem(kind)
	return "" if s == "" else "%s/precip_%s.tres" % [DIR, s]


## The look for `kind`: its file if there is one, else builtin(). Null for
## clear and fog.
static func for_kind(kind: int) -> PrecipLook:
	var path := path_for(kind)
	if path == "":
		return null
	if ResourceLoader.exists(path):
		return load(path) as PrecipLook
	if not _cache.has(kind):
		_cache[kind] = builtin(kind)
	return _cache[kind]


## The look before it was data (WeatherFx v35), so a missing file changes nothing.
static func builtin(kind: int) -> PrecipLook:
	var l := PrecipLook.new()
	match kind:
		WeatherPreset.Kind.SNOW:
			l.fall_speed = 1.4
			l.wind_carry = 0.8
			l.fall_spread = 0.35
			l.sway = 0.6
			l.density_scale = 0.55
			l.width = 0.035
			l.min_length = 0.035
			l.max_length = 0.6
			l.shutter = 0.01
			l.roundness = 1.0
			l.opacity = 0.6
			l.near_fade = 1.5
			l.far_cells = Vector2(0.9, 0.5)
			l.far_scroll = Vector2(0.3, 1.4)
			l.far_threshold = 0.72
			l.far_sharpness = 0.08
			l.far_opacity = 0.22
			l.tint_target = Color(0.95, 0.96, 1.0)
			l.tint_mix = 0.6
		WeatherPreset.Kind.DUST_STORM:
			l.fall_speed = 0.4
			l.wind_carry = 1.1
			l.fall_spread = 0.3
			l.sway = 0.3
			l.width = 0.02
			l.min_length = 0.05
			l.max_length = 1.2
			l.shutter = 0.02
			l.roundness = 0.4
			l.opacity = 0.45
			l.near_fade = 1.0
			l.far_cells = Vector2(0.05, 0.12)
			l.far_scroll = Vector2(14.0, 0.0)
			l.far_threshold = 0.45
			l.far_sharpness = 0.4
			l.far_opacity = 0.4
			l.tint_mix = 0.7
			l.tint_from_dust = true
	return l


## Sets the particle and draw materials (once per kind change, or after an edit).
func configure(process_mat: ShaderMaterial, draw_mat: ShaderMaterial, far_mat: ShaderMaterial) -> void:
	process_mat.set_shader_parameter("fall_spread", fall_spread)
	process_mat.set_shader_parameter("sway", sway)
	draw_mat.set_shader_parameter("width", width)
	draw_mat.set_shader_parameter("min_length", min_length)
	draw_mat.set_shader_parameter("max_length", max_length)
	draw_mat.set_shader_parameter("shutter", shutter)
	draw_mat.set_shader_parameter("roundness", roundness)
	draw_mat.set_shader_parameter("opacity", opacity)
	draw_mat.set_shader_parameter("near_fade", near_fade)
	far_mat.set_shader_parameter("cells", far_cells)
	far_mat.set_shader_parameter("scroll", far_scroll)
	far_mat.set_shader_parameter("threshold", far_threshold)
	far_mat.set_shader_parameter("sharpness", far_sharpness)


## World velocity of a falling particle in this wind.
func fall(wind: Vector3) -> Vector3:
	return wind * wind_carry + Vector3(0.0, -fall_speed, 0.0)


## The colour, from the track's fog colour and dust colour.
func tint(fog: Color, dust: Color) -> Color:
	return fog.lerp(dust if tint_from_dust else tint_target, tint_mix)
