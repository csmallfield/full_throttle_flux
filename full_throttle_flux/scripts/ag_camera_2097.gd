extends Camera3D
class_name AGCamera2097

## WipEout 2097 Style Chase Camera
## Follows the ship with speed-based zoom and smooth tracking
## Now with collision detection to prevent clipping through walls

## Reference to the ship being followed.
## Must be set for camera to function.
@export var ship: ShipController

@export_group("Position")

## Base offset from ship position (X = right, Y = up, Z = behind).
## Higher Y = camera sits higher above ship.
## Higher Z = camera sits further behind ship.
## Typical values: Y = 2.5-4.0, Z = 6.0-10.0
@export var base_offset := Vector3(0, 2.0, 5.0)

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

var shake_offset := Vector3.ZERO
var shake_intensity := 0.0

# Collision state
var collision_distance := 0.0  # Current collision-adjusted distance
var target_collision_distance := 0.0  # Target distance based on raycast

func _physics_process(delta: float) -> void:
	if not ship:
		return
	
	var speed_ratio = ship.get_speed_ratio()
	
	# Calculate desired camera offset with speed-based zoom
	var dynamic_offset = base_offset
	dynamic_offset.z += speed_zoom * speed_ratio
	
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
