extends Node3D

## Where does the AI lose time to the best human lap?
##
## Run after tools/import_recordings.tscn:
##     godot --headless --path . res://tools/analyze_laps.tscn
##     godot --headless --path . res://tools/analyze_laps.tscn -- --track=test_circuit_7_live
##
## For every track with current-handling human flying laps in the library, it
## drives the trained AI alone for a flying lap, records it with the same
## LapRecorder players use, and compares the two section by section:
## time, speed, lateral position, airbrake use and throttle.
##
## This is the tool that found the flat-out technique on circuit 7: the human
## held full throttle through every section and rotated with airbrake taps,
## where the AI lifted to 0.6 throttle and airbraked three times as much.
##
## Reports print to the console and are written to res://recordings_analysis/
## so they can be shared.

const SECTIONS := 16
const OUT_DIR := "res://recordings_analysis/"
const TIME_SCALE := 8.0

var _filter := ""

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--track="):
			_filter = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	
	var targets := _best_human_laps()
	if targets.is_empty():
		print("No current-handling human flying laps in %s. Run tools/import_recordings.tscn first." %
				RecordingStore.LIBRARY_ROOT)
		get_tree().quit()
		return
	for key in targets.keys():
		await _analyze(targets[key])
	get_tree().quit()

## Best human flying lap per track/ship, current handling only, any mode.
func _best_human_laps() -> Dictionary:
	var current := RecordingStore.current_profile_hashes()
	var best := {}
	for f in RecordingStore.all_files(RecordingStore.LIBRARY_ROOT):
		var rel := f.trim_prefix(RecordingStore.LIBRARY_ROOT).split("/")
		if rel.size() < 7 or rel[4] != "flying":
			continue
		if not _filter.is_empty() and rel[0] != _filter:
			continue
		if current.get(rel[1], "") != rel[2]:
			continue
		var t := float(rel[6].get_slice("_", 0)) / 1000.0
		var key := rel[0] + "|" + rel[1]
		if not best.has(key) or t < best[key].time:
			best[key] = {"time": t, "path": f, "track": rel[0], "ship": rel[1]}
	return best

# ============================================================================
# DRIVE THE AI
# ============================================================================

func _analyze(target: Dictionary) -> void:
	var human := ResourceLoader.load(target.path, "", ResourceLoader.CACHE_MODE_IGNORE) as LapRecording
	var scene := load("res://scenes/tracks/%s.tscn" % target.track) as PackedScene
	var profile := _profile_for(target.ship)
	if human == null or scene == null or profile == null:
		print("skip %s / %s: missing lap, track or profile" % [target.track, target.ship])
		return
	
	var track: Node = scene.instantiate()
	add_child(track)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var helper := TrackSplineHelper.new(track)
	
	var ship: ShipController = (load("res://scenes/ships/default_racer.tscn") as PackedScene).instantiate()
	ship.profile = profile
	add_child(ship)
	var grid := _find(track, "StartingGrid")
	if grid and grid.has_method("get_pole_position"):
		ship.global_transform = grid.get_pole_position()
	
	var ai := AIShipController.new()
	ai.ship = ship
	ai.skill_level = 1.0
	ai.avoidance_enabled = false
	add_child(ai)
	ai.initialize(track, null)
	
	var rec := LapRecorder.new()
	rec.ship = ship
	rec.track_root = track
	rec.mode_name = "analysis"
	rec.verbose = false
	add_child(rec)
	
	Engine.time_scale = TIME_SCALE
	Engine.physics_ticks_per_second = int(60 * TIME_SCALE)
	Engine.max_physics_steps_per_frame = 32
	
	var ai_lap := await _drive_flying_lap(ship, rec, helper)
	
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	
	if ai_lap == null:
		print("%s / %s: AI failed to complete a lap" % [target.track, target.ship])
	else:
		_report(target, human, ai_lap, ai.line_source)
	
	rec.queue_free()
	ai.queue_free()
	ship.queue_free()
	track.queue_free()
	await get_tree().physics_frame

## Drive until two full laps are done and return the second -- a flying lap.
## Laps are built here directly rather than through RecordingStore, so the
## analysis never writes the AI's laps into the player's recordings.
func _drive_flying_lap(ship: ShipController, rec: LapRecorder, helper: TrackSplineHelper) -> LapRecording:
	rec._begin_lap()
	var prev := -1.0
	var clock := 0.0
	var lap_start := 0.0
	var crossings := 0
	var dt: float = TIME_SCALE / float(Engine.physics_ticks_per_second)
	while clock < 600.0:
		await get_tree().physics_frame
		clock += dt
		var off := helper.world_to_spline_offset(ship.global_position)
		if prev >= 0.0 and off < prev - 0.5:
			crossings += 1
			var lap: LapRecording = rec._rec
			lap.lap_time = clock - lap_start
			lap.lap_number = crossings
			lap.coverage = rec._coverage()
			rec._begin_lap()
			lap_start = clock
			# crossing 1 ends the partial run up from the grid, crossing 2 ends
			# the standing lap, crossing 3 ends the first flying lap.
			if crossings >= 3 and lap.coverage >= rec.min_coverage:
				rec._active = false
				return lap
		prev = off
	return null

# ============================================================================
# REPORT
# ============================================================================

func _report(target: Dictionary, human: LapRecording, ai_lap: LapRecording, source: String) -> void:
	var h := _sections(human)
	var a := _sections(ai_lap)
	var lines: Array[String] = []
	lines.append("=== %s / %s ===" % [target.track, target.ship])
	lines.append("human %.3fs (%s, tester %s)   AI %.3fs (%s)   gap %+.3fs" % [
		human.lap_time, human.mode, human.tester_id, ai_lap.lap_time, source,
		ai_lap.lap_time - human.lap_time])
	lines.append("")
	lines.append("technique      full throttle   airbrake   mean speed")
	lines.append("  human        %5.0f%%         %5.0f%%     %6.1f" % [
		_frac(human.throttle, 0.98) * 100.0, _ab(human) * 100.0, _mean(human.speed)])
	lines.append("  AI           %5.0f%%         %5.0f%%     %6.1f" % [
		_frac(ai_lap.throttle, 0.98) * 100.0, _ab(ai_lap) * 100.0, _mean(ai_lap.speed)])
	lines.append("")
	lines.append("sec  track   human    AI   AI-human | speed h/AI    | lateral h/AI  | airbrake h/AI | throttle h/AI")
	var gains := []
	for i in range(SECTIONS):
		var d: float = a[i].time - h[i].time
		gains.append({"i": i, "d": d})
		lines.append("%2d   %3.0f%%  %6.2f %6.2f  %+6.2f  | %5.1f %5.1f  | %+5.1f %+5.1f | %4.0f%% %4.0f%%  | %.2f %.2f" % [
			i, float(i) / SECTIONS * 100.0, h[i].time, a[i].time, d,
			h[i].speed, a[i].speed, h[i].lat, a[i].lat,
			h[i].ab * 100.0, a[i].ab * 100.0, h[i].thr, a[i].thr])
	gains.sort_custom(func(x, y): return x.d > y.d)
	lines.append("")
	var worst: Array[String] = []
	for g in gains.slice(0, 4):
		if g.d > 0.05:
			worst.append("section %d (%+.2fs)" % [g.i, g.d])
	lines.append("AI loses most in: " + (", ".join(worst) if not worst.is_empty() else "nowhere significant"))
	var best: Array[String] = []
	for g in gains.slice(gains.size() - 3, gains.size()):
		if g.d < -0.05:
			best.append("section %d (%+.2fs)" % [g.i, g.d])
	lines.append("AI gains in:       " + (", ".join(best) if not best.is_empty() else "nowhere significant"))
	
	var text := "\n".join(lines)
	print("\n" + text)
	var f := FileAccess.open(OUT_DIR + "%s_%s.txt" % [target.track, target.ship], FileAccess.WRITE)
	if f:
		f.store_string(text + "\n")
		f.close()

## Equal-distance sections by spline offset. Handles the lap starting just
## before the line and finishing just after it.
func _sections(r: LapRecording) -> Array:
	var out := []
	for i in range(SECTIONS):
		out.append({"time": 0.0, "speed": 0.0, "lat": 0.0, "ab": 0.0, "thr": 0.0, "n": 0})
	var n := r.sample_count()
	for k in range(n):
		var off: float = r.spline_offset[k]
		if k < n * 0.1 and off > 0.9:
			off -= 1.0
		if k > n * 0.9 and off < 0.1:
			off += 1.0
		var o: Dictionary = out[clampi(int(off * SECTIONS), 0, SECTIONS - 1)]
		o.time += r.sample_interval
		o.speed += r.speed[k]
		o.lat += r.lateral[k]
		o.ab += 1.0 if (r.airbrake_left[k] > 0.05 or r.airbrake_right[k] > 0.05) else 0.0
		o.thr += r.throttle[k]
		o.n += 1
	for o in out:
		var c: float = maxf(o.n, 1)
		o.speed /= c
		o.lat /= c
		o.ab /= c
		o.thr /= c
	return out

func _frac(a: PackedFloat32Array, threshold: float) -> float:
	var c := 0
	for v in a:
		if v >= threshold:
			c += 1
	return float(c) / maxf(a.size(), 1)

func _ab(r: LapRecording) -> float:
	var c := 0
	for k in range(r.sample_count()):
		if r.airbrake_left[k] > 0.05 or r.airbrake_right[k] > 0.05:
			c += 1
	return float(c) / maxf(r.sample_count(), 1)

func _mean(a: PackedFloat32Array) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s / maxf(a.size(), 1)

func _profile_for(ship_id: String) -> ShipProfile:
	for dir in ["res://resources/ships/", "res://resources/ships/hidden/"]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		for f in d.get_files():
			var clean := f.trim_suffix(".remap")
			if clean.ends_with(".tres"):
				var p := load(dir + clean) as ShipProfile
				if p and p.ship_id == ship_id:
					return p
	return null

func _find(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var r := _find(c, nm)
		if r:
			return r
	return null
