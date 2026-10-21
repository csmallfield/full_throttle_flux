extends Node
## Headless autopilot test for magnetic lock zones (v30).
##
##   godot --headless --fixed-fps 60 --path . -s res://tools/dev/loop_lab_drive_boot.gd
##
## Launches a real time trial on a track (default loop_lab), drives the player
## ship with a simple spline-following autopilot (steering measured in the
## SHIP's frame, so it works upside down) and reports, per magnetic zone:
## grounding, hover height, spline-contact recoveries, speed, how far the ship's
## up drifts from the road's, and how the chase camera holds up.
##
## Env:
##   LL_TRACK   track id (default loop_lab)
##   LL_MAGNET  magnet override 0..1 (default: zone values)
##   LL_MAGNET_ZONE  apply LL_MAGNET only to the zone with this name
##   LL_SPEED   target speed in u/s via throttle (default 0 = flat out)
##   LL_LAT     lateral line offset in metres (default 0)
##   LL_LAPS    laps to drive (default 2)
##   LL_TRACE   1 = print a line every 0.25 s
##   LL_SHOTS   "name:distance,name:distance" -- save the chase camera's frame
##              as PNG when the ship first passes each distance (needs a
##              renderer: run under xvfb-run without --headless)
##   LL_SHOT_DIR  output folder (default user://loop_lab_shots)
##   LL_START_AT  teleport to this distance at full speed once the race
##              starts (for rendering just one section)
##   LL_OVERVIEW  "x,y,z>x,y,z" -- after driving, one wide shot from a free
##              camera at the first point looking at the second
##   LL_PUSH    v33: "d:side,d:side" -- knock the ship off the track the first
##              time it passes each distance (side O = outside of the corner
##              ahead, I, L, R) and measure the fall, respawn, settle and the
##              chase camera (FallMonitor). LL_PUSH_LAT / LL_PUSH_UP: kick in
##              u/s (default 70 / 35)

var ship: ShipController
var cam: Camera3D
var mt: MagneticTrack
var trk: MagneticTrack.Tracker

var target_speed := 0.0
var lat_target := 0.0
var trace := false

var stats := {}
var cur_zone := ""
var respawns := 0
var laps_done := 0
var lap_times: Array[float] = []
var sim_t := 0.0
var shots: Array = []      # [name, distance, taken]
var shot_dir := "user://loop_lab_shots"
var _lap_mark := -1.0
var fm: FallMonitor = null
var push_spots: Array = []   # [d, side, done]
var _frame := 0
var _air := 0.0
var _air_max := 0.0

func _env_f(k: String, d: float) -> float:
	var v := OS.get_environment(k)
	return v.to_float() if v != "" else d

func _ready() -> void:
	await get_tree().process_frame
	var root := get_tree().root
	var gm = root.get_node("GameManager")
	var track_id := OS.get_environment("LL_TRACK")
	if track_id == "":
		track_id = "loop_lab"
	gm.select_track_by_id(track_id)
	gm.select_mode("time_trial")
	target_speed = _env_f("LL_SPEED", 0.0)
	lat_target = _env_f("LL_LAT", 0.0)
	trace = OS.get_environment("LL_TRACE") == "1"
	var laps := int(_env_f("LL_LAPS", 2.0))
	for item in OS.get_environment("LL_SHOTS").split(",", false):
		var kv := item.split(":")
		shots.append([kv[0], kv[1].to_float(), false])
	if OS.get_environment("LL_SHOT_DIR") != "":
		shot_dir = OS.get_environment("LL_SHOT_DIR")
	if not shots.is_empty() or OS.get_environment("LL_OVERVIEW") != "":
		DirAccess.make_dir_recursive_absolute(shot_dir)
	
	var launcher: Node = load("res://scenes/race_launcher.tscn").instantiate()
	root.add_child(launcher)
	
	# Wait for the ship and its camera.
	for i in 600:
		await get_tree().physics_frame
		ship = _find_ship(root)
		if ship and ship.camera:
			break
	if ship == null:
		print("DRIVE no ship"); get_tree().quit(1); return
	cam = ship.camera as Camera3D
	mt = get_tree().get_first_node_in_group(MagneticTrack.GROUP) as MagneticTrack
	if mt == null:
		# Plain tracks: a zone-less MagneticTrack just for the autopilot's
		# spline queries (inert for the ship: no zones, weight 0 everywhere).
		mt = MagneticTrack.new()
		mt.spline_path = NodePath("..")
		_find_path(root).add_child(mt)
	var mo := _env_f("LL_MAGNET", -1.0)
	var only := OS.get_environment("LL_MAGNET_ZONE")
	if mo >= 0.0:
		if only == "":
			mt.magnet_override = mo
		else:
			for z in mt.zones:
				if z.zone_name == only:
					z.magnet_strength = mo
	trk = mt.make_tracker()
	ship.ai_controlled = true
	ship.ship_respawned.connect(func(): respawns += 1)
	# v33: after a respawn the autopilot re-acquires its spline position.
	ship.ship_respawned.connect(func(): trk.reset())
	for item in OS.get_environment("LL_PUSH").split(",", false):
		var kv := item.split(":")
		push_spots.append([kv[0].to_float(), kv[1] if kv.size() > 1 else "O", false])
	if not push_spots.is_empty():
		fm = FallMonitor.new(_find_path(root).get_parent(), ship.get_world_3d())
	# RaceManager times laps with the wall clock, which is meaningless under
	# --fixed-fps, so time them in simulated seconds here.
	root.get_node("RaceManager").lap_completed.connect(_on_lap)
	# v33: never file autopilot laps as player recordings. Under --fixed-fps
	# their wall-clock lap times are a few seconds, so they would top every
	# bucket and push real laps out of the KEEP=10 store (deleting them).
	var recorder := root.find_child("LapRecorder", true, false)
	if recorder:
		recorder.set("_enabled", false)
	
	print("DRIVE track=%s magnet=%s%s speed=%s lat=%.0f length=%.0f" % [track_id,
			str(mo) if mo >= 0.0 else "zone", (" on " + only) if only != "" and mo >= 0.0 else "", str(target_speed) if target_speed > 0 else "full",
			lat_target, mt.get_length()])
	
	var t := 0.0
	var next_trace := 0.0
	var max_t := 60.0 * laps + 30.0
	while laps_done < laps and t < max_t:
		await get_tree().physics_frame
		var dt := 1.0 / 60.0
		t += dt
		sim_t = t
		_drive()
		_measure(dt)
		_frame += 1
		_push_tick()
		await _maybe_shoot()
		if trace and t >= next_trace:
			next_trace = t + 0.25
			_trace_line(t)
	_report(t)
	await _overview()
	get_tree().quit(0)

func _maybe_shoot() -> void:
	if ship.controls_locked:
		return
	for sh in shots:
		if sh[2]:
			continue
		var gap: float = trk.distance - (sh[1] as float)
		if gap >= 0.0 and gap < 40.0:
			sh[2] = true
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var path: String = shot_dir.path_join("%s.png" % sh[0])
			img.save_png(path)
			print("SHOT %s at %.0f m v=%.0f -> %s" % [sh[0], trk.distance, ship.velocity.length(),
					ProjectSettings.globalize_path(path)])

func _overview() -> void:
	var spec := OS.get_environment("LL_OVERVIEW")
	if spec == "":
		return
	var ab := spec.split(">")
	var a := ab[0].split_floats(",")
	var b := ab[1].split_floats(",")
	var c := Camera3D.new()
	c.far = 6000.0
	c.fov = 55.0
	get_tree().root.add_child(c)
	c.global_position = Vector3(a[0], a[1], a[2])
	c.look_at(Vector3(b[0], b[1], b[2]), Vector3.UP)
	c.make_current()
	for i in 4:
		await RenderingServer.frame_post_draw
	var path := shot_dir.path_join("overview.png")
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT overview -> %s" % ProjectSettings.globalize_path(path))

func _on_lap(_n: int, _wall: float) -> void:
	# First lap includes the standing start from the grid.
	lap_times.append(sim_t - _lap_mark)
	_lap_mark = sim_t
	laps_done += 1

func _find_ship(n: Node) -> ShipController:
	if n is ShipController and not (n as ShipController).ai_controlled:
		return n
	for c in n.get_children():
		var f := _find_ship(c)
		if f:
			return f
	return null

func _find_path(n: Node) -> Path3D:
	if n is Path3D and n.name == "MainSpline":
		return n
	for c in n.get_children():
		var f := _find_path(c)
		if f:
			return f
	return null

# --- autopilot ----------------------------------------------------------------

func _drive() -> void:
	trk.update(ship.global_position)
	var speed := ship.velocity.length()
	var look := clampf(speed * 0.35, 18.0, 45.0)
	var f := mt.frame_at(fposmod(trk.distance + look, mt.get_length()))
	var target := f.origin + f.basis.x.normalized() * lat_target
	var local := ship.global_transform.basis.inverse() * (target - ship.global_position)
	var err := atan2(-local.x, -local.z)        # + = target to the left
	# damp with yaw rate so it doesn't weave
	var steer := clampf(err * 2.4 - ship.measured_yaw_rate * 0.25, -1.0, 1.0)
	ship.steer_input = steer
	ship.pitch_input = 0.0
	ship.airbrake_left = 0.0
	ship.airbrake_right = 0.0
	if ship.controls_locked:
		ship.throttle_input = 0.0
		return
	if _lap_mark < 0.0:
		_lap_mark = sim_t
		var start_at := _env_f("LL_START_AT", -1.0)
		if start_at >= 0.0:
			var sf := mt.frame_at(start_at)
			ship.respawn(sf.origin + sf.basis.y.normalized() * 2.75, sf.basis.orthonormalized())
			ship.velocity = -sf.basis.z.normalized() * ship.max_speed
			trk.reset()
	if target_speed > 0.0:
		ship.throttle_input = clampf((target_speed - speed) * 0.2, 0.0, 1.0)
		if speed > target_speed + 6.0:
			ship.airbrake_left = 1.0
			ship.airbrake_right = 1.0
	else:
		ship.throttle_input = 1.0

# --- measurement ----------------------------------------------------------------

func _zone_name() -> String:
	var zr := mt.zone_at(trk.distance)
	if (zr[0] as float) <= 0.0 or zr[1] == null:
		return ""
	return (zr[1] as MagneticZone).zone_name

func _measure(dt: float) -> void:
	if ship.controls_locked:
		return
	var z := _zone_name()
	if z == "":
		z = "(open track)"
	if not stats.has(z):
		stats[z] = {"ticks": 0, "air": 0, "recovered": 0, "min_h": INF, "max_h": 0.0,
				"min_v": INF, "max_v": 0.0, "max_up_err": 0.0, "max_cam_up": 0.0,
				"max_cam_aim": 0.0, "min_cam_d": INF, "max_cam_d": 0.0, "walls": 0,
				"min_frame_h": INF, "inverted": 0}
	var s: Dictionary = stats[z]
	s.ticks += 1
	if not ship.is_grounded:
		s.air += 1
	if ship.get("magnet_contact_recovered"):
		s.recovered += 1
	if ship.is_grounded:
		s.min_h = minf(s.min_h, ship.ground_distance)
		s.max_h = maxf(s.max_h, ship.ground_distance)
	var v := ship.velocity.length()
	s.min_v = minf(s.min_v, v)
	s.max_v = maxf(s.max_v, v)
	var f := mt.frame_at(trk.distance)
	var road_up := f.basis.y.normalized()
	if road_up.y < -0.5:
		s.inverted += 1
	s.min_frame_h = minf(s.min_frame_h, (ship.global_position - f.origin).dot(road_up))
	s.max_up_err = maxf(s.max_up_err, rad_to_deg(ship.global_transform.basis.y.angle_to(road_up)))
	if ship._is_scraping_wall:
		s.walls += 1
	if cam:
		var cam_up := cam.global_transform.basis.y
		s.max_cam_up = maxf(s.max_cam_up, rad_to_deg(cam_up.angle_to(ship.global_transform.basis.y)))
		var to_ship := ship.global_position - cam.global_position
		s.max_cam_aim = maxf(s.max_cam_aim, rad_to_deg((-cam.global_transform.basis.z).angle_to(to_ship)))
		var cd := to_ship.length()
		s.min_cam_d = minf(s.min_cam_d, cd)
		s.max_cam_d = maxf(s.max_cam_d, cd)

func _trace_line(t: float) -> void:
	print("T %6.2f d=%6.0f v=%5.1f gnd=%s rec=%s h=%5.2f w=%.2f m=%.2f up=%s camUp=%.0f" % [
		t, trk.distance, ship.velocity.length(), "Y" if ship.is_grounded else "n",
		"Y" if ship.get("magnet_contact_recovered") else "-", ship.ground_distance,
		float(ship.get("magnet_weight") if ship.get("magnet_weight") != null else 0.0),
		float(ship.get("magnet_strength") if ship.get("magnet_strength") != null else 0.0),
		ship.global_transform.basis.y.snapped(Vector3.ONE * 0.01),
		rad_to_deg(cam.global_transform.basis.y.angle_to(ship.global_transform.basis.y)) if cam else 0.0])

func _push_tick() -> void:
	if ship.controls_locked:
		return
	if ship.is_grounded or (fm and fm.is_busy(ship)):
		_air = 0.0
	else:
		_air += 1.0 / 60.0
		_air_max = maxf(_air_max, _air)
	if fm == null:
		return
	if not fm.is_busy(ship) and laps_done == 0:
		for sp in push_spots:
			if not sp[2] and trk.distance >= (sp[0] as float) and trk.distance < (sp[0] as float) + 60.0:
				sp[2] = true
				fm.push(ship, sp[0], sp[1], _frame, _env_f("LL_PUSH_LAT", 70.0), _env_f("LL_PUSH_UP", 35.0), cam)
				break
	fm.tick(_frame)

func _report(t: float) -> void:
	print("DRIVE done t=%.1f s laps=%d lap_times=%s respawns=%d airmax=%.2f" % [t, laps_done,
			str(lap_times.map(func(x): return snappedf(x, 0.01))), respawns, _air_max])
	if fm:
		fm.report()
	# v33: for bit-identical A/B of time-trial runs.
	var tr := ship.global_transform
	print("DRIVE checksum=%d" % str([tr.origin, tr.basis.x, tr.basis.y, ship.velocity, lap_times, respawns]).hash())
	for z in stats:
		var s: Dictionary = stats[z]
		print("ZONE %-14s ticks=%5d air=%4d recovered=%4d inverted=%4d hover[%.2f..%.2f] v[%.0f..%.0f] up_err=%.1f cam_up=%.1f cam_aim=%.1f cam_d[%.1f..%.1f] wall=%d" % [
			z, s.ticks, s.air, s.recovered, s.inverted, s.min_h, s.max_h, s.min_v, s.max_v,
			s.max_up_err, s.max_cam_up, s.max_cam_aim, s.min_cam_d, s.max_cam_d, s.walls])
