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

@export_group("Road Surface (v33)")

## Respawn points sit this far above the road surface, measured along the
## road's normal (v33). That is the default ship's hover height and well
## inside every hover ray's reach (hover_height * 3), so settle_on_surface()
## puts the ship straight onto its hover height: no drop, no bounce.
@export var surface_clearance: float = 2.75

## Rays look this far above and below the spline for the road (v33). The road
## meshes on the circuits are measured 21 m below to 16 m above their splines.
@export var surface_search_range: float = 45.0

@export_group("Off-Track Respawn (v33)")

## An airborne ship this far below the road surface it left is respawned
## (outside magnetic zones and designed jumps). See off_track_reason().
@export var fall_depth: float = 12.0

## An airborne ship (outside magnetic zones and designed jumps) is respawned
## after this many seconds in the air, wherever it is: on top of a wall,
## stranded on something, or falling beside a tall structure.
@export var max_air_time: float = 4.0

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
	## v31 (tracks with a TrackGraph): -1 = MainSpline, else branch index, and
	## metres along that path.
	var path: int = -1
	var path_distance: float = 0.0
	
	func _init(pos: Vector3, rot: Basis, offset: float) -> void:
		position = pos
		rotation = rot
		spline_offset = offset

var respawn_points: Array[RespawnPoint] = []
var spline_helper: TrackSplineHelper
var is_initialized: bool = false
var track_root_node: Node = null  # Store reference for world access
var _magnetic: MagneticTrack = null  # v30: set when the track has magnetic zones
var _graph: TrackGraph = null  # v31: set when the track has branches or jumps

# v33: the road surface along the MainSpline, every SURFACE_STEP metres
# (tracks without a TrackGraph). See _build_surface_table().
const SURFACE_STEP := 5.0
var _surf_pos := PackedVector3Array()   # road surface on the centre line
var _surf_up := PackedVector3Array()    # road normal there
var _surf_fwd := PackedVector3Array()   # direction of travel, in the road plane
var _surf_ok := PackedByteArray()       # 1 = road found
var _surf_found := 0
## MainSpline distance of the start/finish line (-1 = none). Respawns never put
## a ship on the other side of it (see _surface_respawn()).
var _line_distance := -1.0
## Per-ship airborne state for off_track_reason(): [surface index, seconds].
var _air := {}

func _find_graph(node: Node) -> TrackGraph:
	if node == null:
		return null
	if node is TrackGraph and (node as TrackGraph).is_valid():
		return node
	for child in node.get_children():
		var found := _find_graph(child)
		if found:
			return found
	return null

func _find_magnetic_track(node: Node) -> MagneticTrack:
	if node == null:
		return null
	if node is MagneticTrack and (node as MagneticTrack).is_valid():
		return node
	for child in node.get_children():
		var found := _find_magnetic_track(child)
		if found:
			return found
	return null

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
	
	# v30: on tracks with magnetic zones, never respawn inside one (the road
	# may be vertical or upside down there) and orient by the banked/rolled
	# surface frame, which a barrel roll leaves a full turn of tilt behind.
	_magnetic = _find_magnetic_track(track_root_node)
	_graph = _find_graph(track_root_node)
	if _graph and _graph.branches.is_empty() and _graph.jumps.is_empty():
		_graph = null
	if _graph:
		_generate_graph_points(num_points)
		return
	
	_build_surface_table()
	if _surf_found > 0:
		_generate_surface_points(num_points)
		return
	push_warning("TrackRespawnManager: no road surface found under the spline; using fixed-height points")
	
	for i in range(num_points):
		var spline_offset := float(i) / float(num_points)
		if _magnetic and _magnetic.is_in_zone(spline_offset * track_length):
			continue
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
	var up := spline_helper.get_up_at_offset(spline_offset, _magnetic != null)
	var right := tangent.cross(up).normalized()
	
	# Create rotation basis (forward = tangent, up = track up)
	var rotation := Basis(right, up, -tangent).orthonormalized()
	
	# Position above the track
	var respawn_pos := center_pos + up * respawn_height_offset
	
	# Check for collisions and adjust if needed
	respawn_pos = _find_clear_respawn_position(respawn_pos, up)
	
	return RespawnPoint.new(respawn_pos, rotation, spline_offset)

# ============================================================================
# ROAD SURFACE (v33, tracks without a TrackGraph)
# ============================================================================
# The road mesh is not where the spline is. On the circuits each road CSG node
# carries its own small transform (about 1 degree of tilt, pivoting on the
# spline's origin), so the road surface ends up anywhere from 21 m below to
# 16 m above the spline (measured: Utopia -2..+19, Swoopy -9..+14, Hairpin
# Alley +0.5..+16, The Drop -21..+4). "20 m above the spline" was therefore
# 0..41 m above the road, and on banked sections it was also tilted up to
# 50 degrees off the road, because it used the spline's untilted up vector.
# So the surface is found by raycast instead: once, at load, every
# SURFACE_STEP metres along the centre line.

## Fills _surf_*: for each sample, every road hit (layer 1, facing up) on a ray
## through the spline along the tilted road normal, keeping the one nearest the
## previous sample's height. That continuity is what keeps a bridge over the
## road (Utopia: 29 m above a later part of the lap) from being taken for it.
func _build_surface_table() -> void:
	_surf_pos.clear()
	_surf_up.clear()
	_surf_fwd.clear()
	_surf_ok.clear()
	_surf_found = 0
	if not track_root_node is Node3D or (track_root_node as Node3D).get_world_3d() == null:
		return
	var space := (track_root_node as Node3D).get_world_3d().direct_space_state
	var path := spline_helper.track_path
	var curve := spline_helper.curve
	var length := spline_helper.total_length
	var count := maxi(int(length / SURFACE_STEP), 1)
	var expected := INF
	for i in count:
		var f: Transform3D = path.global_transform * curve.sample_baked_with_rotation(
				float(i) * SURFACE_STEP, true, true)
		var up := f.basis.y.normalized()
		var from := f.origin + up * surface_search_range
		var to := f.origin - up * surface_search_range
		var best := {}
		var best_err := INF
		for k in 6:
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
			if hit.is_empty():
				break
			var normal: Vector3 = (hit.normal as Vector3).normalized()
			if normal.dot(up) > 0.5:
				var height: float = ((hit.position as Vector3) - f.origin).dot(up)
				var err := absf(height - (0.0 if expected == INF else expected))
				if err < best_err:
					best_err = err
					best = {"pos": hit.position, "normal": normal, "height": height}
			from = (hit.position as Vector3) - up * 0.05
		var ok := not best.is_empty() and (expected == INF or best_err < 8.0)
		if ok:
			expected = best.height
			var n: Vector3 = best.normal
			_surf_pos.append(best.pos)
			_surf_up.append(n)
			_surf_fwd.append((-f.basis.z).slide(n).normalized())
			_surf_found += 1
		else:
			_surf_pos.append(f.origin + up * (0.0 if expected == INF else expected))
			_surf_up.append(up)
			_surf_fwd.append((-f.basis.z).normalized())
		_surf_ok.append(1 if ok else 0)
	_line_distance = _find_line_distance(track_root_node)
	if debug_print:
		print("TrackRespawnManager: road surface found at %d/%d samples (every %.0f m)%s" % [
				_surf_found, count, SURFACE_STEP,
				"" if _line_distance < 0.0 else ", start/finish line at %.0f m" % _line_distance])

func _find_line_distance(node: Node) -> float:
	if node is StartFinishLine:
		var local := spline_helper.track_path.global_transform.affine_inverse() * (node as Node3D).global_position
		return spline_helper.curve.get_closest_offset(local)
	for c in node.get_children():
		var d := _find_line_distance(c)
		if d >= 0.0:
			return d
	return -1.0

const LINE_CLEARANCE := 15.0

## Respawn points every respawn_point_spacing metres where the road was found,
## surface_clearance above it along its normal, facing along it. None inside a
## magnetic zone (v30), and none within LINE_CLEARANCE of the start/finish
## line: a ship that appears inside its trigger at a standstill is taken for a
## wrong-way crossing, and its next lap would only clear that penalty.
func _generate_surface_points(num_points: int) -> void:
	var length := spline_helper.total_length
	var skipped := 0
	for i in range(num_points):
		var idx := clampi(roundi(float(i) / float(num_points) * length / SURFACE_STEP), 0, _surf_pos.size() - 1)
		var d := float(idx) * SURFACE_STEP
		if _magnetic and _magnetic.is_in_zone(d):
			continue
		if _line_distance >= 0.0 and absf(fposmod(d - _line_distance + length * 0.5, length) - length * 0.5) < LINE_CLEARANCE:
			continue
		if _surf_ok[idx] == 0:
			skipped += 1
			continue
		var up: Vector3 = _surf_up[idx]
		var fwd: Vector3 = _surf_fwd[idx]
		var rotation := Basis(fwd.cross(up).normalized(), up, -fwd).orthonormalized()
		var p := RespawnPoint.new(_surf_pos[idx] + up * surface_clearance, rotation, d / length)
		p.path_distance = d
		respawn_points.append(p)
	if debug_print:
		print("TrackRespawnManager: Generated %d respawn points on the road surface (%d spots without road skipped)" % [
				respawn_points.size(), skipped])

## Index of the surface sample nearest `world_position` (road samples only;
## brute force over every 4th sample, then refined). Nearest to the ROAD, not
## to the spline, so a ship on a bridge maps to the bridge.
func _surface_index(world_position: Vector3) -> int:
	var n := _surf_pos.size()
	var best := 0
	var best_sq := INF
	for i in range(0, n, 4):
		var sq := world_position.distance_squared_to(_surf_pos[i])
		if sq < best_sq:
			best_sq = sq
			best = i
	return _surface_index_near(world_position, best, 4)

## Nearest road sample within `window` samples of `around`.
func _surface_index_near(world_position: Vector3, around: int, window: int) -> int:
	var n := _surf_pos.size()
	var best := around
	var best_sq := INF
	for k in range(-window, window + 1):
		var i := posmod(around + k, n)
		if _surf_ok[i] == 0:
			continue
		var sq := world_position.distance_squared_to(_surf_pos[i])
		if sq < best_sq:
			best_sq = sq
			best = i
	return best

## v33: the last respawn point BEHIND `world_position` (the ship's last
## grounded spot). Behind, as Loop Lab always did (v30), so a respawn never
## gains ground; and never across the start/finish line, which counts laps by
## crossings: a ship put back behind the line would score the lap twice, one
## put ahead of it would lose one. If the point behind is across the line, the
## first point past the line is used instead (at most one spacing ahead).
func _surface_respawn(world_position: Vector3) -> Dictionary:
	var length := spline_helper.total_length
	var d := float(_surface_index(world_position)) * SURFACE_STEP
	var behind: RespawnPoint = null
	var best_gap := INF
	for p in respawn_points:
		var gap := fposmod(d - p.path_distance, length)
		if gap < best_gap:
			best_gap = gap
			behind = p
	if behind == null:
		return {"found": false}
	if _line_distance >= 0.0 and fposmod(_line_distance - behind.path_distance, length) < best_gap:
		var after: RespawnPoint = null
		var after_gap := INF
		for p in respawn_points:
			var g := fposmod(p.path_distance - _line_distance, length)
			if g < after_gap:
				after_gap = g
				after = p
		if after:
			behind = after
	return {"position": behind.position, "rotation": behind.rotation, "found": true,
			"path": -1, "path_distance": behind.path_distance}

## v33: two ships that leave at the same corner a moment apart get the same
## point. If another ship is within SPOT_CLEAR_RADIUS of it, use the spot
## SPOT_SIDE_STEP to its right, then to its left (the road is >= 15 m wide each
## side of the centre line on the circuits, 19.5 m on Fork Lab), else the
## point itself. settle_on_surface() then finds the road under the new spot.
const SPOT_CLEAR_RADIUS := 6.0
const SPOT_SIDE_STEP := 7.0

func _free_spot(pos: Vector3, rot: Basis, ship_rid: RID) -> Vector3:
	if not track_root_node is Node3D:
		return pos
	var space := (track_root_node as Node3D).get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = SPOT_CLEAR_RADIUS
	query.shape = sphere
	query.collision_mask = 2  # ships
	if ship_rid.is_valid():
		query.exclude = [ship_rid]
	for side in [0.0, 1.0, -1.0]:
		var p: Vector3 = pos + rot.x.normalized() * SPOT_SIDE_STEP * side
		query.transform = Transform3D(Basis.IDENTITY, p)
		if space.intersect_shape(query, 1).is_empty():
			return p
	return pos

# ============================================================================
# OFF-TRACK DETECTION (v33)
# ============================================================================
# The only trigger used to be y < respawn_y_threshold (-100): half a kilometre
# of free fall from The Drop's summit, and never for a ship stranded somewhere
# above it. Now, for a ship that is airborne outside a magnetic zone (v30 keeps
# its own rules there) and not flying a designed jump (v31 RespawnTriggers
# catch those), either of
#   * more than fall_depth below the road surface it left,
#   * airborne for more than max_air_time
# means it has left the track. The road reference is tracked locally from the
# ship's last grounded spot, so a ship falling past another part of the lap
# (Utopia's bridge) is still measured against the road it came off. Grounded
# ships cost nothing.

## "" while the ship is fine, else why it should respawn. Call once per tick.
func off_track_reason(ship: ShipController, delta: float) -> String:
	if ship.is_grounded or ship.magnet_weight > 0.0 or ship.jump != null:
		if not _air.is_empty():
			_air.erase(ship)
		return ""
	var st: Array = _air.get(ship, [-1, 0.0])
	st[1] = float(st[1]) + delta
	_air[ship] = st
	if float(st[1]) > max_air_time:
		return "airborne %.1f s" % float(st[1])
	var height: float
	if _graph:
		var loc := _graph.locate(ship.global_position)
		var f := _graph.frame_at(int(loc.path), float(loc.distance))
		height = (ship.global_position - f.origin).dot(f.basis.y.normalized())
	elif _surf_found > 0:
		var i: int = st[0]
		if i < 0:
			i = _surface_index(ship.last_safe_position)
		i = _surface_index_near(ship.global_position, i, 8)
		st[0] = i
		height = (ship.global_position - _surf_pos[i]).dot(_surf_up[i])
	else:
		return ""
	if height < -fall_depth:
		return "%.0f m below the road" % -height
	return ""

## v31: respawn points on the MainSpline and on every branch, none inside a
## jump (kicker to landing end) or in the run-up before one, so a ship that
## falls short comes back far enough before the jump to make it, on the path
## it was on. Branch points stop short of the junctions (main points cover
## those). Oriented by the banked road frame.
func _generate_graph_points(num_points: int) -> void:
	var length := spline_helper.total_length
	for i in range(num_points):
		var d := float(i) / float(num_points) * length
		if _magnetic and _magnetic.is_in_zone(d):
			continue
		if _graph.is_respawn_excluded(-1, d):
			continue
		respawn_points.append(_graph_point(-1, d, d))
	for bi in _graph.branches.size():
		var br: TrackBranch = _graph.branches[bi]
		var lb := _graph.path_length(bi)
		var b := br.fork_blend
		while b <= lb - br.rejoin_blend:
			if not _graph.is_respawn_excluded(bi, b):
				respawn_points.append(_graph_point(bi, b, _graph.branch_to_main(bi, b)))
			b += respawn_point_spacing
	if debug_print:
		print("TrackRespawnManager: Generated %d respawn points (main + %d branch(es), jumps excluded)" % [
			respawn_points.size(), _graph.branches.size()])

## Graph points sit GRAPH_RESPAWN_HEIGHT above the road, inside the hover
## ray's reach, so ShipController.settle_on_surface() puts the ship straight
## onto its hover height. From respawn_height_offset (20 m) the ray can't reach,
## the ship free-falls, and the stock hover spring pulls it down harder still
## once in range: measured ~42 u/s into the road, which pushed the hull
## through the road's one-sided collision on Fork Lab.
const GRAPH_RESPAWN_HEIGHT := 4.0

func _graph_point(path: int, d: float, main_d: float) -> RespawnPoint:
	var f := _graph.frame_at(path, d)
	var up := f.basis.y.normalized()
	var rotation := Basis(f.basis.x.normalized(), up, f.basis.z.normalized()).orthonormalized()
	var pos := f.origin + up * GRAPH_RESPAWN_HEIGHT
	var p := RespawnPoint.new(pos, rotation, main_d / spline_helper.total_length)
	p.path = path
	p.path_distance = d
	return p

## v31: the last respawn point BEHIND the ship on the path it is on; before a
## branch's first point, the last main point before its fork.
func _graph_respawn(world_position: Vector3) -> Dictionary:
	var loc := _graph.locate(world_position)
	var path: int = loc.path
	var main_d: float = loc.distance
	if path >= 0:
		var best: RespawnPoint = null
		for p in respawn_points:
			if p.path == path and p.path_distance <= float(loc.distance) \
					and (best == null or p.path_distance > best.path_distance):
				best = p
		if best:
			return {"position": best.position, "rotation": best.rotation, "found": true,
					"path": path, "path_distance": best.path_distance}
		main_d = _graph.branches[path].fork_distance
	var length := _graph.main_length()
	var behind: RespawnPoint = null
	var best_gap := INF
	for p in respawn_points:
		if p.path != -1:
			continue
		var gap := fposmod(main_d - p.path_distance, length)
		if gap < best_gap:
			best_gap = gap
			behind = p
	if behind == null:
		return {"found": false}
	return {"position": behind.position, "rotation": behind.rotation, "found": true,
			"path": -1, "path_distance": behind.path_distance}

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

func get_nearest_respawn_point(world_position: Vector3, ship_rid: RID = RID()) -> Dictionary:
	"""
	Find the nearest respawn point to a world position.
	Returns: { "position": Vector3, "rotation": Basis, "found": bool }
	v33: `ship_rid` (the ship respawning) is ignored when checking that the
	spot is free of other ships.
	"""
	if not is_initialized or respawn_points.is_empty():
		return {"found": false}
	
	if _graph or _surf_found > 0:
		var r := _graph_respawn(world_position) if _graph else _surface_respawn(world_position)
		if r.found:
			r.position = _free_spot(r.position, r.rotation, ship_rid)
		return r
	
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
	
	# v30: with magnetic zones, respawn at the last point BEHIND the ship.
	# The nearest point to a ship that fell out of a roll may be past it.
	if _magnetic:
		var behind: RespawnPoint = null
		var best_gap := INF
		for point in respawn_points:
			var gap := fmod(spline_offset - point.spline_offset + 1.0, 1.0)
			if gap < best_gap:
				best_gap = gap
				behind = point
		if behind:
			return {"position": behind.position, "rotation": behind.rotation, "found": true}
	
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
