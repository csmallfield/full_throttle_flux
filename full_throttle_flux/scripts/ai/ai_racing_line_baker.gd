extends RefCounted
class_name AIRacingLineBaker

## AI Racing Line Baker
## Offline computation of an optimized racing line + speed profile.
##
## Pipeline:
##   1. Sample the track spline uniformly (~6m spacing)
##   2. Measure the usable corridor per sample via physics raycasts against
##      wall geometry (collision layer 4) -- no hardcoded track widths
##   3. Optimize lateral offsets with iterative curvature-minimizing
##      relaxation ("elastic band"), constrained to the measured corridor
##   4. Compute true geometric curvature (1/radius) of the optimized line
##   5. Two-pass speed profile from ShipPerformanceModel:
##      corner speed limits -> backward braking pass -> forward accel pass
##
## Results are cached to user://baked_lines/ keyed by a content hash of the
## spline + ship profile + baker config, so the cost is paid once per combo.
##
## The output line and speeds are achievable within the ship's real physics
## (same steering rate, grip, thrust, and airbrake behavior the player has).

const WALL_COLLISION_MASK := 4  # walls live on layer 4 (see track scenes)
const CACHE_DIR := "user://baked_lines/"

# ============================================================================
# CONFIGURATION
# ============================================================================

## Approximate distance between line samples (meters).
var sample_spacing_target: float = 3.0

var min_samples: int = 256
var max_samples: int = 4096

## Elastic-band relaxation iterations (early-out on convergence).
var relaxation_iterations: int = 800
var relaxation_alpha: float = 0.35
var convergence_epsilon: float = 0.002

## Subtracted from measured wall distance: half ship width plus margin.
var ship_clearance: float = 4.0

## Additional corridor shrink (meters, per side) so the OPTIMIZED LINE never
## demands riding closer to a wall than the controller's transient tracking
## error (~2-3m entering corners at speed). The speed profile recomputes
## consistently for the slightly tighter line, so this trades a little
## theoretical pace for not scraping walls -- a very good trade.
var line_margin: float = 1.5

## Corridor half-width used where wall raycasts miss (open track edges).
var fallback_half_width: float = 12.0

## Hard cap on measured usable half-width. The track can loop close to
## itself, so a very long "hit" is a far-section artifact, not real corridor.
var max_usable_half_width: float = 20.0

## Height above the ACTUAL track surface to cast wall rays from (mid-wall on
## standard track geometry: walls span roughly -0.5..+4.7 above the surface).
var ray_height: float = 2.0
var ray_length: float = 40.0

## Surface-finding drop ray: cast from this far above the spline point, along
## the banked down direction, against the ground layer. Robust against any
## offset between the spline and the physical geometry (e.g. transforms on
## the CSG geometry nodes -- test_circuit_2's geo nodes carry a ~1 degree
## rotation that displaces the physical track up to ~30m from the spline).
const GROUND_COLLISION_MASK := 1
var surface_probe_height: float = 45.0
var surface_probe_length: float = 140.0

## Reject surface hits farther than this from the spline point (crossover /
## far-section protection).
var surface_max_deviation: float = 60.0

## Cornering confidence passed to the ShipPerformanceModel (see its docs).
var cornering_confidence: float = 0.98

## Planned airbrake application for braking zones. Lower = earlier, longer,
## easier-to-track braking zones (the controller has smoothing lag, so
## planning at full application produces zones too short to execute).
var planned_brake_application: float = 0.7

## If true, straightaway speeds cap at profile.max_speed. The physics itself
## has no clamp (true top speed is the thrust/drag equilibrium, ~134 with
## default profile), so set false only if you intend AI to use that.
var respect_profile_max_speed: bool = true

## Disk cache under user://baked_lines/.
var use_cache: bool = true

## Filled by bake(): fraction of width raycasts that missed walls.
var last_ray_miss_ratio: float = 0.0

# ============================================================================
# PUBLIC API
# ============================================================================

## Bake (or load from cache) a racing line for this spline + ship profile.
## `world` provides the physics space for wall raycasts; pass
## get_viewport().find_world_3d() from any node in the running scene. CSG
## collision shapes build during the first physics frames after a track
## loads, so await a couple of physics_frames before calling this.
func bake(spline_helper: TrackSplineHelper, ship_profile: ShipProfile,
		world: World3D, track_id: String = "") -> BakedRacingLine:
	if not spline_helper or not spline_helper.is_valid:
		push_error("AIRacingLineBaker: invalid spline helper")
		return null
	if not ship_profile:
		push_error("AIRacingLineBaker: no ship profile")
		return null

	var perf := ShipPerformanceModel.new(ship_profile)
	perf.cornering_confidence = cornering_confidence
	perf.planned_brake_application = planned_brake_application
	perf.configure(ship_profile)  # recompute with tuned values
	var source_hash := _compute_source_hash(spline_helper, ship_profile)

	if use_cache:
		var cached := _try_load_cache(track_id, ship_profile.ship_id, source_hash)
		if cached:
			print("AIRacingLineBaker: cache hit -- %s" % cached.get_debug_info())
			return cached

	var t_start := Time.get_ticks_msec()

	var length := spline_helper.total_length
	var n := clampi(int(length / maxf(sample_spacing_target, 1.0)), min_samples, max_samples)

	# --- 1. Sample centerline geometry (BANKED frame: tilts applied, matching
	#         how CSGPolygon3D PATH_FOLLOW extrudes the actual track/walls) ---
	var centers := PackedVector3Array()
	var rights := PackedVector3Array()
	var ups := PackedVector3Array()
	centers.resize(n)
	rights.resize(n)
	ups.resize(n)
	for i in range(n):
		var offset := float(i) / float(n)
		centers[i] = spline_helper.spline_offset_to_world(offset)
		var tangent := spline_helper.get_tangent_at_offset(offset)
		var up := spline_helper.get_up_at_offset(offset, true)
		ups[i] = up
		rights[i] = tangent.cross(up).normalized()

	# --- 2. Measure corridor via wall raycasts, expressed as BOUNDS in
	#         spline-frame lateral coordinates (anchored to the real surface,
	#         so geometry offset from the spline is handled correctly) ---
	var corridor_min := PackedFloat32Array()
	var corridor_max := PackedFloat32Array()
	_measure_corridor(spline_helper, centers, rights, ups, world, corridor_min, corridor_max)

	# --- 3. Elastic-band relaxation within corridor ---
	var laterals := _relax_racing_line(centers, rights, corridor_min, corridor_max)

	# --- 4. Curvature of the optimized line ---
	var points := PackedVector3Array()
	points.resize(n)
	for i in range(n):
		points[i] = centers[i] + rights[i] * laterals[i]
	var seg_lengths := PackedFloat32Array()
	seg_lengths.resize(n)
	for i in range(n):
		seg_lengths[i] = points[i].distance_to(points[(i + 1) % n])
	var kappas := _compute_curvatures(points, seg_lengths)

	# --- 5. Two-pass speed profile ---
	var speeds := _compute_speed_profile(kappas, seg_lengths, perf)

	# --- Package ---
	var result := BakedRacingLine.new()
	result.bake_version = BakedRacingLine.CURRENT_BAKE_VERSION
	result.source_hash = source_hash
	result.track_id = track_id
	result.ship_id = ship_profile.ship_id
	result.track_length = length
	result.sample_count = n
	result.lateral_offsets = laterals
	result.target_speeds = speeds
	result.curvatures = kappas
	result.corridor_min = corridor_min
	result.corridor_max = corridor_max

	var elapsed := Time.get_ticks_msec() - t_start
	print("AIRacingLineBaker: baked %d samples in %d ms (ray miss: %.0f%%) -- %s" % [
		n, elapsed, last_ray_miss_ratio * 100.0, result.get_debug_info()
	])

	if use_cache:
		_save_cache(result)

	return result

# ============================================================================
# STEP 2: CORRIDOR MEASUREMENT
# ============================================================================

func _measure_corridor(spline_helper: TrackSplineHelper, centers: PackedVector3Array,
		rights: PackedVector3Array, ups: PackedVector3Array, world: World3D,
		out_min: PackedFloat32Array, out_max: PackedFloat32Array) -> void:
	var n := centers.size()
	out_min.resize(n)
	out_max.resize(n)

	var space: PhysicsDirectSpaceState3D = null
	if world:
		space = world.direct_space_state
	if not space:
		push_warning("AIRacingLineBaker: no physics space -- using fallback widths (%.1fm)" % fallback_half_width)
		for i in range(n):
			out_min[i] = -fallback_half_width
			out_max[i] = fallback_half_width
		last_ray_miss_ratio = 1.0
		return

	var misses := 0
	for i in range(n):
		var offset := float(i) / float(n)

		# Step 1: find the ACTUAL track surface near this spline sample by
		# dropping a ray along the banked down direction against the ground.
		var surface := _find_surface(space, centers[i], ups[i])
		if surface.is_empty():
			out_min[i] = -fallback_half_width
			out_max[i] = fallback_half_width
			misses += 2
			continue

		# Where does the real surface center sit, in spline-frame laterals?
		# (The physical geometry can be offset from the spline; anchoring the
		# corridor to the measured surface keeps the line inside real walls.)
		var surf_pos: Vector3 = surface.position
		var surf_lat: float = spline_helper.calculate_lateral_offset(surf_pos, offset, true)

		# Step 2: cast laterally from just above the real surface, in the
		# surface plane (right = tangent projected via the surface normal).
		var surf_normal: Vector3 = surface.normal
		# Recover forward: right = tangent x up, so tangent = up x right
		var tangent: Vector3 = ups[i].cross(rights[i]).normalized()
		var right_surf: Vector3 = tangent.cross(surf_normal).normalized()
		if right_surf.length_squared() < 0.5:
			right_surf = rights[i]

		var origin: Vector3 = surf_pos + surf_normal * ray_height
		var w_right := _cast_width(space, origin, right_surf)
		var w_left := _cast_width(space, origin, -right_surf)
		if w_right < 0.0:
			w_right = fallback_half_width
			misses += 1
		else:
			w_right = minf(w_right, max_usable_half_width)
		if w_left < 0.0:
			w_left = fallback_half_width
			misses += 1
		else:
			w_left = minf(w_left, max_usable_half_width)

		out_min[i] = surf_lat - w_left + line_margin
		out_max[i] = surf_lat + w_right - line_margin
		if out_max[i] - out_min[i] < 2.0:
			# Degenerate/narrow measurement; open a minimal corridor at center
			var mid: float = surf_lat + (w_right - w_left) * 0.5
			out_min[i] = mid - 1.0
			out_max[i] = mid + 1.0

	last_ray_miss_ratio = float(misses) / float(n * 2)
	if last_ray_miss_ratio > 0.5:
		push_warning("AIRacingLineBaker: %.0f%% of wall rays missed -- check wall collision layer (expected layer 4). Using fallback widths where needed." % (last_ray_miss_ratio * 100.0))

## Locate the actual track surface near a spline sample. Returns the ray hit
## dictionary ({} on failure). Casts along the banked down direction so it
## works on steeply banked sections too.
func _find_surface(space: PhysicsDirectSpaceState3D, center: Vector3, up: Vector3) -> Dictionary:
	var from: Vector3 = center + up * surface_probe_height
	var to: Vector3 = from - up * surface_probe_length
	var query := PhysicsRayQueryParameters3D.create(from, to, GROUND_COLLISION_MASK)
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return {}
	if center.distance_to(hit.position) > surface_max_deviation:
		return {}  # probably a crossover / different track section
	return hit

## Returns usable half-width in `direction`, or -1.0 on ray miss.
func _cast_width(space: PhysicsDirectSpaceState3D, origin: Vector3, direction: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + direction * ray_length, WALL_COLLISION_MASK
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return -1.0
	var dist: float = origin.distance_to(hit.position)
	return maxf(dist - ship_clearance, 1.0)

# ============================================================================
# STEP 3: ELASTIC-BAND RELAXATION
# ============================================================================

## Iteratively pulls each sample toward the midpoint of its neighbors
## (projected onto the lateral axis), clamped to the corridor. Converges to
## the straightest path that fits inside the walls -- a good approximation of
## the minimum-curvature racing line, which is what this ship physics rewards
## (corner speed limit scales with 1/curvature).
func _relax_racing_line(centers: PackedVector3Array, rights: PackedVector3Array,
		corridor_min: PackedFloat32Array, corridor_max: PackedFloat32Array) -> PackedFloat32Array:
	var n := centers.size()
	var w := PackedFloat32Array()
	w.resize(n)
	for i in range(n):
		# Start at the measured corridor center, not the spline center
		w[i] = (corridor_min[i] + corridor_max[i]) * 0.5

	var points := PackedVector3Array()
	points.resize(n)
	for i in range(n):
		points[i] = centers[i] + rights[i] * w[i]

	for _iter in range(relaxation_iterations):
		var max_delta := 0.0
		for i in range(n):
			var prev := points[(i - 1 + n) % n]
			var next := points[(i + 1) % n]
			var mid := (prev + next) * 0.5
			var w_target := (mid - centers[i]).dot(rights[i])
			var new_w: float = w[i] + relaxation_alpha * (w_target - w[i])
			new_w = clampf(new_w, corridor_min[i], corridor_max[i])
			max_delta = maxf(max_delta, absf(new_w - w[i]))
			w[i] = new_w
			points[i] = centers[i] + rights[i] * new_w
		if max_delta < convergence_epsilon:
			break

	return w

# ============================================================================
# STEP 4: CURVATURE
# ============================================================================

func _compute_curvatures(points: PackedVector3Array, seg_lengths: PackedFloat32Array) -> PackedFloat32Array:
	var n := points.size()
	var kappas := PackedFloat32Array()
	kappas.resize(n)

	for i in range(n):
		var p_prev := points[(i - 1 + n) % n]
		var p_next := points[(i + 1) % n]
		var a := points[i] - p_prev
		var b := p_next - points[i]
		if a.length_squared() < 0.0001 or b.length_squared() < 0.0001:
			kappas[i] = 0.0
			continue
		var angle := a.angle_to(b)
		var mean_seg: float = (seg_lengths[(i - 1 + n) % n] + seg_lengths[i]) * 0.5
		kappas[i] = angle / maxf(mean_seg, 0.1)

	# One smoothing pass (5-tap box) to remove sampling spikes. More passes
	# smear real corner peaks and overestimate corner speeds.
	for _pass in range(1):
		var smoothed := PackedFloat32Array()
		smoothed.resize(n)
		for i in range(n):
			var acc := 0.0
			for k in range(-2, 3):
				acc += kappas[(i + k + n) % n]
			smoothed[i] = acc / 5.0
		kappas = smoothed

	return kappas

# ============================================================================
# STEP 5: SPEED PROFILE
# ============================================================================

func _compute_speed_profile(kappas: PackedFloat32Array, seg_lengths: PackedFloat32Array,
		perf: ShipPerformanceModel) -> PackedFloat32Array:
	var n := kappas.size()
	var v := PackedFloat32Array()
	v.resize(n)

	# Corner speed limits from the ship's real steering/grip physics.
	for i in range(n):
		v[i] = perf.corner_speed(kappas[i], respect_profile_max_speed)

	# Backward pass: entering sample i, we must be able to brake down to
	# v[i+1] over the segment. Two wraps handle the closed-loop seam.
	for _wrap in range(2):
		for i in range(n - 1, -1, -1):
			var nxt := (i + 1) % n
			v[i] = minf(v[i], perf.max_entry_speed(v[nxt], seg_lengths[i]))

	# Forward pass: we can't exceed what full throttle achieves from the
	# previous sample. Two wraps for the seam.
	for _wrap in range(2):
		for i in range(n):
			var nxt := (i + 1) % n
			v[nxt] = minf(v[nxt], perf.speed_after_full_throttle(v[i], seg_lengths[i]))

	return v

# ============================================================================
# CACHING
# ============================================================================

func _compute_source_hash(spline_helper: TrackSplineHelper, profile: ShipProfile) -> int:
	var parts: Array = []
	var curve := spline_helper.curve
	if curve:
		parts.append(curve.point_count)
		for i in range(curve.point_count):
			parts.append(curve.get_point_position(i))
			parts.append(curve.get_point_in(i))
			parts.append(curve.get_point_out(i))
			parts.append(curve.get_point_tilt(i))
	parts.append(profile.max_speed)
	parts.append(profile.thrust_power)
	parts.append(profile.drag_coefficient)
	parts.append(profile.steer_speed)
	parts.append(profile.grip)
	parts.append(profile.airbrake_drag)
	parts.append(profile.airbrake_turn_rate)
	parts.append(profile.dual_airbrake_drag)
	parts.append(profile.lateral_scrub)
	parts.append(profile.airbrake_lateral_scrub)
	parts.append(sample_spacing_target)
	parts.append(ship_clearance)
	parts.append(fallback_half_width)
	parts.append(max_usable_half_width)
	parts.append(ray_height)
	parts.append(cornering_confidence)
	parts.append(planned_brake_application)
	parts.append(line_margin)
	parts.append(respect_profile_max_speed)
	parts.append(BakedRacingLine.CURRENT_BAKE_VERSION)
	return parts.hash()

func _cache_path(track_id: String, ship_id: String, source_hash: int) -> String:
	var tid := track_id if not track_id.is_empty() else "unknown_track"
	var sid := ship_id if not ship_id.is_empty() else "unknown_ship"
	return "%s%s__%s__%d.tres" % [CACHE_DIR, tid.validate_filename(), sid.validate_filename(), source_hash]

func _try_load_cache(track_id: String, ship_id: String, source_hash: int) -> BakedRacingLine:
	var path := _cache_path(track_id, ship_id, source_hash)
	if not ResourceLoader.exists(path):
		return null
	var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as BakedRacingLine
	if res and res.is_usable() and res.source_hash == source_hash \
			and res.bake_version == BakedRacingLine.CURRENT_BAKE_VERSION:
		return res
	return null

func _save_cache(line: BakedRacingLine) -> void:
	if not DirAccess.dir_exists_absolute(CACHE_DIR):
		DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var path := _cache_path(line.track_id, line.ship_id, line.source_hash)
	var err := ResourceSaver.save(line, path)
	if err != OK:
		push_warning("AIRacingLineBaker: failed to cache baked line (error %d)" % err)
