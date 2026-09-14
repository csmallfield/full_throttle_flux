extends RefCounted
class_name ShipPerformanceModel

## Ship Performance Model
## Derives honest performance limits from a ShipProfile plus the actual
## physics implementation in ship_controller.gd. Every constant here is
## traceable to a specific line of the ship physics -- no invented numbers.
##
## Used by AIRacingLineBaker (speed profile) and AILineFollower (geometric
## fallback speed targets). The AI plans with the same limits the player has.

# ============================================================================
# MIRRORS OF ship_controller.gd INTERNALS
# (If you change the ship physics, update these to match.)
# ============================================================================

## _apply_steering(): steer_reduction = lerpf(1.0, 0.7, speed_ratio)
const STEER_HIGH_SPEED_FACTOR := 0.7

## _apply_airbrakes(): dual-brake bonus applies when both airbrakes > 0.25
const DUAL_AIRBRAKE_MIN := 0.25

## _apply_grip(): velocity rotates toward facing at exactly `grip` rad/s.
## v8 made this a true rotation rather than a vector lerp, so this bound is
## now exact rather than approximate; the margin is pure safety.
const GRIP_ROTATION_MARGIN := 0.85

## _apply_airbrakes(): yaw authority scales with speed ratio in v8.
const AIRBRAKE_AUTHORITY_MIN := 0.55

# ============================================================================
# CONFIGURATION
# ============================================================================

## Multiplier on the theoretical corner speed limit. Absorbs modeling error:
## slip transients on corner entry, banking, hover wobble, mid-corner speed
## decay from the grip lerp. 1.0 = theoretical limit, lower = safety margin.
var cornering_confidence: float = 0.98

## Airbrake application assumed when planning braking distances (0-1).
## The control decider can command up to 1.0, so planning at less than that
## builds real margin into every braking zone.
var planned_brake_application: float = 0.7

# ============================================================================
# PROFILE-DERIVED STATE
# ============================================================================

var max_speed_ref: float = 120.0
var thrust_power: float = 65.0
var drag_coefficient: float = 0.617      ## per SECOND as of v8
var steer_speed: float = 1.345
var grip: float = 4.0
var airbrake_drag: float = 0.90          ## per SECOND as of v8
var dual_airbrake_drag: float = 0.30     ## per SECOND as of v8
var airbrake_turn_rate: float = 1.0

## Continuous drag rate lambda, where dv/dt = thrust - lambda * v.
var _drag_lambda: float = 0.0

var tick_rate: float = 60.0
var dt: float = 1.0 / 60.0

## Analytic thrust/drag fixed point, v = thrust / lambda.
## v8 NOTE: ship_controller.gd now enforces profile.max_speed with a soft
## limiter (_apply_speed_limit), so the TRUE top speed is
## min(equilibrium_speed, max_speed). Previously there was no clamp and the
## real top speed was ~134 against a declared max_speed of 120.
var equilibrium_speed: float = 0.0

## Velocity shed per meter traveled while braking at the planned application.
## Closed form from multiplicative per-frame decay (see _recompute()).
var _brake_dv_per_meter: float = 1.0

# ============================================================================
# INITIALIZATION
# ============================================================================

func _init(profile: ShipProfile = null) -> void:
	tick_rate = float(Engine.physics_ticks_per_second)
	dt = 1.0 / tick_rate
	if profile:
		configure(profile)
	else:
		_recompute()

func configure(profile: ShipProfile) -> void:
	max_speed_ref = profile.max_speed
	thrust_power = profile.thrust_power
	drag_coefficient = _as_per_second(profile.drag_coefficient)
	steer_speed = profile.steer_speed
	grip = profile.grip
	airbrake_drag = _as_per_second(profile.airbrake_drag)
	dual_airbrake_drag = _as_per_second(profile.dual_airbrake_drag)
	airbrake_turn_rate = profile.airbrake_turn_rate
	_recompute()

## Mirrors ShipController._migrate_rate() so a legacy per-frame profile is
## modelled the same way the physics actually runs it.
func _as_per_second(value: float) -> float:
	if value > 0.95 and value < 1.0:
		return pow(value, 60.0)
	return clampf(value, 0.0, 1.0)

func _recompute() -> void:
	# v8: drag is a per-second retention, so the continuous model is
	#     dv/dt = thrust - lambda * v,  lambda = -ln(drag_per_second)
	# giving the fixed point v = thrust / lambda.
	if drag_coefficient >= 0.99999 or drag_coefficient <= 0.0:
		_drag_lambda = 0.0001
		equilibrium_speed = max_speed_ref * 2.0  # degenerate profile guard
	else:
		_drag_lambda = -log(drag_coefficient)
		equilibrium_speed = thrust_power / _drag_lambda

	# Braking model. Velocity decays as v(t) = v0 * exp(-lambda_b * t), so
	#     dx = v dt  ->  dv/dx = -lambda_b
	# i.e. a constant velocity loss per meter, exactly as before but now
	# expressed continuously instead of per tick.
	# NOTE: this models longitudinal braking only. The v8 lateral scrub adds
	# further deceleration while actually sliding, so real braking distances
	# are slightly SHORTER than planned here. That direction is safe.
	_brake_dv_per_meter = maxf(brake_lambda(planned_brake_application), 0.05)

## Continuous decay rate (1/s) applied to speed while braking at application b.
func brake_lambda(b: float) -> float:
	b = clampf(b, 0.0, 1.0)
	var retain := lerpf(1.0, airbrake_drag, b)
	if b > DUAL_AIRBRAKE_MIN:
		retain *= lerpf(1.0, dual_airbrake_drag, b)
	retain = clampf(retain * drag_coefficient, 0.0001, 0.9999)
	return -log(retain)

## Retained for callers that still want a per-frame figure.
func brake_frame_multiplier(b: float) -> float:
	return exp(-brake_lambda(b) * dt)

# ============================================================================
# QUERIES
# ============================================================================

## Top speed the AI should plan for on straights.
## respect_profile_max = true caps at profile.max_speed even though the
## physics allows the equilibrium speed (see note on equilibrium_speed).
func top_speed(respect_profile_max: bool = true) -> float:
	if respect_profile_max:
		return minf(equilibrium_speed, max_speed_ref)
	return equilibrium_speed

## Max sustainable speed through a corner of true geometric curvature
## kappa (1/radius, in 1/meters).
##
## Derivation: path curvature = yaw_rate / speed. Full-lock yaw rate from
## _apply_steering() is:
##     omega(v) = steer_speed * (1 - (1 - 0.7) * v / max_speed_ref)
## Solving v * kappa = omega(v) for v:
##     v = steer_speed / (kappa + 0.3 * steer_speed / max_speed_ref)
## Additionally the velocity vector can only rotate as fast as grip allows
## (_apply_grip: at most `grip` rad/s), giving v <= grip * margin / kappa.
func corner_speed(kappa: float, respect_profile_max: bool = true) -> float:
	var cap := top_speed(respect_profile_max)
	if kappa < 0.0001:
		return cap
	# v8: airbrakes contribute real yaw authority (turn rate raised, and it now
	# scales UP with speed instead of staying flat), so corner planning must
	# account for the brake the AI is assumed to be holding.
	var brake_yaw := airbrake_turn_rate * planned_brake_application * AIRBRAKE_AUTHORITY_MIN
	var steer_falloff := (1.0 - STEER_HIGH_SPEED_FACTOR) * steer_speed / maxf(max_speed_ref, 1.0)
	var v_steer := (steer_speed + brake_yaw) / (kappa + steer_falloff)
	var v_grip := (grip * GRIP_ROTATION_MARGIN) / kappa
	var v := minf(v_steer, v_grip) * cornering_confidence
	return clampf(v, 5.0, cap)

## Max speed we may carry NOW given we must be down to v_target after
## `distance` meters of planned braking. Closed form (constant dv per meter).
func max_entry_speed(v_target: float, distance: float) -> float:
	if distance <= 0.0:
		return v_target
	return v_target + distance * _brake_dv_per_meter

## Distance in meters needed to brake from v_from down to v_to.
func braking_distance(v_from: float, v_to: float) -> float:
	if v_from <= v_to:
		return 0.0
	return (v_from - v_to) / _brake_dv_per_meter

## Speed after holding full throttle for `distance` meters starting at v_from.
## Numeric per-frame integration of _apply_thrust + _apply_drag (cheap: a
## handful of frames per baker segment).
func speed_after_full_throttle(v_from: float, distance: float) -> float:
	var v := maxf(v_from, 1.0)
	var cap := top_speed(true)
	var d := 0.0
	var guard := 0
	while d < distance and guard < 100000:
		v += (thrust_power - _drag_lambda * v) * dt
		v = minf(v, cap)  # v8: the speed limiter is real now
		d += v * dt
		guard += 1
	return v

func get_debug_info() -> String:
	return "PerfModel: v_eq=%.1f v_top=%.1f lambda=%.3f brake=%.2f u/m confidence=%.2f" % [
		equilibrium_speed, top_speed(), _drag_lambda,
		_brake_dv_per_meter, cornering_confidence
	]
