extends RefCounted
class_name AILineFollower

## AI Line Follower
## Responsible for answering: "Where should I be on the track?"
## Queries recorded racing line data or falls back to centerline following.

# ============================================================================
# CONFIGURATION
# ============================================================================

## How far ahead to look for target position (meters)
var lookahead_distance: float = 30.0

## Minimum lookahead distance at low speeds
var lookahead_min: float = 15.0

## Maximum lookahead distance at high speeds
var lookahead_max: float = 50.0

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

func get_current_spline_offset() -> float:
	return current_spline_offset

# ============================================================================
# TARGET QUERIES
# ============================================================================

func get_target_position(ship_speed: float, max_speed: float) -> Dictionary:
	"""
	Get the target position the AI should steer toward.
	Returns a dictionary with position, speed hint, and other data.
	"""
	# Scale lookahead with speed
	var speed_ratio := ship_speed / max_speed if max_speed > 0 else 0.0
	var actual_lookahead: float = lerp(lookahead_min, lookahead_max, speed_ratio)
	
	if has_recorded_data:
		return _get_recorded_target(actual_lookahead)
	else:
		return _get_centerline_target(actual_lookahead, max_speed)

func _get_recorded_target(lookahead: float) -> Dictionary:
	"""Get target from recorded racing line data."""
	var target_offset := spline_helper.get_lookahead_offset(current_spline_offset, lookahead)
	var sample := track_ai_data.get_interpolated_sample(target_offset, skill_level)
	
	if sample == null:
		# Fallback if sample retrieval fails
		return _get_centerline_target(lookahead, 120.0)
	
	# Convert sample to world position with lateral offset
	var world_pos := spline_helper.spline_offset_to_world_with_lateral(
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
		# Control hints (AI makes own decisions but can reference these)
		"hint_throttle": sample.throttle,
		"hint_brake": sample.brake,
		"hint_airbrake_left": sample.airbrake_left,
		"hint_airbrake_right": sample.airbrake_right
	}

func _get_centerline_target(lookahead: float, max_speed: float) -> Dictionary:
	"""Fallback: Get target from track centerline with curvature-based speed."""
	var target_offset := spline_helper.get_lookahead_offset(current_spline_offset, lookahead)
	var world_pos := spline_helper.spline_offset_to_world(target_offset)
	var tangent := spline_helper.get_tangent_at_offset(target_offset)
	var suggested_speed := spline_helper.estimate_safe_speed(target_offset, max_speed)
	
	# Apply skill modifier to suggested speed
	# Lower skill = more conservative speed targets
	var skill_speed_modifier: float = lerp(0.7, 1.0, skill_level)
	suggested_speed *= skill_speed_modifier
	
	return {
		"world_position": world_pos,
		"suggested_speed": suggested_speed,
		"lateral_offset": 0.0,
		"heading": tangent,
		"spline_offset": target_offset,
		"from_recorded_data": false,
		# No control hints in fallback mode
		"hint_throttle": 1.0,
		"hint_brake": 0.0,
		"hint_airbrake_left": 0.0,
		"hint_airbrake_right": 0.0
	}

# ============================================================================
# CURRENT SAMPLE (for control hints)
# ============================================================================

func get_current_sample() -> AIRacingSample:
	"""Get the sample at the current position (for control hints)."""
	if not has_recorded_data:
		return null
	
	return track_ai_data.get_interpolated_sample(current_spline_offset, skill_level)

# ============================================================================
# ANALYSIS
# ============================================================================

func get_upcoming_curvature(lookahead: float = 30.0) -> float:
	"""Get the curvature of the track ahead (0 = straight, higher = tighter)."""
	if not spline_helper or not spline_helper.is_valid:
		return 0.0
	
	var target_offset := spline_helper.get_lookahead_offset(current_spline_offset, lookahead)
	return spline_helper.get_curvature_at_offset(target_offset)

func is_approaching_corner(threshold: float = 0.3) -> bool:
	"""Check if a corner is coming up."""
	return get_upcoming_curvature() > threshold

func get_distance_to_finish() -> float:
	"""Get remaining distance to complete current lap."""
	if not spline_helper or not spline_helper.is_valid:
		return 0.0
	
	var remaining_offset := 1.0 - current_spline_offset
	if remaining_offset < 0:
		remaining_offset += 1.0
	
	return spline_helper.offset_to_distance(remaining_offset)

# ============================================================================
# DEBUG
# ============================================================================

func get_debug_info() -> String:
	return "LineFollower: offset=%.3f, skill=%.2f, recorded=%s" % [
		current_spline_offset, 
		skill_level, 
		has_recorded_data
	]
