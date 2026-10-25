extends RefCounted
class_name SplineSpan
## Distance-span maths shared by every "stretch of track" resource (v35):
## MagneticZone (v30) and TrackFxZone.
##
## A span is [start, end] in metres along a CLOSED spline `length` metres long,
## with smooth ramps before start and after end. If end < start the span wraps
## across the lap seam. Moved here unchanged from MagneticZone.weight_at().


## Blend weight 0..1 at `distance`: 1 inside [start, end], smoothstepped down
## to 0 across ramp_in before start and ramp_out after end, 0 elsewhere.
static func weight(distance: float, length: float, start: float, end: float,
		ramp_in: float, ramp_out: float) -> float:
	if length <= 0.0:
		return 0.0
	var span := wrap_distance(end - start, length)
	var into := wrap_distance(distance - start, length)
	if into <= span:
		return 1.0
	# Before the span: how far short of start are we?
	var before := wrap_distance(start - distance, length)
	if ramp_in > 0.0 and before < ramp_in:
		return smooth01(1.0 - before / ramp_in)
	# After the span: how far past end are we?
	var after := wrap_distance(distance - end, length)
	if ramp_out > 0.0 and after < ramp_out:
		return smooth01(1.0 - after / ramp_out)
	return 0.0


## `d` wrapped into [0, length).
static func wrap_distance(d: float, length: float) -> float:
	var r := fmod(d, length)
	return r + length if r < 0.0 else r


static func smooth01(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
