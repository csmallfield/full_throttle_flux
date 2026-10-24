extends Node
## Chase camera + speed probe (v35). One AI ship drives a track's trained line
## with the real AGCamera2097 following it, and every frame logs what the
## camera is looking at and how steady the ship's speed is:
##
##   * ground_dist   distance along the camera's view ray to the track surface
##                   (layer 1). Small = the camera is staring at the road.
##   * pitch_err     camera pitch relative to the road ahead, degrees.
##                   Negative = looking down into the road more than the road
##                   itself drops away.
##   * yaw_err       angle between the camera's view and the direction to the
##                   centre line LOOK_METRES ahead, in the road plane, degrees.
##                   Large = looking into the inside of a corner (or outside).
##   * speed wobble  speed minus its 0.5 s moving average; spots where that
##                   swings by more than WOBBLE_UPS are reported with their
##                   distance along the track.
##
##   godot --headless --fixed-fps 60 --path . -s res://tools/dev/camera_probe_boot.gd
##
## Env:
##   CP_TRACK    track scene id (default test_circuit_5_live = Swoopy)
##   CP_SECONDS  seconds to log after the warm-up (default 75)
##   CP_CSV      write the per-frame log to this path (optional)
##   CP_CAMLEGACY 1 = the pre-v35 camera (no aim feedforward, track look-ahead
##               or boost lag) for an A/B
##   CP_SET      "prop=value,..." camera export overrides, e.g. track_look_weight=0.8

const WARMUP_SECONDS := 6.0
const LOOK_METRES := 45.0
const WOBBLE_UPS := 6.0

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _ready() -> void:
	await get_tree().process_frame
	var track_id := _env("CP_TRACK", "test_circuit_5_live")
	var seconds := _env("CP_SECONDS", "75").to_float()
	var profile := load("res://resources/ships/default_racer.tres") as ShipProfile
	var line_path := AILineTrainer.trained_path(track_id, profile.ship_id)
	var line := ResourceLoader.load(line_path, "", ResourceLoader.CACHE_MODE_IGNORE) as BakedRacingLine
	if line == null:
		print("CAMPROBE no line at %s" % line_path); get_tree().quit(1); return
	var track: Node = (load("res://scenes/tracks/%s.tscn" % track_id) as PackedScene).instantiate()
	add_child(track)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var helper := TrackSplineHelper.new(track)
	var ship := AILineTrainer.spawn_ship(profile)
	add_child(ship)
	var grid := _find(track, "StartingGrid")
	if grid and grid.has_method("get_pole_position"):
		ship.global_transform = grid.get_pole_position()
	ship.ai_controlled = true
	var ai := AIShipController.new()
	ai.ship = ship
	ai.skill_level = 1.0
	ai.avoidance_enabled = false
	add_child(ai)
	ai.prefer_trained_line = false
	ai.initialize(track, line)

	var cam: AGCamera2097 = (load("res://scripts/ag_camera_2097.gd") as GDScript).new()
	cam.intro_enabled = false
	if OS.get_environment("CP_CAMLEGACY") == "1":
		if "track_look_enabled" in cam:
			cam.set("track_look_enabled", false)
		if "boost_lag_enabled" in cam:
			cam.set("boost_lag_enabled", false)
		if "aim_feedforward" in cam:
			cam.set("aim_feedforward", 0.0)
	# CP_SET="prop=value,prop=value": override camera exports for A/B runs
	for kv in OS.get_environment("CP_SET").split(",", false):
		var parts := kv.split("=")
		if parts.size() == 2 and parts[0] in cam:
			cam.set(parts[0], str_to_var(parts[1]))
	add_child(cam)
	cam.ship = ship
	ship.camera = cam
	if cam.has_method("set_track"):
		cam.set_track(track)
	cam.make_current()

	var space := (ship as Node3D).get_world_3d().direct_space_state
	var dt := 1.0 / 60.0
	var t := 0.0
	var rows: Array = []
	var speeds := PackedFloat32Array()
	var prev_over := 0.0
	var boosts: Array = []
	while t < WARMUP_SECONDS + seconds:
		await get_tree().process_frame
		t += dt
		if t < WARMUP_SECONDS:
			continue
		var off: float = helper.world_to_spline_offset(ship.global_position)
		var d: float = off * helper.total_length
		var up: Vector3 = ship.current_track_normal if ship.is_grounded else ship.global_transform.basis.y
		var view: Vector3 = -cam.global_transform.basis.z
		var ahead: Vector3 = helper.spline_offset_to_world(helper.get_lookahead_offset(off, LOOK_METRES)) \
				+ helper.get_up_at_offset(helper.get_lookahead_offset(off, LOOK_METRES), true) * 1.0
		if helper.graph:
			# on a fork branch, measure against that branch's road ahead
			var loc: Dictionary = helper.graph.locate(ship.global_position)
			if int(loc.path) >= 0:
				var bl: float = helper.graph.path_length(loc.path)
				var bd: float = float(loc.distance) + LOOK_METRES
				var fr: Transform3D = helper.graph.frame_at(loc.path, minf(bd, bl)) if bd <= bl \
						else helper.graph.frame_at(-1, helper.graph.branch_to_main(loc.path, bl) + bd - bl)
				ahead = fr.origin + fr.basis.y * 1.0
		var to_ahead: Vector3 = (ahead - cam.global_position).normalized()
		# yaw: in the road plane
		var v_flat := view.slide(up).normalized()
		var a_flat := to_ahead.slide(up).normalized()
		var yaw_err := rad_to_deg(v_flat.signed_angle_to(a_flat, up)) if v_flat.length() > 0.1 and a_flat.length() > 0.1 else 0.0
		var pitch_err := rad_to_deg(asin(clampf(view.dot(up), -1, 1)) - asin(clampf(to_ahead.dot(up), -1, 1)))
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + view * 400.0, 1)
		q.exclude = [ship.get_rid()]
		var hit := space.intersect_ray(q)
		var gdist := 400.0
		if hit:
			gdist = cam.global_position.distance_to(hit.position)
		var v: float = ship.velocity.length()
		var over: float = ship.get_boost_overspeed()
		if over > prev_over + 1.0:
			boosts.append([t, d, v])
		prev_over = over
		speeds.append(v)
		rows.append([t, d, v, gdist, pitch_err, yaw_err, over, cam.fov, ship.measured_yaw_rate, rad_to_deg(asin(clampf(view.dot(up), -1, 1))), cam.global_position.distance_to(ship.global_position)])

	# ---- summary --------------------------------------------------------
	var n := rows.size()
	var low_ground := 0
	var sum_abs_yaw := 0.0
	var max_abs_yaw := 0.0
	var min_pitch := 0.0
	for r in rows:
		if r[3] < 25.0:
			low_ground += 1
		sum_abs_yaw += absf(r[5])
		max_abs_yaw = maxf(max_abs_yaw, absf(r[5]))
		min_pitch = minf(min_pitch, r[4])
	var into := 0
	var into_sum := 0.0
	for r in rows:
		if absf(r[8]) > 0.4:
			var it: float = -r[5] * signf(r[8])
			into_sum += it
			if it > 8.0:
				into += 1
	print("CAMPROBE turning frames: mean into-turn=%.1f deg, >8deg into turn=%.1f%%" % [into_sum / maxf(n, 1), 100.0 * into / maxf(n, 1)])
	print("CAMPROBE track=%s frames=%d ground<25m=%.1f%% mean|yaw|=%.1f max|yaw|=%.1f min_pitch=%.1f" % [
		track_id, n, 100.0 * low_ground / maxf(n, 1), sum_abs_yaw / maxf(n, 1), max_abs_yaw, min_pitch])
	# worst moments
	var idx: Array = range(n)
	idx.sort_custom(func(a, b): return rows[a][3] < rows[b][3])
	var shown := []
	for i in idx:
		var ok := true
		for s in shown:
			if absi(i - s) < 60:
				ok = false
		if ok:
			shown.append(i)
			var r: Array = rows[i]
			print("CAMPROBE low-look t=%.1f d=%.0fm v=%.0f ground=%.1fm pitch=%.1f yaw=%.1f over=%.0f" % r.slice(0, 7))
		if shown.size() >= 6:
			break
	# boosts: camera reaction in the 1 s after each pad
	for b in boosts:
		var i0 := int(round((b[0] - WARMUP_SECONDS) / dt)) - 1
		var minp := 999.0
		var ming := 999.0
		for k in range(maxi(i0 - 5, 0), mini(i0 + 60, n)):
			minp = minf(minp, rows[k][4])
			ming = minf(ming, rows[k][3])
		var d0: float = rows[maxi(i0 - 2, 0)][10]
		var dmax := 0.0
		var tmax := 0.0
		var tback := -1.0
		for k in range(maxi(i0, 0), mini(i0 + 180, n)):
			if rows[k][10] - d0 > dmax:
				dmax = rows[k][10] - d0
				tmax = rows[k][0] - b[0]
		for k in range(maxi(i0, 0), mini(i0 + 300, n)):
			if rows[k][0] - b[0] > tmax and rows[k][10] - d0 < 0.5 and tback < 0.0:
				tback = rows[k][0] - b[0]
		print("CAMPROBE boost t=%.1f d=%.0fm v=%.0f -> 1s min_pitch=%.1f min_ground=%.1fm  lag +%.1fm at %.2fs, back within 0.5m at %.2fs" % [b[0], b[1], b[2], minp, ming, dmax, tmax, tback])
	# speed wobble
	var w := 30
	var wob: Array = []
	for i in range(w, n - w):
		var avg := 0.0
		for k in range(i - w, i + w):
			avg += speeds[k]
		avg /= 2 * w
		wob.append([i, speeds[i] - avg])
	# local peak-to-peak over 1 s windows
	var reported := -1000
	var wob_count := 0
	for j in range(0, wob.size() - 60, 15):
		var lo := 1e9
		var hi := -1e9
		var flips := 0
		var last_sign := 0
		var prev_v := speeds[wob[j][0]]
		for k in range(j, j + 60):
			lo = minf(lo, wob[k][1])
			hi = maxf(hi, wob[k][1])
			var sv: float = speeds[wob[k][0]]
			var s := signi(int(sign(sv - prev_v)))
			if s != 0 and last_sign != 0 and s != last_sign:
				flips += 1
			if s != 0:
				last_sign = s
			prev_v = sv
		if hi - lo > WOBBLE_UPS and flips >= 4 and wob[j][0] - reported > 60:
			reported = wob[j][0]
			wob_count += 1
			var r: Array = rows[wob[j][0]]
			if wob_count <= 12:
				print("CAMPROBE wobble t=%.1f d=%.0fm v=%.0f p2p=%.1f flips=%d over=%.0f" % [r[0], r[1], r[2], hi - lo, flips, r[6]])
	print("CAMPROBE wobble_windows=%d" % wob_count)
	var csv := OS.get_environment("CP_CSV")
	if csv != "":
		var f := FileAccess.open(csv, FileAccess.WRITE)
		f.store_line("t,d,v,ground,pitch,yaw,over,fov,yawrate,localpitch,camdist")
		for r in rows:
			f.store_line(",".join(r.map(func(x): return "%.3f" % x)))
		f.close()
	get_tree().quit(0)

func _find(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var r := _find(c, nm)
		if r:
			return r
	return null
