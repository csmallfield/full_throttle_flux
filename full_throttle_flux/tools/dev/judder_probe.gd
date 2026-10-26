extends Node
## Ship judder probe: one AI ship on its trained line with the real chase
## camera, rendering at JP_FPS while physics runs at its own rate. Every
## rendered frame it records where the ship's origin lands on screen and
## reports the judder: the RMS of the frame-to-frame change in the ship's
## screen motion (second difference, pixels). A ship gliding smoothly across
## the screen scores near 0; one that stutters against the camera scores high.
##
##   godot --path . -s res://tools/dev/judder_probe_boot.gd
##
## Env: JP_TRACK (builder_lab), JP_FPS (144; 0 = uncapped), JP_SECONDS (10),
## JP_WARMUP (5), JP_INTERP (1; 0 = physics interpolation off, the pre-v37.1
## behaviour). Prints JUDDER lines: per frame, and "paced" (per second, which
## divides out uneven frame pacing).
##
## Measured (v37.1, RTX 3080, Builder Lab, 60 Hz physics), off -> on:
## 75 fps 20.6 -> 0.21 px, 144 fps 30.8 -> 0.13 px, 240 fps 25.2 -> 0.06 px;
## Utopia at ~140 fps 35.3 -> 0.19 px.

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var track_id := _env("JP_TRACK", "builder_lab")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(_env("JP_FPS", "144"))
	if _env("JP_INTERP", "1") == "0":
		get_tree().physics_interpolation = false   # A/B: the old behaviour
	var profile := load("res://resources/ships/default_racer.tres") as ShipProfile
	var line := ResourceLoader.load(AILineTrainer.trained_path(track_id, profile.ship_id), "",
			ResourceLoader.CACHE_MODE_IGNORE) as BakedRacingLine
	var track: Node = (load("res://scenes/tracks/%s.tscn" % track_id) as PackedScene).instantiate()
	add_child(track)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var ship := AILineTrainer.spawn_ship(profile)
	add_child(ship)
	var grid := track.find_child("StartingGrid", true, false)
	if grid and grid.has_method("get_pole_position"):
		ship.global_transform = grid.get_pole_position()
	ship.ai_controlled = true
	var ai := AIShipController.new()
	ai.ship = ship
	ai.skill_level = 1.0
	ai.avoidance_enabled = false
	add_child(ai)
	ai.prefer_trained_line = false
	if line:
		ai.initialize(track, line)
	var cam: AGCamera2097 = (load("res://scripts/ag_camera_2097.gd") as GDScript).new()
	cam.intro_enabled = false
	add_child(cam)
	cam.ship = ship
	ship.camera = cam
	if cam.has_method("set_track"):
		cam.set_track(track)
	cam.make_current()
	var warm := float(_env("JP_WARMUP", "5"))
	var secs := float(_env("JP_SECONDS", "10"))
	var t0 := Time.get_ticks_msec()
	var pts := PackedVector2Array()
	var stamps := PackedFloat64Array()
	var frames := 0
	while (Time.get_ticks_msec() - t0) / 1000.0 < warm + secs:
		# After every _process (camera included), just before drawing.
		await RenderingServer.frame_pre_draw
		if (Time.get_ticks_msec() - t0) / 1000.0 < warm:
			continue
		# Where the ship is drawn (its physics transform when interpolation
		# is off).
		var p: Vector3 = ship.get_global_transform_interpolated().origin
		pts.append(cam.unproject_position(p))
		stamps.append(Time.get_ticks_usec() / 1e6)
		frames += 1
	# Per frame (as the player sees it) and per second: the per-second one
	# divides out uneven frame pacing, which the per-frame one counts as judder
	# even when the ship moves perfectly smoothly in time.
	var acc := 0.0
	var acc_t := 0.0
	var n := 0
	var worst := 0.0
	var dts := PackedFloat64Array()
	for i in range(2, pts.size()):
		var d2 := (pts[i] - pts[i - 1]) - (pts[i - 1] - pts[i - 2])
		acc += d2.length_squared()
		worst = maxf(worst, d2.length())
		var dt0: float = maxf(stamps[i - 1] - stamps[i - 2], 1e-5)
		var dt1: float = maxf(stamps[i] - stamps[i - 1], 1e-5)
		var dv := (pts[i] - pts[i - 1]) / dt1 - (pts[i - 1] - pts[i - 2]) / dt0
		acc_t += dv.length_squared()
		dts.append(dt1)
		n += 1
	var fps := frames / maxf(secs, 0.001)
	var mean_dt := 1.0 / maxf(fps, 1.0)
	var dev := 0.0
	for dt in dts:
		dev += (dt - mean_dt) * (dt - mean_dt)
	print("JUDDER %s render %.0f fps, physics %d Hz, interpolation %s: judder RMS %.2f px, worst %.1f px; paced %.2f px; frame time sd %.2f ms (%d frames)" % [
			track_id, fps, Engine.physics_ticks_per_second,
			"on" if ship.is_physics_interpolated_and_enabled() else "off", sqrt(acc / maxf(n, 1)), worst,
			sqrt(acc_t / maxf(n, 1)) * mean_dt, sqrt(dev / maxf(dts.size(), 1)) * 1000.0, frames])
	get_tree().quit(0)
