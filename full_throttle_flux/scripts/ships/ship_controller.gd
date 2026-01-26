extends CharacterBody3D
class_name ShipController

## WipEout 2097 Style Anti-Gravity Ship Controller
## Based on BallisticNG "2159 Mode" physics specifications
## Refactored to use ShipProfile for data-driven configuration.
## v2: Improved ship-to-ship collision handling with impulse-based physics

# ============================================================================
# SIGNALS
# ============================================================================

signal ship_respawned()
signal ship_collision(other_ship: ShipController, impact_speed: float)

# ============================================================================
# PROFILE
# ============================================================================

## Ship profile containing all gameplay attributes
@export var profile: ShipProfile

## Ship collision profile for ship-to-ship interactions (optional)
@export var collision_profile: ShipCollisionProfile

# ============================================================================
# EXTERNAL REFERENCES (set at runtime or via editor)
# ============================================================================

## Reference to the camera for shake effects
@export var camera: Node3D

## Reference to audio controller
@export var audio_controller: ShipAudioController

# ============================================================================
# RESPAWN SETTINGS
# ============================================================================

@export_group("Respawn")

## Y position below which the ship will respawn
@export var respawn_y_threshold: float = -100.0

## How often to save safe position while grounded (seconds)
@export var safe_position_save_interval: float = 0.3

# ============================================================================
# NODE REFERENCES (found automatically)
# ============================================================================

var ship_mesh: Node3D
var hover_ray: RayCast3D

# ============================================================================
# STATE VARIABLES
# ============================================================================

# Physics state
var is_grounded := false
var time_since_grounded := 0.0
var current_track_normal := Vector3.UP
var smoothed_track_normal := Vector3.UP
var ground_distance := 0.0

# Input state
var throttle_input := 0.0
var steer_input := 0.0
var pitch_input := 0.0
var airbrake_left := 0.0
var airbrake_right := 0.0

# Airbrake state
var current_grip: float
var is_airbraking := false

# Visual state (applied to mesh, not physics)
var visual_pitch := 0.0
var visual_roll := 0.0
var visual_accel_pitch := 0.0

# Hover animation state
var hover_time_accumulator := 0.0
var hover_yaw_accumulator := 0.0
var hover_roll_accumulator := 0.0
var rumble_time := 0.0

# Wall scraping state for audio
var _is_scraping_wall := false
var _scrape_timer := 0.0
const SCRAPE_TIMEOUT := 0.1

# Control lock state (for race end)
var controls_locked := false

# Respawn state
var last_safe_position := Vector3.ZERO
var last_safe_rotation := Basis.IDENTITY
var _safe_position_timer := 0.0

# AI control state
var ai_controlled: bool = false

## Reference to track respawn manager (set by mode)
var respawn_manager: TrackRespawnManager = null

# ============================================================================
# SHIP COLLISION STATE (v2 - Contact Tracking)
# ============================================================================

# Contact state tracking - tracks which ships we're currently in contact with
# Key: ship instance_id, Value: ContactState dictionary
var _ship_contacts: Dictionary = {}

# Contact state structure (stored in _ship_contacts)
# {
#   "ship": ShipController reference,
#   "in_contact": bool,
#   "contact_time": float,        # How long we've been in contact
#   "last_impact_time": float,    # Time since last collision detected
#   "impact_cooldown": float,     # Remaining cooldown before next impact
# }

const IMPACT_COOLDOWN_TIME := 0.25  # Time between impact impulses on same ship
const CONTACT_TIMEOUT := 0.15       # Time without collision before contact ends
const MIN_CONTACT_TIME_FOR_RUBBING := 0.05  # Must be in contact this long for "rubbing" mode

# ============================================================================
# CACHED PROFILE VALUES (for performance)
# ============================================================================

var max_speed: float:
	get:
		return _max_speed

var _max_speed: float
var _thrust_power: float
var _drag_coefficient: float
var _air_drag: float
var _steer_speed: float
var _grip: float
var _steer_curve_power: float
var _airbrake_turn_rate: float
var _airbrake_grip: float
var _airbrake_drag: float
var _airbrake_slip_falloff: float
var _hover_height: float
var _hover_stiffness: float
var _hover_damping: float
var _hover_force_max: float
var _track_align_speed: float
var _track_normal_smoothing: float
var _pitch_speed: float
var _pitch_return_speed: float
var _max_pitch_angle: float
var _wall_scrape_min_speed: float
var _wall_bounce_retain: float
var _wall_rotation_force: float
var _gravity: float
var _slope_gravity_factor: float
var _collision_shake_enabled: bool
var _shake_intensity: float
var _shake_speed_threshold: float

# Hover animation cached values
var _hover_animation_enabled: bool
var _hover_pulse_amplitude: float
var _hover_pulse_speed: float
var _hover_pulse_min_intensity: float
var _hover_wobble_yaw: float
var _hover_wobble_roll: float
var _hover_wobble_speed_yaw: float
var _hover_wobble_speed_roll: float
var _rumble_speed_threshold: float
var _rumble_position_intensity: float
var _rumble_rotation_intensity: float
var _rumble_frequency: float

# Ship collision cached values (v2 - Impulse-based)
var _ship_restitution: float = 0.4
var _ship_collision_mass: float = 1.0
var _ship_friction: float = 0.3
var _ship_min_impact_speed: float = 5.0
var _ship_ignore_speed: float = 2.0
var _ship_contact_distance: float = 3.5
var _ship_separation_force: float = 25.0
var _ship_max_separation_speed: float = 15.0
var _ship_separation_stiffness: float = 2.0
var _ship_spin_impulse_factor: float = 0.8
var _ship_max_spin_rate: float = 60.0
var _ship_contact_spin_damping: float = 0.5
var _ship_rear_end_brake_factor: float = 0.6
var _ship_rear_end_push_factor: float = 0.4
var _ship_rear_end_angle_threshold: float = 35.0
var _ship_shake_enabled: bool = true
var _ship_shake_intensity: float = 0.35
var _ship_shake_speed_threshold: float = 15.0
var _ship_sound_speed_threshold: float = 10.0

# ============================================================================
# INITIALIZATION
# ============================================================================

func _ready() -> void:
	_find_child_nodes()
	_apply_profile()
	_apply_collision_profile()
	_setup_hover_ray()
	_setup_audio_controller()
	_setup_ship_collision_layer()
	
	# Initialize safe position to starting position
	last_safe_position = global_position
	last_safe_rotation = global_transform.basis

func _find_child_nodes() -> void:
	ship_mesh = get_node_or_null("ShipMesh")
	hover_ray = get_node_or_null("HoverRay") as RayCast3D
	
	if not ship_mesh:
		push_warning("ShipController: No ShipMesh child found - visuals will be limited")
	if not hover_ray:
		push_warning("ShipController: No HoverRay child found - creating one")
		hover_ray = RayCast3D.new()
		hover_ray.name = "HoverRay"
		add_child(hover_ray)

func _apply_profile() -> void:
	if not profile:
		push_error("ShipController: No profile assigned!")
		_set_default_values()
		return
	
	_max_speed = profile.max_speed
	_thrust_power = profile.thrust_power
	_drag_coefficient = profile.drag_coefficient
	_air_drag = profile.air_drag
	_steer_speed = profile.steer_speed
	_grip = profile.grip
	_steer_curve_power = profile.steer_curve_power
	_airbrake_turn_rate = profile.airbrake_turn_rate
	_airbrake_grip = profile.airbrake_grip
	_airbrake_drag = profile.airbrake_drag
	_airbrake_slip_falloff = profile.airbrake_slip_falloff
	_hover_height = profile.hover_height
	_hover_stiffness = profile.hover_stiffness
	_hover_damping = profile.hover_damping
	_hover_force_max = profile.hover_force_max
	_track_align_speed = profile.track_align_speed
	_track_normal_smoothing = profile.track_normal_smoothing
	_pitch_speed = profile.pitch_speed
	_pitch_return_speed = profile.pitch_return_speed
	_max_pitch_angle = profile.max_pitch_angle
	_wall_scrape_min_speed = profile.wall_scrape_min_speed
	_wall_bounce_retain = profile.wall_bounce_retain
	_wall_rotation_force = profile.wall_rotation_force
	_gravity = profile.gravity
	_slope_gravity_factor = profile.slope_gravity_factor
	_collision_shake_enabled = profile.collision_shake_enabled
	_shake_intensity = profile.shake_intensity
	_shake_speed_threshold = profile.shake_speed_threshold
	
	# Hover animation parameters
	_hover_animation_enabled = profile.hover_animation_enabled
	_hover_pulse_amplitude = profile.hover_pulse_amplitude
	_hover_pulse_speed = profile.hover_pulse_speed
	_hover_pulse_min_intensity = profile.hover_pulse_min_intensity
	_hover_wobble_yaw = profile.hover_wobble_yaw
	_hover_wobble_roll = profile.hover_wobble_roll
	_hover_wobble_speed_yaw = profile.hover_wobble_speed_yaw
	_hover_wobble_speed_roll = profile.hover_wobble_speed_roll
	_rumble_speed_threshold = profile.rumble_speed_threshold
	_rumble_position_intensity = profile.rumble_position_intensity
	_rumble_rotation_intensity = profile.rumble_rotation_intensity
	_rumble_frequency = profile.rumble_frequency
	
	current_grip = _grip

func _apply_collision_profile() -> void:
	"""Apply ship collision profile values (v2 - Impulse-based)."""
	if not collision_profile:
		# Use defaults (already set in variable declarations)
		return
	
	_ship_restitution = collision_profile.restitution
	_ship_collision_mass = collision_profile.collision_mass
	_ship_friction = collision_profile.friction
	_ship_min_impact_speed = collision_profile.min_impact_speed
	_ship_ignore_speed = collision_profile.ignore_speed
	_ship_contact_distance = collision_profile.contact_distance
	_ship_separation_force = collision_profile.separation_force
	_ship_max_separation_speed = collision_profile.max_separation_speed
	_ship_separation_stiffness = collision_profile.separation_stiffness
	_ship_spin_impulse_factor = collision_profile.spin_impulse_factor
	_ship_max_spin_rate = collision_profile.max_spin_rate
	_ship_contact_spin_damping = collision_profile.contact_spin_damping
	_ship_rear_end_brake_factor = collision_profile.rear_end_brake_factor
	_ship_rear_end_push_factor = collision_profile.rear_end_push_factor
	_ship_rear_end_angle_threshold = collision_profile.rear_end_angle_threshold
	_ship_shake_enabled = collision_profile.collision_shake_enabled
	_ship_shake_intensity = collision_profile.shake_intensity
	_ship_shake_speed_threshold = collision_profile.shake_speed_threshold
	_ship_sound_speed_threshold = collision_profile.sound_speed_threshold

func _set_default_values() -> void:
	_max_speed = 120.0
	_thrust_power = 65.0
	_drag_coefficient = 0.992
	_air_drag = 0.97
	_steer_speed = 1.345
	_grip = 4.0
	_steer_curve_power = 2.5
	_airbrake_turn_rate = 0.5
	_airbrake_grip = 0.5
	_airbrake_drag = 0.98
	_airbrake_slip_falloff = 25.0
	_hover_height = 2.0
	_hover_stiffness = 65.0
	_hover_damping = 5.5
	_hover_force_max = 200.0
	_track_align_speed = 8.0
	_track_normal_smoothing = 0.15
	_pitch_speed = 1.0
	_pitch_return_speed = 2.0
	_max_pitch_angle = 10.0
	_wall_scrape_min_speed = 20.0
	_wall_bounce_retain = 0.9
	_wall_rotation_force = 1.5
	_gravity = 25.0
	_slope_gravity_factor = 0.8
	_collision_shake_enabled = true
	_shake_intensity = 0.3
	_shake_speed_threshold = 20.0
	
	# Hover animation defaults
	_hover_animation_enabled = true
	_hover_pulse_amplitude = 0.15
	_hover_pulse_speed = 0.5
	_hover_pulse_min_intensity = 0.2
	_hover_wobble_yaw = 3.0
	_hover_wobble_roll = 2.0
	_hover_wobble_speed_yaw = 0.3
	_hover_wobble_speed_roll = 0.4
	_rumble_speed_threshold = 0.6
	_rumble_position_intensity = 0.03
	_rumble_rotation_intensity = 0.8
	_rumble_frequency = 20.0
	
	current_grip = _grip

func _setup_hover_ray() -> void:
	if hover_ray:
		hover_ray.target_position = Vector3.DOWN * (_hover_height * 3.0)
		hover_ray.collision_mask = 1

func _setup_audio_controller() -> void:
	if not audio_controller:
		audio_controller = get_node_or_null("ShipAudioController")
	
	if audio_controller:
		audio_controller.ship = self

func _setup_ship_collision_layer() -> void:
	"""Enable ship-to-ship collisions."""
	# Ships are on layer 2, walls on layer 4 (value 4 = bit 2)
	# Current mask is 5 = ground (1) + walls (4)
	# Add ship layer (2) to detect other ships: 5 + 2 = 7
	if collision_mask & 2 == 0:
		collision_mask = collision_mask | 2
		# Note: Ships must also be ON layer 2 for mutual detection
		# This should already be set in the scene (collision_layer = 2)

# ============================================================================
# MAIN PHYSICS LOOP
# ============================================================================

func _physics_process(delta: float) -> void:
	_read_input()
	_update_ground_detection()
	_update_safe_position(delta)
	_check_respawn_needed()
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
	_update_scrape_audio(delta)
	_update_ship_contacts(delta)

# ============================================================================
# INPUT HANDLING
# ============================================================================

func _read_input() -> void:
	# AI SUPPORT: Skip input reading when AI controlled
	# AI sets throttle_input, steer_input, etc. directly
	if ai_controlled:
		return
	
	if controls_locked:
		throttle_input = 0.0
		steer_input = 0.0
		pitch_input = 0.0
		airbrake_left = 0.0
		airbrake_right = 0.0
		return
	
	throttle_input = Input.get_action_strength("accelerate")
	steer_input = Input.get_axis("steer_right", "steer_left")
	pitch_input = Input.get_axis("pitch_down", "pitch_up")
	airbrake_left = Input.get_action_strength("airbrake_left")
	airbrake_right = Input.get_action_strength("airbrake_right")

# ============================================================================
# RESPAWN SYSTEM
# ============================================================================

func _update_safe_position(delta: float) -> void:
	"""Periodically save position while grounded for respawn."""
	if not is_grounded:
		return
	
	_safe_position_timer += delta
	if _safe_position_timer >= safe_position_save_interval:
		_safe_position_timer = 0.0
		last_safe_position = global_position
		last_safe_rotation = global_transform.basis

func _check_respawn_needed() -> void:
	"""Check if ship has fallen below threshold and needs respawn."""
	if global_position.y < respawn_y_threshold:
		respawn()

func respawn(custom_position: Vector3 = Vector3.ZERO, custom_rotation: Basis = Basis.IDENTITY) -> void:
	"""Respawn the ship at the last safe position or a custom location."""
	var target_position: Vector3
	var target_rotation: Basis
	
	# Priority 1: Custom position (from RespawnTrigger or direct call)
	if custom_position != Vector3.ZERO:
		target_position = custom_position
		target_rotation = custom_rotation if custom_rotation != Basis.IDENTITY else last_safe_rotation
	
	# Priority 2: Respawn manager (procedural safe points)
	elif respawn_manager and respawn_manager.is_initialized:
		var respawn_data := respawn_manager.get_nearest_respawn_point(global_position)
		if respawn_data.found:
			target_position = respawn_data.position
			target_rotation = respawn_data.rotation
		else:
			# Fallback to last safe
			target_position = last_safe_position
			target_rotation = last_safe_rotation
	
	# Priority 3: Last safe position (existing behavior)
	else:
		target_position = last_safe_position
		target_rotation = last_safe_rotation
	
	# Teleport ship
	global_position = target_position
	global_transform.basis = target_rotation
	
	# Zero out all velocity
	velocity = Vector3.ZERO
	
	# Reset visual states
	visual_pitch = 0.0
	visual_roll = 0.0
	visual_accel_pitch = 0.0
	
	# Reset hover animation accumulators
	hover_time_accumulator = 0.0
	hover_yaw_accumulator = 0.0
	hover_roll_accumulator = 0.0
	rumble_time = 0.0
	
	# Reset airbrake state
	current_grip = _grip
	is_airbraking = false
	
	# Reset track normal to up (will re-detect on next frame)
	current_track_normal = Vector3.UP
	smoothed_track_normal = Vector3.UP
	
	# Clear ship contacts
	_ship_contacts.clear()
	
	# Stop any wall scraping audio
	if _is_scraping_wall:
		_is_scraping_wall = false
		if audio_controller:
			audio_controller.stop_wall_scrape()
	
	# Emit signal for UI/audio feedback
	ship_respawned.emit()
	
	var source := "respawn_manager" if respawn_manager and respawn_manager.is_initialized else "last_safe"
	if custom_position != Vector3.ZERO:
		source = "custom"
	
	if ai_controlled:
		print("AI Ship respawned at: %s (source: %s)" % [target_position, source])
	else:
		print("Ship respawned at: %s (source: %s)" % [target_position, source])

func set_safe_position(position: Vector3, rotation: Basis) -> void:
	"""Manually set the safe respawn position (useful for checkpoints)."""
	last_safe_position = position
	last_safe_rotation = rotation

# ============================================================================
# GROUND DETECTION & HOVER
# ============================================================================

func _update_ground_detection() -> void:
	if not hover_ray:
		is_grounded = false
		return
	
	hover_ray.force_raycast_update()
	
	if hover_ray.is_colliding():
		is_grounded = true
		time_since_grounded = 0.0
		ground_distance = global_position.distance_to(hover_ray.get_collision_point())
		
		var new_normal = hover_ray.get_collision_normal()
		smoothed_track_normal = smoothed_track_normal.lerp(new_normal, _track_normal_smoothing).normalized()
		current_track_normal = smoothed_track_normal
		
	else:
		is_grounded = false
		time_since_grounded += get_physics_process_delta_time()
		current_track_normal = current_track_normal.lerp(Vector3.UP, 2.0 * get_physics_process_delta_time())

func _apply_hover_force(delta: float) -> void:
	if not is_grounded:
		# Progressive gravity - increases the longer airborne (1.0x to 2.0x over 0.5s)
		# This gives short hops a natural arc while pulling down firmly on longer jumps
		var gravity_multiplier = 1.0 + clampf(time_since_grounded * 2.0, 0.0, 1.0)
		velocity.y -= _gravity * gravity_multiplier * delta
		
		# Light vertical air drag to smooth landings
		velocity.y *= 0.995
		return
	
	var height_error = _hover_height - ground_distance
	var vertical_velocity = velocity.dot(current_track_normal)
	var spring_force = height_error * _hover_stiffness
	var damping_force = -vertical_velocity * _hover_damping
	var total_force = clampf(spring_force + damping_force, -_hover_force_max, _hover_force_max)
	
	velocity += current_track_normal * total_force * delta
	
	# Slope gravity
	var slope_dot = current_track_normal.dot(Vector3.UP)
	if slope_dot < 0.99:
		var slope_dir = Vector3.DOWN.slide(current_track_normal.normalized()).normalized()
		var slope_strength = (1.0 - slope_dot) * _gravity * _slope_gravity_factor
		velocity += slope_dir * slope_strength * delta

# ============================================================================
# THRUST SYSTEM
# ============================================================================

func _apply_thrust(delta: float) -> void:
	if throttle_input <= 0:
		return
	
	var thrust_force = _thrust_power * throttle_input
	var pitch_efficiency = _calculate_pitch_efficiency()
	thrust_force *= pitch_efficiency
	
	var forward_dir = -global_transform.basis.z
	
	if is_grounded:
		forward_dir = forward_dir.slide(current_track_normal.normalized()).normalized()
	else:
		forward_dir.y = 0
		if forward_dir.length() > 0.01:
			forward_dir = forward_dir.normalized()
		else:
			forward_dir = -global_transform.basis.z
			forward_dir.y = 0
			forward_dir = forward_dir.normalized()
	
	velocity += forward_dir * thrust_force * delta

func _calculate_pitch_efficiency() -> float:
	var pitch_factor = absf(visual_pitch) / deg_to_rad(_max_pitch_angle)
	var efficiency = 1.0 - (pitch_factor * 0.3)
	return clampf(efficiency, 0.7, 1.0)

# ============================================================================
# STEERING SYSTEM
# ============================================================================

func _apply_steering(delta: float) -> void:
	if absf(steer_input) < 0.01:
		return
	
	var curved_input = signf(steer_input) * pow(absf(steer_input), _steer_curve_power)
	var speed_ratio = velocity.length() / _max_speed
	var steer_reduction = lerpf(1.0, 0.7, speed_ratio)
	var steer_torque = curved_input * _steer_speed * steer_reduction * delta
	
	rotate_object_local(Vector3.UP, steer_torque)
	_apply_grip(delta)

func _apply_grip(delta: float) -> void:
	# No grip redirection when airborne - trajectory is committed
	if not is_grounded:
		return
	
	var current_speed = velocity.length()
	if current_speed < 1.0:
		return
	
	var target_dir = -global_transform.basis.z
	var target_velocity = target_dir * current_speed
	var grip_factor = current_grip * delta
	velocity = velocity.lerp(target_velocity, grip_factor)

# ============================================================================
# AIRBRAKE SYSTEM
# ============================================================================

func _apply_airbrakes(delta: float) -> void:
	var brake_amount = maxf(airbrake_left, airbrake_right)
	is_airbraking = brake_amount > 0.1
	
	if not is_airbraking:
		current_grip = lerpf(current_grip, _grip, _airbrake_slip_falloff * delta)
		return
	
	# Airbrake rotation - reduced when airborne (cosmetic only, like steering)
	var rotation_effectiveness = 1.0 if is_grounded else 0.3
	var brake_rotation = (airbrake_left - airbrake_right) * _airbrake_turn_rate * rotation_effectiveness * delta
	rotate_object_local(Vector3.UP, brake_rotation)
	
	# Grip changes only when grounded
	if is_grounded:
		current_grip = lerpf(_grip, _airbrake_grip, brake_amount)
		
		var is_opposite = (airbrake_left > 0.5 and steer_input < -0.3) or \
						  (airbrake_right > 0.5 and steer_input > 0.3)
		if is_opposite:
			current_grip *= 0.5
	
	# Drag - only affects horizontal velocity when airborne
	var drag_factor = lerpf(1.0, _airbrake_drag, brake_amount)
	
	if is_grounded:
		velocity *= drag_factor
		
		# Full brake (both airbrakes) - only when grounded
		if airbrake_left > 0.25 and airbrake_right > 0.25:
			var full_brake = minf(airbrake_left, airbrake_right)
			velocity *= lerpf(1.0, 0.85, full_brake)
	else:
		# Airborne: only apply drag to horizontal components, preserve Y
		# Also reduced effectiveness
		var air_drag_factor = lerpf(1.0, _airbrake_drag, brake_amount * 0.3)  # 30% effectiveness
		velocity.x *= air_drag_factor
		velocity.z *= air_drag_factor

# ============================================================================
# PITCH SYSTEM (Visual Only)
# ============================================================================

func _apply_pitch(delta: float) -> void:
	var can_pitch = is_grounded or time_since_grounded < 0.3
	
	if can_pitch and absf(pitch_input) > 0.1:
		visual_pitch += pitch_input * _pitch_speed * delta
	else:
		var return_speed = _pitch_return_speed
		if not is_grounded:
			return_speed *= 2.0
		visual_pitch = lerpf(visual_pitch, 0.0, return_speed * delta)
	
	var max_pitch_rad = deg_to_rad(_max_pitch_angle)
	visual_pitch = clampf(visual_pitch, -max_pitch_rad, max_pitch_rad)

# ============================================================================
# DRAG SYSTEM
# ============================================================================

func _apply_drag() -> void:
	var drag = _drag_coefficient if is_grounded else _air_drag
	velocity.x *= drag
	velocity.z *= drag

# ============================================================================
# TRACK ALIGNMENT
# ============================================================================

func _align_to_track(delta: float) -> void:
	if not is_grounded:
		return
	
	var current_up = global_transform.basis.y
	var target_up = current_track_normal
	var new_up = current_up.slerp(target_up, _track_align_speed * delta)
	
	var forward = -global_transform.basis.z
	var right = forward.cross(new_up).normalized()
	forward = new_up.cross(right).normalized()
	
	global_transform.basis = Basis(right, new_up, -forward).orthonormalized()

# ============================================================================
# COLLISION HANDLING
# ============================================================================

func _handle_collisions() -> void:
	var had_wall_collision := false
	var current_speed = velocity.length()
	
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		var normal = collision.get_normal()
		
		# Check if this is a ship-to-ship collision
		if collider is ShipController:
			_handle_ship_collision(collider as ShipController, collision)
		elif absf(normal.y) < 0.5:
			# Wall collision (horizontal surface = wall, not ground)
			_handle_wall_collision(normal)
			had_wall_collision = true
	
	if had_wall_collision and current_speed >= _wall_scrape_min_speed:
		_is_scraping_wall = true
		_scrape_timer = SCRAPE_TIMEOUT
		if audio_controller:
			audio_controller.start_wall_scrape()
			audio_controller.update_wall_scrape_intensity(current_speed)
	elif had_wall_collision and current_speed < _wall_scrape_min_speed:
		if _is_scraping_wall:
			_is_scraping_wall = false
			if audio_controller:
				audio_controller.stop_wall_scrape()

func _update_scrape_audio(delta: float) -> void:
	if _is_scraping_wall:
		_scrape_timer -= delta
		if _scrape_timer <= 0:
			_is_scraping_wall = false
			if audio_controller:
				audio_controller.stop_wall_scrape()

func _handle_wall_collision(wall_normal: Vector3) -> void:
	var impact_speed = velocity.length()
	
	var reflected = velocity.bounce(wall_normal)
	velocity = reflected * _wall_bounce_retain
	
	var rotate_away = wall_normal.cross(Vector3.UP).dot(-global_transform.basis.z)
	rotate_y(rotate_away * _wall_rotation_force * get_physics_process_delta_time())
	
	if _collision_shake_enabled and camera and impact_speed > _shake_speed_threshold:
		var speed_ratio = (impact_speed - _shake_speed_threshold) / (_max_speed - _shake_speed_threshold)
		speed_ratio = clampf(speed_ratio, 0.0, 1.0)
		var final_intensity = _shake_intensity * speed_ratio * 2.0
		if camera.has_method("apply_shake"):
			camera.apply_shake(final_intensity)
	
	if audio_controller and impact_speed > _shake_speed_threshold:
		audio_controller.play_wall_hit(impact_speed)

# ============================================================================
# SHIP-TO-SHIP COLLISION HANDLING (v3 - One-Sided Processing)
# ============================================================================

func _update_ship_contacts(delta: float) -> void:
	"""Update contact state tracking and expire old contacts."""
	var to_remove: Array[int] = []
	
	for ship_id in _ship_contacts:
		var contact: Dictionary = _ship_contacts[ship_id]
		
		# Update cooldowns
		if contact.impact_cooldown > 0:
			contact.impact_cooldown -= delta
		
		# Update contact timeout
		contact.last_impact_time += delta
		
		# Decay post-collision damping
		if contact.damping_timer > 0:
			contact.damping_timer -= delta
		
		# If no collision detected recently, end contact
		if contact.last_impact_time > CONTACT_TIMEOUT:
			contact.in_contact = false
			contact.contact_time = 0.0
			to_remove.append(ship_id)
	
	# Clean up expired contacts
	for ship_id in to_remove:
		_ship_contacts.erase(ship_id)


func _handle_ship_collision(other_ship: ShipController, collision: KinematicCollision3D) -> void:
	"""
	Handle WipEout-style ship-to-ship collision with impulse-based physics.
	
	v3 improvements:
	- One-sided processing (lower instance_id handles collision for both ships)
	- Mutual rear-end detection (detects if hitter OR being hit from behind)
	- Post-collision damping for weight feel
	- Prevents double-impulse from both ships processing same collision
	"""
	var my_id := get_instance_id()
	var other_id := other_ship.get_instance_id()
	var collision_normal := collision.get_normal()
	var delta := get_physics_process_delta_time()
	
	# === ONE-SIDED COLLISION PROCESSING ===
	# Only the ship with lower instance_id processes the collision for both ships.
	# This prevents double-application of forces.
	var i_am_primary := my_id < other_id
	
	if not i_am_primary:
		# We're the secondary ship - just update contact state, don't apply forces
		# The other ship will handle the physics for both of us
		_update_contact_state_only(other_ship)
		return
	
	# === GET OR CREATE CONTACT STATE ===
	if not _ship_contacts.has(other_id):
		_ship_contacts[other_id] = {
			"ship": other_ship,
			"in_contact": false,
			"contact_time": 0.0,
			"last_impact_time": 0.0,
			"impact_cooldown": 0.0,
			"damping_timer": 0.0,
		}
	
	var contact: Dictionary = _ship_contacts[other_id]
	contact.last_impact_time = 0.0  # Reset timeout
	
	# === CALCULATE RELATIVE VELOCITY ===
	var relative_velocity := velocity - other_ship.velocity
	
	# Project relative velocity onto collision normal
	# This is the "closing speed" - how fast we're approaching along the collision direction
	var closing_speed := relative_velocity.dot(-collision_normal)
	
	# If ships are separating (negative closing speed), only apply soft separation
	if closing_speed < _ship_ignore_speed:
		_apply_mutual_soft_separation(other_ship, collision_normal, delta)
		contact.in_contact = true
		contact.contact_time += delta
		return
	
	# === DETERMINE COLLISION TYPE ===
	var rear_end_info: Dictionary = _detect_rear_end_collision(other_ship)
	var is_rear_end: bool = rear_end_info.is_rear_end
	var is_first_contact: bool = not contact.in_contact
	var is_rubbing: bool = contact.contact_time > MIN_CONTACT_TIME_FOR_RUBBING
	var can_apply_impact: bool = contact.impact_cooldown <= 0
	
	# Update contact state
	contact.in_contact = true
	contact.contact_time += delta
	
	# === HANDLE BASED ON COLLISION TYPE ===
	if is_rear_end:
		_handle_rear_end_collision_mutual(other_ship, collision_normal, closing_speed, rear_end_info, delta)
	elif is_first_contact and can_apply_impact:
		# First contact - apply full impact impulse to both ships
		_apply_mutual_impact_impulse(other_ship, collision_normal, closing_speed, delta)
		contact.impact_cooldown = IMPACT_COOLDOWN_TIME
		contact.damping_timer = 0.15  # Brief damping period for weight feel
	elif is_rubbing:
		# Sustained contact - apply friction and soft separation
		_apply_mutual_rubbing_response(other_ship, collision_normal, relative_velocity, delta)
	elif can_apply_impact:
		# Repeated impact (not rubbing, cooldown expired)
		_apply_mutual_impact_impulse(other_ship, collision_normal, closing_speed * 0.6, delta)
		contact.impact_cooldown = IMPACT_COOLDOWN_TIME
	else:
		# On cooldown - just soft separation
		_apply_mutual_soft_separation(other_ship, collision_normal, delta)
	
	# === FEEDBACK (only for player ship) ===
	if not ai_controlled:
		_apply_collision_feedback(closing_speed)


func _update_contact_state_only(other_ship: ShipController) -> void:
	"""Update contact tracking without applying forces (for secondary ship in collision pair)."""
	var other_id := other_ship.get_instance_id()
	
	if not _ship_contacts.has(other_id):
		_ship_contacts[other_id] = {
			"ship": other_ship,
			"in_contact": true,
			"contact_time": 0.0,
			"last_impact_time": 0.0,
			"impact_cooldown": 0.0,
			"damping_timer": 0.0,
		}
	
	var contact: Dictionary = _ship_contacts[other_id]
	contact.last_impact_time = 0.0
	contact.in_contact = true
	contact.contact_time += get_physics_process_delta_time()


func _detect_rear_end_collision(other_ship: ShipController) -> Dictionary:
	"""
	Detect rear-end collision from either perspective (hitter or being hit).
	Returns info about which ship is the hitter and which is being hit.
	"""
	var result := {
		"is_rear_end": false,
		"hitter": null,  # The faster ship hitting from behind
		"victim": null,  # The slower ship being hit
	}
	
	# Get forward directions (horizontal)
	var my_forward := -global_transform.basis.z
	my_forward.y = 0
	if my_forward.length() < 0.1:
		return result
	my_forward = my_forward.normalized()
	
	var their_forward := -other_ship.global_transform.basis.z
	their_forward.y = 0
	if their_forward.length() < 0.1:
		return result
	their_forward = their_forward.normalized()
	
	# Check if ships are facing roughly the same direction
	var threshold_rad := deg_to_rad(_ship_rear_end_angle_threshold)
	var alignment := my_forward.dot(their_forward)
	if alignment < cos(threshold_rad):
		return result  # Not same direction, not a rear-end
	
	# Direction vectors
	var to_other := other_ship.global_position - global_position
	to_other.y = 0
	if to_other.length() < 0.1:
		return result
	to_other = to_other.normalized()
	
	var my_speed := velocity.length()
	var their_speed := other_ship.velocity.length()
	var speed_threshold := 3.0  # Minimum speed difference for rear-end
	
	# Check if I'm hitting them from behind
	var i_face_them := my_forward.dot(to_other) > 0.5
	var they_face_away := their_forward.dot(to_other) > 0.3
	var i_am_faster := my_speed > their_speed + speed_threshold
	
	if i_face_them and they_face_away and i_am_faster:
		result.is_rear_end = true
		result.hitter = self
		result.victim = other_ship
		return result
	
	# Check if they're hitting me from behind
	var to_me := -to_other
	var they_face_me := their_forward.dot(to_me) > 0.5
	var i_face_away := my_forward.dot(to_me) > 0.3
	var they_are_faster := their_speed > my_speed + speed_threshold
	
	if they_face_me and i_face_away and they_are_faster:
		result.is_rear_end = true
		result.hitter = other_ship
		result.victim = self
		return result
	
	return result


func _apply_mutual_impact_impulse(other_ship: ShipController, collision_normal: Vector3, closing_speed: float, delta: float) -> void:
	"""
	Apply physics-based impulse to BOTH ships (called only by primary ship).
	Uses coefficient of restitution and mass ratio for realistic momentum transfer.
	"""
	if closing_speed < _ship_min_impact_speed:
		_apply_mutual_soft_separation(other_ship, collision_normal, delta)
		return
	
	# === CALCULATE IMPULSE MAGNITUDE ===
	# Using impulse formula: j = -(1 + e) * v_rel / (1/m1 + 1/m2)
	var my_mass := _ship_collision_mass
	var their_mass := other_ship._ship_collision_mass
	
	if my_mass < 0.01:
		my_mass = 1.0
	if their_mass < 0.01:
		their_mass = 1.0
	
	var impulse_magnitude := (1.0 + _ship_restitution) * closing_speed
	impulse_magnitude /= (1.0 / my_mass + 1.0 / their_mass)
	
	# Increase base impulse for more weight feel (was 0.5, now 0.8)
	impulse_magnitude *= 0.8
	
	# === APPLY IMPULSE TO BOTH SHIPS ===
	var impulse := collision_normal * impulse_magnitude
	
	# I get pushed in the collision normal direction
	var my_velocity_change := impulse / my_mass
	# They get pushed in the opposite direction
	var their_velocity_change := -impulse / their_mass
	
	# Cap velocity changes
	var max_change := _ship_max_separation_speed
	if my_velocity_change.length() > max_change:
		my_velocity_change = my_velocity_change.normalized() * max_change
	if their_velocity_change.length() > max_change:
		their_velocity_change = their_velocity_change.normalized() * max_change
	
	velocity += my_velocity_change
	other_ship.velocity += their_velocity_change
	
	# === POST-COLLISION DAMPING (weight feel) ===
	# Briefly reduce both ships' velocities to simulate energy absorption
	var damping := 0.95  # 5% speed loss on impact
	velocity *= damping
	other_ship.velocity *= damping
	
	# === APPLY SPIN TO BOTH ===
	_apply_collision_spin(collision_normal, closing_speed, delta)
	other_ship._apply_collision_spin(-collision_normal, closing_speed, delta)
	
	# Emit signals
	ship_collision.emit(other_ship, closing_speed)
	other_ship.ship_collision.emit(self, closing_speed)


func _handle_rear_end_collision_mutual(other_ship: ShipController, collision_normal: Vector3, closing_speed: float, rear_end_info: Dictionary, delta: float) -> void:
	"""
	Handle rear-end collision for both ships.
	The hitter slows down, the victim gets a small push forward.
	"""
	var hitter: ShipController = rear_end_info.hitter
	var victim: ShipController = rear_end_info.victim
	
	if hitter == null or victim == null:
		_apply_mutual_soft_separation(other_ship, collision_normal, delta)
		return
	
	var hitter_speed := hitter.velocity.length()
	var victim_speed := victim.velocity.length()
	var speed_diff := hitter_speed - victim_speed
	
	if speed_diff < 1.0:
		_apply_mutual_soft_separation(other_ship, collision_normal, delta)
		return
	
	# Get hitter's forward direction
	var hitter_forward := -hitter.global_transform.basis.z
	hitter_forward.y = 0
	hitter_forward = hitter_forward.normalized()
	
	# Get victim's forward direction
	var victim_forward := -victim.global_transform.basis.z
	victim_forward.y = 0
	victim_forward = victim_forward.normalized()
	
	# === BRAKE THE HITTER ===
	var brake_amount := speed_diff * _ship_rear_end_brake_factor * delta * 8.0
	brake_amount = minf(brake_amount, speed_diff * 0.4)
	hitter.velocity -= hitter_forward * brake_amount
	
	# === PUSH THE VICTIM FORWARD (small boost) ===
	var push_amount := speed_diff * _ship_rear_end_push_factor * delta * 5.0
	push_amount = minf(push_amount, 10.0 * delta)  # Cap the push
	victim.velocity += victim_forward * push_amount
	
	# === SLIGHT LATERAL SEPARATION ===
	var lateral := collision_normal
	lateral.y = 0
	if lateral.length() > 0.1:
		lateral = lateral.normalized()
		var lateral_force := _ship_separation_force * 0.2 * delta
		
		# Push both ships apart slightly
		if hitter == self:
			velocity += lateral * lateral_force
			other_ship.velocity -= lateral * lateral_force
		else:
			velocity -= lateral * lateral_force
			other_ship.velocity += lateral * lateral_force
	
	# === MINIMAL SPIN ===
	var spin_amount := closing_speed * _ship_spin_impulse_factor * 0.15 * delta
	spin_amount = clampf(spin_amount, 0.0, deg_to_rad(_ship_max_spin_rate * 0.2) * delta)
	
	var to_other := other_ship.global_position - global_position
	var spin_dir := signf(to_other.dot(global_transform.basis.x))
	rotate_y(-spin_dir * spin_amount)
	other_ship.rotate_y(spin_dir * spin_amount * 0.5)
	
	# Emit signals with reduced intensity
	ship_collision.emit(other_ship, closing_speed * 0.3)
	other_ship.ship_collision.emit(self, closing_speed * 0.3)


func _apply_mutual_rubbing_response(other_ship: ShipController, collision_normal: Vector3, relative_velocity: Vector3, delta: float) -> void:
	"""
	Handle sustained contact (ships rubbing against each other).
	Applies friction and soft separation to both ships.
	"""
	# === SOFT SEPARATION ===
	_apply_mutual_soft_separation(other_ship, collision_normal, delta)
	
	# === FRICTION ===
	var normal_component := collision_normal * relative_velocity.dot(collision_normal)
	var tangent_velocity := relative_velocity - normal_component
	
	if tangent_velocity.length() > 1.0:
		var friction_force := tangent_velocity.normalized() * _ship_friction * delta * 15.0
		
		if friction_force.length() > tangent_velocity.length() * 0.3:
			friction_force = tangent_velocity * 0.3
		
		# Apply friction to both ships (half each)
		velocity -= friction_force * 0.5
		other_ship.velocity += friction_force * 0.5


func _apply_mutual_soft_separation(other_ship: ShipController, collision_normal: Vector3, delta: float) -> void:
	"""
	Apply gentle separation force to BOTH ships to prevent overlap.
	"""
	var distance := global_position.distance_to(other_ship.global_position)
	var overlap := _ship_contact_distance - distance
	
	if overlap <= 0:
		return
	
	# Separation force increases with overlap depth
	var force_magnitude := overlap * _ship_separation_force * _ship_separation_stiffness
	
	# Direction: away from other ship (horizontal)
	var separation_dir := collision_normal
	separation_dir.y *= 0.1
	if separation_dir.length() > 0.1:
		separation_dir = separation_dir.normalized()
	else:
		separation_dir = (global_position - other_ship.global_position)
		separation_dir.y = 0
		if separation_dir.length() > 0.1:
			separation_dir = separation_dir.normalized()
		else:
			separation_dir = Vector3.RIGHT
	
	# Calculate separation velocity
	var separation_velocity := separation_dir * force_magnitude * delta
	
	# Cap separation speed
	var max_sep := _ship_max_separation_speed * delta
	if separation_velocity.length() > max_sep:
		separation_velocity = separation_velocity.normalized() * max_sep
	
	# Apply to both ships (half each for balanced response)
	velocity += separation_velocity * 0.5
	other_ship.velocity -= separation_velocity * 0.5


func _apply_collision_spin(collision_normal: Vector3, impact_speed: float, delta: float) -> void:
	"""Apply rotational response to collision."""
	var right := global_transform.basis.x
	var hit_side := collision_normal.dot(right)
	
	var spin_magnitude := impact_speed * _ship_spin_impulse_factor * delta
	spin_magnitude *= absf(hit_side)
	spin_magnitude = clampf(spin_magnitude, 0.0, deg_to_rad(_ship_max_spin_rate) * delta)
	
	rotate_y(-signf(hit_side) * spin_magnitude)


func _apply_collision_feedback(impact_speed: float) -> void:
	"""Apply camera shake and audio feedback for collision."""
	if _ship_shake_enabled and camera and impact_speed > _ship_shake_speed_threshold:
		var intensity_ratio := (impact_speed - _ship_shake_speed_threshold) / 50.0
		intensity_ratio = clampf(intensity_ratio, 0.0, 1.0)
		var final_intensity := _ship_shake_intensity * intensity_ratio
		if camera.has_method("apply_shake"):
			camera.apply_shake(final_intensity)
	
	if audio_controller and impact_speed > _ship_sound_speed_threshold:
		audio_controller.play_wall_hit(impact_speed * 0.6)

# ============================================================================
# VISUAL FEEDBACK
# ============================================================================

func _update_visuals(delta: float) -> void:
	if not ship_mesh:
		return
	
	# Calculate steering/airbrake roll (existing system)
	var target_roll := 0.0
	target_roll += steer_input * deg_to_rad(25.0)
	target_roll += (airbrake_left - airbrake_right) * deg_to_rad(15.0)
	
	var speed_factor = clampf(velocity.length() / _max_speed, 0.3, 1.0)
	target_roll *= speed_factor
	
	visual_roll = lerpf(visual_roll, target_roll, 8.0 * delta)
	
	# Calculate acceleration pitch (existing system)
	var target_accel_pitch = -throttle_input * deg_to_rad(5.0)
	visual_accel_pitch = lerpf(visual_accel_pitch, target_accel_pitch, 6.0 * delta)
	
	# Combine pitch components
	var total_pitch = visual_pitch + visual_accel_pitch
	
	# Apply hover animation if enabled
	if _hover_animation_enabled:
		_apply_hover_animation(delta)
	else:
		# Just apply the basic rotation without animation
		ship_mesh.rotation = Vector3(total_pitch, 0, visual_roll)
		ship_mesh.position = Vector3.ZERO

# ============================================================================
# HOVER ANIMATION SYSTEM
# ============================================================================

func _apply_hover_animation(delta: float) -> void:
	var speed_ratio = get_speed_ratio()
	
	# Calculate intensity falloff based on speed
	var intensity = lerpf(1.0, _hover_pulse_min_intensity, speed_ratio)
	
	# === VERTICAL PULSE ===
	hover_time_accumulator += delta * _hover_pulse_speed * TAU
	var vertical_offset = sin(hover_time_accumulator) * _hover_pulse_amplitude * intensity
	
	# === YAW WOBBLE ===
	# Independent frequency for organic feel
	hover_yaw_accumulator += delta * _hover_wobble_speed_yaw * TAU
	var yaw_wobble = sin(hover_yaw_accumulator) * deg_to_rad(_hover_wobble_yaw) * intensity
	
	# === ROLL WOBBLE ===
	# Different frequency from yaw for organic motion
	hover_roll_accumulator += delta * _hover_wobble_speed_roll * TAU
	var roll_wobble = sin(hover_roll_accumulator) * deg_to_rad(_hover_wobble_roll) * intensity
	
	# === HIGH-SPEED RUMBLE ===
	var rumble_offset := Vector3.ZERO
	var rumble_rotation := Vector3.ZERO
	
	if speed_ratio >= _rumble_speed_threshold:
		# Calculate rumble intensity (0 at threshold, 1 at max speed)
		var rumble_intensity = (speed_ratio - _rumble_speed_threshold) / (1.0 - _rumble_speed_threshold)
		rumble_time += delta * _rumble_frequency * TAU
		
		# High-frequency noise using combined sine waves for pseudo-random feel
		var noise_x = sin(rumble_time * 1.73) * cos(rumble_time * 2.31)
		var noise_y = sin(rumble_time * 2.11) * cos(rumble_time * 1.89)
		var noise_z = sin(rumble_time * 1.97) * cos(rumble_time * 2.47)
		
		# Position rumble
		rumble_offset = Vector3(noise_x, noise_y, noise_z) * _rumble_position_intensity * rumble_intensity
		
		# Rotation rumble (yaw and roll only, not pitch)
		var rumble_yaw = noise_x * deg_to_rad(_rumble_rotation_intensity) * rumble_intensity
		var rumble_roll = noise_z * deg_to_rad(_rumble_rotation_intensity) * rumble_intensity
		rumble_rotation = Vector3(0, rumble_yaw, rumble_roll)
	
	# === COMBINE ALL EFFECTS ===
	# Position: vertical pulse + rumble
	ship_mesh.position = Vector3(0, vertical_offset, 0) + rumble_offset
	
	# Rotation: existing controls (pitch from input + accel, roll from steering) + hover wobbles + rumble
	var total_pitch = visual_pitch + visual_accel_pitch
	var total_yaw = yaw_wobble + rumble_rotation.y
	var total_roll = visual_roll + roll_wobble + rumble_rotation.z
	
	ship_mesh.rotation = Vector3(total_pitch, total_yaw, total_roll)

# ============================================================================
# PUBLIC API
# ============================================================================

func get_speed() -> float:
	return velocity.length()

func get_speed_ratio() -> float:
	return velocity.length() / _max_speed

func get_max_speed() -> float:
	return _max_speed

func get_debug_info() -> String:
	return "Speed: %.0f / %.0f\nGrip: %.1f\nGrounded: %s\nAirbrake: %s" % [
		velocity.length(), _max_speed, current_grip, is_grounded, is_airbraking
	]

func lock_controls() -> void:
	controls_locked = true

func unlock_controls() -> void:
	controls_locked = false

func apply_boost(amount: float) -> void:
	var forward = -global_transform.basis.z
	
	if is_grounded:
		forward = forward.slide(current_track_normal).normalized()
	else:
		forward.y = 0
		if forward.length() > 0.01:
			forward = forward.normalized()
		else:
			forward = -global_transform.basis.z
			forward.y = 0
			forward = forward.normalized()
	
	velocity += forward * amount
	
	if audio_controller:
		audio_controller.trigger_boost()
