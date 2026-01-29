extends CharacterBody3D
class_name ShipController

## WipEout 2097 Style Anti-Gravity Ship Controller
## Based on BallisticNG "2159 Mode" physics specifications
## Refactored to use ShipProfile for data-driven configuration.
## v5: BallisticNG-style arcade collision system

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
# SHIP COLLISION STATE (v5 - BallisticNG Arcade Style)
# ============================================================================

# Contact state tracking - tracks which ships we're currently in contact with
# Key: ship instance_id, Value: ContactState dictionary
var _ship_contacts: Dictionary = {}

# Collision stun state - reduces grip after significant impacts
var _collision_stun_timer: float = 0.0
var _collision_stun_intensity: float = 0.0  # 0-1, how much grip is reduced

# Collision type enum
enum CollisionType { REAR_END, SIDE_SWIPE, HEAD_ON, GENTLE }

# Debug collision system (set to true to see collision details)
var debug_collisions: bool = false

# Pre-collision velocity tracking (captured before move_and_slide modifies it)
var _pre_collision_velocity: Vector3 = Vector3.ZERO
var _pre_collision_speed: float = 0.0

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

# ============================================================================
# CACHED COLLISION PROFILE VALUES (v5 - Arcade System)
# ============================================================================

# Classification thresholds
var _coll_rear_end_angle: float = 40.0
var _coll_head_on_angle: float = 50.0
var _coll_rear_speed_diff_min: float = 5.0
var _coll_min_speed: float = 3.0

# Rear-end parameters
var _coll_rear_attacker_brake: float = 0.12
var _coll_rear_victim_boost: float = 0.35
var _coll_rear_max_boost: float = 20.0
var _coll_rear_cooldown: float = 0.5

# Side-swipe parameters
var _coll_side_speed_loss: float = 0.08
var _coll_side_lateral_force: float = 12.0
var _coll_side_lateral_strength: float = 0.4

# Head-on parameters
var _coll_head_speed_loss: float = 0.25
var _coll_head_separation: float = 18.0
var _coll_head_stun_mult: float = 1.5

# Velocity limits
var _coll_max_speed_gain: float = 25.0
var _coll_max_speed_loss: float = 35.0
var _coll_max_lateral_push: float = 15.0

# Forward-bias
var _coll_forward_bias: float = 0.75
var _coll_lateral_damping: float = 0.3

# Stun parameters
var _coll_stun_enabled: bool = true
var _coll_stun_duration: float = 0.35
var _coll_stun_grip_mult: float = 0.25
var _coll_stun_speed_threshold: float = 40.0

# Rotation parameters
var _coll_rotation_enabled: bool = true
var _coll_rotation_strength: float = 0.6
var _coll_max_rotation_deg: float = 25.0

# Contact parameters
var _coll_contact_distance: float = 3.5
var _coll_separation_force: float = 15.0
var _coll_max_separation: float = 12.0
var _coll_contact_timeout: float = 0.15

# Feedback parameters
var _coll_shake_enabled: bool = true
var _coll_shake_intensity: float = 0.4
var _coll_shake_threshold: float = 15.0
var _coll_sound_threshold: float = 5.0

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
	"""Apply ship collision profile values (v5 - Arcade system)."""
	if not collision_profile:
		# Defaults already set in variable declarations
		return
	
	# Classification
	_coll_rear_end_angle = collision_profile.rear_end_angle_threshold
	_coll_head_on_angle = collision_profile.head_on_angle_threshold
	_coll_rear_speed_diff_min = collision_profile.rear_end_speed_diff_min
	_coll_min_speed = collision_profile.min_collision_speed
	
	# Rear-end
	_coll_rear_attacker_brake = collision_profile.rear_end_attacker_brake
	_coll_rear_victim_boost = collision_profile.rear_end_victim_boost
	_coll_rear_max_boost = collision_profile.rear_end_max_boost
	_coll_rear_cooldown = collision_profile.rear_end_cooldown
	
	# Side-swipe
	_coll_side_speed_loss = collision_profile.sideswipe_speed_loss
	_coll_side_lateral_force = collision_profile.sideswipe_lateral_force
	_coll_side_lateral_strength = collision_profile.sideswipe_lateral_strength
	
	# Head-on
	_coll_head_speed_loss = collision_profile.head_on_speed_loss
	_coll_head_separation = collision_profile.head_on_separation_force
	_coll_head_stun_mult = collision_profile.head_on_stun_multiplier
	
	# Limits
	_coll_max_speed_gain = collision_profile.max_speed_gain
	_coll_max_speed_loss = collision_profile.max_speed_loss
	_coll_max_lateral_push = collision_profile.max_lateral_push
	
	# Forward-bias
	_coll_forward_bias = collision_profile.forward_bias_strength
	_coll_lateral_damping = collision_profile.lateral_damping
	
	# Stun
	_coll_stun_enabled = collision_profile.stun_enabled
	_coll_stun_duration = collision_profile.stun_duration
	_coll_stun_grip_mult = collision_profile.stun_grip_multiplier
	_coll_stun_speed_threshold = collision_profile.stun_speed_threshold
	
	# Rotation
	_coll_rotation_enabled = collision_profile.rotation_enabled
	_coll_rotation_strength = collision_profile.rotation_strength
	_coll_max_rotation_deg = collision_profile.max_rotation_degrees
	
	# Contact
	_coll_contact_distance = collision_profile.contact_distance
	_coll_separation_force = collision_profile.separation_force
	_coll_max_separation = collision_profile.max_separation_speed
	_coll_contact_timeout = collision_profile.contact_timeout
	
	# Feedback
	_coll_shake_enabled = collision_profile.shake_enabled
	_coll_shake_intensity = collision_profile.shake_intensity
	_coll_shake_threshold = collision_profile.shake_speed_threshold
	_coll_sound_threshold = collision_profile.sound_speed_threshold

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
	# Store velocity BEFORE move_and_slide modifies it (for accurate collision debug)
	_pre_collision_velocity = velocity
	_pre_collision_speed = velocity.length()
	
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
	_update_collision_stun(delta)

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
	
	# Clear ship contacts and collision stun
	_ship_contacts.clear()
	_collision_stun_timer = 0.0
	_collision_stun_intensity = 0.0
	
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
	
	# Calculate effective grip (reduced during collision stun)
	var effective_grip := current_grip
	if _collision_stun_timer > 0:
		var stun_factor := _collision_stun_intensity * (1.0 - _coll_stun_grip_mult)
		effective_grip *= (1.0 - stun_factor)
	
	var grip_factor = effective_grip * delta
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
	var had_ship_collision := false
	
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		var normal = collision.get_normal()
		
		# Check if this is a ship-to-ship collision
		if collider is ShipController:
			had_ship_collision = true
			# CRITICAL: Restore pre-collision velocity BEFORE our handler
			# Godot's move_and_slide already applied its aggressive response
			# We want to handle ship collisions ourselves
			velocity = _pre_collision_velocity
			
			_handle_ship_collision(collider as ShipController, collision)
		elif absf(normal.y) < 0.5:
			# Wall collision (horizontal surface = wall, not ground)
			_handle_wall_collision(normal)
			had_wall_collision = true
	
	# For ship collisions, we've already set velocity in our handler
	# For wall collisions, Godot's response is fine
	
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
# SHIP-TO-SHIP COLLISION HANDLING (v5 - BallisticNG Arcade Style)
# ============================================================================

func _update_collision_stun(delta: float) -> void:
	"""Decay collision stun over time."""
	if _collision_stun_timer > 0:
		_collision_stun_timer -= delta
		# Intensity decays with timer
		_collision_stun_intensity = clampf(_collision_stun_timer / _coll_stun_duration, 0.0, 1.0)
		
		if _collision_stun_timer <= 0:
			_collision_stun_timer = 0.0
			_collision_stun_intensity = 0.0

func _apply_collision_stun(intensity: float) -> void:
	"""Apply collision stun (reduces grip temporarily)."""
	if not _coll_stun_enabled:
		return
	
	# Only apply if this would increase the stun
	if intensity > _collision_stun_intensity:
		_collision_stun_intensity = clampf(intensity, 0.0, 1.0)
		_collision_stun_timer = _coll_stun_duration

func _update_ship_contacts(delta: float) -> void:
	"""Update contact state tracking and expire old contacts."""
	var to_remove: Array[int] = []
	
	for ship_id in _ship_contacts:
		var contact: Dictionary = _ship_contacts[ship_id]
		
		# Update cooldowns
		if contact.has("rear_end_cooldown") and contact.rear_end_cooldown > 0:
			contact.rear_end_cooldown -= delta
		
		# Update contact timeout
		contact.time_since_last_collision += delta
		
		# If no collision detected recently, end contact
		if contact.time_since_last_collision > _coll_contact_timeout:
			to_remove.append(ship_id)
	
	# Clean up expired contacts
	for ship_id in to_remove:
		_ship_contacts.erase(ship_id)

func _get_or_create_contact(other_ship: ShipController) -> Dictionary:
	"""Get existing contact state or create new one."""
	var other_id := other_ship.get_instance_id()
	
	if not _ship_contacts.has(other_id):
		_ship_contacts[other_id] = {
			"ship": other_ship,
			"time_since_last_collision": 0.0,
			"rear_end_cooldown": 0.0,
			"last_collision_type": CollisionType.GENTLE
		}
	
	return _ship_contacts[other_id]

func _classify_collision(other_ship: ShipController, collision_normal: Vector3) -> Dictionary:
	"""
	Classify the collision type based on relative velocity and ship orientations.
	Returns: {
		"type": CollisionType enum,
		"closing_speed": float,
		"relative_velocity": Vector3,
		"is_i_faster": bool,
		"speed_difference": float,
		"i_am_attacker": bool  # NEW: who initiated the collision
	}
	"""
	# CRITICAL: Use PRE-COLLISION velocities!
	# By the time this function runs, move_and_slide() has already modified velocities
	var my_velocity := _pre_collision_velocity
	var their_velocity := other_ship._pre_collision_velocity
	var relative_velocity := my_velocity - their_velocity
	
	# Closing speed along collision normal
	var closing_speed := relative_velocity.dot(-collision_normal)
	
	# Speed comparison (calculate EARLY so it's available for all returns)
	var my_speed := my_velocity.length()
	var their_speed := their_velocity.length()
	var speed_diff := my_speed - their_speed
	var abs_speed_diff := absf(speed_diff)
	var is_i_faster := abs_speed_diff > _coll_rear_speed_diff_min and speed_diff > 0
	var is_they_faster := abs_speed_diff > _coll_rear_speed_diff_min and speed_diff < 0
	
	# Get ship orientations
	var my_forward := -global_transform.basis.z
	var their_forward := -other_ship.global_transform.basis.z
	
	# Direction of relative velocity (which way is the collision happening?)
	var collision_dir := relative_velocity.normalized() if relative_velocity.length() > 0.1 else -collision_normal
	
	# === REAR-END DETECTION (BIDIRECTIONAL) ===
	# Check if I'm rear-ending them
	if is_i_faster:
		var my_alignment := collision_dir.dot(my_forward)
		var their_alignment := collision_dir.dot(their_forward)
		
		# Check if I'm hitting them from behind
		var angle_to_my_forward := rad_to_deg(acos(clampf(my_alignment, -1.0, 1.0)))
		var angle_to_their_forward := rad_to_deg(acos(clampf(-their_alignment, -1.0, 1.0)))
		
		if angle_to_my_forward < _coll_rear_end_angle and angle_to_their_forward < _coll_rear_end_angle:
			return {
				"type": CollisionType.REAR_END,
				"closing_speed": closing_speed,
				"relative_velocity": relative_velocity,
				"is_i_faster": true,
				"speed_difference": abs_speed_diff,
				"i_am_attacker": true  # I'm hitting them
			}
	
	# Check if THEY'RE rear-ending ME
	if is_they_faster:
		# For them hitting me, reverse the collision direction
		var reverse_collision_dir := -collision_dir
		var my_alignment := reverse_collision_dir.dot(my_forward)
		var their_alignment := reverse_collision_dir.dot(their_forward)
		
		# Check if they're hitting me from behind
		var angle_to_their_forward := rad_to_deg(acos(clampf(their_alignment, -1.0, 1.0)))
		var angle_to_my_forward := rad_to_deg(acos(clampf(-my_alignment, -1.0, 1.0)))
		
		if angle_to_their_forward < _coll_rear_end_angle and angle_to_my_forward < _coll_rear_end_angle:
			return {
				"type": CollisionType.REAR_END,
				"closing_speed": closing_speed,
				"relative_velocity": relative_velocity,
				"is_i_faster": false,  # They're faster
				"speed_difference": abs_speed_diff,
				"i_am_attacker": false  # They're hitting me
			}
	
	# === GENTLE CONTACT ===
	# Only gentle if BOTH low closing speed AND low speed difference
	if absf(closing_speed) < _coll_min_speed and abs_speed_diff < _coll_rear_speed_diff_min:
		return {
			"type": CollisionType.GENTLE,
			"closing_speed": closing_speed,
			"relative_velocity": relative_velocity,
			"is_i_faster": is_i_faster,
			"speed_difference": abs_speed_diff,
			"i_am_attacker": false
		}
	
	# === HEAD-ON DETECTION ===
	# Head-on if ships are moving toward each other
	var my_vel_dir := my_velocity.normalized() if my_velocity.length() > 0.1 else my_forward
	var their_vel_dir := their_velocity.normalized() if their_velocity.length() > 0.1 else their_forward
	var vel_opposition := -my_vel_dir.dot(their_vel_dir)
	
	if vel_opposition > 0.5:  # Velocities pointing toward each other
		return {
			"type": CollisionType.HEAD_ON,
			"closing_speed": closing_speed,
			"relative_velocity": relative_velocity,
			"is_i_faster": is_i_faster,
			"speed_difference": abs_speed_diff,
			"i_am_attacker": false
		}
	
	# === DEFAULT: SIDE-SWIPE ===
	return {
		"type": CollisionType.SIDE_SWIPE,
		"closing_speed": closing_speed,
		"relative_velocity": relative_velocity,
		"is_i_faster": is_i_faster,
		"speed_difference": abs_speed_diff,
		"i_am_attacker": false
	}

func _handle_ship_collision(other_ship: ShipController, collision: KinematicCollision3D) -> void:
	"""
	Handle ship-to-ship collision with BallisticNG-style arcade physics.
	
	v5 Features:
	- Collision classification (rear-end, side-swipe, head-on)
	- Asymmetric velocity transfer
	- Forward-biased velocity changes
	- Hard velocity clamps
	- Bilateral processing coordination
	"""
	
	# === BILATERAL PROCESSING COORDINATION ===
	# Use instance_id to determine which ship does the calculation
	var my_id := get_instance_id()
	var other_id := other_ship.get_instance_id()
	var i_am_primary := my_id < other_id
	
	# Get or create contact state
	var contact := _get_or_create_contact(other_ship)
	contact.time_since_last_collision = 0.0
	
	# Only primary ship calculates forces
	if not i_am_primary:
		return
	
	# === CLASSIFY COLLISION ===
	var collision_normal := collision.get_normal()
	var collision_point := collision.get_position()
	var classification := _classify_collision(other_ship, collision_normal)
	
	contact.last_collision_type = classification.type
	
	# === DEBUG OUTPUT ===
	if debug_collisions and not ai_controlled:
		print("=== COLLISION DEBUG ===")
		print("  Type: %s" % CollisionType.keys()[classification.type])
		print("  Closing speed: %.1f" % classification.closing_speed)
		print("  My speed (PRE-collision): %.1f | Their speed: %.1f" % [_pre_collision_speed, other_ship._pre_collision_speed])
		print("  My speed (after move_and_slide): %.1f | Their speed: %.1f" % [velocity.length(), other_ship.velocity.length()])
		print("  Speed diff: %.1f (is_i_faster: %s)" % [classification.speed_difference, classification.is_i_faster])
		
		# DEBUG: Show angle information for rear-end detection
		if classification.type == CollisionType.SIDE_SWIPE and absf(classification.speed_difference) > _coll_rear_speed_diff_min:
			print("  ⚠ Large speed diff but not REAR_END - checking angles:")
			var my_forward := -global_transform.basis.z
			var their_forward := -other_ship.global_transform.basis.z
			var rel_vel := _pre_collision_velocity - other_ship._pre_collision_velocity  # Use PRE-collision!
			var collision_dir := rel_vel.normalized() if rel_vel.length() > 0.1 else -collision_normal
			
			var my_alignment := collision_dir.dot(my_forward)
			var their_alignment := collision_dir.dot(their_forward)
			var angle_to_my_forward := rad_to_deg(acos(clampf(my_alignment, -1.0, 1.0)))
			var angle_to_their_forward := rad_to_deg(acos(clampf(-their_alignment, -1.0, 1.0)))
			
			print("    My angle: %.1f° (threshold: %.1f°)" % [angle_to_my_forward, _coll_rear_end_angle])
			print("    Their angle: %.1f° (threshold: %.1f°)" % [angle_to_their_forward, _coll_rear_end_angle])
			print("    Collision dir (PRE): %s" % collision_dir)
			print("    My forward: %s" % my_forward)
			print("    Their forward: %s" % their_forward)
		
		# Show classification reasoning
		if classification.type == CollisionType.REAR_END:
			var attacker_role := "I AM ATTACKER" if classification.i_am_attacker else "THEY ARE ATTACKER"
			print("  → Rear-end: %s (Speed diff > %.1f and angles OK)" % [attacker_role, _coll_rear_speed_diff_min])
		elif classification.type == CollisionType.GENTLE:
			print("  → Gentle: Closing < %.1f AND speed_diff < %.1f" % [_coll_min_speed, _coll_rear_speed_diff_min])
		elif classification.type == CollisionType.SIDE_SWIPE:
			print("  → Side-swipe: Default (not rear-end/head-on/gentle)")
		elif classification.type == CollisionType.HEAD_ON:
			print("  → Head-on: Velocities opposing")
	
	# Store velocities BEFORE collision for debug
	var my_vel_before := velocity.length()
	var their_vel_before := other_ship.velocity.length()
	
	# === HANDLE BY TYPE ===
	match classification.type:
		CollisionType.REAR_END:
			_handle_rear_end_collision(other_ship, classification, collision_normal, contact)
		
		CollisionType.SIDE_SWIPE:
			_handle_side_swipe_collision(other_ship, classification, collision_normal)
		
		CollisionType.HEAD_ON:
			_handle_head_on_collision(other_ship, classification, collision_normal)
		
		CollisionType.GENTLE:
			_handle_gentle_contact(other_ship, collision_normal)
	
	# === DEBUG OUTPUT (AFTER) ===
	if debug_collisions and not ai_controlled:
		print("  AFTER: My speed: %.1f (Δ%.1f) | Their speed: %.1f (Δ%.1f)" % [
			velocity.length(), velocity.length() - my_vel_before,
			other_ship.velocity.length(), other_ship.velocity.length() - their_vel_before
		])
		print("====================")
	
	# === OPTIONAL ROTATION ===
	if _coll_rotation_enabled and classification.type != CollisionType.GENTLE:
		_apply_off_center_rotation(collision_point, classification.closing_speed)
		other_ship._apply_off_center_rotation(collision_point, classification.closing_speed)
	
	# === FEEDBACK ===
	if classification.closing_speed > _coll_sound_threshold:
		_apply_collision_feedback(classification.closing_speed)
		other_ship._apply_collision_feedback(classification.closing_speed)
	
	# === EMIT SIGNALS ===
	ship_collision.emit(other_ship, classification.closing_speed)
	other_ship.ship_collision.emit(self, classification.closing_speed)

func _handle_rear_end_collision(other_ship: ShipController, classification: Dictionary, collision_normal: Vector3, contact: Dictionary) -> void:
	"""
	Handle rear-end collision (bumper drafting).
	Now supports bidirectional - either ship can be the attacker.
	"""
	
	# Check rear-end cooldown
	if contact.rear_end_cooldown > 0:
		# On cooldown, just do gentle separation
		_handle_gentle_contact(other_ship, collision_normal)
		return
	
	# Set cooldown
	contact.rear_end_cooldown = _coll_rear_cooldown
	
	# Determine who is attacker and victim based on classification
	var i_am_attacker: bool = classification.i_am_attacker
	var attacker = self if i_am_attacker else other_ship
	var victim = other_ship if i_am_attacker else self
	
	var attacker_forward: Vector3 = -attacker.global_transform.basis.z
	var victim_forward: Vector3 = -victim.global_transform.basis.z
	var speed_diff: float = classification.speed_difference
	
	# === ATTACKER (faster ship) ===
	# Calculate speed loss as a delta, not a direct change
	var attacker_current_speed: float = attacker.velocity.length()
	var attacker_speed_loss: float = attacker_current_speed * _coll_rear_attacker_brake
	attacker_speed_loss = clampf(attacker_speed_loss, 0.0, _coll_max_speed_loss)
	
	# Apply as a velocity magnitude reduction along forward direction
	var attacker_new_speed: float = maxf(attacker_current_speed - attacker_speed_loss, 0.0)
	if attacker_current_speed > 0.1:
		var speed_ratio: float = attacker_new_speed / attacker_current_speed
		attacker.velocity *= speed_ratio
	
	# Light stun for attacker
	var stun_intensity: float = clampf(classification.closing_speed / _coll_stun_speed_threshold, 0.2, 0.6)
	attacker._apply_collision_stun(stun_intensity)
	
	# === VICTIM (slower ship) ===
	# Calculate boost amount
	var victim_speed_gain: float = speed_diff * _coll_rear_victim_boost
	victim_speed_gain = clampf(victim_speed_gain, 0.0, _coll_rear_max_boost)
	
	# Apply boost along their forward direction (already clamped)
	var victim_boost_vector: Vector3 = victim_forward * victim_speed_gain
	
	# Apply with forward-bias (this will further clamp if needed)
	victim.velocity += victim._apply_forward_bias(victim_boost_vector, victim_forward)
	
	# Minimal stun for victim (they got a boost!)
	victim._apply_collision_stun(stun_intensity * 0.3)
	
	if not ai_controlled:
		if i_am_attacker:
			print("Rear-end: I attacked - lost %.1f speed (%.1f → %.1f), they gained %.1f boost" % [
				attacker_speed_loss, attacker_current_speed, attacker.velocity.length(), victim_speed_gain
			])
		else:
			print("Rear-end: I was victim - gained %.1f boost, they lost %.1f speed" % [
				victim_speed_gain, attacker_speed_loss
			])

func _handle_side_swipe_collision(other_ship: ShipController, classification: Dictionary, collision_normal: Vector3) -> void:
	"""
	Handle side-swipe collision.
	Both ships lose a little speed and get pushed apart laterally.
	"""
	
	var my_forward := -global_transform.basis.z
	var their_forward := -other_ship.global_transform.basis.z
	
	# === SPEED LOSS (both ships) ===
	var my_speed: float = velocity.length()
	var their_speed: float = other_ship.velocity.length()
	
	var my_speed_loss: float = my_speed * _coll_side_speed_loss
	var their_speed_loss: float = their_speed * _coll_side_speed_loss
	
	velocity *= (1.0 - _coll_side_speed_loss)
	other_ship.velocity *= (1.0 - _coll_side_speed_loss)
	
	# === LATERAL PUSH ===
	# Push apart along collision normal (horizontal only)
	var push_dir := collision_normal
	push_dir.y = 0
	if push_dir.length() > 0.1:
		push_dir = push_dir.normalized()
	else:
		# Fallback: push directly apart
		push_dir = (global_position - other_ship.global_position)
		push_dir.y = 0
		push_dir = push_dir.normalized() if push_dir.length() > 0.1 else Vector3.RIGHT
	
	var push_amount: float = _coll_side_lateral_force * _coll_side_lateral_strength
	push_amount = minf(push_amount, _coll_max_lateral_push)
	
	# Apply push with lateral damping
	var my_push: Vector3 = push_dir * push_amount
	var their_push: Vector3 = -push_dir * push_amount
	
	velocity += _apply_forward_bias(my_push, my_forward)
	other_ship.velocity += other_ship._apply_forward_bias(their_push, their_forward)
	
	# === LIGHT STUN (both ships) ===
	var stun_intensity: float = clampf(classification.closing_speed / _coll_stun_speed_threshold, 0.15, 0.4)
	_apply_collision_stun(stun_intensity)
	other_ship._apply_collision_stun(stun_intensity)

func _handle_head_on_collision(other_ship: ShipController, classification: Dictionary, collision_normal: Vector3) -> void:
	"""
	Handle head-on collision.
	Both ships lose significant speed and bounce apart.
	"""
	
	var my_forward := -global_transform.basis.z
	var their_forward := -other_ship.global_transform.basis.z
	
	# === SPEED LOSS (both ships) ===
	var my_speed: float = velocity.length()
	var their_speed: float = other_ship.velocity.length()
	
	var my_speed_loss: float = my_speed * _coll_head_speed_loss
	var their_speed_loss: float = their_speed * _coll_head_speed_loss
	
	my_speed_loss = clampf(my_speed_loss, 0.0, _coll_max_speed_loss)
	their_speed_loss = clampf(their_speed_loss, 0.0, _coll_max_speed_loss)
	
	velocity *= (1.0 - _coll_head_speed_loss)
	other_ship.velocity *= (1.0 - _coll_head_speed_loss)
	
	# === SEPARATION (push apart) ===
	var separation_dir := collision_normal
	separation_dir.y *= 0.1  # Mostly horizontal
	separation_dir = separation_dir.normalized() if separation_dir.length() > 0.1 else Vector3.RIGHT
	
	var separation_amount: float = _coll_head_separation
	separation_amount = minf(separation_amount, _coll_max_lateral_push)
	
	var my_push: Vector3 = separation_dir * separation_amount
	var their_push: Vector3 = -separation_dir * separation_amount
	
	velocity += _apply_forward_bias(my_push, my_forward)
	other_ship.velocity += other_ship._apply_forward_bias(their_push, their_forward)
	
	# === HEAVY STUN (both ships) ===
	var stun_intensity: float = clampf(classification.closing_speed / _coll_stun_speed_threshold, 0.5, 1.0)
	stun_intensity *= _coll_head_stun_mult
	
	_apply_collision_stun(stun_intensity)
	other_ship._apply_collision_stun(stun_intensity)
	
	if not ai_controlled:
		print("Head-on collision! Speed loss: %.1f" % my_speed_loss)

func _handle_gentle_contact(other_ship: ShipController, collision_normal: Vector3) -> void:
	"""
	Handle gentle contact when ships are barely touching.
	Just soft separation, no speed changes.
	"""
	var distance: float = global_position.distance_to(other_ship.global_position)
	var overlap: float = _coll_contact_distance - distance
	
	if overlap <= 0:
		return
	
	# Separation direction (horizontal)
	var separation_dir := collision_normal
	separation_dir.y *= 0.05
	if separation_dir.length() < 0.1:
		separation_dir = (global_position - other_ship.global_position)
		separation_dir.y = 0
	
	if separation_dir.length() > 0.1:
		separation_dir = separation_dir.normalized()
	else:
		return  # Can't determine direction
	
	# Soft separation force (reduced from original to prevent compounding)
	var force: float = overlap * _coll_separation_force * 0.5  # REDUCED by 50%
	var delta: float = get_physics_process_delta_time()
	var separation_velocity: Vector3 = separation_dir * force * delta
	
	# Tighter clamp to prevent excessive separation
	var max_sep: float = _coll_max_separation * delta * 0.3  # REDUCED from 0.5 to 0.3
	if separation_velocity.length() > max_sep:
		separation_velocity = separation_velocity.normalized() * max_sep
	
	# Apply to both ships (equally distributed)
	velocity += separation_velocity
	other_ship.velocity -= separation_velocity

func _apply_forward_bias(velocity_change: Vector3, forward: Vector3) -> Vector3:
	"""
	Apply forward-bias to velocity changes.
	Projects changes mostly onto forward vector, dampens lateral components.
	Returns: modified velocity_change
	"""
	if _coll_forward_bias < 0.01:
		return velocity_change  # No bias
	
	# Decompose into forward and lateral components
	var forward_component := velocity_change.dot(forward) * forward
	var lateral_component := velocity_change - forward_component
	
	# CRITICAL: Clamp forward component to prevent excessive forward changes
	var forward_magnitude := forward_component.length() * signf(forward_component.dot(forward))
	if absf(forward_magnitude) > _coll_max_speed_gain:
		forward_component = forward.normalized() * signf(forward_magnitude) * _coll_max_speed_gain
	
	# Apply lateral damping
	lateral_component *= _coll_lateral_damping
	
	# Clamp lateral component
	if lateral_component.length() > _coll_max_lateral_push:
		lateral_component = lateral_component.normalized() * _coll_max_lateral_push
	
	# Blend based on forward_bias strength
	var result := forward_component + lateral_component * (1.0 - _coll_forward_bias)
	
	return result

func _apply_off_center_rotation(collision_point: Vector3, impact_speed: float) -> void:
	"""
	Apply light rotation if hit off-center.
	Much subtler than v4 torque system.
	"""
	if not _coll_rotation_enabled:
		return
	
	# Calculate offset from ship center
	var ship_center: Vector3 = global_position
	var offset: Vector3 = collision_point - ship_center
	offset.y = 0
	
	if offset.length() < 0.5:
		return  # Hit too close to center
	
	# Determine rotation direction based on offset
	var ship_right: Vector3 = global_transform.basis.x
	var side_offset: float = offset.dot(ship_right)
	var rotation_dir: float = signf(side_offset)
	
	# Scale by distance from center and impact speed
	var rotation_amount: float = _coll_rotation_strength * (offset.length() / 3.0)
	rotation_amount *= clampf(impact_speed / 50.0, 0.3, 1.0)
	
	# Clamp
	var max_rotation: float = deg_to_rad(_coll_max_rotation_deg) * get_physics_process_delta_time()
	rotation_amount = clampf(rotation_amount * get_physics_process_delta_time(), 0.0, max_rotation)
	
	# Apply rotation
	rotate_y(rotation_dir * rotation_amount)

func _apply_collision_feedback(impact_speed: float) -> void:
	"""Apply camera shake and audio feedback."""
	
	# Camera shake
	if _coll_shake_enabled and camera and impact_speed > _coll_shake_threshold:
		var intensity_ratio: float = (impact_speed - _coll_shake_threshold) / 50.0
		intensity_ratio = clampf(intensity_ratio, 0.0, 1.0)
		var final_intensity: float = _coll_shake_intensity * intensity_ratio
		if camera.has_method("apply_shake"):
			camera.apply_shake(final_intensity)
	
	# Audio
	if audio_controller and impact_speed > _coll_sound_threshold:
		audio_controller.play_ship_collision(impact_speed)

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
