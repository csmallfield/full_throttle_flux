@tool
extends Node
class_name TrackFxZones
## Optional scene node for a track's environment FX zones (v35).
##
## Most tracks need none of this: zones can live in the track's
## TrackEnvironment resource instead (no scene edit). Use the node when the
## zones belong with the scene, e.g. Track Builder tracks (an FxKey will write
## here later). EnvironmentState merges both sources.

const GROUP := "track_fx_zones"

@export var spline_path: NodePath = NodePath("../MainSpline")

## Hand-authored zones.
@export var zones: Array[TrackFxZone] = []

## Generated sets (survey_cover.gd and friends).
@export var zone_sets: Array[TrackFxZoneSet] = []


func _enter_tree() -> void:
	add_to_group(GROUP)


func get_spline() -> Path3D:
	return get_node_or_null(spline_path) as Path3D


## Every enabled zone from both lists, flattened.
func all_zones() -> Array[TrackFxZone]:
	var out: Array[TrackFxZone] = []
	collect(zones, zone_sets, out)
	return out


static func collect(list: Array[TrackFxZone], sets: Array[TrackFxZoneSet],
		out: Array[TrackFxZone]) -> void:
	for z in list:
		if z and z.enabled:
			out.append(z)
	for s in sets:
		if s == null:
			continue
		for z in s.zones:
			if z and z.enabled:
				out.append(z)


## Combined zone values at `distance` (metres along a spline `length` long).
## Overlaps: dust_scale multiplies (each blended toward 1 by its weight), the
## others take the strongest weighted value. Pass `out` to avoid allocating.
static func sample_zones(zone_list: Array[TrackFxZone], distance: float, length: float,
		out: Sample = null) -> Sample:
	if out == null:
		out = Sample.new()
	out.reset()
	if distance < 0.0 or length <= 0.0:
		return out
	for z in zone_list:
		var w := z.weight_at(distance, length)
		if w <= 0.0:
			continue
		out.weight = maxf(out.weight, w)
		out.dust_scale *= lerpf(1.0, z.dust_scale, w)
		out.covered = maxf(out.covered, z.covered * w)
		out.standing_water = maxf(out.standing_water, z.standing_water * w)
		out.snow_drift = maxf(out.snow_drift, z.snow_drift * w)
	return out


## Zone values at one point of the track. Neutral = no zone.
class Sample extends RefCounted:
	## Strongest zone weight here (0 = outside every zone).
	var weight: float = 0.0
	var dust_scale: float = 1.0
	var covered: float = 0.0
	var standing_water: float = 0.0
	var snow_drift: float = 0.0

	func reset() -> void:
		weight = 0.0
		dust_scale = 1.0
		covered = 0.0
		standing_water = 0.0
		snow_drift = 0.0
