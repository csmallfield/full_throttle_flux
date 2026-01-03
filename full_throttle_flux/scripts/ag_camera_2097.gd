extends Camera3D
class_name AGCamera2097

## WipEout 2097 Style Chase Camera
## Follows the ship with speed-based zoom and smooth tracking

## Reference to the ship being followed.
## Must be set for camera to function.
@export var ship: AGShip2097

@export_group("Position")

## Base offset from ship position (X = right, Y = up, Z = behind).
## Higher Y = camera sits higher above ship.
## Higher Z = camera sits further behind ship.
## Typical values: Y = 2.5-4.0, Z = 6.0-10.0
@export var base_offset := Vector3(0, 3.0, 8.0)

## Extra distance added at maximum speed.
## Camera pulls back as you go faster, enhancing sense of speed.
## 0 = no zoom effect, 2-4 = noticeable pullback at top speed.
@export var speed_zoom := 2.0

## How quickly camera moves to target position (units per second factor).
## Higher = snappier following, lower = more floaty/cinematic.
## Range: 4.0-12.0. Start with 8.0 for balanced feel.
@export var follow_speed := 8.0

@export_group("Look")

## How far ahead of the ship to look, based on velocity.
## Creates a sense of anticipation in the direction of travel.
## 0 = look directly at ship, 0.1-0.2 = slight prediction ahead.
@export var look_ahead := 0.1

## How quickly camera rotates to face target (factor per second).
## Higher = snappier rotation, lower = smoother panning.
## Range: 6.0-15.0. Start with 10.0.
@export var look_speed := 10.0

@export_group("Effects")

## Field of view at rest / low speed (degrees).
## Standard FOV, used when ship is slow or stationary.
## Typical range: 60-70.
@export var base_fov := 65.0

## Field of view at maximum speed (degrees).
## FOV increases with speed to enhance sense of velocity.
## Should be higher than base_fov. Typical range: 75-90.
@export var max_fov := 80.0

var shake_offset := Vector3.ZERO
var shake_intensity := 0.0

func _physics_process(delta: float) -> void:
	if not ship:
		return
	
	var speed_ratio = ship.get_speed_ratio()
	
	# Calculate camera offset with speed-based zoom
	var dynamic_offset = base_offset
	dynamic_offset.z += speed_zoom * speed_ratio
	
	# Transform offset to world space based on ship orientation
	# But use a smoothed/stable version of the ship's rotation
	var ship_basis = ship.global_transform.basis
	var target_pos = ship.global_position + ship_basis * dynamic_offset
	
	# Smooth follow
	global_position = global_position.lerp(target_pos, follow_speed * delta)
	
	# Add shake
	global_position += shake_offset
	_update_shake(delta)
	
	# Look at ship with slight prediction
	var look_target = ship.global_position + ship.velocity * look_ahead
	
	# Smooth look
	var current_xform = global_transform
	var target_xform = current_xform.looking_at(look_target, Vector3.UP)
	global_transform = current_xform.interpolate_with(target_xform, look_speed * delta)
	
	# Dynamic FOV
	fov = lerp(base_fov, max_fov, speed_ratio)

func apply_shake(intensity: float) -> void:
	shake_intensity = max(shake_intensity, intensity)

func _update_shake(delta: float) -> void:
	if shake_intensity > 0.01:
		shake_offset = Vector3(
			randf_range(-1, 1),
			randf_range(-1, 1),
			0
		) * shake_intensity
		shake_intensity *= 0.9  # Decay
	else:
		shake_offset = Vector3.ZERO
		shake_intensity = 0.0
