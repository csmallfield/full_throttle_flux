@tool
extends Resource
class_name ShipProfile

## Ship Profile Resource
## Defines all tunable parameters for an anti-gravity racing ship.
## Create .tres files from this in resources/ships/

# ============================================================================
# IDENTITY
# ============================================================================

@export_group("Identity")

## Unique identifier for this ship (used for save data, unlocks, etc.)
@export var ship_id: String = "default_racer"

## Display name shown in menus
@export var display_name: String = "Default Racer"

## Ship description for selection screen
@export_multiline var description: String = "A balanced ship suitable for all tracks."

## Manufacturer/team name
@export var manufacturer: String = "Unknown"

## Thumbnail image for selection UI
@export var thumbnail: Texture2D

# ============================================================================
# SHIP SCENE
# ============================================================================

@export_group("Ship Scene")

## The ship scene containing ONLY mesh + collision shape (no controller)
@export var ship_scene: PackedScene

# ============================================================================
# SPEED PARAMETERS
# ============================================================================

@export_group("Speed")

## Maximum velocity the ship can reach under normal thrust.
@export var max_speed: float = 120.0

## How much forward force is applied when accelerating.
@export var thrust_power: float = 65.0

## Velocity retained each physics frame (1.0 = no drag, 0.9 = heavy drag).
@export var drag_coefficient: float = 0.992

## Additional drag applied when ship is airborne.
@export var air_drag: float = 0.97

# ============================================================================
# STEERING PARAMETERS
# ============================================================================

@export_group("Steering")

## How fast the ship rotates when steering (radians per second).
@export var steer_speed: float = 1.345

## Affects the sliding/drifting behavior during turns.
@export var steer_slide: float = 10.0

## How quickly velocity follows the ship's facing direction.
## THIS IS THE KEY HANDLING STAT. Higher = tighter, lower = slidier.
@export var grip: float = 4.0

## Input response curve power. Higher = more precision at small inputs.
@export var steer_curve_power: float = 2.5

# ============================================================================
# AIRBRAKE PARAMETERS
# ============================================================================

@export_group("Airbrakes")

## Rotation speed when using airbrakes (radians per second).
@export var airbrake_turn_rate: float = 0.5

## Grip value while airbraking. LOWER than normal grip = more slide.
@export var airbrake_grip: float = 0.5

## Speed multiplier while airbraking (per frame).
@export var airbrake_drag: float = 0.98

## How quickly grip recovers after releasing airbrakes.
@export var airbrake_slip_falloff: float = 25.0

# ============================================================================
# HOVER PARAMETERS
# ============================================================================

@export_group("Hover")

## Target distance above the track surface.
@export var hover_height: float = 2.0

## Spring force pushing ship toward target height.
@export var hover_stiffness: float = 65.0

## Dampens vertical oscillation.
@export var hover_damping: float = 5.5

## Maximum hover force to prevent physics explosions.
@export var hover_force_max: float = 200.0

## How fast the ship rotates to match track surface angle.
@export var track_align_speed: float = 8.0

## How quickly track normal updates at slope transitions (0-1).
@export var track_normal_smoothing: float = 0.15

## Torque applied for rotational track alignment.
@export var hover_rot_power: float = 20.0

# ============================================================================
# PITCH PARAMETERS (Visual Only)
# ============================================================================

@export_group("Pitch")

## Visual pitch rotation speed (radians per second).
@export var pitch_speed: float = 1.0

## How fast visual pitch returns to neutral when no input.
@export var pitch_return_speed: float = 2.0

## Maximum visual pitch angle in degrees.
@export var max_pitch_angle: float = 10.0

# ============================================================================
# COLLISION PARAMETERS
# ============================================================================

@export_group("Collision")

## Minimum speed for wall scraping sound to trigger.
@export var wall_scrape_min_speed: float = 20.0

## Velocity retained after bouncing off walls (0-1).
@export var wall_bounce_retain: float = 0.9

## How much hitting a wall rotates the ship away.
@export var wall_rotation_force: float = 1.5

## Speed retained while scraping along walls (per frame).
@export var wall_friction: float = 0.9

## Downward force when ship is airborne.
@export var gravity: float = 25.0

## How much gravity affects speed on slopes (0-1).
@export var slope_gravity_factor: float = 0.8

# ============================================================================
# CAMERA SHAKE PARAMETERS
# ============================================================================

@export_group("Camera Shake")

## Enable/disable camera shake on collisions.
@export var collision_shake_enabled: bool = true

## Base shake intensity multiplier for collisions.
@export var shake_intensity: float = 0.3

## Speed threshold for shake to trigger.
@export var shake_speed_threshold: float = 20.0

# ============================================================================
# HOVER ANIMATION PARAMETERS (Visual Only)
# ============================================================================

@export_group("Hover Animation")

## Enable hover animation effects
@export var hover_animation_enabled: bool = true

## Vertical bobbing amplitude (units)
@export var hover_pulse_amplitude: float = 0.15

## Vertical pulse speed (cycles per second)
@export var hover_pulse_speed: float = 0.5

## Minimum pulse intensity at max speed (0-1). 0 = disabled at speed, 1 = full strength always
@export var hover_pulse_min_intensity: float = 0.2

## Maximum yaw wobble angle (degrees)
@export var hover_wobble_yaw: float = 3.0

## Maximum roll wobble angle (degrees)
@export var hover_wobble_roll: float = 2.0

## Yaw oscillation speed (cycles per second)
@export var hover_wobble_speed_yaw: float = 0.3

## Roll oscillation speed (cycles per second)
@export var hover_wobble_speed_roll: float = 0.4

## Speed ratio (0-1) where rumble begins
@export var rumble_speed_threshold: float = 0.6

## Position rumble intensity (units)
@export var rumble_position_intensity: float = 0.03

## Rotation rumble intensity (degrees)
@export var rumble_rotation_intensity: float = 0.8

## Rumble frequency (Hz)
@export var rumble_frequency: float = 20.0
