extends RefCounted
class_name AILineFollower

## AI Line Follower
## Responsible for answering: "Where should I be on the track?"
## Uses dual-lookahead system: near point for steering, far point for speed planning.
## Curvature-aware lookahead shortens when approaching tight corners.

# ============================================================================
# CONFIGURATION - STEERING LOOKAHEAD
# ============================================================================

## Base steering lookahead at low speeds (meters)
var steer_lookahead_min: float = 12.0

## Base steering lookahead at high speeds (meters)  
var steer_lookahead_max: float = 35.0

## Minimum steering lookahead in tight corners (meters)
var steer_lookahead_corner_min: float = 8.0

# ============================================================================
# CONFIGURATION - SPEED LOOKAHEAD (for braking decisions)
# ============================================================================

## How far ahead to scan for upcoming corners (meters)
var speed_lookahead_distance: float = 60.0

## Number of points to sample when scanning for corners
var speed_lookahead_samples: int = 6

# ============================================================================
# CONFIGURATION - CURVATURE RESPONSE
# ============================================================================

## Curvature threshold for "tight corner" (triggers lookahead reduction)
var tight_corner_threshold: float = 0.4

## Curvature threshold for "very tight corner" (hairpin-like)
var very_tight_corner_threshold: float = 0.8

## How much to reduce lookahead in tight corners (multiplier)
var corner_lookahead_reduction: float = 0.5

# ============================================================================
# SKILL EFFECTS
# ============================================================================

## Skill level of this AI (0.0 = safe, 1.0 = fast)
var skill_level: float = 0.5

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

func _update_curvature_analysis() -> void:
	"""Scan ahead and cache curvature information for this frame."""
	cached_max_upcoming_curvature = 0.0
	cached_corner_distance = speed_lookahead_distance
	cached_immediate_curvature = spline_helper.get_curvature_at_offset(current_spline_offset, 15.0)
	
	# Sample multiple points ahead to find the worst corner
	var sample_spacing: float = speed_lookahead_distance / float(speed_lookahead_samples)
	
	for i in range(speed_lookahead_samples):
		var distance: float = sample_spacing * float(i + 1)
		var sample_offset: float = spline_helper.get_lookahead_offset(current_spline_offset, distance)
		var curvature: float = spline_helper.get_curvature_at_offset(sample_offset, 15.0)
		
		if curvature > cached_max_upcoming_curvature:
			cached_max_upcoming_curvature = curvature
			cached_corner_distance = distance

func get_current_spline_offset() -> float:
	return current_spline_offset

# ============================================================================
# TARGET QUERIES - MAIN INTERFACE
# ============================================================================

func get_target_position(ship_speed: float, max_speed: float) -> Dictionary:
	"""
	Get the target position the AI should steer toward.
	Returns a dictionary with position, speed hint, and analysis data.
	"""
	var speed_ratio: float = ship_speed / max_speed if max_speed > 0 else 0.0
	
	# Calculate adaptive steering lookahead
	var base_lookahead: float = lerpf(steer_lookahead_min, steer_lookahead_max, speed_ratio)
	var actual_lookahead: float = _apply_curvature_lookahead_adjustment(base_lookahead)
	
	# Skill affects lookahead: lower skill = shorter lookahead (more reactive)
	var skill_lookahead_modifier: float = lerpf(0.8, 1.1, skill_level)
	actual_lookahead *= skill_lookahead_modifier
	
	if has_recorded_data:
		return _get_recorded_target(actual_lookahead, max_speed)
	else:
		return _get_centerline_target(actual_lookahead, max_speed, speed_ratio)

func _apply_curvature_lookahead_adjustment(base_lookahead: float) -> float:
	"""Reduce lookahead when approaching tight corners for quicker reactions."""
	if cached_max_upcoming_curvature < tight_corner_threshold:
		return base_lookahead
	
	# Calculate reduction based on how tight the corner is
	var tightness: float = (cached_max_upcoming_curvature - tight_corner_threshold) / (very_tight_corner_threshold - tight_corner_threshold)
	tightness = clamp(tightness, 0.0, 1.0)
	
	# Also consider how close the corner is
	var proximity_factor: float = 1.0 - clamp(cached_corner_distance / speed_lookahead_distance, 0.0, 1.0)
	
	# Combined reduction
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
		"hint_throttle": sample.throttle,
		"hint_brake": sample.brake,
		"hint_airbrake_left": sample.airbrake_left,
		"hint_airbrake_right": sample.airbrake_right
	}

func _get_centerline_target(lookahead: float, max_speed: float, speed_ratio: float) -> Dictionary:
	"""Fallback: Get target from track centerline with curvature-based speed."""
	var target_offset: float = spline_helper.get_lookahead_offset(current_spline_offset, lookahead)
	var world_pos: Vector3 = spline_helper.spline_offset_to_world(target_offset)
	var tangent: Vector3 = spline_helper.get_tangent_at_offset(target_offset)
	
	# Calculate suggested speed based on UPCOMING curvature, not current position
	var suggested_speed: float = _calculate_corner_safe_speed(max_speed)
	
	# Apply skill modifier
	var skill_speed_modifier: float = lerpf(0.65, 1.0, skill_level)
	suggested_speed *= skill_speed_modifier
	
	return {
		"world_position": world_pos,
		"suggested_speed": suggested_speed,
		"lateral_offset": 0.0,
		"heading": tangent,
		"spline_offset": target_offset,
		"from_recorded_data": false,
		"lookahead_used": lookahead,
		"max_upcoming_curvature": cached_max_upcoming_curvature,
		"corner_distance": cached_corner_distance,
		"immediate_curvature": cached_immediate_curvature,
		"hint_throttle": 1.0,
		"hint_brake": 0.0,
		"hint_airbrake_left": 0.0,
		"hint_airbrake_right": 0.0
	}

func _calculate_corner_safe_speed(max_speed: float) -> float:
	"""Calculate safe speed considering upcoming corners."""
	# Use the worst curvature we found in our lookahead scan
	var curvature: float = cached_max_upcoming_curvature
	
	# Also consider immediate curvature (we might already be in a corner)
	curvature = max(curvature, cached_immediate_curvature)
	
	# Base minimum speed ratio (don't go below this fraction of max speed)
	var min_speed_ratio: float = 0.3
	
	# Map curvature to speed reduction
	# curvature 0.0 = straight, ~0.5 = moderate corner, ~1.0+ = tight corner
	var speed_reduction: float = curvature * 1.8  # More aggressive than before
	speed_reduction = clamp(speed_reduction, 0.0, 1.0 - min_speed_ratio)
	
	var safe_speed: float = max_speed * (1.0 - speed_reduction)
	
	# Additional reduction if corner is very close
	if cached_corner_distance < 30.0 and curvature > tight_corner_threshold:
		var proximity_penalty: float = (30.0 - cached_corner_distance) / 30.0 * 0.15
		safe_speed *= (1.0 - proximity_penalty)
	
	return max(safe_speed, max_speed * min_speed_ratio)

# ============================================================================
# CURRENT SAMPLE (for control hints)
# ============================================================================

func get_current_sample() -> AIRacingSample:
	"""Get the sample at the current position (for control hints)."""
	if not has_recorded_data:
		return null
	
	return track_ai_data.get_interpolated_sample(current_spline_offset, skill_level)

# ============================================================================
# ANALYSIS - PUBLIC INTERFACE
# ============================================================================

func get_upcoming_curvature(lookahead: float = 30.0) -> float:
	"""Get the curvature of the track at a specific distance ahead."""
	if not spline_helper or not spline_helper.is_valid:
		return 0.0
	
	var target_offset: float = spline_helper.get_lookahead_offset(current_spline_offset, lookahead)
	return spline_helper.get_curvature_at_offset(target_offset)

func get_max_upcoming_curvature() -> float:
	"""Get the maximum curvature found in the speed lookahead scan."""
	return cached_max_upcoming_curvature

func get_immediate_curvature() -> float:
	"""Get the curvature at/near current position."""
	return cached_immediate_curvature

func get_corner_distance() -> float:
	"""Get distance to the tightest upcoming corner."""
	return cached_corner_distance

func is_approaching_corner(threshold: float = 0.3) -> bool:
	"""Check if a significant corner is coming up."""
	return cached_max_upcoming_curvature > threshold

func is_in_corner(threshold: float = 0.25) -> bool:
	"""Check if currently in a corner."""
	return cached_immediate_curvature > threshold

func get_distance_to_finish() -> float:
	"""Get remaining distance to complete current lap."""
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
	return "LineFollower: offset=%.3f, curv=%.2f/%.2f, corner@%.0fm, skill=%.2f" % [
		current_spline_offset,
		cached_immediate_curvature,
		cached_max_upcoming_curvature,
		cached_corner_distance,
		skill_level
	]
