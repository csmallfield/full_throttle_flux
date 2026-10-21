extends Node
## Headless autopilot for Fork Lab (v31): forks and jumps.
##
##   godot --headless --fixed-fps 60 --path . -s res://tools/fork_lab/fork_lab_drive_boot.gd
##
## Launches a real time trial, drives the player ship with a spline-following
## autopilot that takes the ROUTE you tell it at the fork, and reports:
##   * per section (open track, junctions, branch, each jump's ramps and gap):
##     grounded share, hover range, speed range, wall contacts, chase camera;
##   * per jump attempt: takeoff speed, flight time and distance, hover-ray
##     grounding flips in flight, touchdown, landing vertical speed into the
##     road, hover compression, rebound, speed lost;
##   * lap progress as RacePositionTracker computes it (TrackSplineHelper):
##     the largest step back / forward between ticks, so a jump in progress
##     crossing the fork shows up;
##   * respawns: where the ship fell, where it came back (path + metres) and
##     how its orientation matches the road there;
##   * lap times (simulated seconds: RaceManager uses the wall clock, which is
##     meaningless under --fixed-fps).
##
## Env:
##   FL_TRACK      track id (default fork_lab)
##   FL_ROUTE      "main" or "branch" at the fork (default main); "alt" =
##                 alternate each lap starting with main
##   FL_SPEED      target speed everywhere (default 0 = flat out)
##   FL_JUMP_SPEED "name:speed,...": hold `speed` for the 250 m before that
##                 jump's lip ("shared", "branch") -- e.g. to fall short. Only
##                 on the FIRST attempt; after a respawn the run is flat out.
##   FL_LAT        lateral line offset (default 0)
##   FL_LAPS       laps (default 2)
##   FL_MAX_T      give up after this many simulated seconds (default 60*laps+40)
##   FL_TRACE      1 = a line every 0.25 s; 2 = every tick within jumps;
##                 3 = every slide collision (what the hull hit)
##   FL_SHOTS      "name:path:metres,..." (path main|branch) chase-camera stills
##                 when the ship first passes that point (needs a renderer)
##   FL_SHOT_DIR   output folder (default user://fork_lab_shots)
##   FL_OVERVIEW   "x,y,z>x,y,z" one wide still from a free camera after driving
##   FL_RIG        N = also attach the cinematic camera rig to the player ship,
##                 snap and cycle it every N ticks (like the spectator's keys),
##                 and report each rig camera's occlusion per section
##   FL_STOCK      1 = fly the jumps with the profile's own air drag and hover
##                 spring (A/B against the TrackJump flight physics)

var ship: ShipController
var cam: Camera3D
var g: TrackGraph
var helper: TrackSplineHelper

var route := "main"
var alt_route := false
var target_speed := 0.0
var lat_target := 0.0
var trace := 0
var jump_speed := {}       # jump name ("shared"/"branch") -> speed
var jump_speed_used := {}

# Autopilot path state: -1 main, 0 branch.
var path := -1
var dist := 0.0

var stats := {}
var jumps_log: Array = []
var cur_jump: Dictionary = {}
var respawn_log: Array = []
var respawns := 0
var laps_done := 0
var lap_times: Array[float] = []
var lap_routes: Array[String] = []
var lap_route := ""
var sim_t := 0.0
var _lap_mark := -1.0
var shots: Array = []
var shot_dir := "user://fork_lab_shots"

var prog_prev := -1.0
var prog_back := 0.0
var prog_fwd := 0.0
var prog_back_at := ""
var prog_fwd_at := ""
var _respawned_tick := false
var _prev_cam_pos := Vector3.ZERO
var _prev_cam_fwd := Vector3.FORWARD
var _prev_ship_pos := Vector3.ZERO
var _cam_ready := false
var _fell_from := {}
var rig: CinematicCameraRig
var rig_every := 0
var rig_stats := {}   # section -> {cam name -> [ticks, occluded]}
var rig_snaps := 0

func _env_f(k: String, d: float) -> float:
	var v := OS.get_environment(k)
	return v.to_float() if v != "" else d

func _ready() -> void:
	await get_tree().process_frame
	var root := get_tree().root
	var gm = root.get_node("GameManager")
	var track_id := OS.get_environment("FL_TRACK")
	if track_id == "":
		track_id = "fork_lab"
	gm.select_track_by_id(track_id)
	gm.select_mode("time_trial")
	route = OS.get_environment("FL_ROUTE")
	if route == "":
		route = "main"
	if route == "alt":
		alt_route = true
		route = "main"
	target_speed = _env_f("FL_SPEED", 0.0)
	lat_target = _env_f("FL_LAT", 0.0)
	trace = int(_env_f("FL_TRACE", 0.0))
	for item in OS.get_environment("FL_JUMP_SPEED").split(",", false):
		var kv := item.split(":")
		jump_speed[kv[0]] = kv[1].to_float()
	var laps := int(_env_f("FL_LAPS", 2.0))
	for item in OS.get_environment("FL_SHOTS").split(",", false):
		var kv := item.split(":")
		shots.append([kv[0], -1 if kv[1] == "main" else 0, kv[2].to_float(), false])
	if OS.get_environment("FL_SHOT_DIR") != "":
		shot_dir = OS.get_environment("FL_SHOT_DIR")
	if not shots.is_empty() or OS.get_environment("FL_OVERVIEW") != "":
		DirAccess.make_dir_recursive_absolute(shot_dir)
	
	var launcher: Node = load("res://scenes/race_launcher.tscn").instantiate()
	root.add_child(launcher)
	for i in 600:
		await get_tree().physics_frame
		ship = _find_ship(root)
		if ship and ship.camera:
			break
	if ship == null:
		print("DRIVE no ship"); get_tree().quit(1); return
	cam = ship.camera as Camera3D
	g = get_tree().get_first_node_in_group(TrackGraph.GROUP) as TrackGraph
	if g == null:
		print("DRIVE no TrackGraph on this track"); get_tree().quit(1); return
	helper = TrackSplineHelper.new(_track_root(root))
	if OS.get_environment("FL_STOCK") == "1":
		# A/B: fly the jumps with the profile's own air and hover physics.
		for j in g.jumps:
			j.air_drag = ship.profile.air_drag
			j.landing_pull_limit_g = -1.0
			j.landing_damping_scale = 1.0
			j.landing_force_scale = 1.0
	ship.ai_controlled = true
	ship.ship_respawned.connect(_on_respawn)
	root.get_node("RaceManager").lap_completed.connect(_on_lap)
	path = -1
	dist = g.locate(ship.global_position).distance
	rig_every = int(_env_f("FL_RIG", 0.0))
	if rig_every > 0:
		rig = CinematicCameraRig.new()
		rig.name = "CinematicCameraRig"
		root.add_child(rig)
		rig.spline = helper
		rig.follow(ship)
	lap_route = route
	
	print("DRIVE track=%s route=%s speed=%s jump_speed=%s lat=%.0f main=%.0f m branch=%.0f m" % [track_id,
			"alt" if alt_route else route, str(target_speed) if target_speed > 0 else "full",
			str(jump_speed), lat_target, g.main_length(), g.path_length(0) if g.branches.size() > 0 else 0.0])
	
	var t := 0.0
	var next_trace := 0.0
	var max_t := _env_f("FL_MAX_T", 60.0 * laps + 40.0)
	while laps_done < laps and t < max_t:
		await get_tree().physics_frame
		var dt := 1.0 / 60.0
		t += dt
		sim_t = t
		_track_path()
		_drive()
		_measure(dt)
		if rig:
			_measure_rig()
		await _maybe_shoot()
		if trace == 1 and t >= next_trace:
			next_trace = t + 0.25
			_trace_line(t)
		elif trace == 2 and not cur_jump.is_empty():
			_trace_line(t)
		elif trace == 3:
			for i in ship.get_slide_collision_count():
				var col := ship.get_slide_collision(i)
				var f := g.frame_at(path, dist)
				print("COL t=%.2f %s d=%.1f lat=%.1f collider=%s/%s pos=%s normal=%s" % [t, "M" if path < 0 else "B",
						dist, (ship.global_position - f.origin).dot(f.basis.x), col.get_collider().get_parent().name if col.get_collider().get_parent() else "", col.get_collider().name,
						col.get_position().snapped(Vector3.ONE * 0.1), col.get_normal().snapped(Vector3.ONE * 0.01)])
	_report(t)
	await _overview()
	get_tree().quit(0)

func _track_root(root: Node) -> Node:
	var n: Node = g
	while n.get_parent() and n.get_parent() != root and not (n.get_parent() is ModeBase):
		n = n.get_parent()
	return n

# --- path tracking ---------------------------------------------------------------

## Local search along the current path; switch to the branch at the fork if
## that's the chosen route, back to main at the rejoin.
func _track_path() -> void:
	var p := ship.global_position
	var length := g.path_length(path)
	var curve := g.path_of(path).curve
	var xf := g.path_of(path).global_transform
	var local := xf.affine_inverse() * p
	var best := dist
	var best_sq := INF
	var d := -40.0
	while d <= 40.0:
		var s := dist + d
		if path < 0:
			s = fposmod(s, length)
		else:
			s = clampf(s, 0.0, length)
		var sq := curve.sample_baked(s).distance_squared_to(local)
		if sq < best_sq:
			best_sq = sq
			best = s
		d += 1.0
	if best_sq > 60.0 * 60.0:
		var loc := g.locate(p)
		path = loc.path
		best = loc.distance
	dist = best
	if g.branches.is_empty():
		return
	var br: TrackBranch = g.branches[0]
	if path < 0 and route == "branch" and dist >= br.fork_distance and dist < br.fork_distance + 30.0:
		path = 0
		dist = dist - br.fork_distance
	elif path == 0 and dist >= g.path_length(0) - 1.0:
		path = -1
		dist = br.rejoin_distance + 1.0

# --- autopilot ----------------------------------------------------------------

func _drive() -> void:
	var speed := ship.velocity.length()
	var look := clampf(speed * 0.35, 18.0, 45.0)
	var ahead := dist + look
	var length := g.path_length(path)
	var f: Transform3D
	if path < 0:
		f = g.frame_at(-1, fposmod(ahead, length))
	elif ahead <= length:
		f = g.frame_at(path, ahead)
	else:
		f = g.frame_at(-1, g.branches[0].rejoin_distance + (ahead - length))
	var target := f.origin + f.basis.x.normalized() * lat_target
	var local := ship.global_transform.basis.inverse() * (target - ship.global_position)
	var err := atan2(-local.x, -local.z)
	ship.steer_input = clampf(err * 2.4 - ship.measured_yaw_rate * 0.25, -1.0, 1.0) if ship.is_grounded else 0.0
	ship.pitch_input = 0.0
	ship.airbrake_left = 0.0
	ship.airbrake_right = 0.0
	if ship.controls_locked:
		ship.throttle_input = 0.0
		return
	if _lap_mark < 0.0:
		_lap_mark = sim_t
	var want := target_speed
	for j in g.jumps:
		var key := "shared" if j.branch < 0 else "branch"
		if not jump_speed.has(key) or jump_speed_used.get(key, false) or j.branch != path:
			continue
		if dist > j.lip - 250.0 and dist < j.lip:
			want = jump_speed[key]
	if want > 0.0:
		ship.throttle_input = clampf((want - speed) * 0.2, 0.0, 1.0)
		if speed > want + 6.0 and ship.is_grounded:
			ship.airbrake_left = 1.0
			ship.airbrake_right = 1.0
	else:
		ship.throttle_input = 1.0

# --- measurement ----------------------------------------------------------------

func _jump_here() -> TrackJump:
	for j in g.jumps:
		if j.branch == path and dist >= j.kicker_start and dist <= j.landing_end:
			return j
	return null

func _section() -> String:
	var j := _jump_here()
	if j:
		if dist < j.lip:
			return j.jump_name + ": kicker"
		if dist < j.landing:
			return j.jump_name + ": gap"
		return j.jump_name + ": landing"
	if g.branches.is_empty():
		return "open track"
	var br: TrackBranch = g.branches[0]
	if path == 0:
		if dist < br.fork_blend:
			return "fork junction"
		if dist > g.path_length(0) - br.rejoin_blend:
			return "rejoin junction"
		return "branch"
	var tabs: Array = g._tables(0)
	if dist >= br.fork_distance and dist <= br.fork_distance + 200.0 and dist - br.fork_distance < (tabs[0] as PackedFloat64Array)[-1]:
		return "fork junction"
	if dist <= br.rejoin_distance and dist >= br.rejoin_distance - (tabs[1] as PackedFloat64Array)[-1]:
		return "rejoin junction"
	if dist > br.fork_distance and dist < br.rejoin_distance:
		return "main route"
	return "open track"

func _measure(dt: float) -> void:
	if ship.controls_locked:
		return
	var z := _section()
	if not stats.has(z):
		stats[z] = {"ticks": 0, "air": 0, "min_h": INF, "max_h": 0.0, "min_v": INF, "max_v": 0.0,
				"walls": 0, "cam_aim": 0.0, "cam_up": 0.0, "min_cam_d": INF, "max_cam_d": 0.0,
				"cam_blocked": 0, "cam_jump": 0, "cam_turn": 0.0, "gflips": 0, "pg": ship.is_grounded}
	var s: Dictionary = stats[z]
	s.ticks += 1
	if not ship.is_grounded:
		s.air += 1
	else:
		s.min_h = minf(s.min_h, ship.ground_distance)
		s.max_h = maxf(s.max_h, ship.ground_distance)
	if bool(s.pg) != ship.is_grounded:
		s.gflips += 1
	s.pg = ship.is_grounded
	var v := ship.velocity.length()
	s.min_v = minf(s.min_v, v)
	s.max_v = maxf(s.max_v, v)
	if ship._is_scraping_wall:
		s.walls += 1
	if cam:
		var to_ship := ship.global_position - cam.global_position
		s.cam_aim = maxf(s.cam_aim, rad_to_deg((-cam.global_transform.basis.z).angle_to(to_ship)))
		s.cam_up = maxf(s.cam_up, rad_to_deg(cam.global_transform.basis.y.angle_to(Vector3.UP)))
		var cd := to_ship.length()
		s.min_cam_d = minf(s.min_cam_d, cd)
		s.max_cam_d = maxf(s.max_cam_d, cd)
		var space := ship.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(ship.global_position, cam.global_position, 5)
		q.exclude = [ship.get_rid()]
		if not space.intersect_ray(q).is_empty():
			s.cam_blocked += 1
		if _cam_ready and not _respawned_tick:
			var moved := (cam.global_position - _prev_cam_pos) - (ship.global_position - _prev_ship_pos)
			if moved.length() > 2.0:
				s.cam_jump += 1
			s.cam_turn = maxf(s.cam_turn, rad_to_deg(_prev_cam_fwd.angle_to(-cam.global_transform.basis.z)))
		_prev_cam_pos = cam.global_position
		_prev_cam_fwd = -cam.global_transform.basis.z
		_prev_ship_pos = ship.global_position
		_cam_ready = true
	_measure_jump()
	_measure_progress()
	_respawned_tick = false

func _measure_rig() -> void:
	if ship.controls_locked:
		return
	if Engine.get_physics_frames() % rig_every == 0:
		rig.snap()
		rig.cycle(1)
		rig_snaps += 1
	var z := _section()
	if not rig_stats.has(z):
		rig_stats[z] = {}
	var space := ship.get_world_3d().direct_space_state
	for i in rig.cameras.size():
		var c: Camera3D = rig.cameras[i]
		var n: String = rig.CAMERA_NAMES[i]
		if not (rig_stats[z] as Dictionary).has(n):
			rig_stats[z][n] = [0, 0]
		var e: Array = rig_stats[z][n]
		e[0] += 1
		var q := PhysicsRayQueryParameters3D.create(c.global_position, ship.global_position, 5)
		q.exclude = [ship.get_rid()]
		if not space.intersect_ray(q).is_empty():
			e[1] += 1

func _measure_jump() -> void:
	var j := _jump_here()
	if cur_jump.is_empty():
		if j and dist >= j.lip - 3.0 and dist < j.lip + 5.0 and not ship.is_grounded:
			cur_jump = {"name": j.jump_name, "jump": j, "path": path, "t0": sim_t, "v0": ship.velocity.length(),
					"vy0": ship.velocity.y, "lip_y": g.frame_at(j.branch, j.lip).origin.y,
					"physics": ship.jump != null, "touch_t": -1.0, "touch_d": 0.0, "vn": 0.0,
					"settle_vn": 0.0, "min_h": INF, "rebound": 0.0, "min_v": INF, "flips": 0,
					"pg": false, "max_up": 0.0, "result": "", "landed_t": -1.0}
		return
	var c := cur_jump
	var v := ship.velocity.length()
	if c.touch_t < 0.0:
		c.max_up = maxf(c.max_up, ship.global_position.y - float(c.lip_y))
		if ship.is_grounded and dist > (c.jump as TrackJump).landing - 2.0:
			c.touch_t = sim_t
			c.touch_d = dist - (c.jump as TrackJump).landing
			var n := ship.hover_ray.get_collision_normal() if ship.hover_ray.is_colliding() else Vector3.UP
			c.vn = ship.velocity.dot(n)
			c.v_touch = v
		elif ship.is_grounded and bool(c.pg) == false and sim_t - float(c.t0) > 0.05:
			c.flips += 1   # grounded mid-flight before the landing ramp
	else:
		c.min_v = minf(c.min_v, v)
		if ship.is_grounded:
			if ship.ground_distance < 2.75 and c.settle_vn == 0.0:
				var n2 := ship.hover_ray.get_collision_normal() if ship.hover_ray.is_colliding() else Vector3.UP
				c.settle_vn = ship.velocity.dot(n2)
			c.min_h = minf(c.min_h, ship.ground_distance)
			var n3 := ship.current_track_normal
			c.rebound = maxf(c.rebound, ship.velocity.dot(n3))
		if sim_t - float(c.touch_t) > 1.5:
			c.result = "landed"
			_close_jump()
			return
	c.pg = ship.is_grounded
	if path != int(c.path) or dist > (c.jump as TrackJump).landing_end + 250.0:
		c.result = "lost"
		_close_jump()

func _close_jump() -> void:
	var c := cur_jump
	c.v_end = ship.velocity.length()
	jumps_log.append(c)
	cur_jump = {}

func _measure_progress() -> void:
	var off := helper.world_to_spline_offset(ship.global_position)
	var p := float(laps_done) + off
	if prog_prev >= 0.0 and not _respawned_tick:
		var dp := p - prog_prev
		# Lap wrap before the lap is counted (the line is 30 m in).
		if dp < -0.5:
			dp += 1.0
		elif dp > 0.5:
			dp -= 1.0
		var dm := dp * g.main_length()
		if dm < -1.0 or dm > 4.0:
			var loc := g.locate(ship.global_position)
			print("PROGSTEP %.2f m at t=%.2f %s %.1f m: helper says %.2f, exact locate path %d main_d %.2f lat %.1f" % [
					dm, sim_t, "main" if path < 0 else "branch", dist, off * g.main_length(), loc.path,
					loc.main_distance, (ship.global_position - g.frame_at(path, dist).origin).dot(g.frame_at(path, dist).basis.x)])
		if dm < prog_back:
			prog_back = dm
			prog_back_at = "%s %s %.0f m" % [_section(), "main" if path < 0 else "branch", dist]
		if dm > prog_fwd:
			prog_fwd = dm
			prog_fwd_at = "%s %s %.0f m" % [_section(), "main" if path < 0 else "branch", dist]
	prog_prev = p

func _on_respawn() -> void:
	respawns += 1
	_respawned_tick = true
	var from_path := path
	var from_d := dist
	if not cur_jump.is_empty():
		cur_jump.result = "fell"
		_close_jump()
	var loc := g.locate(ship.global_position)
	path = loc.path
	dist = loc.distance
	var f := g.frame_at(path, dist)
	var up_err := rad_to_deg(ship.global_transform.basis.y.angle_to(f.basis.y))
	var fwd_err := rad_to_deg((-ship.global_transform.basis.z).angle_to(-f.basis.z))
	respawn_log.append("respawn %d at t=%.2f: fell on %s at %.0f m -> back on %s at %.0f m (%.0f m behind), up err %.1f deg, heading err %.1f deg, h=%.2f" % [
		respawns, sim_t, "main" if from_path < 0 else "branch", from_d, "main" if path < 0 else "branch",
		dist, (from_d - dist) if path == from_path else -1.0, up_err, fwd_err, ship.ground_distance])
	# Only the first attempt is slowed down.
	for j in g.jumps:
		if j.branch == from_path:
			jump_speed_used["shared" if j.branch < 0 else "branch"] = true

func _on_lap(_n: int, _wall: float) -> void:
	lap_times.append(sim_t - _lap_mark)
	lap_routes.append(lap_route)
	_lap_mark = sim_t
	laps_done += 1
	if alt_route:
		route = "branch" if route == "main" else "main"
	lap_route = route

func _find_ship(n: Node) -> ShipController:
	if n is ShipController and not (n as ShipController).ai_controlled:
		return n
	for c in n.get_children():
		var f := _find_ship(c)
		if f:
			return f
	return null

func _maybe_shoot() -> void:
	if ship.controls_locked:
		return
	for sh in shots:
		if sh[3] or int(sh[1]) != path:
			continue
		var gap: float = dist - float(sh[2])
		if gap >= 0.0 and gap < 30.0:
			sh[3] = true
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var fp: String = shot_dir.path_join("%s.png" % sh[0])
			img.save_png(fp)
			print("SHOT %s at %s %.0f m v=%.0f grounded=%s -> %s" % [sh[0], "main" if path < 0 else "branch",
					dist, ship.velocity.length(), str(ship.is_grounded), ProjectSettings.globalize_path(fp)])

func _overview() -> void:
	var spec := OS.get_environment("FL_OVERVIEW")
	if spec == "":
		return
	var ab := spec.split(">")
	var a := ab[0].split_floats(",")
	var b := ab[1].split_floats(",")
	var c := Camera3D.new()
	c.far = 8000.0
	c.fov = 55.0
	get_tree().root.add_child(c)
	c.global_position = Vector3(a[0], a[1], a[2])
	c.look_at(Vector3(b[0], b[1], b[2]), Vector3.UP if absf(a[1] - b[1]) < 0.99 * Vector3(a[0], a[1], a[2]).distance_to(Vector3(b[0], b[1], b[2])) else Vector3.FORWARD)
	c.make_current()
	for i in 4:
		await RenderingServer.frame_post_draw
	var fp := shot_dir.path_join("overview.png")
	get_viewport().get_texture().get_image().save_png(fp)
	print("SHOT overview -> %s" % ProjectSettings.globalize_path(fp))

func _trace_line(t: float) -> void:
	print("T %6.2f %s d=%6.1f v=%5.1f vy=%6.2f gnd=%s h=%5.2f jump=%s prog=%.4f" % [t,
		"M" if path < 0 else "B", dist, ship.velocity.length(), ship.velocity.y,
		"Y" if ship.is_grounded else "n", ship.ground_distance, "Y" if ship.jump else "-", prog_prev])

func _report(t: float) -> void:
	var lt := []
	for i in lap_times.size():
		lt.append("%.2f (%s)" % [lap_times[i], lap_routes[i]])
	print("DRIVE done t=%.1f s laps=%d lap_times=%s respawns=%d" % [t, laps_done, str(lt), respawns])
	for s in respawn_log:
		print("RESPAWN " + s)
	for c in jumps_log:
		var flight: float = (float(c.touch_t) - float(c.t0)) if float(c.touch_t) > 0.0 else -1.0
		print("JUMP %-12s %-6s takeoff v=%5.1f vy=%5.1f peak=%+5.1f m | %s" % [c.name, c.result, c.v0, c.vy0, c.max_up,
			("flight %.2f s, ray contact %.1f m past the landing lip, v into road %.1f (at hover height %.1f) | hover min %.2f, rebound %.1f, speed %.0f -> min %.0f -> %.0f, mid-flight groundings %d, jump physics %s" % [
				flight, c.touch_d, c.vn, c.settle_vn, c.min_h, c.rebound, c.get("v_touch", 0.0),
				c.min_v if float(c.min_v) < INF else 0.0, c.v_end, c.flips, str(c.physics)]) if flight > 0.0 else "no touchdown"])
	if rig:
		print("RIG snaps+cycles=%d" % rig_snaps)
		for z in rig_stats:
			var parts := []
			var tot := 0.0
			for n in rig_stats[z]:
				var e: Array = rig_stats[z][n]
				var pc := 100.0 * float(e[1]) / maxf(float(e[0]), 1.0)
				tot += pc
				if pc >= 20.0:
					parts.append("%s %.0f%%" % [n, pc])
			print("RIG %-22s mean occlusion %.1f%% over %d cameras; >=20%%: %s" % [z, tot / maxf(float((rig_stats[z] as Dictionary).size()), 1.0),
					(rig_stats[z] as Dictionary).size(), ", ".join(parts)])
	print("PROGRESS largest step back %.2f m (%s), largest step forward %.2f m (%s) per tick" % [
			prog_back, prog_back_at, prog_fwd, prog_fwd_at])
	for z in stats:
		var s: Dictionary = stats[z]
		print("ZONE %-22s ticks=%5d air=%4d gflips=%3d hover[%.2f..%.2f] v[%.0f..%.0f] wall=%d cam_aim<=%.1f cam_tilt<=%.1f cam_d[%.1f..%.1f] cam_blocked=%d cam_snaps=%d cam_turn<=%.1f/tick" % [
			z, s.ticks, s.air, s.gflips, s.min_h, s.max_h, s.min_v, s.max_v, s.walls, s.cam_aim, s.cam_up,
			s.min_cam_d, s.max_cam_d, s.cam_blocked, s.cam_jump, s.cam_turn])
