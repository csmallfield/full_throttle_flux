extends RefCounted
class_name AILineFollower

## AI Line Follower
## Responsible for answering: "Where should I be on the track, and how fast?"
##
## v3 Changes (major rework):
## - BAKED RACING LINE support: when a BakedRacingLine is provided, both the
##   steering target (optimized lateral offsets) and the speed target (two-pass
##   speed profile) come from it. The profile is DISTANCE-AWARE by
##   construction: braking points are encoded in the speeds themselves.
##   Source priority: recorded laps > baked line > geometric fallback
##   (set prefer_baked_over_recorded to flip the first two).
## - Geometric fallback is now distance-aware too: when a ShipPerformanceModel
##   is available, the target speed is max_entry_speed(corner_speed, distance)
##   instead of collapsing the moment a corner enters the 120m scan window.
## - Track width fixed: the old default (21.0m) targeted apexes INSIDE the
##   walls (inner faces are ~16.2m out on test_circuit_2, ship needs ~3m).
##   Baked lines use per-sample raycast-measured widths; the geometric
##   fallback default is now conservative.
## - Honest skill: the flat 0.70-1.0 speed multiplier is gone. Skill applies
##   a margin (novice brakes earlier / carries less speed) but skill 1.0 runs
##   the full computed profile. Same ship limits at every level.
## - Apex phase timing retuned (geometric fallback): the old constants began
##   the apex cut 70m before the corner (early apex -> runs wide at exit).

# ============================================================================
# CONFIGURATION - STEERING LOOKAHEAD
# ============================================================================

## Base steering lookahead at low speeds (meters)
var steer_lookahead_min: float = 25.0

## Base steering lookahead at high speeds (meters)
var steer_lookahead_max: float = 70.0

## Minimum steering lookahead in tight corners (meters)
var steer_lookahead_corner_min: float = 15.0

# ============================================================================
# CONFIGURATION - SPEED/CORNER LOOKAHEAD (geometric fallback + debug)
# ============================================================================

## How far ahead to scan for upcoming corners (meters)
var speed_lookahead_distance: float = 120.0

## Number of points to sample when scanning for corners
var speed_lookahead_samples: int = 10

# ============================================================================
# CONFIGURATION - RACING LINE / APEX SEEKING (geometric fallback)
# ============================================================================

## How aggressively to cut corners (0 = centerline, 1 = full apex seeking)
var apex_seeking_strength: float = 1.0

## Minimum curvature to trigger lateral offset
var lateral_offset_curvature_threshold: float = 0.001

## Track half-width used by the GEOMETRIC FALLBACK ONLY (baked lines carry
## per-sample raycast-measured widths). Conservative default: on
## test_circuit_2 wall inner faces are ~16.2m from center and the ship needs
## ~3m clearance. The old 21.0 sent the AI into the walls every corner.
var estimated_track_half_width: float = 12.0

## Extra margin from the (estimated) wall for the geometric fallback.
var wall_margin: float = 0.0

# ============================================================================
# CONFIGURATION - CURVATURE THRESHOLDS (pseudo-curvature units, 1 - dot)
# ============================================================================

## Curvature threshold for "tight corner"
var tight_corner_threshold: float = 0.03

## Curvature threshold for "very tight corner" (hairpin-like)
var very_tight_corner_threshold: float = 0.12

## How much to reduce lookahead in tight corners (multiplier)
var corner_lookahead_reduction: float = 0.5

## Sample distance used for pseudo-curvature probes (meters). Needed to
## convert pseudo-curvature (1 - dot) into true curvature (rad/m).
var curvature_sample_distance: float = 15.0

# ============================================================================
# CONFIGURATION - CORNER PHASE TIMING (geometric fallback)
# ============================================================================

## Distance to start the racing line approach (meters)
var phase_distance: float = 60.0

## Entry phase fraction (0..this = positioning to outside). Retuned: the old
## 0.10 meant the apex cut began 70m out (early apex).
var entry_phase_end: float = 0.40

## Apex phase fraction (entry_end..this = cutting to inside)
var apex_phase_end: float = 0.80

# ============================================================================
# CONFIGURATION - SPEED TARGET / SKILL
# ============================================================================

## Skill level of this AI (0.0 = safe, 1.0 = fast)
var skill_level: float = 1.0

## Speed margin at skill 0 (fraction of computed target). Skill 1.0 = 1.0.
var skill_speed_margin_min: float = 0.85

## Line aggression at skill 0 (fraction of baked lateral offset).
var skill_line_factor_min: float = 0.90

## Anticipation TIME over which the minimum baked profile speed is taken
## (window in meters = time * current speed). Covers the control smoothing
## lag so braking commands develop before the braking zone arrives. Novices
## look further ahead = slow earlier.
var anticipation_time_novice: float = 0.8
var anticipation_time_expert: float = 0.3

## Steering pursuit lookahead range in BAKED mode (meters). The baked line is
## already smooth and optimal; long pursuit lookaheads cut inside it (classic
## pure-pursuit corner-cutting), pointing the nose at inside walls.
var baked_steer_lookahead_min: float = 18.0
var baked_steer_lookahead_max: float = 42.0

## Crosstrack feedback gain (baked mode). Pure pursuit carries a steady-state
## error toward the inside of corners (~kappa * L^2 / 2); this P-term on the
## current lateral error shifts the aim point to cancel it. 0 disables.
var crosstrack_gain: float = 0.8

## Clamp on the crosstrack correction (meters) so a bad spline-offset match
## (self-crossing track sections) cannot inject huge steering.
var crosstrack_max_correction: float = 8.0

## If true, prefer the baked line even when recorded laps exist.
var prefer_baked_over_recorded: bool = false

## Cap geometric-fallback cruise speed at profile.max_speed (see
## ShipPerformanceModel.equilibrium_speed note).
var respect_profile_max_speed: bool = true

# ============================================================================
# STATE
# ============================================================================

var spline_helper: TrackSplineHelper
var track_ai_data: TrackAIData  # May be null if no recorded data
var baked_line: BakedRacingLine  # May be null if not baked
var perf_model: ShipPerformanceModel  # May be null (legacy heuristics used)

var current_spline_offset: float = 0.0
var current_world_position: Vector3 = Vector3.ZERO
var has_recorded_data: bool = false

# Cached analysis results (updated each frame)
var cached_max_upcoming_curvature: float = 0.0
var cached_max_curvature_signed: float = 0.0
var cached_corner_distance: float = 0.0
var cached_immediate_curvature: float = 0.0
var cached_immediate_curvature_signed: float = 0.0

# S-curve detection (kept for debug/telemetry)
var cached_is_s_curve: bool = false
var cached_s_curve_first_direction: float = 0.0
var cached_s_curve_transition_distance: float = 0.0

# Racing line (geometric fallback)
var cached_target_lateral_offset: float = 0.0
var cached_corner_phase: float = 0.0

# Debug: apex world position
var cached_apex_world_position: Vector3 = Vector3.ZERO
var cached_apex_spline_offset: float = 0.0

# ============================================================================
# INITIALIZATION
# ============================================================================

func initialize(p_spline_helper: TrackSplineHelper, p_track_ai_data: TrackAIData = null,
		p_baked_line: BakedRacingLine = null, p_perf_model: ShipPerformanceModel = null) -> void:
	spline_helper = p_spline_helper
	track_ai_data = p_track_ai_data
	baked_line = p_baked_line
	perf_model = p_perf_model
	has_recorded_data = track_ai_data != null and track_ai_data.has_recorded_data()

func set_skill(skill: float) -> void:
	skill_level = clamp(skill, 0.0, 1.0)

func has_baked_line() -> bool:
	return baked_line != null and baked_line.is_usable()

# ============================================================================
# POSITION TRACKING
# ============================================================================

func update_position(world_position: Vector3) -> void:
	"""Call each frame with the ship's current world position."""
	current_world_position = world_position

	if spline_helper and spline_helper.is_valid:
		current_spline_offset = spline_helper.world_to_spline_offset(world_position)
		_update_curvature_analysis()
		_update_racing_line()

func _update_curvature_analysis() -> void:
	"""Scan ahead and cache curvature information including S-curve detection."""
	cached_max_upcoming_curvature = 0.0
	cached_max_curvature_signed = 0.0
	cached_corner_distance = speed_lookahead_distance
	cached_immediate_curvature = spline_helper.get_curvature_at_offset(current_spline_offset, curvature_sample_distance)
	cached_immediate_curvature_signed = _get_signed_curvature(current_spline_offset, curvature_sample_distance)

	# Reset S-curve detection
	cached_is_s_curve = false
	cached_s_curve_first_direction = 0.0
	cached_s_curve_transition_distance = 0.0

	# Sample multiple points ahead
	var sample_spacing: float = speed_lookahead_distance / float(speed_lookahead_samples)
	var prev_sign: float = sign(cached_immediate_curvature_signed) if abs(cached_immediate_curvature_signed) > 0.1 else 0.0
	var first_significant_sign: float = prev_sign

	for i in range(speed_lookahead_samples):
		var distance: float = sample_spacing * float(i + 1)
		var sample_offset: float = spline_helper.get_lookahead_offset(current_spline_offset, distance)
		var curvature: float = spline_helper.get_curvature_at_offset(sample_offset, curvature_sample_distance)
		var signed_curv: float = _get_signed_curvature(sample_offset, curvature_sample_distance)

		# Track maximum curvature magnitude AND its sign
		if curvature > cached_max_upcoming_curvature:
			cached_max_upcoming_curvature = curvature
			cached_max_curvature_signed = signed_curv
			cached_corner_distance = distance

		# S-curve detection: look for sign change in curvature
		var current_sign: float = sign(signed_curv) if abs(signed_curv) > 0.15 else 0.0

		if first_significant_sign == 0.0 and current_sign != 0.0:
			first_significant_sign = current_sign

		if prev_sign != 0.0 and current_sign != 0.0 and prev_sign != current_sign:
			if not cached_is_s_curve:
				cached_is_s_curve = true
				cached_s_curve_first_direction = prev_sign
				cached_s_curve_transition_distance = distance

		if current_sign != 0.0:
			prev_sign = current_sign

func _get_signed_curvature(offset: float, sample_distance: float) -> float:
	"""
	Get curvature with sign indicating direction.
	Positive = turning left, Negative = turning right.
	"""
	if not spline_helper or not spline_helper.is_valid:
		return 0.0

	var delta: float = spline_helper.distance_to_offset(sample_distance)

	var pos_current: Vector3 = spline_helper.spline_offset_to_world(offset)
	var pos_ahead: Vector3 = spline_helper.spline_offset_to_world(offset + delta)

	var dir_current: Vector3 = (pos_ahead - pos_current)
	dir_current.y = 0
	if dir_current.length_squared() < 0.001:
		return 0.0
	dir_current = dir_current.normalized()

	var pos_further: Vector3 = spline_helper.spline_offset_to_world(offset + delta * 2.0)
	var dir_ahead: Vector3 = (pos_further - pos_ahead)
	dir_ahead.y = 0
	if dir_ahead.length_squared() < 0.001:
		return 0.0
	dir_ahead = dir_ahead.normalized()

	var cross: Vector3 = dir_current.cross(dir_ahead)
	var dot: float = dir_current.dot(dir_ahead)

	var curvature_magnitude: float = 1.0 - dot
	var turn_direction: float = sign(cross.y)

	return curvature_magnitude * turn_direction

# ============================================================================
# RACING LINE (geometric fallback only -- baked lines carry their own)
# ============================================================================

func _update_racing_line() -> void:
	"""
	Calculate optimal lateral offset for the geometric fallback racing line.
	When a baked line is active this only feeds debug visualization.
	"""
	cached_target_lateral_offset = 0.0
	cached_corner_phase = 0.0

	_update_apex_debug_position()

	if has_baked_line():
		# Baked line provides laterals directly; cache for debug display.
		cached_target_lateral_offset = baked_line.get_lateral_at(current_spline_offset)
		return

	if cached_max_upcoming_curvature < lateral_offset_curvature_threshold:
		return

	var curvature_normalized: float = clamp(
		(cached_max_upcoming_curvature - lateral_offset_curvature_threshold) /
		(very_tight_corner_threshold - lateral_offset_curvature_threshold),
		0.0, 1.0
	)

	var apex_depth: float = lerpf(0.60, 0.95, curvature_normalized)
	var usable_half_width: float = estimated_track_half_width - wall_margin
	var apex_offset: float = usable_half_width * apex_depth

	var entry_depth: float = lerpf(0.50, 0.75, curvature_normalized)
	var entry_offset: float = usable_half_width * entry_depth

	cached_apex_spline_offset = spline_helper.get_lookahead_offset(current_spline_offset, cached_corner_distance)

	var base_offset: float = 0.0

	if cached_is_s_curve:
		# === S-CURVE LOGIC ===
		var first_turn_right: bool = cached_s_curve_first_direction < 0
		var transition_progress: float = 0.0

		if cached_s_curve_transition_distance > 0:
			transition_progress = clamp(cached_corner_distance / cached_s_curve_transition_distance, 0.0, 2.0)

		cached_corner_phase = transition_progress / 2.0

		if transition_progress < 0.5:
			var phase: float = transition_progress / 0.5
			if first_turn_right:
				base_offset = lerpf(-entry_offset, -entry_offset * 0.2, phase)
			else:
				base_offset = lerpf(entry_offset, entry_offset * 0.2, phase)
		elif transition_progress < 1.0:
			var phase: float = (transition_progress - 0.5) / 0.5
			if first_turn_right:
				base_offset = lerpf(-entry_offset * 0.2, apex_offset * 0.8, phase)
			else:
				base_offset = lerpf(entry_offset * 0.2, -apex_offset * 0.8, phase)
		elif transition_progress < 1.5:
			var phase: float = (transition_progress - 1.0) / 0.5
			if first_turn_right:
				base_offset = lerpf(apex_offset * 0.8, -apex_offset * 0.6, phase)
			else:
				base_offset = lerpf(-apex_offset * 0.8, apex_offset * 0.6, phase)
		else:
			var phase: float = clamp((transition_progress - 1.5) / 0.5, 0.0, 1.0)
			var second_turn_right: bool = not first_turn_right
			if second_turn_right:
				base_offset = lerpf(apex_offset * 0.6, apex_offset * 0.3, phase)
			else:
				base_offset = lerpf(-apex_offset * 0.6, -apex_offset * 0.3, phase)
	else:
		# === SINGLE CORNER LOGIC (outside-inside-outside, LATE apex) ===
		var turn_right: bool
		if abs(cached_max_curvature_signed) > 0.005:
			turn_right = cached_max_curvature_signed < 0
		elif abs(cached_immediate_curvature_signed) > 0.005:
			turn_right = cached_immediate_curvature_signed < 0
		else:
			return

		var corner_phase: float = 0.0
		if cached_corner_distance < phase_distance:
			corner_phase = 1.0 - (cached_corner_distance / phase_distance)
		cached_corner_phase = corner_phase

		if corner_phase < entry_phase_end:
			# ENTRY: hold the outside of the turn
			var phase: float = corner_phase / entry_phase_end
			if turn_right:
				base_offset = lerpf(-entry_offset * 0.9, -entry_offset * 0.7, phase)
			else:
				base_offset = lerpf(entry_offset * 0.9, entry_offset * 0.7, phase)
		elif corner_phase < apex_phase_end:
			# APEX: cut to the inside (late)
			var phase: float = (corner_phase - entry_phase_end) / (apex_phase_end - entry_phase_end)
			if turn_right:
				base_offset = lerpf(-entry_offset * 0.7, apex_offset, phase)
			else:
				base_offset = lerpf(entry_offset * 0.7, -apex_offset, phase)
		else:
			# EXIT: drift back out
			var phase: float = (corner_phase - apex_phase_end) / (1.0 - apex_phase_end)
			if turn_right:
				base_offset = lerpf(apex_offset, entry_offset * 0.3, phase)
			else:
				base_offset = lerpf(-apex_offset, -entry_offset * 0.3, phase)

	# === APPLY MODIFIERS ===
	var skill_modifier: float = lerpf(skill_line_factor_min, 1.0, skill_level)
	cached_target_lateral_offset = base_offset * apex_seeking_strength * skill_modifier

	var max_allowed_offset: float = estimated_track_half_width - wall_margin
	cached_target_lateral_offset = clamp(cached_target_lateral_offset, -max_allowed_offset, max_allowed_offset)

func get_current_spline_offset() -> float:
	return current_spline_offset

func _update_apex_debug_position() -> void:
	"""Calculate apex position for debug visualization."""
	if not spline_helper or not spline_helper.is_valid:
		cached_apex_world_position = Vector3.ZERO
		return

	cached_apex_spline_offset = spline_helper.get_lookahead_offset(current_spline_offset, cached_corner_distance)

	if has_baked_line():
		cached_apex_world_position = spline_helper.spline_offset_to_world_with_lateral(
			cached_apex_spline_offset, baked_line.get_lateral_at(cached_apex_spline_offset), true
		)
		return

	var usable_width: float = estimated_track_half_width - wall_margin

	if cached_max_upcoming_curvature > lateral_offset_curvature_threshold:
		var curvature_normalized: float = clamp(
			(cached_max_upcoming_curvature - lateral_offset_curvature_threshold) /
			(very_tight_corner_threshold - lateral_offset_curvature_threshold),
			0.0, 1.0
		)
		var apex_depth: float = lerpf(0.60, 0.95, curvature_normalized)
		var apex_offset: float = usable_width * apex_depth

		var turn_right: bool
		if cached_is_s_curve and abs(cached_s_curve_first_direction) > 0.1:
			turn_right = cached_s_curve_first_direction < 0
		else:
			turn_right = cached_max_curvature_signed < 0

		var apex_lateral: float = apex_offset if turn_right else -apex_offset
		cached_apex_world_position = spline_helper.spline_offset_to_world_with_lateral(
			cached_apex_spline_offset, apex_lateral
		)
	else:
		cached_apex_world_position = spline_helper.spline_offset_to_world(cached_apex_spline_offset)

# ============================================================================
# TARGET QUERIES - MAIN INTERFACE
# ============================================================================

func get_target_position(ship_speed: float, max_speed: float) -> Dictionary:
	"""
	Get the target position and (distance-aware) target speed.
	Source priority: recorded laps > baked line > geometric fallback.
	"""
	var speed_ratio: float = ship_speed / max_speed if max_speed > 0 else 0.0

	var base_lookahead: float = lerpf(steer_lookahead_min, steer_lookahead_max, speed_ratio)
	var actual_lookahead: float = _apply_curvature_lookahead_adjustment(base_lookahead)

	var skill_lookahead_modifier: float = lerpf(0.8, 1.1, skill_level)
	actual_lookahead *= skill_lookahead_modifier

	var use_recorded: bool = has_recorded_data
	if prefer_baked_over_recorded and has_baked_line():
		use_recorded = false

	if use_recorded:
		return _get_recorded_target(actual_lookahead, max_speed)
	elif has_baked_line():
		# Tighter pursuit lookahead: the baked line is already the smooth
		# optimal path, so we track it closely instead of cutting across it
		var baked_lookahead: float = lerpf(baked_steer_lookahead_min, baked_steer_lookahead_max, speed_ratio)
		baked_lookahead = _apply_curvature_lookahead_adjustment(baked_lookahead)
		baked_lookahead *= skill_lookahead_modifier
		return _get_baked_target(baked_lookahead, ship_speed, max_speed)
	else:
		return _get_centerline_target(actual_lookahead, max_speed, speed_ratio)

func _apply_curvature_lookahead_adjustment(base_lookahead: float) -> float:
	"""Reduce lookahead when approaching tight corners."""
	if cached_max_upcoming_curvature < tight_corner_threshold:
		return base_lookahead

	var tightness: float = (cached_max_upcoming_curvature - tight_corner_threshold) / (very_tight_corner_threshold - tight_corner_threshold)
	tightness = clamp(tightness, 0.0, 1.0)

	var proximity_factor: float = 1.0 - clamp(cached_corner_distance / speed_lookahead_distance, 0.0, 1.0)
	var reduction: float = tightness * proximity_factor * (1.0 - corner_lookahead_reduction)
	var adjusted: float = base_lookahead * (1.0 - reduction)

	return max(adjusted, steer_lookahead_corner_min)

# ============================================================================
# TARGET SOURCE: BAKED RACING LINE
# ============================================================================

func _get_baked_target(lookahead: float, ship_speed: float, _max_speed: float) -> Dictionary:
	"""
	Target from the baked racing line + speed profile.
	Position: optimized lateral offset at the lookahead point.
	Speed: minimum of the profile over a short anticipation window from the
	CURRENT position -- the profile already encodes braking distances, so this
	is a complete, distance-aware instruction.
	"""
	var target_offset: float = spline_helper.get_lookahead_offset(current_spline_offset, lookahead)

	var line_factor: float = lerpf(skill_line_factor_min, 1.0, skill_level)
	var lateral: float = baked_line.get_lateral_at(target_offset) * line_factor

	# Crosstrack feedback: cancel pure-pursuit corner-cutting by shifting the
	# aim point opposite the current lateral tracking error.
	if crosstrack_gain > 0.0:
		var desired_now: float = baked_line.get_lateral_at(current_spline_offset) * line_factor
		var actual_now: float = spline_helper.calculate_lateral_offset(
			current_world_position, current_spline_offset, true)
		var correction: float = clampf((desired_now - actual_now) * crosstrack_gain,
			-crosstrack_max_correction, crosstrack_max_correction)
		lateral += correction

	# Tilted frame: baked laterals live in the banked track plane
	var world_pos: Vector3 = spline_helper.spline_offset_to_world_with_lateral(target_offset, lateral, true)

	var anticipation_t: float = lerpf(anticipation_time_novice, anticipation_time_expert, skill_level)
	var anticipation: float = clampf(ship_speed * anticipation_t, 10.0, 90.0)
	var raw_speed: float = baked_line.get_min_speed_ahead(current_spline_offset, anticipation)
	var speed_margin: float = lerpf(skill_speed_margin_min, 1.0, skill_level)
	var target_speed: float = raw_speed * speed_margin

	var tangent: Vector3 = spline_helper.get_tangent_at_offset(target_offset)

	return {
		"world_position": world_pos,
		"suggested_speed": target_speed,
		"lateral_offset": lateral,
		"heading": tangent,
		"spline_offset": target_offset,
		"from_recorded_data": false,
		"from_baked_line": true,
		"lookahead_used": lookahead,
		"max_upcoming_curvature": cached_max_upcoming_curvature,
		"corner_distance": cached_corner_distance,
		"immediate_curvature": cached_immediate_curvature,
		"is_s_curve": cached_is_s_curve,
		"corner_phase": cached_corner_phase,
		"hint_throttle": 1.0,
		"hint_brake": 0.0,
		"hint_airbrake_left": 0.0,
		"hint_airbrake_right": 0.0
	}

# ============================================================================
# TARGET SOURCE: RECORDED LAPS
# ============================================================================

func _get_recorded_target(lookahead: float, max_speed: float) -> Dictionary:
	"""Get target from recorded racing line data.

	Two sample points: LOOKAHEAD for position/speed (where to steer),
	CURRENT for control hints (what inputs to use now).
	"""
	var target_offset: float = spline_helper.get_lookahead_offset(current_spline_offset, lookahead)

	var lookahead_sample: AIRacingSample = track_ai_data.get_interpolated_sample(target_offset, skill_level)
	var current_sample: AIRacingSample = track_ai_data.get_interpolated_sample(current_spline_offset, skill_level)

	if lookahead_sample == null:
		push_warning("AILineFollower: recorded lookahead sample is NULL - falling back")
		if has_baked_line():
			return _get_baked_target(lookahead, max_speed * 0.5, max_speed)
		return _get_centerline_target(lookahead, max_speed, 0.5)

	var world_pos: Vector3 = spline_helper.spline_offset_to_world_with_lateral(
		target_offset,
		lookahead_sample.lateral_offset
	)

	var hint_throttle: float = current_sample.throttle if current_sample else lookahead_sample.throttle
	var hint_brake: float = current_sample.brake if current_sample else lookahead_sample.brake
	var hint_airbrake_left: float = current_sample.airbrake_left if current_sample else lookahead_sample.airbrake_left
	var hint_airbrake_right: float = current_sample.airbrake_right if current_sample else lookahead_sample.airbrake_right

	return {
		"world_position": world_pos,
		"suggested_speed": lookahead_sample.speed,
		"lateral_offset": lookahead_sample.lateral_offset,
		"heading": lookahead_sample.heading,
		"spline_offset": target_offset,
		"from_recorded_data": true,
		"from_baked_line": false,
		"lookahead_used": lookahead,
		"max_upcoming_curvature": cached_max_upcoming_curvature,
		"corner_distance": cached_corner_distance,
		"immediate_curvature": cached_immediate_curvature,
		"is_s_curve": cached_is_s_curve,
		"corner_phase": cached_corner_phase,
		"hint_throttle": hint_throttle,
		"hint_brake": hint_brake,
		"hint_airbrake_left": hint_airbrake_left,
		"hint_airbrake_right": hint_airbrake_right
	}

# ============================================================================
# TARGET SOURCE: GEOMETRIC FALLBACK
# ============================================================================

func _get_centerline_target(lookahead: float, max_speed: float, _speed_ratio: float) -> Dictionary:
	"""Geometric fallback: racing line offset + distance-aware speed target."""
	var target_offset: float = spline_helper.get_lookahead_offset(current_spline_offset, lookahead)

	var centerline_pos: Vector3 = spline_helper.spline_offset_to_world(target_offset)

	var world_pos: Vector3
	if abs(cached_target_lateral_offset) > 0.1:
		world_pos = spline_helper.spline_offset_to_world_with_lateral(target_offset, cached_target_lateral_offset)
	else:
		world_pos = centerline_pos

	var tangent: Vector3 = spline_helper.get_tangent_at_offset(target_offset)
	var suggested_speed: float = _calculate_target_speed(max_speed)

	# Honest skill margin (replaces the old flat 0.70-1.0 governor)
	suggested_speed *= lerpf(skill_speed_margin_min, 1.0, skill_level)

	return {
		"world_position": world_pos,
		"suggested_speed": suggested_speed,
		"lateral_offset": cached_target_lateral_offset,
		"heading": tangent,
		"spline_offset": target_offset,
		"from_recorded_data": false,
		"from_baked_line": false,
		"lookahead_used": lookahead,
		"max_upcoming_curvature": cached_max_upcoming_curvature,
		"corner_distance": cached_corner_distance,
		"immediate_curvature": cached_immediate_curvature,
		"is_s_curve": cached_is_s_curve,
		"corner_phase": cached_corner_phase,
		"hint_throttle": 1.0,
		"hint_brake": 0.0,
		"hint_airbrake_left": 0.0,
		"hint_airbrake_right": 0.0
	}

func _calculate_target_speed(max_speed: float) -> float:
	"""
	Distance-aware target speed for the geometric fallback.

	With a ShipPerformanceModel: the corner ahead imposes a speed limit AT the
	corner; between here and there we may carry anything we can brake off in
	time -- v_now = max_entry_speed(v_corner, distance). This is what fixes
	the old behavior of lifting the moment a corner entered the 120m window.

	Without a perf model: legacy curvature heuristic (kept as last resort).
	"""
	if perf_model:
		var cruise: float = perf_model.top_speed(respect_profile_max_speed)

		# Immediate corner limit (we are IN it -- no braking distance left)
		var v_limit: float = cruise
		if cached_immediate_curvature > 0.003:
			v_limit = perf_model.corner_speed(
				_pseudo_to_true_curvature(cached_immediate_curvature), respect_profile_max_speed)

		# Upcoming corner limit, relaxed by the distance we have to brake in
		if cached_max_upcoming_curvature > 0.003:
			var v_corner: float = perf_model.corner_speed(
				_pseudo_to_true_curvature(cached_max_upcoming_curvature), respect_profile_max_speed)
			var brake_room: float = maxf(cached_corner_distance - 5.0, 0.0)
			v_limit = minf(v_limit, perf_model.max_entry_speed(v_corner, brake_room))

		return clampf(minf(cruise, v_limit), 5.0, cruise)

	# --- Legacy heuristic (no perf model) ---
	var curvature: float = max(cached_max_upcoming_curvature, cached_immediate_curvature)
	var min_speed_ratio: float = 0.35
	var speed_reduction: float = clamp(curvature * 1.4, 0.0, 1.0 - min_speed_ratio)
	var safe_speed: float = max_speed * (1.0 - speed_reduction)
	return clamp(safe_speed, max_speed * min_speed_ratio, max_speed)

## Convert pseudo-curvature (1 - dot over curvature_sample_distance) into
## true curvature (rad/m): theta = acos(1 - c), kappa = theta / sample_dist.
func _pseudo_to_true_curvature(pseudo: float) -> float:
	var theta: float = acos(clampf(1.0 - pseudo, -1.0, 1.0))
	return theta / maxf(curvature_sample_distance, 0.1)

# ============================================================================
# DEBUG DATA FOR VISUALIZATION
# ============================================================================

func get_racing_line_preview(num_points: int = 10, preview_distance: float = 100.0) -> Array[Dictionary]:
	"""
	Get a preview of the racing line ahead for debug visualization.
	Shows the baked line when active, otherwise the geometric estimate.
	"""
	var preview: Array[Dictionary] = []

	if not spline_helper or not spline_helper.is_valid:
		return preview

	var spacing: float = preview_distance / float(num_points)

	for i in range(num_points):
		var distance: float = spacing * float(i + 1)
		var offset: float = spline_helper.get_lookahead_offset(current_spline_offset, distance)

		var lateral: float = 0.0
		var curv: float = spline_helper.get_curvature_at_offset(offset, curvature_sample_distance)

		var use_tilt := false
		if has_baked_line():
			lateral = baked_line.get_lateral_at(offset)
			use_tilt = true
		elif curv > lateral_offset_curvature_threshold:
			var signed_curv: float = _get_signed_curvature(offset, curvature_sample_distance)
			var usable_width: float = estimated_track_half_width - wall_margin
			var depth: float = lerpf(0.5, 0.9, clamp(curv / very_tight_corner_threshold, 0.0, 1.0))
			lateral = usable_width * depth * -sign(signed_curv)

		var world_pos: Vector3 = spline_helper.spline_offset_to_world_with_lateral(offset, lateral, use_tilt)

		preview.append({
			"world_position": world_pos,
			"lateral_offset": lateral,
			"curvature": curv,
			"is_apex": abs(offset - cached_apex_spline_offset) < 0.02
		})

	return preview

func get_apex_world_position() -> Vector3:
	"""Get the calculated apex position for debug visualization."""
	return cached_apex_world_position

func get_centerline_position_at_distance(distance: float) -> Vector3:
	"""Get centerline position at a given distance ahead."""
	if not spline_helper or not spline_helper.is_valid:
		return Vector3.ZERO
	var offset: float = spline_helper.get_lookahead_offset(current_spline_offset, distance)
	return spline_helper.spline_offset_to_world(offset)

# ============================================================================
# CURRENT SAMPLE (for control hints)
# ============================================================================

func get_current_sample() -> AIRacingSample:
	"""Get the sample at the current position."""
	if not has_recorded_data:
		return null
	return track_ai_data.get_interpolated_sample(current_spline_offset, skill_level)

# ============================================================================
# ANALYSIS - PUBLIC INTERFACE
# ============================================================================

func get_upcoming_curvature(lookahead: float = 30.0) -> float:
	if not spline_helper or not spline_helper.is_valid:
		return 0.0
	var target_offset: float = spline_helper.get_lookahead_offset(current_spline_offset, lookahead)
	return spline_helper.get_curvature_at_offset(target_offset)

func get_max_upcoming_curvature() -> float:
	return cached_max_upcoming_curvature

func get_max_curvature_signed() -> float:
	return cached_max_curvature_signed

func get_immediate_curvature() -> float:
	return cached_immediate_curvature

func get_signed_curvature() -> float:
	return cached_immediate_curvature_signed

func get_corner_distance() -> float:
	return cached_corner_distance

func is_approaching_corner(threshold: float = 0.3) -> bool:
	return cached_max_upcoming_curvature > threshold

func is_in_corner(threshold: float = 0.25) -> bool:
	return cached_immediate_curvature > threshold

func is_in_s_curve() -> bool:
	return cached_is_s_curve

func get_target_lateral_offset() -> float:
	return cached_target_lateral_offset

func get_corner_phase() -> float:
	return cached_corner_phase

func get_distance_to_finish() -> float:
	if not spline_helper or not spline_helper.is_valid:
		return 0.0
	var remaining_offset: float = 1.0 - current_spline_offset
	if remaining_offset < 0:
		remaining_offset += 1.0
	return spline_helper.offset_to_distance(remaining_offset)

# ============================================================================
# DEBUG
# ============================================================================

func get_debug_info() -> String:
	var source := "geometric"
	if has_recorded_data and not prefer_baked_over_recorded:
		source = "recorded"
	elif has_baked_line():
		source = "baked"
	var s_curve_str: String = "S-CURVE" if cached_is_s_curve else "single"
	return "Line[%s]: curv=%.2f imm=%.2f lat=%.1fm phase=%.0f%% @%.0fm [%s]" % [
		source,
		cached_max_upcoming_curvature,
		cached_immediate_curvature,
		cached_target_lateral_offset,
		cached_corner_phase * 100.0,
		cached_corner_distance,
		s_curve_str
	]
