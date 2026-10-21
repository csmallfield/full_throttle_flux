@tool
extends Node
class_name MagneticTrack

## Magnetic lock zones for a track (v30).
##
## Add one of these to a track scene, point `spline_path` at the MainSpline and
## list MagneticZone resources in `zones`. Ships find it through the
## "magnetic_track" group and each keeps a MagneticTrack.Tracker that follows
## its distance along the spline (a local search, so a ship on the loop exit is
## never confused with the loop entry running beside it).
##
## Tracks without this node behave exactly as before.

const GROUP := "magnetic_track"

@export var spline_path: NodePath = NodePath("../MainSpline")

@export var zones: Array[MagneticZone] = []

## Debug override for every zone's magnet_strength: -1 = use each zone's own
## value, 0..1 forces that value everywhere. Handy for A/B testing the two
## gravity models without editing the zones.
@export_range(-1.0, 1.0) var magnet_override: float = -1.0

var _path: Path3D
var _curve: Curve3D
var _length: float = 0.0


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	_resolve()


func _resolve() -> bool:
	if _curve and is_instance_valid(_path):
		return true
	_path = get_node_or_null(spline_path) as Path3D
	if _path == null or _path.curve == null:
		return false
	_curve = _path.curve
	_length = _curve.get_baked_length()
	return _length > 0.0


func is_valid() -> bool:
	return _resolve()


func get_length() -> float:
	_resolve()
	return _length


func get_path3d() -> Path3D:
	_resolve()
	return _path


## Strongest zone weight at `distance` and the zone that produced it.
func zone_at(distance: float) -> Array:
	var best_w := 0.0
	var best: MagneticZone = null
	for z in zones:
		if z == null:
			continue
		var w := z.weight_at(distance, _length)
		if w > best_w:
			best_w = w
			best = z
	return [best_w, best]


func magnet_of(zone: MagneticZone) -> float:
	if magnet_override >= 0.0:
		return magnet_override
	return zone.magnet_strength if zone else 0.0


## Global-space surface frame at `distance`: origin on the road centre line,
## basis.y = road up (tilt applied), -basis.z = driving direction.
func frame_at(distance: float) -> Transform3D:
	_resolve()
	var local := _curve.sample_baked_with_rotation(clampf(distance, 0.0, _length), true, true)
	return _path.global_transform * local


## Distance along the spline of the closest point to `world_pos`.
func closest_distance(world_pos: Vector3) -> float:
	_resolve()
	var local := _path.global_transform.affine_inverse() * world_pos
	return _curve.get_closest_offset(local)


## True if `distance` lies inside any enabled zone or its ramps.
func is_in_zone(distance: float) -> bool:
	return (zone_at(distance)[0] as float) > 0.0


## Per-ship state. Cheap to update every physics tick.
func make_tracker() -> Tracker:
	return Tracker.new(self)


class Tracker extends RefCounted:
	var track: MagneticTrack
	var distance: float = -1.0
	var weight: float = 0.0
	var zone: MagneticZone = null
	var magnet: float = 0.0
	var frame := Transform3D.IDENTITY
	var surface_up := Vector3.UP
	## Signed height of the ship above the road plane along surface_up.
	var height: float = 0.0
	## Lateral offset from the centre line (+ = right of travel).
	var lateral: float = 0.0
	
	const WINDOW := 40.0     # metres searched either side of the last distance
	const STEP := 2.0
	const LOST := 30.0       # further than this from every sample = re-acquire globally
	
	func _init(t: MagneticTrack) -> void:
		track = t
	
	func reset() -> void:
		distance = -1.0
	
	func update(world_pos: Vector3) -> void:
		if not track.is_valid():
			weight = 0.0
			zone = null
			return
		var length := track.get_length()
		if distance < 0.0:
			distance = track.closest_distance(world_pos)
		else:
			distance = _local_search(world_pos, length)
		
		var zr := track.zone_at(distance)
		weight = zr[0]
		zone = zr[1]
		magnet = track.magnet_of(zone)
		
		if weight > 0.0:
			frame = track.frame_at(distance)
			surface_up = frame.basis.y.normalized()
			var rel := world_pos - frame.origin
			height = rel.dot(surface_up)
			lateral = rel.dot(frame.basis.x.normalized())
	
	func _local_search(world_pos: Vector3, length: float) -> float:
		var path := track.get_path3d()
		var local := path.global_transform.affine_inverse() * world_pos
		var curve := path.curve
		var best_d := distance
		var best_sq := INF
		var d := -WINDOW
		while d <= WINDOW:
			var s := _wrap(distance + d, length)
			var sq := curve.sample_baked(s).distance_squared_to(local)
			if sq < best_sq:
				best_sq = sq
				best_d = s
			d += STEP
		if best_sq > LOST * LOST:
			return curve.get_closest_offset(local)
		# Refine by projecting onto the tangent (two Newton-style steps).
		for i in 2:
			var p := curve.sample_baked(best_d)
			var ahead := curve.sample_baked(minf(best_d + 0.5, length))
			var behind := curve.sample_baked(maxf(best_d - 0.5, 0.0))
			var tan := ahead - behind
			if tan.length_squared() < 1e-6:
				break
			tan = tan.normalized()
			best_d = _wrap(best_d + clampf((local - p).dot(tan), -STEP, STEP), length)
		return best_d
	
	static func _wrap(d: float, length: float) -> float:
		var r := fmod(d, length)
		return r + length if r < 0.0 else r
