extends RefCounted
class_name FallMonitor
## v33: forced-fall measurement shared by ai_race_probe.gd (AI ships, PROBE_PUSH)
## and loop_lab_driver.gd (player in time trial, LL_PUSH).
##
## push() knocks a ship off the track. Side "T…" (TO / TI / TL / TR) puts it
## over the wall: 14 m past the wall's inner face, same height, same velocity
## plus 20 u/s outward. Side O / I / L / R is a kick instead: a sideways
## velocity kick (default 70 u/s) plus an upward one along the road normal
## (default 35 u/s). On the circuits a kick almost never gets a ship over the
## walls (the hover spring and the walls hold it), so a kick tests that an
## airborne ship that comes back down on the road is NOT respawned. tick() follows the ship until it respawns and for 3 s
## after, and report() prints one FALL line per push:
##
##   leave   push -> first airborne tick (s)
##   resp    push -> respawn (s); "never" if it had not respawned in 15 s
##   drop    metres the ship fell (y at push - y before respawn)
##   back    metres along the MainSpline from the push spot back to the respawn
##   lat     respawn offset from the centre line (m)
##   road    what the downward ray from the respawned ship hit (collider) and
##           how far: on_road = road collider within 0.5 m of hover height
##   up_err  ship up vs road normal at respawn / max over the next 0.5 s
##   gnd     ticks grounded / 180 in the 3 s after the respawn, first ungrounded tick
##   settle0.5s  max |height above road - hover height| / max speed along the
##           road normal, in the first 0.5 s after the respawn (drop, bounce)
##   hover   max |ground distance - hover height| from 0.1 s after the respawn
##   vn      max speed along the road normal in those 3 s (includes driving
##           over crests and any contact with other ships)
##   sunk    ticks the ship centre was below the road surface in those 3 s
##   v80     seconds from respawn to 80 u/s (standing start)
##   bumps   ship-ship collisions in the 3 s after the respawn
##   cam     (player only) camera distance and aim error the tick after the
##           respawn, and the largest per-tick camera move beyond the ship's own
##           over the following second (the respawn's own snap excluded)
##
## Measurement is independent of the respawn code it tests: its own rays
## (layer 1) and the MainSpline's closest point.

const SETTLE_TICKS := 180
const GIVE_UP_TICKS := 900

var path: Path3D
var curve: Curve3D
var length := 0.0
var space: PhysicsDirectSpaceState3D
var episodes: Array = []     # all episodes, in push order
var _active := {}            # ship -> episode
var hover_height := 2.75
var trace := OS.get_environment("FALL_TRACE") == "1"

func _init(track_root: Node, world: World3D) -> void:
	path = _find_spline(track_root)
	if path:
		curve = path.curve
		length = curve.get_baked_length()
	space = world.direct_space_state

func _find_spline(n: Node) -> Path3D:
	if n is Path3D and n.name == "MainSpline":
		return n
	for c in n.get_children():
		var f := _find_spline(c)
		if f:
			return f
	return null

func distance_of(p: Vector3) -> float:
	return curve.get_closest_offset(path.global_transform.affine_inverse() * p)

func frame_at(d: float) -> Transform3D:
	return path.global_transform * curve.sample_baked_with_rotation(fposmod(d, length), true, true)

## Turn direction over the next `ahead` metres: +1 = left, -1 = right.
func turn_sign(d: float, ahead: float = 80.0) -> float:
	var a := (-frame_at(d).basis.z).slide(Vector3.UP)
	var b := (-frame_at(d + ahead).basis.z).slide(Vector3.UP)
	return 1.0 if a.signed_angle_to(b, Vector3.UP) > 0.0 else -1.0

func is_busy(ship: ShipController) -> bool:
	return _active.has(ship)

## side: "O" outside of the corner ahead, "I" inside, "L", "R".
func push(ship: ShipController, spot: float, side: String, frame: int, lat_speed: float = 70.0,
		up_speed: float = 35.0, camera: Camera3D = null) -> void:
	var d := distance_of(ship.global_position)
	var f := frame_at(d)
	var right := f.basis.x.normalized()
	var up := f.basis.y.normalized()
	var s := turn_sign(d)   # "O": turning left (+1) -> outside is right (+1)
	var tele := side.begins_with("T")
	match side.trim_prefix("T"):
		"L": s = -1.0
		"R": s = 1.0
		"I": s = -turn_sign(d)
	if tele:
		# Over the wall: place the ship 14 m past the wall's inner face (the
		# walls are ~7.5 m thick) on that side, at
		# its current height above the road, keeping its velocity plus 20 u/s
		# outward (the ship has just cleared the wall). Kicks alone rarely get
		# a ship off these circuits: the hover spring and the walls hold it.
		var p := ship.global_position
		var wh := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + right * s * 80.0, 4))
		var wall_d: float = p.distance_to(wh.position) if not wh.is_empty() else 25.0
		ship.global_position = p + right * s * (wall_d + 14.0)
		ship.velocity += right * s * 20.0
	else:
		ship.velocity += right * s * lat_speed + up * up_speed
	hover_height = ship.profile.hover_height if ship.profile else hover_height
	var e := {"ship": ship, "name": String(ship.name), "spot": spot, "side": side, "dir": "R" if s > 0 else "L",
			"f0": frame, "d0": d, "y0": ship.global_position.y, "v0": ship.velocity.length(),
			"leave_f": -1, "resp_f": -1, "resp_n": 0, "y_before": 0.0, "pos": Vector3.ZERO,
			"back": 0.0, "lat": 0.0, "road": "", "road_h": 0.0, "on_road": false, "up0": 0.0, "up_max": 0.0,
			"gnd": 0, "first_air": -1, "hover_dev": 0.0, "vn": 0.0, "hover0": 0.0, "vn0": 0.0, "sunk": 0, "v80": -1.0, "bumps": 0,
			"cam_d": -1.0, "cam_aim": -1.0, "cam_jump": 0.0, "cam": camera, "after": 0, "prev_pos": ship.global_position,
			"prev_cam": camera.global_position if camera else Vector3.ZERO, "done": false}
	episodes.append(e)
	_active[ship] = e
	if not ship.ship_respawned.is_connected(_on_respawn):
		ship.ship_respawned.connect(_on_respawn.bind(ship))
	if not ship.ship_collision.is_connected(_on_bump):
		ship.ship_collision.connect(_on_bump.bind(ship))
	print("PUSH f%d %s at %.0f m (%s -> %s) v=%.0f y=%.1f" % [frame, ship.name, d, side, e.dir,
			ship.velocity.length(), ship.global_position.y])

func _on_bump(_other, _speed, ship: ShipController) -> void:
	if _active.has(ship) and int(_active[ship].resp_f) >= 0:
		_active[ship].bumps = int(_active[ship].bumps) + 1

func _on_respawn(ship: ShipController) -> void:
	if not _active.has(ship):
		return
	var e: Dictionary = _active[ship]
	e.resp_n = int(e.resp_n) + 1
	if int(e.resp_f) >= 0:
		return   # a second respawn inside the settle window: counted only
	e.resp_f = int(e.get("now", e.f0))
	e.y_before = (e.prev_pos as Vector3).y
	var p := ship.global_position
	e.pos = p
	var d := distance_of(p)
	e.back = fposmod(float(e.d0) - d + length * 0.5, length) - length * 0.5
	var f := frame_at(d)
	e.lat = (p - f.origin).dot(f.basis.x.normalized())
	var n := ship.global_transform.basis.y.normalized()
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p - n * 12.0, 1))
	if hit.is_empty():
		e.road = "nothing within 12 m"
	else:
		e.road = String((hit.collider as Node).name)
		e.road_h = p.distance_to(hit.position)
		e.on_road = absf(float(e.road_h) - hover_height) < 0.5
		e.up0 = rad_to_deg(n.angle_to(hit.normal))
	var cam: Camera3D = e.cam
	if cam:
		e.prev_cam = cam.global_position

func tick(frame: int) -> void:
	for ship in _active.keys():
		var e: Dictionary = _active[ship]
		e.now = frame
		var s: ShipController = ship
		if int(e.leave_f) < 0 and not s.is_grounded:
			e.leave_f = frame
		if trace and (frame - int(e.f0)) % 30 == 0 and frame - int(e.f0) <= 600:
			var dd := distance_of(s.global_position)
			var ff := frame_at(dd)
			print("FTRACE %s +%.1fs d=%.0f lat=%.1f h_spline=%.1f y=%.1f v=%s gnd=%s gd=%.2f" % [s.name,
					(frame - int(e.f0)) / 60.0, dd, (s.global_position - ff.origin).dot(ff.basis.x.normalized()),
					(s.global_position - ff.origin).dot(ff.basis.y.normalized()), s.global_position.y,
					s.velocity.snapped(Vector3.ONE * 0.1), s.is_grounded, s.ground_distance])
		if int(e.resp_f) < 0:
			e.prev_pos = s.global_position
			if frame - int(e.f0) > GIVE_UP_TICKS:
				_finish(e)
			continue
		if frame == int(e.resp_f):
			continue
		e.after = int(e.after) + 1
		var a := int(e.after)
		var n := s.global_transform.basis.y.normalized()
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(s.global_position, s.global_position - n * 12.0, 1))
		if not hit.is_empty():
			if a <= 30:
				e.up_max = maxf(float(e.up_max), rad_to_deg(n.angle_to(hit.normal)))
				e.vn0 = maxf(float(e.vn0), absf(s.velocity.dot(hit.normal)))
				e.hover0 = maxf(float(e.hover0), absf(p_h(s, hit) - hover_height))
			e.vn = maxf(float(e.vn), absf(s.velocity.dot(hit.normal)))
		var above := space.intersect_ray(PhysicsRayQueryParameters3D.create(s.global_position + n * 6.0, s.global_position, 1))
		if not above.is_empty():
			e.sunk = int(e.sunk) + 1
		if s.is_grounded:
			e.gnd = int(e.gnd) + 1
			if a > 6:
				e.hover_dev = maxf(float(e.hover_dev), absf(s.ground_distance - hover_height))
		elif int(e.first_air) < 0:
			e.first_air = a
		if float(e.v80) < 0.0 and s.velocity.length() >= 80.0:
			e.v80 = a / 60.0
		var cam: Camera3D = e.cam
		if cam:
			var to_ship := s.global_position - cam.global_position
			if a == 1:
				e.cam_d = to_ship.length()
				e.cam_aim = rad_to_deg((-cam.global_transform.basis.z).angle_to(to_ship))
			var cam_move := cam.global_position - (e.prev_cam as Vector3)
			var ship_move := s.global_position - (e.prev_pos as Vector3)
			# From the second tick: the first one is the respawn's own snap.
			if a >= 2 and a <= 60:
				e.cam_jump = maxf(float(e.cam_jump), (cam_move - ship_move).length())
			e.prev_cam = cam.global_position
		e.prev_pos = s.global_position
		if a >= SETTLE_TICKS:
			_finish(e)

static func p_h(s: ShipController, hit: Dictionary) -> float:
	return s.global_position.distance_to(hit.position)

func _finish(e: Dictionary) -> void:
	e.done = true
	_active.erase(e.ship)

func report(extra := {}) -> void:
	for e in episodes:
		var resp := "never" if int(e.resp_f) < 0 else "%.2f" % ((int(e.resp_f) - int(e.f0)) / 60.0)
		var leave := "-" if int(e.leave_f) < 0 else "%.2f" % ((int(e.leave_f) - int(e.f0)) / 60.0)
		var cam := ""
		if e.cam:
			cam = " cam d=%.1f aim=%.1f jump=%.2f" % [e.cam_d, e.cam_aim, e.cam_jump]
		var laps := ""
		if extra.has(e.ship):
			laps = " " + str(extra[e.ship])
		print("FALL %-10s spot=%5.0f %s->%s leave=%s resp=%s drop=%.0f back=%.0f lat=%.1f road=%s h=%.2f on_road=%s up_err=%.1f/%.1f gnd=%d/%d first_air=%d settle0.5s=%.2f/%.1f hover=%.2f vn=%.1f sunk=%d v80=%.2f bumps=%d respawns=%d%s%s" % [
				e.name, e.spot, e.side, e.dir, leave, resp, float(e.y0) - float(e.y_before), e.back, e.lat,
				e.road, e.road_h, str(e.on_road), e.up0, e.up_max, e.gnd, int(e.after), e.first_air,
				e.hover0, e.vn0, e.hover_dev, e.vn, e.sunk, e.v80, e.bumps, e.resp_n, cam, laps])
