extends Node
## Single-AI lap probe (v33). One AI ship, alone on the track, drives a given
## racing line exactly the way AILineTrainer measures it (warm up, wait for
## the start/finish line, time whole laps in SIMULATED seconds) and reports
## the lap time, the line's mean target speed, the speed actually driven, the
## speed through each corner, wall contacts and tracking error.
##
##   godot --headless --fixed-fps 60 --path . -s res://tools/dev/ai_lap_probe_boot.gd
##
## Env:
##   AL_TRACK    track scene id (default test_circuit_3_live)
##   AL_LINE     BakedRacingLine to drive: res:// or absolute path
##               (default: the track's saved trained line)
##   AL_PROFILE  ShipProfile path (default res://resources/ships/default_racer.tres)
##   AL_SKILL    AI skill (default 1.0)
##   AL_LAPS     flying laps to time (default 2)
##   AL_CORNERS  1 = print every corner (default: summary only)
##   AL_SCENE    ship scene to drive instead of the profile's (profile still
##               applied before _ready), e.g. res://scenes/ships/default_racer_old.tscn
##   AL_ROUTE    forked tracks: -1 = main route lap, r = through branch r
##               (pair with AL_LINE=<track>__route<r> line for r >= 0)
##
## Corners are the line's curvature peaks tighter than CORNER_RADIUS, at
## least CORNER_GAP metres apart. Old and new lines share their geometry (the
## style search and trainer only rewrite speeds and control gains), so the
## same corners come out for both and the numbers compare directly.

const WARMUP_SECONDS := 6.0     # AILineTrainer.warmup_seconds
const CORNER_RADIUS := 350.0
const CORNER_GAP := 150.0
const CORNER_WINDOW := 60.0

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d

func _ready() -> void:
	await get_tree().process_frame
	var track_id := _env("AL_TRACK", "test_circuit_3_live")
	var profile_path := _env("AL_PROFILE", "res://resources/ships/default_racer.tres")
	var skill := _env("AL_SKILL", "1.0").to_float()
	var laps := int(_env("AL_LAPS", "2"))
	var profile := load(profile_path) as ShipProfile
	var line_path := _env("AL_LINE", AILineTrainer.trained_path(track_id, profile.ship_id))
	var line := ResourceLoader.load(line_path, "", ResourceLoader.CACHE_MODE_IGNORE) as BakedRacingLine
	if line == null:
		print("LAPPROBE no line at %s" % line_path); get_tree().quit(1); return
	
	var track: Node = (load("res://scenes/tracks/%s.tscn" % track_id) as PackedScene).instantiate()
	add_child(track)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var helper := TrackSplineHelper.new(track)
	# Forked tracks: drive one route lap, timed along that route (as the trainer).
	var route := -2
	if OS.get_environment("AL_ROUTE") != "" and helper.graph:
		route = int(OS.get_environment("AL_ROUTE"))
		var g: TrackGraph = helper.graph
		helper = TrackSplineHelper.for_path(g.route_path(route), track)
		helper.set_jump_spans(g, route)
	
	var ship := AILineTrainer.spawn_ship(profile)
	if OS.get_environment("AL_SCENE") != "":
		ship.free()
		ship = (load(OS.get_environment("AL_SCENE")) as PackedScene).instantiate()
		ship.profile = profile
	add_child(ship)
	var grid := _find(track, "StartingGrid")
	if grid and grid.has_method("get_pole_position"):
		ship.global_transform = grid.get_pole_position()
	ship.ai_controlled = true
	var ai := AIShipController.new()
	ai.ship = ship
	ai.skill_level = skill
	ai.avoidance_enabled = false
	add_child(ai)
	ai.prefer_trained_line = false  # drive exactly the line we were given
	if route != -2:
		ai.fixed_route = route
	ai.initialize(track, line)
	var driven := AILineTrainer.driven_profile(ship)
	print("LAPPROBE track=%s line=%s profile=%s driven_hash=%s line_hash=%s line_lap=%.3f style_log=%d" % [
		track_id, line_path.get_file(), profile.ship_id,
		driven.handling_hash() if driven else "MISMATCH", line.profile_hash,
		line.trained_lap_time, line.style_log.size()])
	
	var n := line.sample_count
	var speed := PackedFloat32Array()
	var lat_err := PackedFloat32Array()
	speed.resize(n)
	lat_err.resize(n)
	var t := 0.0
	var dt := 1.0 / 60.0
	var armed := false
	var timing := false
	var lap_start := 0.0
	var prev := -1.0
	var lap_times: Array[float] = []
	var walls := 0
	var wall_ticks := 0
	var was_scraping := false
	var max_lat := 0.0
	var respawns := [0]
	ship.ship_respawned.connect(func(): respawns[0] += 1)
	while lap_times.size() < laps and t < 600.0:
		await get_tree().physics_frame
		t += dt
		var off: float = helper.world_to_spline_offset(ship.global_position)
		var wrapped: bool = prev >= 0.0 and off < prev - 0.5
		if not armed:
			if t >= WARMUP_SECONDS:
				armed = true
				prev = off
			continue
		if not timing:
			if wrapped:
				timing = true
				lap_start = t
			prev = off
			continue
		# Only the first timed lap feeds the per-sample arrays.
		if lap_times.is_empty():
			var i: int = wrapi(int(off * float(n)), 0, n)
			var v: float = ship.velocity.length()
			speed[i] = v if speed[i] == 0.0 else minf(speed[i], v)
			var e: float = absf(helper.calculate_lateral_offset(ship.global_position, off, true) - line.get_lateral_at(off))
			lat_err[i] = maxf(lat_err[i], e)
			max_lat = maxf(max_lat, e)
			var scraping: bool = ship.get("_is_scraping_wall") == true
			if scraping:
				wall_ticks += 1
				if not was_scraping:
					walls += 1
			was_scraping = scraping
		if wrapped:
			lap_times.append(t - lap_start)
			lap_start = t
		prev = off
	
	# Fill samples the ship skipped (fast sections) from their neighbours.
	for k in range(n):
		if speed[k] == 0.0:
			for j in range(1, 8):
				if speed[wrapi(k - j, 0, n)] > 0.0:
					speed[k] = speed[wrapi(k - j, 0, n)]
					break
	
	var ds: float = line.track_length / float(n)
	var mean_target := 0.0
	var mean_speed := 0.0
	for k in range(n):
		mean_target += line.target_speeds[k]
		mean_speed += speed[k]
	mean_target /= n
	mean_speed /= n
	
	var corners := _corners(line, ds)
	var win: int = int(CORNER_WINDOW / ds)
	var c_driven := 0.0
	var c_target := 0.0
	var verbose := OS.get_environment("AL_CORNERS") == "1"
	for c in corners:
		var tmin := INF
		var dmin := INF
		for k in range(-win, win + 1):
			var j: int = wrapi(c + k, 0, n)
			tmin = minf(tmin, line.target_speeds[j])
			if speed[j] > 0.0:
				dmin = minf(dmin, speed[j])
		c_driven += dmin
		c_target += tmin
		if verbose:
			print("CORNER d=%5.0fm R=%4.0fm target_min=%5.1f driven_min=%5.1f" % [
				c * ds, 1.0 / maxf(absf(line.curvatures[c]), 0.00001), tmin, dmin])
	if not corners.is_empty():
		c_driven /= corners.size()
		c_target /= corners.size()
	print("LAPPROBE laps=%s mean_target=%.1f mean_driven=%.1f corners=%d corner_target=%.1f corner_driven=%.1f walls=%d wall_ticks=%d respawns=%d max_lat_err=%.1f" % [
		str(lap_times.map(func(x): return snappedf(x, 0.001))), mean_target, mean_speed,
		corners.size(), c_target, c_driven, walls, wall_ticks, respawns[0], max_lat])
	get_tree().quit(0)

## Curvature peaks tighter than CORNER_RADIUS, the tightest first, CORNER_GAP apart.
func _corners(line: BakedRacingLine, ds: float) -> Array[int]:
	var n := line.sample_count
	var order: Array[int] = []
	for i in range(n):
		if absf(line.curvatures[i]) >= 1.0 / CORNER_RADIUS:
			order.append(i)
	order.sort_custom(func(a, b): return absf(line.curvatures[a]) > absf(line.curvatures[b]))
	var gap: int = int(CORNER_GAP / ds)
	var out: Array[int] = []
	for i in order:
		var ok := true
		for c in out:
			if mini(absi(i - c), n - absi(i - c)) < gap:
				ok = false
				break
		if ok:
			out.append(i)
	out.sort()
	return out

func _find(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var r := _find(c, nm)
		if r:
			return r
	return null
