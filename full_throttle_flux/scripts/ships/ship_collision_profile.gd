@tool
extends Resource
class_name ShipCollisionProfile

## Ship Collision Profile Resource
## BallisticNG-style arcade collision parameters
## v5: Arcade collision system with velocity transfer and forward-bias

# ============================================================================
# COLLISION CLASSIFICATION
# ============================================================================

@export_group("Classification")

## Angle threshold for rear-end detection (degrees)
## Collision within this angle of directly behind = rear-end
@export_range(0.0, 90.0) var rear_end_angle_threshold: float = 40.0

## Angle threshold for head-on detection (degrees)
## Collision within this angle of directly ahead = head-on
@export_range(0.0, 90.0) var head_on_angle_threshold: float = 50.0

## Speed difference threshold for rear-end classification
## Attacker must be moving this much faster (units/sec)
@export var rear_end_speed_diff_min: float = 5.0

## Minimum closing speed to register as collision (units/sec)
## Below this, ships just gently separate
@export var min_collision_speed: float = 3.0

# ============================================================================
# REAR-END COLLISIONS (Bumper Drafting)
# ============================================================================

@export_group("Rear-End")

## Speed loss for faster ship (0-1, where 1 = total speed loss)
## Lower = bumper drafting is viable
@export_range(0.0, 1.0) var rear_end_attacker_brake: float = 0.12

## Speed gain for slower ship (0-1, multiplier of speed difference)
## Higher = more boost from being rear-ended
@export_range(0.0, 1.0) var rear_end_victim_boost: float = 0.35

## Maximum speed that can be gained from rear-end (units/sec)
@export var rear_end_max_boost: float = 20.0

## Minimum time between rear-end boosts from same ship (seconds)
@export var rear_end_cooldown: float = 0.5

# ============================================================================
# SIDE-SWIPE COLLISIONS
# ============================================================================

@export_group("Side-Swipe")

## Speed loss when ships scrape sides (0-1)
@export_range(0.0, 1.0) var sideswipe_speed_loss: float = 0.08

## Lateral push force when swiping (units/sec)
@export var sideswipe_lateral_force: float = 12.0

## How much lateral force is applied (0-1, 0=none, 1=full)
@export_range(0.0, 1.0) var sideswipe_lateral_strength: float = 0.4

# ============================================================================
# HEAD-ON COLLISIONS
# ============================================================================

@export_group("Head-On")

## Speed loss for both ships in head-on (0-1)
@export_range(0.0, 1.0) var head_on_speed_loss: float = 0.25

## How much ships bounce apart in head-on
@export var head_on_separation_force: float = 18.0

## Head-on collision stun intensity multiplier
@export var head_on_stun_multiplier: float = 1.5

# ============================================================================
# VELOCITY TRANSFER LIMITS
# ============================================================================

@export_group("Velocity Limits")

## Maximum speed gain from any single collision (units/sec)
@export var max_speed_gain: float = 25.0

## Maximum speed loss from any single collision (units/sec)
@export var max_speed_loss: float = 35.0

## Maximum lateral push from any collision (units/sec)
@export var max_lateral_push: float = 15.0

# ============================================================================
# FORWARD-BIAS SYSTEM
# ============================================================================

@export_group("Forward Bias")

## How much to favor forward velocity changes over lateral (0-1)
## 1.0 = all changes projected onto forward vector
## 0.0 = raw physics (not recommended)
@export_range(0.0, 1.0) var forward_bias_strength: float = 0.75

## Lateral damping factor (multiplies lateral velocity changes)
## Lower = less sideways push, more forward racing
@export_range(0.0, 1.0) var lateral_damping: float = 0.3

# ============================================================================
# COLLISION STUN SYSTEM
# ============================================================================

@export_group("Collision Stun")

## Enable grip reduction after significant impacts
@export var stun_enabled: bool = true

## Duration of grip reduction (seconds)
@export var stun_duration: float = 0.35

## Grip multiplier during full stun (0-1)
@export_range(0.0, 1.0) var stun_grip_multiplier: float = 0.25

## Impact speed threshold for full stun effect
@export var stun_speed_threshold: float = 40.0

# ============================================================================
# ROTATION EFFECTS (Optional)
# ============================================================================

@export_group("Rotation")

## Enable rotation on off-center hits
@export var rotation_enabled: bool = true

## Rotation strength multiplier
@export_range(0.0, 2.0) var rotation_strength: float = 0.6

## Maximum rotation per collision (degrees)
@export var max_rotation_degrees: float = 25.0

# ============================================================================
# SUSTAINED CONTACT
# ============================================================================

@export_group("Contact")

## Distance threshold for "in contact" state (meters)
@export var contact_distance: float = 3.5

## Soft separation force when ships overlap slightly
@export var separation_force: float = 15.0

## Maximum separation velocity
@export var max_separation_speed: float = 12.0

## Time without collision before contact state ends (seconds)
@export var contact_timeout: float = 0.15

# ============================================================================
# FEEDBACK
# ============================================================================

@export_group("Feedback")

## Trigger camera shake on collision
@export var shake_enabled: bool = true

## Shake intensity multiplier
@export var shake_intensity: float = 0.4

## Speed threshold for shake (units/sec)
@export var shake_speed_threshold: float = 15.0

## Speed threshold for collision sound (units/sec)
@export var sound_speed_threshold: float = 5.0
