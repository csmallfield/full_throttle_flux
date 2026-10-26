@tool
extends Resource
class_name FxParticlePreset
## One look of ship-kicked particles (v35 Phase 2): dust, spray or snow powder.
##
## Two GPU particle systems per look, per race (FxPools):
##   CARRIERS  invisible, emitted by ships from script (emit_particle) with the
##             ship's wake velocity; they decelerate hard and, while alive,
##   PUFFS     spawn small textured puffs on the GPU (sub-emitter), so one
##             script call becomes `puff_rate * carrier_lifetime` puffs.
## Tens of thousands of small particles for the cost of a few hundred script
## calls a second.

@export var display_name: String = "Dust"

@export_group("Carriers")
## Max live carriers per quality tier.
@export var carrier_amount: int = 3000
## Seconds a carrier lives (and spawns puffs).
@export var carrier_lifetime: float = 0.45
## Deceleration, m/s per second: high = the plume stops close behind the ship.
@export var carrier_damping: float = 25.0
## Puffs each carrier spawns per second. At most FxPools.CARRIER_HZ (60): a
## carrier lays one puff per simulation step. Want more? Emit more carriers.
@export var puff_rate: float = 60.0
## Puffs start with their carrier's velocity (spray flung off the road) or
## nearly still where they are laid (dust hanging in the air behind the ship).
@export var puffs_keep_velocity: bool = false

@export_group("Puff budget")
## Max live puffs per quality tier (LOW, MEDIUM, HIGH).
@export var amount_low: int = 12000
@export var amount_medium: int = 25000
@export var amount_high: int = 50000

@export_group("Puff motion")
@export var lifetime: float = 1.6
@export_range(0.0, 1.0) var lifetime_randomness: float = 0.4
## Downward pull, m/s^2 (negative = rises).
@export var gravity: float = -0.15
## How much the race wind (EnvironmentState) pushes the puffs, m/s^2 per m/s.
@export var wind_influence: float = 0.35
## Drag, m/s per second.
@export var damping: float = 5.0
## Random burst speed of a new puff around its carrier, m/s.
@export var burst_min: float = 0.3
@export var burst_max: float = 4.0
@export var turbulence_strength: float = 1.5
@export var turbulence_scale: float = 4.0
@export var spin: float = 45.0                  # degrees per second, random sign

@export_group("Puff size")
## Quad size at birth, metres (the drawn puff fills roughly 60 % of it).
@export var scale_min: float = 0.8
@export var scale_max: float = 1.6
## Size at the end of life, relative to birth (most growth early).
@export var grow: float = 4.5

@export_group("Look")
@export var color := Color(0.62, 0.52, 0.38)
## Use the track's dust colour (TrackEnvironment.dust_color) instead of `color`.
@export var use_track_dust_color: bool = true
## Per-puff brightness spread: each puff is lit between this and 1.
@export_range(0.0, 1.0) var brightness_min: float = 0.78
@export_range(0.0, 2.0) var opacity: float = 0.2
## Fraction of life spent fading in.
@export_range(0.0, 0.5) var fade_in: float = 0.0
@export_range(0.0, 1.0) var erosion: float = 0.6
@export_range(0.0, 1.0) var core_darken: float = 0.15
## How strongly the baked normals shade the puff (1 = full relief).
@export_range(0.0, 2.0) var normal_strength: float = 0.6
@export_range(0.0, 2.0) var backlight: float = 0.5
@export var emission_boost: float = 0.0
