@tool
extends Resource
class_name AIRacingSample

## AI Racing Sample
## A single recorded sample point from a human play session.
## Contains both line data (used for positioning) and control data (reference hints).

# ============================================================================
# LINE DATA — Used directly for AI positioning
# ============================================================================

## Position along track spline as 0.0–1.0 value
@export var spline_offset: float = 0.0

## Distance from track centerline in meters (negative = left, positive = right)
@export var lateral_offset: float = 0.0

## Velocity magnitude at this point (m/s)
@export var speed: float = 0.0

## Ship facing direction (normalized)
@export var heading: Vector3 = Vector3.FORWARD

## World position when this sample was recorded
@export var world_position: Vector3 = Vector3.ZERO

# ============================================================================
# CONTROL DATA — Reference only, AI makes own decisions
# ============================================================================

## Throttle input at this point (0.0–1.0)
@export var throttle: float = 0.0

## Brake input at this point (0.0–1.0)
@export var brake: float = 0.0

## Left airbrake input (0.0–1.0)
@export var airbrake_left: float = 0.0

## Right airbrake input (0.0–1.0)
@export var airbrake_right: float = 0.0

## Was ship grounded (hovering normally) at this point
@export var is_grounded: bool = true

## Was boost effect active at this point
@export var is_boosting: bool = false

# ============================================================================
# UTILITY
# ============================================================================

static func create_sample(
	p_spline_offset: float,
	p_lateral_offset: float,
	p_speed: float,
	p_heading: Vector3,
	p_world_position: Vector3,
	p_throttle: float = 0.0,
	p_brake: float = 0.0,
	p_airbrake_left: float = 0.0,
	p_airbrake_right: float = 0.0,
	p_is_grounded: bool = true,
	p_is_boosting: bool = false
) -> AIRacingSample:
	var sample = AIRacingSample.new()
	sample.spline_offset = p_spline_offset
	sample.lateral_offset = p_lateral_offset
	sample.speed = p_speed
	sample.heading = p_heading
	sample.world_position = p_world_position
	sample.throttle = p_throttle
	sample.brake = p_brake
	sample.airbrake_left = p_airbrake_left
	sample.airbrake_right = p_airbrake_right
	sample.is_grounded = p_is_grounded
	sample.is_boosting = p_is_boosting
	return sample
