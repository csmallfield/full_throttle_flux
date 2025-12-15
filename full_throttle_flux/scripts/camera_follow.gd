extends Camera3D

@export var follow_speed := 5.0
@export var offset := Vector3(0, 3, 8)
@export var look_ahead := 2.0

var ship: RigidBody3D


func _ready():
	ship = get_parent()


func _physics_process(delta):
	# Position behind and above ship
	var target_pos = ship.global_position + ship.global_transform.basis * offset
	global_position = global_position.lerp(target_pos, follow_speed * delta)
	
	# Look at point ahead of ship
	var forward = -ship.global_transform.basis.z
	var look_target = ship.global_position + forward * look_ahead
	look_at(look_target, Vector3.UP)
