@tool
extends Resource
class_name ShipCollisionProfile

## Ship Collision Profile Resource
## Tunable parameters for ship-to-ship collisions
## Separate from wall collision handling for independent tuning
## Create .tres files from this in resources/ships/

# ============================================================================
# COLLISION RESPONSE
# ============================================================================

@export_group("Collision Response")

## Velocity retained after ship collision (0.0 = full stop, 1.0 = no loss)
## WipEout style typically 0.7-0.85
@export_range(0.0, 1.0) var velocity_retain: float = 0.8

## Additional speed penalty on collision (subtracted from speed)
## Higher values = more punishing collisions
@export var speed_penalty: float = 5.0

## How much the collision pushes ships apart (separation force)
## Higher = more "bouncy" feel
@export var push_force: float = 15.0

## Minimum relative speed required to trigger collision effects
## Prevents micro-collisions at low speed
@export var min_collision_speed: float = 10.0

# ============================================================================
# SPIN/ROTATION
# ============================================================================

@export_group("Spin Effects")

## Rotational force applied on contact (spin-out tendency)
## Higher values = more dramatic spin on contact
@export var spin_force: float = 2.0

## Maximum spin rate from a single collision (degrees/second)
@export var max_spin_rate: float = 90.0

## How much collision angle affects spin (side hits spin more than rear-end)
@export_range(0.0, 1.0) var angle_spin_factor: float = 0.7

# ============================================================================
# MASS/WEIGHT
# ============================================================================

@export_group("Mass System")

## Ship's effective mass for collision calculations
## Heavier ships push lighter ones more
@export var collision_mass: float = 1.0

## Whether to use mass difference in collision response
@export var use_mass_difference: bool = true

# ============================================================================
# AUDIO/VISUAL FEEDBACK
# ============================================================================

@export_group("Feedback")

## Trigger camera shake on ship collision
@export var collision_shake_enabled: bool = true

## Shake intensity multiplier for ship collisions
@export var shake_intensity: float = 0.4

## Speed threshold for shake effect
@export var shake_speed_threshold: float = 25.0

# ============================================================================
# FUTURE: DAMAGE SYSTEM HOOKS
# ============================================================================

@export_group("Damage (Future)")

## Base damage dealt on collision (for future damage meter)
@export var base_collision_damage: float = 10.0

## Damage scales with relative speed
@export var damage_speed_multiplier: float = 0.5
