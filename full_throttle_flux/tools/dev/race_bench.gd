extends Node
## Race bench: the real game path (GameManager selections -> race_launcher.tscn
## -> RaceMode with 7 AI), measured once the race is running. Unlike gfx_bench,
## this includes the full grid: AI, ship physics, ship FX, HUD, audio.
##
##   godot --path . -s res://tools/dev/race_bench_boot.gd
##
## Env: RB_TRACK (test_circuit_3_live), RB_SECONDS (15), RB_WARMUP (8, from
## the green light), RB_VSYNC (1; 0 = off), RB_FPS (0 = uncapped),
## RB_DIFFICULTY (1), RB_PLAYER_AI (1: the player ship is driven by the AI
## too, so it races with the pack). Prints RACEBENCH lines: FPS, frame time
## percentiles, the frame's phases (physics scripts, physics step, process,
## draw, wait) from our own timestamps, GPU time, ticks per frame, node and
## collision counts. The "cpu process / physics" line is Godot's TIME_*
## monitors: the worst frame of the last second, so a noisy upper bound.
##
## Modes:
##   RB_NOFX=1    strip the v35 ship FX (ShipFx, ShipEnvProbe) at the green
##                light, for an A/B
##   RB_PROFILE=1 then switch off each script's _process / _physics_process
##                (and pause 3D audio and particles) in turn, and print what
##                each saves; noisy (the pack moves through the scenery), so
##                read only the big numbers
##   RB_EMPTY=1   the track scene alone with a fixed camera, no race
##
## Found with it (v38 merge, Xeon W-2265 + RTX 3080, Utopia): CPU-bound at
## ~40 fps; without ship FX 59 fps (vsync-locked). Trail ribbons ~3 ms/frame,
## ShipFx ~2 ms/frame, AI ~2.5 ms/tick.

## Frame phases from our own timestamps (Godot's TIME_* monitors report the
## worst frame of the last second, refreshed once a second). Main loop order:
## each physics tick (physics_frame -> _physics_process scripts -> server
## step), then process_frame -> _process scripts, then frame_pre_draw -> draw
## -> frame_post_draw, then present / vsync / input.
var _phase_on := false
var _phase_frames := 0
var _ph_scripts := 0.0
var _ph_step := 0.0
var _ph_ticks := 0.0
var _ph_proc := 0.0
var _ph_draw := 0.0
var _ph_wait := 0.0
var _t_tick := 0
var _t_scripts_end := 0
var _t_frame_start := 0
var _t_proc := 0
var _t_pre := 0
var _t_post := 0
var _tail: Node


func _start_phases() -> void:
	_tail = Node.new()
	_tail.set_script(_TailScript)
	_tail.process_physics_priority = 1000000
	_tail.bench = self
	add_child(_tail)
	get_tree().physics_frame.connect(_on_physics_frame)
	get_tree().process_frame.connect(_on_process_frame)
	RenderingServer.frame_pre_draw.connect(func(): _t_pre = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	_phase_on = true


func _on_physics_frame() -> void:
	var now := Time.get_ticks_usec()
	if _t_scripts_end > _t_tick and _t_tick > _t_post:
		_ph_step += (now - _t_scripts_end) / 1000.0   # previous tick's server step
	if _t_frame_start <= _t_post:
		_t_frame_start = now
	_t_tick = now


func _scripts_done() -> void:
	_t_scripts_end = Time.get_ticks_usec()
	if _phase_on:
		_ph_scripts += (_t_scripts_end - _t_tick) / 1000.0
		_ph_ticks += 1.0


func _on_process_frame() -> void:
	_t_proc = Time.get_ticks_usec()
	if _phase_on and _t_scripts_end > _t_post and _t_tick > _t_post:
		_ph_step += (_t_proc - _t_scripts_end) / 1000.0   # last tick's server step


func _on_post_draw() -> void:
	var now := Time.get_ticks_usec()
	if _phase_on and _t_post > 0:
		var start := _t_frame_start if _t_frame_start > _t_post else _t_proc
		_ph_wait += (start - _t_post) / 1000.0
		_ph_proc += (_t_pre - _t_proc) / 1000.0
		_ph_draw += (now - _t_pre) / 1000.0
		_phase_frames += 1
	_t_post = now


const _TailScript := preload("res://tools/dev/race_bench_tail.gd")


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var track_id := _env("RB_TRACK", "test_circuit_3_live")
	if _env("RB_VSYNC", "1") == "0":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(_env("RB_FPS", "0"))
	if _env("RB_EMPTY", "0") == "1":
		await _empty_track(track_id)
		return
	GameManager.select_mode("race")
	GameManager.select_track_by_id(track_id)
	GameManager.select_ship_by_id("default_racer")
	GameManager.select_race_difficulty(int(_env("RB_DIFFICULTY", "1")))
	get_tree().change_scene_to_file("res://scenes/race_launcher.tscn")

	# Wait for the green light.
	var started := false
	var t_wait := Time.get_ticks_msec()
	while not started and Time.get_ticks_msec() - t_wait < 60000:
		await get_tree().process_frame
		var player := _find_player()
		if player and "controls_locked" in player:
			started = not player.controls_locked
		elif player:
			started = Time.get_ticks_msec() - t_wait > 12000
	if not started:
		print("RACEBENCH could not detect the race start")
		get_tree().quit(1)
		return
	var player := _find_player()
	if player and _env("RB_PLAYER_AI", "1") == "1":
		_drive_player(player)

	if _env("RB_NOFX", "0") == "1":
		# A/B: the race without v35 ship FX (ribbons, thrust, dust, sparks)
		# and without the env probes that feed them.
		for fx in get_tree().root.find_children("*", "ShipFx", true, false):
			fx._unbind()
			fx.set_process(false)
		for pr in get_tree().root.find_children("*", "ShipEnvProbe", true, false):
			pr.set_physics_process(false)
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var warm := float(_env("RB_WARMUP", "8"))
	var secs := float(_env("RB_SECONDS", "15"))
	var t0 := Time.get_ticks_usec()
	while (Time.get_ticks_usec() - t0) / 1e6 < warm:
		await get_tree().process_frame

	_start_phases()
	var dts := PackedFloat64Array()
	var proc := 0.0
	var phys := 0.0
	var gpu := 0.0
	var cpu_render := 0.0
	var n := 0
	var ticks0 := Engine.get_physics_frames()
	var last := Time.get_ticks_usec()
	var t1 := last
	while (Time.get_ticks_usec() - t1) / 1e6 < secs:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		dts.append((now - last) / 1000.0)
		last = now
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		cpu_render += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		n += 1
	var ticks := Engine.get_physics_frames() - ticks0
	_phase_on = false
	var pn := maxf(_phase_frames, 1)
	print("RACEBENCH   phases per frame (ms): physics scripts %.2f + physics step %.2f (%.2f ticks), process %.2f, draw %.2f, wait/other %.2f" % [
			_ph_scripts / pn, _ph_step / pn, _ph_ticks / pn, _ph_proc / pn, _ph_draw / pn, _ph_wait / pn])
	var sorted := dts.duplicate()
	sorted.sort()
	var elapsed := (Time.get_ticks_usec() - t1) / 1e6
	var size := DisplayServer.window_get_size()
	print("RACEBENCH %s %dx%d vsync %s: %.1f fps; frame ms p50 %.2f p95 %.2f p99 %.2f max %.1f" % [
			track_id, size.x, size.y, "on" if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED else "off",
			n / elapsed, sorted[n / 2], sorted[int(n * 0.95)], sorted[int(n * 0.99)], sorted[n - 1]])
	print("RACEBENCH   cpu process %.2f ms, physics %.2f ms per tick, %.2f ticks/frame (%d Hz); render cpu %.2f ms, gpu %.2f ms; ships %d" % [
			proc / n, phys / n, float(ticks) / n, Engine.physics_ticks_per_second,
			cpu_render / n, gpu / n, get_tree().get_nodes_in_group(ShipContactResolver.GROUP).size()])
	print("RACEBENCH   objects %d, nodes %d, draw calls %d, primitives %d" % [
			Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	print("RACEBENCH   physics: active objects %d, collision pairs %d, islands %d" % [
			Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
			Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
			Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)])
	var kinds := {}
	for co in get_tree().root.find_children("*", "CollisionObject3D", true, false):
		var k: String = co.get_class() + (" monitoring" if co is Area3D and co.monitoring else "")
		kinds[k] = int(kinds.get(k, 0)) + 1
	print("RACEBENCH   collision objects: %s" % str(kinds))
	var builtin := {}
	for t in ["RayCast3D", "ShapeCast3D", "GPUParticles3D", "CPUParticles3D", "AnimationPlayer",
			"AudioStreamPlayer3D", "OmniLight3D", "SpotLight3D", "MeshInstance3D", "MultiMeshInstance3D", "Label3D"]:
		var all := get_tree().root.find_children("*", t, true, false)
		var on := all.filter(func(x): return x.is_inside_tree() and (not x is Node3D or x.is_visible_in_tree()))
		builtin[t] = "%d (%d active)" % [all.size(), on.size()] if t != "RayCast3D" else \
				"%d (%d enabled)" % [all.size(), all.filter(func(x): return x.enabled).size()]
	print("RACEBENCH   built-in nodes: %s" % str(builtin))
	if _env("RB_PROFILE", "0") == "1":
		await _profile()
	get_tree().quit(0)


## Per-script cost: switch off each script's _process (then _physics_process)
## on every node that has it, and see how much frame time goes away.
func _profile() -> void:
	var groups := {}
	for n in get_tree().root.find_children("*", "", true, false):
		var s: Script = n.get_script()
		if s == null or n == self:
			continue
		var key := s.resource_path.get_file()
		if not groups.has(key):
			groups[key] = []
		groups[key].append(n)
	var base := await _sample(2.0)
	print("RACEBENCH PROFILE base: process %.2f ms/frame, physics scripts %.2f ms/tick" % [base.x, base.y])
	var rows := []
	for key in groups:
		var nodes: Array = groups[key]
		var p_on := nodes.filter(func(n): return n.is_processing())
		var f_on := nodes.filter(func(n): return n.is_physics_processing())
		if p_on.is_empty() and f_on.is_empty():
			continue
		var dp := 0.0
		var df := 0.0
		if not p_on.is_empty():
			for n in p_on: n.set_process(false)
			var r := await _sample(2.0)
			for n in p_on: if is_instance_valid(n): n.set_process(true)
			dp = base.x - r.x
		if not f_on.is_empty():
			for n in f_on: n.set_physics_process(false)
			var r := await _sample(2.0)
			for n in f_on: if is_instance_valid(n): n.set_physics_process(true)
			df = base.y - r.y
		rows.append([key, nodes.size(), dp, df])
	# Built-in nodes with internal per-tick work: pause them (PROCESS_MODE_DISABLED).
	for t in ["AudioStreamPlayer3D", "GPUParticles3D"]:
		var all := get_tree().root.find_children("*", t, true, false)
		var modes := all.map(func(x): return x.process_mode)
		for x in all: x.process_mode = Node.PROCESS_MODE_DISABLED
		var r := await _sample(2.0)
		for i in all.size():
			if is_instance_valid(all[i]): all[i].process_mode = modes[i]
		rows.append(["(built-in) " + t, all.size(), base.x - r.x, base.y - r.y])
	rows.sort_custom(func(a, b): return a[2] + a[3] > b[2] + b[3])
	for r in rows:
		print("RACEBENCH PROFILE %-34s x%-4d process %+.2f ms/frame  physics %+.2f ms/tick" % [r[0], r[1], -r[2], -r[3]])


## RB_EMPTY=1: the track scene alone (no ships, mode, HUD), a fixed camera
## above the start. What the world costs by itself.
func _empty_track(track_id: String) -> void:
	var track: Node = (load("res://scenes/tracks/%s.tscn" % track_id) as PackedScene).instantiate()
	add_child(track)
	var cam := Camera3D.new()
	add_child(cam)
	var grid := track.find_child("StartingGrid", true, false)
	var xf: Transform3D = grid.get_pole_position() if grid and grid.has_method("get_pole_position") else Transform3D.IDENTITY
	cam.global_transform = xf.translated_local(Vector3(0, 4, 10))
	cam.make_current()
	await get_tree().create_timer(3.0).timeout
	var r := await _sample(5.0)
	print("RACEBENCH EMPTY %s: process %.2f ms, physics %.2f ms/tick; objects %d, nodes %d" % [
			track_id, r.x, r.y, Performance.get_monitor(Performance.OBJECT_COUNT),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	print("RACEBENCH EMPTY   physics: active objects %d, collision pairs %d, islands %d" % [
			Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
			Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
			Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)])
	get_tree().quit(0)


## (process ms per frame, physics script ms per tick) over `secs`, from the
## phase timers.
func _sample(secs: float) -> Vector2:
	await get_tree().create_timer(0.3).timeout
	_phase_frames = 0
	_ph_scripts = 0.0
	_ph_step = 0.0
	_ph_ticks = 0.0
	_ph_proc = 0.0
	_ph_draw = 0.0
	_ph_wait = 0.0
	_phase_on = true
	await get_tree().create_timer(secs).timeout
	_phase_on = false
	return Vector2(_ph_proc / maxf(_phase_frames, 1), _ph_scripts / maxf(_ph_ticks, 1))


func _find_player() -> Node:
	var scene := get_tree().current_scene
	return scene.find_child("Player_Ship", true, false) if scene else null


## The player ship sits on the grid otherwise; hand it to an AI controller so
## the camera follows a ship racing in the pack, as when playing.
func _drive_player(ship: Node) -> void:
	var donor: AIShipController = null
	for c in get_tree().current_scene.find_children("*", "AIShipController", true, false):
		donor = c
		break
	if donor == null:
		return
	var ai := AIShipController.new()
	ai.ship = ship
	ai.skill_level = 1.0
	ship.ai_controlled = true
	donor.get_parent().add_child(ai)
	ai.initialize(donor.track_root, donor.baked_line)
