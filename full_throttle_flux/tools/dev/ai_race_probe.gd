extends Node
## AI race probe (v30). Runs a real RaceMode race (the AI field; the player
## ship gets no input) for a fixed number of physics frames and reports, per ship:
## laps, distance, speed range, respawns, airborne time inside magnetic zones,
## plus a checksum of every ship's final transform, so two code versions can
## be compared for bit-identical behaviour.
##
##   godot --headless --fixed-fps 60 --path . -s res://tools/dev/ai_race_probe_boot.gd
##
## Env: PROBE_TRACK (default loop_lab), PROBE_SECONDS (default 60),
##      PROBE_MAGNET (optional magnet override 0..1 for every zone, or only
##      the zone named PROBE_MAGNET_ZONE), PROBE_SEED (default 1234),
##      PROBE_DIFFICULTY (0 easy, 1 medium = default, 2 hard),
##      PROBE_SPIKES=1 (graph tracks: log every tick a ship is over 135 u/s),
##      PROBE_SHOVE=1 (graph tracks: once per lap per AI, shove it sideways
##      toward the OTHER route as the roads split, as contact would; =2 puts
##      it straight onto the other route's road, past the splitter nose),
##      PROBE_SABOTAGE=1 (graph tracks: once per AI, take over in the branch
##      jump's run-up and hold ~55 u/s to the lip so it falls short, then
##      hand control back)
##
## v32: on tracks with a TrackGraph (forks / jumps) it also reports, per ship:
## route decisions and the route actually driven each time through the fork,
## jump attempts / landings / falls, where each respawn put the ship, lap
## progress continuity (largest step back, as RacePositionTracker measures it),
## and how often the race order inside the fork disagreed with the order the
## ships came out of it. Nothing extra is computed on other tracks.

var ships: Array = []
var respawns := {}
var air_in_zone := {}
var zone_ticks := {}
var vmin := {}
var vmax := {}
var laps := {}
## v33: lap completions in race frames (RaceManager's lap times are wall
## clock, meaningless under --fixed-fps), wall contacts (rising edges of the
## ship's scrape state) and ticks spent on a wall. Read-only: the checksum is
## unaffected.
var lap_frames := {}
var walls := {}
var wall_ticks := {}
var scraping := {}
var frame_now := 0

func _ready() -> void:
	await get_tree().process_frame
	var root := get_tree().root
	var gm = root.get_node("GameManager")
	var track_id := OS.get_environment("PROBE_TRACK")
	if track_id == "":
		track_id = "loop_lab"
	gm.select_track_by_id(track_id)
	gm.selected_mode = "race"
	if OS.get_environment("PROBE_DIFFICULTY") != "":
		gm.select_race_difficulty(int(OS.get_environment("PROBE_DIFFICULTY")))
	var seconds := OS.get_environment("PROBE_SECONDS").to_float()
	if seconds <= 0.0:
		seconds = 60.0
	
	# Repeatable races: the grid slot and each AI's wobble phase use the
	# global RNG (visual models use their own, which only changes looks).
	seed(int(OS.get_environment("PROBE_SEED")) if OS.get_environment("PROBE_SEED") != "" else 1234)
	var launcher: Node = load("res://scenes/race_launcher.tscn").instantiate()
	root.add_child(launcher)
	
	# Wait for the race to start; the whole field exists by then.
	var rm = root.get_node("RaceManager")
	var go := [false]
	rm.race_started.connect(func(): go[0] = true)
	for i in 1800:
		await get_tree().physics_frame
		if go[0]:
			break
	ships = _find_ships(root)
	if ships.is_empty():
		print("PROBE no ships"); get_tree().quit(1); return
	
	var mo := OS.get_environment("PROBE_MAGNET")
	if mo != "":
		var mt := get_tree().get_first_node_in_group(MagneticTrack.GROUP) as MagneticTrack
		var only := OS.get_environment("PROBE_MAGNET_ZONE")
		if mt and only == "":
			mt.magnet_override = mo.to_float()
		elif mt:
			for z in mt.zones:
				if z.zone_name == only:
					z.magnet_strength = mo.to_float()
	
	rm.ship_lap_completed.connect(_on_ship_lap)
	var graph := get_tree().get_first_node_in_group(TrackGraph.GROUP) as TrackGraph
	if graph and graph.branches.is_empty() and graph.jumps.is_empty():
		graph = null
	if graph:
		_fork_setup(graph, ships)
	for s in ships:
		respawns[s] = 0
		air_in_zone[s] = 0
		zone_ticks[s] = 0
		vmin[s] = INF
		vmax[s] = 0.0
		laps[s] = 0
		lap_frames[s] = []
		walls[s] = 0
		wall_ticks[s] = 0
		scraping[s] = false
		s.ship_respawned.connect(func(): respawns[s] += 1)
	
	# The player ship gets no input and sits on the grid; the AI field races.
	var frames := int(seconds * 60.0)
	for f in frames:
		frame_now = f + 1
		await get_tree().physics_frame
		for s in ships:
			var scr: bool = s.get("_is_scraping_wall") == true
			if scr:
				wall_ticks[s] += 1
				if not scraping[s]:
					walls[s] += 1
			scraping[s] = scr
			var v: float = s.velocity.length()
			vmin[s] = minf(vmin[s], v)
			vmax[s] = maxf(vmax[s], v)
			if s.magnet_weight > 0.5:
				zone_ticks[s] += 1
				if not s.is_grounded:
					air_in_zone[s] += 1
		if graph:
			_fork_tick(f)
	
	var h := []
	for s in ships:
		var t: Transform3D = s.global_transform
		h.append([t.origin, t.basis.x, t.basis.y, s.velocity])
		print("PROBE %-22s ai=%s laps=%d v[%.0f..%.0f] respawns=%d zone_ticks=%d air_in_zone=%d pos=%s" % [
			s.name, str(s.ai_controlled), laps[s], vmin[s] if vmin[s] < INF else 0.0, vmax[s],
			respawns[s], zone_ticks[s], air_in_zone[s], t.origin.snapped(Vector3.ONE * 0.1)])
	if graph:
		_fork_report()
	_lap_report()
	print("PROBE track=%s seconds=%.0f ships=%d checksum=%d" % [track_id, seconds, ships.size(), str(h).hash()])
	get_tree().quit(0)

func _on_ship_lap(s, n, _t) -> void:
	laps[s] = n
	if lap_frames.has(s):
		lap_frames[s].append(frame_now)

## v33: per-ship lap times in simulated seconds (lap 1 is the standing start,
## timed from the green light), wall contacts, and the field's spread at each
## lap line every AI crossed.
func _lap_report() -> void:
	var ai_ships: Array = ships.filter(func(s): return s.ai_controlled)
	var flying: Array[float] = []
	for s in ai_ships:
		var times: Array[float] = []
		var prev := 0
		for fr in lap_frames[s]:
			times.append((fr - prev) / 60.0)
			prev = fr
		flying.append_array(times.slice(1))
		print("PROBELAP %-12s laps=%s walls=%d wall_ticks=%d respawns=%d" % [
			s.name, str(times.map(func(x): return snappedf(x, 0.01))),
			walls[s], wall_ticks[s], respawns[s]])
	var spreads: Array[float] = []
	var k := 0
	while true:
		var lo := INF
		var hi := -INF
		var all_done := true
		for s in ai_ships:
			if lap_frames[s].size() <= k:
				all_done = false
				break
			lo = minf(lo, lap_frames[s][k])
			hi = maxf(hi, lap_frames[s][k])
		if not all_done or ai_ships.is_empty():
			break
		spreads.append(snappedf((hi - lo) / 60.0, 0.01))
		k += 1
	var tw := 0
	for s in ai_ships:
		tw += walls[s]
	flying.sort()
	var mean := 0.0
	for x in flying:
		mean += x
	if not flying.is_empty():
		mean /= flying.size()
	print("PROBEFIELD ai=%d walls=%d best_flying=%.2f mean_flying=%.2f flying_laps=%d spread_at_lap_line=%s" % [
		ai_ships.size(), tw, flying[0] if not flying.is_empty() else 0.0, mean,
		flying.size(), str(spreads)])

func _find_ships(n: Node) -> Array:
	var out: Array = []
	if n is ShipController:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_ships(c))
	return out

# =============================================================================
# FORKS AND JUMPS (v32; only on tracks with a TrackGraph)
# =============================================================================

var g: TrackGraph
var scorer: TrackSplineHelper
var trk := {}        # ship -> TrackGraph.Tracker (independent of the AI's own)
var fk := {}         # ship -> stats dictionary
var fork_samples := []   # [lap_key, ship_a, ship_b, a_ahead_by_progress]
var exits := {}      # "ship:lap" -> frame the ship came out of the fork
var routes_taken := {}   # "ship:lap" -> path taken through the fork
var takeoffs := {}   # jump name -> [takeoff speeds]

func _fork_setup(graph: TrackGraph, ship_list: Array) -> void:
	g = graph
	scorer = TrackSplineHelper.new(g.get_parent())
	for s in ship_list:
		trk[s] = g.make_tracker()
		var st := {"took": [], "prev_prog": -1.0, "back": 0.0, "fwd": 0.0, "jump_tries": {}, "jump_falls": {},
				"respawn_at": [], "air": false, "jump_name": "", "in_fork": false, "fork_path": -1,
				"lap": 0, "last_main": -1.0, "sunk": 0, "sunk_at": "", "vmax_at": "", "vmax": 0.0,
				"shoved_lap": -1, "shoves": 0, "sabotaged": false, "sabotage_t": 0, "walls": 0}
		fk[s] = st
		s.ship_respawned.connect(_fork_respawn.bind(s))

func _ai_of(s: ShipController) -> AIShipController:
	return _find_ai(get_tree().root, s)

func _find_ai(n: Node, s: ShipController) -> AIShipController:
	if n is AIShipController and (n as AIShipController).ship == s:
		return n
	for c in n.get_children():
		var f := _find_ai(c, s)
		if f:
			return f
	return null

func _fork_tick(frame: int) -> void:
	var br: TrackBranch = g.branches[0] if not g.branches.is_empty() else null
	var L := g.main_length()
	for s in ships:
		var st: Dictionary = fk[s]
		var t: TrackGraph.Tracker = trk[s]
		t.update(s.global_position)
		# Progress as the race positions see it.
		var off := scorer.world_to_spline_offset(s.global_position)
		var p := float(laps[s]) + off
		if float(st.prev_prog) >= 0.0:
			var dp := p - float(st.prev_prog)
			if dp < -0.5:
				dp += 1.0
			elif dp > 0.5:
				dp -= 1.0
			st.back = minf(st.back, dp * L)
			st.fwd = maxf(st.fwd, dp * L)
		st.prev_prog = p
		# Below the road surface (hull through the collision) or a speed spike.
		var fr := g.frame_at(t.path, t.distance)
		var hgt: float = (s.global_position - fr.origin).dot(fr.basis.y)
		var lat: float = absf((s.global_position - fr.origin).dot(fr.basis.x))
		if hgt < 0.8 and lat < 19.0 and not s.is_grounded and s.jump == null:
			st.sunk = int(st.sunk) + 1
			if st.sunk_at == "":
				st.sunk_at = "f%d %s %.0f h=%.1f" % [frame, "M" if t.path < 0 else "B", t.distance, hgt]
		if s.velocity.length() > 135.0 and OS.get_environment("PROBE_SPIKES") == "1":
			var near: ShipController = null
			for o in ships:
				if o != s and (near == null or (o as Node3D).global_position.distance_to(s.global_position) \
						< near.global_position.distance_to(s.global_position)):
					near = o
			print("SPIKE f%d %s v=%s grounded=%s jump=%s h=%.2f nearest %s %.1f m (its v=%s grounded=%s)" % [frame, s.name,
					s.velocity.snapped(Vector3.ONE * 0.1), s.is_grounded, s.jump != null, s.ground_distance, near.name,
					near.global_position.distance_to(s.global_position), near.velocity.snapped(Vector3.ONE * 0.1), near.is_grounded])
		if s.velocity.length() > float(st.vmax):
			st.vmax = s.velocity.length()
			st.vmax_at = "f%d %s %.0f" % [frame, "M" if t.path < 0 else "B", t.distance]
		if s._is_scraping_wall:
			st.walls = int(st.walls) + 1
		st.last_pos = s.global_position
		st.last_v = s.velocity
		# Off the track: airborne, not on a jump, for over a second.
		if not s.is_grounded and (s.jump == null or (st.has("air_from") and frame - int(st.air_from[0]) > 150)):
			if not st.has("air_from"):
				st.air_from = [frame, s.global_position, s.velocity, t.path, t.distance]
			elif frame - int(st.air_from[0]) == 60:
				print("OFFTRACK f%d %s airborne since f%d at %s %.0f (pos %s v %s), now %s" % [frame, s.name,
						st.air_from[0], "main" if int(st.air_from[3]) < 0 else "branch", st.air_from[4],
						(st.air_from[1] as Vector3).snapped(Vector3.ONE * 0.1), (st.air_from[2] as Vector3).snapped(Vector3.ONE * 0.1),
						s.global_position.snapped(Vector3.ONE * 0.1)])
		else:
			st.erase("air_from")
		_fork_disturb(s, st, t, frame)
		# Jumps: a flight from a TrackJump is an attempt.
		if s.jump != null and not st.air:
			st.air = true
			st.jump_name = s.jump.jump_name
			st.jump_tries[st.jump_name] = int(st.jump_tries.get(st.jump_name, 0)) + 1
			if not takeoffs.has(st.jump_name):
				takeoffs[st.jump_name] = []
			(takeoffs[st.jump_name] as Array).append(s.velocity.length())
			if OS.get_environment("PROBE_TAKEOFFS") == "1":
				var tf := g.frame_at(t.path, t.distance)
				print("TAKEOFF f%d %s %s v=%.0f lat=%.1f heading_err=%.1f deg vel_err=%.1f deg" % [frame, s.name,
						st.jump_name, s.velocity.length(), (s.global_position - tf.origin).dot(tf.basis.x),
						rad_to_deg((-s.global_transform.basis.z).slide(Vector3.UP).signed_angle_to((-tf.basis.z).slide(Vector3.UP), Vector3.UP)),
						rad_to_deg(s.velocity.slide(Vector3.UP).signed_angle_to((-tf.basis.z).slide(Vector3.UP), Vector3.UP))])
		elif s.jump == null:
			st.air = false
		# Fork: which road did it actually take, and when did it come out.
		if br:
			var md := t.main_distance()
			var inside := fposmod(md - br.fork_distance, L) < fposmod(br.rejoin_distance - br.fork_distance, L)
			if inside:
				if t.path >= 0:
					st.fork_path = t.path
				if not st.in_fork:
					st.in_fork = true
					st.fork_path = -1
					st.lap = int(st.lap) + 1
			elif st.in_fork:
				st.in_fork = false
				(st.took as Array).append(st.fork_path)
				exits["%s:%d" % [s.name, st.lap]] = frame
				routes_taken["%s:%d" % [s.name, st.lap]] = st.fork_path
	# Race order inside the fork, every 0.5 s, for later comparison with the
	# order the ships came out of it.
	if br and frame % 30 == 0:
		for i in ships.size():
			for j in range(i + 1, ships.size()):
				var a: ShipController = ships[i]
				var b: ShipController = ships[j]
				var sa: Dictionary = fk[a]
				var sb: Dictionary = fk[b]
				if sa.in_fork and sb.in_fork and sa.lap == sb.lap:
					fork_samples.append([sa.lap, a, b, float(sa.prev_prog) > float(sb.prev_prog)])

## Test disturbances (env-gated): a sideways shove toward the other route as
## the roads split, and a throttle cut in the branch jump's run-up.
func _fork_disturb(s: ShipController, st: Dictionary, t: TrackGraph.Tracker, frame: int) -> void:
	if not s.ai_controlled or g.branches.is_empty():
		return
	var br: TrackBranch = g.branches[0]
	var ai := _ai_of(s)
	if ai == null or ai.route_follower == null:
		return
	if OS.get_environment("PROBE_SHOVE") != "" and int(st.shoved_lap) != int(st.lap) and st.in_fork:
		var main_into: float = fposmod(t.main_distance() - br.fork_distance, g.main_length())
		if main_into > 105.0 and main_into < 115.0 and OS.get_environment("PROBE_SHOVE") == "1":
			st.shoved_lap = st.lap
			st.shoves = int(st.shoves) + 1
			var f := g.frame_at(-1, br.fork_distance + main_into)
			# The branch lies to the right of the main route at this fork.
			var side := 1.0 if ai.route_choice < 0 else -1.0
			s.velocity += f.basis.x.normalized() * side * 40.0
			print("SHOVE f%d %s (route %d) toward the %s" % [frame, s.name, ai.route_choice,
					"branch" if side > 0.0 else "main route"])
		elif OS.get_environment("PROBE_SHOVE") == "2" and main_into > 175.0 and main_into < 185.0:
			# Onto the other road beyond the nose: where a hard hit at the
			# splitter could leave it.
			st.shoved_lap = st.lap
			st.shoves = int(st.shoves) + 1
			var other: int = 0 if ai.route_choice < 0 else -1
			var od: float = main_into if other == 0 else br.fork_distance + main_into
			if other == 0:
				od = main_into * 0.92
			var f2 := g.frame_at(other, od)
			var keep_speed := s.velocity.length()
			s.global_position = f2.origin + f2.basis.y.normalized() * 2.75
			s.global_transform.basis = f2.basis.orthonormalized()
			s.velocity = -f2.basis.z.normalized() * keep_speed
			print("SHOVE f%d %s (route %d) placed on the %s at %.0f m" % [frame, s.name, ai.route_choice,
					"branch" if other == 0 else "main route", od])
	if OS.get_environment("PROBE_SABOTAGE") == "1" and not st.sabotaged and t.path == 0 \
			and t.distance > 330.0 and t.distance < 380.0:
		st.sabotaged = true
		st.sabotage_t = 90
		ai.ai_active = false
		print("SABOTAGE f%d %s: throttle cut on the branch run-up at %.0f m, v=%.0f" % [frame, s.name,
				t.distance, s.velocity.length()])
	if int(st.sabotage_t) > 0:
		# Hold ~55 u/s (airbrakes, then a trickle of throttle) up to the lip,
		# then hand back: a ship that is far too slow for the jump.
		var v: float = s.velocity.length()
		s.throttle_input = clampf((55.0 - v) * 0.2, 0.0, 1.0)
		s.steer_input = 0.0
		s.airbrake_left = 1.0 if v > 62.0 else 0.0
		s.airbrake_right = s.airbrake_left
		if (t.path == 0 and t.distance > 541.0) or t.path != 0:
			st.sabotage_t = 0
			s.airbrake_left = 0.0
			s.airbrake_right = 0.0
			ai.ai_active = true

func _fork_respawn(s: ShipController) -> void:
	var st: Dictionary = fk[s]
	if int(st.sabotage_t) > 0:
		st.sabotage_t = 0
		var ai := _ai_of(s)
		if ai:
			ai.ai_active = true
	if st.air and st.jump_name != "":
		st.jump_falls[st.jump_name] = int(st.jump_falls.get(st.jump_name, 0)) + 1
	st.air = false
	var loc := g.locate(s.global_position)
	(st.respawn_at as Array).append("%s %.0f" % ["main" if int(loc.path) < 0 else "branch", loc.distance])
	if st.has("last_pos"):
		var lp: Vector3 = st.last_pos
		var lloc := g.locate(lp)
		print("RESPAWNED %s from %s (%s %.0f, dist %.0f m to it, v=%s) to %s %.0f" % [s.name, lp.snapped(Vector3.ONE * 0.1),
				"main" if int(lloc.path) < 0 else "branch", lloc.distance, sqrt(float(lloc.dist_sq)),
				(st.last_v as Vector3).snapped(Vector3.ONE * 0.1), "main" if int(loc.path) < 0 else "branch", loc.distance])
	(trk[s] as TrackGraph.Tracker).reset()
	st.prev_prog = -1.0

func _fork_report() -> void:
	var tot_take := 0
	var tot_pass := 0
	var tries := {}
	var falls := {}
	var reasons := {}
	for s in ships:
		var st: Dictionary = fk[s]
		var ai := _ai_of(s)
		var decisions := []
		var forced := 0
		var traffic := 0
		if ai and ai.route_follower:
			for e in ai.route_log:
				decisions.append("%s" % ("B" if int(e[1]) >= 0 else "M"))
				var why := str(e[2])
				var cat := "shortcut (roll)" if why.begins_with("shortcut") \
						else "main (roll)" if why.contains("roll") \
						else "main (predicted lip speed too low)" if why.contains("predicted") \
						else "commit: too slow, back to main" if why.contains("too slow") \
						else "commit: traffic switch" if why.contains("blocked") \
						else "forced: on the other road" if why.begins_with("forced") else why
				reasons[cat] = int(reasons.get(cat, 0)) + 1
			forced = ai.route_forced_switches
			traffic = ai.route_traffic_switches
		var took := ""
		for x in st.took:
			took += "B" if int(x) >= 0 else "M"
			tot_pass += 1
			if int(x) >= 0:
				tot_take += 1
		for k in st.jump_tries:
			tries[k] = int(tries.get(k, 0)) + int(st.jump_tries[k])
		for k in st.jump_falls:
			falls[k] = int(falls.get(k, 0)) + int(st.jump_falls[k])
		print("FORK %-14s skill=%.2f decided=%s took=%s traffic_switch=%d forced=%d shoves=%d jumps=%s falls=%s respawns_at=%s progress_step back=%.2f fwd=%.2f m wall_ticks=%d below_road=%d %s vmax=%.0f %s" % [
			s.name, ai.skill_level if ai else -1.0, "".join(decisions), took, traffic, forced, st.shoves,
			str(st.jump_tries), str(st.jump_falls), str(st.respawn_at), st.back, st.fwd, st.walls, st.sunk, st.sunk_at,
			st.vmax, st.vmax_at])
	# Order inside the fork vs order out of it.
	# Same-route pairs measure ordinary overtaking inside the fork; mixed-route
	# pairs add whatever the branch -> main mapping gets wrong.
	var agree := [0, 0, 0]
	var n := [0, 0, 0]
	for smp in fork_samples:
		var a: ShipController = smp[1]
		var b: ShipController = smp[2]
		var ka := "%s:%d" % [a.name, smp[0]]
		var kb := "%s:%d" % [b.name, smp[0]]
		if not exits.has(ka) or not exits.has(kb):
			continue
		var mixed := 1 if int(routes_taken[ka]) != int(routes_taken[kb]) else 0
		n[mixed] += 1
		var a_first: bool = int(exits[ka]) < int(exits[kb])
		if a_first == bool(smp[3]):
			agree[mixed] += 1
		# Mixed pairs that came out more than half a second apart (not a tie).
		if mixed == 1 and absi(int(exits[ka]) - int(exits[kb])) > 30:
			n[2] += 1
			if a_first == bool(smp[3]):
				agree[2] += 1
	var tk := ""
	for k in takeoffs:
		var arr: Array = takeoffs[k]
		var lo := INF
		var sum := 0.0
		for v in arr:
			lo = minf(lo, v)
			sum += v
		tk += "%s min %.0f mean %.0f; " % [k, lo, sum / maxf(arr.size(), 1)]
	print("FORK summary: shortcut taken %d/%d passes (%.0f%%); jump attempts %s, falls %s; takeoff speeds: %s" % [
		tot_take, tot_pass, 100.0 * tot_take / maxf(tot_pass, 1), str(tries), str(falls), tk])
	print("FORK reasons: %s" % str(reasons))
	print("FORK order: race order inside the fork matched the exit order for same-route pairs %d/%d (%.1f%%), mixed-route pairs %d/%d (%.1f%%), mixed pairs exiting > 0.5 s apart %d/%d (%.1f%%)" % [
		agree[0], n[0], 100.0 * agree[0] / maxf(n[0], 1), agree[1], n[1], 100.0 * agree[1] / maxf(n[1], 1),
		agree[2], n[2], 100.0 * agree[2] / maxf(n[2], 1)])
	# Flicker: how often each pair's order changes while both are in the fork.
	# A shortcut ship catching a main-route one SHOULD pass it once (the
	# estimate catching up); passing back and forth is noise. And the last
	# in-fork order should match who came out first.
	var seqs := {}
	for smp in fork_samples:
		var key := "%d|%s|%s" % [smp[0], (smp[1] as Node).name, (smp[2] as Node).name]
		if not seqs.has(key):
			seqs[key] = [smp[1], smp[2], smp[0], []]
		(seqs[key][3] as Array).append(bool(smp[3]))
	var pairs := [0, 0]
	var multi := [0, 0]
	var last_ok := [0, 0]
	for key in seqs:
		var e: Array = seqs[key]
		var ka := "%s:%d" % [(e[0] as Node).name, e[2]]
		var kb := "%s:%d" % [(e[1] as Node).name, e[2]]
		if not exits.has(ka) or not exits.has(kb):
			continue
		var mixed := 1 if int(routes_taken[ka]) != int(routes_taken[kb]) else 0
		var seq: Array = e[3]
		var flips := 0
		for i in range(1, seq.size()):
			if seq[i] != seq[i - 1]:
				flips += 1
		pairs[mixed] += 1
		if flips > 1:
			multi[mixed] += 1
		if bool(seq[seq.size() - 1]) == (int(exits[ka]) < int(exits[kb])):
			last_ok[mixed] += 1
	print("FORK flicker: pairs in the fork together: same-route %d (order changed more than once: %d; last order = exit order: %d), mixed-route %d (more than once: %d; last = exit: %d)" % [
		pairs[0], multi[0], last_ok[0], pairs[1], multi[1], last_ok[1]])
