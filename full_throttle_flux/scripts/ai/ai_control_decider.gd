extends RefCounted
class_name AIControlDecider

## AI Control Decider
## Responsible for answering: "How should I control the ship?"
## Makes autonomous decisions but can reference recorded control data as hints.

# ============================================================================
# TUNING PARAMETERS
# ============================================================================

## How much to weight recorded control hints (0 = ignore, 1 = follow exactly)
var hint_weight: float = 0.3

## Steering sensitivity (higher = more aggressive steering)
var steering_sensitivity: float = 2.5

## How quickly to reach target speed before braking (multiplier on speed error)
var throttle_responsiveness: float = 0.15

## Speed error threshold to start braking (units/second)
var brake_threshold: float = 15.0

## Minimum speed error to use airbrakes (helps with sharp corners)
var airbrake_threshold: float = 20.0

## How much upcoming curvature affects airbrake decision
var curvature_airbrake_factor: float = 2.0

# ============================================================================
# STATE
# ============================================================================

var ship: ShipController
var line_follower: AILineFollower

# Smoothed control values to prevent jitter
var smoothed_steer: float = 0.0
var smoothed_throttle: float = 0.0
var smoothed_brake: float = 0.0

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
	var current_speed := ship.velocity.length()
	var max_speed := ship.get_max_speed()
	var target := line_follower.get_target_position(current_speed, max_speed)
	
	# Calculate each control component
	var target_pos: Vector3 = target.world_position
	var target_speed: float = target.suggested_speed
	var raw_steer: float = _calculate_steering(target_pos)
	var raw_throttle: float = _calculate_throttle(current_speed, target_speed, target)
	var raw_brake: float = _calculate_brake(current_speed, target_speed, target)
	var airbrakes: Dictionary = _calculate_airbrakes(target, raw_steer)
	
	# Smooth controls to prevent jitter
	smoothed_steer = lerp(smoothed_steer, raw_steer, 10.0 * delta)
	smoothed_throttle = lerp(smoothed_throttle, raw_throttle, 8.0 * delta)
	smoothed_brake = lerp(smoothed_brake, raw_brake, 12.0 * delta)
	
	return {
		"throttle": smoothed_throttle,
		"brake": smoothed_brake,
		"steer": smoothed_steer,
		"airbrake_left": airbrakes.left,
		"airbrake_right": airbrakes.right
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

func _calculate_steering(target_position: Vector3) -> float:
	"""Calculate steering input to reach target position."""
	var ship_pos := ship.global_position
	var ship_forward := -ship.global_transform.basis.z
	
	# Vector to target
	var to_target := target_position - ship_pos
	to_target.y = 0  # Ignore vertical component for steering
	to_target = to_target.normalized()
	
	ship_forward.y = 0
	ship_forward = ship_forward.normalized()
	
	# Calculate signed angle to target
	var cross := ship_forward.cross(to_target)
	var dot := ship_forward.dot(to_target)
	
	# Cross product Y component gives us the signed angle direction
	var angle_sign: float = sign(cross.y)
	var angle: float = acos(clamp(dot, -1.0, 1.0))
	
	# Convert to steering input (-1 to 1)
	# Negative = steer left, Positive = steer right
	var steer: float = angle * angle_sign * steering_sensitivity
	
	# Clamp to valid range
	return clamp(steer, -1.0, 1.0)

# ============================================================================
# THROTTLE
# ============================================================================

func _calculate_throttle(current_speed: float, target_speed: float, target: Dictionary) -> float:
	"""Calculate throttle input based on speed target."""
	var speed_error := target_speed - current_speed
	
	# Base decision: accelerate if below target speed
	var own_decision: float = clamp(speed_error * throttle_responsiveness, 0.0, 1.0)
	
	# If we're way over target speed, don't accelerate
	if speed_error < -brake_threshold:
		own_decision = 0.0
	
	# Blend with recorded hint if available
	if target.from_recorded_data and hint_weight > 0:
		var hint: float = target.hint_throttle
		return lerp(own_decision, hint, hint_weight)
	
	return own_decision

# ============================================================================
# BRAKING
# ============================================================================

func _calculate_brake(current_speed: float, target_speed: float, target: Dictionary) -> float:
	"""Calculate brake input based on speed target."""
	var speed_error := current_speed - target_speed
	
	# Only brake if significantly over target speed
	var own_decision := 0.0
	if speed_error > brake_threshold:
		own_decision = clamp((speed_error - brake_threshold) * 0.05, 0.0, 1.0)
	
	# Blend with recorded hint if available
	if target.from_recorded_data and hint_weight > 0:
		var hint: float = target.hint_brake
		return lerp(own_decision, hint, hint_weight)
	
	return own_decision

# ============================================================================
# AIRBRAKES
# ============================================================================

func _calculate_airbrakes(target: Dictionary, steer: float) -> Dictionary:
	"""
	Calculate airbrake inputs for sharp cornering.
	Airbrakes help rotate the ship faster in tight corners.
	"""
	var result := {"left": 0.0, "right": 0.0}
	
	# Get upcoming curvature
	var curvature := line_follower.get_upcoming_curvature(20.0)
	
	# Check if we should use airbrakes based on:
	# 1. Sharp corner coming up
	# 2. Significant steering input
	# 3. Going fast enough that airbrakes help
	
	var current_speed := ship.velocity.length()
	var speed_ratio := current_speed / ship.get_max_speed()
	
	# Only use airbrakes at reasonable speed
	if speed_ratio < 0.3:
		return result
	
	# Calculate airbrake intensity based on curvature and steering
	var airbrake_intensity := curvature * curvature_airbrake_factor
	airbrake_intensity = clamp(airbrake_intensity, 0.0, 1.0)
	
	# Also consider steering amount
	var steer_factor: float = abs(steer)
	airbrake_intensity *= steer_factor
	
	# Apply to appropriate side (opposite of turn direction)
	# Turning left (negative steer) = right airbrake
	# Turning right (positive steer) = left airbrake
	if steer < -0.2:
		result.right = airbrake_intensity
	elif steer > 0.2:
		result.left = airbrake_intensity
	
	# Blend with recorded hints if available
	if target.from_recorded_data and hint_weight > 0:
		var hint_left: float = target.hint_airbrake_left
		var hint_right: float = target.hint_airbrake_right
		result.left = lerp(result.left, hint_left, hint_weight)
		result.right = lerp(result.right, hint_right, hint_weight)
	
	return result

# ============================================================================
# DEBUG
# ============================================================================

func get_debug_info() -> String:
	return "Controls: T=%.2f B=%.2f S=%.2f AB=%.2f/%.2f" % [
		smoothed_throttle,
		smoothed_brake,
		smoothed_steer,
		0.0,  # Would need to track airbrakes
		0.0
	]
