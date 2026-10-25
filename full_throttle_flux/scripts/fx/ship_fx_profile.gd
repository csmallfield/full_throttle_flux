@tool
extends Resource
class_name ShipFxProfile
## Look of one ship model's FX (v35): trail colours, sizes, and fallback socket
## positions for models that have no FX_* markers yet.
##
## A visual variant points at its profile with metadata `fx_profile` on its
## root node; without one ShipFx uses resources/fx/default_ship_fx.tres.
## Kept off ShipProfile on purpose: ShipProfile.handling_hash() fingerprints
## every number on it, and looks must never orphan trained lines.
##
## Sockets (Marker3D under the model, -Z = forward, +Y = up):
##   FX_Thrust_*      one per nozzle (any suffix; sorted by name)
##   FX_Wingtip_L/R   air streams
##   FX_Airbrake_L/R  airbrake dust (Phase 2)
##   FX_Belly         ground dust origin (Phase 2)

@export_group("Thrust trail")
@export var thrust_color := Color(0.35, 0.75, 1.0)
## Brightness when coasting / idling (0..1); full throttle is 1.
@export_range(0.0, 1.0) var thrust_idle: float = 0.3
@export var thrust_width_head: float = 0.4
@export var thrust_width_tail: float = 0.04
@export var thrust_lifetime: float = 0.3
@export var thrust_max_length: float = 14.0
@export var thrust_spacing: float = 1.5
## While boost overspeed is active: trail length, brightness and width.
@export var boost_length_mult: float = 1.6
@export var boost_intensity_mult: float = 1.8
@export var boost_width_mult: float = 1.3
## Tint lerps toward this with boost.
@export var boost_color := Color(0.75, 0.9, 1.0)

@export_group("Air streams")
@export var air_color := Color(0.92, 0.96, 1.0)
## Opacity at full load in humid air.
@export_range(0.0, 1.0) var air_opacity: float = 0.65
@export var air_width_head: float = 0.08
@export var air_width_tail: float = 0.5
@export var air_lifetime: float = 1.1
@export var air_max_length: float = 70.0
@export var air_spacing: float = 2.5
## Speed ratio (speed / max_speed) where streams start to show, and full.
@export_range(0.0, 1.5) var air_speed_start: float = 0.45
@export_range(0.0, 1.5) var air_speed_full: float = 0.9
## Load (|yaw rate| * speed, u*rad/s^2-ish) that counts as full; a hard
## airbrake on that side adds on top.
@export var air_load_full: float = 90.0
## Visible fraction at zero load (straight-line flight) and in dry air.
@export_range(0.0, 1.0) var air_base_load: float = 0.4
@export_range(0.0, 1.0) var air_dry_visibility: float = 0.35

@export_group("Dust, spray, powder (Phase 2)")
## Carriers per second at full strength, per emitter. Each carrier lays
## puff_rate x carrier_lifetime puffs (about 30 for dust), see FxParticlePreset.
@export var dust_ground_rate: float = 280.0
@export var dust_wall_rate: float = 180.0
@export var dust_airbrake_rate: float = 220.0
## Speed (u/s) where ground particles start, and where they are full.
@export var dust_speed_start: float = 15.0
@export var dust_speed_full: float = 100.0
## Ground term: full at hover height and below, 0 at this many hover heights.
@export var dust_ground_reach: float = 3.0
## Extra when the hull dips below hover height (landings, compressions).
@export var dust_ground_low_bonus: float = 0.3
## A wall closer than this (m) kicks up wall dust.
@export var dust_wall_range: float = 4.0
## Fraction of ship velocity the carriers start with. High = carriers ride
## along under the ship and lay their puffs right behind it, where a chase
## camera (13 m back, i.e. ~0.1 s at race speed) can see them.
@export_range(0.0, 1.0) var dust_inherit: float = 0.92
## Upward kick, m/s (random 0.5x .. 1x).
@export var dust_rise: float = 2.5
## Sideways spread, m/s.
@export var dust_spread: float = 7.0
## Surface wetter than this sprays instead of dusting; frostier than
## frost_switch throws snow powder instead.
@export_range(0.0, 1.0) var dust_wet_switch: float = 0.3
@export_range(0.0, 1.0) var dust_frost_switch: float = 0.35
## Spray and powder strength relative to dust at the same surface value.
@export var spray_strength: float = 1.2
@export var powder_strength: float = 1.0

@export_group("Wall hits (Phase 3)")
## Closing speed into the wall (u/s) that counts as a full-force hit.
@export var hit_full_closing: float = 40.0
## Sparks per hit, from a glancing touch to a full-force hit.
@export var hit_sparks_min: float = 10.0
@export var hit_sparks_max: float = 80.0
## Fraction of ship velocity sparks keep (hit / scrape): high = they trail
## behind the ship instead of stopping dead at the wall.
@export_range(0.0, 1.0) var hit_spark_inherit: float = 0.5
@export_range(0.0, 1.0) var scrape_spark_inherit: float = 0.8
## Spark kick off the wall and random scatter, m/s.
@export var hit_spark_kick: float = 8.0
@export var hit_spark_scatter: float = 5.0
## Spark stream while scraping: sparks per second per u/s of speed.
@export var scrape_sparks_per_speed: float = 4.0
## Sparks lost on a soaked surface (0 = none, 1 = all).
@export_range(0.0, 1.0) var spark_wet_quench: float = 0.6
## Flash on hits at least this hard (0..1), and its light energy at full force.
@export_range(0.0, 1.0) var flash_min_heat: float = 0.25
@export var flash_energy: float = 6.0
## Dust / spray / powder carriers per hit (at full surface), and per second
## while scraping.
@export var hit_dust_carriers: float = 25.0
@export var scrape_dust_rate: float = 60.0
## Scrape marks: shortest mark (m), and seconds of travel between marks while
## scraping (so spacing grows with speed and the decal ring lasts).
@export var mark_min_length: float = 1.4
@export var mark_spacing_time: float = 0.07

@export_group("Fallback sockets (ship space, metres)")
@export var fallback_thrust: PackedVector3Array = PackedVector3Array([Vector3(-0.45, -0.3, 3.7), Vector3(0.45, -0.3, 3.7)])
@export var fallback_wingtip_l := Vector3(-1.9, -0.78, 2.1)
@export var fallback_wingtip_r := Vector3(1.9, -0.78, 2.1)
@export var fallback_airbrake_l := Vector3(-1.4, -0.6, 3.0)
@export var fallback_airbrake_r := Vector3(1.4, -0.6, 3.0)
@export var fallback_belly := Vector3(0.0, -1.2, 0.0)
