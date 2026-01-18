extends Camera3D
class_name AGCamera2097

## WipEout 2097 Style Chase Camera
## Follows the ship with speed-based zoom and smooth tracking
## Now with collision detection to prevent clipping through walls
## Lateral swing system for dynamic corner presentation

## Reference to the ship being followed.
## Must be set for camera to function.
@export var ship: ShipController

@export_group("Position")

## Base offset from ship position (X = right, Y = up, Z = behind).
## Higher Y = camera sits higher above ship.
## Higher Z = camera sits further behind ship.
## Typical values: Y = 2.5-4.0, Z = 6.0-10.0
@export var base_offset := Vector3(0, 3.0, 5.5)

## Extra distance added at maximum speed.
## Camera pulls back as you go faster, enhancing sense of speed.
## 0 = no zoom effect, 2-4 = noticeable pullback at top speed.
@export var speed_zoom := 1

## How quickly camera moves to target position (units per second factor).
## Higher = snappier following, lower = more floaty/cinematic.
## Range: 4.0-12.0. Start with 8.0 for balanced feel.
@export var follow_speed := 12.0

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
@export var max_fov := 70.0

@export_group("Lateral Swing")

## Enable lateral camera swing during turns
@export var swing_enabled := true

## Maximum lateral offset at full deflection (units).
## Positive = camera swings right when ship turns right.
## Range: 0.5-4.0. Recommended: 2.0-2.5
@export var swing_max_offset := 0.45

## How much steering input affects swing (0-1).
## Higher = more responsive to input, feels immediate.
@export var swing_input_influence := 0.3

## How much actual rotation affects swing (0-1).
## Higher = follows ship's turning motion more.
@export var swing_rotation_influence := 0.7

## How much airbrakes add to swing effect (0-1).
## Multiplied by airbrake amount. 1.0 = same as full steering.
@export var swing_airbrake_multiplier := 1.2

## How quickly camera swings out when turning (factor per second).
## Higher = snappier response to turns.
## Range: 3.0-10.0. Recommended: 6.0-8.0
@export var swing_out_speed := 3.0

## How quickly camera returns to center when straightening (factor per second).
## Higher = snappier centering, lower = more cinematic drift.
## Range: 2.0-8.0. Recommended: 4.0-5.0
@export var swing_return_speed := 3.0

## Minimum speed ratio for swing to be active (0-1).
## Below this speed, swing is disabled (prevents weird behavior at idle).
@export var swing_min_speed := 0.1

## How much speed affects swing intensity (0-1).
## 0 = constant swing at all speeds above minimum
## 1 = linear scaling from min speed to max speed (more dramatic at high speed)
@export var swing_speed_scaling := 0.4

@export_group("Collision")

## Enable camera collision detection to prevent clipping through walls.
@export var collision_enabled := true

## How much to pull the camera back from collision point (safety margin).
## Prevents camera from touching the wall exactly. Range: 0.1-0.5
@export var collision_margin := 0.3

## How quickly camera returns to normal distance after collision (factor per second).
## Higher = snappier return, lower = smoother. Range: 3.0-10.0
@export var collision_recovery_speed := 5.0

## Collision mask - which layers the camera should collide with.
## Layer 1 = track surface, Layer 3 = walls. Mask 5 = both (1 + 4).
@export_flags_3d_physics var collision_mask := 5

# Shake state
var shake_offset := Vector3.ZERO
var shake_intensity := 0.0

# Collision state
var collision_distance := 0.0  # Current collision-adjusted distance
var target_collision_distance := 0.0  # Target distance based on raycast

# Swing state
var current_swing := 0.0  # Current lateral offset
var last_ship_yaw := 0.0  # Track rotation for rate calculation

func _ready() -> void:
	if ship:
		last_ship_yaw = ship.rotation.y

func _physics_process(delta: float) -> void:
	if not ship:
		return
	
	var speed_ratio = ship.get_speed_ratio()
	
	# Calculate lateral swing
	var swing_offset_x := 0.0
	if swing_enabled:
		swing_offset_x = _calculate_swing(delta, speed_ratio)
	
	# Calculate desired camera offset with speed-based zoom
	var dynamic_offset = base_offset
	dynamic_offset.z += speed_zoom * speed_ratio
	dynamic_offset.x += swing_offset_x  # Add lateral swing
	
	# Transform offset to world space based on ship orientation
	var ship_basis = ship.global_transform.basis
	var desired_pos = ship.global_position + ship_basis * dynamic_offset
	
	# Apply collision detection if enabled
	var final_target_pos = desired_pos
	if collision_enabled:
		final_target_pos = _apply_collision_detection(ship.global_position, desired_pos, dynamic_offset.length())
	
	# Smooth follow to final position
	global_position = global_position.lerp(final_target_pos, follow_speed * delta)
	
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

func _calculate_swing(delta: float, speed_ratio: float) -> float:
	# Below minimum speed, disable swing
	if speed_ratio < swing_min_speed:
		current_swing = lerp(current_swing, 0.0, swing_return_speed * delta)
		return current_swing
	
	# Calculate speed scaling factor
	# At min speed = 1.0, at max speed = 1.0 + swing_speed_scaling
	var speed_factor = 1.0
	if speed_ratio > swing_min_speed:
		var normalized_speed = (speed_ratio - swing_min_speed) / (1.0 - swing_min_speed)
		speed_factor = 1.0 + (normalized_speed * swing_speed_scaling)
	
	# Component 1: Steering input (immediate, responsive)
	var input_component = ship.steer_input * swing_input_influence
	
	# Component 2: Rotation rate (measured turn speed)
	var current_yaw = ship.rotation.y
	var yaw_delta = _angle_difference(current_yaw, last_ship_yaw)
	last_ship_yaw = current_yaw
	
	# Convert yaw rate to normalized steering-like value (-1 to 1)
	# Typical max turn rate is about 1.5 rad/s, so we scale by that
	var rotation_rate = yaw_delta / delta
	var normalized_rotation = clamp(rotation_rate / 1.5, -1.0, 1.0)
	var rotation_component = normalized_rotation * swing_rotation_influence
	
	# Component 3: Airbrakes add extra swing in their direction
	var airbrake_component = 0.0
	if ship.airbrake_left > 0.1 or ship.airbrake_right > 0.1:
		# Left airbrake = negative (camera swings left)
		# Right airbrake = positive (camera swings right)
		airbrake_component = (ship.airbrake_right - ship.airbrake_left) * swing_airbrake_multiplier
	
	# Combine all components
	var target_swing = (input_component + rotation_component + airbrake_component) * swing_max_offset * speed_factor
	
	# Smooth interpolation with different speeds for engaging vs returning
	var swing_speed: float
	if abs(target_swing) > abs(current_swing):
		# Swinging out - use faster speed
		swing_speed = swing_out_speed
	else:
		# Returning to center - use slower speed for cinematic feel
		swing_speed = swing_return_speed
	
	current_swing = lerp(current_swing, target_swing, swing_speed * delta)
	
	return current_swing

func _angle_difference(angle1: float, angle2: float) -> float:
	"""Calculate shortest angular difference between two angles."""
	var diff = angle1 - angle2
	# Normalize to -PI to PI range
	while diff > PI:
		diff -= TAU
	while diff < -PI:
		diff += TAU
	return diff

func _apply_collision_detection(ship_pos: Vector3, desired_cam_pos: Vector3, desired_distance: float) -> Vector3:
	# Cast ray from ship to desired camera position
	var space_state = get_world_3d().direct_space_state
	
	var query = PhysicsRayQueryParameters3D.new()
	query.from = ship_pos
	query.to = desired_cam_pos
	query.collision_mask = collision_mask
	query.exclude = [ship]  # Don't collide with the ship itself
	
	var result = space_state.intersect_ray(query)
	
	if result:
		# Hit something! Calculate safe camera position
		var hit_point = result.position
		var hit_distance = ship_pos.distance_to(hit_point)
		
		# Pull back by collision_margin to avoid touching the wall
		var safe_distance = max(hit_distance - collision_margin, 0.5)  # Minimum 0.5 units from ship
		target_collision_distance = safe_distance
	else:
		# No collision, use full desired distance
		target_collision_distance = desired_distance
	
	# Smoothly interpolate current collision distance toward target
	collision_distance = lerp(collision_distance, target_collision_distance, collision_recovery_speed * get_physics_process_delta_time())
	
	# If we're collision-limited, place camera at the safe distance
	if collision_distance < desired_distance - 0.1:
		# Camera is being pushed in by collision
		var direction = (desired_cam_pos - ship_pos).normalized()
		return ship_pos + direction * collision_distance
	else:
		# No collision affecting us, use desired position
		return desired_cam_pos

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
