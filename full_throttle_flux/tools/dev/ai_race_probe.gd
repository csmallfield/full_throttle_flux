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
##      the zone named PROBE_MAGNET_ZONE), PROBE_SEED (default 1234)

var ships: Array = []
var respawns := {}
var air_in_zone := {}
var zone_ticks := {}
var vmin := {}
var vmax := {}
var laps := {}

func _ready() -> void:
	await get_tree().process_frame
	var root := get_tree().root
	var gm = root.get_node("GameManager")
	var track_id := OS.get_environment("PROBE_TRACK")
	if track_id == "":
		track_id = "loop_lab"
	gm.select_track_by_id(track_id)
	gm.selected_mode = "race"
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
	
	rm.ship_lap_completed.connect(func(s, n, _t): laps[s] = n)
	for s in ships:
		respawns[s] = 0
		air_in_zone[s] = 0
		zone_ticks[s] = 0
		vmin[s] = INF
		vmax[s] = 0.0
		laps[s] = 0
		s.ship_respawned.connect(func(): respawns[s] += 1)
	
	# The player ship gets no input and sits on the grid; the AI field races.
	var frames := int(seconds * 60.0)
	for f in frames:
		await get_tree().physics_frame
		for s in ships:
			var v: float = s.velocity.length()
			vmin[s] = minf(vmin[s], v)
			vmax[s] = maxf(vmax[s], v)
			if s.magnet_weight > 0.5:
				zone_ticks[s] += 1
				if not s.is_grounded:
					air_in_zone[s] += 1
	
	var h := []
	for s in ships:
		var t: Transform3D = s.global_transform
		h.append([t.origin, t.basis.x, t.basis.y, s.velocity])
		print("PROBE %-22s ai=%s laps=%d v[%.0f..%.0f] respawns=%d zone_ticks=%d air_in_zone=%d pos=%s" % [
			s.name, str(s.ai_controlled), laps[s], vmin[s] if vmin[s] < INF else 0.0, vmax[s],
			respawns[s], zone_ticks[s], air_in_zone[s], t.origin.snapped(Vector3.ONE * 0.1)])
	print("PROBE track=%s seconds=%.0f ships=%d checksum=%d" % [track_id, seconds, ships.size(), str(h).hash()])
	get_tree().quit(0)

func _find_ships(n: Node) -> Array:
	var out: Array = []
	if n is ShipController:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_ships(c))
	return out
