extends Camera3D
class_name AGCamera2097

## WipEout-style chase camera.
##
## v2 REWRITE -- WHY
## ---------------------------------------------------------------------------
## v1 computed a camera offset in the ship's basis every frame and then
## smoothed the WORLD position toward it with `lerp(target, follow_speed *
## delta)`. That smoothing has a steady-state lag proportional to speed:
## measured at 6.7 units at top speed. Combined with `speed_zoom = -7` against
## a `base_offset.z` of 6.5 -- which asks for the camera to sit 1.33 units in
## FRONT of the ship at terminal speed -- the two errors cancelled:
##
##     speed   intended offset   measured offset
##      27         +4.87              6.18
##      93         +1.03              5.73
##     134         -1.33              5.38
##
## The camera therefore always landed behind the ship (which is why it looked
## fine) but its distance barely moved across a 5x speed range, so there was
## effectively NO speed pullback at all. Worse, `follow_speed` alone controlled
## resting distance, speed-dependent pullback, how much the ship could rotate
## within the frame, and shake recovery. One coupled knob doing four jobs is
## why the camera could not be made more dynamic by tuning.
##
## v2 separates them:
##   * Position uses velocity feedforward, so there is NO speed-dependent lag
##     and `speed_distance` genuinely controls pullback.
##   * The camera carries its OWN forward and up vectors which chase the
##     ship's with their own rates. `yaw_follow_rate` is now the single knob
##     for "how much does the ship rotate inside the frame".
##   * `up_follow_rate` makes the horizon roll with banked track instead of
##     being pinned to Vector3.UP (which also gimbal-flipped past vertical).
##   * FOV is driven by acceleration and boost, not by absolute speed. v1
##     measured 116 degrees on straights and 81 mid-corner: a 35-degree lens
##     breathing in and out of every corner, zooming IN when you turned.

## Reference to the ship being followed. Must be set for the camera to run.
@export var ship: ShipController

# ============================================================================
# FRAME
# ============================================================================

@export_group("Frame")

## Resting height above the ship, in the camera's own frame.
@export var base_height := 2.6

## Resting distance behind the ship.
@export var base_distance := 7.0

## EXTRA distance at max speed. Positive = pulls back as you go faster.
## This now works: v1's equivalent was cancelled out by follow lag.
@export var speed_distance := 3.4

## Extra height at max speed.
@export var speed_height := 0.7

## How quickly the camera position converges on its target (per second).
## Velocity feedforward means this controls softness ONLY -- it no longer
## secretly sets the camera distance.
@export var position_follow_rate := 13.0

## How quickly the camera's forward vector chases the ship's heading.
## THIS IS THE DYNAMISM KNOB. Lower = the ship rotates further within the
## frame during a turn and the camera whips to catch up. Higher = rigid.
## Useful range 5.0-12.0.
@export var yaw_follow_rate := 9.0

## How quickly the camera's up vector chases the ship's up (the track normal).
## Keep well above yaw_follow_rate or banked sections feel seasick.
@export var up_follow_rate := 11.0

# ============================================================================
# AIM
# ============================================================================

@export_group("Aim")

## How far ahead of the ship the camera aims.
@export var look_distance := 9.0

## Height of the aim point above the ship.
@export var aim_height := 1.0

## 0 = aim straight down the ship's nose, 1 = aim down the velocity vector.
## v1 was effectively 1.0, which is why rotation-in-frame exactly equalled
## the slip angle and the camera could never lead a corner.
@export var look_velocity_blend := 0.45

## How quickly the aim point converges (per second).
@export var aim_follow_rate := 12.0

# ============================================================================
# BANK
# ============================================================================

@export_group("Bank")

## Fraction of the ship's visual roll the camera picks up.
@export var bank_from_roll := 0.05

## Degrees of camera roll per rad/s of ship yaw rate.
@export var bank_from_yaw_rate := 0.05

## Hard cap on camera roll, degrees.
@export var bank_max := 14.0

## How quickly camera bank converges (per second).
@export var bank_follow_rate := 5.0

# ============================================================================
# LATERAL SWING
# ============================================================================

@export_group("Lateral Swing")

@export var swing_enabled := true

## Maximum lateral offset at full deflection. v1 shipped 0.45 against its own
## documented 2.0-2.5 recommendation, so the swing was invisible.
@export var swing_max_offset := 1

## Contribution of measured yaw rate (normalised against 1.5 rad/s).
@export var swing_from_yaw_rate := 0.75

## Contribution of slip angle (normalised against 30 degrees).
@export var swing_from_slip := 0.5

## Contribution of raw steering input, for immediacy.
@export var swing_from_input := 0.2

## How quickly the camera swings out (per second).
@export var swing_out_rate := 7.0

## How quickly it returns to centre (per second). Lower than out_rate gives
## the cinematic trailing return.
@export var swing_return_rate := 2.0

## Below this speed ratio, swing is disabled.
@export var swing_min_speed := 0.1

# ============================================================================
# FIELD OF VIEW
# ============================================================================

@export_group("Field of View")

## FOV at rest.
@export var base_fov := 74.0

## Extra FOV at max speed. Deliberately modest: the drama comes from the
## acceleration kick below, not from a constantly moving lens.
@export var speed_fov := 10.0

## Degrees of FOV per unit/second^2 of longitudinal acceleration.
@export var accel_fov_gain := 0.22

## Cap on the acceleration contribution, degrees.
@export var accel_fov_max := 9.0

## Extra FOV at the peak of a boost kick, degrees.
@export var boost_fov_kick := 12.0

## How quickly a boost kick decays (per second).
@export var boost_kick_decay := 3.0

## How quickly FOV converges on its target (per second).
@export var fov_follow_rate := 5.0

## Absolute clamps. v1 had none, and Godot's lerp() does not clamp, so an
## unbounded speed_ratio of 1.119 produced 116 degrees against max_fov 110.
@export var fov_min := 55.0
@export var fov_max := 105.0

# ============================================================================
# COLLISION
# ============================================================================

@export_group("Collision")

## Prevent the camera clipping through walls.
@export var collision_enabled := true

## Safety margin pulled back from the contact point.
@export var collision_margin := 0.3

## How quickly the camera returns to normal distance after a collision.
@export var collision_recovery_rate := 5.0

## Layer 1 = track surface, Layer 3 = walls. Mask 5 = both.
@export_flags_3d_physics var collision_mask := 5

# ============================================================================
# SHAKE
# ============================================================================

@export_group("Shake")

# ============================================================================
# INTRO
# ============================================================================

@export_group("Intro")

## Cinematic entry on the first acquisition of the ship: the camera starts
## high and off-axis and eases down into the normal chase pose.
##
## This also hides the start-of-race settle. Measured on the grid: the ship
## spawns at a hover ray distance of 1.59 against a hover_height of 2.0, the
## hover spring fires to +12.7 u/s of vertical velocity, and the resulting
## ring produced an 18-degree camera pitch oscillation. ShipController now
## settles to hover equilibrium on spawn, and this covers whatever is left.
@export var intro_enabled := true

## Seconds the entry takes. Match this to your countdown.
@export var intro_duration := 2.6

## Starting height above the ship.
@export var intro_start_height := 26.0

## Starting distance behind the ship.
@export var intro_start_distance := 16.0

## Lateral offset at the start, for a slight arc rather than a straight drop.
@export var intro_start_lateral := 9.0

## How quickly shake decays (per second).
@export var shake_decay := 7.0

## Rotational shake, degrees at full intensity.
@export var shake_rotation := 0.6

# ============================================================================
# STATE
# ============================================================================

var _cam_forward := Vector3.FORWARD
var _cam_up := Vector3.UP
var _cam_position := Vector3.ZERO
var _aim_point := Vector3.ZERO
var _swing := 0.0
var _bank := 0.0
var _fov_current := 0.0
var _fov_kick := 0.0
var _shake_intensity := 0.0
var _collision_distance := 0.0
var _initialised := false
var _intro_time := 0.0
var _intro_active := false
var _intro_consumed := false

## True while the cinematic entry is playing.
func is_intro_playing() -> bool:
	return _intro_active

func _ready() -> void:
	# v2: runs in _process, not _physics_process. v1 stepped the camera at the
	# physics tick, which judders visibly on a display running above 60Hz even
	# though the world is static.
	set_physics_process(false)
	set_process(true)
	_fov_current = base_fov
	fov = base_fov

## Frame-rate independent smoothing weight.
static func _w(rate: float, delta: float) -> float:
	return 1.0 - exp(-maxf(rate, 0.0) * delta)

func _process(delta: float) -> void:
	if not is_instance_valid(ship):
		return
	if not _initialised:
		_snap_to_ship()
		return
	if delta <= 0.0:
		return
	
	if _intro_active:
		_process_intro(delta)
		return
	
	var ship_pos: Vector3 = ship.global_position
	var ship_forward: Vector3 = -ship.global_transform.basis.z
	var ship_up: Vector3 = ship.global_transform.basis.y
	var ratio: float = ship.get_speed_ratio()
	
	_update_frame(ship_forward, ship_up, delta)
	
	var frame := _build_basis()
	var desired_pos := _desired_position(ship_pos, frame, ratio, delta)
	
	if collision_enabled:
		desired_pos = _apply_collision(ship_pos, desired_pos, delta)
	
	# Velocity feedforward, then converge. The feedforward is what removes
	# the speed-proportional lag that dominated v1's camera distance.
	_cam_position += ship.velocity * delta
	_cam_position = _cam_position.lerp(desired_pos, _w(position_follow_rate, delta))
	
	_update_aim(ship_pos, ship_forward, ship_up, delta)
	_update_bank(delta)
	_update_shake(delta)
	
	global_position = _cam_position + _shake_offset()
	_apply_look()
	_update_fov(ratio, delta)

# ============================================================================
# FRAME
# ============================================================================

func _update_frame(ship_forward: Vector3, ship_up: Vector3, delta: float) -> void:
	_cam_forward = _cam_forward.slerp(ship_forward, _w(yaw_follow_rate, delta)).normalized()
	_cam_up = _cam_up.slerp(ship_up, _w(up_follow_rate, delta)).normalized()
	
	# Re-orthogonalise. Note this never falls back to Vector3.UP, so the
	# camera survives banked, vertical and inverted track.
	var right := _cam_forward.cross(_cam_up)
	if right.length() < 0.001:
		right = ship.global_transform.basis.x
	right = right.normalized()
	_cam_up = right.cross(_cam_forward).normalized()

func _build_basis() -> Basis:
	var right := _cam_forward.cross(_cam_up).normalized()
	return Basis(right, _cam_up, -_cam_forward)

func _desired_position(ship_pos: Vector3, frame: Basis, ratio: float, delta: float) -> Vector3:
	var swing := _update_swing(ratio, delta)
	var offset := Vector3(
		swing,
		base_height + speed_height * ratio,
		base_distance + speed_distance * ratio
	)
	return ship_pos + frame * offset

# ============================================================================
# LATERAL SWING
# ============================================================================

func _update_swing(ratio: float, delta: float) -> float:
	if not swing_enabled or ratio < swing_min_speed:
		_swing = lerpf(_swing, 0.0, _w(swing_return_rate, delta))
		return _swing
	
	# v1 derived its rotation term from ship.rotation.y, an Euler angle of a
	# basis that _align_to_track() rebuilds from the surface normal every
	# frame, so it jumped on banked geometry. measured_yaw_rate is computed
	# about the ship's own up axis instead.
	var yaw_term := clampf(ship.measured_yaw_rate / 1.5, -1.0, 1.0) * swing_from_yaw_rate
	var slip_term := clampf(ship.slip_angle / deg_to_rad(30.0), -1.0, 1.0) * swing_from_slip
	var input_term := ship.steer_input * swing_from_input
	
	# Positive swing = camera moves to the ship's right. A left turn
	# (positive yaw rate, negative slip) should swing the camera right so the
	# corner opens up in frame.
	var target := -(yaw_term - slip_term + input_term) * swing_max_offset * ratio
	
	var rate := swing_out_rate if absf(target) > absf(_swing) else swing_return_rate
	_swing = lerpf(_swing, target, _w(rate, delta))
	return _swing

# ============================================================================
# AIM
# ============================================================================

func _update_aim(ship_pos: Vector3, ship_forward: Vector3, ship_up: Vector3, delta: float) -> void:
	var aim_dir := ship_forward
	if ship.velocity.length() > 1.0:
		var vel_dir := ship.velocity.normalized()
		if ship_forward.dot(vel_dir) > -0.5:
			aim_dir = ship_forward.slerp(vel_dir, look_velocity_blend).normalized()
	
	var target := ship_pos + aim_dir * look_distance + ship_up * aim_height
	_aim_point = _aim_point.lerp(target, _w(aim_follow_rate, delta))

func _apply_look() -> void:
	var to_target := _aim_point - global_position
	if to_target.length() < 0.05:
		return
	var view_axis := to_target.normalized()
	var up_ref := _cam_up.rotated(view_axis, _bank)
	if absf(up_ref.dot(view_axis)) > 0.999:
		return
	look_at(_aim_point, up_ref)

func _update_bank(delta: float) -> void:
	var target := deg_to_rad(bank_from_yaw_rate) * ship.measured_yaw_rate
	target += bank_from_roll * ship.visual_roll
	var limit := deg_to_rad(bank_max)
	target = clampf(target, -limit, limit)
	_bank = lerpf(_bank, target, _w(bank_follow_rate, delta))

# ============================================================================
# FIELD OF VIEW
# ============================================================================

func _update_fov(ratio: float, delta: float) -> void:
	var target := base_fov + speed_fov * ratio
	
	# Acceleration kick. Narrows slightly under braking, widens on a hard
	# launch or boost, and is silent at constant speed.
	var accel_term := ship.longitudinal_accel * accel_fov_gain
	target += clampf(accel_term, -accel_fov_max * 0.5, accel_fov_max)
	
	_fov_kick *= exp(-boost_kick_decay * delta)
	if _fov_kick < 0.001:
		_fov_kick = 0.0
	target += boost_fov_kick * _fov_kick
	
	_fov_current = lerpf(_fov_current, target, _w(fov_follow_rate, delta))
	fov = clampf(_fov_current, fov_min, fov_max)

## Called by ShipController.apply_boost().
func apply_fov_kick(strength: float = 1.0) -> void:
	_fov_kick = maxf(_fov_kick, clampf(strength, 0.0, 1.0))

# ============================================================================
# COLLISION
# ============================================================================

func _apply_collision(ship_pos: Vector3, desired_pos: Vector3, delta: float) -> Vector3:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	query.from = ship_pos
	query.to = desired_pos
	query.collision_mask = collision_mask
	query.exclude = [ship]
	
	var desired_distance := ship_pos.distance_to(desired_pos)
	var result := space_state.intersect_ray(query)
	var target_distance := desired_distance
	
	if result:
		var hit_distance: float = ship_pos.distance_to(result.position as Vector3)
		target_distance = maxf(hit_distance - collision_margin, 0.5)
	
	_collision_distance = lerpf(_collision_distance, target_distance,
			_w(collision_recovery_rate, delta))
	
	if _collision_distance < desired_distance - 0.1 and desired_distance > 0.001:
		var direction := (desired_pos - ship_pos) / desired_distance
		return ship_pos + direction * _collision_distance
	return desired_pos

# ============================================================================
# SHAKE
# ============================================================================

## Called by ShipController on wall and ship impacts.
func apply_shake(intensity: float) -> void:
	_shake_intensity = maxf(_shake_intensity, intensity)

func _update_shake(delta: float) -> void:
	if _shake_intensity <= 0.001:
		_shake_intensity = 0.0
		return
	_shake_intensity *= exp(-shake_decay * delta)

## v1 did `global_position += shake_offset` and then lerped FROM the shaken
## position on the next frame, so shake performed a random walk that partly
## baked itself into the camera's resting place. Here it is applied only at
## the point of writing the transform and never fed back into _cam_position.
func _shake_offset() -> Vector3:
	if _shake_intensity <= 0.0:
		return Vector3.ZERO
	return Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)
	) * _shake_intensity

# ============================================================================
# INITIALISATION
# ============================================================================

# ============================================================================
# CINEMATIC INTRO
# ============================================================================

## Chase pose the intro is easing toward, recomputed every frame so the
## landing is exact even if the ship creeps on the grid.
func _chase_pose() -> Array:
	var ship_forward: Vector3 = -ship.global_transform.basis.z
	var ship_up: Vector3 = ship.global_transform.basis.y
	_cam_forward = ship_forward
	_cam_up = ship_up
	var frame := _build_basis()
	var pos: Vector3 = ship.global_position + frame * Vector3(0.0, base_height, base_distance)
	var aim: Vector3 = ship.global_position + ship_forward * look_distance + ship_up * aim_height
	return [pos, aim, frame]

func _process_intro(delta: float) -> void:
	_intro_time += delta
	var t: float = clampf(_intro_time / maxf(intro_duration, 0.01), 0.0, 1.0)
	
	# Ease out cubic: fast descent, gentle arrival, so it is already settled
	# and stable by the time the lights go out.
	var e: float = 1.0 - pow(1.0 - t, 3.0)
	
	var pose: Array = _chase_pose()
	var end_pos: Vector3 = pose[0]
	var end_aim: Vector3 = pose[1]
	var frame: Basis = pose[2]
	
	var start_pos: Vector3 = ship.global_position + frame * Vector3(
			intro_start_lateral, intro_start_height, intro_start_distance)
	
	_cam_position = start_pos.lerp(end_pos, e)
	_aim_point = ship.global_position.lerp(end_aim, e)
	_fov_current = lerpf(base_fov + 8.0, base_fov, e)
	fov = _fov_current
	
	global_position = _cam_position
	_apply_look()
	
	if t >= 1.0:
		_intro_active = false
		_collision_distance = _cam_position.distance_to(ship.global_position)

## Restart the cinematic entry (e.g. at the start of a countdown).
func begin_intro(duration: float = -1.0) -> void:
	if not is_instance_valid(ship):
		return
	if duration > 0.0:
		intro_duration = duration
	_intro_time = 0.0
	_intro_active = true
	_intro_consumed = true
	_swing = 0.0
	_bank = 0.0
	_shake_intensity = 0.0

func _snap_to_ship() -> void:
	var pose: Array = _chase_pose()
	_cam_position = pose[0]
	# v2.1: this used to omit the `ship_up * aim_height` term that _update_aim()
	# applies every frame, so frame one started with a 1-unit aim mismatch that
	# the aim spring then had to chase out.
	_aim_point = pose[1]
	_collision_distance = _cam_position.distance_to(ship.global_position)
	_swing = 0.0
	_bank = 0.0
	_fov_current = base_fov
	fov = base_fov
	global_position = _cam_position
	_apply_look()
	_initialised = true
	
	if intro_enabled and not _intro_consumed:
		begin_intro()

## Re-snap after a respawn or teleport so the camera does not sweep across
## the level.
## Re-snap after a respawn or teleport. Deliberately does NOT replay the
## intro -- a respawn should be instant.
func reset_to_ship() -> void:
	_initialised = false
	_intro_active = false
	_intro_consumed = true
	if is_instance_valid(ship):
		_snap_to_ship()
