@tool
extends Resource
class_name FxParticlePreset
## One look of ship-kicked particles (v35 Phase 2): dust, spray or snow powder.
## FxPools builds one GPUParticles3D per preset per race from this; ships feed
## it with emit_particle(), so the whole grid costs one draw call per look.

@export var display_name: String = "Dust"

@export_group("Budget")
## Max live particles per quality tier (LOW, MEDIUM, HIGH).
@export var amount_low: int = 1800
@export var amount_medium: int = 3500
@export var amount_high: int = 6000

@export_group("Motion")
@export var lifetime: float = 1.2
## Downward pull, m/s^2 (negative = rises).
@export var gravity: float = 0.6
## How much the race wind (EnvironmentState) pushes the particles, m/s^2 per m/s.
@export var wind_influence: float = 0.35
## Drag on the inherited velocity, m/s per second.
@export var damping: float = 9.0
@export var turbulence_strength: float = 1.2
@export var turbulence_scale: float = 6.0
@export var spin: float = 40.0                  # degrees per second, random sign

@export_group("Size")
@export var scale_min: float = 1.0
@export var scale_max: float = 2.2
## Size at the end of life, relative to the start.
@export var grow: float = 2.6

@export_group("Look")
@export var color := Color(0.62, 0.52, 0.38)
## Use the track's dust colour (TrackEnvironment.dust_color) instead of `color`.
@export var use_track_dust_color: bool = true
@export_range(0.0, 1.0) var opacity: float = 0.55
## Fraction of life spent fading in.
@export_range(0.0, 0.5) var fade_in: float = 0.1
@export_range(0.05, 1.0) var softness: float = 0.85
@export_range(0.0, 1.0) var erosion: float = 0.7
@export var emission_boost: float = 0.0
