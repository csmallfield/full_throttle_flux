extends RefCounted
class_name AILineFollower

## AI Line Follower
## Responsible for answering: "Where should I be on the track?"
## 
## Key improvements:
## - S-curve detection: Finds alternating turns and calculates racing line through apexes
## - Apex-seeking: Calculates lateral offset to cut corners rather than following centerline
## - Late braking support: Provides corner entry distance for brake timing

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
# CONFIGURATION - SPEED/CORNER LOOKAHEAD
# ============================================================================

## How far ahead to scan for upcoming corners (meters)
var speed_lookahead_distance: float = 120.0

## Number of points to sample when scanning for corners
var speed_lookahead_samples: int = 10

# ============================================================================
# CONFIGURATION - RACING LINE / APEX SEEKING
# ============================================================================

## Maximum lateral offset from centerline (meters) - how wide the AI can go
var max_lateral_offset: float = 12.0

## How aggressively to cut corners (0 = centerline, 1 = full apex seeking)
var apex_seeking_strength: float = 1.0

## Minimum curvature to trigger lateral offset
var lateral_offset_curvature_threshold: float = 0.15

## Track width estimate (used for clamping lateral offset)
var estimated_track_half_width: float = 16.0

# ============================================================================
# CONFIGURATION - CURVATURE THRESHOLDS
# ============================================================================

## Curvature threshold for "tight corner"
var tight_corner_threshold: float = 0.4

## Curvature threshold for "very tight corner" (hairpin-like)
var very_tight_corner_threshold: float = 0.8

## How much to reduce lookahead in tight corners (multiplier)
var corner_lookahead_reduction: float = 0.5

# ============================================================================
# SKILL EFFECTS
# ============================================================================

## Skill level of this AI (0.0 = safe, 1.0 = fast)
var skill_level: float = 1.0

# ============================================================================
# STATE
# ============================================================================

var spline_helper: TrackSplineHelper
var track_ai_data: TrackAIData  # May be null if no recorded data

var current_spline_offset: float = 0.0
var current_world_position: Vector3 = Vector3.ZERO
var has_recorded_data: bool = false

# Cached analysis results (updated each frame)
var cached_max_upcoming_curvature: float = 0.0
var cached_corner_distance: float = 0.0
var cached_immediate_curvature: float = 0.0
var cached_immediate_curvature_signed: float = 0.0  # Positive = right turn, negative = left

# S-curve detection
var cached_is_s_curve: bool = false
var cached_s_curve_first_direction: float = 0.0  # Sign of first turn
var cached_s_curve_transition_distance: float = 0.0  # Where direction changes

# Racing line
var cached_target_lateral_offset: float = 0.0

# ============================================================================
# INITIALIZATION
# ============================================================================

func initialize(p_spline_helper: TrackSplineHelper, p_track_ai_data: TrackAIData = null) -> void:
	spline_helper = p_spline_helper
	track_ai_data = p_track_ai_data
	has_recorded_data = track_ai_data != null and track_ai_data.has_recorded_data()
	
	if has_recorded_data:
		print("AILineFollower: Initialized with recorded data (skill: %.2f)" % skill_level)
	else:
		print("AILineFollower: Initialized in centerline fallback mode (skill: %.2f)" % skill_level)

func set_skill(skill: float) -> void:
	skill_level = clamp(skill, 0.0, 1.0)

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
	cached_corner_distance = speed_lookahead_distance
	cached_immediate_curvature = spline_helper.get_curvature_at_offset(current_spline_offset, 15.0)
	cached_immediate_curvature_signed = _get_signed_curvature(current_spline_offset, 15.0)
	
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
		var curvature: float = spline_helper.get_curvature_at_offset(sample_offset, 15.0)
		var signed_curv: float = _get_signed_curvature(sample_offset, 15.0)
		
		# Track maximum curvature magnitude
		if curvature > cached_max_upcoming_curvature:
			cached_max_upcoming_curvature = curvature
			cached_corner_distance = distance
		
		# S-curve detection: look for sign change in curvature
		var current_sign: float = sign(signed_curv) if abs(signed_curv) > 0.15 else 0.0
		
		if first_significant_sign == 0.0 and current_sign != 0.0:
			first_significant_sign = current_sign
		
		if prev_sign != 0.0 and current_sign != 0.0 and prev_sign != current_sign:
			# Direction changed - this is an S-curve!
			if not cached_is_s_curve:
				cached_is_s_curve = true
				cached_s_curve_first_direction = prev_sign
				cached_s_curve_transition_distance = distance
		
		if current_sign != 0.0:
			prev_sign = current_sign

func _get_signed_curvature(offset: float, sample_distance: float) -> float:
	"""
	Get curvature with sign indicating direction.
	Positive = turning right, Negative = turning left.
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
	
	# Cross product Y component tells us turn direction
	var cross: Vector3 = dir_current.cross(dir_ahead)
	var dot: float = dir_current.dot(dir_ahead)
	
	# Magnitude from dot product, sign from cross product
	var curvature_magnitude: float = 1.0 - dot
	var turn_direction: float = -sign(cross.y)  # Negative because of coordinate system
	
	return curvature_magnitude * turn_direction

func _update_racing_line() -> void:
	"""
	Calculate optimal lateral offset for racing line.
	Uses ACTUAL TRACK WIDTH for geometric apex calculation.
	
	Racing line principle:
	- Entry: Outside of turn (near outside wall)
	- Apex: Inside of turn (near inside wall) 
	- Exit: Let the ship drift back out (use full track width)
	
	The tighter the corner, the closer to the inside edge the apex should be.
	"""
	cached_target_lateral_offset = 0.0
	
	# Don't offset if curvature is too low (straight section)
	if cached_max_upcoming_curvature < lateral_offset_curvature_threshold:
		return
	
	# === CALCULATE APEX DEPTH BASED ON CORNER TIGHTNESS ===
	# Tighter corners = deeper into the inside of the track
	# curvature 0.2 (gentle) = 50% of available width
	# curvature 0.5 (medium) = 75% of available width  
	# curvature 0.8+ (tight) = 90% of available width
	
	var curvature_normalized: float = clamp(
		(cached_max_upcoming_curvature - lateral_offset_curvature_threshold) / 
		(very_tight_corner_threshold - lateral_offset_curvature_threshold),
		0.0, 1.0
	)
	
	# How close to the inside edge to place the apex (0.5 = halfway, 0.9 = very close to edge)
	var apex_depth: float = lerpf(0.5, 0.9, curvature_normalized)
	
	# Calculate actual apex offset in meters
	# Leave small margin from wall (based on ship size ~6m, use half + buffer)
	var wall_margin: float = 5.0
	var usable_half_width: float = estimated_track_half_width - wall_margin
	var apex_offset: float = usable_half_width * apex_depth
	
	# Entry/exit offset (position on outside of turn)
	# Less aggressive than apex - use 50-70% of available width
	var entry_depth: float = lerpf(0.4, 0.65, curvature_normalized)
	var entry_offset: float = usable_half_width * entry_depth
	
	var base_offset: float = 0.0
	
	if cached_is_s_curve:
		# === S-CURVE LOGIC ===
		# Key insight: In an S-curve, the exit of turn 1 IS the entry of turn 2
		# So we need to find a compromise line that works for both turns
		
		var first_turn_right: bool = cached_s_curve_first_direction > 0
		var transition_progress: float = 0.0
		
		if cached_s_curve_transition_distance > 0:
			transition_progress = clamp(cached_corner_distance / cached_s_curve_transition_distance, 0.0, 2.0)
		
		# S-curve phases:
		# 0.0 - 0.5: Approaching first turn, set up on outside
		# 0.5 - 1.0: Through first apex
		# 1.0 - 1.5: Transition (this is the key "straight line" through the S)
		# 1.5 - 2.0: Through second apex
		
		if transition_progress < 0.5:
			# Entry to first turn - position to outside
			var phase: float = transition_progress / 0.5
			if first_turn_right:
				# Right turn = start on LEFT side (negative), moving toward center
				base_offset = lerpf(-entry_offset, -entry_offset * 0.3, phase)
			else:
				# Left turn = start on RIGHT side (positive), moving toward center
				base_offset = lerpf(entry_offset, entry_offset * 0.3, phase)
				
		elif transition_progress < 1.0:
			# First apex - cut to inside
			var phase: float = (transition_progress - 0.5) / 0.5
			if first_turn_right:
				# Right turn apex = RIGHT side (positive)
				base_offset = lerpf(-entry_offset * 0.3, apex_offset * 0.7, phase)
			else:
				# Left turn apex = LEFT side (negative)
				base_offset = lerpf(entry_offset * 0.3, -apex_offset * 0.7, phase)
				
		elif transition_progress < 1.5:
			# Transition between turns - the "straight line through the S"
			# This is where we cut across from one apex toward the other
			var phase: float = (transition_progress - 1.0) / 0.5
			
			if first_turn_right:
				# Was right turn, now going to left turn
				# Move from right apex area toward left apex area
				base_offset = lerpf(apex_offset * 0.7, -apex_offset * 0.5, phase)
			else:
				# Was left turn, now going to right turn
				base_offset = lerpf(-apex_offset * 0.7, apex_offset * 0.5, phase)
				
		else:
			# Second apex and exit
			var phase: float = clamp((transition_progress - 1.5) / 0.5, 0.0, 1.0)
			var second_turn_right: bool = not first_turn_right
			
			if second_turn_right:
				# Right turn apex, then drift left on exit
				base_offset = lerpf(apex_offset * 0.5, apex_offset * 0.3, phase)
			else:
				# Left turn apex, then drift right on exit
				base_offset = lerpf(-apex_offset * 0.5, -apex_offset * 0.3, phase)
	
	else:
		# === SINGLE CORNER LOGIC ===
		# Classic racing line: outside-inside-outside
		
		var turn_right: bool = cached_immediate_curvature_signed > 0
		if abs(cached_immediate_curvature_signed) < 0.1:
			# Use upcoming curvature direction if immediate is too low
			turn_right = cached_max_upcoming_curvature > 0 and cached_s_curve_first_direction >= 0
		
		# Phase calculation based on distance to corner
		# Scale the phase distance with track size
		var phase_distance: float = 100.0  # How far out to start the racing line
		var corner_phase: float = 0.0
		
		if cached_corner_distance < phase_distance:
			corner_phase = 1.0 - (cached_corner_distance / phase_distance)
		
		# Racing line phases:
		# 0.0 - 0.35: Entry - position to outside of turn
		# 0.35 - 0.65: Apex - cut to inside of turn (this is where time is saved!)
		# 0.65 - 1.0: Exit - drift back toward outside/center
		
		if corner_phase < 0.35:
			# ENTRY: Position to outside of turn
			var phase: float = corner_phase / 0.35
			if turn_right:
				# Right turn entry = LEFT side (negative offset)
				base_offset = lerpf(-entry_offset * 0.8, -entry_offset * 0.5, phase)
			else:
				# Left turn entry = RIGHT side (positive offset)
				base_offset = lerpf(entry_offset * 0.8, entry_offset * 0.5, phase)
				
		elif corner_phase < 0.65:
			# APEX: Cut hard to the inside!
			var phase: float = (corner_phase - 0.35) / 0.3
			if turn_right:
				# Right turn apex = RIGHT side (positive offset, near inside wall)
				base_offset = lerpf(-entry_offset * 0.5, apex_offset, phase)
			else:
				# Left turn apex = LEFT side (negative offset, near inside wall)
				base_offset = lerpf(entry_offset * 0.5, -apex_offset, phase)
				
		else:
			# EXIT: Drift back out, using track width
			var phase: float = (corner_phase - 0.65) / 0.35
			if turn_right:
				# Exiting right turn - drift back toward left/center
				base_offset = lerpf(apex_offset, entry_offset * 0.3, phase)
			else:
				# Exiting left turn - drift back toward right/center
				base_offset = lerpf(-apex_offset, -entry_offset * 0.3, phase)
	
	# === APPLY MODIFIERS ===
	
	# Skill modifier: Lower skill = less aggressive line
	var skill_modifier: float = lerpf(0.6, 1.0, skill_level)
	
	# Apply apex seeking strength and skill
	cached_target_lateral_offset = base_offset * apex_seeking_strength * skill_modifier
	
	# Clamp to track bounds (leave margin from walls)
	var max_allowed_offset: float = estimated_track_half_width - 4.0  # 4m minimum from wall
	cached_target_lateral_offset = clamp(cached_target_lateral_offset, -max_allowed_offset, max_allowed_offset)

func get_current_spline_offset() -> float:
	return current_spline_offset

# ============================================================================
# TARGET QUERIES - MAIN INTERFACE
# ============================================================================

func get_target_position(ship_speed: float, max_speed: float) -> Dictionary:
	"""
	Get the target position the AI should steer toward.
	Now includes racing line lateral offset for apex-seeking.
	"""
	var speed_ratio: float = ship_speed / max_speed if max_speed > 0 else 0.0
	
	# Calculate adaptive steering lookahead
	var base_lookahead: float = lerpf(steer_lookahead_min, steer_lookahead_max, speed_ratio)
	var actual_lookahead: float = _apply_curvature_lookahead_adjustment(base_lookahead)
	
	# Skill affects lookahead
	var skill_lookahead_modifier: float = lerpf(0.8, 1.1, skill_level)
	actual_lookahead *= skill_lookahead_modifier
	
	if has_recorded_data:
		return _get_recorded_target(actual_lookahead, max_speed)
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

func _get_recorded_target(lookahead: float, max_speed: float) -> Dictionary:
	"""Get target from recorded racing line data."""
	var target_offset: float = spline_helper.get_lookahead_offset(current_spline_offset, lookahead)
	var sample: AIRacingSample = track_ai_data.get_interpolated_sample(target_offset, skill_level)
	
	if sample == null:
		return _get_centerline_target(lookahead, max_speed, 0.5)
	
	var world_pos: Vector3 = spline_helper.spline_offset_to_world_with_lateral(
		target_offset, 
		sample.lateral_offset
	)
	
	return {
		"world_position": world_pos,
		"suggested_speed": sample.speed,
		"lateral_offset": sample.lateral_offset,
		"heading": sample.heading,
		"spline_offset": target_offset,
		"from_recorded_data": true,
		"lookahead_used": lookahead,
		"max_upcoming_curvature": cached_max_upcoming_curvature,
		"corner_distance": cached_corner_distance,
		"immediate_curvature": cached_immediate_curvature,
		"is_s_curve": cached_is_s_curve,
		"hint_throttle": sample.throttle,
		"hint_brake": sample.brake,
		"hint_airbrake_left": sample.airbrake_left,
		"hint_airbrake_right": sample.airbrake_right
	}

func _get_centerline_target(lookahead: float, max_speed: float, speed_ratio: float) -> Dictionary:
	"""Get target with racing line offset applied."""
	var target_offset: float = spline_helper.get_lookahead_offset(current_spline_offset, lookahead)
	
	# Get base centerline position
	var centerline_pos: Vector3 = spline_helper.spline_offset_to_world(target_offset)
	
	# Apply racing line lateral offset
	var world_pos: Vector3
	if abs(cached_target_lateral_offset) > 0.1:
		world_pos = spline_helper.spline_offset_to_world_with_lateral(target_offset, cached_target_lateral_offset)
	else:
		world_pos = centerline_pos
	
	var tangent: Vector3 = spline_helper.get_tangent_at_offset(target_offset)
	var suggested_speed: float = _calculate_corner_safe_speed(max_speed)
	
	# Apply skill modifier
	var skill_speed_modifier: float = lerpf(0.65, 1.0, skill_level)
	suggested_speed *= skill_speed_modifier
	
	return {
		"world_position": world_pos,
		"suggested_speed": suggested_speed,
		"lateral_offset": cached_target_lateral_offset,
		"heading": tangent,
		"spline_offset": target_offset,
		"from_recorded_data": false,
		"lookahead_used": lookahead,
		"max_upcoming_curvature": cached_max_upcoming_curvature,
		"corner_distance": cached_corner_distance,
		"immediate_curvature": cached_immediate_curvature,
		"is_s_curve": cached_is_s_curve,
		"hint_throttle": 1.0,
		"hint_brake": 0.0,
		"hint_airbrake_left": 0.0,
		"hint_airbrake_right": 0.0
	}

func _calculate_corner_safe_speed(max_speed: float) -> float:
	"""Calculate safe speed - now with late braking support."""
	var curvature: float = cached_max_upcoming_curvature
	curvature = max(curvature, cached_immediate_curvature)
	
	var min_speed_ratio: float = 0.3
	
	# S-curves can be taken faster due to straighter racing line
	var s_curve_bonus: float = 1.0
	if cached_is_s_curve:
		s_curve_bonus = 1.15  # 15% faster through S-curves with good line
	
	# Map curvature to speed reduction
	var speed_reduction: float = curvature * 1.6  # Slightly less aggressive for late braking
	speed_reduction = clamp(speed_reduction, 0.0, 1.0 - min_speed_ratio)
	
	var safe_speed: float = max_speed * (1.0 - speed_reduction) * s_curve_bonus
	
	# Late braking: only apply proximity penalty when VERY close
	if cached_corner_distance < 20.0 and curvature > tight_corner_threshold:
		var proximity_penalty: float = (20.0 - cached_corner_distance) / 20.0 * 0.1
		safe_speed *= (1.0 - proximity_penalty)
	
	return clamp(safe_speed, max_speed * min_speed_ratio, max_speed)

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

func get_immediate_curvature() -> float:
	return cached_immediate_curvature

func get_signed_curvature() -> float:
	"""Get curvature with direction. Positive = right turn, negative = left turn."""
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
	"""Get the calculated racing line lateral offset."""
	return cached_target_lateral_offset

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
	var s_curve_str: String = "S-CURVE" if cached_is_s_curve else "single"
	return "Line: off=%.3f curv=%.2f/%s lat=%.1fm corner@%.0fm [%s]" % [
		current_spline_offset,
		cached_immediate_curvature,
		"R" if cached_immediate_curvature_signed > 0 else "L",
		cached_target_lateral_offset,
		cached_corner_distance,
		s_curve_str
	]
