extends Area3D
class_name BoostPad

## Placeable boost pad that accelerates ships passing over it.
## Injects velocity in the ship's forward direction, allowing speeds above max_speed.

@export_group("Boost Settings")

## Velocity units added to ship when triggered.
## Low: 80-120 (gentle push), Medium: 150-200 (noticeable), High: 250+ (major boost)
@export var boost_strength := 150.0

## Cooldown before this pad can boost the same ship again (0 = no cooldown).
## Prevents rapid re-triggering if ship lingers on pad edge.
@export var cooldown_time := 0.5

@export_group("Visuals")

## Base color of the boost pad glow and chevrons.
@export var boost_color := Color(1.0, 0.5, 0.0, 1.0)

## Intensity of the light glow effect.
@export var glow_intensity := 2.0

## Whether to pulse the glow effect.
@export var animate_glow := true

## Pulse speed (cycles per second).
@export var pulse_speed := 2.0

# Internal state
var _cooldown_timers: Dictionary = {}  # ship_id -> time_remaining
var _base_light_energy: float

@onready var glow_light: OmniLight3D = $GlowLight
@onready var chevron_container: Node3D = $ChevronMesh

func _ready() -> void:
	# Connect signal
	body_entered.connect(_on_body_entered)
	
	# Store base energy for animation
	if glow_light:
		_base_light_energy = glow_intensity
		glow_light.light_energy = glow_intensity
		glow_light.light_color = boost_color
	
	# Apply color to chevron material
	_update_chevron_material()

func _process(delta: float) -> void:
	# Update cooldown timers
	var expired_ships: Array = []
	for ship_id in _cooldown_timers:
		_cooldown_timers[ship_id] -= delta
		if _cooldown_timers[ship_id] <= 0:
			expired_ships.append(ship_id)
	for ship_id in expired_ships:
		_cooldown_timers.erase(ship_id)
	
	# Animate glow
	if animate_glow and glow_light:
		var pulse = sin(Time.get_ticks_msec() * 0.001 * pulse_speed * TAU) * 0.3 + 0.7
		glow_light.light_energy = _base_light_energy * pulse

func _on_body_entered(body: Node3D) -> void:
	print("BoostPad: body_entered triggered with: ", body.name)
	
	# Check if it's a ship
	if body is AGShip2097:
		var ship = body as AGShip2097
		var ship_id = ship.get_instance_id()
		
		# Check cooldown
		if ship_id in _cooldown_timers:
			print("BoostPad: Ship on cooldown, ignoring")
			return
		
		print("BoostPad: Applying boost of ", boost_strength, " to ship")
		print("BoostPad: Ship velocity BEFORE: ", ship.velocity, " (", ship.velocity.length(), ")")
		
		# Apply boost
		ship.apply_boost(boost_strength)
		
		print("BoostPad: Ship velocity AFTER: ", ship.velocity, " (", ship.velocity.length(), ")")
		
		# Start cooldown
		if cooldown_time > 0:
			_cooldown_timers[ship_id] = cooldown_time
		
		# Visual feedback
		_play_activation_effect()
	else:
		print("BoostPad: Body is not AGShip2097, it's: ", body.get_class())

func _play_activation_effect() -> void:
	# Flash the light brighter momentarily
	if glow_light:
		var tween = create_tween()
		tween.tween_property(glow_light, "light_energy", glow_intensity * 3.0, 0.05)
		tween.tween_property(glow_light, "light_energy", glow_intensity, 0.2)

func _update_chevron_material() -> void:
	if not chevron_container:
		return
	
	# Create emissive material for chevrons
	var mat = StandardMaterial3D.new()
	mat.albedo_color = boost_color
	mat.emission_enabled = true
	mat.emission = boost_color
	mat.emission_energy_multiplier = 2.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	# Apply to all CSG children
	for child in chevron_container.get_children():
		if child is CSGShape3D:
			child.material = mat

## Called from editor when properties change
func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_update_chevron_material()
