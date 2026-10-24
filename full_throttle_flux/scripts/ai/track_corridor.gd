extends RefCounted
class_name TrackCorridor
## v34: usable lateral corridor [min, max] (metres, +right, tilted frame) at a
## spline offset, measured with the same wall raycasts AIRacingLineBaker uses
## but lazily, per bucket, at run time, because baked lines do not persist
## their widths. One instance per track per AI; buckets are shared statically
## per track root so eight AIs measure each bucket once.

const BUCKETS := 256
const WALL_MASK := 4
const GROUND_MASK := 1
const RAY_HEIGHT := 2.0
const RAY_LENGTH := 40.0
const SURFACE_PROBE_HEIGHT := 45.0
const SURFACE_PROBE_LENGTH := 140.0
const MAX_HALF_WIDTH := 20.0
const FALLBACK_HALF_WIDTH := 12.0
## Half the hull (0.63 m) plus a margin the strategy can lean against.
const SHIP_CLEARANCE := 2.0

static var _cache: Dictionary = {}   # track root id -> PackedVector2Array (x = min, y = max; NAN = unmeasured)

var helper: TrackSplineHelper
var world: World3D
var _buckets: PackedVector2Array

func _init(p_helper: TrackSplineHelper, p_world: World3D, track_root: Node) -> void:
	helper = p_helper
	world = p_world
	var key: int = track_root.get_instance_id() if track_root else 0
	if not _cache.has(key):
		var arr := PackedVector2Array()
		arr.resize(BUCKETS)
		arr.fill(Vector2(NAN, NAN))
		_cache[key] = arr
	_buckets = _cache[key]

## [min, max] lateral at `offset`.
func limits(offset: float) -> Vector2:
	var i: int = int(floor(fposmod(offset, 1.0) * BUCKETS)) % BUCKETS
	var v: Vector2 = _buckets[i]
	if is_nan(v.x):
		v = _measure((float(i) + 0.5) / float(BUCKETS))
		_buckets[i] = v
	return v

func _measure(offset: float) -> Vector2:
	var fallback := Vector2(-FALLBACK_HALF_WIDTH, FALLBACK_HALF_WIDTH)
	if world == null or helper == null or not helper.is_valid:
		return fallback
	var space := world.direct_space_state
	if space == null:
		return fallback
	var center: Vector3 = helper.spline_offset_to_world(offset)
	var up: Vector3 = helper.get_up_at_offset(offset, true)
	var tangent: Vector3 = helper.get_tangent_at_offset(offset)
	var q := PhysicsRayQueryParameters3D.create(center + up * SURFACE_PROBE_HEIGHT,
			center + up * (SURFACE_PROBE_HEIGHT - SURFACE_PROBE_LENGTH), GROUND_MASK)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return fallback
	var surf: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	var surf_lat: float = helper.calculate_lateral_offset(surf, offset, true)
	var right: Vector3 = tangent.cross(normal).normalized()
	if right.length_squared() < 0.5:
		right = tangent.cross(up).normalized()
	var origin: Vector3 = surf + normal * RAY_HEIGHT
	var wr := _cast(space, origin, right)
	var wl := _cast(space, origin, -right)
	return Vector2(surf_lat - wl, surf_lat + wr)

func _cast(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * RAY_LENGTH, WALL_MASK)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return FALLBACK_HALF_WIDTH
	return clampf(origin.distance_to(hit.position) - SHIP_CLEARANCE, 1.0, MAX_HALF_WIDTH)
