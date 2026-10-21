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
##
## LOOPS AND BARREL ROLLS (v30)
## ---------------------------------------------------------------------------
## On tracks with magnetic zones (MagneticTrack) every camera is handled by
## what it physically is, not by rotating the whole rig:
##
##   MOUNTED on the ship -- cockpit, flank, bumper, tail, fisheye,
##     fisheye_rear. Already in the ship's own frame; they roll and loop with
##     it. Unchanged.
##   RIDING the track -- front, side, lowchase, skim, drone, overtake, orbit,
##     vertigo, crashzoom, kamikaze. Camera ships flying the course with the
##     racer. Inside a zone their offsets, "up" and ground clearance follow
##     the ROAD (the ship's up) instead of world Y, so they go round the loop
##     and roll with the racer. Heading smoothing stays in the road plane.
##   FIXED TO THE TRACK -- roadkill, whip. Bolted to the road surface, so
##     inside a zone they sit on the (possibly inverted) road, oriented by it.
##   WITNESSES in the world -- trackside, crane, pan, crossing, handheld,
##     heli, helilost. Tripods, cranes, cable cams, people and helicopters
##     can't loop. They stay world-up, never stand inside a zone's swept
##     space, and when a shot would cover a zone they watch it from outside:
##     from the side, looking through a loop (the only place the racer is
##     visible all the way round), or beside a roll.
##
## On tracks without zones none of this runs and every camera is
## bit-identical to before (verified with tools/dev/cine_rig_probe.gd).

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

@export_group("Magnetic zones (loops, rolls)")
## Swept cross-section of the road plus walls around the spline, used to keep
## witness cameras out of the space a loop or roll sweeps through. Matches the
## greybox test-circuit section (road edge 21.5, outer wall face 28.6, wall
## top 8.5, slab 2 below).
@export var zone_envelope_half_width: float = 30.0
@export var zone_envelope_height: float = 10.0
@export var zone_envelope_depth: float = 3.0
## Extra clearance kept from the swept space.
@export var zone_envelope_margin: float = 6.0
## Where witnesses stand, chosen by measurement (cine_rig_probe CR_ANALYZE=1,
## raycasting the racer's recorded path from a grid of candidate spots):
##   loop: beside it, level with its hub plus `zone_witness_rise`, about 25 m
##         outside its footprint -- 87% of the lap in view. 130 m out managed
##         under 75%: the racer hugs the near wall at the bottom and a distant
##         camera can't see over it.
##   roll: beside its last fifth looking back down it, `zone_roll_witness_height`
##         up -- 58%. A roll hides the racer behind its own road for part of
##         every turn from anywhere off the centreline; anywhere from 80% of
##         the way along to past the exit measures the same, so the closest.
## The side (left/right of the zone) is picked per zone by raycasting the
## road from both.
@export var zone_witness_standoff: float = 25.0
@export var zone_witness_rise: float = 20.0
@export var zone_roll_witness_height: float = 12.0
## Witness shots on a zone end once the ship is this far past it.
@export var zone_after_margin: float = 60.0
## The helicopters start moving out to their zone position this far before
## a zone, and drift back this far after it.
@export var zone_heli_lead: float = 250.0
@export var zone_heli_tail: float = 150.0
## The cable cam crosses THROUGH a loop along its axis (it never touches the
## road; the racer is in view the whole way round). Off = it crosses over
## the top like it does for a roll.
@export var crossing_through_loops: bool = true
## How far above a riding camera to look for the road under it.
@export var ride_clear_search: float = 20.0

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

# v30: per-tick frames. See the header. Outside magnetic zones the ride frame
# IS the old world frame and the witness heading IS the old heading.
var _w := 0.0                 # ship's magnet weight
var _ru := Vector3.UP         # riding cameras' up (road up in zones)
var _rf := Vector3.FORWARD    # riding cameras' forward (in the road plane)
var _rs := Vector3.RIGHT      # riding cameras' right
var _fw := Vector3.FORWARD    # witness heading (held while in a zone)
var _sw := Vector3.RIGHT
var _ship_d := -1.0           # ship's distance along the spline (zone tracks)
var _zones: Array[Dictionary] = []
var _zones_built := false
# Riding cameras carry their offset with the road's rotation between ticks.
var _ride_rot := Quaternion.IDENTITY
var _carry_from := Vector3.ZERO
var _prev_ru := Vector3.UP
var _prev_ship_p := Vector3.INF

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
	_update_frames(f, fwd, side_dir, snap_now)
	var rf := _rf
	var rs := _rs
	var ru := _ru
	var fw := _fw
	var sw := _sw
	
	# --- MOUNTED: the ship's own frame; loops and rolls with it -------------
	
	# cockpit: rigid at the nose, looking ahead
	_rigid("cockpit", f, Vector3(0.0, _body.y * 0.35, -_body.z * 0.20),
			Vector3(0.0, _body.y * 0.30, -_body.z * 0.5 - 40.0), 78.0)
	
	# heli: WITNESS. High and behind, slow heading, looking down with lead.
	# A helicopter can't loop: near a zone it moves out to the side and
	# tracks the ship from there (see _heli_zone).
	var hf := _smooth_dir("heli_dir", fw, 1.0, dt, snap_now)
	var heli_lead: Vector3 = fwd if _w <= 0.0 else -f.basis.z
	var heli_target := _clear_ground(p + Vector3.UP * (28.0 * k) - hf * (18.0 * k * sp), 10.0)
	var heli_fov := 35.0
	if not _zones.is_empty():
		var hz := _heli_zone("heli", heli_target, 28.0 * k, 0.0)
		heli_target = hz[0]
		heli_fov = lerpf(35.0, clampf(rad_to_deg(2.0 * atan(9.0 * k
				/ maxf(_cams["heli"].global_position.distance_to(p), 1.0))), 12.0, 35.0), hz[1])
	_place("heli", heli_target, p + heli_lead * (8.0 * sp), 2.5, 6.0, heli_fov, dt, snap_now)
	
	# --- RIDING: camera ships flying the course; road frame in zones ---------
	
	# front: tracking ahead, looking back
	var ff := _smooth_dir("front_dir", rf, 3.0, dt, snap_now, ru)
	_place("front", _clear_ride(p + ff * (11.0 * k) + ru * (1.6 * k), 0.8),
			p + ru * (0.5 * k), 6.0, 10.0, 50.0, dt, snap_now, true, -1.0, true)
	
	# side: Russian arm alongside, slight lead
	var sf := _smooth_dir("side_dir", rf, 3.0, dt, snap_now, ru)
	_place("side", _clear_ride(p - sf.cross(ru).normalized() * (7.5 * k)
			+ ru * (1.3 * k) + sf * 1.5, 0.7),
			p + ru * (0.5 * k), 5.0, 10.0, 42.0, dt, snap_now, true, -1.0, true)
	
	# flank: rigid low on the left side, looking forward along the hull
	_rigid("flank", f, Vector3(-_body.x * 0.9, -_body.y * 0.1, _body.z * 0.15),
			Vector3(-_body.x * 0.3, -_body.y * 0.1, -_body.z * 0.5 - 6.0), 70.0)
	
	# bumper: rigid on the nose, looking ahead
	_rigid("bumper", f, Vector3(0.0, -_body.y * 0.25, -_body.z * 0.5 - 0.1),
			Vector3(0.0, -_body.y * 0.25, -_body.z * 0.5 - 25.0), 75.0)
	
	# --- WITNESSES: world cameras; watch zones from outside ------------------
	
	# trackside: planted ahead, pans and zooms, leapfrogs once passed or far.
	# If the shot would cover a zone, it plants on a tower beside it instead:
	# level with a loop's axis, looking through it.
	var ts: Dictionary = _state.get("trackside", {})
	var plant: Vector3 = ts.get("plant", Vector3.INF)
	var rel := p - plant
	var ts_zone: int = ts.get("zone", -1)
	var replant: bool
	if ts_zone >= 0:
		replant = snap_now or _zone_done(ts_zone)
	else:
		replant = snap_now or plant == Vector3.INF \
				or rel.length() > trackside_max_range * sp \
				or rel.dot(fw) > trackside_hold_past * sp or _zone_cut(sp)
	if replant:
		var side_sign: float = -float(ts.get("side", 1.0))
		var zi := _zone_window(ZONE_SHOT_LEAD * sp)
		if zi >= 0:
			var z: Dictionary = _zones[zi]
			plant = _zone_spot(z, z.side, z.spot_a, z.spot_y, 1.0)
		else:
			var ahead: float = clampf(maxf(vel.length(), 20.0) * trackside_lead_factor,
					trackside_lead_min, trackside_lead_max)
			plant = _clear_ground(p + fw * ahead + sw * (11.0 * k) * side_sign
					+ Vector3.UP * (trackside_height * k), trackside_clearance)
			plant = _outside_zones(plant)
		_state["trackside"] = {"plant": plant, "side": side_sign, "zone": zi}
	var dist := plant.distance_to(p)
	_look("trackside", plant, p + Vector3.UP * (0.5 * k), 8.0, snap_now or replant,
			clampf(rad_to_deg(2.0 * atan(5.0 * k / maxf(dist, 1.0))), 6.0, 55.0), dt)
	
	# crane: plant ahead and low, rise and swing back over the ship.
	# Covering a zone it stands beside it, timed to the ship's progress
	# rather than the clock: up from low near a loop's entry to its hub
	# height as the ship arrives, or down over a roll toward its exit.
	var cr: Dictionary = _state.get("crane", {})
	var cplant: Vector3 = cr.get("plant", Vector3.INF)
	var crel := p - cplant
	var cr_zone: int = cr.get("zone", -1)
	var crane_replant: bool
	if cr_zone >= 0:
		crane_replant = snap_now or _zone_done(cr_zone)
	else:
		crane_replant = snap_now or cplant == Vector3.INF \
				or crel.length() > crane_max_range * sp or crel.dot(fw) > crane_hold_past * sp \
				or _zone_cut(sp)
	if crane_replant:
		var zi := _zone_window(ZONE_SHOT_LEAD * sp)
		if zi >= 0:
			cr = {"plant": Vector3.ZERO, "t": 0.0, "zone": zi}
		else:
			cplant = _clear_ground(p + fw * clampf(maxf(vel.length(), 20.0) * crane_lead_factor,
					crane_lead_min, crane_lead_max) + sw * (6.0 * k), crane_clearance)
			cplant = _outside_zones(cplant)
			cr = {"plant": cplant, "t": 0.0}
		_state["crane"] = cr
		cr_zone = cr.get("zone", -1)
	if cr_zone >= 0:
		var z: Dictionary = _zones[cr_zone]
		var cpos: Vector3
		if z.loop_like:
			# A reveal: low beside the entry as the ship approaches, up at the
			# hub by the time it starts to climb (measured: rising DURING the
			# climb kept it low exactly while the racer hugs the near wall).
			var u: float = clampf((_zone_rel(z) + ZONE_SHOT_CUT * sp) / (ZONE_SHOT_CUT * sp + 0.2 * float(z.span)), 0.0, 1.0)
			var zrise := u * u * (3.0 - 2.0 * u)
			var low: float = float(z.base_y) + zone_envelope_height + crane_base_height * k
			var base_a := lerpf(z.a0, z.a1, 0.15)
			var cside := _side_for(z, z.spot_a, z.spot_y, 1.0)
			cpos = _zone_spot(z, cside, base_a, low, 1.0).lerp(
					_zone_spot(z, cside, z.spot_a, z.spot_y, 1.0), zrise)
		else:
			# Over a roll, higher measured worse: crane DOWN instead, from
			# high over its middle to the low witness spot near its exit.
			var u: float = clampf(_zone_rel(z) / (0.8 * float(z.span)), 0.0, 1.0)
			var zdrop := u * u * (3.0 - 2.0 * u)
			var cside := _side_for(z, z.spot_a, z.spot_y, 1.0)
			cpos = _zone_spot(z, cside, lerpf(z.a0, z.a1, 0.55), float(z.y1) + 15.0, 1.0).lerp(
					_zone_spot(z, cside, z.spot_a, z.spot_y, 1.0), zdrop)
		var zfov: float = clampf(rad_to_deg(2.0 * atan(6.0 * k
				/ maxf(cpos.distance_to(p), 1.0))), 6.0, 42.0)
		_place("crane", cpos, p + Vector3.UP * 0.5, 6.0, 5.0, zfov, dt, crane_replant, false)
	else:
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
				+ crane_rise_height * rise) * k) - fw * (22.0 * rise * k), crane_clearance),
				p + Vector3.UP * 0.5, 6.0, 5.0, crane_fov, dt, crane_replant, false)
	
	# drone: swings to the outside of the turn, breathes in height.
	# measured_yaw_rate is positive to the left, so the camera swings right.
	# RIDING. measured_yaw_rate is about the ship's own up, which is the road
	# up in zones, so the swing stays correct upside down.
	var turn := clampf(-_target.measured_yaw_rate * 0.9, -1.0, 1.0)
	var bob: float = float(_state.get("orbit_ang", 0.0)) * 0.6
	_place("drone", _clear_ride(p - rf * (9.0 * k) + rs * (6.0 * turn * k)
			+ ru * (3.8 * k + 0.8 * sin(bob)), 1.4),
			p + rf * 5.0, 3.0, 4.0, 55.0, dt, snap_now, true, -1.0, true)
	
	# lowchase: RIDING. Low, close, long lens
	var lf := _smooth_dir("low_dir", rf, 2.0, dt, snap_now, ru)
	_place("lowchase", _clear_ride(p - lf * (8.5 * k) + ru * (0.6 * k), 0.5),
			p + ru * (0.6 * k), 8.0, 7.0, 34.0, dt, snap_now, true, 0.5, true)
	
	# pan: WITNESS. Locked-off tripod. Only pans and tilts until the ship is
	# too far. If a zone is coming up it sets up well back from the zone's
	# side, watching the entry.
	var pn: Dictionary = _state.get("pan", {})
	var pplant: Vector3 = pn.get("plant", Vector3.INF)
	var pn_zone: int = pn.get("zone", -1)
	var pan_replant: bool
	if pn_zone >= 0:
		pan_replant = snap_now or _zone_done(pn_zone)
	else:
		pan_replant = snap_now or pplant == Vector3.INF or pplant.distance_to(p) > pan_max_range * sp \
				or _zone_cut(sp)
	if pan_replant:
		var zi := _zone_window(ZONE_SHOT_LEAD * sp)
		if zi >= 0:
			# Further back than trackside, same height (higher measured worse).
			var z: Dictionary = _zones[zi]
			pplant = _zone_spot(z, _side_for(z, z.spot_a, z.spot_y, 1.6), z.spot_a, z.spot_y, 1.6)
			_state["pan"] = {"plant": pplant, "zone": zi}
		else:
			pplant = _clear_ground(p - fw * (18.0 * k) + sw * (20.0 * k)
					+ Vector3.UP * (pan_height * k), pan_clearance)
			pplant = _outside_zones(pplant)
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
	# orbit: RIDING. Circles in the road plane. On zone tracks the circle's
	# reference axis is carried along with the road (projected onto the new
	# road plane every tick), so it turns smoothly through a loop or roll
	# instead of flipping when the road passes vertical.
	var orbit_off: Vector3
	if _zones.is_empty():
		orbit_off = Vector3(cos(ang), 0.0, sin(ang)) * (11.0 * k)
	else:
		var ox: Vector3 = (_state.get("orbit_x", Vector3.RIGHT) as Vector3).slide(ru)
		ox = ox.normalized() if ox.length_squared() > 1e-6 else rs
		_state["orbit_x"] = ox
		orbit_off = ox * (cos(ang) * 11.0 * k) + ox.cross(ru) * (sin(ang) * 11.0 * k)
	_place("orbit", _clear_ride(p + orbit_off + ru * (3.0 * k), 1.0),
			p + ru * (0.5 * k), 8.0, 12.0, 50.0, dt, snap_now, true, -1.0, true)

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
	# v30 frames (see header): riding cameras use the road frame in zones,
	# witnesses the held heading. Both equal the old frame outside zones.
	var rf := _rf
	var rs := _rs
	var ru := _ru
	var fw := _fw
	var sw := _sw
	var up_r := p + ru * (0.5 * k)

	# handheld: WITNESS -- an operator on foot. At the edge of the track,
	# wide lens, never steady, and always a beat behind. Clamped to the track
	# corridor -- left free it wandered into scenery on open sections and lost
	# the shot entirely. Covering a zone, they stand on a platform just
	# outside it near the entry (a person can't stand on a loop).
	var hh: Dictionary = _state.get("handheld", {})
	var hplant: Vector3 = hh.get("plant", Vector3.INF)
	var hrel := p - hplant
	var hh_zone: int = hh.get("zone", -1)
	var hh_replant: bool
	if hh_zone >= 0:
		hh_replant = snap_now or _zone_done(hh_zone)
	else:
		hh_replant = snap_now or hplant == Vector3.INF or hrel.dot(fw) > 220.0 * sp or hrel.length() > 380.0 * sp \
				or _zone_cut(sp)
	if hh_replant:
		var hside: float = -float(hh.get("side", 1.0))
		var zi := _zone_window(ZONE_SHOT_LEAD * sp)
		if zi >= 0:
			var z: Dictionary = _zones[zi]
			hplant = _zone_spot(z, _side_for(z, z.spot_a, z.spot_y, 0.4), z.spot_a, z.spot_y, 0.4)
		else:
			hplant = p + fw * clampf(speed * 1.2, 60.0, 150.0) + sw * (5.0 * k) * hside
			# Measured at 9.0 the plants still read out to ~20 units off centre,
			# because height on a banked section adds to the measured lateral.
			hplant = _clamp_to_track(hplant, 6.0 * k)
			hplant = _clear_ground(hplant + Vector3.UP * (1.7 * k), 1.5)
			hplant = _outside_zones(hplant)
		_state["handheld"] = {"plant": hplant, "side": hside, "zone": zi}
	var shake := Vector3(sin(clock * 3.1) + 0.4 * sin(clock * 7.9),
			sin(clock * 2.3 + 1.1) + 0.3 * sin(clock * 6.1),
			sin(clock * 1.7 + 2.2)) * (handheld_shake * k)
	_look("handheld", hplant + shake, _spring("hh_aim", up_pt, 1.6, 0.45, dt, snap_now),
			9.0, snap_now, 82.0, dt)

	# overtake: RIDING. Comes up from behind, draws level, pulls ahead, drops back.
	var oph: float = fposmod(clock / maxf(overtake_period, 0.5), 1.0)
	var tri: float = 1.0 - absf(oph * 2.0 - 1.0)
	var ease_t := tri * tri * (3.0 - 2.0 * tri)
	_place("overtake", _clear_ride(p + rf * lerpf(-34.0 * k, 46.0 * k, ease_t)
			+ rs * (7.5 * k) + ru * (1.3 * k), 0.8),
			up_r, 7.0, 8.0, lerpf(34.0, 62.0, tri), dt, snap_now, true, -1.0, true)

	# kamikaze: RIDING the track backwards. Flown along the SPLINE against
	# the race direction, so it follows the track through corners instead of
	# flying into the wall on the outside. Planted far enough ahead that
	# contact lands in the middle of the take, and it keeps going afterwards
	# so the ship recedes behind it rather than the shot cutting on the pass.
	_kamikaze(dt, snap_now, k, p, fwd, side_dir, speed, up_pt)

	# vertigo: RIDING. Dolly and zoom opposed, so the ship holds its size
	# while the track behind stretches and compresses. Each take approaches
	# from a different angle -- back, front, side, three-quarter, overhead.
	var vtake: int = int(clock / maxf(vertigo_period, 1.0))
	var vph: float = fposmod(clock / maxf(vertigo_period, 1.0), 1.0)
	var vramp := 0.5 - 0.5 * cos(vph * TAU)
	var vdist := lerpf(10.0 * k, 38.0 * k, vramp)
	var vdir := _angle_for(vtake, rf, rs, false, ru)
	var vfov := clampf(rad_to_deg(2.0 * atan(4.6 * k / maxf(vdist, 1.0))), 11.0, 96.0)
	_place("vertigo", _clear_ride(p + vdir * vdist + ru * (1.9 * k), 0.8),
			up_r, 9.0, 9.0, vfov, dt, snap_now, true, -1.0, true)

	# roadkill: FIXED TO THE TRACK. ON the surface and near the racing line,
	# not beside it. The lateral offset is taken from the spline rather than
	# from the ship, so it sits on the track even when the ship is running
	# wide. In a zone it lies on the road wherever the road is -- up the
	# loop, upside down at the top -- oriented by it.
	_roadkill(dt, snap_now, k, sp, p, fw, speed)

	# helilost: WITNESS (a helicopter). Drifts ahead, gets left behind, hauls
	# back on. Both the lead and the follow rate move on smooth curves now --
	# stepping them made the recovery snap rather than drift. Near a zone it
	# does the same drift, from beside the zone.
	var lph: float = fposmod(clock / maxf(helilost_period, 1.0), 1.0)
	var lcurve := 0.5 - 0.5 * cos(lph * TAU)
	var hl_target := _clear_ground(p + fw * lerpf(26.0 * k, -30.0 * k, lcurve)
			+ sw * (9.0 * k) + Vector3.UP * (24.0 * k), 8.0)
	if not _zones.is_empty():
		hl_target = _heli_zone("helilost", hl_target, 24.0 * k, lerpf(26.0 * k, -30.0 * k, lcurve))[0]
	_place("helilost", hl_target,
			p, lerpf(0.22, 1.9, lcurve * lcurve), lerpf(0.5, 1.4, lcurve), 42.0, dt, snap_now)

	# whip: FIXED TO THE TRACK. Dead still on a wide lens, then snaps through
	# the pass. In a zone it is bolted to the road edge, oriented by the road.
	_whip(dt, snap_now, k, sp, p, fw, sw, speed, up_pt)

	# crashzoom: RIDING. Punch in, HOLD, punch out, hold wide. The holds are
	# the point -- without them it read as a continuous pulse. Frontal and
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
	var czdir := _angle_for(int(clock / maxf(crashzoom_period, 1.0)), rf, rs, true, ru)
	_place("crashzoom", _clear_ride(p + czdir * (12.0 * k) + ru * (2.0 * k), 1.0),
			up_r, 6.0, 7.0, czfov, dt, snap_now, true, -1.0, true)

	# skim: RIDING. AHEAD of the ship looking back, a hand's width off the
	# road, sliding between four positions rather than cutting. In a zone
	# "the road" is the loop's or roll's surface, so it skims round with it.
	var soff := _blend_offsets(clock, 4.5, [
			rf * (7.0 * k) + ru * (0.45 * k),
			rf * (9.0 * k) + rs * (3.2 * k) + ru * (1.2 * k),
			rf * (9.0 * k) - rs * (3.2 * k) + ru * (1.2 * k),
			rf * (6.0 * k) + ru * (3.2 * k)])
	_place("skim", _clear_ride(p + soff, 0.30), up_r, 10.0, 11.0, 90.0, dt,
			snap_now, true, 0.30, true)

	# crossing: WITNESS -- a cable cam at its own constant speed. Sometimes
	# it meets the ship, sometimes it misses. Covering a zone, the cable is
	# strung beside or over it and the run is timed to the ship's progress:
	# through a loop along its axis (crossing_through_loops), over the top
	# of a roll.
	_crossing(dt, snap_now, k, sp, p, fw, sw, speed, up_pt)

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
func _angle_for(take: int, fwd: Vector3, side_dir: Vector3, frontal: bool = false,
		up: Vector3 = Vector3.UP) -> Vector3:
	var options: Array[Vector3] = [fwd, (fwd + side_dir).normalized(),
			(fwd - side_dir).normalized(), side_dir]
	if not frontal:
		options = [-fwd, fwd, side_dir, (-fwd + side_dir).normalized(),
				(fwd - side_dir).normalized(), up * 0.9 + fwd * 0.3]
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
	var kup := Vector3.UP
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
		if not _zones.is_empty() and spline.zone_weight_at_offset(off) > 0.0:
			# v30: RIDING the track. In a zone it flies along the road surface
			# itself (up the loop, round the roll), oriented by it.
			kup = spline.get_up_at_offset(off, true).normalized()
			pos += kup * (2.4 * k)
		else:
			# The spline is a centreline, not a surface: on elevation changes
			# and banked sections its point can sit well under the track,
			# which put this camera below the geometry looking at nothing.
			# Every other camera clears the ground; this one was not.
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
	var aim := up_pt if kup == Vector3.UP else _target.global_position + _ru * (0.5 * k)
	_look("kamikaze", pos, aim, 10.0, snap_now or t < dt * 1.5, 66.0, dt, kup)

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
# v30: FRAMES AND MAGNETIC ZONES
# ============================================================================

## Per-tick frames for the three kinds of non-mounted camera. Outside zones
## (and on tracks without them) every value here equals the old world frame,
## so those cameras behave exactly as before.
func _update_frames(f: Transform3D, fwd: Vector3, side_dir: Vector3, snap_now: bool) -> void:
	if not _zones_built:
		_build_zones()
	_w = _target.magnet_weight
	_ru = Vector3.UP
	_rf = fwd
	_rs = side_dir
	if _w > 0.0:
		# Riding cameras: road up, blended in over the zone's ramp.
		var su := f.basis.y.normalized()
		_ru = su if _w >= 1.0 else ShipController.slerp_safe(Vector3.UP, su, _w).normalized()
		var rf := (-f.basis.z).slide(_ru)
		_rf = rf.normalized() if rf.length_squared() > 1e-6 else fwd
		_rs = _rf.cross(_ru).normalized()
	# Witnesses: the world heading, frozen while the ship is in a zone. On a
	# loop wall the ship's nose points at the sky and its world heading is
	# meaningless; over the top it points backwards.
	if _w <= 0.0:
		_fw = fwd
		_state["w_fwd"] = fwd
	else:
		_fw = _state.get("w_fwd", fwd)
	_sw = side_dir if _fw == fwd else _fw.cross(Vector3.UP).normalized()
	_ship_d = -1.0
	if not _zones.is_empty():
		_ship_d = spline.world_to_spline_offset(f.origin) * spline.total_length
	# The road's rotation since last tick (pitch through a loop, roll through
	# a roll; yaw excluded) and where the ship was, for _place.
	_ride_rot = Quaternion.IDENTITY
	_carry_from = f.origin if _prev_ship_p == Vector3.INF or snap_now else _prev_ship_p
	if _w > 0.0 and not snap_now and _prev_ru.dot(_ru) < 0.9999999:
		_ride_rot = Quaternion(_prev_ru.normalized(), _ru.normalized())
	_prev_ru = _ru
	_prev_ship_p = f.origin

## Clearance for RIDING cameras: above the road under them, measured along the
## road's up. Outside zones this is exactly _clear_ground. (_clear_ground
## casts down from 400 m above, which near a loop finds the TOP of the loop
## and lifted chase cameras 180 m into the sky.)
func _clear_ride(pos: Vector3, min_height: float) -> Vector3:
	if _w <= 0.0:
		return _clear_ground(pos, min_height)
	if _space == null:
		return pos
	var q := PhysicsRayQueryParameters3D.create(
			pos + _ru * ride_clear_search, pos - _ru * 80.0, ground_mask)
	var hit := _space.intersect_ray(q)
	if hit:
		var h: float = (pos - (hit["position"] as Vector3)).dot(_ru)
		if h < min_height:
			pos += _ru * (min_height - h)
	return pos

## One entry per enabled zone: its swept envelope as a box in a local frame
## (along the zone's entry heading, across it, world height), its axis (mean
## of the centreline: a loop's hub), and how far witnesses stand off.
func _build_zones() -> void:
	_zones_built = true
	_zones.clear()
	if spline == null or not spline.is_valid or spline.magnetic == null \
			or not spline.magnetic.is_valid():
		return
	var mt := spline.magnetic
	var length := mt.get_length()
	var hw := zone_envelope_half_width
	for zone in mt.zones:
		if zone == null or not zone.enabled:
			continue
		var span := fposmod(zone.end_distance - zone.start_distance, length)
		if span <= 0.0:
			continue
		var o := mt.frame_at(fposmod(zone.start_distance, length)).origin
		var tf := mt.frame_at(fposmod(zone.start_distance - maxf(zone.ramp_in, 1.0), length))
		var h := (-tf.basis.z).slide(Vector3.UP)
		h = h.normalized() if h.length_squared() > 1e-6 else Vector3.FORWARD
		var s := h.cross(Vector3.UP).normalized()
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		var sum_a := 0.0
		var sum_y := 0.0
		var cmin := INF
		var cmax := -INF
		var count := 0
		var d := 0.0
		while d <= span + 0.01:
			var fr := mt.frame_at(fposmod(zone.start_distance + d, length))
			var x := fr.basis.x.normalized()
			var y := fr.basis.y.normalized()
			var c := fr.origin - o
			sum_a += c.dot(h)
			sum_y += c.y
			cmin = minf(cmin, c.y)
			cmax = maxf(cmax, c.y)
			count += 1
			for sx: float in [-hw, hw]:
				for sy: float in [-zone_envelope_depth, zone_envelope_height]:
					var lp := fr.origin + x * sx + y * sy - o
					var l := Vector3(lp.dot(h), lp.dot(s), lp.y)
					lo = Vector3(minf(lo.x, l.x), minf(lo.y, l.y), minf(lo.z, l.z))
					hi = Vector3(maxf(hi.x, l.x), maxf(hi.y, l.y), maxf(hi.z, l.z))
			d += 4.0
		var z := {
			"name": zone.zone_name, "start": zone.start_distance, "span": span,
			"length": length, "o": o, "h": h, "s": s,
			"a0": lo.x, "a1": hi.x, "c0": lo.y, "c1": hi.y, "y0": lo.z, "y1": hi.z,
			"axis_a": sum_a / count, "axis_y": sum_y / count, "base_y": cmin,
			# A loop climbs more than the track is wide; a roll doesn't.
			"loop_like": (cmax - cmin) > 2.0 * hw,
			"standoff": zone_witness_standoff,
		}
		# The standard witness spot (see zone_witness_standoff).
		if z.loop_like:
			z["spot_a"] = z.axis_a
			z["spot_y"] = float(z.axis_y) + zone_witness_rise
		else:
			z["spot_a"] = lerpf(z.a0, z.a1, 0.8)
			z["spot_y"] = float(z.base_y) + zone_roll_witness_height
		z["sides"] = {}
		z["side"] = _side_for(z, z.spot_a, z.spot_y, 1.0)
		_zones.append(z)

## Which side of zone `z` sees more of its road from a witness spot at
## (`along`, `height`, `standoff_scale`): raycast from it, on each side, to
## points 2.75 m over the road right across it (racers hug walls: the AI runs
## Loop Lab's loop entry 16 m off centre, and sampling only +-12 m picked the
## worse side), every 15 m through the zone. Per spot, because a low camera
## and a high one can prefer different sides. Cached per zone.
func _side_for(z: Dictionary, along: float, height: float, standoff_scale: float) -> float:
	var key := "%d_%d_%d" % [roundi(along), roundi(height), roundi(standoff_scale * 10.0)]
	var cache: Dictionary = z.sides
	if cache.has(key):
		return cache[key]
	if _space == null:
		_space = get_world_3d().direct_space_state
	var mt := spline.magnetic
	var length: float = z.length
	var score := {1.0: 0, -1.0: 0}
	for side: float in [1.0, -1.0]:
		var st: float = float(z.standoff) * standoff_scale + zone_envelope_margin
		var c: float = (float(z.c1) + st) if side > 0.0 else (float(z.c0) - st)
		var spot := _zone_world(z, clampf(along, z.a0, z.a1), c, height)
		var d := 0.0
		while d <= float(z.span):
			var fr := mt.frame_at(fposmod(float(z.start) + d, length))
			for lat: float in [-17.0, -8.5, 0.0, 8.5, 17.0]:
				var pt := fr.origin + fr.basis.x.normalized() * lat + fr.basis.y.normalized() * 2.75
				if _space.intersect_ray(PhysicsRayQueryParameters3D.create(spot, pt, ground_mask)).is_empty():
					score[side] += 1
			d += 15.0
	var best := 1.0 if int(score[1.0]) >= int(score[-1.0]) else -1.0
	cache[key] = best
	return best

func _zone_local(z: Dictionary, pos: Vector3) -> Vector3:
	var d: Vector3 = pos - z.o
	return Vector3(d.dot(z.h), d.dot(z.s), d.y)

func _zone_world(z: Dictionary, along: float, across: float, height: float) -> Vector3:
	return z.o + z.h * along + z.s * across + Vector3.UP * height

## Ship's distance from a zone's start along the spline, signed, wrapped.
func _zone_rel(z: Dictionary) -> float:
	var length: float = z.length
	return fposmod(_ship_d - float(z.start) + length * 0.5, length) - length * 0.5

## The zone (index) the ship is in, or reaches within `window` metres; -1.
func _zone_window(window: float) -> int:
	if _zones.is_empty() or _ship_d < 0.0:
		return -1
	for i in _zones.size():
		var rel := _zone_rel(_zones[i])
		if rel >= -window and rel <= float(_zones[i].span):
			return i
	return -1

## Witness zone shots: chosen at a natural replant when a zone is within
## `zone_shot_lead`, and cut to (pre-empting a normal shot) at
## `zone_shot_cut`. Planting earlier ran shots over a kilometre long.
const ZONE_SHOT_LEAD := 250.0
const ZONE_SHOT_CUT := 150.0

func _zone_cut(sp: float) -> bool:
	return _zone_window(ZONE_SHOT_CUT * sp) >= 0

## A witness shot on zone `zi` is over: the ship is clear of the far end (or
## was sent back a long way by a respawn).
func _zone_done(zi: int) -> bool:
	if zi < 0 or zi >= _zones.size() or _ship_d < 0.0:
		return true
	var z: Dictionary = _zones[zi]
	var rel := _zone_rel(z)
	return rel > float(z.span) + zone_after_margin or rel < -1500.0

## How present the nearest zone is: 1 inside, ramping to 0 `lead` metres
## before and `tail` metres after. Returns [weight, zone index].
func _zone_presence(lead: float, tail: float) -> Array:
	var best := 0.0
	var bi := -1
	if _ship_d < 0.0:
		return [0.0, -1]
	for i in _zones.size():
		var z: Dictionary = _zones[i]
		var rel := _zone_rel(z)
		var w := 0.0
		if rel >= 0.0 and rel <= float(z.span):
			w = 1.0
		elif rel < 0.0 and -rel < lead:
			w = 1.0 + rel / lead
		elif rel > float(z.span) and rel - float(z.span) < tail:
			w = 1.0 - (rel - float(z.span)) / tail
		if w > best:
			best = w
			bi = i
	return [best, bi]

## Push a point out of every zone's swept space (plus margin) by the shortest
## way: either side, over the top, or before/after it along the track. A
## no-op on tracks without zones.
func _outside_zones(pos: Vector3) -> Vector3:
	if _zones.is_empty():
		return pos
	var m := zone_envelope_margin
	for z in _zones:
		var l := _zone_local(z, pos)
		if l.x < z.a0 - m or l.x > z.a1 + m or l.y < z.c0 - m or l.y > z.c1 + m \
				or l.z < z.y0 - m or l.z > z.y1 + m:
			continue
		var exits := [
			[l.y - (z.c0 - m), Vector3(l.x, z.c0 - m, l.z)],
			[(z.c1 + m) - l.y, Vector3(l.x, z.c1 + m, l.z)],
			[(z.y1 + m) - l.z, Vector3(l.x, l.y, z.y1 + m)],
			[l.x - (z.a0 - m), Vector3(z.a0 - m, l.y, l.z)],
			[(z.a1 + m) - l.x, Vector3(z.a1 + m, l.y, l.z)],
		]
		var best: Array = exits[0]
		for e in exits:
			if float(e[0]) < float(best[0]):
				best = e
		var to: Vector3 = best[1]
		pos = _zone_world(z, to.x, to.y, to.z)
	return pos

## A witness position beside zone `z`: `side` +1/-1, at `along` and
## `height` (zone-local), standing off by the zone's witness distance times
## `standoff_scale`.
func _zone_spot(z: Dictionary, side: float, along: float, height: float,
		standoff_scale: float) -> Vector3:
	var st: float = float(z.standoff) * standoff_scale + zone_envelope_margin
	var c: float = (float(z.c1) + st) if side > 0.0 else (float(z.c0) - st)
	var pos := _zone_world(z, clampf(along, z.a0, z.a1), c, height)
	return _clear_ground(_outside_zones(pos), 2.0)

## Helicopters near a loop: blend from the normal follow position out to the
## loop's better side, at witness height, keeping pace with the ship along
## it. Returns [target, blend weight].
func _heli_zone(cam_name: String, normal_target: Vector3, height: float,
		along_offset: float) -> Array:
	var pres := _zone_presence(zone_heli_lead, zone_heli_tail)
	if int(pres[1]) < 0 or float(pres[0]) <= 0.0:
		return [normal_target, 0.0]
	var z: Dictionary = _zones[int(pres[1])]
	var wz: float = pres[0]
	var e := wz * wz * (3.0 - 2.0 * wz)
	if not z.loop_like:
		# Over a roll the normal follow (high, behind) is already the best
		# a helicopter can do; just keep it out of the swept space.
		return [_outside_zones(normal_target), e]
	# Mostly hold the loop's hub line (the only place that sees all the way
	# round), drifting a little with the ship rather than pacing it.
	var lp := _zone_local(z, _target.global_position)
	var along := lerpf(float(z.spot_a), clampf(lp.x + along_offset, z.a0, z.a1), 0.3)
	var y := maxf(float(z.spot_y), float(z.base_y) + height)
	var st: float = float(z.standoff) + zone_envelope_margin
	var c: float = (float(z.c1) + st) if float(z.side) > 0.0 else (float(z.c0) - st)
	return [normal_target.lerp(_zone_world(z, along, c, y), e), e]

## For the track-fixed cameras: the spline offset (0..1) `ahead` metres down
## the track, if the ship or that point is in a zone; else -1, meaning plant
## the old way.
func _zone_track_offset(ahead: float) -> float:
	if _zones.is_empty() or _ship_d < 0.0:
		return -1.0
	var off := fposmod(spline.get_lookahead_offset(_ship_d / spline.total_length, ahead), 1.0)
	if _w > 0.0 or spline.zone_weight_at_offset(off) > 0.0:
		return off
	return -1.0

## Ship has driven more than `dist` past spline distance `d`.
func _passed_spline(d: float, dist: float) -> bool:
	if _ship_d < 0.0:
		return false
	var length := spline.total_length
	var after := fposmod(_ship_d - d, length)
	return after > dist and after < length * 0.5

## roadkill: see _update_wild. Outside zones this is the original code.
func _roadkill(dt: float, snap_now: bool, k: float, sp: float, p: Vector3, fw: Vector3,
		speed: float) -> void:
	var rk: Dictionary = _state.get("roadkill", {})
	var rplant: Vector3 = rk.get("plant", Vector3.INF)
	var rrel := p - rplant
	var need: bool
	if bool(rk.get("spl", false)):
		need = snap_now or _passed_spline(float(rk.d), 110.0 * sp) or rrel.length() > 260.0 * sp
	else:
		need = snap_now or rplant == Vector3.INF or rrel.dot(fw) > 110.0 * sp or rrel.length() > 260.0 * sp
	if need:
		var rside: float = -float(rk.get("side", 1.0))
		var ahead: float = clampf(speed * 1.1, 60.0, 140.0)
		var zoff := _zone_track_offset(ahead)
		if zoff >= 0.0:
			var base := spline.spline_offset_to_world_with_lateral(zoff, 2.2 * k * rside, true)
			var rup := Vector3.UP
			if spline.zone_weight_at_offset(zoff) > 0.0:
				rup = spline.get_up_at_offset(zoff, true).normalized()
				rplant = base + rup * (0.28 * k)
			else:
				rplant = _clear_ground(base + Vector3.UP * (0.28 * k), 0.30)
			rk = {"plant": rplant, "side": rside, "spl": true,
					"d": zoff * spline.total_length, "up": rup}
		else:
			rplant = _on_track(p + fw * ahead, 2.2 * k * rside)
			rplant = _clear_ground(rplant + Vector3.UP * (0.28 * k), 0.30)
			rk = {"plant": rplant, "side": rside}
		_state["roadkill"] = rk
	var rup2: Vector3 = rk.get("up", Vector3.UP)
	var rnear: float = clampf(1.0 - rplant.distance_to(p) / (55.0 * k), 0.0, 1.0)
	var aim := p + Vector3.UP * (0.35 * k) if rup2 == Vector3.UP else p + _ru * (0.35 * k)
	_look("roadkill", rplant, aim, lerpf(2.5, 16.0, rnear * rnear), snap_now, 96.0, dt, rup2)

## whip: see _update_wild. Outside zones this is the original code.
func _whip(dt: float, snap_now: bool, k: float, sp: float, p: Vector3, fw: Vector3, sw: Vector3,
		speed: float, up_pt: Vector3) -> void:
	var wh: Dictionary = _state.get("whip", {})
	var wplant: Vector3 = wh.get("plant", Vector3.INF)
	var wrel := p - wplant
	var need: bool
	if bool(wh.get("spl", false)):
		need = snap_now or _passed_spline(float(wh.d), 130.0 * sp) or wrel.length() > 280.0 * sp
	else:
		need = snap_now or wplant == Vector3.INF or wrel.dot(fw) > 130.0 * sp or wrel.length() > 280.0 * sp
	if need:
		var wside: float = -float(wh.get("side", 1.0))
		var ahead: float = clampf(speed * 1.3, 70.0, 170.0)
		var zoff := _zone_track_offset(ahead)
		if zoff >= 0.0:
			var base := spline.spline_offset_to_world_with_lateral(zoff, 4.2 * k * wside, true)
			var wup := Vector3.UP
			if spline.zone_weight_at_offset(zoff) > 0.0:
				wup = spline.get_up_at_offset(zoff, true).normalized()
				wplant = base + wup * (1.1 * k)
			else:
				wplant = _clear_ground(base + Vector3.UP * (1.1 * k), 1.0)
			wh = {"plant": wplant, "side": wside, "spl": true,
					"d": zoff * spline.total_length, "up": wup}
		else:
			wplant = _clamp_to_track(p + fw * ahead + sw * (4.2 * k) * wside, 8.0 * k)
			wplant = _clear_ground(wplant + Vector3.UP * (1.1 * k), 1.0)
			wh = {"plant": wplant, "side": wside}
		_state["whip"] = wh
	var wup2: Vector3 = wh.get("up", Vector3.UP)
	var wnear: float = clampf(1.0 - wplant.distance_to(p) / (70.0 * k), 0.0, 1.0)
	var aim := up_pt if wup2 == Vector3.UP else p + _ru * (0.5 * k)
	_look("whip", wplant, aim, lerpf(1.4, 26.0, pow(wnear, 3.0)), snap_now, 74.0, dt, wup2)

## crossing: see _update_wild. Outside zones this is the original code.
func _crossing(dt: float, snap_now: bool, k: float, sp: float, p: Vector3,
		fw: Vector3, sw: Vector3, speed: float, up_pt: Vector3) -> void:
	var cs: Dictionary = _state.get("crossing", {})
	var czone: int = cs.get("zone", -1)
	# A snap (camera cycled, ship changed) only re-frames a zone shot; ending
	# it on snap made the replant below pick the same zone again, forever.
	if czone >= 0 and _zone_done(czone):
		czone = -1
		cs = {"side": cs.get("side", 1.0)}
	if czone < 0:
		# Normal shot (original behaviour), unless a zone is coming up.
		var ccentre: Vector3 = cs.get("centre", Vector3.INF)
		var caxis: Vector3 = cs.get("axis", sw)
		var ct2: float = float(cs.get("t", 0.0)) + dt * crossing_rate
		if snap_now or ccentre == Vector3.INF or ct2 >= 1.0 or (p - ccentre).dot(fw) > 90.0 * sp \
				or _zone_cut(sp):
			var zi := _zone_window(ZONE_SHOT_LEAD * sp)
			if zi >= 0:
				czone = zi
				cs = {"zone": zi, "side": -float(cs.get("side", 1.0)), "fresh": true}
			else:
				ccentre = p + fw * clampf(speed * 1.6, 90.0, 240.0)
				caxis = sw
				ct2 = 0.0
		if czone < 0:
			_state["crossing"] = {"centre": ccentre, "axis": caxis, "t": ct2, "side": cs.get("side", 1.0)}
			_look("crossing", _clear_ground(ccentre + caxis * lerpf(58.0 * k, -58.0 * k, ct2)
					+ Vector3.UP * (crossing_height * k), crossing_clearance),
					up_pt, 6.0, snap_now, 46.0, dt)
			return
	# Zone shot: the cable strung beside/over the zone, run timed to the
	# ship's progress through it.
	var z: Dictionary = _zones[czone]
	var u: float = clampf((_zone_rel(z) + 0.1 * float(z.span)) / (1.2 * float(z.span)), 0.0, 1.0)
	var c_a: float
	var c_b: float
	var y: float
	var ca: float = z.axis_a
	if z.loop_like and crossing_through_loops:
		# Along the loop's axis, through the hub. The racer is on the
		# inside of the hoop, facing this line the whole way round
		# (measured 100% in view from the hub).
		var st: float = float(z.standoff) + zone_envelope_margin
		c_a = float(z.c0) - st
		c_b = float(z.c1) + st
		y = z.axis_y
	else:
		c_a = float(z.c0) - 30.0
		c_b = float(z.c1) + 30.0
		y = float(z.y1) + zone_envelope_margin + crossing_height * k
		ca = lerpf(z.a0, z.a1, 0.75)
	if float(cs.get("side", 1.0)) < 0.0:
		var t := c_a
		c_a = c_b
		c_b = t
	var pos := _zone_world(z, ca, lerpf(c_a, c_b, u), y)
	var fov := clampf(rad_to_deg(2.0 * atan(7.0 * k / maxf(pos.distance_to(p), 1.0))), 10.0, 46.0)
	_look("crossing", pos, up_pt, 6.0, snap_now or bool(cs.get("fresh", false)), fov, dt)
	cs["fresh"] = false
	_state["crossing"] = cs

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
##
## v30: `ride` marks a RIDING camera: its clearance follows the road and its
## up is the road up inside zones (both identical to before outside them).
func _place(n: String, target: Vector3, look_at_pt: Vector3, pos_sharp: float,
		rot_sharp: float, fov: float, dt: float, snap_now: bool,
		follows_ship: bool = true, clear_after: float = -1.0, ride: bool = false) -> void:
	var cam: Camera3D = _cams[n]
	var pos := target
	var carried := ride and _w > 0.0
	if not snap_now:
		var from: Vector3
		if carried:
			# v30: carry the camera's offset from the ship with the ship's
			# move AND the road's rotation. The straight-line velocity
			# feedforward leaves a loop's curve and drives the camera into
			# the road (measured: front blocked 22% of the loop by the road
			# at its own position).
			from = _target.global_position + _ride_rot * (cam.global_position - _carry_from)
		else:
			from = cam.global_position + (_vel * dt if follows_ship else Vector3.ZERO)
		pos = from.lerp(target, 1.0 - exp(-pos_sharp * dt))
	if clear_after >= 0.0:
		pos = _clear_ride(pos, clear_after) if ride else _clear_ground(pos, clear_after)
	elif carried:
		pos = _clear_ride(pos, 0.5)
	_look(n, pos, look_at_pt, rot_sharp, snap_now, fov, dt, _ru if ride else Vector3.UP)

## v30: `up_hint` is the camera's up: world UP for everything outside zones
## (unchanged path), the road up for riding and track-fixed cameras in them.
func _look(n: String, pos: Vector3, look_at_pt: Vector3, rot_sharp: float,
		snap_now: bool, fov: float, dt: float = 0.0, up_hint: Vector3 = Vector3.UP) -> void:
	var cam: Camera3D = _cams[n]
	var dir := look_at_pt - pos
	if dir.length_squared() < 1e-6:
		return
	var up: Vector3
	if up_hint == Vector3.UP:
		up = Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.FORWARD
	else:
		up = up_hint if absf(dir.normalized().dot(up_hint)) < 0.99 else _rf
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

## v30: `plane_up` keeps the smoothing in the road plane for riding cameras:
## the stored direction is carried onto the current road plane first, so the
## lag applies to heading (yaw) only and a loop's pitch is followed rigidly.
## A pitch lag would put a camera ahead of the ship under the loop's road.
func _smooth_dir(key: String, want: Vector3, sharp: float, dt: float, snap_now: bool,
		plane_up: Vector3 = Vector3.UP) -> Vector3:
	var cur: Vector3 = _state.get(key, want)
	var in_plane := plane_up != Vector3.UP
	if in_plane:
		cur = cur.slide(plane_up)
		cur = cur.normalized() if cur.length_squared() > 1e-6 else want
	if snap_now or cur.dot(want) < -0.99:
		cur = want
	elif in_plane:
		cur = ShipController.slerp_safe(cur, want, 1.0 - exp(-sharp * dt)).normalized()
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
