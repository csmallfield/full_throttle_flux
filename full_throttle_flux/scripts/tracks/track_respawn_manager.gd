extends Node
class_name TrackRespawnManager

## Track Respawn Manager
## Generates and manages procedural respawn points along the track's MainSpline.
## Ships can query for the nearest safe respawn point based on their position.

# ============================================================================
# CONFIGURATION
# ============================================================================

@export_group("Respawn Point Generation")

## Distance between respawn points along the spline (meters)
@export var respawn_point_spacing: float = 50.0

## Height above the spline to place respawn points
@export var respawn_height_offset: float = 20.0

## Radius to check for collisions at respawn points
@export var collision_check_radius: float = 5.0

## Maximum attempts to find a clear respawn spot
@export var max_collision_check_attempts: int = 5

## Vertical offset increment when searching for clear spot
@export var collision_avoidance_step: float = 2.0

@export_group("Debug")

## Show debug visualization of respawn points
@export var debug_visualization: bool = false

## Print debug info during initialization
@export var debug_print: bool = true

# ============================================================================
# RESPAWN POINT DATA
# ============================================================================

class RespawnPoint:
	var position: Vector3
	var rotation: Basis
	var spline_offset: float  # 0.0 to 1.0
	
	func _init(pos: Vector3, rot: Basis, offset: float) -> void:
		position = pos
		rotation = rot
		spline_offset = offset

var respawn_points: Array[RespawnPoint] = []
var spline_helper: TrackSplineHelper
var is_initialized: bool = false
var track_root_node: Node = null  # Store reference for world access

# Debug markers
var debug_markers: Array[MeshInstance3D] = []

# ============================================================================
# INITIALIZATION
# ============================================================================

func initialize(track_root: Node) -> bool:
	"""Initialize respawn system with track data."""
	if is_initialized:
		push_warning("TrackRespawnManager: Already initialized")
		return true
	
	# Store track root for world access
	track_root_node = track_root
	
	# Create spline helper
	spline_helper = TrackSplineHelper.new(track_root)
	if not spline_helper.is_valid:
		push_error("TrackRespawnManager: Failed to find track spline")
		return false
	
	# Wait a frame to ensure physics world is ready
	await get_tree().process_frame
	
	# Generate respawn points
	_generate_respawn_points()
	
	# Setup debug visualization
	if debug_visualization:
		_create_debug_markers()
	
	is_initialized = true
	
	if debug_print:
		print("TrackRespawnManager: Initialized with %d respawn points (spacing: %.1fm)" % [
			respawn_points.size(), respawn_point_spacing
		])
	
	return true

# ============================================================================
# RESPAWN POINT GENERATION
# ============================================================================

func _generate_respawn_points() -> void:
	"""Generate respawn points along the spline."""
	respawn_points.clear()
	
	var track_length := spline_helper.total_length
	var num_points := int(track_length / respawn_point_spacing)
	
	# Ensure at least a few points
	num_points = maxi(num_points, 4)
	
	if debug_print:
		print("TrackRespawnManager: Generating %d points for %.1fm track" % [num_points, track_length])
	
	for i in range(num_points):
		var spline_offset := float(i) / float(num_points)
		var point := _create_respawn_point(spline_offset)
		if point:
			respawn_points.append(point)
	
	if debug_print:
		print("TrackRespawnManager: Generated %d respawn points" % respawn_points.size())

func _create_respawn_point(spline_offset: float) -> RespawnPoint:
	"""Create a single respawn point at the given spline offset."""
	# Get centerline position
	var center_pos := spline_helper.spline_offset_to_world(spline_offset)
	
	# Get track orientation
	var tangent := spline_helper.get_tangent_at_offset(spline_offset)
	var up := spline_helper.get_up_at_offset(spline_offset)
	var right := tangent.cross(up).normalized()
	
	# Create rotation basis (forward = tangent, up = track up)
	var rotation := Basis(right, up, -tangent).orthonormalized()
	
	# Position above the track
	var respawn_pos := center_pos + up * respawn_height_offset
	
	# Check for collisions and adjust if needed
	respawn_pos = _find_clear_respawn_position(respawn_pos, up)
	
	return RespawnPoint.new(respawn_pos, rotation, spline_offset)

func _find_clear_respawn_position(initial_pos: Vector3, up_dir: Vector3) -> Vector3:
	"""Find a clear position for respawning, checking for collisions."""
	# Get world from track root (Node3D)
	if not track_root_node or not track_root_node is Node3D:
		# Can't do collision checks without a Node3D
		return initial_pos
	
	var world := (track_root_node as Node3D).get_world_3d()
	if not world:
		return initial_pos
	
	var space_state := world.direct_space_state
	if not space_state:
		return initial_pos
	
	var current_pos := initial_pos
	
	for attempt in range(max_collision_check_attempts):
		# Check sphere for collisions
		var query := PhysicsShapeQueryParameters3D.new()
		var shape := SphereShape3D.new()
		shape.radius = collision_check_radius
		query.shape = shape
		query.transform = Transform3D(Basis.IDENTITY, current_pos)
		
		# Check against ground (layer 1) and walls (layer 4)
		query.collision_mask = 1 | 4
		
		var result := space_state.intersect_shape(query, 1)
		
		if result.is_empty():
			# Found clear spot
			return current_pos
		
		# Move up and try again
		current_pos += up_dir * collision_avoidance_step
	
	# Return best attempt even if not perfectly clear
	return current_pos

# ============================================================================
# RESPAWN POINT QUERIES
# ============================================================================

func get_nearest_respawn_point(world_position: Vector3) -> Dictionary:
	"""
	Find the nearest respawn point to a world position.
	Returns: { "position": Vector3, "rotation": Basis, "found": bool }
	"""
	if not is_initialized or respawn_points.is_empty():
		return {"found": false}
	
	# Convert world position to spline offset
	var spline_offset := spline_helper.world_to_spline_offset(world_position)
	
	return get_respawn_point_at_offset(spline_offset)

func get_respawn_point_at_offset(spline_offset: float) -> Dictionary:
	"""
	Get the respawn point closest to a given spline offset.
	Returns: { "position": Vector3, "rotation": Basis, "found": bool }
	"""
	if not is_initialized or respawn_points.is_empty():
		return {"found": false}
	
	# Normalize offset to 0-1 range
	spline_offset = fmod(spline_offset, 1.0)
	if spline_offset < 0:
		spline_offset += 1.0
	
	# Find nearest respawn point
	var nearest_point: RespawnPoint = respawn_points[0]
	var min_distance := _circular_distance(spline_offset, nearest_point.spline_offset)
	
	for point in respawn_points:
		var distance := _circular_distance(spline_offset, point.spline_offset)
		if distance < min_distance:
			min_distance = distance
			nearest_point = point
	
	return {
		"position": nearest_point.position,
		"rotation": nearest_point.rotation,
		"found": true
	}

func _circular_distance(offset1: float, offset2: float) -> float:
	"""Calculate shortest distance between two points on a circular track (0-1)."""
	var direct := absf(offset1 - offset2)
	var wrap := 1.0 - direct
	return minf(direct, wrap)

# ============================================================================
# DEBUG VISUALIZATION
# ============================================================================

func _create_debug_markers() -> void:
	"""Create visual markers for respawn points."""
	_cleanup_debug_markers()
	
	for point in respawn_points:
		var marker := _create_sphere_marker(Color.GREEN, 1.5)
		marker.global_position = point.position
		get_tree().root.add_child(marker)
		debug_markers.append(marker)
		
		# Add direction indicator
		var direction_marker := _create_arrow_marker(Color.YELLOW)
		direction_marker.global_transform = Transform3D(point.rotation, point.position)
		get_tree().root.add_child(direction_marker)
		debug_markers.append(direction_marker)
	
	if debug_print:
		print("TrackRespawnManager: Created %d debug markers" % debug_markers.size())

func _create_sphere_marker(color: Color, radius: float) -> MeshInstance3D:
	"""Helper to create a colored sphere marker."""
	var marker := MeshInstance3D.new()
	
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	marker.mesh = sphere
	
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = material
	
	return marker

func _create_arrow_marker(color: Color) -> MeshInstance3D:
	"""Helper to create a directional arrow."""
	var marker := MeshInstance3D.new()
	
	# Use a cylinder as arrow shaft
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.3
	cylinder.bottom_radius = 0.3
	cylinder.height = 5.0
	marker.mesh = cylinder
	
	# Rotate to point forward (cylinder points up by default)
	marker.rotation_degrees.x = 90
	marker.position.z = -2.5  # Offset forward
	
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = material
	
	return marker

func _cleanup_debug_markers() -> void:
	"""Remove existing debug markers."""
	for marker in debug_markers:
		if is_instance_valid(marker):
			marker.queue_free()
	debug_markers.clear()

# ============================================================================
# CLEANUP
# ============================================================================

func _exit_tree() -> void:
	_cleanup_debug_markers()
