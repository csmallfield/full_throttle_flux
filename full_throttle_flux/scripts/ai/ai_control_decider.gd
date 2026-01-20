extends RefCounted
class_name AIControlDecider

## AI Control Decider
## Responsible for answering: "How should I control the ship?"
## 
## Key improvements:
## - Late braking: Maintains speed longer, brakes harder when needed
## - S-curve awareness: Less braking through S-curves with good racing line
## - Throttle on exit: Gets back on throttle earlier when exiting corners

# ============================================================================
# TUNING PARAMETERS - STEERING (User tuned)
# ============================================================================

## Steering sensitivity (higher = more aggressive steering)
var steering_sensitivity: float = 3.5

## Maximum steering rate of change per second (prevents oscillation)
var max_steer_rate: float = 10.0

# ============================================================================
# TUNING PARAMETERS - THROTTLE/BRAKE (User tuned + late braking)
# ============================================================================

## How quickly to reach target speed (multiplier on speed error)
var throttle_responsiveness: float = 0.25

## Speed error threshold to cut throttle (units/second over target)
var throttle_cutoff_threshold: float = 8.0

## Speed error threshold to start braking (units/second over target)
var brake_threshold: float = 4.0

## Brake intensity (multiplier on speed error above threshold)
var brake_intensity: float = 0.5

## Distance to corner to START considering braking (late braking = lower value)
var brake_distance_threshold: float = 60.0

## Emergency brake distance (hard brake if this close and too fast)
var emergency_brake_distance: float = 25.0

# ============================================================================
# TUNING PARAMETERS - AIRBRAKES (User tuned)
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
	"""Calculate control inputs for this frame."""
	if not ship or not line_follower:
		return _neutral_controls()
	
	var current_speed: float = ship.velocity.length()
	var max_speed: float = ship.get_max_speed()
	var target: Dictionary = line_follower.get_target_position(current_speed, max_speed)
	
	# Extract data from target
	var target_world_pos: Vector3 = target.world_position
	var target_speed: float = target.suggested_speed
	var max_curvature: float = target.max_upcoming_curvature
	var immediate_curvature: float = target.immediate_curvature
	var corner_distance: float = target.corner_distance
	var is_s_curve: bool = target.is_s_curve
	
	# Calculate controls
	var raw_steer: float = _calculate_steering(target_world_pos, delta)
	var throttle_brake: Dictionary = _calculate_throttle_and_brake(
		current_speed, target_speed, max_speed, max_curvature, 
		immediate_curvature, corner_distance, is_s_curve, target
	)
	var airbrakes: Dictionary = _calculate_airbrakes(
		current_speed, max_speed, raw_steer, max_curvature, 
		immediate_curvature, is_s_curve, target
	)
	
	# Smooth controls
	smoothed_steer = lerpf(smoothed_steer, raw_steer, 12.0 * delta)
	smoothed_throttle = lerpf(smoothed_throttle, throttle_brake.throttle, 10.0 * delta)
	smoothed_brake = lerpf(smoothed_brake, throttle_brake.brake, 15.0 * delta)  # Faster brake response
	smoothed_airbrake_left = lerpf(smoothed_airbrake_left, airbrakes.left, 12.0 * delta)
	smoothed_airbrake_right = lerpf(smoothed_airbrake_right, airbrakes.right, 12.0 * delta)
	
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
	
	var to_target: Vector3 = target_position - ship_pos
	to_target.y = 0
	if to_target.length_squared() < 0.01:
		return 0.0
	to_target = to_target.normalized()
	
	ship_forward.y = 0
	if ship_forward.length_squared() < 0.01:
		return 0.0
	ship_forward = ship_forward.normalized()
	
	var cross: Vector3 = ship_forward.cross(to_target)
	var dot: float = ship_forward.dot(to_target)
	
	var angle_sign: float = sign(cross.y)
	var angle: float = acos(clamp(dot, -1.0, 1.0))
	
	var steer: float = angle * angle_sign * steering_sensitivity
	
	# Rate limit steering
	var max_change: float = max_steer_rate * delta
	steer = clamp(steer, prev_steer - max_change, prev_steer + max_change)
	prev_steer = steer
	
	return clamp(steer, -1.0, 1.0)

# ============================================================================
# THROTTLE AND BRAKE - LATE BRAKING PHILOSOPHY
# ============================================================================

func _calculate_throttle_and_brake(
	current_speed: float, 
	target_speed: float, 
	max_speed: float,
	max_curvature: float, 
	immediate_curvature: float,
	corner_distance: float, 
	is_s_curve: bool,
	target: Dictionary
) -> Dictionary:
	"""
	Late braking approach:
	- Stay on throttle as long as possible
	- Brake hard and late when needed
	- Get back on throttle early when exiting
	"""
	var speed_error: float = target_speed - current_speed
	var over_target: float = current_speed - target_speed
	var speed_ratio: float = current_speed / max_speed if max_speed > 0 else 0.0
	
	var throttle: float = 0.0
	var brake: float = 0.0
	
	# === PHASE DETECTION ===
	var in_corner: bool = immediate_curvature > 0.2
	var approaching_corner: bool = max_curvature > 0.3 and corner_distance < brake_distance_threshold
	var exiting_corner: bool = in_corner and max_curvature < immediate_curvature * 0.7
	
	# S-curves with good racing line need less braking
	var s_curve_modifier: float = 1.0
	if is_s_curve:
		s_curve_modifier = 0.7  # 30% less braking in S-curves
	
	# === THROTTLE LOGIC ===
	if exiting_corner:
		# CORNER EXIT: Get on throttle early!
		throttle = clamp(0.7 + speed_error * 0.1, 0.5, 1.0)
	elif speed_error > 0:
		# Below target - accelerate
		throttle = clamp(speed_error * throttle_responsiveness, 0.0, 1.0)
	elif over_target < throttle_cutoff_threshold:
		# Slightly over but not dangerous - partial throttle / coast
		var coast_factor: float = 1.0 - (over_target / throttle_cutoff_threshold)
		throttle = clamp(coast_factor * 0.5, 0.0, 0.5)
	
	# === LATE BRAKING LOGIC ===
	# Only brake when we really need to
	
	var need_to_brake: bool = false
	var brake_urgency: float = 0.0
	
	if approaching_corner and not exiting_corner:
		# Calculate if we're going too fast for the upcoming corner
		var speed_excess: float = current_speed - target_speed
		
		if speed_excess > 0:
			# We're over target speed
			if corner_distance < emergency_brake_distance:
				# EMERGENCY: Very close to corner and too fast
				need_to_brake = true
				brake_urgency = clamp(speed_excess / target_speed * 2.0, 0.3, 1.0)
			elif corner_distance < brake_distance_threshold:
				# Within braking zone - calculate required deceleration
				# Simple model: can we slow down in time?
				var distance_to_brake: float = corner_distance - 5.0  # Leave margin
				var required_decel: float = (speed_excess * speed_excess) / (2.0 * max(distance_to_brake, 1.0))
				
				# If required deceleration is high, brake hard
				if required_decel > 5.0:  # Threshold for "needs braking"
					need_to_brake = true
					brake_urgency = clamp(required_decel / 20.0, 0.0, 1.0)
	
	# Also brake if significantly over target in corner
	if in_corner and over_target > brake_threshold:
		need_to_brake = true
		brake_urgency = max(brake_urgency, clamp((over_target - brake_threshold) * brake_intensity, 0.0, 0.8))
	
	# Apply braking
	if need_to_brake:
		brake = brake_urgency * s_curve_modifier
		# Cut throttle when braking hard
		if brake > 0.3:
			throttle = 0.0
		elif brake > 0.1:
			throttle *= 0.5
	
	# === BLEND WITH RECORDED HINTS ===
	var from_recorded: bool = target.from_recorded_data
	if from_recorded and hint_weight > 0:
		var hint_throttle: float = target.hint_throttle
		var hint_brake: float = target.hint_brake
		throttle = lerpf(throttle, hint_throttle, hint_weight)
		brake = lerpf(brake, hint_brake, hint_weight)
	
	return {"throttle": clamp(throttle, 0.0, 1.0), "brake": clamp(brake, 0.0, 1.0)}

# ============================================================================
# AIRBRAKES
# ============================================================================

func _calculate_airbrakes(
	current_speed: float, 
	max_speed: float, 
	steer: float, 
	max_curvature: float, 
	immediate_curvature: float,
	is_s_curve: bool,
	target: Dictionary
) -> Dictionary:
	"""Calculate airbrake inputs for cornering assistance."""
	var result: Dictionary = {"left": 0.0, "right": 0.0}
	
	var speed_ratio: float = current_speed / max_speed if max_speed > 0 else 0.0
	
	if speed_ratio < airbrake_min_speed_ratio:
		return result
	
	var airbrake_intensity: float = 0.0
	var effective_curvature: float = max(max_curvature, immediate_curvature)
	
	# Curvature-based airbrakes
	if effective_curvature > airbrake_curvature_threshold:
		var curvature_factor: float = (effective_curvature - airbrake_curvature_threshold) / (1.0 - airbrake_curvature_threshold)
		curvature_factor = clamp(curvature_factor, 0.0, 1.0)
		airbrake_intensity = curvature_factor * airbrake_curvature_factor
	
	# Steering effort-based airbrakes
	var steer_magnitude: float = abs(steer)
	if steer_magnitude > airbrake_steering_threshold:
		var steer_factor: float = (steer_magnitude - airbrake_steering_threshold) / (1.0 - airbrake_steering_threshold)
		steer_factor = clamp(steer_factor, 0.0, 1.0)
		airbrake_intensity = max(airbrake_intensity, steer_factor * 0.8)
	
	# S-curves: Use less airbrake since racing line is straighter
	if is_s_curve:
		airbrake_intensity *= 0.6
	
	# Scale by speed
	var speed_factor: float = clamp((speed_ratio - airbrake_min_speed_ratio) / (0.8 - airbrake_min_speed_ratio), 0.0, 1.0)
	airbrake_intensity *= speed_factor
	airbrake_intensity = clamp(airbrake_intensity, 0.0, 1.0)
	
	# Apply to appropriate side
	if steer < -0.15:
		result.right = airbrake_intensity
	elif steer > 0.15:
		result.left = airbrake_intensity
	elif effective_curvature > airbrake_curvature_threshold:
		# Light both for general slowing before turn
		result.left = airbrake_intensity * 0.25
		result.right = airbrake_intensity * 0.25
	
	# Blend with recorded hints
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
