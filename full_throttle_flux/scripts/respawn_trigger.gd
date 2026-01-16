extends Area3D
class_name RespawnTrigger

## Respawn Trigger Area
## Place these in your track where ships might leave the playable area.
## When a ship enters this area, it will respawn to its last safe position.
##
## Usage:
## 1. Add this scene to your track
## 2. Scale/position the collision shape to cover the danger zone
## 3. Optionally set a custom respawn point

@export_group("Respawn Settings")

## If true, use a custom respawn position instead of the ship's last safe position
@export var use_custom_respawn_point := false

## Custom respawn position (only used if use_custom_respawn_point is true)
## Tip: Use a Marker3D child node and reference its position
@export var custom_respawn_position: Vector3 = Vector3.ZERO

## Custom respawn rotation in degrees (Y rotation only for simplicity)
@export var custom_respawn_rotation_y: float = 0.0

## Optional: Reference to a Marker3D for visual respawn point editing
@export var respawn_marker: Marker3D

@export_group("Debug")

## Show debug prints when triggered
@export var debug_mode := false

func _ready() -> void:
	# Ensure we're set up as an Area3D trigger
	monitoring = true
	monitorable = false
	
	# Connect signal
	body_entered.connect(_on_body_entered)
	
	# Set collision to detect ships (layer 2)
	collision_layer = 0
	collision_mask = 2  # Ships are on layer 2
	
	if debug_mode:
		print("RespawnTrigger ready: ", name)

func _on_body_entered(body: Node3D) -> void:
	if body is ShipController:
		_respawn_ship(body as ShipController)

func _respawn_ship(ship: ShipController) -> void:
	if debug_mode:
		print("RespawnTrigger [%s]: Ship entered, triggering respawn" % name)
	
	if use_custom_respawn_point:
		var position := custom_respawn_position
		
		# If we have a marker, use its position instead
		if respawn_marker:
			position = respawn_marker.global_position
		
		# Build rotation basis from Y rotation
		var rotation := Basis.IDENTITY.rotated(Vector3.UP, deg_to_rad(custom_respawn_rotation_y))
		
		# If marker exists, use its full rotation
		if respawn_marker:
			rotation = respawn_marker.global_transform.basis
		
		ship.respawn(position, rotation)
	else:
		# Use ship's last safe position
		ship.respawn()
