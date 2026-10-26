extends Node
## GPU benchmark for shadow and anti-aliasing settings (v37). For each track
## and each settings config: a fresh copy of the track, one AI ship driving
## its trained line from the grid with the real chase camera (dynamic FOV,
## motion blur and all), a short warm-up, then GPU and CPU frame times
## measured by the RenderingServer for GB_SECONDS. Vsync is off.
##
## Run it on the real GPU, windowed, nothing else heavy running:
##
##   godot --path . -s res://tools/dev/gfx_bench_boot.gd
##
## Env (all optional):
##   GB_TRACKS   default: the four circuits
##               test_circuit_3_live,test_circuit_5_live,test_circuit_6_live,test_circuit_7_live
##   GB_CONFIGS  name:aa:shadows:profile:grid[:tier],...  aa 0-3 and shadows 0-2
##               as in GraphicsSettings; profile 1 = apply the v37 ShadowProfile,
##               0 = the track's own v36 light settings; grid 0 = the v36 road
##               grid shader, 1 (or left out) = the filtered one, 2 = the v38
##               track surface where the track has it (builder tracks) and the
##               filtered grid elsewhere; with 0 and 1 builder roads are put
##               back on the grid; 3 = the v38 road with the walls on the grid
##               (phase 5: what the walls cost). tier = v38 surface tier 0 low / 1 high
##               (default 1). Default: CONFIGS; "v38" = V38_CONFIGS, the v38 gate.
##   GB_ENV      1 (default) = run EnvSurfaces.adopt() as a race does, so road
##               and walls draw with their weather shaders (env globals at 0).
##               Skipped on grid 0 rows (it would swap the v36 grid out).
##   GB_SECONDS  measured seconds per config (default 20)
##   GB_WARMUP   seconds before measuring (default 4)
##   GB_RES      window size, default 1920x1080
##   GB_SHOTS    seconds (after the warm-up) to save a screenshot at, e.g. "2,6"
##   GB_OUT      folder for screenshots and the CSV (default user://gfx_bench)
##   (Add --fixed-fps 60 for screenshots that line up between configs: the
##    ship is then in the same place at the same shot time. Not for timing.)
##
## Output: a GFXBENCH line per track and config (GPU median / p99, CPU median,
## fps median) and gfx_bench.csv. Compare each config with "v36" on the same
## track: the budget we agreed is about +0.5 ms of GPU time.

const CONFIGS := "v36:0:0:0:0,profile:0:0:1,shadows_high:0:1:1,msaa4:1:0:1,v37:1:1:1,shadows_ultra:1:2:1,taa:2:1:1,fsr2:3:1:1"
const TRACKS := "test_circuit_3_live,test_circuit_5_live,test_circuit_6_live,test_circuit_7_live"
## v38 gate: the filtered grid against the track surface, both tiers, at v37
## settings. Run with GB_TRACKS=builder_lab. Budgets (FTF_v38_TRACK_SURFACE_P2.md):
## low tier <= +0.1 ms GPU over grid_v37 on the RTX 3080 at 1080p (verify on
## a GTX 1080 Ti); high tier <= +0.5 ms over grid_v37 on the 3080 at 1440p.
const V38_CONFIGS := "grid_v37:1:1:1:1,surface_low:1:1:1:2:0,surface_high:1:1:1:2:1"
const GRID_MATERIAL := "res://shaders/resources/grid_material.tres"

var out := ""
var rows: Array = []


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d


func _ready() -> void:
	out = _env("GB_OUT", "user://gfx_bench")
	DirAccess.make_dir_recursive_absolute(out)
	var res := _env("GB_RES", "1920x1080").split("x")
	get_window().size = Vector2i(int(res[0]), int(res[1]))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_run.call_deferred()


func _run() -> void:
	var gs: Node = get_node_or_null("/root/GraphicsSettings")
	if gs == null:
		print("GFXBENCH needs the GraphicsSettings autoload")
		get_tree().quit(1)
		return
	var secs := float(_env("GB_SECONDS", "20"))
	var warm := float(_env("GB_WARMUP", "4"))
	var shots := PackedFloat32Array()
	for s in _env("GB_SHOTS", "").split(",", false):
		shots.append(float(s))
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	print("GFXBENCH %s, %s, %s" % [RenderingServer.get_video_adapter_name(),
			RenderingServer.get_video_adapter_api_version(), get_window().size])
	for track_id in _env("GB_TRACKS", TRACKS).split(",", false):
		var configs := _env("GB_CONFIGS", CONFIGS)
		if configs == "v38":
			configs = V38_CONFIGS
		for cfg in configs.split(",", false):
			var c := cfg.split(":")
			var name := c[0]
			gs.set_aa(int(c[1]))
			gs.set_shadows(int(c[2]))
			var grid := int(c[4]) if c.size() > 4 else 1
			gs.set_grid_v36(grid == 0)
			gs.set_surface_tier(int(c[5]) if c.size() > 5 else 1)
			var setup := await _setup(track_id, c.size() > 3 and c[3] == "1", grid)
			if setup.is_empty():
				continue
			var t := 0.0
			var gpu := PackedFloat32Array()
			var cpu := PackedFloat32Array()
			var dt := PackedFloat32Array()
			var shot_i := 0
			while t < warm + secs:
				await get_tree().process_frame
				var d := get_process_delta_time()
				t += d
				if t < warm:
					continue
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
				cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
				dt.append(d * 1000.0)
				if shot_i < shots.size() and t - warm >= shots[shot_i]:
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_png(
							"%s/%s_%s_%02d.png" % [out, track_id, name, shot_i])
					shot_i += 1
			var row := [track_id, name, _q(gpu, 0.5), _q(gpu, 0.99), _q(cpu, 0.5),
					1000.0 / maxf(_q(dt, 0.5), 0.001), gpu.size()]
			rows.append(row)
			print("GFXBENCH %-22s %-14s gpu %6.2f ms (p99 %6.2f)  cpu %5.2f ms  %6.1f fps  (%d frames)" % row)
			(setup.root as Node).queue_free()
			await get_tree().process_frame
	var f := FileAccess.open("%s/gfx_bench.csv" % out, FileAccess.WRITE)
	if f:
		f.store_line("track,config,gpu_median_ms,gpu_p99_ms,cpu_median_ms,fps_median,frames")
		for r in rows:
			f.store_line(",".join(r.map(func(x): return str(x))))
	print("GFXBENCH done -> %s" % ProjectSettings.globalize_path(out))
	get_tree().quit(0)


## A fresh track with one AI ship and the chase camera. {root} or {}.
func _setup(track_id: String, use_profile: bool, grid_mode: int) -> Dictionary:
	var ps := load("res://scenes/tracks/%s.tscn" % track_id) as PackedScene
	if ps == null:
		print("GFXBENCH no track %s" % track_id)
		return {}
	var holder := Node3D.new()
	add_child(holder)
	var track := ps.instantiate()
	holder.add_child(track)
	if use_profile:
		var tp := _track_profile(track_id)
		get_node("/root/GraphicsSettings").apply_track(track, tp.get("shadow_profile") if tp else null)
	if grid_mode < 2:
		_roads_to_grid(track)
	elif grid_mode == 3:
		_roads_to_grid(track, true)
	if grid_mode != 0 and _env("GB_ENV", "1") == "1":
		EnvSurfaces.adopt(track, track.find_child("MainSpline", true, false) as Path3D)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var profile := load("res://resources/ships/default_racer.tres") as ShipProfile
	var line := ResourceLoader.load(AILineTrainer.trained_path(track_id, profile.ship_id), "",
			ResourceLoader.CACHE_MODE_IGNORE) as BakedRacingLine
	var ship := AILineTrainer.spawn_ship(profile)
	holder.add_child(ship)
	var grid := track.find_child("StartingGrid", true, false)
	if grid and grid.has_method("get_pole_position"):
		ship.global_transform = grid.get_pole_position()
	ship.ai_controlled = true
	var ai := AIShipController.new()
	ai.ship = ship
	ai.skill_level = 1.0
	ai.avoidance_enabled = false
	holder.add_child(ai)
	ai.prefer_trained_line = false
	if line:
		ai.initialize(track, line)
	var cam: AGCamera2097 = (load("res://scripts/ag_camera_2097.gd") as GDScript).new()
	cam.intro_enabled = false
	holder.add_child(cam)
	cam.ship = ship
	ship.camera = cam
	if cam.has_method("set_track"):
		cam.call("set_track", track)
	cam.make_current()
	return {root = holder}


## v38 baseline: builder road (and, phase 5, wall) segments drawn with the
## grid again.
func _roads_to_grid(track: Node, walls_only := false) -> void:
	var grid_mat := load(GRID_MATERIAL) as Material
	for n in track.find_children("*", "TrackRoadSegment", true, false):
		if walls_only and not ((n as TrackRoadSegment).collision_layer & 4):
			continue
		var mi := (n as TrackRoadSegment).mesh_instance()
		if mi and mi.mesh and mi.mesh.surface_get_material(0) != grid_mat:
			mi.set_surface_override_material(0, grid_mat)


func _track_profile(track_id: String) -> Resource:
	var p := "res://resources/tracks/%s.tres" % track_id
	return load(p) if ResourceLoader.exists(p) else null


static func _q(v: PackedFloat32Array, q: float) -> float:
	if v.is_empty():
		return 0.0
	var s := v.duplicate()
	s.sort()
	return s[clampi(int(q * (s.size() - 1)), 0, s.size() - 1)]
