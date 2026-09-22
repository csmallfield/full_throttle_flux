extends Node3D

## Headless entry point for AILineTrainer.
##
## Run from the project root:
##     godot --headless res://tools/train_ai_lines.tscn
##
## For each track it bakes a line, drives it until the speed profile stops
## improving, and writes the result to res://resources/ai_data/ where
## AIShipController picks it up automatically at runtime.
##
## Only the gameworthy circuits are listed. Add or remove entries here.

const TRACKS: Array[String] = [
	"res://scenes/tracks/test_circuit_3_live.tscn",
	"res://scenes/tracks/test_circuit_5_live.tscn",
	"res://scenes/tracks/test_circuit_6_live.tscn",
	"res://scenes/tracks/test_circuit_7_live.tscn",
]

const SHIP_PROFILES: Array[String] = [
	"res://resources/ships/default_racer.tres",
]

const SHIP_SCENE := "res://scenes/ships/default_racer.tscn"

## Overridden by --max-iterations=N on the command line.
@export var max_iterations: int = 14

## Overridden by --time-scale=N.
@export var time_scale: float = 8.0

var _results: Array[Dictionary] = []

func _ready() -> void:
	_parse_args()
	print_rich("[b]AI line trainer[/b] - %d track(s) x %d ship(s), up to %d iterations at %.0fx" % [
		TRACKS.size(), SHIP_PROFILES.size(), max_iterations, time_scale])
	await _run_all()
	_print_summary()
	get_tree().quit()

func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--max-iterations="):
			max_iterations = int(arg.split("=")[1])
		elif arg.begins_with("--time-scale="):
			time_scale = float(arg.split("=")[1])

func _run_all() -> void:
	for track_path in TRACKS:
		for profile_path in SHIP_PROFILES:
			await _train_one(track_path, profile_path)

func _train_one(track_path: String, profile_path: String) -> void:
	var scene := load(track_path) as PackedScene
	var profile := load(profile_path) as ShipProfile
	if scene == null or profile == null:
		push_error("trainer: could not load %s / %s" % [track_path, profile_path])
		return
	
	var track: Node = scene.instantiate()
	add_child(track)
	# Two frames so CSG geometry and its collision shapes exist before the
	# baker starts casting corridor rays at them.
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# Scene-file derived, so tracks sharing a root node name do not collide.
	var track_id := AILineTrainer.track_id_for(track)
	if track_id.is_empty():
		track_id = track_path.get_file().get_basename()
	print_rich("\n[b]%s[/b] / %s" % [track_id, profile.ship_id])
	
	var helper := TrackSplineHelper.new(track)
	if not helper.is_valid:
		push_error("trainer: no usable spline in %s" % track_id)
		track.queue_free()
		return
	
	var perf := ShipPerformanceModel.new(profile)
	# Seed from an existing trained/assembled line when there is one. The
	# style search produces a much better starting point than a fresh bake,
	# and its per-sample style gains ride along on the same resource -- the
	# trainer only ever rewrites target_speeds, so they survive untouched.
	var line: BakedRacingLine = AILineTrainer.load_trained_line(track_id, profile.ship_id)
	if line != null:
		print("  seeded from existing trained line%s" % [
			" (with style gains)" if line.has_style_gains() else ""])
	else:
		var baker := AIRacingLineBaker.new()
		baker.use_cache = false
		line = baker.bake(helper, profile, get_viewport().find_world_3d(), track_id)
		if line == null:
			push_error("trainer: bake failed for %s" % track_id)
			track.queue_free()
			return
		print("  baked: %s" % line.get_debug_info())
	var analytic_speeds := line.target_speeds.duplicate()
	
	# --- ship + AI ---
	var ship: ShipController = (load(SHIP_SCENE) as PackedScene).instantiate()
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
	ai.prefer_trained_line = false  # test the line we pass, not the saved one
	ai.initialize(track, line)
	
	if not ai.is_initialized:
		push_error("trainer: AI failed to initialize on %s" % track_id)
		_cleanup(track, ship, ai)
		return
	
	# --- train ---
	var trainer := AILineTrainer.new()
	trainer.max_iterations = max_iterations
	trainer.time_scale = time_scale
	add_child(trainer)
	trainer.progress.connect(func(msg: String): print("  " + msg))
	
	var had_gains: bool = line.has_style_gains()
	var trained: BakedRacingLine = await trainer.train(track, ship, ai, helper, line, perf)
	if had_gains and not trained.has_style_gains():
		push_error("trainer: style gains were lost during training on %s" % track_id)
	
	# --- report + save ---
	var mean_before := _mean(analytic_speeds)
	var mean_after := _mean(trained.target_speeds)
	var err := AILineTrainer.save_trained_line(trained, profile)
	if err != OK:
		push_error("trainer: failed to save %s (error %d)" % [track_id, err])
	
	_results.append({
		"track": track_id,
		"ship": profile.ship_id,
		"lap": trained.trained_lap_time,
		"before": mean_before,
		"after": mean_after,
		"saved": err == OK,
	})
	print("  mean target speed %.1f -> %.1f, best lap %.2fs%s" % [
		mean_before, mean_after, trained.trained_lap_time,
		"" if err == OK else "  [SAVE FAILED]"])
	
	trainer.queue_free()
	_cleanup(track, ship, ai)
	await get_tree().physics_frame

func _cleanup(track: Node, ship: Node, ai: Node) -> void:
	ai.queue_free()
	ship.queue_free()
	track.queue_free()

func _mean(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / a.size()

func _find(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var r := _find(c, nm)
		if r:
			return r
	return null

func _print_summary() -> void:
	print_rich("\n[b]Summary[/b]")
	for r in _results:
		print("  %-24s %-16s lap %7.2fs   mean speed %6.1f -> %6.1f  %s" % [
			r.track, r.ship, r.lap, r.before, r.after,
			"saved" if r.saved else "NOT SAVED"])
	if _results.is_empty():
		print("  nothing trained")
