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
@export_range(-1.0, 0.002, 0.00001) var fog_density: float = -1.0

## Overrides the sky controller's volumetric fog density (-1 = keep).
@export_range(-1.0, 0.1, 0.0005) var volumetric_density: float = -1.0

## Blend time for a mid-race sky change.
@export_range(0.0, 60.0) var sky_transition_time: float = 6.0
