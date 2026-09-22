@tool
extends Resource
class_name ShipProfile

## Ship Profile Resource
## Defines all tunable parameters for an anti-gravity racing ship.
## Create .tres files from this in resources/ships/
##
## v2 -- TIME-NORMALISED UNITS
## ---------------------------------------------------------------------------
## All decay/retention coefficients are now PER SECOND, not per physics frame.
## Previously `drag_coefficient = 0.992` meant "retain 99.2% of velocity each
## physics tick", making the whole handling model a function of
## Engine.physics_ticks_per_second. Measured: top speed halved from 131 to 66
## when the tick rate was raised from 60 to 120.
##
## Conversion: per_second = per_frame ^ 60
##     0.992 -> 0.617   (drag_coefficient)
##     0.970 -> 0.161   (air_drag)
##     0.980 -> 0.298   (airbrake_drag)
##
## ShipController migrates legacy per-frame values automatically at load and
## logs a warning, so old .tres files keep working. Update them when you can.

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

## Record the player's laps on this ship (LapRecorder).
## Leave OFF while inventing or tuning a profile, and switch it on once the
## ship is a real candidate for the game. Laps from a profile still in flux
## are noise: they rank against a handling model that will not survive.
@export var recordable: bool = false

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

## Maximum velocity under normal thrust. AUTHORITATIVE as of v2: a soft
## limiter holds the ship here, so speed_ratio genuinely reaches 1.0 and no
## higher. Boost may exceed it temporarily (see overspeed_damping).
@export var max_speed: float = 120.0

## Forward force applied when accelerating. Governs how quickly the ship
## reaches max_speed, no longer what the top speed actually is.
@export var thrust_power: float = 65.0

## Velocity retained per SECOND while grounded (see header note on units).
@export var drag_coefficient: float = 0.617

## Velocity retained per SECOND while airborne.
@export var air_drag: float = 0.161

## How quickly overspeed (from boost) bleeds back to max_speed, per second.
## Higher = shorter-lived boost overspeed. 0 disables the limiter entirely.
@export var overspeed_damping: float = 2.5

# ============================================================================
# STEERING PARAMETERS
# ============================================================================

@export_group("Steering")

## How fast the ship rotates when steering (radians per second).
@export var steer_speed: float = 1.345

## Legacy. No longer read by ShipController; kept so old .tres files load.
@export var steer_slide: float = 10.0

## Rate (rad/s) at which the velocity vector rotates toward the ship's facing.
## THIS IS THE KEY HANDLING STAT. Higher = tighter, lower = slidier.
## As of v2 this is applied EVERY frame, not only while steering.
@export var grip: float = 4.0

## Input response curve power. Higher = more precision at small inputs.
@export var steer_curve_power: float = 2.5

## Lateral velocity destroyed per second during normal cornering. This is the
## speed COST of sliding, kept separate from `grip` (which only rotates the
## velocity and preserves its magnitude). Higher = corners scrub more speed.
@export var lateral_scrub: float = 0.8

# ============================================================================
# AIRBRAKE PARAMETERS
# ============================================================================

@export_group("Airbrakes")

## Rotation speed when using airbrakes (radians per second). Raised in v2:
## airbrakes are meant to be the primary cornering tool at racing speed.
@export var airbrake_turn_rate: float = 1.0

## Grip while airbraking. LOWER than normal grip = more slide.
@export var airbrake_grip: float = 0.35

## Velocity retained per SECOND at full airbrake (longitudinal only).
## v1 used 0.98/frame = 0.298/second, which cost 73% of top speed and made the
## airbrake a handbrake. The speed cost now comes mostly from scrub.
@export var airbrake_drag: float = 0.90

## Lateral velocity destroyed per second while airbraking. This makes a big
## slide expensive without punishing a clean, committed turn.
@export var airbrake_lateral_scrub: float = 1.8

## Velocity retained per SECOND when BOTH airbrakes are held (emergency stop).
## v1 used 0.85/frame, i.e. ~0.00006/second -- an instant stop.
@export var dual_airbrake_drag: float = 0.30

## How quickly grip recovers after releasing airbrakes (per second).
@export var airbrake_slip_falloff: float = 6.0

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

## How fast the ship rotates to match track surface angle (per second).
@export var track_align_speed: float = 8.0

## How quickly the track normal is tracked at slope transitions, PER SECOND.
## v2: time-normalised. The old 0.15 was a per-frame lerp weight.
@export var track_normal_smoothing: float = 9.0

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
# VISUAL ROTATION (Aesthetic -- does not affect physics)
# ============================================================================

@export_group("Visual Rotation")

## Hard cap on visual bank angle, degrees. v1 measured 71-80 degrees in corners
## because steering roll (45) and airbrake roll (75) stacked additively.
## WipEout-class craft bank around 25-35.
@export var roll_max_angle: float = 32.0

## Degrees of bank per rad/s of MEASURED yaw rate. Bank now follows what the
## ship is actually doing rather than which button is held.
@export var roll_from_yaw_rate: float = 16.0

## Degrees of bank per radian of slip angle (velocity vs facing). This is what
## makes the bank read as the ship being pushed sideways.
@export var roll_from_slip: float = 30.0

## Degrees of immediate, input-led bank. Small: just enough that the ship
## acknowledges the stick before the yaw rate has built.
@export var roll_from_input: float = 7.0

## Natural frequency of the roll spring, Hz. Higher = snappier bank.
@export var roll_frequency: float = 2.2

## Damping ratio of the roll spring. 1.0 = critical (no overshoot),
## 0.5-0.7 = visible overshoot and settle, which is the "whip" in WipEout.
@export var roll_damping_ratio: float = 0.62

## Fraction of the slip angle applied as visual yaw, so the nose visibly points
## into the slide. 0 = disabled.
@export var visual_yaw_from_slip: float = 0.40

## Cap on that visual yaw, degrees.
@export var visual_yaw_max: float = 9.0

# ============================================================================
# COLLISION PARAMETERS
# ============================================================================

@export_group("Collision")

## Minimum speed for wall scraping sound to trigger.
@export var wall_scrape_min_speed: float = 20.0

## Velocity retained after bouncing off walls (0-1). An impulse, not a rate,
## so it is unaffected by the v2 time normalisation.
@export var wall_bounce_retain: float = 0.9

## How much hitting a wall rotates the ship away.
@export var wall_rotation_force: float = 1.5

## Speed retained while scraping along walls (per frame).
@export var wall_friction: float = 0.9

## --- Ship-to-ship collision ---

## Bounciness of ship-to-ship contact (0 = ships stop dead against each
## other, 1 = fully elastic billiard-ball bounce). ~0.3-0.5 feels arcade-y.
@export var ship_collision_restitution: float = 0.35

## Hard cap on the per-contact velocity change (units/sec) either ship can
## receive from a single ship-to-ship impulse. Prevents physics spikes.
@export var ship_collision_max_impulse: float = 40.0

## Minimum relative closing speed for collision feedback (sound/shake/signal).
## Below this, contact is resolved silently (gentle nudges while pack racing).
@export var ship_collision_feedback_min_speed: float = 5.0

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


# ============================================================================
# HANDLING HASH
# ============================================================================

## Properties that cannot change a lap time: identity, presentation, feedback.
## Everything else that is a number or a bool is treated as handling, so a
## NEW physics field is included automatically -- the safe default is to
## invalidate recordings and trained lines rather than silently keep them.
const NON_HANDLING_PROPERTIES := [
	"ship_id", "display_name", "description", "manufacturer", "thumbnail",
	"ship_scene", "recordable", "steer_slide",
	# visual rotation (mesh only)
	"roll_max_angle", "roll_from_yaw_rate", "roll_from_slip", "roll_from_input",
	"roll_frequency", "roll_damping_ratio", "visual_yaw_from_slip", "visual_yaw_max",
	# camera shake and hover animation (presentation only)
	"collision_shake_enabled", "shake_intensity", "shake_speed_threshold",
	"hover_animation_enabled", "hover_pulse_amplitude", "hover_pulse_speed",
	"hover_pulse_min_intensity", "hover_wobble_yaw", "hover_wobble_roll",
	"hover_wobble_speed_yaw", "hover_wobble_speed_roll", "rumble_speed_threshold",
	"rumble_position_intensity", "rumble_rotation_intensity", "rumble_frequency",
	# audio and feedback thresholds
	"wall_scrape_min_speed", "ship_collision_feedback_min_speed",
]

## Short, stable fingerprint of everything about this profile that can change
## how fast the ship goes round a track. Recordings and trained lines store it
## so that a handling change can never silently compare new laps against old
## ones, or leave the AI driving speeds measured for a different ship.
func handling_hash() -> String:
	var parts: Array[String] = []
	for prop in get_property_list():
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n: String = prop.name
		if n in NON_HANDLING_PROPERTIES:
			continue
		var v = get(n)
		if typeof(v) in [TYPE_FLOAT, TYPE_INT, TYPE_BOOL]:
			parts.append("%s=%s" % [n, str(v)])
	parts.sort()
	return "%08x" % ("|".join(parts).hash() & 0xFFFFFFFF)
