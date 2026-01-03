extends CharacterBody3D
class_name AGShip2097

## WipEout 2097 Style Anti-Gravity Ship Controller
## Based on BallisticNG "2159 Mode" physics specifications

# ============================================================================
# SPEED PARAMETERS
# ============================================================================

@export_group("Speed")

## Maximum velocity the ship can reach under normal thrust.
## Higher values = faster top speed but harder to control.
## Typical range: 400-700. Start with 550 for balanced feel.
@export var max_speed := 550.0

## How much forward force is applied when accelerating.
## Higher = quicker acceleration but can feel twitchy.
## Typical range: 80-150. Balanced ships use ~115.
@export var thrust_power := 115.0

## Velocity retained each physics frame (1.0 = no drag, 0.9 = heavy drag).
## Controls how quickly ship slows when not accelerating.
## Typical range: 0.98-0.995. Lower = more arcade, higher = more momentum.
@export var drag_coefficient := 0.992

## Additional drag applied when ship is airborne (not hovering).
## Should be slightly lower than ground drag for floatier jumps.
## Typical range: 0.96-0.98.
@export var air_drag := 0.97

# ============================================================================
# STEERING PARAMETERS
# ============================================================================

@export_group("Steering")

## How fast the ship rotates when steering (radians per second).
## Higher = more responsive turning but can feel twitchy.
## Low handling ships: 1.4-1.6, Mid: 1.6-1.8, High: 1.8-2.2
@export var steer_speed := 1.7

## Affects the sliding/drifting behavior during turns.
## Higher values create more pronounced slides.
## Typical range: 0.8-1.6. Start with 1.25.
@export var steer_slide := 1.25

## How quickly velocity follows the ship's facing direction.
## THIS IS THE KEY HANDLING STAT. Higher = tighter, lower = slidier.
## Low grip (4.5-5.0) = drifty. High grip (6.0-7.0) = snappy.
## Applied as: velocity.lerp(target_direction, grip * delta)
@export var grip := 5.5

## Input response curve power. Higher = more precision at small inputs.
## 1.0 = linear, 2.0-3.0 = recommended for analog sticks.
## Makes small steering adjustments easier while keeping full range.
@export var steer_curve_power := 2.5

# ============================================================================
# AIRBRAKE PARAMETERS
# ============================================================================

@export_group("Airbrakes")

## Rotation speed when using airbrakes (radians per second).
## Left airbrake rotates left, right rotates right.
## Higher = sharper cornering ability. Range: 2.5-4.0
@export var airbrake_turn_rate := 3.2

## Grip value while airbraking. LOWER than normal grip = more slide.
## This is what creates the drift effect - ship rotates but velocity lags.
## Typical range: 1.5-3.0. Lower = more dramatic drifts.
@export var airbrake_grip := 2.0

## Speed multiplier while airbraking (per frame).
## 1.0 = no slowdown, 0.9 = heavy braking.
## Range: 0.92-0.96. This is how airbrakes scrub speed.
@export var airbrake_drag := 0.94

## How quickly grip recovers after releasing airbrakes.
## Higher = snappier recovery from drift. Lower = longer slides.
## Typical range: 20-30.
@export var airbrake_slip_falloff := 25.0

# ============================================================================
# HOVER PARAMETERS
# ============================================================================

@export_group("Hover")

## Target distance above the track surface.
## Affects how "floaty" the ship feels and collision clearance.
## Typical range: 1.5-2.5 units.
@export var hover_height := 2.0

## Spring force pushing ship toward target height.
## Higher = stiffer hover, less bounce. Lower = softer, more bounce.
## Range: 50-80. Start with 65 for authentic 2097 feel.
@export var hover_stiffness := 65.0

## Dampens vertical oscillation. CRITICAL FOR FEEL.
## LOW values (3-5) = bouncy, floaty (authentic 2097).
## HIGH values (8+) = stiff, locked-in (more modern feel).
## This was the main problem before - too high kills the float.
@export var hover_damping := 5.5

## Maximum hover force to prevent physics explosions.
## Clamps extreme corrections. Keep at 200 unless issues occur.
@export var hover_force_max := 200.0

## How fast the ship rotates to match track surface angle.
## Higher = snappier alignment, lower = smoother over bumps.
## Range: 6-10. Too high can cause jitter on uneven tracks.
@export var track_align_speed := 8.0

## How quickly track normal updates at slope transitions (0-1).
## Lower = smoother transitions, prevents launching at hill bottoms.
## Higher = more responsive to track changes.
## Range: 0.1-0.3. Start with 0.15.
@export var track_normal_smoothing := 0.15

## Torque applied for rotational track alignment.
## Affects how aggressively ship matches banking/slopes.
## Typical range: 15-25.
@export var hover_rot_power := 20.0

# ============================================================================
# PITCH PARAMETERS (Visual Only)
# ============================================================================

@export_group("Pitch")

## Visual pitch rotation speed (radians per second).
## Pitch is VISUAL ONLY - tilts the mesh, doesn't affect physics.
## Affects speed efficiency slightly but ship stays on track.
## Higher = more responsive visual pitch. Range: 2.0-3.5
@export var pitch_speed := 2.8

## How fast visual pitch returns to neutral when no input.
## Higher = quicker return to level. Range: 1.5-2.5
@export var pitch_return_speed := 2.0

## Maximum visual pitch angle in degrees.
## Only affects appearance and speed efficiency.
## Range: 15-30 degrees.
@export var max_pitch_angle := 25.0

# ============================================================================
# COLLISION PARAMETERS
# ============================================================================

@export_group("Collision")

## Velocity retained after bouncing off walls (0-1).
## 1.0 = perfect bounce, 0.5 = loses half speed.
## Range: 0.6-0.75. Authentic feel uses ~0.7.
@export var wall_bounce_retain := 0.7

## How much hitting a wall rotates the ship away.
## Higher = more dramatic spin on impact. Range: 1.5-3.0
@export var wall_rotation_force := 2.0

## Speed retained while scraping along walls (per frame).
## Applied when grinding against wall, not on impact.
## Range: 0.85-0.92.
@export var wall_friction := 0.9

## Downward force when ship is airborne (not hovering).
## Higher = faster fall, less hang time on jumps.
## Typical range: 20-35.
@export var gravity := 25.0

## How much gravity affects speed on slopes (0-1).
## 1.0 = full gravity assist downhill / penalty uphill.
## 0.0 = slopes don't affect speed at all.
## Typical range: 0.5-1.0 for authentic feel.
@export var slope_gravity_factor := 0.8

# ============================================================================
# NODE REFERENCES
# ============================================================================

@onready var ship_mesh: Node3D = $ShipMesh
@onready var hover_ray: RayCast3D = $HoverRay

# ============================================================================
# STATE VARIABLES
# ============================================================================

# Physics state
var is_grounded := false
var time_since_grounded := 0.0
var current_track_normal := Vector3.UP
var smoothed_track_normal := Vector3.UP  # Smoothed version to prevent sudden changes
var ground_distance := 0.0

# Input state
var throttle_input := 0.0
var steer_input := 0.0
var pitch_input := 0.0
var airbrake_left := 0.0
var airbrake_right := 0.0

# Airbrake state
var current_grip := 5.5
var is_airbraking := false

# Visual state (applied to mesh, not physics)
var visual_pitch := 0.0   # Nose up/down visual tilt
var visual_roll := 0.0    # Banking visual tilt
var visual_accel_pitch := 0.0  # Smoothed acceleration pitch feedback

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	current_grip = grip
	smoothed_track_normal = Vector3.UP
	visual_pitch = 0.0
	visual_roll = 0.0
	visual_accel_pitch = 0.0
	_setup_hover_ray()

func _setup_hover_ray() -> void:
	if hover_ray:
		hover_ray.target_position = Vector3.DOWN * (hover_height * 3.0)
		hover_ray.collision_mask = 1  # Track layer only

# ============================================================================
# MAIN PHYSICS LOOP
# ============================================================================

func _physics_process(delta: float) -> void:
	_read_input()
	_update_ground_detection()
	_apply_hover_force(delta)
	_apply_thrust(delta)
	_apply_steering(delta)
	_apply_airbrakes(delta)
	_apply_pitch(delta)
	_apply_drag()
	_align_to_track(delta)
	
	move_and_slide()
	
	_handle_collisions()
	_update_visuals(delta)

# ============================================================================
# INPUT HANDLING
# ============================================================================

func _read_input() -> void:
	throttle_input = Input.get_action_strength("accelerate")
	var brake_input = Input.get_action_strength("brake")
	
	# Brake reduces throttle or applies reverse
	if brake_input > 0:
		throttle_input -= brake_input * 0.5
	
	steer_input = Input.get_axis("steer_right", "steer_left")
	
	# Pitch input (optional - may not be defined)
	pitch_input = 0.0
	if InputMap.has_action("pitch_up") and InputMap.has_action("pitch_down"):
		pitch_input = Input.get_axis("pitch_down", "pitch_up")
	
	airbrake_left = Input.get_action_strength("airbrake_left")
	airbrake_right = Input.get_action_strength("airbrake_right")

# ============================================================================
# GROUND DETECTION
# ============================================================================

func _update_ground_detection() -> void:
	if hover_ray and hover_ray.is_colliding():
		ground_distance = global_position.distance_to(hover_ray.get_collision_point())
		var raw_normal = hover_ray.get_collision_normal()
		
		# Smooth the track normal to prevent sudden changes at slope transitions
		# This is critical for preventing launch at hill bottoms
		smoothed_track_normal = smoothed_track_normal.slerp(raw_normal, track_normal_smoothing)
		current_track_normal = smoothed_track_normal
		
		# Grounded when within threshold
		is_grounded = ground_distance < (hover_height * 1.5)
		
		if is_grounded:
			time_since_grounded = 0.0
	else:
		is_grounded = false
		ground_distance = hover_height * 3.0
		# Gradually return normal to UP when airborne
		smoothed_track_normal = smoothed_track_normal.slerp(Vector3.UP, 0.02)
		current_track_normal = smoothed_track_normal
	
	time_since_grounded += get_physics_process_delta_time()

# ============================================================================
# HOVER SYSTEM (Spring-Damper)
# ============================================================================

func _apply_hover_force(delta: float) -> void:
	if is_grounded:
		# Get velocity component along track normal (how fast we're moving toward/away from track)
		var normal_velocity = velocity.dot(current_track_normal)
		
		# Spring-damper hover force
		var compression = hover_height - ground_distance
		var spring_force = compression * hover_stiffness
		var damping_force = -normal_velocity * hover_damping  # Damp velocity toward track, not world Y
		
		var hover_force = spring_force + damping_force
		hover_force = clamp(hover_force, -hover_force_max, hover_force_max)
		
		# Apply hover force ALONG TRACK NORMAL, not world Y
		# This keeps consistent hover height on slopes
		velocity += current_track_normal * hover_force * delta
		
		# SLOPE GRAVITY: Add gravity component along the track surface
		# This makes downhill faster and uphill slower (authentic feel)
		_apply_slope_gravity(delta)
	else:
		# Apply gravity when airborne (world down)
		velocity.y -= gravity * delta

func _apply_slope_gravity(delta: float) -> void:
	# Project gravity onto the track plane to get slope direction
	# This gives us the "downhill" direction
	var gravity_vec = Vector3.DOWN * gravity * slope_gravity_factor
	
	# Remove the component perpendicular to track (that's what hover handles)
	var normal_component = current_track_normal * gravity_vec.dot(current_track_normal)
	var slope_force = gravity_vec - normal_component
	
	# Apply slope force to velocity (this accelerates downhill, decelerates uphill)
	velocity += slope_force * delta

# ============================================================================
# THRUST SYSTEM
# ============================================================================

func _apply_thrust(delta: float) -> void:
	if throttle_input <= 0:
		return
	
	var thrust_force = thrust_power * throttle_input
	
	# Pitch affects thrust efficiency (visual pitch = less efficient)
	var pitch_efficiency = _calculate_pitch_efficiency()
	thrust_force *= pitch_efficiency
	
	# Get thrust direction - always projected onto track/horizontal plane
	# This ensures thrust can NEVER push the ship upward
	var forward_dir = -global_transform.basis.z
	
	if is_grounded:
		# Project onto track plane
		forward_dir = forward_dir.slide(current_track_normal).normalized()
	else:
		# Project onto horizontal plane when airborne
		forward_dir.y = 0
		if forward_dir.length() > 0.01:
			forward_dir = forward_dir.normalized()
		else:
			forward_dir = -global_transform.basis.z
			forward_dir.y = 0
			forward_dir = forward_dir.normalized()
	
	velocity += forward_dir * thrust_force * delta

func _calculate_pitch_efficiency() -> float:
	# Pitch efficiency based on visual pitch (nose angle)
	# Level = 100% efficiency, pitched up or down = reduced efficiency
	# This rewards keeping the ship level
	
	var pitch_factor = abs(visual_pitch) / deg_to_rad(max_pitch_angle)
	var efficiency = 1.0 - (pitch_factor * 0.3)  # Max 30% penalty at extreme pitch
	return clamp(efficiency, 0.7, 1.0)

# ============================================================================
# STEERING SYSTEM
# ============================================================================

func _apply_steering(delta: float) -> void:
	if abs(steer_input) < 0.01:
		return
	
	# Apply response curve to input
	var curved_input = sign(steer_input) * pow(abs(steer_input), steer_curve_power)
	
	# Speed-dependent steering reduction (optional, feels more realistic)
	var speed_ratio = velocity.length() / max_speed
	var steer_reduction = lerp(1.0, 0.7, speed_ratio)
	
	# Calculate steering rotation
	var steer_torque = curved_input * steer_speed * steer_reduction * delta
	
	# Apply rotation around local Y axis
	rotate_object_local(Vector3.UP, steer_torque)
	
	# Velocity follows rotation based on grip
	# This is the key mechanic - grip determines how tightly velocity follows facing
	_apply_grip(delta)

func _apply_grip(delta: float) -> void:
	var current_speed = velocity.length()
	if current_speed < 1.0:
		return
	
	# Target velocity direction is ship's forward
	var target_dir = -global_transform.basis.z
	var target_velocity = target_dir * current_speed
	
	# Lerp velocity toward target based on grip
	# Higher grip = velocity follows facing more tightly
	var grip_factor = current_grip * delta
	velocity = velocity.lerp(target_velocity, grip_factor)

# ============================================================================
# AIRBRAKE SYSTEM
# ============================================================================

func _apply_airbrakes(delta: float) -> void:
	var brake_amount = max(airbrake_left, airbrake_right)
	is_airbraking = brake_amount > 0.1
	
	if not is_airbraking:
		# Recover grip when not airbraking
		current_grip = lerp(current_grip, grip, airbrake_slip_falloff * delta)
		return
	
	# Airbrake rotation (left brake = turn left, right brake = turn right)
	var brake_rotation = (airbrake_left - airbrake_right) * airbrake_turn_rate * delta
	rotate_object_local(Vector3.UP, brake_rotation)
	
	# Reduce grip while airbraking (creates slide/drift)
	current_grip = lerp(grip, airbrake_grip, brake_amount)
	
	# Apply airbrake drag
	var drag_factor = lerp(1.0, airbrake_drag, brake_amount)
	velocity *= drag_factor
	
	# Check for opposite braking (advanced technique)
	var is_opposite = (airbrake_left > 0.5 and steer_input < -0.3) or \
					  (airbrake_right > 0.5 and steer_input > 0.3)
	if is_opposite:
		# Reduce grip further to hold drift angle
		current_grip *= 0.5
	
	# Full brake (both airbrakes)
	if airbrake_left > 0.25 and airbrake_right > 0.25:
		var full_brake = min(airbrake_left, airbrake_right)
		velocity *= lerp(1.0, 0.85, full_brake)

# ============================================================================
# PITCH SYSTEM (Visual Only)
# ============================================================================

func _apply_pitch(delta: float) -> void:
	# Pitch is now VISUAL ONLY - affects the mesh, not the physics body
	# The physics body stays locked to track alignment
	# Pitch only affects:
	#   1. Visual appearance (mesh tilts)
	#   2. Speed efficiency (calculated elsewhere)
	
	# Only allow pitch input when grounded or very recently grounded
	var can_pitch = is_grounded or time_since_grounded < 0.3
	
	if can_pitch and abs(pitch_input) > 0.1:
		# Accumulate visual pitch
		visual_pitch += pitch_input * pitch_speed * delta
	else:
		# Auto-return to neutral
		var return_speed = pitch_return_speed
		if not is_grounded:
			return_speed *= 2.0  # Faster return when airborne
		visual_pitch = lerp(visual_pitch, 0.0, return_speed * delta)
	
	# Clamp visual pitch
	var max_pitch_rad = deg_to_rad(max_pitch_angle)
	visual_pitch = clamp(visual_pitch, -max_pitch_rad, max_pitch_rad)

# ============================================================================
# DRAG SYSTEM
# ============================================================================

func _apply_drag() -> void:
	var drag = drag_coefficient if is_grounded else air_drag
	
	# Apply drag to horizontal velocity only
	velocity.x *= drag
	velocity.z *= drag

# ============================================================================
# TRACK ALIGNMENT
# ============================================================================

func _align_to_track(delta: float) -> void:
	if not is_grounded:
		return
	
	# Get current and target up vectors
	var current_up = global_transform.basis.y
	var target_up = current_track_normal
	
	# Spherical interpolation for smooth alignment
	var new_up = current_up.slerp(target_up, track_align_speed * delta)
	
	# Rebuild basis with new up vector while preserving forward direction
	var forward = -global_transform.basis.z
	var right = forward.cross(new_up).normalized()
	forward = new_up.cross(right).normalized()
	
	global_transform.basis = Basis(right, new_up, -forward).orthonormalized()

# ============================================================================
# COLLISION HANDLING
# ============================================================================

func _handle_collisions() -> void:
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var normal = collision.get_normal()
		
		# Check if this is a wall (mostly horizontal normal)
		if abs(normal.y) < 0.5:
			_handle_wall_collision(normal)

func _handle_wall_collision(wall_normal: Vector3) -> void:
	var impact_speed = velocity.length()
	
	# Reflect velocity with energy loss
	var reflected = velocity.bounce(wall_normal)
	velocity = reflected * wall_bounce_retain
	
	# Rotate ship away from wall
	var rotate_away = wall_normal.cross(Vector3.UP).dot(-global_transform.basis.z)
	rotate_y(rotate_away * wall_rotation_force * get_physics_process_delta_time())
	
	# Optional: Apply damage based on impact speed
	# var damage = impact_speed * 0.03
	# apply_damage(damage)

# ============================================================================
# VISUAL FEEDBACK
# ============================================================================

func _update_visuals(delta: float) -> void:
	if not ship_mesh:
		return
	
	# Roll based on steering and airbrakes
	var target_roll := 0.0
	target_roll += steer_input * deg_to_rad(25.0)
	target_roll += (airbrake_left - airbrake_right) * deg_to_rad(15.0)
	
	var speed_factor = clamp(velocity.length() / max_speed, 0.3, 1.0)
	target_roll *= speed_factor
	
	# Smooth visual roll
	visual_roll = lerp(visual_roll, target_roll, 8.0 * delta)
	
	# Smooth acceleration pitch feedback (prevents popping)
	var target_accel_pitch = -throttle_input * deg_to_rad(5.0)
	visual_accel_pitch = lerp(visual_accel_pitch, target_accel_pitch, 6.0 * delta)
	
	# Combine visual pitch from input + smoothed acceleration feedback
	var total_pitch = visual_pitch + visual_accel_pitch
	
	# Apply to mesh
	ship_mesh.rotation.x = total_pitch
	ship_mesh.rotation.z = visual_roll

# ============================================================================
# DEBUG / UTILITY
# ============================================================================

func get_speed() -> float:
	return velocity.length()

func get_speed_ratio() -> float:
	return velocity.length() / max_speed

func get_debug_info() -> String:
	return "Speed: %.0f / %.0f\nGrip: %.1f\nGrounded: %s\nAirbrake: %s" % [
		velocity.length(), max_speed, current_grip, is_grounded, is_airbraking
	]
# ============================================================================
## EXTERNAL FORCES (Boost Pads, etc.)
# ============================================================================

## Apply an external boost force in the ship's forward direction.
## This allows speed to exceed max_speed temporarily (drag will bring it back down).
## Called by BoostPad and similar track elements.
func apply_boost(amount: float) -> void:
	var forward = -global_transform.basis.z
	
	# Project onto track plane if grounded for consistent behavior on slopes
	if is_grounded:
		forward = forward.slide(current_track_normal).normalized()
	else:
		# When airborne, use horizontal forward to prevent launching upward
		forward.y = 0
		if forward.length() > 0.01:
			forward = forward.normalized()
		else:
			forward = -global_transform.basis.z
			forward.y = 0
			forward = forward.normalized()
	
	velocity += forward * amount
