@tool
extends Resource
class_name BakedRacingLine

## Baked Racing Line
## Precomputed racing line + speed profile for one (track, ship profile) pair.
## Produced by AIRacingLineBaker, consumed by AILineFollower.
##
## Sample i corresponds to spline offset i / sample_count. Samples are uniform
## in spline offset and wrap around (closed track). All lateral offsets are in
## meters from the track centerline (positive = right, matching
## TrackSplineHelper.calculate_lateral_offset). All speeds are in
## velocity units per second and are DISTANCE-AWARE: the two-pass profile
## already encodes where braking must begin, so "speed at my current offset"
## is a complete instruction -- no separate corner-distance logic needed.

const CURRENT_BAKE_VERSION := 4

@export var bake_version: int = CURRENT_BAKE_VERSION

## Hash of the inputs (spline points, profile params, baker config) used to
## detect stale caches.
@export var source_hash: int = 0

@export var track_id: String = ""
@export var ship_id: String = ""
@export var track_length: float = 0.0
@export var sample_count: int = 0

## Optimized racing line: lateral offset from centerline per sample (meters).
@export var lateral_offsets: PackedFloat32Array = PackedFloat32Array()

## Target speed per sample (already includes braking/acceleration passes).
@export var target_speeds: PackedFloat32Array = PackedFloat32Array()

## True geometric curvature (1/m) of the optimized line per sample.
@export var curvatures: PackedFloat32Array = PackedFloat32Array()

## True when target_speeds came from AILineTrainer measuring the real ship
## against this line, rather than from the analytic model alone.
@export var is_trained: bool = false

## Best lap time the trainer actually achieved with this profile, in seconds.
@export var trained_lap_time: float = 0.0

## Iterations the trainer ran to reach it.
@export var trained_iterations: int = 0

# ============================================================================
# PER-SAMPLE STYLE GAINS
# ============================================================================
#
# A strong driver does not use one technique for a whole lap. These arrays let
# the controller vary its behaviour around the track: the style search times
# several driving styles per track segment and splices the winner of each into
# these arrays.
#
# Empty arrays mean "no style data", and the controller keeps its own defaults.
# Values are ABSOLUTE parameter values, not multipliers, so a line authored by
# one version of the tool cannot be silently rescaled by another.

## AIControlDecider.max_corner_airbrake per sample.
@export var style_airbrake: PackedFloat32Array = PackedFloat32Array()

## AIControlDecider.corner_steer_reserve per sample.
@export var style_reserve: PackedFloat32Array = PackedFloat32Array()

## AILineFollower.baked_steer_lookahead_max per sample (meters).
@export var style_lookahead: PackedFloat32Array = PackedFloat32Array()

## AIControlDecider.steering_sensitivity per sample.
@export var style_sensitivity: PackedFloat32Array = PackedFloat32Array()

## Human-readable record of which style won which segment, for debugging.
@export var style_log: PackedStringArray = PackedStringArray()

func has_style_gains() -> bool:
	return style_airbrake.size() == sample_count and sample_count > 0

func get_style_airbrake_at(offset: float) -> float:
	return _interp(style_airbrake, offset)

func get_style_reserve_at(offset: float) -> float:
	return _interp(style_reserve, offset)

func get_style_lookahead_at(offset: float) -> float:
	return _interp(style_lookahead, offset)

func get_style_sensitivity_at(offset: float) -> float:
	return _interp(style_sensitivity, offset)

## Usable corridor per sample as BOUNDS IN SPLINE-FRAME LATERAL COORDINATES
## (min = leftmost allowed lateral, max = rightmost), ship clearance already
## subtracted. These are anchored to the MEASURED surface center, so they
## remain correct even when the physical geometry is offset from the spline
## (e.g. transforms on CSG geometry nodes). Kept for validation, debugging,
## and future per-pilot line variation.
@export var corridor_min: PackedFloat32Array = PackedFloat32Array()
@export var corridor_max: PackedFloat32Array = PackedFloat32Array()

# ============================================================================
# VALIDITY
# ============================================================================

func is_usable() -> bool:
	return sample_count > 8 \
		and lateral_offsets.size() == sample_count \
		and target_speeds.size() == sample_count

# ============================================================================
# SAMPLING (wrap-around linear interpolation)
# ============================================================================

func _interp(arr: PackedFloat32Array, offset: float) -> float:
	if arr.is_empty() or sample_count <= 0:
		return 0.0
	offset = fposmod(offset, 1.0)
	var f := offset * float(sample_count)
	var i0 := int(floorf(f)) % sample_count
	var i1 := (i0 + 1) % sample_count
	var t := f - floorf(f)
	return lerpf(arr[i0], arr[i1], t)

func get_lateral_at(offset: float) -> float:
	return _interp(lateral_offsets, offset)

func get_speed_at(offset: float) -> float:
	return _interp(target_speeds, offset)

func get_curvature_at(offset: float) -> float:
	return _interp(curvatures, offset)

## Minimum profile speed over a window ahead of `offset`. The follower uses
## this so the controller leads the profile slightly (starts slowing a beat
## early) instead of chasing it sample-by-sample. Window is in meters.
func get_min_speed_ahead(offset: float, window_meters: float) -> float:
	if track_length <= 0.0 or sample_count <= 0 or target_speeds.is_empty():
		return get_speed_at(offset)
	var spacing := track_length / float(sample_count)
	var samples_ahead := clampi(int(ceil(window_meters / maxf(spacing, 0.1))), 1, sample_count)
	var start := int(floorf(fposmod(offset, 1.0) * float(sample_count)))
	var min_v := INF
	for k in range(samples_ahead + 1):
		min_v = minf(min_v, target_speeds[(start + k) % sample_count])
	return min_v

func get_debug_info() -> String:
	if not is_usable():
		return "BakedRacingLine: NOT USABLE"
	var min_v := INF
	var max_v := 0.0
	for v in target_speeds:
		min_v = minf(min_v, v)
		max_v = maxf(max_v, v)
	return "BakedRacingLine: %d samples, %.0fm, speeds %.0f-%.0f (%s / %s)" % [
		sample_count, track_length, min_v, max_v, track_id, ship_id
	]
