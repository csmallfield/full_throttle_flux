extends RefCounted
class_name TrackSplineHelper

## Track Spline Helper
## Utility class for working with track splines.
## Provides world-to-spline and spline-to-world conversions.

# ============================================================================
# CONFIGURATION
# ============================================================================

## Names to search for when finding the track spline
const SPLINE_NODE_NAMES: Array[String] = ["MainSpline", "Track", "RacingLine", "AISpline", "Spline"]

## How many samples to use when searching for closest point
const SEARCH_RESOLUTION: int = 200

## Cache resolution for baked points
const CACHE_RESOLUTION: int = 500

# ============================================================================
# STATE
# ============================================================================

var track_path: Path3D
var curve: Curve3D
var total_length: float = 0.0
var is_valid: bool = false

## Cached baked points for fast lookups
var cached_points: PackedVector3Array
var cached_offsets: PackedFloat32Array  # Corresponding spline offsets (0-1)

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init(track_root: Node = null) -> void:
	if track_root:
		initialize(track_root)

func initialize(track_root: Node) -> bool:
	"""Initialize with a track scene root. Searches for Path3D node."""
	track_path = _find_track_spline(track_root)
	
	if not track_path or not track_path.curve:
		push_warning("TrackSplineHelper: Could not find valid track spline in scene")
		is_valid = false
		return false
	
	curve = track_path.curve
	total_length = curve.get_baked_length()
	
	_build_point_cache()
	
	is_valid = true
	print("TrackSplineHelper: Initialized with spline '%s', length: %.1f units" % [track_path.name, total_length])
	return true

func _find_track_spline(root: Node) -> Path3D:
	"""Search for Path3D node by known names, then by type."""
	# First, search by name
	for search_name in SPLINE_NODE_NAMES:
		var found := _find_node_by_name(root, search_name)
		if found and found is Path3D:
			return found as Path3D
	
	# Fallback: find any Path3D
	var any_path := _find_node_by_type(root, "Path3D")
	if any_path:
		return any_path as Path3D
	
	return null

func _find_node_by_name(node: Node, search_name: String) -> Node:
	if node.name == search_name:
		return node
	for child in node.get_children():
		var found := _find_node_by_name(child, search_name)
		if found:
			return found
	return null

func _find_node_by_type(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name:
		return node
	for child in node.get_children():
		var found := _find_node_by_type(child, type_name)
		if found:
			return found
	return null

func _build_point_cache() -> void:
	"""Pre-compute points along the spline for fast lookups."""
	cached_points = PackedVector3Array()
	cached_offsets = PackedFloat32Array()
	
	for i in range(CACHE_RESOLUTION):
		var offset := float(i) / float(CACHE_RESOLUTION - 1)
		var distance := offset * total_length
		var point := curve.sample_baked(distance)
		
		# Transform to world space
		point = track_path.global_transform * point
		
		cached_points.append(point)
		cached_offsets.append(offset)

# ============================================================================
# POSITION QUERIES
# ============================================================================

func world_to_spline_offset(world_position: Vector3) -> float:
	"""Convert a world position to a spline offset (0.0 - 1.0)."""
	if not is_valid:
		return 0.0
	
	# Find closest cached point
	var closest_idx := 0
	var closest_dist := INF
	
	for i in range(cached_points.size()):
		var dist := world_position.distance_squared_to(cached_points[i])
		if dist < closest_dist:
			closest_dist = dist
			closest_idx = i
	
	# Refine search around closest point
	var search_start := maxf(0.0, cached_offsets[closest_idx] - 0.02)
	var search_end := minf(1.0, cached_offsets[closest_idx] + 0.02)
	
	var best_offset := cached_offsets[closest_idx]
	var best_dist := closest_dist
	
	var steps := 20
	for i in range(steps):
		var offset := search_start + (search_end - search_start) * (float(i) / float(steps - 1))
		var point := spline_offset_to_world(offset)
		var dist := world_position.distance_squared_to(point)
		if dist < best_dist:
			best_dist = dist
			best_offset = offset
	
	return best_offset

func spline_offset_to_world(offset: float) -> Vector3:
	"""Convert a spline offset (0.0 - 1.0) to world position."""
	if not is_valid:
		return Vector3.ZERO
	
	# Wrap offset to valid range
	offset = fmod(offset, 1.0)
	if offset < 0:
		offset += 1.0
	
	var distance := offset * total_length
	var local_point := curve.sample_baked(distance)
	return track_path.global_transform * local_point

func spline_offset_to_world_with_lateral(offset: float, lateral: float) -> Vector3:
	"""Get world position at spline offset with lateral offset from centerline."""
	if not is_valid:
		return Vector3.ZERO
	
	var center := spline_offset_to_world(offset)
	var tangent := get_tangent_at_offset(offset)
	var up := get_up_at_offset(offset)
	
	# Calculate right vector - perpendicular to forward, in the track plane
	# tangent.cross(up) gives RIGHT in Godot's coordinate system
	var right := tangent.cross(up).normalized()  # FIXED: was up.cross(tangent)
	
	# Debug output to verify the calculation
	if Engine.get_physics_frames() % 120 == 0:
		print("LATERAL DEBUG: lateral=%.1f tangent=%s up=%s right=%s" % [
			lateral, tangent, up, right
		])
		print("LATERAL DEBUG: center=%s result=%s" % [
			center, center + right * lateral
		])
	
	return center + right * lateral

func get_tangent_at_offset(offset: float) -> Vector3:
	"""Get the forward direction at a spline offset."""
	if not is_valid:
		return Vector3.FORWARD
	
	# Sample two nearby points to get tangent
	var delta := 0.001
	var pos_before := spline_offset_to_world(offset - delta)
	var pos_after := spline_offset_to_world(offset + delta)
	
	return (pos_after - pos_before).normalized()

func get_up_at_offset(offset: float) -> Vector3:
	"""Get the up vector at a spline offset (accounts for track banking)."""
	if not is_valid:
		return Vector3.UP
	
	offset = fmod(offset, 1.0)
	if offset < 0:
		offset += 1.0
	
	var distance := offset * total_length
	var up := curve.sample_baked_up_vector(distance)
	
	# Transform to world space
	return track_path.global_transform.basis * up

# ============================================================================
# DISTANCE / LOOKAHEAD
# ============================================================================

func distance_to_offset(distance: float) -> float:
	"""Convert a distance in units to a spline offset delta."""
	if total_length <= 0:
		return 0.0
	return distance / total_length

func offset_to_distance(offset: float) -> float:
	"""Convert a spline offset to distance in units."""
	return offset * total_length

func get_lookahead_offset(current_offset: float, lookahead_distance: float) -> float:
	"""Get the spline offset that is lookahead_distance units ahead."""
	var delta := distance_to_offset(lookahead_distance)
	var target := current_offset + delta
	
	# Wrap around for closed tracks
	if target > 1.0:
		target -= 1.0
	
	return target

# ============================================================================
# CURVATURE ANALYSIS
# ============================================================================

func get_curvature_at_offset(offset: float, sample_distance: float = 20.0) -> float:
	"""
	Estimate track curvature at a given offset.
	Returns 0.0 for straight, higher values for tighter curves.
	Useful for AI speed estimation on tracks without recorded data.
	"""
	if not is_valid:
		return 0.0
	
	var delta := distance_to_offset(sample_distance)
	
	var pos_current := spline_offset_to_world(offset)
	var pos_ahead := spline_offset_to_world(offset + delta)
	var pos_further := spline_offset_to_world(offset + delta * 2.0)
	
	var dir1 := (pos_ahead - pos_current).normalized()
	var dir2 := (pos_further - pos_ahead).normalized()
	
	# Dot product: 1.0 = straight, 0.0 = 90 degree turn, -1.0 = hairpin
	var dot := dir1.dot(dir2)
	
	# Convert to curvature value (0 = straight, ~2 = hairpin)
	return 1.0 - dot

func estimate_safe_speed(offset: float, max_speed: float, min_speed_ratio: float = 0.4) -> float:
	"""
	Estimate a safe speed based on upcoming track curvature.
	Used as fallback when no recorded data exists.
	"""
	var curvature := get_curvature_at_offset(offset)
	var min_speed := max_speed * min_speed_ratio
	
	# Map curvature to speed (adjust multiplier based on handling)
	var speed_factor: float = 1.0 - clamp(curvature * 2.5, 0.0, 1.0 - min_speed_ratio)
	
	return max_speed * speed_factor

# ============================================================================
# LATERAL OFFSET CALCULATION
# ============================================================================

func calculate_lateral_offset(world_position: Vector3, spline_offset: float) -> float:
	"""
	Calculate how far a position is from the track centerline.
	Negative = left of center, Positive = right of center.
	"""
	if not is_valid:
		return 0.0
	
	var center := spline_offset_to_world(spline_offset)
	var tangent := get_tangent_at_offset(spline_offset)
	var up := get_up_at_offset(spline_offset)
	var right := tangent.cross(up).normalized()  # FIXED: was up.cross(tangent)
	
	var to_position := world_position - center
	return to_position.dot(right)

# ============================================================================
# DEBUG
# ============================================================================

func get_debug_info() -> String:
	if not is_valid:
		return "TrackSplineHelper: Invalid (no spline found)"
	return "TrackSplineHelper: '%s', Length: %.1f, Points cached: %d" % [
		track_path.name, total_length, cached_points.size()
	]
