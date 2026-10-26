@tool
extends Resource
class_name WeatherPreset
## One weather at one intensity (v35). EnvironmentState applies it: surface
## targets go to the global shader uniforms, sky values to the track's
## UtopiaSkyController. Light / Medium / Heavy are just separate presets.
##
## Visual only: nothing here touches handling, so trained AI lines and
## recordings stay valid in every weather.

enum Kind { CLEAR, RAIN, SNOW, FOG, DUST_STORM }

@export var display_name: String = "Clear"
@export var kind: Kind = Kind.CLEAR

## 0..1 within its kind; FX scale their density with it.
@export_range(0.0, 1.0) var intensity: float = 0.0

@export_group("Surface targets")

## Road wetness the weather drives toward (0 dry ... 1 soaked).
@export_range(0.0, 1.0) var wetness: float = 0.0

## Frost / snow cover (0 none ... 1 white over).
@export_range(0.0, 1.0) var frost: float = 0.0

## Added to the track's own dust (TrackEnvironment.dust).
@export_range(0.0, 1.0) var dust_add: float = 0.0

## Moisture in the air, 0..1. Wingtip air streams show clearly in humid air
## and stay faint in dry air (v35 Phase 1).
@export_range(0.0, 1.0) var humidity: float = 0.3

## Falling rain / snow / grit density, 0..1.
@export_range(0.0, 1.0) var precipitation: float = 0.0

## Seconds for the surface to reach these targets after a MID-RACE change.
## The weather a race starts in is applied instantly.
@export_range(0.0, 300.0) var surface_change_time: float = 20.0

@export_group("Wind")

## Use wind_direction_deg instead of the track sky's own cloud wind direction.
@export var override_wind_direction: bool = false

## Same convention as UtopiaSkyController.wind_direction_deg.
@export_range(0.0, 360.0) var wind_direction_deg: float = 40.0

## Wind near the road, m/s. Drives rain slant and dust drift (not the clouds).
@export_range(0.0, 40.0) var ground_wind: float = 3.0

@export_group("Sky (empty / negative = keep the track's own)")

## A UtopiaSkyController preset to take the WEATHER part from (cloud cover,
## density, absorption, cloud shadow, cirrus, cloud wind, god rays). Sun
## position, colours and exposure always stay the track's own.
@export var sky_preset: String = ""

## Overrides the preset's cloud coverage (-1 = keep).
@export_range(-1.0, 1.0) var sky_coverage: float = -1.0

## Overrides the sky controller's distance fog density (-1 = keep).
@export_range(-1.0, 0.03, 0.00001) var fog_density: float = -1.0

## Overrides the sky controller's volumetric fog density (-1 = keep).
@export_range(-1.0, 0.1, 0.0005) var volumetric_density: float = -1.0

## How much of the sky preset's MOOD to take over the track's own: zenith,
## horizon and fog colour, ambient light (0 = keep the track's colours).
@export_range(0.0, 1.0) var sky_mood: float = 0.0

## Fog colour pushed toward this; alpha = how far (after sky_mood).
@export var fog_tint := Color(0.5, 0.5, 0.5, 0.0)

## Tint the fog with the track's dust colour instead (dust storms).
@export var fog_tint_dust: bool = false

## Sun light multiplier on top of the cloud-cover dimming (1 = unchanged).
@export_range(0.0, 1.0) var sun_scale: float = 1.0

## Height fog density near the road (-1 = keep the lighting scene's).
@export_range(-1.0, 0.2, 0.001) var height_fog_density: float = -1.0

## Top of the height fog, metres above the track's average road height
## (only used when height_fog_density is set).
@export_range(-50.0, 200.0) var height_fog_top: float = 15.0

## How much the distance fog covers the sky (-1 = keep the lighting scene's).
## Dense fog and storms want it high or the sky stays crisp behind a wall of fog.
@export_range(-1.0, 1.0) var fog_sky_affect: float = -1.0

## Grid lines on road and walls glow this much (0..1): keeps the line
## readable in fog, storms and heavy rain.
@export_range(0.0, 1.0) var line_glow: float = 0.0

## Blend time for a mid-race sky change.
@export_range(0.0, 60.0) var sky_transition_time: float = 6.0
