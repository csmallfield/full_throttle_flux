extends RigidBody3D

# Hover settings
@export var hover_force := 50.0
@export var hover_height := 1.5
@export var hover_damping := 5.0

# Movement settings
@export var thrust_power := 80.0
@export var max_speed := 50.0
@export var air_brake_strength := 3.0
@export var turn_speed := 3.0

# References
@onready var hover_points = $HoverPoints.get_children()

var input_thrust := 0.0
var input_turn := 0.0
var input_brake_left := false
var input_brake_right := false


func _ready():
	# Configure RigidBody
	gravity_scale = 0.0  # We handle gravity via hover force
	linear_damp = 0.5
	angular_damp = 2.0


func _physics_process(delta):
	# Get inputs
	input_thrust = Input.get_axis("ui_down", "ui_up")
	input_turn = Input.get_axis("ui_left", "ui_right")
	input_brake_left = Input.is_action_pressed("ui_focus_prev")  # Q key
	input_brake_right = Input.is_action_pressed("ui_focus_next") # E key
	
	# Apply hover force at each corner
	apply_hover_forces()
	
	# Apply thrust
	apply_thrust()
	
	# Apply steering/air brakes
	apply_steering(delta)
	
	# Align ship to surface
	align_to_surface(delta)


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
	
	# Apply slight downward force when airborne (prevents floating forever)
	if total_compression < 0.1:
		apply_central_force(Vector3.DOWN * 20.0)


func apply_thrust():
	var forward = -global_transform.basis.z
	var current_speed = linear_velocity.dot(forward)
	
	# Only apply thrust if under max speed
	if abs(current_speed) < max_speed:
		var thrust = forward * input_thrust * thrust_power
		apply_central_force(thrust)


func apply_steering(delta):
	# Air brake turning (Wipeout style)
	if input_brake_left or input_brake_right:
		var brake_turn = 0.0
		if input_brake_left:
			brake_turn = air_brake_strength
		if input_brake_right:
			brake_turn = -air_brake_strength
		
		# Apply yaw rotation
		var turn_torque = Vector3.UP * brake_turn
		apply_torque(turn_torque)
		
		# Add drag when braking
		linear_velocity *= 0.98
	else:
		# Normal steering (subtle, mainly for course correction)
		var turn_torque = Vector3.UP * -input_turn * turn_speed
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
