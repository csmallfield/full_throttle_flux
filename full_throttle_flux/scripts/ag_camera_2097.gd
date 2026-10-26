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
##
## v35:
##   * Velocity feedforward on the AIM point too (aim_feedforward). v2 only
##     fed it into the position, so the aim lagged speed / aim_follow_rate
##     (10 m at 120 u/s, against look_distance 9): at speed the camera aimed
##     at the ship, stared at the road, cut to the inside of corners, and
##     whipped down on boost pads.
##   * Track look-ahead: the aim bends toward where the track goes over the
##     next track_look_time seconds (forks followed). See set_track().
##   * Boost lag: the chase distance grows with the speed above max_speed, so
##     the ship surges away on a pad and the camera reels it back in.

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

## v30: multiplies yaw_follow_rate and up_follow_rate inside magnetic zones
## (blended by the ship's magnet weight). 1 = no change.
@export var magnetic_follow_boost := 1.8

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

## v35: velocity feedforward on the aim point, matching what v2 did for the
## position. Without it the aim point lags its target by speed / rate --
## 10 m at 120 u/s against a 9 m look_distance -- so at top speed the camera
## was aiming at the SHIP, not ahead of it: it stared at the road (55% of a
## Swoopy lap had the view ray hitting the track within 25 m), cut to the
## inside of tight corners, and on a 150 u/s boost pad the aim point fell
## ~13 m behind the ship and the view whipped down 24 degrees.
## 1 = full feedforward. 0 = the old behaviour.
@export_range(0.0, 1.0) var aim_feedforward := 1.0

# ============================================================================
# TRACK LOOK-AHEAD
# ============================================================================

@export_group("Track Look-Ahead")

## v35: bend the aim toward where the TRACK goes, not just where the ship
## points. Needs a track: ModeBase calls set_track(); otherwise the camera
## looks for one once and falls back to the plain nose/velocity aim.
@export var track_look_enabled := true

## 0 = nose/velocity aim only, 1 = aim entirely along the upcoming track.
## The aim keeps its look_distance, so on a straight nothing changes; through
## corners, crests and dips the view leads down the road.
@export_range(0.0, 1.0) var track_look_weight := 0.55

## How far ahead along the track to look, in seconds at the current speed...
@export var track_look_time := 0.35

## ...clamped to this range, metres.
@export var track_look_min := 15.0
@export var track_look_max := 55.0

## The look-ahead fades out when the ship is further than this from the
## centre line (a fork's other branch, a big jump, off the road), metres.
@export var track_look_fade_lateral := 40.0

# ============================================================================
# BOOST LAG
# ============================================================================

@export_group("Boost Lag")

## v35: on a boost the ship surges away from the camera, then the camera
## catches up as the overspeed bleeds off.
@export var boost_lag_enabled := true

## Extra distance at a speed excess of boost_lag_ref_speed, metres.
@export var boost_lag_distance := 7.0

## Speed above max_speed that gives the full boost_lag_distance (u/s).
## The default pad adds 150.
@export var boost_lag_ref_speed := 120.0

## How quickly the camera drops back when the boost hits (per second).
@export var boost_lag_attack := 12.0

## How quickly it catches up again (per second).
@export var boost_lag_release := 1.5

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
var _boost_lag := 0.0

# v35 track look-ahead: the track's centre lines (MainSpline, plus each fork
# branch) resampled every TRACK_STEP m in world space, and where along them
# the ship was last frame.
const TRACK_STEP := 2.0
var _track_searched := false
## [{pts, ups, closed, rejoin, idx}] -- rejoin = main distance at a branch's
## end (-1 on the main line), idx = nearest sample last frame (-1 = unknown).
var _paths: Array = []
var _cur_path := -1
var _track_ship: Node = null
var _track_weight := 0.0

## Give the camera the track it is racing on (ModeBase does this). Rebuilds
## the look-ahead samples; pass null to turn the look-ahead off.
func set_track(track_root: Node) -> void:
	_track_searched = true
	_paths = []
	_cur_path = -1
	if track_root == null:
		return
	var graph := _find_graph(track_root)
	var main: Path3D = graph.path_of(-1) if graph and graph.is_valid() else null
	if main == null:
		main = TrackSplineHelper.new()._find_track_spline(track_root)
	if not _add_path(main, -1.0):
		return
	if graph and graph.has_branches():
		for i in graph.branches.size():
			var bp := graph.path_of(i)
			if bp and bp.curve:
				_add_path(bp, graph.branch_to_main(i, graph.path_length(i)))

static func _find_graph(node: Node) -> TrackGraph:
	if node is TrackGraph:
		return node
	for c in node.get_children():
		var g := _find_graph(c)
		if g:
			return g
	return null

func _add_path(path: Path3D, rejoin: float) -> bool:
	if path == null or path.curve == null:
		return false
	var curve: Curve3D = path.curve
	var length := curve.get_baked_length()
	if length < TRACK_STEP * 4.0:
		return false
	var xf := path.global_transform
	var n := int(ceil(length / TRACK_STEP)) + 1
	var pts := PackedVector3Array()
	var ups := PackedVector3Array()
	for i in n:
		var d := minf(i * TRACK_STEP, length)
		pts.append(xf * curve.sample_baked(d))
		var up := xf.basis * curve.sample_baked_up_vector(d, true)
		ups.append(up.normalized() if up.length() > 0.001 else Vector3.UP)
	var closed := rejoin < 0.0 and (curve.closed or pts[0].distance_to(pts[n - 1]) < TRACK_STEP * 3.0)
	_paths.append({pts = pts, ups = ups, closed = closed, rejoin = rejoin, idx = -1})
	return true

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

func _exit_tree() -> void:
	MotionBlurEffect.speed_ratio = -1.0   # nothing drives the fade any more

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
	# drives the motion blur's speed fade (also keeps it off during the intro,
	# when the ship sits on the grid)
	MotionBlurEffect.speed_ratio = ship.get_speed_ratio()
	
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
	# v30: tighter frame follow inside magnetic zones (loops pitch the ship
	# ~100 deg/s; at the flat-track rates the camera trails it by ~30 deg).
	var boost: float = lerpf(1.0, magnetic_follow_boost, ship.magnet_weight)
	_cam_forward = _slerp_unit(_cam_forward, ship_forward, _w(yaw_follow_rate * boost, delta))
	_cam_up = _slerp_unit(_cam_up, ship_up, _w(up_follow_rate * boost, delta))
	
	# Re-orthogonalise. Note this never falls back to Vector3.UP, so the
	# camera survives banked, vertical and inverted track.
	var right := _cam_forward.cross(_cam_up)
	if right.length() < 0.001:
		right = ship.global_transform.basis.x
	right = right.normalized()
	_cam_up = right.cross(_cam_forward).normalized()

## v30: slerp that survives parallel vectors (dead-straight flat road at
## constant speed); see ShipController.slerp_safe().
static func _slerp_unit(a: Vector3, b: Vector3, weight: float) -> Vector3:
	return ShipController.slerp_safe(a, b, weight).normalized()

func _build_basis() -> Basis:
	var right := _cam_forward.cross(_cam_up).normalized()
	return Basis(right, _cam_up, -_cam_forward)

func _desired_position(ship_pos: Vector3, frame: Basis, ratio: float, delta: float) -> Vector3:
	var swing := _update_swing(ratio, delta)
	var offset := Vector3(
		swing,
		base_height + speed_height * ratio,
		base_distance + speed_distance * ratio + _update_boost_lag(delta)
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

	# v35: lead down the upcoming track. Same look_distance, so this only
	# turns the aim; it does not move it further away or change the framing.
	var track_dir := _track_look_dir(ship_pos, ship_forward)
	var want := track_look_weight if track_look_enabled and track_dir != Vector3.ZERO else 0.0
	_track_weight = lerpf(_track_weight, want, _w(4.0, delta))
	if _track_weight > 0.001 and track_dir != Vector3.ZERO:
		aim_dir = ShipController.slerp_safe(aim_dir, track_dir, _track_weight).normalized()

	var target := ship_pos + aim_dir * look_distance + ship_up * aim_height
	_aim_point += ship.velocity * delta * aim_feedforward
	_aim_point = _aim_point.lerp(target, _w(aim_follow_rate, delta))

## v35: unit direction from the ship to where it will be track_look_time
## from now if it follows the track at its current lateral and vertical
## offset, or ZERO when there is no usable track here. Carrying the offset
## across cancels a constant road-vs-spline offset, so this works on the
## older circuits whose road does not sit exactly on MainSpline. On a fork
## the ship follows whichever centre line it is nearest, and a look-ahead
## that runs off the end of a branch carries on along the main line from
## the rejoin.
func _track_look_dir(ship_pos: Vector3, ship_forward: Vector3) -> Vector3:
	if not track_look_enabled:
		return Vector3.ZERO
	if not _track_searched:
		_track_searched = true
		var scene := get_tree().current_scene
		if scene:
			set_track(scene)
	if _paths.is_empty():
		return Vector3.ZERO
	if ship != _track_ship:
		_track_ship = ship
		_reset_track_search()
	_locate(ship_pos)
	var P: Dictionary = _paths[_cur_path]
	var pts: PackedVector3Array = P.pts
	var i: int = P.idx
	var j := _step_idx(P, i, 1)
	if j == i:
		i = _step_idx(P, i, -1)
		j = P.idx
	var seg := pts[j] - pts[i]
	if seg.length_squared() < 0.0001:
		return Vector3.ZERO
	# Where along the track the ship is, and its offset in the track frame.
	var t := clampf((ship_pos - pts[i]).dot(seg) / seg.length_squared(), 0.0, 1.0)
	var f := float(i) + t
	var here := _track_frame(_cur_path, f)
	var rel := ship_pos - (here[0] as Vector3)
	var lateral := rel.dot(here[1] as Vector3)
	var vertical := rel.dot(here[2] as Vector3)
	var fade := 1.0 - clampf((absf(lateral) - track_look_fade_lateral) / 15.0, 0.0, 1.0)
	if fade <= 0.0:
		return Vector3.ZERO
	var look := clampf(ship.velocity.length() * track_look_time, track_look_min, track_look_max)
	var ahead_path := _cur_path
	var ahead_f := f + look / TRACK_STEP
	var last := float(pts.size() - 1)
	if not P.closed and ahead_f > last and float(P.rejoin) >= 0.0:
		ahead_path = 0
		ahead_f = (float(P.rejoin) + (ahead_f - last) * TRACK_STEP) / TRACK_STEP
	var ahead := _track_frame(ahead_path, ahead_f)
	var target: Vector3 = (ahead[0] as Vector3) + (ahead[1] as Vector3) * lateral + (ahead[2] as Vector3) * vertical
	var dir := target - ship_pos
	if dir.length() < 1.0:
		return Vector3.ZERO
	dir = dir.normalized()
	if dir.dot(ship_forward) < 0.0:
		return Vector3.ZERO   # facing backwards, spun out: keep the plain aim
	return ShipController.slerp_safe(ship_forward, dir, fade).normalized() if fade < 1.0 else dir

func _reset_track_search() -> void:
	_cur_path = -1
	for P in _paths:
		P.idx = -1

func _step_idx(P: Dictionary, i: int, k: int) -> int:
	var n: int = (P.pts as PackedVector3Array).size()
	return wrapi(i + k, 0, n - 1) if P.closed else clampi(i + k, 0, n - 1)

## [position, right, up] at a fractional sample index on path `pi`.
func _track_frame(pi: int, f: float) -> Array:
	var P: Dictionary = _paths[pi]
	var pts: PackedVector3Array = P.pts
	var ups: PackedVector3Array = P.ups
	var n := pts.size()
	f = fposmod(f, float(n - 1)) if P.closed else clampf(f, 0.0, float(n - 1))
	var i := mini(int(f), n - 2)
	var k := f - float(i)
	var p := pts[i].lerp(pts[i + 1], k)
	var up := ups[i].lerp(ups[i + 1], k)
	var tangent := pts[i + 1] - pts[i]
	if tangent.length_squared() < 0.0001:
		tangent = -ship.global_transform.basis.z
	tangent = tangent.normalized()
	var right := tangent.cross(up)
	if right.length_squared() < 0.0001:
		right = ship.global_transform.basis.x
	right = right.normalized()
	up = right.cross(tangent).normalized()
	return [p, right, up]

## Nearest sample on every centre line -- a short window around last frame's,
## or the whole line on the first frame or after a jump in position (respawn,
## a line the ship is nowhere near). The window keeps multi-level tracks from
## snapping to the deck above or below. The ship then follows the nearest
## line, sticking with the current one unless another is clearly closer.
func _locate(pos: Vector3) -> void:
	var best_path := -1
	var best_sq := INF
	var cur_sq := INF
	for pi in _paths.size():
		var P: Dictionary = _paths[pi]
		var pts: PackedVector3Array = P.pts
		var b := -1
		var bsq := INF
		if int(P.idx) >= 0:
			for k in range(-20, 41):
				var i := _step_idx(P, P.idx, k)
				var sq := pos.distance_squared_to(pts[i])
				if sq < bsq:
					bsq = sq
					b = i
		if b < 0 or bsq > 60.0 * 60.0:
			for i in pts.size():
				var sq := pos.distance_squared_to(pts[i])
				if sq < bsq:
					bsq = sq
					b = i
		P.idx = b
		if pi == _cur_path:
			cur_sq = bsq
		if bsq < best_sq:
			best_sq = bsq
			best_path = pi
	if _cur_path < 0 or sqrt(best_sq) < sqrt(cur_sq) - 2.0:
		_cur_path = best_path

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

## v35: extra chase distance while the ship runs above max_speed on a boost.
## Follows the speed excess, so it surges out on the pad and eases back in as
## the overspeed bleeds off.
func _update_boost_lag(delta: float) -> float:
	var target := 0.0
	if boost_lag_enabled and not _intro_active:
		var excess: float = ship.velocity.length() - ship._max_speed
		target = boost_lag_distance * clampf(excess / maxf(boost_lag_ref_speed, 1.0), 0.0, 1.5)
	var rate := boost_lag_attack if target > _boost_lag else boost_lag_release
	_boost_lag = lerpf(_boost_lag, target, _w(rate, delta))
	return _boost_lag

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
	MotionBlurEffect.notify_camera_cut()
	var pose: Array = _chase_pose()
	_cam_position = pose[0]
	# v2.1: this used to omit the `ship_up * aim_height` term that _update_aim()
	# applies every frame, so frame one started with a 1-unit aim mismatch that
	# the aim spring then had to chase out.
	_aim_point = pose[1]
	_collision_distance = _cam_position.distance_to(ship.global_position)
	_swing = 0.0
	_bank = 0.0
	_boost_lag = 0.0
	_reset_track_search()
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
