@tool
extends Resource
class_name MagneticZone

## One stretch of track where ships are held to the surface (v30).
##
## A zone is a distance range along the track's MainSpline, in metres from the
## spline start. Ramps blend the zone in and out so nothing switches on in a
## single frame. Owned by a MagneticTrack node in the track scene.
##
## The two knobs that set how the zone plays:
##   magnet_strength      1 = gravity always pulls into the track and the hover
##                            spring keeps its pull, so a ship can crawl round a
##                            loop upside down (forgiving).
##                        0 = real world gravity, including the part that pulls
##                            a ship OFF a ceiling, and the hover spring can only
##                            push. Make it over the top by carrying enough speed
##                            (skill check). Values in between blend the two.
##   slope_gravity_scale  how much speed the ship loses climbing (and gains
##                        falling). 1 = the ship profile's normal slope gravity,
##                        0 = none.

@export var zone_name: String = "Zone"

## Can be switched off without deleting the zone.
@export var enabled: bool = true

@export_group("Extent (metres along MainSpline)")

## Full strength from here...
@export var start_distance: float = 0.0

## ...to here. If end < start the zone wraps across the lap seam.
@export var end_distance: float = 100.0

## Blend-in length before start_distance.
@export var ramp_in: float = 40.0

## Blend-out length after end_distance.
@export var ramp_out: float = 40.0

@export_group("Behaviour")

@export_range(0.0, 1.0) var magnet_strength: float = 1.0

@export_range(0.0, 2.0) var slope_gravity_scale: float = 1.0

## Multiplies the profile's hover_force_max. A tight loop at full speed asks
## the hover spring for more than flat track does; without headroom the hull
## bottoms out on the road.
@export_range(1.0, 4.0) var hover_force_scale: float = 2.0

## Track-normal smoothing rate used inside the zone (per second). The road
## normal turns hundreds of degrees per second here, so the profile's flat-track
## rate (about 9) lags it visibly.
@export var normal_smoothing: float = 30.0

## If the hover ray misses (CSG seams, very tight curvature) use the spline's
## own surface frame as the ground instead of dropping to airborne physics.
@export var contact_recovery: bool = true

## Recovery only applies within this many hover heights of the surface.
@export var recovery_range: float = 4.0

## ...and within this lateral distance of the spline centre line (metres).
@export var recovery_half_width: float = 24.0


## Blend weight 0..1 at `distance` along a spline of `length` metres.
## v35: the span maths moved to SplineSpan (shared with TrackFxZone); same
## numbers, bit for bit.
func weight_at(distance: float, length: float) -> float:
	if not enabled:
		return 0.0
	return SplineSpan.weight(distance, length, start_distance, end_distance, ramp_in, ramp_out)


static func _wrap(d: float, length: float) -> float:
	return SplineSpan.wrap_distance(d, length)


static func _smooth01(t: float) -> float:
	return SplineSpan.smooth01(t)
