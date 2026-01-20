extends RefCounted
class_name AIControlDecider

## AI Control Decider
## Responsible for answering: "How should I control the ship?"
## Uses curvature data for anticipatory braking and smarter airbrake usage.

# ============================================================================
# TUNING PARAMETERS - STEERING
# ============================================================================

## Steering sensitivity (higher = more aggressive steering)
var steering_sensitivity: float = 3.5

## Maximum steering rate of change per second (prevents oscillation)
var max_steer_rate: float = 10.0

# ============================================================================
# TUNING PARAMETERS - THROTTLE/BRAKE
# ============================================================================

## How quickly to reach target speed (multiplier on speed error)
var throttle_responsiveness: float = 0.2

## Speed error threshold to cut throttle (units/second over target)
var throttle_cutoff_threshold: float = 5.0

## Speed error threshold to start braking (units/second over target)
var brake_threshold: float = 4.0

## Brake intensity (multiplier on speed error above threshold)
var brake_intensity: float = 0.5

# ============================================================================
# TUNING PARAMETERS - AIRBRAKES
# ============================================================================

## Curvature threshold to start using airbrakes
var airbrake_curvature_threshold: float = 0.10

## Steering threshold to start using airbrakes (helps when struggling to turn)
var airbrake_steering_threshold: float = 0.3

## How much curvature affects airbrake intensity
var airbrake_curvature_factor: float = 1.5

## Minimum speed ratio to use airbrakes
var airbrake_min_speed_ratio: float = 0.25

## How much to weight recorded control hints (0 = ignore, 1 = follow exactly)
var hint_weight: float = 0.3

# ============================================================================
# STATE
# ============================================================================

var ship: ShipController
var line_follower: AILineFollower

# Smoothed control values to prevent jitter
var smoothed_steer: float = 0.0
var smoothed_throttle: float = 0.0
var smoothed_brake: float = 0.0
var smoothed_airbrake_left: float = 0.0
var smoothed_airbrake_right: float = 0.0

# Previous frame values for rate limiting
var prev_steer: float = 0.0

# ============================================================================
# INITIALIZATION
# ============================================================================

func initialize(p_ship: ShipController, p_line_follower: AILineFollower) -> void:
	ship = p_ship
	line_follower = p_line_follower

# ============================================================================
# MAIN DECISION FUNCTION
# ============================================================================

func decide_controls(delta: float) -> Dictionary:
	"""
	Calculate control inputs for this frame.
	Returns a dictionary with throttle, brake, steer, airbrake_left, airbrake_right.
	"""
	if not ship or not line_follower:
		return _neutral_controls()
	
	# Get target from line follower
	var current_speed: float = ship.velocity.length()
	var max_speed: float = ship.get_max_speed()
	var target: Dictionary = line_follower.get_target_position(current_speed, max_speed)
	
	# Extract curvature data from target
	var target_world_pos: Vector3 = target.world_position
	var target_speed: float = target.suggested_speed
	var max_curvature: float = target.max_upcoming_curvature
	var immediate_curvature: float = target.immediate_curvature
	var corner_distance: float = target.corner_distance
	
	# Calculate each control component
	var raw_steer: float = _calculate_steering(target_world_pos, delta)
	var throttle_brake: Dictionary = _calculate_throttle_and_brake(current_speed, target_speed, max_curvature, corner_distance, target)
	var airbrakes: Dictionary = _calculate_airbrakes(current_speed, max_speed, raw_steer, max_curvature, immediate_curvature, target)
	
	# Smooth controls to prevent jitter
	smoothed_steer = lerpf(smoothed_steer, raw_steer, 10.0 * delta)
	smoothed_throttle = lerpf(smoothed_throttle, throttle_brake.throttle, 8.0 * delta)
	smoothed_brake = lerpf(smoothed_brake, throttle_brake.brake, 12.0 * delta)
	smoothed_airbrake_left = lerpf(smoothed_airbrake_left, airbrakes.left, 10.0 * delta)
	smoothed_airbrake_right = lerpf(smoothed_airbrake_right, airbrakes.right, 10.0 * delta)
	
	return {
		"throttle": smoothed_throttle,
		"brake": smoothed_brake,
		"steer": smoothed_steer,
		"airbrake_left": smoothed_airbrake_left,
		"airbrake_right": smoothed_airbrake_right
	}

func _neutral_controls() -> Dictionary:
	return {
		"throttle": 0.0,
		"brake": 0.0,
		"steer": 0.0,
		"airbrake_left": 0.0,
		"airbrake_right": 0.0
	}

# ============================================================================
# STEERING
# ============================================================================

func _calculate_steering(target_position: Vector3, delta: float) -> float:
	"""Calculate steering input to reach target position."""
	var ship_pos: Vector3 = ship.global_position
	var ship_forward: Vector3 = -ship.global_transform.basis.z
	
	# Vector to target
	var to_target: Vector3 = target_position - ship_pos
	to_target.y = 0  # Ignore vertical component for steering
	if to_target.length_squared() < 0.01:
		return 0.0
	to_target = to_target.normalized()
	
	ship_forward.y = 0
	if ship_forward.length_squared() < 0.01:
		return 0.0
	ship_forward = ship_forward.normalized()
	
	# Calculate signed angle to target
	var cross: Vector3 = ship_forward.cross(to_target)
	var dot: float = ship_forward.dot(to_target)
	
	# Cross product Y component gives us the signed angle direction
	var angle_sign: float = sign(cross.y)
	var angle: float = acos(clamp(dot, -1.0, 1.0))
	
	# Convert to steering input (-1 to 1)
	var steer: float = angle * angle_sign * steering_sensitivity
	
	# Rate limit steering to prevent oscillation
	var max_change: float = max_steer_rate * delta
	steer = clamp(steer, prev_steer - max_change, prev_steer + max_change)
	prev_steer = steer
	
	# Clamp to valid range
	return clamp(steer, -1.0, 1.0)

# ============================================================================
# THROTTLE AND BRAKE (combined for better coordination)
# ============================================================================

func _calculate_throttle_and_brake(current_speed: float, target_speed: float, max_curvature: float, corner_distance: float, target: Dictionary) -> Dictionary:
	"""Calculate throttle and brake together for better coordination."""
	var speed_error: float = target_speed - current_speed
	var over_target: float = current_speed - target_speed
	
	var throttle: float = 0.0
	var brake: float = 0.0
	
	# === THROTTLE LOGIC ===
	if speed_error > 0:
		# Below target speed - accelerate
		throttle = clamp(speed_error * throttle_responsiveness, 0.0, 1.0)
	elif over_target < throttle_cutoff_threshold:
		# Slightly over target but not by much - coast (partial throttle)
		throttle = clamp(1.0 - (over_target / throttle_cutoff_threshold), 0.0, 0.5)
	else:
		# Way over target - no throttle
		throttle = 0.0
	
	# === ANTICIPATORY BRAKING ===
	# If a tight corner is coming up and we're going too fast, brake BEFORE the corner
	if max_curvature > 0.3 and corner_distance < 50.0:
		var corner_approach_factor: float = 1.0 - (corner_distance / 50.0)
		var curvature_severity: float = (max_curvature - 0.3) / 0.7  # Normalize 0.3-1.0 to 0-1
		curvature_severity = clamp(curvature_severity, 0.0, 1.0)
		
		# Reduce throttle when approaching corners
		var throttle_reduction: float = corner_approach_factor * curvature_severity * 0.7
		throttle *= (1.0 - throttle_reduction)
	
	# === BRAKE LOGIC ===
	if over_target > brake_threshold:
		# Significantly over target speed - apply brakes
		brake = clamp((over_target - brake_threshold) * brake_intensity, 0.0, 1.0)
		throttle = 0.0  # Don't accelerate while braking
	
	# Harder braking when approaching tight corners at high speed
	if max_curvature > 0.5 and corner_distance < 30.0 and current_speed > target_speed * 1.1:
		var emergency_brake: float = (current_speed - target_speed) / target_speed
		brake = max(brake, clamp(emergency_brake * 0.5, 0.0, 0.8))
		throttle = 0.0
	
	# === BLEND WITH RECORDED HINTS ===
	var from_recorded: bool = target.from_recorded_data
	if from_recorded and hint_weight > 0:
		var hint_throttle: float = target.hint_throttle
		var hint_brake: float = target.hint_brake
		throttle = lerpf(throttle, hint_throttle, hint_weight)
		brake = lerpf(brake, hint_brake, hint_weight)
	
	return {"throttle": throttle, "brake": brake}

# ============================================================================
# AIRBRAKES
# ============================================================================

func _calculate_airbrakes(current_speed: float, max_speed: float, steer: float, max_curvature: float, immediate_curvature: float, target: Dictionary) -> Dictionary:
	"""
	Calculate airbrake inputs for cornering assistance.
	Airbrakes help rotate the ship faster in tight corners.
	Much more aggressive than before.
	"""
	var result: Dictionary = {"left": 0.0, "right": 0.0}
	
	var speed_ratio: float = current_speed / max_speed if max_speed > 0 else 0.0
	
	# Only use airbrakes at reasonable speed
	if speed_ratio < airbrake_min_speed_ratio:
		return result
	
	var airbrake_intensity: float = 0.0
	
	# === CURVATURE-BASED AIRBRAKES ===
	# Use airbrakes when there's significant curvature ahead or currently
	var effective_curvature: float = max(max_curvature, immediate_curvature)
	
	if effective_curvature > airbrake_curvature_threshold:
		var curvature_factor: float = (effective_curvature - airbrake_curvature_threshold) / (1.0 - airbrake_curvature_threshold)
		curvature_factor = clamp(curvature_factor, 0.0, 1.0)
		airbrake_intensity = curvature_factor * airbrake_curvature_factor
	
	# === STEERING EFFORT-BASED AIRBRAKES ===
	# If steering hard, use airbrakes to help rotation
	var steer_magnitude: float = abs(steer)
	
	if steer_magnitude > airbrake_steering_threshold:
		var steer_factor: float = (steer_magnitude - airbrake_steering_threshold) / (1.0 - airbrake_steering_threshold)
		steer_factor = clamp(steer_factor, 0.0, 1.0)
		
		# Add to curvature-based intensity
		airbrake_intensity = max(airbrake_intensity, steer_factor * 0.8)
	
	# === SCALE BY SPEED ===
	# More effective at higher speeds
	var speed_factor: float = clamp((speed_ratio - airbrake_min_speed_ratio) / (0.8 - airbrake_min_speed_ratio), 0.0, 1.0)
	airbrake_intensity *= speed_factor
	
	# Clamp final intensity
	airbrake_intensity = clamp(airbrake_intensity, 0.0, 1.0)
	
	# === APPLY TO APPROPRIATE SIDE ===
	# Apply airbrake to the OUTSIDE of the turn (opposite side of steer direction)
	# Turning left (negative steer) = right airbrake helps pivot
	# Turning right (positive steer) = left airbrake helps pivot
	
	if steer < -0.15:  # Turning left
		result.right = airbrake_intensity
	elif steer > 0.15:  # Turning right
		result.left = airbrake_intensity
	elif effective_curvature > airbrake_curvature_threshold:
		# No strong steer yet but corner coming - light both airbrakes for general slowing
		result.left = airbrake_intensity * 0.3
		result.right = airbrake_intensity * 0.3
	
	# === BLEND WITH RECORDED HINTS ===
	var from_recorded: bool = target.from_recorded_data
	if from_recorded and hint_weight > 0:
		var hint_left: float = target.hint_airbrake_left
		var hint_right: float = target.hint_airbrake_right
		result.left = lerpf(result.left, hint_left, hint_weight)
		result.right = lerpf(result.right, hint_right, hint_weight)
	
	return result

# ============================================================================
# DEBUG
# ============================================================================

func get_debug_info() -> String:
	return "Controls: T=%.2f B=%.2f S=%.2f AB=L%.2f/R%.2f" % [
		smoothed_throttle,
		smoothed_brake,
		smoothed_steer,
		smoothed_airbrake_left,
		smoothed_airbrake_right
	]
