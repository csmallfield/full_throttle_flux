extends RigidBody3D

# Hover settings
@export var hover_force := 50.0
@export var hover_height := 1.5
@export var hover_damping := 5.0

# Movement settings
@export var thrust_power := 50.0
@export var reverse_power := 40.0
@export var max_speed := 30.0
@export var air_brake_strength := 15.0
@export var turn_speed := 3.0

# Pitch control
@export var pitch_power := 2.0
@export var max_pitch_angle := 15.0  # Degrees

# Visual effects (banking/pitch)
@export var visual_bank_amount := 15.0  # Degrees of roll when turning
@export var visual_pitch_amount := 10.0  # Degrees of pitch when moving stick
@export var visual_smooth_speed := 8.0  # How fast visual catches up

# Hover pulse effect (add this section)
@export var hover_pulse_amount := 0.10  # How much vertical movement (meters)
@export var hover_pulse_speed := 1.0  # How fast it pulses (Hz)
@export var hover_pulse_min_speed := 0.3  # Pulse strength at max speed (0.0 = none, 1.0 = full)

# References
@onready var hover_points = $HoverPoints.get_children()
@onready var visual_body = $VisualBody

var input_steer := 0.0
var input_pitch := 0.0
var input_thrust := false
var input_reverse := false
var input_airbrake_left := 0.0
var input_airbrake_right := 0.0
var pulse_time := 0.0

func _ready():
	# Configure RigidBody
	gravity_scale = 0.0
	linear_damp = 0.5
	angular_damp = 2.0


func _physics_process(delta):
	# Get inputs - using get_axis for paired actions
	input_steer = Input.get_axis("ship_steer_left", "ship_steer_right")
	input_pitch = Input.get_axis("ship_pitch_up", "ship_pitch_down")
	input_thrust = Input.is_action_pressed("ship_thrust")
	input_reverse = Input.is_action_pressed("ship_reverse")
	input_airbrake_left = Input.get_action_strength("ship_airbrake_left")
	input_airbrake_right = Input.get_action_strength("ship_airbrake_right")
	
	# Apply hover force at each corner
	apply_hover_forces()
	
	# Apply thrust/reverse
	apply_thrust()
	
	# Apply pitch control (physical)
	apply_pitch_control()
	
	# Apply steering/air brakes
	apply_steering(delta)
	
	# Align ship to surface
	align_to_surface(delta)
	
	# Update visual banking/pitch (cosmetic only)
	update_visual_rotation(delta)


func apply_hover_forces():
	var total_compression := 0.0
	
	for raycast in hover_points:
		if raycast.is_colliding():
			var distance = raycast.global_position.distance_to(raycast.get_collision_point())
			var compression = clamp(hover_height - distance, 0.0, hover_height)
			var force_strength = compression * hover_force
			
			# Apply spring force
			var force = raycast.global_transform.basis.y * force_strength
			apply_force(force, raycast.global_position - global_position)
			
			# Add damping
			var velocity_at_point = linear_velocity + angular_velocity.cross(raycast.global_position - global_position)
			var damping_force = -velocity_at_point.y * hover_damping
			apply_force(Vector3.UP * damping_force, raycast.global_position - global_position)
			
			total_compression += compression
	
	# Apply slight downward force when airborne
	if total_compression < 0.1:
		apply_central_force(Vector3.DOWN * 20.0)


func apply_thrust():
	var forward = -global_transform.basis.z
	var current_speed = linear_velocity.dot(forward)
	
	if input_thrust:
		# Forward thrust
		if abs(current_speed) < max_speed:
			var thrust = forward * thrust_power
			apply_central_force(thrust)
	elif input_reverse:
		# Reverse thrust
		if current_speed > -max_speed * 0.5:  # Half speed in reverse
			var thrust = -forward * reverse_power
			apply_central_force(thrust)


func apply_pitch_control():
	# Physical pitch (nose up/down) - subtle effect
	if abs(input_pitch) > 0.1:
		var pitch_torque = global_transform.basis.x * input_pitch * pitch_power
		apply_torque(pitch_torque)


func apply_steering(delta):
	# Air brake turning (triggers)
	var airbrake_input = input_airbrake_left - input_airbrake_left
	
	if abs(airbrake_input) > 0.1:
		var brake_turn = airbrake_input * air_brake_strength
		var turn_torque = Vector3.UP * brake_turn
		apply_torque(turn_torque)
		
		# Add drag when braking
		linear_velocity *= 0.98
	else:
		# Normal steering (left stick horizontal)
		if abs(input_steer) > 0.1:
			var turn_torque = Vector3.UP * -input_steer * turn_speed
			apply_torque(turn_torque)


func align_to_surface(delta):
	# Average normal from all raycasts
	var average_normal := Vector3.ZERO
	var hits := 0
	
	for raycast in hover_points:
		if raycast.is_colliding():
			average_normal += raycast.get_collision_normal()
			hits += 1
	
	if hits > 0:
		average_normal = average_normal.normalized()
		
		# Smoothly rotate ship to match surface
		var target_up = average_normal
		var current_up = global_transform.basis.y
		var rotation_axis = current_up.cross(target_up)
		
		if rotation_axis.length() > 0.01:
			var angle = current_up.angle_to(target_up)
			apply_torque(rotation_axis.normalized() * angle * 10.0)


func update_visual_rotation(delta):
	if not visual_body:
		return
	
	# Update pulse time
	pulse_time += delta
	
	# Calculate speed factor (0.0 at rest, 1.0 at max speed)
	var forward = -global_transform.basis.z
	var current_speed = abs(linear_velocity.dot(forward))
	var speed_factor = clamp(current_speed / max_speed, 0.0, 1.0)
	
	# Calculate pulse strength (stronger when slow, weaker when fast)
	var pulse_strength = lerp(1.0, hover_pulse_min_speed, speed_factor)
	
	# Calculate hover pulse (sine wave)
	var pulse_offset = sin(pulse_time * hover_pulse_speed * TAU) * hover_pulse_amount * pulse_strength
	
	# Calculate target visual rotation
	var target_rotation = Vector3.ZERO
	
	# Banking (roll) from steering input or airbrakes
	var total_turn_input = input_steer + (input_airbrake_right - input_airbrake_left)
	target_rotation.z = -total_turn_input * deg_to_rad(visual_bank_amount)
	
	# Pitch from stick input
	target_rotation.x = input_pitch * deg_to_rad(visual_pitch_amount)
	
	# Smoothly interpolate rotation to target
	visual_body.rotation.x = lerp(visual_body.rotation.x, target_rotation.x, visual_smooth_speed * delta)
	visual_body.rotation.z = lerp(visual_body.rotation.z, target_rotation.z, visual_smooth_speed * delta)
	
	# Apply hover pulse to vertical position
	visual_body.position.y = lerp(visual_body.position.y, pulse_offset, visual_smooth_speed * delta)
