extends RefCounted
class_name SplineTracker
## Follows one body's distance along a closed Path3D, cheaply, every tick (v35).
##
## Same local search as MagneticTrack.Tracker (v30): look a short window either
## side of last tick's distance, so a ship on a loop exit or a crossover is
## never confused with the stretch running beside or under it. A full
## get_closest_offset() only on the first update, after reset(), or when the
## body is further than LOST from every sample (respawn, teleport).
##
## MagneticTrack.Tracker keeps its own copy for now so v35 cannot move a
## magnetic-zone lap; fold it onto this once FX work is merged.

const WINDOW := 40.0     # metres searched either side of the last distance
const STEP := 2.0
const LOST := 30.0       # further than this from every sample = re-acquire globally
const FAST_STEP := 6.0    # metres per refine step from last tick's distance
const FAST_SETTLE := 0.05 # last refine step under this = settled, skip the scan

var path: Path3D
var length: float = 0.0
## The four circuits render their road through the groundGeo node's own
## transform, up to ~21 m off the raw spline (TRACK_AUTHORING.md section 7;
## UtopiaKit.road_xf). Positions are mapped back through its inverse before the
## search, so distances agree with UtopiaKit and the cover survey. Identity on
## builder tracks.
var road_xf := Transform3D.IDENTITY
## Metres along the spline, [0, length). -1 = not acquired yet.
var distance: float = -1.0


func _init(p_path: Path3D, p_road_xf := Transform3D.IDENTITY) -> void:
	path = p_path
	road_xf = p_road_xf
	if is_instance_valid(path) and path.curve:
		length = path.curve.get_baked_length()


func is_valid() -> bool:
	return is_instance_valid(path) and path.curve != null and length > 0.0


func reset() -> void:
	distance = -1.0


## Updates and returns the distance for `world_pos` (-1 if the path is gone).
func update(world_pos: Vector3) -> float:
	if not is_valid():
		distance = -1.0
		return distance
	var local := path.global_transform.affine_inverse() * (road_xf.affine_inverse() * world_pos)
	if distance < 0.0:
		distance = path.curve.get_closest_offset(local)
	else:
		distance = _local_search(local)
	return distance


## Global-space frame at the current distance, through road_xf: origin on the
## road centre line (the driving surface is ~2 m above it on the circuits),
## basis.y = road up (tilt applied), -basis.z = driving direction.
func frame() -> Transform3D:
	if not is_valid() or distance < 0.0:
		return Transform3D.IDENTITY
	var t := path.curve.sample_baked_with_rotation(clampf(distance, 0.0, length), true, true)
	return road_xf * (path.global_transform * t)


func _local_search(local: Vector3) -> float:
	var curve := path.curve
	# v38.1: a body moves a few metres per tick, so first refine from last
	# tick's distance; scan the window only if that does not settle (a jump,
	# a hairpin). Even more local than the scan, so loops and crossovers are
	# as safe as before; ~9 curve samples instead of ~47.
	var quick := _refine(curve, local, distance, 3, FAST_STEP)
	if quick.y < FAST_SETTLE:
		return quick.x
	var best_d := distance
	var best_sq := INF
	var d := -WINDOW
	while d <= WINDOW:
		var s := SplineSpan.wrap_distance(distance + d, length)
		var sq := curve.sample_baked(s).distance_squared_to(local)
		if sq < best_sq:
			best_sq = sq
			best_d = s
		d += STEP
	if best_sq > LOST * LOST:
		return curve.get_closest_offset(local)
	return _refine(curve, local, best_d, 2, STEP).x


## Newton-style steps projecting `local` onto the tangent from distance `d`,
## each clamped to `max_step`. Returns (distance, |last step|): a last step
## near zero means it settled on the nearest point.
func _refine(curve: Curve3D, local: Vector3, d: float, steps: int, max_step: float) -> Vector2:
	var last := INF
	for i in steps:
		var p := curve.sample_baked(d)
		var ahead := curve.sample_baked(minf(d + 0.5, length))
		var behind := curve.sample_baked(maxf(d - 0.5, 0.0))
		var tan := ahead - behind
		if tan.length_squared() < 1e-6:
			break
		tan = tan.normalized()
		var step := clampf((local - p).dot(tan), -max_step, max_step)
		d = SplineSpan.wrap_distance(d + step, length)
		last = absf(step)
	return Vector2(d, last)
