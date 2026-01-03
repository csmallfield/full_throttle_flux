extends Area3D
class_name StartFinishLine

## Detects when ships cross the start/finish line and triggers lap completion.
## Also detects wrong-way crossings.

@export_group("Visual Settings")

## Color of the start/finish line
@export var line_color := Color(1.0, 1.0, 1.0, 0.8)

## Emission intensity for the glowing effect
@export var glow_intensity := 2.0

@export_group("Detection Settings")

## How far ahead/behind the line to check for direction (world units)
@export var direction_check_distance := 5.0

# Internal state
var _last_ship_position: Vector3
var _has_ship_position := false
var _race_started := false

func _ready() -> void:
	# Connect to race manager
	RaceManager.race_started.connect(_on_race_started)
	RaceManager.race_finished.connect(_on_race_finished)
	
	# Connect area signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Update visual material
	_update_visual_material()

func _on_race_started() -> void:
	_race_started = true
	_has_ship_position = false

func _on_race_finished(_total_time: float, _best_lap: float) -> void:
	_race_started = false
	_has_ship_position = false

func _on_body_entered(body: Node3D) -> void:
	if not body is AGShip2097:
		return
	
	var ship = body as AGShip2097
	
	# Store position for direction checking
	if not _has_ship_position:
		_last_ship_position = ship.global_position
		_has_ship_position = true
		return
	
	# Check if ship is moving in correct direction (forward through line)
	var is_forward = _check_crossing_direction(ship)
	
	if is_forward and _race_started:
		# Valid lap completion
		RaceManager.complete_lap()
		_play_crossing_effect()
	elif not is_forward and _race_started:
		# Wrong way!
		RaceManager.wrong_way_warning.emit()
	
	# Update position
	_last_ship_position = ship.global_position

func _on_body_exited(body: Node3D) -> void:
	if body is AGShip2097:
		_last_ship_position = body.global_position

func _check_crossing_direction(ship: AGShip2097) -> bool:
	"""Check if ship crossed in the forward direction"""
	
	# Get the line's forward direction (local -Z in world space)
	var line_forward = -global_transform.basis.z
	
	# Vector from last position to current position
	var movement = ship.global_position - _last_ship_position
	
	# Dot product > 0 means moving in same direction as line forward
	var dot = movement.dot(line_forward)
	
	return dot > 0

func _play_crossing_effect() -> void:
	# Flash the line brighter
	var line_mesh = $LineMesh
	if line_mesh and line_mesh is CSGBox3D:
		var material = line_mesh.material as StandardMaterial3D
		if material:
			var tween = create_tween()
			tween.tween_property(material, "emission_energy_multiplier", glow_intensity * 2.0, 0.1)
			tween.tween_property(material, "emission_energy_multiplier", glow_intensity, 0.3)

func _update_visual_material() -> void:
	var line_mesh = get_node_or_null("LineMesh")
	if not line_mesh or not line_mesh is CSGBox3D:
		return
	
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = line_color
	mat.emission_enabled = true
	mat.emission = Color(line_color.r, line_color.g, line_color.b, 1.0)
	mat.emission_energy_multiplier = glow_intensity
	
	line_mesh.material = mat
