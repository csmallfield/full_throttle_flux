@tool
extends Resource
class_name TrackFxZone
## One stretch of track that changes the environment FX locally (v35).
##
## Same extent model as MagneticZone: metres along the track's MainSpline,
## smooth ramps either side, end < start wraps across the lap seam. Lives in a
## TrackEnvironment (zones / zone_sets) or a TrackFxZones node in the scene.
##
## Overlapping zones combine: dust_scale multiplies, the others take the
## strongest value.

@export var zone_name: String = "Zone"

## Can be switched off without deleting the zone.
@export var enabled: bool = true

@export_group("Extent (metres along MainSpline)")

## Full strength from here...
@export var start_distance: float = 0.0

## ...to here. If end < start the zone wraps across the lap seam.
@export var end_distance: float = 100.0

## Blend-in length before start_distance.
@export var ramp_in: float = 15.0

## Blend-out length after end_distance.
@export var ramp_out: float = 15.0

@export_group("Effects")

## Multiplies ship dust here. 1 = no change, 0 = none, 3 = a dust bowl.
@export_range(0.0, 4.0) var dust_scale: float = 1.0

## 1 = roof or tunnel: no rain or snow reaches the road, the surface stays dry
## and unfrozen, precipitation cuts out for a camera in here.
@export_range(0.0, 1.0) var covered: float = 0.0

## Puddles on top of the global wetness (only shows while the road is wet).
@export_range(0.0, 1.0) var standing_water: float = 0.0

## Drifts on top of the global frost (only shows while it is cold).
@export_range(0.0, 1.0) var snow_drift: float = 0.0


## Blend weight 0..1 at `distance` along a spline of `length` metres.
func weight_at(distance: float, length: float) -> float:
	if not enabled:
		return 0.0
	return SplineSpan.weight(distance, length, start_distance, end_distance, ramp_in, ramp_out)
