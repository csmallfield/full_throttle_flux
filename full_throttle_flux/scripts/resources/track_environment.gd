@tool
extends Resource
class_name TrackEnvironment
## What a track is like, environment-wise (v35). Set on TrackProfile.environment.
## No environment = a clean track in clear weather, exactly as before.

## How dusty the road is in dry weather. 0 = clean, ~0.5 = dusty, ~0.85 = sandy.
@export_range(0.0, 1.0) var dust: float = 0.0

## Colour of dust trails, dust puffs and the dusty road look.
@export var dust_color: Color = Color(0.62, 0.52, 0.38)

@export_group("Weather")

## Weather a race starts in. Null = clear.
@export var default_weather: WeatherPreset

## Weathers this track supports (menu / random pick, debug cycling).
## Empty = default_weather only.
@export var allowed_weather: Array[WeatherPreset] = []

@export_group("FX zones")

## Hand-authored zones (metres along MainSpline).
@export var zones: Array[TrackFxZone] = []

## Generated sets, e.g. covered spans from tools/env/survey_cover.gd.
@export var zone_sets: Array[TrackFxZoneSet] = []
