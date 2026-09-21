extends Node3D

## PHASE A: style runner + segmentation report.
##
## Runs a set of driving STYLES (different lookahead, airbrake commitment,
## brake aggression, line confidence) around one circuit, times each one per
## track segment, and reports which style wins where.
##
## The point is to find out whether the styles are meaningfully different at
## all before building the splicing machinery on top of them. If every style
## wins roughly the same segments, or if one style dominates everywhere,
## there is nothing to assemble and this approach should be abandoned in
## favour of straight hill-climbing.
##
## SEGMENTATION
## ---------------------------------------------------------------------------
## Segment boundaries are placed where the SPEED VARIANCE ACROSS STYLES IS
## LOWEST, not at hand-labelled features like "the hairpin".
##
## Why: segment times do not simply add up. Racing is a coupled problem -- the
## fastest way through a corner depends on the speed you arrive at, and the
## fastest way down the preceding straight depends on what the corner demands.
## Splicing style B's straight onto style A's corner hands A an entry speed it
## has never driven. Cutting where all styles agree on speed (typically
## mid-straight, near max) minimises that splice error, because the entry
## state at the boundary is nearly identical whichever style produced it.

const TRACKS: Array[String] = [
	"res://scenes/tracks/test_circuit_3_live.tscn",
	"res://scenes/tracks/test_circuit_5_live.tscn",
	"res://scenes/tracks/test_circuit_6_live.tscn",
	"res://scenes/tracks/test_circuit_7_live.tscn",
]
## Every ship gets its own search: the fastest technique for one ship is not
## the fastest for another, and a class with more top speed shifts where the
## time is won.
const SHIP_PROFILES: Array[String] = [
	"res://resources/ships/default_racer.tres",
	"res://resources/ships/fast_racer.tres",
]
const SHIP_SCENE := "res://scenes/ships/default_racer.tscn"

const TIME_SCALE := 8.0
const WARMUP_SECONDS := 6.0
const LAP_TIMEOUT := 200.0

## Target number of segments. Boundaries are chosen greedily from the
## lowest-variance samples, with a minimum spacing so we do not get a cluster
## of cuts inside one long straight.
const TARGET_SEGMENTS := 14
const MIN_SEGMENT_METERS := 150.0

## Styles. `line` keys force a re-bake; everything else is applied to the
## live controller, so most styles cost one lap and nothing else.
const STYLES: Array[Dictionary] = [
	{"name": "baseline"},
	{"name": "brake_late", "look_min": 12.0, "look_max": 28.0, "brake": 1.0, "confidence": 1.10},
	{"name": "flow", "look_min": 26.0, "look_max": 58.0, "airbrake": 0.35, "coast": 2.0},
	{"name": "airbrake_max", "airbrake": 1.0, "reserve": 0.60},
	{"name": "no_airbrake", "airbrake": 0.0, "reserve": 1.0},
	{"name": "conservative", "confidence": 0.88, "brake": 0.8, "coast": 6.0},
	{"name": "confident", "confidence": 1.12},
	{"name": "very_confident", "confidence": 1.20},
	{"name": "short_look", "look_min": 12.0, "look_max": 30.0},
	{"name": "sharp_steer", "sensitivity": 10.0, "feedforward": 1.2},
	{"name": "smooth_steer", "sensitivity": 4.0, "feedforward": 0.9},
	# Added after round 1: no_airbrake won outright, so explore around it.
	{"name": "ab_last_resort", "airbrake": 0.5, "reserve": 0.97},
	{"name": "no_ab_conserv", "airbrake": 0.0, "reserve": 1.0, "confidence": 0.88},
	{"name": "no_ab_confident", "airbrake": 0.0, "reserve": 1.0, "confidence": 1.10},
	{"name": "no_ab_smooth", "airbrake": 0.0, "reserve": 1.0, "sensitivity": 4.0},
]

## LINE GEOMETRY variants. `apex` shifts the solved line along the track (late
## apex trades entry speed for exit speed), `bias` pulls it toward the
## centreline, `min_curv: false` falls back to the shortest-path elastic band.
##
## OFF BY DEFAULT -- measured on circuit 3 and it costs lap time.
## Every geometry variant is substantially slower as a whole lap than the
## min-curvature line (apex_late 58.12s, shortest_path 56.45s, apex_early
## 54.40s, centre_safe 52.95s against 51.45s), and although they do win
## individual segments on paper, splicing them in produced 51.27s against
## 50.93s for assembling control styles alone. The disruption at a geometry
## boundary costs more than the better local shape gains.
##
## Kept and working because they are the right basis for AI VARIANCE later:
## distinct, drivable, measurably different lines for different opponents.
## Set USE_GEOMETRY_VARIANTS to true to search over them.
const USE_GEOMETRY_VARIANTS := false

const GEOMETRY_STYLES: Array[Dictionary] = [
	{"name": "apex_late", "apex": 18.0},
	{"name": "apex_early", "apex": -18.0},
	{"name": "apex_late_conf", "apex": 18.0, "confidence": 1.10},
	{"name": "apex_early_conf", "apex": -18.0, "confidence": 1.10},
	{"name": "centre_safe", "bias": 0.35, "confidence": 1.10},
	{"name": "shortest_path", "min_curv": false, "confidence": 1.10},
]

var _styles: Array[Dictionary] = []

var _ship: ShipController
var _ai: AIShipController
var _helper: TrackSplineHelper
var _profile: ShipProfile
var _track: Node
var _start_transform: Transform3D
var _sample_count: int = 0
var _track_length: float = 0.0

## style index -> per-sample arrival time and speed
var _times: Array[PackedFloat32Array] = []
var _speeds: Array[PackedFloat32Array] = []
var _lap_times: PackedFloat32Array = PackedFloat32Array()
var _line_cache: Dictionary = {}
var _theoretical: float = 0.0

func _ready() -> void:
	for profile_path in SHIP_PROFILES:
		for track_path in TRACKS:
			await _run_track(track_path, profile_path)
	get_tree().quit()

func _reset_state() -> void:
	_times = []
	_speeds = []
	_lap_times = PackedFloat32Array()
	_line_cache = {}

func _run_track(track_path: String, profile_path: String) -> void:
	_reset_state()
	_styles = STYLES.duplicate()
	if USE_GEOMETRY_VARIANTS:
		_styles.append_array(GEOMETRY_STYLES)
	_track = (load(track_path) as PackedScene).instantiate()
	add_child(_track)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_helper = TrackSplineHelper.new(_track)
	_profile = load(profile_path)
	print_rich("\n[b]=== %s / %s ===[/b] %d styles" % [
		AILineTrainer.track_id_for(_track), _profile.ship_id, _styles.size()])

	var ship_scene: PackedScene = _profile.ship_scene if _profile.ship_scene else load(SHIP_SCENE)
	_ship = ship_scene.instantiate()
	add_child(_ship)
	var grid := _find(_track, "StartingGrid")
	if grid and grid.has_method("get_pole_position"):
		_ship.global_transform = grid.get_pole_position()
	_ship.ai_controlled = true
	_start_transform = _ship.global_transform

	_ai = AIShipController.new()
	_ai.ship = _ship
	_ai.skill_level = 1.0
	_ai.avoidance_enabled = false
	add_child(_ai)
	_ai.initialize(_track, null, _bake_for({}))
	if not _ai.is_initialized:
		push_error("AI failed to initialize")
		_track.queue_free()
		return

	_sample_count = _ai.baked_line.sample_count
	_track_length = _ai.baked_line.track_length

	Engine.time_scale = TIME_SCALE
	Engine.physics_ticks_per_second = int(round(60.0 * TIME_SCALE))
	Engine.max_physics_steps_per_frame = 32

	for i in range(_styles.size()):
		var style: Dictionary = _styles[i]
		_apply_style(style)
		var result: Dictionary = await _drive_lap()
		_times.append(result.times)
		_speeds.append(result.speeds)
		_lap_times.append(result.lap_time)
		print("  %-16s lap %7.2fs%s" % [style.name, result.lap_time,
			"  (FAILED)" if result.lap_time < 0.0 else ""])

	_report()
	await _assemble_and_measure()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	_ai.queue_free()
	_ship.queue_free()
	_track.queue_free()
	await get_tree().physics_frame

# ============================================================================
# SETUP
# ============================================================================

## Bake keyed on every parameter that changes the LINE, so geometry variants
## get their own solve instead of silently sharing one.
func _bake_for(style: Dictionary) -> BakedRacingLine:
	var confidence: float = style.get("confidence", 1.0)
	var apex: float = style.get("apex", 0.0)
	var bias: float = style.get("bias", 0.0)
	var min_curv: bool = style.get("min_curv", true)
	var key := "c%.3f_a%.1f_b%.2f_m%s" % [confidence, apex, bias, min_curv]
	if _line_cache.has(key):
		return _line_cache[key]
	var baker := AIRacingLineBaker.new()
	baker.use_cache = false
	baker.cornering_confidence = confidence
	baker.apex_shift_meters = apex
	baker.centre_bias = bias
	baker.use_min_curvature = min_curv
	var line: BakedRacingLine = baker.bake(_helper, _profile,
			get_viewport().find_world_3d(), "stylesearch_" + key)
	_line_cache[key] = line
	return line

func _apply_style(style: Dictionary) -> void:
	var follower := _ai.line_follower
	var decider := _ai.control_decider

	# Re-bake only when the style changes the LINE, not the controller.
	var line := _bake_for(style)
	follower.baked_line = line

	follower.baked_steer_lookahead_min = style.get("look_min", 18.0)
	follower.baked_steer_lookahead_max = style.get("look_max", 42.0)

	decider.max_corner_airbrake = style.get("airbrake", 0.9)
	decider.corner_steer_reserve = style.get("reserve", 0.80)
	decider.max_brake_application = style.get("brake", 0.95)
	decider.coast_band = style.get("coast", 4.0)
	decider.steering_sensitivity = style.get("sensitivity", 6.5)
	decider.steer_feedforward_gain = style.get("feedforward", 1.0)
	if decider.perf_model:
		decider.perf_model.corner_airbrake_application = decider.max_corner_airbrake

# ============================================================================
# DRIVING
# ============================================================================

func _drive_lap() -> Dictionary:
	_ship.global_transform = _start_transform
	_ship.velocity = Vector3.ZERO
	if _ship.has_method("settle_on_surface"):
		_ship.settle_on_surface()
	if _ai.has_method("reset"):
		_ai.reset()

	var times := PackedFloat32Array()
	var speeds := PackedFloat32Array()
	times.resize(_sample_count)
	speeds.resize(_sample_count)
	for i in range(_sample_count):
		times[i] = -1.0
		speeds[i] = 0.0

	var elapsed := 0.0
	var armed := false
	var recording := false
	var lap_start := 0.0
	var prev_offset := -1.0
	var prev_idx := -1
	var prev_time := 0.0
	var dt: float = TIME_SCALE / float(Engine.physics_ticks_per_second)

	while elapsed < LAP_TIMEOUT:
		await get_tree().physics_frame
		elapsed += dt
		var offset: float = _helper.world_to_spline_offset(_ship.global_position)
		var wrapped: bool = prev_offset >= 0.0 and offset < prev_offset - 0.5

		if not armed:
			if elapsed >= WARMUP_SECONDS:
				armed = true
				prev_offset = offset
			continue
		if not recording:
			if wrapped:
				recording = true
				lap_start = elapsed
			prev_offset = offset
			continue

		var idx: int = wrapi(int(offset * float(_sample_count)), 0, _sample_count)
		var now: float = elapsed - lap_start
		var speed: float = _ship.velocity.length()
		# Fill every sample between the last frame and this one. At 120 u/s
		# with a 3m sample spacing the ship crosses ~0.7 samples per frame,
		# but on the fast sections it skips some -- and those are exactly the
		# low-variance samples the segmenter wants to cut at, so leaving them
		# unset made every segment lookup fail.
		if prev_idx >= 0:
			var gap: int = wrapi(idx - prev_idx, 0, _sample_count)
			if gap > 0 and gap < _sample_count / 2:
				for k in range(1, gap + 1):
					var j: int = wrapi(prev_idx + k, 0, _sample_count)
					if times[j] < 0.0:
						times[j] = lerpf(prev_time, now, float(k) / float(gap))
						speeds[j] = speed
		elif times[idx] < 0.0:
			times[idx] = now
			speeds[idx] = speed
		prev_idx = idx
		prev_time = now

		if wrapped:
			return {"times": times, "speeds": speeds, "lap_time": elapsed - lap_start}
		prev_offset = offset

	return {"times": times, "speeds": speeds, "lap_time": -1.0}

## Same style twice. If these differ, every style needs repeat runs and the
## compute budget for this whole approach multiplies.
func _determinism_check() -> void:
	_apply_style(_styles[0])
	var a: Dictionary = await _drive_lap()
	_apply_style(_styles[0])
	var b: Dictionary = await _drive_lap()
	var delta: float = absf(a.lap_time - b.lap_time)
	print("  determinism: %.3fs vs %.3fs (delta %.4fs) -> %s" % [
		a.lap_time, b.lap_time, delta,
		"DETERMINISTIC" if delta < 0.02 else "NON-DETERMINISTIC, styles need repeats"])

# ============================================================================
# SEGMENTATION + REPORT
# ============================================================================

## Cut points where the styles agree most on speed.
func _find_boundaries() -> PackedInt32Array:
	var n := _sample_count
	var variance := PackedFloat32Array()
	variance.resize(n)

	for i in range(n):
		var sum := 0.0
		var count := 0
		for s in range(_speeds.size()):
			if _lap_times[s] > 0.0:
				sum += _speeds[s][i]
				count += 1
		if count < 2:
			variance[i] = INF
			continue
		var mean: float = sum / count
		var acc := 0.0
		for s in range(_speeds.size()):
			if _lap_times[s] > 0.0:
				var d: float = _speeds[s][i] - mean
				acc += d * d
		variance[i] = acc / count

	# Greedy: repeatedly take the lowest-variance sample that is far enough
	# from every boundary already chosen.
	var order: Array[int] = []
	for i in range(n):
		order.append(i)
	order.sort_custom(func(a, b): return variance[a] < variance[b])

	var ds: float = _track_length / float(n)
	var min_gap: int = maxi(2, int(MIN_SEGMENT_METERS / maxf(ds, 0.01)))
	var chosen: Array[int] = []
	for idx in order:
		if chosen.size() >= TARGET_SEGMENTS:
			break
		if is_inf(variance[idx]):
			continue
		var ok := true
		for c in chosen:
			var gap: int = mini(absi(idx - c), n - absi(idx - c))
			if gap < min_gap:
				ok = false
				break
		if ok:
			chosen.append(idx)
	chosen.sort()

	var out := PackedInt32Array()
	for c in chosen:
		out.append(c)
	return out

func _report() -> void:
	var valid := 0
	for t in _lap_times:
		if t > 0.0:
			valid += 1
	if valid < 2:
		print("not enough valid laps to segment")
		return

	var bounds := _find_boundaries()
	print_rich("\n[b]Segments[/b] (%d boundaries, cut where styles agree on speed)" % bounds.size())

	var ds: float = _track_length / float(_sample_count)
	var best_total := 0.0
	var winners: Dictionary = {}

	for b in range(bounds.size()):
		var start: int = bounds[b]
		var end: int = bounds[(b + 1) % bounds.size()]
		var seg_len: float = _segment_length(start, end) * ds

		var best_style := -1
		var best_time := INF
		var baseline_time := _segment_time(0, start, end)
		for s in range(_styles.size()):
			if _lap_times[s] <= 0.0:
				continue
			var t: float = _segment_time(s, start, end)
			if t > 0.0 and t < best_time:
				best_time = t
				best_style = s
		if best_style < 0:
			continue
		best_total += best_time
		var name: String = _styles[best_style].name
		winners[name] = winners.get(name, 0) + 1
		var gain: float = baseline_time - best_time
		print("  seg %2d  %6.0fm  %-16s %6.3fs  (baseline %6.3fs, %+.3fs)" % [
			b, seg_len, name, best_time, baseline_time, -gain])

	print_rich("\n[b]Summary[/b]")
	var order: Array[int] = []
	for i in range(_styles.size()):
		order.append(i)
	order.sort_custom(func(a, b): 
		var ta: float = _lap_times[a] if _lap_times[a] > 0.0 else INF
		var tb: float = _lap_times[b] if _lap_times[b] > 0.0 else INF
		return ta < tb)
	for i in order:
		if _lap_times[i] > 0.0:
			print("  %-16s %7.3fs" % [_styles[i].name, _lap_times[i]])
	print("  segment winners: %s" % [str(winners)])
	_theoretical = best_total
	print("  theoretical spliced lap: %.3fs (best single style %.3fs)" % [
		best_total, _lap_times[order[0]]])
	print("  NOTE: spliced total is optimistic -- it ignores that each style's")
	print("  segment was driven from ITS OWN entry speed, not the spliced one.")

# ============================================================================
# ASSEMBLY
# ============================================================================

## Meters over which style gains are blended at a segment boundary. Hard
## switches would step the controller's parameters mid-corner.
const BOUNDARY_BLEND_METERS := 40.0

## Crossfade distance for spliced LINE GEOMETRY, meters.
const GEOMETRY_BLEND_METERS := 60.0

## A segment only adopts a different style if it beats the OVERALL best
## single style there by this much.
##
## Measured on circuit 3: unconstrained splicing (take the winner of every
## segment) produced 52.03s against 51.45s for simply running the best single
## style everywhere, and against a theoretical 50.80s. The theory was
## optimistic by 1.23s and the splice actively lost 0.58s. Every boundary is
## a chance for a style to inherit an entry speed it has never driven, so
## each swap must pay for that risk rather than just edging ahead on paper.
const MIN_SEGMENT_GAIN := 0.08

func _assemble_and_measure() -> void:
	var bounds := _find_boundaries()
	if bounds.size() < 2:
		return
	
	var n := _sample_count
	var base: BakedRacingLine = _bake_for({})
	var line: BakedRacingLine = base.duplicate(true)
	
	var airbrake := PackedFloat32Array()
	var reserve := PackedFloat32Array()
	var lookahead := PackedFloat32Array()
	var sensitivity := PackedFloat32Array()
	var speeds := PackedFloat32Array()
	for arr in [airbrake, reserve, lookahead, sensitivity, speeds]:
		arr.resize(n)
	
	var log := PackedStringArray()
	var laterals := PackedFloat32Array()
	laterals.resize(n)
	var seg_of := PackedInt32Array()
	seg_of.resize(n)
	var conf_of := PackedFloat32Array()
	conf_of.resize(n)
	
	# Anchor on the best single style: that is a lap we have actually driven
	# end to end, so it carries no splice risk at all.
	var anchor := _best_overall_style()
	var swaps := 0
	
	for b in range(bounds.size()):
		var start: int = bounds[b]
		var end: int = bounds[(b + 1) % bounds.size()]
		var winner := _best_style_for(start, end)
		var anchor_time := _segment_time(anchor, start, end)
		var winner_time: float = _segment_time(winner, start, end) if winner >= 0 else INF
		if winner < 0 or anchor_time <= 0.0 or winner_time > anchor_time - MIN_SEGMENT_GAIN:
			winner = anchor
		elif winner != anchor:
			swaps += 1
		var style: Dictionary = _styles[winner]
		var style_line: BakedRacingLine = _bake_for(style)
		log.append("seg%d=%s" % [b, style.name])
		
		var count := _segment_length(start, end)
		for k in range(count):
			var i: int = wrapi(start + k, 0, n)
			airbrake[i] = style.get("airbrake", 0.9)
			reserve[i] = style.get("reserve", 0.80)
			lookahead[i] = style.get("look_max", 42.0)
			sensitivity[i] = style.get("sensitivity", 6.5)
			speeds[i] = style_line.target_speeds[i]
			laterals[i] = style_line.lateral_offsets[i]
			seg_of[i] = winner
			conf_of[i] = style.get("confidence", 1.0)
	
	var ds: float = _track_length / float(n)
	var blend: int = maxi(1, int(BOUNDARY_BLEND_METERS / maxf(ds, 0.01)))
	# Geometry needs a far longer crossfade than the control gains. A step in
	# lateral position is not drivable at all, and an abrupt change in lateral
	# RATE is a curvature spike that the speed profile will brake for.
	var geo_blend: int = maxi(2, int(GEOMETRY_BLEND_METERS / maxf(ds, 0.01)))
	_crossfade_geometry(laterals, seg_of, bounds, geo_blend)
	_box_smooth(airbrake, blend)
	_box_smooth(reserve, blend)
	_box_smooth(lookahead, blend)
	_box_smooth(sensitivity, blend)
	# Speeds are deliberately NOT smoothed: the anchor profile is already
	# feasible, and blurring it would change every segment rather than just
	# the swapped ones. The feasibility passes below reconcile the seams.
	
	# The spliced speed profile must still be something the ship can brake
	# into and accelerate out of -- segment winners were chosen independently
	# and know nothing about each other's entry speeds.
	var perf := ShipPerformanceModel.new(_profile)
	var seg_lengths := PackedFloat32Array()
	seg_lengths.resize(n)
	for i in range(n):
		seg_lengths[i] = ds
	var geometry_spliced := false
	for i in range(n):
		if _styles[seg_of[i]].has("apex") or _styles[seg_of[i]].has("bias") \
				or _styles[seg_of[i]].has("min_curv"):
			geometry_spliced = true
			break
	
	var rebuilt: BakedRacingLine = null
	if not geometry_spliced:
		# No geometry variation in play: keep the anchor's solved line exactly
		# as it was rather than round-tripping it through a rebuild.
		for i in range(n):
			laterals[i] = base.lateral_offsets[i]
	else:
		rebuilt = _rebuild_geometry(laterals, base, anchor)
		if rebuilt != null:
			line = rebuilt
			speeds = rebuilt.target_speeds.duplicate()
			var anchor_conf: float = _styles[anchor].get("confidence", 1.0)
			var cap: float = perf_cap()
			for i in range(n):
				speeds[i] = minf(speeds[i] * conf_of[i] / maxf(anchor_conf, 0.01), cap)

	# Re-running the feasibility passes here uses uniform segment lengths
	# where the baker used measured ones, which perturbs the profile slightly
	# -- measured as a 0.1s loss on circuit 6 with zero segments swapped.
	if swaps > 0 or rebuilt != null:
		speeds = AIRacingLineBaker.apply_feasibility_passes(speeds, seg_lengths, perf)
	
	line.target_speeds = speeds
	line.style_airbrake = airbrake
	line.style_reserve = reserve
	line.style_lookahead = lookahead
	line.style_sensitivity = sensitivity
	line.style_log = log
	line.track_id = AILineTrainer.track_id_for(_track)
	line.ship_id = _profile.ship_id
	
	# Measure it. Reset the live controller params to defaults FIRST -- this
	# call also reassigns follower.baked_line, which would otherwise throw
	# away the assembled line we just built and drive the plain bake instead.
	_apply_style({"name": "assembled"})
	_ai.baked_line = line
	_ai.line_follower.baked_line = line
	var result: Dictionary = await _drive_lap()
	
	var best_single := INF
	for t in _lap_times:
		if t > 0.0:
			best_single = minf(best_single, t)
	
	print("  anchored on %s, %d of %d segments swapped" % [
		_styles[anchor].name, swaps, bounds.size()])
	print_rich("[b]  assembled: %.3fs[/b]  (best single style %.3fs, theoretical splice %.3fs)" % [
		result.lap_time, best_single, _theoretical])
	if result.lap_time > 0.0 and result.lap_time < best_single:
		# Stamp provenance so the in-game spectator can say what this line
		# measured. v15 omitted this, so assembled lines reported 0.000s.
		line.is_trained = true
		line.trained_lap_time = result.lap_time
		var err := AILineTrainer.save_trained_line(line)
		print("  saved assembled line%s" % ["" if err == OK else " FAILED"])
	else:
		# The splice lost. Do NOT fall back to nothing -- with no saved line
		# the AI bakes a default at runtime and drives with default controller
		# params, which is far slower than the anchor style we just measured.
		# Save the anchor as a UNIFORM strategy instead: its own line, its own
		# gains everywhere, zero splice risk, and a lap time we have driven.
		print("  splice did not beat the best single style, as warned")
		await _save_uniform_anchor(anchor, best_single)

func perf_cap() -> float:
	var p := ShipPerformanceModel.new(_profile)
	return p.top_speed(true)

## Crossfade spliced geometry at boundaries where the STYLE actually changes.
##
## The first version blended each sample toward a straight chord joining the
## two sides of every boundary. With 14 boundaries and a 120m window that
## flattened roughly half the track's apexes toward chords, and the assembled
## lap came out at 63.95s against 51.45s for the best single style. This
## instead interpolates between the two source geometries evaluated at the
## same sample, so the line is always a genuine blend of two solved lines and
## is never flattened.
func _crossfade_geometry(a: PackedFloat32Array, style_of: PackedInt32Array,
		bounds: PackedInt32Array, half: int) -> void:
	var n := a.size()
	for b in bounds:
		var before_style: int = style_of[wrapi(b - 1, 0, n)]
		var after_style: int = style_of[wrapi(b, 0, n)]
		if before_style == after_style:
			continue  # nothing changes here, leave the geometry alone
		var line_a: BakedRacingLine = _bake_for(_styles[before_style])
		var line_b: BakedRacingLine = _bake_for(_styles[after_style])
		for k in range(-half, half + 1):
			var i: int = wrapi(b + k, 0, n)
			var t: float = (float(k) + float(half)) / float(half * 2)
			t = t * t * (3.0 - 2.0 * t)  # smoothstep: no kink at the seams
			a[i] = lerpf(line_a.lateral_offsets[i], line_b.lateral_offsets[i], t)

## Save the best single style as a flat, uniform strategy. This is the floor:
## every ship/track pair ends up with something measured, even when splicing
## fails to improve on it.
func _save_uniform_anchor(anchor: int, best_single: float) -> void:
	var style: Dictionary = _styles[anchor]
	var src: BakedRacingLine = _bake_for(style)
	var line: BakedRacingLine = src.duplicate(true)
	var n := line.sample_count
	
	var airbrake := PackedFloat32Array()
	var reserve := PackedFloat32Array()
	var lookahead := PackedFloat32Array()
	var sensitivity := PackedFloat32Array()
	for arr in [airbrake, reserve, lookahead, sensitivity]:
		arr.resize(n)
	for i in range(n):
		airbrake[i] = style.get("airbrake", 0.9)
		reserve[i] = style.get("reserve", 0.80)
		lookahead[i] = style.get("look_max", 42.0)
		sensitivity[i] = style.get("sensitivity", 6.5)
	
	line.style_airbrake = airbrake
	line.style_reserve = reserve
	line.style_lookahead = lookahead
	line.style_sensitivity = sensitivity
	line.style_log = PackedStringArray(["uniform=" + str(style.name)])
	line.track_id = AILineTrainer.track_id_for(_track)
	line.ship_id = _profile.ship_id
	line.is_trained = true
	line.trained_lap_time = best_single
	
	var err := AILineTrainer.save_trained_line(line)
	print("  saved uniform '%s' strategy (%.3fs)%s" % [
		style.name, best_single, "" if err == OK else " FAILED"])

func _best_overall_style() -> int:
	var best := 0
	var best_time := INF
	for s in range(_styles.size()):
		if _lap_times[s] > 0.0 and _lap_times[s] < best_time:
			best_time = _lap_times[s]
			best = s
	return best

func _best_style_for(start: int, end: int) -> int:
	var best := -1
	var best_time := INF
	for s in range(_styles.size()):
		if _lap_times[s] <= 0.0:
			continue
		var t: float = _segment_time(s, start, end)
		if t > 0.0 and t < best_time:
			best_time = t
			best = s
	return best

func _box_smooth(a: PackedFloat32Array, radius: int) -> void:
	var n := a.size()
	if n == 0 or radius < 1:
		return
	var src := a.duplicate()
	for i in range(n):
		var sum := 0.0
		for k in range(-radius, radius + 1):
			sum += src[wrapi(i + k, 0, n)]
		a[i] = sum / float(radius * 2 + 1)

func _segment_time(style: int, start: int, end: int) -> float:
	var t := _times[style]
	if t[start] < 0.0 or t[end] < 0.0:
		return -1.0
	var dt: float = t[end] - t[start]
	if dt < 0.0:
		dt += _lap_times[style]   # wrapped the start/finish line
	return dt

func _segment_length(start: int, end: int) -> int:
	var d: int = end - start
	if d <= 0:
		d += _sample_count
	return d

func _find(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var r := _find(c, nm)
		if r:
			return r
	return null

## Geometry changed, so curvature and the whole speed profile must be
## recomputed: the spliced shape is one no variant actually solved, and its
## curvature belongs to none of them.
func _rebuild_geometry(laterals: PackedFloat32Array,
		base: BakedRacingLine, anchor: int) -> BakedRacingLine:
	var geo_baker := AIRacingLineBaker.new()
	geo_baker.use_cache = false
	geo_baker.cornering_confidence = _styles[anchor].get("confidence", 1.0)
	return geo_baker.rebuild_from_laterals(_helper, _profile, laterals, base)
