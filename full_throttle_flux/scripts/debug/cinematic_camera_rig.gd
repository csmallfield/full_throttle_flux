extends Node3D
class_name CinematicCameraRig

## Cinematic camera director, ported from the MotorRig chase_camera_rig.
##
## Thirteen cameras, every one updated every physics tick whether or not it is
## on screen, so switching never jumps and a camera you come back to has been
## tracking the whole time.
##
##   cockpit    rigid mount at the nose, looking ahead
##   heli       high overhead follow, slow heading lag, looking down with lead
##   front      tracking camera ahead of the ship, looking back at it
##   side       Russian-arm profile: alongside, matching speed, slight lead
##   flank      rigid mount low on the left flank, looking forward along the hull
##   bumper     rigid mount on the nose, looking ahead
##   trackside  broadcast camera planted ahead; pans and zooms as the ship
##              passes, then leapfrogs ahead again
##   crane      starts low ahead, cranes up and back over the ship as it passes
##   drone      loose FPV chase: swings wide on the outside of turns
##   lowchase   low behind the ship, long lens
##   pan        locked-off tripod that only pans and tilts, replants when far
##   tail       rigid mount at the tail, looking forward along the hull
##   orbit      slow orbit around the ship
##
## CHANGES FROM MOTORRIG
## ---------------------------------------------------------------------------
## * Follows a ShipController rather than a DrivingCar, and takes velocity and
##   yaw rate straight off it (`velocity`, `measured_yaw_rate`) instead of
##   reading a RigidBody3D or differencing positions.
## * The three wheel-dependent cameras have no meaning on an anti-grav ship.
##   `wheel` and `rearwheel` became `flank` and `tail`, rigid mounts derived
##   from the hull bounds, and `driver` became `cockpit`, since FTF ships have
##   no DriverCam node.
## * No `chase`: AGCamera2097 already is the chase camera, and it is better
##   than a spring arm here. AISpectator puts it first in the cycle.
## * Distances scale with the ship's top speed as well as its size. These
##   ships run at 120 units/sec against a car's ~30, so a trackside camera
##   planted 30m ahead is passed before it has finished panning.
## * No take recording or replay ghosts.

signal camera_changed(camera_name: String)

## Order of the cycle.
const CAMERA_NAMES: PackedStringArray = [
	"cockpit", "heli", "front", "side", "flank", "bumper", "trackside",
	"crane", "drone", "lowchase", "pan", "tail", "orbit",
	# Wilder set: near-misses, overshoot, lens violence, losing the subject.
	"handheld", "overtake", "kamikaze", "vertigo", "roadkill",
	"helilost", "whip", "crashzoom", "skim", "crossing", "fisheye",
	"fisheye_rear",
]

## Track surface (layer 1) and walls (layer 3), matching AGCamera2097.
@export_flags_3d_physics var ground_mask: int = 5

## Reference hull length the framing was authored for.
@export var reference_length: float = 5.0

## Reference top speed the plant distances were authored for.
@export var reference_speed: float = 120.0

@export_group("Trackside")
## Metres past the camera the ship must travel before it leapfrogs ahead.
##
## These are distances, but what matters is how long a shot runs, so they are
## set from measured speed: the ship covers ~105 units/sec on circuit 7, so
## the numbers below give a six second shot. Note these are STRAIGHT-LINE
## ranges, and on a track that curves the ship's distance from the plant grows
## noticeably slower than the distance it drives -- 470 units of range ran 8.5
## seconds, not the 6 the arithmetic suggested, so they were measured rather
## than calculated. Long shots also read as distant shots, because the ship
## keeps receding until the cut.
@export var trackside_hold_past: float = 330.0
## Replant once the ship is this far away in any direction.
@export var trackside_max_range: float = 470.0
## Height above the surface.
@export var trackside_height: float = 5.5
@export var trackside_clearance: float = 4.0
## How far ahead it plants, as a multiple of current speed. ~1.5s of approach.
@export var trackside_lead_factor: float = 1.5
@export var trackside_lead_min: float = 60.0
@export var trackside_lead_max: float = 170.0

@export_group("Crane")
## Seconds for the crane to complete its rise. Must be comfortably shorter
## than the shot, or the move gets cut off part way through.
@export var crane_rise_seconds: float = 3.5
## How far ahead it plants, as a multiple of current speed.
@export var crane_lead_factor: float = 1.5
@export var crane_lead_min: float = 60.0
@export var crane_lead_max: float = 170.0
## Long enough that the rise above completes, short enough to stay close.
@export var crane_hold_past: float = 330.0
@export var crane_max_range: float = 470.0
## Height at the start of the move, and how much it rises by.
@export var crane_base_height: float = 4.0
@export var crane_rise_height: float = 18.0
@export var crane_clearance: float = 3.0

@export_group("Pan")
@export var pan_height: float = 8.0
@export var pan_clearance: float = 6.0
## Replant only once the ship is this far off; a locked tripod should hold.
## The tripod never moves, so its whole shot is the ship receding. ~6 seconds
## at racing speed; at 1400 it ran 34s and ended with the ship a speck.
@export var pan_max_range: float = 520.0

@export_group("Wild cameras")
## Handheld shake amplitude, in metres at reference hull size.
@export var handheld_shake: float = 0.11
## Seconds for one overtake pass: behind, alongside, ahead, and back.
@export var overtake_period: float = 7.0
## Length of one kamikaze take, seconds. Contact lands in the middle.
@export var kamikaze_take_seconds: float = 4.6
## Camera speed as a fraction of the ship's, flying the other way.
@export var kamikaze_speed_fraction: float = 0.55
## Seconds for one full vertigo push-in and pull-out, per approach angle.
@export var vertigo_period: float = 8.0
## Seconds between crash zoom punches.
@export var crashzoom_period: float = 5.0
## Seconds between the heli losing the ship and reacquiring it.
@export var helilost_period: float = 9.0
## How long the cable cam takes to cross, as a fraction of the crossing per
## second. 0.14 is about seven seconds; 0.33 was about three and read as a
## flyby rather than a crossing.
@export var crossing_rate: float = 0.14
## Height above the surface, and the minimum it keeps. Raised because at 6.5
## it was catching the track on climbs and banked sections.
@export var crossing_height: float = 12.0
@export var crossing_clearance: float = 9.0
## Multiplier on how far the fisheye mounts stand off the hull. 1.0 is the
## v25 framing; higher gives the ship more room in frame.
@export var fisheye_standoff: float = 1.2

@export_group("Orbit")
## The orbit ramps between these rates rather than turning at a constant
## speed, so it eases into a fast sweep and back out again.
@export var orbit_speed_min: float = 0.15
@export var orbit_speed_max: float = 1.10
## How quickly it moves between the two, in cycles per second.
@export var orbit_ramp_rate: float = 0.35

var cameras: Array[Camera3D] = []
var active_camera: Camera3D

var _target: ShipController
var _cams: Dictionary = {}
var _state: Dictionary = {}
var _space: PhysicsDirectSpaceState3D
## Optional. Several cameras need to know where the track is rather than just
## where the ship is: clamping a plant so it cannot wander off into scenery,
## putting a camera ON the racing surface, and flying the kamikaze camera
## along the track rather than straight through the walls beside a corner.
## AISpectator supplies this from the AI's own spline helper.
var spline: TrackSplineHelper

var _body := Vector3(1.6, 1.2, 5.0)
var _vel := Vector3.ZERO

func _ready() -> void:
	top_level = true
	for n in CAMERA_NAMES:
		var cam := Camera3D.new()
		cam.name = "Cam_" + n
		cam.top_level = true
		cam.near = 0.05
		cam.far = 6000.0
		add_child(cam)
		cameras.append(cam)
		_cams[n] = cam
	set_physics_process(false)

## Point every camera at a ship. Safe to call repeatedly.
func follow(ship: ShipController) -> void:
	if ship == _target:
		return
	_target = ship
	_body = _measure_hull(ship)
	set_physics_process(_target != null)
	if _target:
		snap()

func snap() -> void:
	_state.clear()
	if _target:
		_update(0.0, true)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_target):
		set_physics_process(false)
		return
	_update(delta, false)

# ============================================================================
# CYCLE
# ============================================================================

func cycle(step: int) -> void:
	if cameras.is_empty():
		return
	var i := cameras.find(active_camera)
	select_index(wrapi(i + step, 0, cameras.size()))

func select_index(i: int) -> void:
	if i < 0 or i >= cameras.size():
		return
	active_camera = cameras[i]
	active_camera.make_current()
	camera_changed.emit(CAMERA_NAMES[i])

func active_name() -> String:
	var i := cameras.find(active_camera)
	return CAMERA_NAMES[i] if i >= 0 else ""

## Stop driving the view; the caller makes its own camera current again.
func release() -> void:
	active_camera = null

# ============================================================================
# SCALE
# ============================================================================

## One factor from the hull's own size scales every distance and height, so a
## longer ship is framed further out.
func _size_scale() -> float:
	return clampf(maxf(_body.z, _body.y * 2.2) / reference_length, 0.8, 3.0)

## And one from its top speed, so plants stay ahead of a faster ship.
func _speed_scale() -> float:
	if _target == null or _target.profile == null:
		return 1.0
	return clampf(_target.get_max_speed() / maxf(reference_speed, 1.0), 0.6, 3.0)

## Hull bounds from the ship's collision shape, falling back to a sane guess.
func _measure_hull(ship: ShipController) -> Vector3:
	if ship == null:
		return Vector3(1.6, 1.2, 5.0)
	for child in ship.get_children():
		if child is CollisionShape3D and child.shape != null:
			var s: Shape3D = child.shape
			var sc: Vector3 = child.scale * ship.scale
			if s is CapsuleShape3D:
				var c := s as CapsuleShape3D
				return Vector3(c.radius * 2.0 * sc.x, c.radius * 2.0 * sc.y,
						c.height * sc.z)
			if s is BoxShape3D:
				return (s as BoxShape3D).size * sc
			if s is SphereShape3D:
				var r: float = (s as SphereShape3D).radius
				return Vector3(r * 2.0, r * 2.0, r * 2.0) * sc
	return Vector3(1.6, 1.2, 5.0)

# ============================================================================
# THE CAMERAS
# ============================================================================

func _update(dt: float, snap_now: bool) -> void:
	if _space == null:
		_space = get_world_3d().direct_space_state
	
	var k := _size_scale()
	var sp := _speed_scale()
	var f := _target.global_transform
	var p := f.origin
	var fwd := -f.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.FORWARD
	var vel: Vector3 = _target.velocity
	_vel = vel
	var side_dir := fwd.cross(Vector3.UP).normalized()
	
	# cockpit: rigid at the nose, looking ahead
	_rigid("cockpit", f, Vector3(0.0, _body.y * 0.35, -_body.z * 0.20),
			Vector3(0.0, _body.y * 0.30, -_body.z * 0.5 - 40.0), 78.0)
	
	# heli: high and behind, slow heading, looking down with lead
	var hf := _smooth_dir("heli_dir", fwd, 1.0, dt, snap_now)
	_place("heli", _clear_ground(p + Vector3.UP * (28.0 * k) - hf * (18.0 * k * sp), 10.0),
			p + fwd * (8.0 * sp), 2.5, 6.0, 35.0, dt, snap_now)
	
	# front: tracking ahead, looking back
	var ff := _smooth_dir("front_dir", fwd, 3.0, dt, snap_now)
	_place("front", _clear_ground(p + ff * (11.0 * k) + Vector3.UP * (1.6 * k), 0.8),
			p + Vector3.UP * (0.5 * k), 6.0, 10.0, 50.0, dt, snap_now)
	
	# side: Russian arm alongside, slight lead
	var sf := _smooth_dir("side_dir", fwd, 3.0, dt, snap_now)
	_place("side", _clear_ground(p - sf.cross(Vector3.UP).normalized() * (7.5 * k)
			+ Vector3.UP * (1.3 * k) + sf * 1.5, 0.7),
			p + Vector3.UP * (0.5 * k), 5.0, 10.0, 42.0, dt, snap_now)
	
	# flank: rigid low on the left side, looking forward along the hull
	_rigid("flank", f, Vector3(-_body.x * 0.9, -_body.y * 0.1, _body.z * 0.15),
			Vector3(-_body.x * 0.3, -_body.y * 0.1, -_body.z * 0.5 - 6.0), 70.0)
	
	# bumper: rigid on the nose, looking ahead
	_rigid("bumper", f, Vector3(0.0, -_body.y * 0.25, -_body.z * 0.5 - 0.1),
			Vector3(0.0, -_body.y * 0.25, -_body.z * 0.5 - 25.0), 75.0)
	
	# trackside: planted ahead, pans and zooms, leapfrogs once passed or far
	var ts: Dictionary = _state.get("trackside", {})
	var plant: Vector3 = ts.get("plant", Vector3.INF)
	var rel := p - plant
	var replant: bool = snap_now or plant == Vector3.INF \
			or rel.length() > trackside_max_range * sp \
			or rel.dot(fwd) > trackside_hold_past * sp
	if replant:
		var side_sign: float = -float(ts.get("side", 1.0))
		var ahead: float = clampf(maxf(vel.length(), 20.0) * trackside_lead_factor,
				trackside_lead_min, trackside_lead_max)
		plant = _clear_ground(p + fwd * ahead + side_dir * (11.0 * k) * side_sign
				+ Vector3.UP * (trackside_height * k), trackside_clearance)
		_state["trackside"] = {"plant": plant, "side": side_sign}
	var dist := plant.distance_to(p)
	_look("trackside", plant, p + Vector3.UP * (0.5 * k), 8.0, snap_now or replant,
			clampf(rad_to_deg(2.0 * atan(5.0 * k / maxf(dist, 1.0))), 6.0, 55.0), dt)
	
	# crane: plant ahead and low, rise and swing back over the ship
	var cr: Dictionary = _state.get("crane", {})
	var cplant: Vector3 = cr.get("plant", Vector3.INF)
	var crel := p - cplant
	var crane_replant: bool = snap_now or cplant == Vector3.INF \
			or crel.length() > crane_max_range * sp or crel.dot(fwd) > crane_hold_past * sp
	if crane_replant:
		cplant = _clear_ground(p + fwd * clampf(maxf(vel.length(), 20.0) * crane_lead_factor,
				crane_lead_min, crane_lead_max) + side_dir * (6.0 * k), crane_clearance)
		cr = {"plant": cplant, "t": 0.0}
		_state["crane"] = cr
	var ct: float = minf(float(cr.get("t", 0.0)) + dt / maxf(crane_rise_seconds, 0.1), 1.0)
	cr["t"] = ct
	var rise := ct * ct * (3.0 - 2.0 * ct)
	# The crane holds for ten seconds or more now, and the ship covers a long
	# way in that time, so it zooms as the ship recedes the way the trackside
	# and pan cameras do. Without this the shot ends on a speck: measured at
	# 717 units away still on a 42 degree lens.
	var crane_fov: float = clampf(rad_to_deg(2.0 * atan(6.0 * k
			/ maxf(cplant.distance_to(p), 1.0))), 6.0, lerpf(50.0, 42.0, rise))
	_place("crane", _clear_ground(cplant + Vector3.UP * ((crane_base_height
			+ crane_rise_height * rise) * k) - fwd * (22.0 * rise * k), crane_clearance),
			p + Vector3.UP * 0.5, 6.0, 5.0, crane_fov, dt, crane_replant, false)
	
	# drone: swings to the outside of the turn, breathes in height.
	# measured_yaw_rate is positive to the left, so the camera swings right.
	var turn := clampf(-_target.measured_yaw_rate * 0.9, -1.0, 1.0)
	var bob: float = float(_state.get("orbit_ang", 0.0)) * 0.6
	_place("drone", _clear_ground(p - fwd * (9.0 * k) + side_dir * (6.0 * turn * k)
			+ Vector3.UP * (3.8 * k + 0.8 * sin(bob)), 1.4),
			p + fwd * 5.0, 3.0, 4.0, 55.0, dt, snap_now)
	
	# lowchase: low, close, long lens
	var lf := _smooth_dir("low_dir", fwd, 2.0, dt, snap_now)
	_place("lowchase", _clear_ground(p - lf * (8.5 * k) + Vector3.UP * (0.6 * k), 0.5),
			p + Vector3.UP * (0.6 * k), 8.0, 7.0, 34.0, dt, snap_now, true, 0.5)
	
	# pan: locked-off tripod. Only pans and tilts until the ship is too far.
	var pn: Dictionary = _state.get("pan", {})
	var pplant: Vector3 = pn.get("plant", Vector3.INF)
	if snap_now or pplant == Vector3.INF or pplant.distance_to(p) > pan_max_range * sp:
		pplant = _clear_ground(p - fwd * (18.0 * k) + side_dir * (20.0 * k)
				+ Vector3.UP * (pan_height * k), pan_clearance)
		_state["pan"] = {"plant": pplant}
	_look("pan", pplant, p + Vector3.UP * (0.5 * k), 5.0, snap_now,
			clampf(rad_to_deg(2.0 * atan(6.0 * k / maxf(pplant.distance_to(p), 1.0))), 6.0, 60.0), dt)
	
	# tail: rigid at the back, looking forward along the hull
	_rigid("tail", f, Vector3(_body.x * 0.55, _body.y * 0.2, _body.z * 0.5),
			Vector3(0.0, 0.0, -_body.z * 0.5 - 4.0), 68.0)
	
	# orbit: circles the ship on a speed ramp, easing between a slow drift and
	# a fast sweep rather than turning at one constant rate.
	var ophase: float = float(_state.get("orbit_phase", 0.0)) + dt * orbit_ramp_rate
	_state["orbit_phase"] = ophase
	var ramp := 0.5 - 0.5 * cos(ophase * TAU)
	var ang: float = float(_state.get("orbit_ang", 0.0)) \
			+ lerpf(orbit_speed_min, orbit_speed_max, ramp) * dt
	_state["orbit_ang"] = ang
	
	_update_wild(dt, snap_now, k, sp, p, fwd, side_dir, vel)
	_place("orbit", _clear_ground(p + Vector3(cos(ang), 0.0, sin(ang)) * (11.0 * k)
			+ Vector3.UP * (3.0 * k), 1.0),
			p + Vector3.UP * (0.5 * k), 8.0, 12.0, 50.0, dt, snap_now)

# ============================================================================
# WILD CAMERAS
# ============================================================================

## Everything above is broadcast coverage: safe framing, subject always held.
## These deliberately break that -- near-misses, overshoot, lens moves that
## draw attention to themselves, and a camera that loses the ship entirely.
func _update_wild(dt: float, snap_now: bool, k: float, sp: float, p: Vector3,
		fwd: Vector3, side_dir: Vector3, vel: Vector3) -> void:
	var speed: float = maxf(vel.length(), 20.0)
	var clock: float = float(_state.get("clock", 0.0)) + dt
	_state["clock"] = clock
	var up_pt := p + Vector3.UP * (0.5 * k)

	# handheld: operator at the edge of the track, wide lens, never steady,
	# and always a beat behind. Clamped to the track corridor -- left free it
	# wandered into scenery on open sections and lost the shot entirely.
	var hh: Dictionary = _state.get("handheld", {})
	var hplant: Vector3 = hh.get("plant", Vector3.INF)
	var hrel := p - hplant
	if snap_now or hplant == Vector3.INF or hrel.dot(fwd) > 220.0 * sp or hrel.length() > 380.0 * sp:
		var hside: float = -float(hh.get("side", 1.0))
		hplant = p + fwd * clampf(speed * 1.2, 60.0, 150.0) + side_dir * (5.0 * k) * hside
		# Measured at 9.0 the plants still read out to ~20 units off centre,
		# because height on a banked section adds to the measured lateral.
		hplant = _clamp_to_track(hplant, 6.0 * k)
		hplant = _clear_ground(hplant + Vector3.UP * (1.7 * k), 1.5)
		_state["handheld"] = {"plant": hplant, "side": hside}
	var shake := Vector3(sin(clock * 3.1) + 0.4 * sin(clock * 7.9),
			sin(clock * 2.3 + 1.1) + 0.3 * sin(clock * 6.1),
			sin(clock * 1.7 + 2.2)) * (handheld_shake * k)
	_look("handheld", hplant + shake, _spring("hh_aim", up_pt, 1.6, 0.45, dt, snap_now),
			9.0, snap_now, 82.0, dt)

	# overtake: comes up from behind, draws level, pulls ahead, drops back.
	var oph: float = fposmod(clock / maxf(overtake_period, 0.5), 1.0)
	var tri: float = 1.0 - absf(oph * 2.0 - 1.0)
	var ease_t := tri * tri * (3.0 - 2.0 * tri)
	_place("overtake", _clear_ground(p + fwd * lerpf(-34.0 * k, 46.0 * k, ease_t)
			+ side_dir * (7.5 * k) + Vector3.UP * (1.3 * k), 0.8),
			up_pt, 7.0, 8.0, lerpf(34.0, 62.0, tri), dt, snap_now)

	# kamikaze: flown along the SPLINE against the race direction, so it
	# follows the track through corners instead of flying into the wall on
	# the outside. Planted far enough ahead that contact lands in the middle
	# of the take, and it keeps going afterwards so the ship recedes behind
	# it rather than the shot cutting on the pass.
	_kamikaze(dt, snap_now, k, p, fwd, side_dir, speed, up_pt)

	# vertigo: dolly and zoom opposed, so the ship holds its size while the
	# track behind stretches and compresses. Each take approaches from a
	# different angle -- back, front, side, three-quarter, overhead.
	var vtake: int = int(clock / maxf(vertigo_period, 1.0))
	var vph: float = fposmod(clock / maxf(vertigo_period, 1.0), 1.0)
	var vramp := 0.5 - 0.5 * cos(vph * TAU)
	var vdist := lerpf(10.0 * k, 38.0 * k, vramp)
	var vdir := _angle_for(vtake, fwd, side_dir)
	var vfov := clampf(rad_to_deg(2.0 * atan(4.6 * k / maxf(vdist, 1.0))), 11.0, 96.0)
	_place("vertigo", _clear_ground(p + vdir * vdist + Vector3.UP * (1.9 * k), 0.8),
			up_pt, 9.0, 9.0, vfov, dt, snap_now)

	# roadkill: ON the surface and near the racing line, not beside it. The
	# lateral offset is taken from the spline rather than from the ship, so
	# it sits on the track even when the ship is running wide.
	var rk: Dictionary = _state.get("roadkill", {})
	var rplant: Vector3 = rk.get("plant", Vector3.INF)
	var rrel := p - rplant
	if snap_now or rplant == Vector3.INF or rrel.dot(fwd) > 110.0 * sp or rrel.length() > 260.0 * sp:
		var rside: float = -float(rk.get("side", 1.0))
		rplant = _on_track(p + fwd * clampf(speed * 1.1, 60.0, 140.0), 2.2 * k * rside)
		rplant = _clear_ground(rplant + Vector3.UP * (0.28 * k), 0.30)
		_state["roadkill"] = {"plant": rplant, "side": rside}
	var rnear: float = clampf(1.0 - rplant.distance_to(p) / (55.0 * k), 0.0, 1.0)
	_look("roadkill", rplant, p + Vector3.UP * (0.35 * k),
			lerpf(2.5, 16.0, rnear * rnear), snap_now, 96.0, dt)

	# helilost: drifts ahead, gets left behind, hauls back on. Both the lead
	# and the follow rate move on smooth curves now -- stepping them made the
	# recovery snap rather than drift.
	var lph: float = fposmod(clock / maxf(helilost_period, 1.0), 1.0)
	var lcurve := 0.5 - 0.5 * cos(lph * TAU)
	_place("helilost", _clear_ground(p + fwd * lerpf(26.0 * k, -30.0 * k, lcurve)
			+ side_dir * (9.0 * k) + Vector3.UP * (24.0 * k), 8.0),
			p, lerpf(0.22, 1.9, lcurve * lcurve), lerpf(0.5, 1.4, lcurve), 42.0, dt, snap_now)

	# whip: dead still on a wide lens, then snaps through the pass.
	var wh: Dictionary = _state.get("whip", {})
	var wplant: Vector3 = wh.get("plant", Vector3.INF)
	var wrel := p - wplant
	if snap_now or wplant == Vector3.INF or wrel.dot(fwd) > 130.0 * sp or wrel.length() > 280.0 * sp:
		var wside: float = -float(wh.get("side", 1.0))
		wplant = _clamp_to_track(p + fwd * clampf(speed * 1.3, 70.0, 170.0)
				+ side_dir * (4.2 * k) * wside, 8.0 * k)
		wplant = _clear_ground(wplant + Vector3.UP * (1.1 * k), 1.0)
		_state["whip"] = {"plant": wplant, "side": wside}
	var wnear: float = clampf(1.0 - wplant.distance_to(p) / (70.0 * k), 0.0, 1.0)
	_look("whip", wplant, up_pt, lerpf(1.4, 26.0, pow(wnear, 3.0)), snap_now, 74.0, dt)

	# crashzoom: punch in, HOLD, punch out, hold wide. The holds are the
	# point -- without them it read as a continuous pulse. Frontal and
	# three-quarter angles, which is where a zoom punch has something to
	# push into.
	var czph: float = fposmod(clock / maxf(crashzoom_period, 1.0), 1.0)
	var czfov: float
	if czph < 0.07:
		czfov = lerpf(72.0, 24.0, ease(czph / 0.07, 0.35))
	elif czph < 0.45:
		czfov = 24.0
	elif czph < 0.56:
		czfov = lerpf(24.0, 72.0, ease((czph - 0.45) / 0.11, 0.35))
	else:
		czfov = 72.0
	var czdir := _angle_for(int(clock / maxf(crashzoom_period, 1.0)), fwd, side_dir, true)
	_place("crashzoom", _clear_ground(p + czdir * (12.0 * k) + Vector3.UP * (2.0 * k), 1.0),
			up_pt, 6.0, 7.0, czfov, dt, snap_now)

	# skim: now AHEAD of the ship looking back, a hand's width off the
	# surface, sliding between four positions rather than cutting.
	var soff := _blend_offsets(clock, 4.5, [
			fwd * (7.0 * k) + Vector3.UP * (0.45 * k),
			fwd * (9.0 * k) + side_dir * (3.2 * k) + Vector3.UP * (1.2 * k),
			fwd * (9.0 * k) - side_dir * (3.2 * k) + Vector3.UP * (1.2 * k),
			fwd * (6.0 * k) + Vector3.UP * (3.2 * k)])
	_place("skim", _clear_ground(p + soff, 0.30), up_pt, 10.0, 11.0, 90.0, dt,
			snap_now, true, 0.30)

	# crossing: cable cam at its own constant speed. Sometimes it meets the
	# ship, sometimes it misses.
	var cs: Dictionary = _state.get("crossing", {})
	var ccentre: Vector3 = cs.get("centre", Vector3.INF)
	var caxis: Vector3 = cs.get("axis", side_dir)
	var ct2: float = float(cs.get("t", 0.0)) + dt * crossing_rate
	if snap_now or ccentre == Vector3.INF or ct2 >= 1.0 or (p - ccentre).dot(fwd) > 90.0 * sp:
		ccentre = p + fwd * clampf(speed * 1.6, 90.0, 240.0)
		caxis = side_dir
		ct2 = 0.0
	_state["crossing"] = {"centre": ccentre, "axis": caxis, "t": ct2}
	_look("crossing", _clear_ground(ccentre + caxis * lerpf(58.0 * k, -58.0 * k, ct2)
			+ Vector3.UP * (crossing_height * k), crossing_clearance),
			up_pt, 6.0, snap_now, 46.0, dt)

	# fisheye: hard-mounted on the nose looking BACK down the hull, on the
	# widest lens in the rig. Slides between four mounts -- on the deck
	# looking up, both three-quarters, and above looking down -- so the hull
	# swings through frame instead of cutting.
	var f := _target.global_transform
	var g := fisheye_standoff
	var mount := _blend_offsets(clock, 6.5, [
			Vector3(0.0, -_body.y * 0.45, -_body.z * 0.50 - 1.5 * g),
			Vector3(-_body.x * 1.60 * g, -_body.y * 0.15, -_body.z * 0.42 - 0.9 * g),
			Vector3(_body.x * 1.60 * g, -_body.y * 0.15, -_body.z * 0.42 - 0.9 * g),
			Vector3(0.0, _body.y * 1.50 * g, -_body.z * 0.40 - 0.9 * g)])
	var aim := _blend_offsets(clock, 6.5, [
			Vector3(0.0, _body.y * 1.10, _body.z * 0.60),
			Vector3(_body.x * 0.20, _body.y * 0.35, _body.z * 0.60),
			Vector3(-_body.x * 0.20, _body.y * 0.35, _body.z * 0.60),
			Vector3(0.0, -_body.y * 0.30, _body.z * 0.60)])
	_rigid("fisheye", f, mount, aim, 118.0)

	# fisheye_rear: the same idea mounted behind the tail, looking forward up
	# the hull. Offset by half a cycle so the two are never on the same mount
	# at the same time.
	var rmount := _blend_offsets(clock + 1.75, 6.5, [
			Vector3(0.0, -_body.y * 0.45, _body.z * 0.50 + 1.5 * g),
			Vector3(_body.x * 1.60 * g, -_body.y * 0.15, _body.z * 0.42 + 0.9 * g),
			Vector3(-_body.x * 1.60 * g, -_body.y * 0.15, _body.z * 0.42 + 0.9 * g),
			Vector3(0.0, _body.y * 1.50 * g, _body.z * 0.40 + 0.9 * g)])
	var raim := _blend_offsets(clock + 1.75, 6.5, [
			Vector3(0.0, _body.y * 1.10, -_body.z * 0.60),
			Vector3(-_body.x * 0.20, _body.y * 0.35, -_body.z * 0.60),
			Vector3(_body.x * 0.20, _body.y * 0.35, -_body.z * 0.60),
			Vector3(0.0, -_body.y * 0.30, -_body.z * 0.60)])
	_rigid("fisheye_rear", f, rmount, raim, 118.0)

## Cycles an approach direction per take: back, front, side, three-quarter,
## overhead. `frontal` drops the rear angles, for moves that need something
## to push into.
func _angle_for(take: int, fwd: Vector3, side_dir: Vector3, frontal: bool = false) -> Vector3:
	var options: Array[Vector3] = [fwd, (fwd + side_dir).normalized(),
			(fwd - side_dir).normalized(), side_dir]
	if not frontal:
		options = [-fwd, fwd, side_dir, (-fwd + side_dir).normalized(),
				(fwd - side_dir).normalized(), Vector3.UP * 0.9 + fwd * 0.3]
	return (options[posmod(take, options.size())] as Vector3).normalized()

## Hold each offset for `hold` seconds, then slide to the next over the last
## quarter of it. Transitions, never cuts.
func _blend_offsets(clock: float, hold: float, offsets: Array) -> Vector3:
	var n := offsets.size()
	var idx := int(clock / hold)
	var ph: float = fposmod(clock / hold, 1.0)
	var a: Vector3 = offsets[posmod(idx, n)]
	if ph < 0.75:
		return a
	var b: Vector3 = offsets[posmod(idx + 1, n)]
	var t: float = (ph - 0.75) / 0.25
	return a.lerp(b, t * t * (3.0 - 2.0 * t))

## Fly the kamikaze camera backwards along the spline into the oncoming ship.
func _kamikaze(dt: float, snap_now: bool, k: float, p: Vector3, fwd: Vector3,
		side_dir: Vector3, speed: float, up_pt: Vector3) -> void:
	var st: Dictionary = _state.get("kamikaze", {})
	var t: float = float(st.get("t", 999.0)) + dt
	var have_spline: bool = spline != null and spline.is_valid
	
	if snap_now or st.is_empty() or t > kamikaze_take_seconds:
		# Contact should land mid-take, so plant at the closing distance
		# covered in half of it.
		var closing: float = speed * (1.0 + kamikaze_speed_fraction)
		var ahead: float = clampf(closing * kamikaze_take_seconds * 0.5, 160.0, 700.0)
		var lat: float = 2.4 * k * (-float(st.get("side", 1.0)))
		var fallback := p + fwd * ahead + side_dir * lat + Vector3.UP * (2.6 * k)
		if have_spline:
			var here: float = spline.world_to_spline_offset(p)
			st = {"t": 0.0, "on_spline": true, "lat": lat, "side": signf(lat),
					"off": spline.get_lookahead_offset(here, ahead), "pos": fallback}
		else:
			st = {"t": 0.0, "on_spline": false, "lat": lat, "side": signf(lat),
					"off": 0.0, "pos": fallback}
		t = 0.0
	
	var pos: Vector3
	if have_spline and bool(st.get("on_spline", false)):
		# Negative lookahead walks back down the track, so the camera follows
		# the racing surface through corners instead of flying off the
		# outside of them. Wrapped, because walking backwards past the start
		# of the spline returns a negative offset -- which read as "no spline
		# position" and produced an infinite camera distance.
		var off: float = fposmod(spline.get_lookahead_offset(float(st["off"]),
				-speed * kamikaze_speed_fraction * dt), 1.0)
		st["off"] = off
		pos = spline.spline_offset_to_world_with_lateral(off, float(st["lat"]), true)
		# The spline is a centreline, not a surface: on elevation changes and
		# banked sections its point can sit well under the track, which put
		# this camera below the geometry looking at nothing. Every other
		# camera clears the ground; this one was not.
		pos = _clear_ground(pos + Vector3.UP * (2.4 * k), 2.4 * k)
	else:
		pos = st.get("pos", p)
		var to_ship: Vector3 = p - pos
		if to_ship.length() > 0.01:
			pos += to_ship.normalized() * (speed * kamikaze_speed_fraction) * dt
		pos = _clear_ground(pos, 2.4 * k)
		st["pos"] = pos
	st["t"] = t
	_state["kamikaze"] = st
	_look("kamikaze", pos, up_pt, 10.0, snap_now or t < dt * 1.5, 66.0, dt)

## Pull a point back toward the track centreline if it has strayed too far.
func _clamp_to_track(pos: Vector3, max_lateral: float) -> Vector3:
	if spline == null or not spline.is_valid:
		return pos
	var off: float = spline.world_to_spline_offset(pos)
	var lat: float = spline.calculate_lateral_offset(pos, off, true)
	if absf(lat) <= max_lateral:
		return pos
	var fixed := spline.spline_offset_to_world_with_lateral(off,
			clampf(lat, -max_lateral, max_lateral), true)
	fixed.y = maxf(fixed.y, pos.y)
	return fixed

## Put a point ON the track at a chosen distance from the centreline, taking
## the position from the spline rather than from wherever the ship happens to
## be running.
func _on_track(near: Vector3, lateral: float) -> Vector3:
	if spline == null or not spline.is_valid:
		return near
	var off: float = spline.world_to_spline_offset(near)
	return spline.spline_offset_to_world_with_lateral(off, lateral, true)

## Underdamped spring toward a moving point: overshoots, then settles. Used
## where a camera should feel operated rather than driven by maths.
func _spring(key: String, target: Vector3, freq: float, damping: float,
		dt: float, snap_now: bool) -> Vector3:
	var pos: Vector3 = _state.get(key + "_p", target)
	var vel: Vector3 = _state.get(key + "_v", Vector3.ZERO)
	if snap_now:
		pos = target
		vel = Vector3.ZERO
	else:
		var omega := TAU * freq
		vel += ((target - pos) * omega * omega - vel * (2.0 * damping * omega)) * dt
		pos += vel * dt
	_state[key + "_p"] = pos
	_state[key + "_v"] = vel
	return pos

# ============================================================================
# PLACEMENT HELPERS
# ============================================================================

## `follows_ship` adds velocity feedforward before converging, which removes
## the steady-state lag a first-order follow has against a moving target.
##
## MotorRig did not need this: its cars run at ~30 units/sec, where the lag is
## a couple of metres. These ships run at 120, and lag is speed/sharpness --
## 20 units for the tracking camera, 40 for the drone. Ported straight across,
## the "front" camera was 4 units from the ship instead of 15 (it was being
## run over) and the drone trailed at 49 instead of 12.
##
## Planted cameras (crane) pass false: their target does not move with the
## ship, so feedforward would only push them off their own plant.
## `clear_after` re-applies ground clearance to the SMOOTHED position.
##
## Clearing only the target is not enough for a low camera: the smoothing
## lerps toward that target from wherever the camera was, and the interpolated
## point can sit under the surface even though both ends are above it.
## Measured on skim, which spent 55 frames of a lap up to 3 metres below the
## track. Cameras placed through _look() are immune, since they are written
## directly rather than interpolated.
func _place(n: String, target: Vector3, look_at_pt: Vector3, pos_sharp: float,
		rot_sharp: float, fov: float, dt: float, snap_now: bool,
		follows_ship: bool = true, clear_after: float = -1.0) -> void:
	var cam: Camera3D = _cams[n]
	var pos := target
	if not snap_now:
		var from := cam.global_position + (_vel * dt if follows_ship else Vector3.ZERO)
		pos = from.lerp(target, 1.0 - exp(-pos_sharp * dt))
	if clear_after >= 0.0:
		pos = _clear_ground(pos, clear_after)
	_look(n, pos, look_at_pt, rot_sharp, snap_now, fov, dt)

func _look(n: String, pos: Vector3, look_at_pt: Vector3, rot_sharp: float,
		snap_now: bool, fov: float, dt: float = 0.0) -> void:
	var cam: Camera3D = _cams[n]
	var dir := look_at_pt - pos
	if dir.length_squared() < 1e-6:
		return
	var up := Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.FORWARD
	var want := Basis.looking_at(dir, up)
	var b := want if snap_now else cam.global_basis.orthonormalized().slerp(
			want, 1.0 - exp(-rot_sharp * dt))
	cam.global_transform = Transform3D(b, pos)
	cam.fov = fov

## Rigid mount in the ship's own frame, so it inherits roll and pitch.
func _rigid(n: String, f: Transform3D, local_pos: Vector3, local_look: Vector3, fov: float) -> void:
	var cam: Camera3D = _cams[n]
	var pos := f * local_pos
	var dir := (f * local_look) - pos
	if dir.length_squared() < 1e-6:
		return
	cam.global_transform = Transform3D(Basis.looking_at(dir, f.basis.y), pos)
	cam.fov = fov

func _smooth_dir(key: String, want: Vector3, sharp: float, dt: float, snap_now: bool) -> Vector3:
	var cur: Vector3 = _state.get(key, want)
	if snap_now or cur.dot(want) < -0.99:
		cur = want
	else:
		cur = cur.slerp(want, 1.0 - exp(-sharp * dt)).normalized()
	_state[key] = cur
	return cur

## Lift a camera above whatever surface is under it. On a track that banks and
## climbs this matters more than it does on a road.
func _clear_ground(pos: Vector3, min_height: float) -> Vector3:
	if _space == null:
		return pos
	var q := PhysicsRayQueryParameters3D.create(
			pos + Vector3.UP * 400.0, pos + Vector3.DOWN * 400.0, ground_mask)
	var hit := _space.intersect_ray(q)
	if hit:
		pos.y = maxf(pos.y, (hit["position"] as Vector3).y + min_height)
	return pos
