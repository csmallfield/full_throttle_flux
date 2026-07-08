extends RefCounted
class_name AIControlDecider

## AI Control Decider
## Responsible for answering: "How should I control the ship?"
##
## v3 Changes (major rework):
## - BRAKE IS NOW EXECUTED: brake output is merged into BOTH airbrakes, which
##   is the only real brake in this ship physics (there is no brake input on
##   ShipController; v2's brake output was silently discarded).
## - Speed control is a clean tracking law around a DISTANCE-AWARE target
##   speed supplied by AILineFollower (baked profile / perf model). The old
##   phase heuristics (approaching/exiting corner, S-curve modifiers) are
##   gone -- braking points now live in the speed profile itself.
## - Airbrakes no longer trigger from 120m-lookahead curvature (which dragged
##   speed on straights). Steering-assist airbraking only fires as understeer
##   recovery: steering saturated at speed. NOTE: in this physics, airbraking
##   mid-corner REDUCES achievable path curvature (grip drops 4.0 -> 0.5, and
##   the velocity vector can only rotate at `grip` rad/s), so airbrakes are
##   for braking, not for turning. Full-grip full-lock is the fastest way
##   through a corner.
## - Honest skill effects: skill no longer multiplies speed here (margins are
##   applied in the follower). Skill affects control smoothing (reaction
##   crispness) and adds low-frequency steering wobble at low skill. Same
##   ship limits at every skill level.

# ============================================================================
# TUNING PARAMETERS - STEERING
# ============================================================================

## Steering sensitivity (higher = more aggressive steering)
var steering_sensitivity: float = 10.5

## Maximum steering rate of change per second (prevents oscillation)
var max_steer_rate: float = 30.0

# ============================================================================
# TUNING PARAMETERS - SPEED TRACKING
# ============================================================================

## Overspeed (units/s) tolerated with a lifted throttle before braking starts.
var coast_band: float = 4.0

## Overspeed range mapped onto 0..max brake application above the coast band.
## Smaller = snappier braking response.
var brake_response_range: float = 16.0

## Maximum airbrake application from normal braking (1.0 = slam).
var max_brake_application: float = 0.95

## Overspeed beyond which we slam full brakes regardless.
var emergency_overspeed: float = 30.0

## Throttle floor while under target (keeps corner-exit drive strong).
var throttle_floor_under_target: float = 0.6

# ============================================================================
# TUNING PARAMETERS - UNDERSTEER RECOVERY AIRBRAKE
# ============================================================================

## |steer| above this counts as saturated (understeering).
var assist_steer_saturation: float = 0.92

## Steering must be saturated this long (seconds) before assist engages.
var assist_min_saturation_time: float = 0.25

## Minimum speed ratio for assist (pointless at low speed).
var assist_min_speed_ratio: float = 0.45

## Single-side airbrake application during understeer recovery. Keep modest:
## airbraking costs grip, so this trades speed for rotation. 0 disables.
var steering_assist_strength: float = 0.35

# ============================================================================
# TUNING PARAMETERS - HINT WEIGHT (SKILL DEPENDENT, recorded data only)
# ============================================================================

## Base hint weight at skill 0.0 (novice trusts calculations more)
var hint_weight_min: float = 0.3

## Max hint weight at skill 1.0 (expert trusts recordings more)
var hint_weight_max: float = 1.0

## Current computed hint weight
var hint_weight: float = 0.65

# ============================================================================
# SKILL-DEPENDENT CONTROL FEEL
# ============================================================================

## Control smoothing rate range (novice sluggish -> expert crisp).
var smoothing_rate_min: float = 7.0
var smoothing_rate_max: float = 16.0

## Low-frequency steering wobble amplitude at skill 0 (0 at skill 1).
## Honest imperfection: noise within the same input range the player has.
var steer_wobble_amplitude_max: float = 0.05
var steer_wobble_frequency: float = 0.6

# ============================================================================
# STATE
# ============================================================================

var ship: ShipController
var line_follower: AILineFollower
var skill_level: float = 1.0

var _smoothing_rate: float = 16.0
var _wobble_amplitude: float = 0.0
var _wobble_phase: float = 0.0
var _time: float = 0.0
var _steer_saturated_time: float = 0.0

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
	_wobble_phase = randf() * TAU
	if line_follower:
		skill_level = line_follower.skill_level
	_update_skill_dependent_params()

func set_skill(skill: float) -> void:
	skill_level = clamp(skill, 0.0, 1.0)
	_update_skill_dependent_params()

func _update_skill_dependent_params() -> void:
	"""Update parameters that vary based on skill level."""
	hint_weight = lerpf(hint_weight_min, hint_weight_max, skill_level)
	_smoothing_rate = lerpf(smoothing_rate_min, smoothing_rate_max, skill_level)
	_wobble_amplitude = lerpf(steer_wobble_amplitude_max, 0.0, skill_level)

# ============================================================================
# MAIN DECISION FUNCTION
# ============================================================================

func decide_controls(delta: float) -> Dictionary:
	"""Calculate control inputs for this frame."""
	if not ship or not line_follower:
		return _neutral_controls()

	_time += delta

	var current_speed: float = ship.velocity.length()
	var max_speed: float = ship.get_max_speed()
	var target: Dictionary = line_follower.get_target_position(current_speed, max_speed)

	var target_world_pos: Vector3 = target.world_position
	var target_speed: float = target.suggested_speed

	# --- Steering ---
	var raw_steer: float = _calculate_steering(target_world_pos, delta)

	# Low-skill wobble (honest imperfection, stays within input range)
	if _wobble_amplitude > 0.001:
		raw_steer = clampf(
			raw_steer + sin(_time * steer_wobble_frequency * TAU + _wobble_phase) * _wobble_amplitude,
			-1.0, 1.0
		)

	# --- Speed tracking: throttle + brake ---
	var speed_error: float = target_speed - current_speed
	var throttle: float = 0.0
	var brake: float = 0.0

	if speed_error >= 0.0:
		# Under target: drive. Full throttle beyond a small error.
		throttle = clampf(throttle_floor_under_target + speed_error * 0.1,
			throttle_floor_under_target, 1.0)
	else:
		var over: float = -speed_error
		if over <= coast_band:
			# Slightly over: lift and let drag work.
			throttle = lerpf(0.45, 0.0, over / coast_band)
		else:
			# Genuinely over the (distance-aware) target: brake.
			throttle = 0.0
			brake = clampf((over - coast_band) / brake_response_range, 0.0, 1.0) \
				* max_brake_application
			if over > emergency_overspeed:
				brake = 1.0

	# --- Understeer recovery (single-side airbrake) ---
	var speed_ratio: float = current_speed / max_speed if max_speed > 0 else 0.0
	if absf(raw_steer) > assist_steer_saturation and speed_ratio > assist_min_speed_ratio:
		_steer_saturated_time += delta
	else:
		_steer_saturated_time = 0.0

	var assist: float = 0.0
	if steering_assist_strength > 0.0 \
			and _steer_saturated_time > assist_min_saturation_time \
			and brake < 0.2:
		assist = steering_assist_strength

	# --- Merge braking into airbrakes (the only real brake this ship has) ---
	var ab_left: float = brake
	var ab_right: float = brake
	if assist > 0.0:
		# steer > 0 = turning left = left airbrake adds yaw in that direction
		if raw_steer > 0.0:
			ab_left = maxf(ab_left, assist)
		else:
			ab_right = maxf(ab_right, assist)

	# --- Blend with recorded hints (skill dependent, recorded data only) ---
	var from_recorded: bool = target.get("from_recorded_data", false)
	if from_recorded and hint_weight > 0:
		throttle = lerpf(throttle, target.hint_throttle, hint_weight)
		brake = lerpf(brake, target.hint_brake, hint_weight)
		ab_left = lerpf(ab_left, maxf(target.hint_airbrake_left, target.hint_brake), hint_weight)
		ab_right = lerpf(ab_right, maxf(target.hint_airbrake_right, target.hint_brake), hint_weight)

	# --- Smooth controls (rate scales with skill: novice sluggish, expert crisp) ---
	var s: float = _smoothing_rate * delta
	smoothed_steer = lerpf(smoothed_steer, raw_steer, minf(s, 1.0))
	smoothed_throttle = lerpf(smoothed_throttle, throttle, minf(s * 0.8, 1.0))
	smoothed_brake = lerpf(smoothed_brake, brake, minf(s * 1.2, 1.0))
	smoothed_airbrake_left = lerpf(smoothed_airbrake_left, ab_left, minf(s * 1.2, 1.0))
	smoothed_airbrake_right = lerpf(smoothed_airbrake_right, ab_right, minf(s * 1.2, 1.0))

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
	steer = clamp(steer, -1.0, 1.0)
	prev_steer = steer

	return steer

# ============================================================================
# DEBUG
# ============================================================================

func get_debug_info() -> String:
	return "Controls: T=%.2f B=%.2f S=%.2f AB=L%.2f/R%.2f (hint=%.0f%%, smooth=%.0f/s)" % [
		smoothed_throttle,
		smoothed_brake,
		smoothed_steer,
		smoothed_airbrake_left,
		smoothed_airbrake_right,
		hint_weight * 100.0,
		_smoothing_rate
	]
