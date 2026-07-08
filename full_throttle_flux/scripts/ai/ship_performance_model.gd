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

## _apply_airbrakes(): velocity *= lerpf(1.0, 0.85, full_brake)
const DUAL_AIRBRAKE_FACTOR := 0.85

## _apply_grip(): velocity can rotate at most `grip` rad/s (at full slip);
## we plan with a margin since sin(slip) < 1 in practice.
const GRIP_ROTATION_MARGIN := 0.85

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
var drag_coefficient: float = 0.992
var steer_speed: float = 1.345
var grip: float = 4.0
var airbrake_drag: float = 0.98

var tick_rate: float = 60.0
var dt: float = 1.0 / 60.0

## Analytic top speed: the thrust/drag fixed point v = (v + T*dt) * drag.
## NOTE: ship_controller.gd has NO velocity clamp, so this -- not
## profile.max_speed -- is the true top speed for player and AI alike.
## With default profile values this is ~134, above max_speed (120).
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
	drag_coefficient = profile.drag_coefficient
	steer_speed = profile.steer_speed
	grip = profile.grip
	airbrake_drag = profile.airbrake_drag
	_recompute()

func _recompute() -> void:
	# Thrust/drag equilibrium: v' = (v + thrust*dt) * drag  ->  fixed point
	if drag_coefficient >= 0.99999:
		equilibrium_speed = max_speed_ref * 2.0  # degenerate profile guard
	else:
		equilibrium_speed = (thrust_power * dt * drag_coefficient) / (1.0 - drag_coefficient)

	# Braking model. Per physics frame at application b (throttle off, grounded):
	#   velocity *= lerp(1, airbrake_drag, b)          [airbrake drag]
	#   velocity *= lerp(1, 0.85, b)  if b > 0.25      [dual airbrake bonus]
	#   velocity *= drag_coefficient                   [regular drag]
	# Pure multiplicative decay v_k = v0 * m^k gives a constant velocity loss
	# per meter: distance from v0 to v1 = (v0 - v1) * dt / (1 - m), therefore
	# dv/dm = (1 - m) / dt.
	var m := brake_frame_multiplier(planned_brake_application)
	_brake_dv_per_meter = maxf((1.0 - m) / dt, 0.05)

## Per-frame velocity multiplier while braking at application b (0-1).
func brake_frame_multiplier(b: float) -> float:
	b = clampf(b, 0.0, 1.0)
	var m := lerpf(1.0, airbrake_drag, b)
	if b > DUAL_AIRBRAKE_MIN:
		m *= lerpf(1.0, DUAL_AIRBRAKE_FACTOR, b)
	return m * drag_coefficient

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
	var steer_falloff := (1.0 - STEER_HIGH_SPEED_FACTOR) * steer_speed / maxf(max_speed_ref, 1.0)
	var v_steer := steer_speed / (kappa + steer_falloff)
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
	var d := 0.0
	var guard := 0
	while d < distance and guard < 100000:
		v = (v + thrust_power * dt) * drag_coefficient
		d += v * dt
		guard += 1
	return v

func get_debug_info() -> String:
	return "PerfModel: v_eq=%.1f v_top=%.1f brake=%.1f u/m confidence=%.2f" % [
		equilibrium_speed, top_speed(), _brake_dv_per_meter, cornering_confidence
	]
