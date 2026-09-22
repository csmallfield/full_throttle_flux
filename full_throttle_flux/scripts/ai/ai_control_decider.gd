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
##
## v9 Changes (AIRBRAKE CORNERING + FEEDFORWARD):
## - AIRBRAKES ARE NOW A CORNERING TOOL. The v3 note below was correct for the
##   v7 ship physics and is WRONG for v8+: airbrake_turn_rate went 0.5 -> 1.0
##   and now scales UP with speed (0.55 -> 1.0 authority), so a pilot holding
##   the inside airbrake has roughly 1.94 rad/s of yaw against 0.94 rad/s from
##   steering alone. Measured over a full AI lap on circuit 7, v8 used the
##   airbrakes for 0.00/0.00 the entire lap and cornered at 28-48 u/s with
##   steering pinned at full lock. The AI was cornering with half the
##   rotational authority the player has.
##   Superseded v3 note: "in this physics, airbraking mid-corner REDUCES
##   achievable path curvature ... airbrakes are for braking, not for turning."
## - STEERING FEEDFORWARD from the baked line's signed curvature. The pure-P
##   law needed accumulated heading error before it would turn, which costs
##   corner entry every single time.
## - THROTTLE NO LONGER ASYMPTOTES BELOW TARGET. The old law
##   (floor + error * 0.1) reached equilibrium where thrust balanced drag
##   *under* the target: measured 117.3 u/s at throttle 0.87 against a target
##   of 120, forever.
## - STUCK RECOVERY. Measured on a wall contact: 35+ seconds at 9 u/s with
##   full lock and full throttle, never recovering.
## - Honest skill effects: skill no longer multiplies speed here (margins are
##   applied in the follower). Skill affects control smoothing (reaction
##   crispness) and adds low-frequency steering wobble at low skill. Same
##   ship limits at every skill level.

# ============================================================================
# TUNING PARAMETERS - STEERING
# ============================================================================

## Steering sensitivity of the pure-pursuit (feedback) term.
## Lower than v3's 10.5 because the feedforward term below now carries the
## steady-state cornering load; this only has to correct the error.
var steering_sensitivity: float = 6.5

## How much the steering error is measured from the VELOCITY vector rather
## than the hull heading. 1.0 = fully compensate for slip, 0.0 = v9 behaviour.
var slip_compensation: float = 1.0

## Below this speed the velocity vector is too noisy to steer by.
var slip_compensation_min_speed: float = 12.0

## Weight of the curvature feedforward term. 1.0 = command exactly the
## steering fraction the baked line's curvature requires at this speed.
var steer_feedforward_gain: float = 1.0

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

## Legacy, no longer used. The v9 law is full throttle under target with a
## continuous lift through the coast band; see _decide_speed().
var throttle_floor_under_target: float = 0.6

# ============================================================================
# TUNING PARAMETERS - AIRBRAKE CORNERING
# ============================================================================

## Fraction of available steering yaw we plan to use before calling on the
## airbrake. Below 1.0 so the airbrake engages while steering still has
## reserve to correct with, rather than only once it is pinned.
var corner_steer_reserve: float = 0.80

## Maximum airbrake application used for CORNERING (not braking).
## MUST match ShipPerformanceModel.corner_airbrake_application, or the baked
## speed profile will plan for curvature this controller does not deliver.
var max_corner_airbrake: float = 0.9

## Below this speed ratio, cornering airbrake is pointless (plenty of steering
## authority at low speed, and the yaw authority scale is at its minimum).
var corner_airbrake_min_ratio: float = 0.30

## Extra cornering airbrake per meter of outward tracking error, to recover a
## line the ship is drifting wide of.
var corner_airbrake_error_gain: float = 0.06

# ============================================================================
# TUNING PARAMETERS - STUCK RECOVERY
# ============================================================================

## Speed below which, at meaningful throttle, we might be stuck on something.
var stuck_speed: float = 18.0

## Seconds below stuck_speed before recovery engages.
var stuck_time_threshold: float = 1.2

## Seconds of recovery behaviour once engaged.
var recovery_duration: float = 1.5

## Throttle during recovery. Reduced so the ship rotates away from a wall
## instead of grinding into it (this physics has no reverse thrust).
var recovery_throttle: float = 0.35

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
var perf_model: ShipPerformanceModel
var skill_level: float = 1.0

var _stuck_time: float = 0.0
var _recovery_time: float = 0.0
var _corner_airbrake: float = 0.0

## Exposed for the trainer and debug overlay.
var last_required_yaw: float = 0.0
var last_available_yaw: float = 0.0
var is_recovering: bool = false

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

func initialize(p_ship: ShipController, p_line_follower: AILineFollower,
		p_perf_model: ShipPerformanceModel = null) -> void:
	ship = p_ship
	line_follower = p_line_follower
	perf_model = p_perf_model
	if perf_model == null and p_ship and p_ship.profile:
		perf_model = ShipPerformanceModel.new(p_ship.profile)
	if perf_model:
		perf_model.corner_airbrake_application = max_corner_airbrake
	_wobble_phase = randf() * TAU
	if line_follower:
		skill_level = line_follower.skill_level
	_update_skill_dependent_params()

func set_skill(skill: float) -> void:
	skill_level = clamp(skill, 0.0, 1.0)
	_update_skill_dependent_params()

func _update_skill_dependent_params() -> void:
	"""Update parameters that vary based on skill level."""
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
	var speed_ratio: float = current_speed / max_speed if max_speed > 0.0 else 0.0

	# --- Yaw budget for this corner ---
	# Signed curvature of the baked line, positive = turning left, matching
	# ShipController.measured_yaw_rate. required = kappa * v.
	var line_kappa: float = target.get("line_curvature_signed", 0.0)
	last_required_yaw = line_kappa * current_speed
	last_available_yaw = perf_model.steer_yaw_rate(current_speed) if perf_model else 1.0

	# --- Stuck detection ---
	_update_stuck_state(current_speed, delta)
	if is_recovering:
		return _recovery_controls(target_world_pos, delta)

	# --- Steering: curvature feedforward + pure-pursuit feedback ---
	var raw_steer: float = _calculate_steering(target_world_pos, delta)

	# Low-skill wobble (honest imperfection, stays within input range)
	if _wobble_amplitude > 0.001:
		raw_steer = clampf(
			raw_steer + sin(_time * steer_wobble_frequency * TAU + _wobble_phase) * _wobble_amplitude,
			-1.0, 1.0
		)

	# --- Speed tracking: throttle + brake ---
	# v9: continuous law with no equilibrium below target. Full throttle while
	# under, lifting linearly across the coast band, braking beyond it.
	var speed_error: float = target_speed - current_speed
	var throttle: float = 1.0
	var brake: float = 0.0

	if speed_error < 0.0:
		var over: float = -speed_error
		throttle = clampf(1.0 - over / maxf(coast_band, 0.01), 0.0, 1.0)
		if over > coast_band:
			brake = clampf((over - coast_band) / brake_response_range, 0.0, 1.0) \
				* max_brake_application
			if over > emergency_overspeed:
				brake = 1.0

	# --- Cornering airbrake ---
	var corner_ab: float = _corner_airbrake_application(current_speed, speed_ratio, target)
	_corner_airbrake = corner_ab

	# --- Understeer recovery (single-side airbrake) ---
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
	
	# Cornering airbrake goes on the INSIDE of the turn. Positive required
	# yaw = turning left = left airbrake (rotate_object_local(UP, +) is left).
	if corner_ab > 0.0:
		if last_required_yaw > 0.0:
			ab_left = maxf(ab_left, corner_ab)
		else:
			ab_right = maxf(ab_right, corner_ab)
	
	if assist > 0.0:
		# steer > 0 = turning left = left airbrake adds yaw in that direction
		if raw_steer > 0.0:
			ab_left = maxf(ab_left, assist)
		else:
			ab_right = maxf(ab_right, assist)

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
# CORNERING AIRBRAKE
# ============================================================================

## How much inside airbrake this corner needs, as an application 0..1.
##
## The corner requires yaw rate kappa * v. Steering supplies steer_yaw_rate(v),
## of which we plan to spend `corner_steer_reserve` so there is authority left
## to correct with. Anything still missing is bought from the airbrake, which
## is exactly the trade a player makes.
func _corner_airbrake_application(speed: float, speed_ratio: float,
		target: Dictionary) -> float:
	if max_corner_airbrake <= 0.0 or perf_model == null:
		return 0.0
	if speed_ratio < corner_airbrake_min_ratio:
		return 0.0
	
	var required: float = absf(last_required_yaw)
	if required < 0.01:
		return 0.0
	
	var budget: float = perf_model.steer_yaw_rate(speed) * corner_steer_reserve
	var shortfall: float = required - budget
	
	# Feedback: if we are already drifting wide of the line, buy more yaw.
	var tracking_error: float = _outward_tracking_error(target)
	if tracking_error > 0.0:
		shortfall += tracking_error * corner_airbrake_error_gain \
				* maxf(perf_model.airbrake_yaw_rate(speed, 1.0), 0.01)
	
	if shortfall <= 0.0:
		return 0.0
	
	var capacity: float = perf_model.airbrake_yaw_rate(speed, 1.0)
	if capacity < 0.01:
		return 0.0
	return clampf(shortfall / capacity, 0.0, max_corner_airbrake)

## Meters the ship sits OUTSIDE the intended line (0 if on or inside it).
func _outward_tracking_error(target: Dictionary) -> float:
	if line_follower == null or not line_follower.spline_helper:
		return 0.0
	var desired: float = target.get("lateral_offset", 0.0)
	var actual: float = line_follower.spline_helper.calculate_lateral_offset(
			ship.global_position, line_follower.current_spline_offset, true)
	# Outward means away from the turn centre: left turn (positive required
	# yaw) drifts to the right, i.e. toward positive lateral.
	var outward: float = (actual - desired) if last_required_yaw > 0.0 else (desired - actual)
	return maxf(outward, 0.0)

# ============================================================================
# STUCK RECOVERY
# ============================================================================

func _update_stuck_state(speed: float, delta: float) -> void:
	if _recovery_time > 0.0:
		_recovery_time -= delta
		is_recovering = _recovery_time > 0.0
		if not is_recovering:
			_stuck_time = 0.0
		return
	
	if speed < stuck_speed and smoothed_throttle > 0.5:
		_stuck_time += delta
	else:
		_stuck_time = maxf(0.0, _stuck_time - delta * 2.0)
	
	if _stuck_time > stuck_time_threshold:
		_recovery_time = recovery_duration
		is_recovering = true

## Rotate toward the line instead of grinding into whatever we hit. Throttle
## is reduced rather than cut: this ship has no reverse, so we still need
## enough drive to pull away once the nose comes round.
func _recovery_controls(target_position: Vector3, delta: float) -> Dictionary:
	var steer: float = _calculate_steering(target_position, delta, false)
	var ab_left: float = 0.0
	var ab_right: float = 0.0
	if steer > 0.0:
		ab_left = 1.0
	else:
		ab_right = 1.0
	
	var s: float = _smoothing_rate * delta
	smoothed_steer = lerpf(smoothed_steer, signf(steer), minf(s, 1.0))
	smoothed_throttle = lerpf(smoothed_throttle, recovery_throttle, minf(s, 1.0))
	smoothed_brake = 0.0
	smoothed_airbrake_left = lerpf(smoothed_airbrake_left, ab_left, minf(s, 1.0))
	smoothed_airbrake_right = lerpf(smoothed_airbrake_right, ab_right, minf(s, 1.0))
	
	return {
		"throttle": smoothed_throttle,
		"brake": 0.0,
		"steer": smoothed_steer,
		"airbrake_left": smoothed_airbrake_left,
		"airbrake_right": smoothed_airbrake_right
	}

# ============================================================================
# STEERING
# ============================================================================

func _calculate_steering(target_position: Vector3, delta: float,
		use_feedforward: bool = true) -> float:
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

	# v10: SLIP COMPENSATION.
	# The ship travels along its VELOCITY vector, not its nose. v9 measured
	# the error between the hull heading and the target, so every degree of
	# slip was an uncorrected path error -- and since v9 made the AI actually
	# slide (18-23% airbrake use), that error became structural. Measuring
	# from the velocity vector instead makes the controller steer the PATH.
	var reference: Vector3 = ship_forward
	if slip_compensation > 0.0 and ship.velocity.length() > slip_compensation_min_speed:
		var vel_dir: Vector3 = ship.velocity
		vel_dir.y = 0.0
		if vel_dir.length_squared() > 0.01:
			vel_dir = vel_dir.normalized()
			# Guard against reversing into a spin: only trust the velocity
			# vector while it still broadly agrees with where we point.
			if vel_dir.dot(ship_forward) > 0.3:
				reference = ship_forward.slerp(vel_dir, slip_compensation).normalized()

	var cross: Vector3 = reference.cross(to_target)
	var dot: float = reference.dot(to_target)

	var angle_sign: float = sign(cross.y)
	var angle: float = acos(clamp(dot, -1.0, 1.0))

	var steer: float = angle * angle_sign * steering_sensitivity
	
	# v9: feedforward. A pure-P law has to accumulate heading error before it
	# will turn, which loses corner entry every time. This commands the
	# steering fraction the line's curvature actually requires at this speed,
	# and leaves the P term to correct what is left.
	if use_feedforward and steer_feedforward_gain > 0.0 and last_available_yaw > 0.01:
		var feedforward: float = clampf(last_required_yaw / last_available_yaw, -1.0, 1.0)
		steer += feedforward * steer_feedforward_gain

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
	return "Controls: T=%.2f B=%.2f S=%.2f AB=L%.2f/R%.2f\nyaw req=%.2f avail=%.2f corner_ab=%.2f%s" % [
		smoothed_throttle,
		smoothed_brake,
		smoothed_steer,
		smoothed_airbrake_left,
		smoothed_airbrake_right,
		last_required_yaw,
		last_available_yaw,
		_corner_airbrake,
		"  [RECOVERING]" if is_recovering else ""
	]
