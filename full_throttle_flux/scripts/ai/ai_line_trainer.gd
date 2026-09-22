class_name AILineTrainer
extends Node

## Measures what the ship can ACTUALLY carry through every corner, by driving
## the real ShipController against a baked line and iterating the speed
## profile where it runs wide or leaves margin.
##
## WHY THIS EXISTS
## ---------------------------------------------------------------------------
## Corner speeds were coming from ShipPerformanceModel.corner_speed(), which
## solves v * kappa = yaw_rate(v) analytically. That model is necessarily
## approximate: it ignores the speed cost of scrub while sliding, the
## controller's own tracking error, hover and track-normal transitions, and
## how much of a corner the ship spends off its planned line. The gap was
## being papered over with a single global `cornering_confidence` multiplier,
## which has to be simultaneously right for every corner on every track --
## and at 1.05 it was already above 1.0, i.e. openly compensating for the
## model being wrong rather than describing anything.
##
## The trainer replaces that one number with a measurement per sample.
##
## HOW IT WORKS
## ---------------------------------------------------------------------------
## Each iteration drives a lap and records, per line sample, the worst OUTWARD
## tracking error and the speed actually achieved. Then:
##
##   ran wide   -> reduce target speed over the approach to that sample
##                 (the cause of a wide exit is the entry speed, which is
##                  upstream, hence attribution_distance)
##   tracked clean AND hit its target -> raise that sample's target
##
## The edited profile is smoothed and pushed back through the baker's
## feasibility passes, so it stays something the ship can brake into and
## accelerate out of. The best profile BY MEASURED LAP TIME is kept, not the
## last one, because the update can and does overshoot.
##
## SPEED
## ---------------------------------------------------------------------------
## Training runs faster than realtime by raising Engine.time_scale together
## with physics_ticks_per_second, which keeps the per-step delta at its normal
## value while advancing sim time faster. This only works because the v8 time
## normalisation made the handling model tick-rate independent -- before that,
## training at 8x would have produced a profile for a different game.

signal iteration_complete(iteration: int, lap_time: float, changed_fraction: float)
signal training_complete(line: BakedRacingLine, best_lap: float)
signal progress(message: String)

# ============================================================================
# CONFIGURATION
# ============================================================================

## Hard cap on iterations. Convergence usually arrives before this.
var max_iterations: int = 14

## Stop early once fewer than this fraction of samples changed.
var convergence_fraction: float = 0.01

## Stop early after this many iterations without improving the best lap.
var patience: int = 4

## Seconds of driving before recording starts, so the standing start off the
## pole is not attributed to the line.
var warmup_seconds: float = 6.0

## Abort a lap that takes longer than best_lap * this (the ship is stuck or
## has lost the line, and the data would be misleading).
var lap_timeout_factor: float = 2.5

## Absolute ceiling on one lap attempt, seconds of sim time.
var lap_timeout_max: float = 240.0

## Sim time multiplier. Raise for faster training, lower if the machine
## cannot keep up (watch for the physics spiral warning).
var time_scale: float = 8.0

## Meters outside the intended line that counts as running wide.
var wide_threshold: float = 4.0

## Meters within which the ship is considered to have tracked cleanly.
## Measured mean tracking error is ~1.2m, so a 1.2 threshold excluded about
## half of a well-driven lap from ever earning an increase.
var clean_threshold: float = 2.5

## Meters either side of a cleanly-tracked sample that share the increase.
## Raises MUST be applied over a window: a single sample lifted on its own is
## immediately pulled back down by the feasibility passes, because you cannot
## brake into or accelerate out of a one-sample spike. Corner speeds only move
## when the whole corner moves.
var raise_window: float = 30.0

## Deprecated. Gating increases on "did the ship reach its current target"
## deadlocked the search: the analytic profile starts above what the ship can
## actually do, so nothing ever qualified and the trainer could only ratchet
## down. Clean tracking alone now earns an increase.
var speed_reached_fraction: float = 0.97

## A wide sample is only blamed on speed if the ship reached this fraction of
## its target there.
var speed_blame_fraction: float = 0.95

## Multiplicative reduction applied over the approach when the ship runs wide.
var speed_down_step: float = 0.05

## Adaptive step scaling. A worse lap reverts to the best profile and retries
## with a smaller perturbation; a better lap grows it back toward full size.
## This makes lap time the arbiter rather than the heuristic, so the trainer
## can never finish worse than it started.
var step_shrink: float = 0.6
var step_grow: float = 1.25
var min_step_scale: float = 0.15

## Multiplicative increase when a sample is tracked cleanly at target.
var speed_up_step: float = 0.03

## Meters upstream of a wide sample that share the blame for it.
var attribution_distance: float = 60.0

## Floor on any trained corner speed.
var min_speed: float = 15.0

# ============================================================================
# STYLE GAIN TRAINING
# ============================================================================

## Also perturb the per-sample style gains (cornering airbrake and steering
## reserve) the style search produced, not just the speed profile.
##
## The style search adopts gains in segment-sized blocks, chosen from a fixed
## menu of styles. This refines them continuously: where the ship runs wide it
## buys more yaw (more airbrake, less steering reserve), and where it tracks
## clean it saves scrub (less airbrake, more reserve). Measured on circuit 3,
## refining SPEEDS alone found nothing once the assembled strategy was in
## place -- every perturbation was reverted -- so the gains looked like where
## the remaining search space was.
##
## OFF BY DEFAULT: it was measured and it does not work. Seeded from the
## assembled circuit 3 line (50.93s), enabling this made every perturbation
## WORSE than perturbing speeds alone -- 53.02s against 51.33s on the
## equivalent iteration -- and all of them were reverted. The likely reason is
## that the style search already picked gains per segment from measured laps,
## so a blind nudge based on tracking error is a step away from a measured
## optimum rather than toward one.
##
## Kept because it is wired up correctly and cheap to re-test if the gain
## menu or the error attribution changes. Do not enable it expecting a win.
var train_style_gains: bool = false

## Per-iteration change in style_airbrake, absolute.
var airbrake_step: float = 0.06

## Per-iteration change in style_reserve, absolute.
var reserve_step: float = 0.04

## Bounds on the trained gains.
var airbrake_min: float = 0.0
var airbrake_max: float = 1.0
var reserve_min: float = 0.55
var reserve_max: float = 1.0

# ============================================================================
# STATE
# ============================================================================

var _ship: ShipController
var _ai: AIShipController
var _helper: TrackSplineHelper
var _line: BakedRacingLine
var _perf: ShipPerformanceModel
var _start_transform: Transform3D

var _sample_count: int = 0
var _seg_lengths: PackedFloat32Array
var _worst_outward: PackedFloat32Array
var _best_speed: PackedFloat32Array
var _visited: PackedByteArray

var _best_speeds: PackedFloat32Array
var _best_airbrake: PackedFloat32Array
var _best_reserve: PackedFloat32Array
var _best_lap: float = INF
var _running: bool = false

# ============================================================================
# TRAINED LINE STORAGE
# ============================================================================

## Trained lines live in the project, not user://, because they are content:
## they are baked once by a developer and shipped with the game.
const TRAINED_DIR := "res://resources/ai_data/"

## Stable identifier for a track, derived from its SCENE FILE rather than its
## root node name.
##
## Node names are not unique: in this project test_circuit_3_live and
## test_circuit_4_live are both rooted "TestCircuit3", and test_circuit_6_live
## and test_circuit_7_live are both rooted "TestCircuit6" -- copy-paste
## duplicates. Keying anything on the node name makes those pairs collide.
## The bake cache survived it only because its source hash includes the spline
## geometry, which forces a miss; a trained-line FILE has no such protection
## and one track silently overwrites the other.
static func track_id_for(track_root: Node) -> String:
	if track_root == null:
		return ""
	var path: String = track_root.scene_file_path
	if not path.is_empty():
		return path.get_file().get_basename()
	return String(track_root.name)

static func trained_path(track_id: String, ship_id: String) -> String:
	return "%s%s_%s_trained_line.tres" % [TRAINED_DIR, track_id, ship_id]

## Returns the trained line for this track/ship, or null. Safe to call at
## runtime; returns null in an export where the file was never generated.
static func load_trained_line(track_id: String, ship_id: String) -> BakedRacingLine:
	if track_id.is_empty() or ship_id.is_empty():
		return null
	var path := trained_path(track_id, ship_id)
	if not ResourceLoader.exists(path):
		return null
	var line := ResourceLoader.load(path) as BakedRacingLine
	if line == null:
		return null
	if line.bake_version != BakedRacingLine.CURRENT_BAKE_VERSION:
		push_warning("AILineTrainer: %s is bake version %d, expected %d - retrain it" % [
			path, line.bake_version, BakedRacingLine.CURRENT_BAKE_VERSION])
		return null
	return line

static func save_trained_line(line: BakedRacingLine, profile: ShipProfile = null) -> Error:
	if profile != null:
		line.profile_hash = profile.handling_hash()
	if not DirAccess.dir_exists_absolute(TRAINED_DIR):
		DirAccess.make_dir_recursive_absolute(TRAINED_DIR)
	var path := trained_path(line.track_id, line.ship_id)
	return ResourceSaver.save(line, path)

# ============================================================================
# ENTRY POINT
# ============================================================================

## Train `line` in place and return it. Must be awaited.
func train(track_root: Node, ship: ShipController, ai: AIShipController,
		helper: TrackSplineHelper, line: BakedRacingLine,
		perf: ShipPerformanceModel) -> BakedRacingLine:
	_ship = ship
	_ai = ai
	_helper = helper
	_line = line
	_perf = perf
	_start_transform = ship.global_transform
	_sample_count = line.sample_count
	
	if _sample_count < 8 or not helper.is_valid:
		push_warning("AILineTrainer: nothing to train (invalid line or spline)")
		return line
	
	# Uniform segment lengths are accurate enough for the feasibility passes;
	# the baker resamples to near-uniform spacing anyway.
	var ds: float = line.track_length / float(_sample_count)
	_seg_lengths = PackedFloat32Array()
	_seg_lengths.resize(_sample_count)
	for i in range(_sample_count):
		_seg_lengths[i] = ds
	
	_best_speeds = line.target_speeds.duplicate()
	_best_airbrake = line.style_airbrake.duplicate()
	_best_reserve = line.style_reserve.duplicate()
	_best_lap = INF
	
	var prev_scale := Engine.time_scale
	var prev_ticks := Engine.physics_ticks_per_second
	var prev_steps := Engine.max_physics_steps_per_frame
	_apply_time_scale()
	
	var stale := 0
	var step_scale := 1.0
	for iteration in range(max_iterations):
		_reset_accumulators()
		var lap_time: float = await _drive_lap()
		
		var verdict := ""
		if lap_time < 0.0:
			line.target_speeds = _best_speeds.duplicate()
			line.style_airbrake = _best_airbrake.duplicate()
			line.style_reserve = _best_reserve.duplicate()
			step_scale *= step_shrink
			stale += 1
			progress.emit("iteration %d: lap failed, reverted (step %.2f)" % [
				iteration + 1, step_scale])
			if stale >= patience or step_scale < min_step_scale:
				break
			continue
		
		if lap_time < _best_lap - 0.01:
			_best_lap = lap_time
			_best_speeds = line.target_speeds.duplicate()
			_best_airbrake = line.style_airbrake.duplicate()
			_best_reserve = line.style_reserve.duplicate()
			stale = 0
			step_scale = minf(step_scale * step_grow, 1.0)
			verdict = "kept"
		else:
			# Hill climbing with revert: the perturbation made things worse,
			# so go back to the best profile and try a gentler one. Without
			# this the error heuristic ratchets speeds down indefinitely --
			# it assumes running wide means going too fast, which is only
			# sometimes true. Often it is controller lag, and cutting speed
			# there just loses lap time without fixing the line.
			line.target_speeds = _best_speeds.duplicate()
			line.style_airbrake = _best_airbrake.duplicate()
			line.style_reserve = _best_reserve.duplicate()
			step_scale *= step_shrink
			stale += 1
			verdict = "reverted"
		
		var changed: float = _update_speed_profile(step_scale)
		iteration_complete.emit(iteration + 1, lap_time, changed)
		progress.emit("iteration %d: lap %.2fs (best %.2fs) %s, step %.2f, %.1f%% changed" % [
			iteration + 1, lap_time, _best_lap, verdict, step_scale, changed * 100.0])
		
		if changed < convergence_fraction:
			progress.emit("converged after %d iterations" % [iteration + 1])
			break
		if step_scale < min_step_scale:
			progress.emit("step size exhausted after %d iterations" % [iteration + 1])
			break
		if stale >= patience:
			progress.emit("no improvement in %d iterations, stopping" % [patience])
			break
	
	Engine.time_scale = prev_scale
	Engine.physics_ticks_per_second = prev_ticks
	Engine.max_physics_steps_per_frame = prev_steps
	
	# Always finish on the best measured profile, never the last attempt.
	line.target_speeds = _best_speeds.duplicate()
	if _best_airbrake.size() == _sample_count:
		line.style_airbrake = _best_airbrake.duplicate()
		line.style_reserve = _best_reserve.duplicate()
	line.is_trained = true
	line.trained_lap_time = _best_lap
	line.trained_iterations = max_iterations
	
	training_complete.emit(line, _best_lap)
	return line

func _apply_time_scale() -> void:
	var scale: float = maxf(time_scale, 1.0)
	# Raise the tick rate with the time scale so the per-step delta stays at
	# its normal value. Sim time advances `scale` times faster, the physics
	# integrates exactly as it would at 1x.
	Engine.time_scale = scale
	Engine.physics_ticks_per_second = int(round(60.0 * scale))
	Engine.max_physics_steps_per_frame = maxi(8, int(ceil(scale)) * 2)

# ============================================================================
# DRIVING A LAP
# ============================================================================

func _reset_accumulators() -> void:
	_worst_outward = PackedFloat32Array()
	_worst_outward.resize(_sample_count)
	_best_speed = PackedFloat32Array()
	_best_speed.resize(_sample_count)
	_visited = PackedByteArray()
	_visited.resize(_sample_count)
	for i in range(_sample_count):
		_worst_outward[i] = -INF
		_best_speed[i] = 0.0
		_visited[i] = 0

## Returns lap time in seconds, or -1.0 if the lap failed.
func _drive_lap() -> float:
	_ship.global_transform = _start_transform
	_ship.velocity = Vector3.ZERO
	if _ship.has_method("settle_on_surface"):
		_ship.settle_on_surface()
	if _ai and _ai.has_method("reset"):
		_ai.reset()
	
	var elapsed: float = 0.0
	var armed := false        # past warmup, waiting for the line
	var recording := false    # timing a full lap
	var lap_start: float = 0.0
	var prev_offset: float = -1.0
	var timeout: float = lap_timeout_max
	if _best_lap < INF:
		timeout = minf(lap_timeout_max, _best_lap * lap_timeout_factor)
	
	while true:
		await get_tree().physics_frame
		var delta: float = get_tree().root.get_process_delta_time()
		# physics_frame delta comes from the physics step, which we have
		# scaled; use the engine's own value so sim time is counted correctly.
		delta = 1.0 / float(Engine.physics_ticks_per_second) * Engine.time_scale
		elapsed += delta
		
		if elapsed > timeout:
			return -1.0
		
		var offset: float = _helper.world_to_spline_offset(_ship.global_position)
		
		var wrapped: bool = prev_offset >= 0.0 and offset < prev_offset - 0.5
		
		if not armed:
			if elapsed >= warmup_seconds:
				armed = true
				prev_offset = offset
			continue
		
		if not recording:
			# Wait for the start/finish line so we time a WHOLE lap. Timing
			# from wherever the ship happened to be at the end of warmup
			# measured ~99% of a lap and flattered every result.
			if wrapped:
				recording = true
				lap_start = elapsed
			prev_offset = offset
			continue
		
		_record(offset)
		
		if wrapped:
			return elapsed - lap_start
		prev_offset = offset
	
	return -1.0

func _record(offset: float) -> void:
	var idx: int = wrapi(int(offset * float(_sample_count)), 0, _sample_count)
	
	var desired: float = _line.get_lateral_at(offset)
	var actual: float = _helper.calculate_lateral_offset(_ship.global_position, offset, true)
	
	# Outward = away from the turn centre. Curvature sign tells us which side
	# that is: positive curvature turns left, so drifting wide means drifting
	# toward positive lateral.
	var kappa_sign: float = 1.0
	if _ai and _ai.line_follower and _ai.line_follower.has_method("signed_line_curvature"):
		var k: float = _ai.line_follower.signed_line_curvature(offset)
		if absf(k) > 0.0001:
			kappa_sign = signf(k)
	var outward: float = (actual - desired) * kappa_sign
	
	_worst_outward[idx] = maxf(_worst_outward[idx], outward)
	_best_speed[idx] = maxf(_best_speed[idx], _ship.velocity.length())
	_visited[idx] = 1

# ============================================================================
# PROFILE UPDATE
# ============================================================================

## Returns the fraction of samples whose target speed changed.
func _update_speed_profile(step_scale: float = 1.0) -> float:
	var speeds: PackedFloat32Array = _line.target_speeds.duplicate()
	var before: PackedFloat32Array = speeds.duplicate()
	var cap: float = _perf.top_speed(true)
	
	var ds: float = _line.track_length / float(_sample_count)
	var window: int = maxi(1, int(round(attribution_distance / maxf(ds, 0.01))))
	
	# Build a multiplier per sample rather than editing speeds in place.
	# Applying the reduction directly inside the attribution loop compounded:
	# a run of 20 wide samples each knocked 6% off 20 overlapping windows, so
	# the same stretch could lose 70% of its target speed in one iteration.
	var adjust := PackedFloat32Array()
	adjust.resize(_sample_count)
	for i in range(_sample_count):
		adjust[i] = 1.0
	
	for i in range(_sample_count):
		if _visited[i] == 0 or _worst_outward[i] == -INF:
			continue
		if _worst_outward[i] <= wide_threshold:
			continue
		# Only blame SPEED when the ship was actually at speed here. Running
		# wide while below target is a tracking failure, not an over-speed,
		# and slowing the approach would cost lap time without fixing it.
		if _best_speed[i] < before[i] * speed_blame_fraction:
			continue
		# Ran wide here. The cause is the speed carried INTO this sample, so
		# blame the approach rather than the apex. Worst case wins; the
		# reduction is never applied twice to the same sample.
		for w in range(window):
			var j: int = wrapi(i - w, 0, _sample_count)
			adjust[j] = minf(adjust[j], 1.0 - speed_down_step * step_scale)
	
	var raise_half: int = maxi(1, int(round(raise_window / maxf(ds, 0.01) * 0.5)))
	var raises := PackedFloat32Array()
	raises.resize(_sample_count)
	for i in range(_sample_count):
		raises[i] = 1.0
	
	for i in range(_sample_count):
		if _visited[i] == 0 or _worst_outward[i] == -INF:
			continue
		if _worst_outward[i] >= clean_threshold:
			continue
		# Tracked clean here: lift this sample and its neighbourhood so the
		# increase survives the feasibility passes.
		for w in range(-raise_half, raise_half + 1):
			var j: int = wrapi(i + w, 0, _sample_count)
			raises[j] = maxf(raises[j], 1.0 + speed_up_step * step_scale)
	
	# A reduction anywhere in the neighbourhood always wins over an increase.
	for i in range(_sample_count):
		if adjust[i] >= 1.0:
			adjust[i] = raises[i]
	
	for i in range(_sample_count):
		speeds[i] = clampf(speeds[i] * adjust[i], min_speed, cap)
	
	_smooth(speeds)
	speeds = AIRacingLineBaker.apply_feasibility_passes(speeds, _seg_lengths, _perf)
	
	if train_style_gains and _line.has_style_gains():
		_update_style_gains(step_scale, window)
	
	var changed: int = 0
	for i in range(_sample_count):
		if absf(speeds[i] - before[i]) > 0.25:
			changed += 1
	
	_line.target_speeds = speeds
	return float(changed) / float(_sample_count)

## Nudge the per-sample cornering technique in the direction the measurement
## suggests. Hill climbing with revert in train() is what makes this safe:
## a perturbation that costs lap time is simply thrown away.
func _update_style_gains(step_scale: float, window: int) -> void:
	var airbrake: PackedFloat32Array = _line.style_airbrake.duplicate()
	var reserve: PackedFloat32Array = _line.style_reserve.duplicate()
	if airbrake.size() != _sample_count or reserve.size() != _sample_count:
		return
	
	var d_ab: float = airbrake_step * step_scale
	var d_res: float = reserve_step * step_scale
	
	for i in range(_sample_count):
		if _visited[i] == 0 or _worst_outward[i] == -INF:
			continue
		
		if _worst_outward[i] > wide_threshold:
			# Running wide: not enough rotation. Buy yaw over the approach,
			# same attribution logic as the speed reduction.
			for w in range(window):
				var j: int = wrapi(i - w, 0, _sample_count)
				airbrake[j] = clampf(airbrake[j] + d_ab, airbrake_min, airbrake_max)
				reserve[j] = clampf(reserve[j] - d_res, reserve_min, reserve_max)
		elif _worst_outward[i] < clean_threshold:
			# Tracking clean: we are paying scrub for rotation we do not need.
			airbrake[i] = clampf(airbrake[i] - d_ab, airbrake_min, airbrake_max)
			reserve[i] = clampf(reserve[i] + d_res, reserve_min, reserve_max)
	
	_smooth(airbrake)
	_smooth(reserve)
	_line.style_airbrake = airbrake
	_line.style_reserve = reserve

## Three-tap smoothing so single-sample spikes do not survive into the
## profile and make the controller stab the brakes.
func _smooth(speeds: PackedFloat32Array) -> void:
	var n := speeds.size()
	var copy := speeds.duplicate()
	for i in range(n):
		var a: float = copy[wrapi(i - 1, 0, n)]
		var b: float = copy[i]
		var c: float = copy[wrapi(i + 1, 0, n)]
		speeds[i] = (a + b * 2.0 + c) * 0.25
