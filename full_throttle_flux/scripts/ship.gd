extends RigidBody3D

# Where to place the car mesh relative to the sphere
var sphere_offset = Vector3.DOWN
# Engine power
var acceleration = 50.0
# Turn amount, in degrees
var steering = 11.0
# How quickly the car turns
var turn_speed = 2.76
# Below this speed, the car doesn't turn
var turn_stop_limit = 0.50

# Variables for input values
var speed_input = 0
var turn_input = 0
var body_tilt = -60

var airbrake_strength = 8.0  # How much extra turn
var airbrake_drag = 0.987  # Speed reduction multiplier when airbraking

@export var hover_height = 0.5

@onready var ship_mesh: Node3D = $shipTest
@onready var body_mesh: Node3D = $shipTest/ship01
@onready var ground_ray: RayCast3D = $shipTest/RayCast3D

# Create a tilt wrapper in code
var tilt_wrapper: Node3D

func _ready():
	# Create wrapper node and reparent the body mesh
	tilt_wrapper = Node3D.new()
	tilt_wrapper.name = "TiltWrapper"
	ship_mesh.add_child(tilt_wrapper)
	
	# Move body_mesh to be a child of tilt_wrapper
	body_mesh.reparent(tilt_wrapper)
	
	# Apply hover height to the wrapper, not the body
	tilt_wrapper.position.y = hover_height
	body_mesh.position.y = 0  # Reset body_mesh to center of wrapper

func _physics_process(delta):
	ship_mesh.position = position + sphere_offset
	if ground_ray.is_colliding():
		apply_central_force(-ship_mesh.global_transform.basis.z * speed_input)

func _process(delta):
	if not ground_ray.is_colliding():
		return
	speed_input = Input.get_axis("brake", "accelerate") * acceleration
	turn_input = Input.get_axis("steer_right", "steer_left") * deg_to_rad(steering)
	
	# Airbrake logic
	var airbrake_input = 0.0
	if Input.is_action_pressed("airbrake_left"):
		airbrake_input = 1.0  # Turn left harder
		linear_velocity *= airbrake_drag  # Apply drag
	elif Input.is_action_pressed("airbrake_right"):
		airbrake_input = -1.0  # Turn right harder
		linear_velocity *= airbrake_drag  # Apply drag
	
	# Combine normal steering with airbrake
	var total_turn = turn_input + (airbrake_input * deg_to_rad(airbrake_strength))
	
	# rotate ship mesh
	if linear_velocity.length() > turn_stop_limit:
		var new_basis = ship_mesh.global_transform.basis.rotated(ship_mesh.global_transform.basis.y, total_turn)
		ship_mesh.global_transform.basis = ship_mesh.global_transform.basis.slerp(new_basis, turn_speed * delta)
		ship_mesh.global_transform = ship_mesh.global_transform.orthonormalized()
		var t = -total_turn * linear_velocity.length() / body_tilt
		tilt_wrapper.rotation.z = lerp(tilt_wrapper.rotation.z, t, 5.0 * delta)
		
		# Ground alignment must be INSIDE the velocity check
		if ground_ray.is_colliding():
			var n = ground_ray.get_collision_normal()
			var xform = align_with_y(ship_mesh.global_transform, n)
			ship_mesh.global_transform = ship_mesh.global_transform.interpolate_with(xform, 10.0 * delta)
		
func align_with_y(xform, new_y):
	xform.basis.y = new_y
	xform.basis.x = -xform.basis.z.cross(new_y)
	xform.basis = xform.basis.orthonormalized()
	return xform.orthonormalized()
