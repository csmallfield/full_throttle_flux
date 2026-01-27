@tool
extends Resource
class_name ShipCollisionProfile

## Ship Collision Profile Resource
## Tunable parameters for ship-to-ship collisions
## v2: Impulse-based physics with contact state tracking

# ============================================================================
# IMPULSE PHYSICS
# ============================================================================

@export_group("Impulse Physics")

## Coefficient of restitution (bounciness): 0 = perfectly inelastic, 1 = perfectly elastic
## WipEout style typically 0.3-0.5 (ships absorb impact, don't bounce off)
@export_range(0.0, 1.0) var restitution: float = 0.4

## Ship's effective mass for collision calculations
## Heavier ships push lighter ones more, are pushed less themselves
@export var collision_mass: float = 1.0

## Friction coefficient for sliding contact (ships rubbing sides)
## Higher = more speed loss when scraping
@export_range(0.0, 1.0) var friction: float = 0.3

# ============================================================================
# COLLISION THRESHOLDS
# ============================================================================

@export_group("Thresholds")

## Minimum closing speed (along collision normal) to trigger impact response
## Below this, only soft separation is applied
@export var min_impact_speed: float = 5.0

## Speed below which collisions are ignored entirely
@export var ignore_speed: float = 2.0

## Distance threshold for "in contact" state (meters)
## Ships closer than this are considered in sustained contact
@export var contact_distance: float = 3.5

# ============================================================================
# SEPARATION FORCES
# ============================================================================

@export_group("Separation")

## Soft separation force for sustained contact (prevents overlap without bouncing)
## Applied continuously while ships are overlapping
@export var separation_force: float = 25.0

## Maximum separation velocity (caps how fast ships push apart)
@export var max_separation_speed: float = 15.0

## How quickly separation force ramps up as ships overlap more
@export var separation_stiffness: float = 2.0

# ============================================================================
# SPIN/ROTATION
# ============================================================================

@export_group("Spin Effects")

## Rotational impulse multiplier on impact
## Higher values = more dramatic spin on contact
@export var spin_impulse_factor: float = 0.8

## Maximum spin rate from a single collision (degrees/second)
@export var max_spin_rate: float = 60.0

## Spin damping during sustained contact (reduces oscillation)
@export_range(0.0, 1.0) var contact_spin_damping: float = 0.5

# ============================================================================
# REAR-END COLLISION TUNING
# ============================================================================

@export_group("Rear-End Collisions")

## How much the faster ship slows down when rear-ending (0-1)
## Higher = more braking effect on the attacker
@export_range(0.0, 1.0) var rear_end_brake_factor: float = 0.6

## How much the slower ship gets pushed forward (0-1)  
## Higher = more boost to the ship being hit from behind
@export_range(0.0, 1.0) var rear_end_push_factor: float = 0.4

## Angle threshold for rear-end detection (degrees from directly behind)
## Hits within this angle of the rear are treated as rear-end collisions
@export_range(0.0, 90.0) var rear_end_angle_threshold: float = 35.0

# ============================================================================
# AUDIO/VISUAL FEEDBACK
# ============================================================================

@export_group("Feedback")

## Trigger camera shake on ship collision
@export var collision_shake_enabled: bool = true

## Shake intensity multiplier for ship collisions
@export var shake_intensity: float = 0.35

## Impact speed threshold for shake effect
@export var shake_speed_threshold: float = 15.0

## Impact speed threshold for collision sound
@export var sound_speed_threshold: float = 1.0

# ============================================================================
# FUTURE: DAMAGE SYSTEM HOOKS
# ============================================================================

@export_group("Damage (Future)")

## Base damage dealt on collision (for future damage meter)
@export var base_collision_damage: float = 10.0

## Damage scales with impact speed
@export var damage_speed_multiplier: float = 0.5
