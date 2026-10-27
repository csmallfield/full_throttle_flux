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
## behaviour), JP_CAM (a CinematicCameraRig camera name, e.g. side, front,
## trackside; "" = the chase camera), JP_FX (low / medium / high: FX quality
## for this run, never saved), JP_HITCH (ms: up to this much extra CPU time
## on random frames, to make the frame rate drop). Prints JUDDER lines: per frame, and "paced" (per second, which
## divides out uneven frame pacing).
##
## Measured (v37.1, RTX 3080, Builder Lab, 60 Hz physics), off -> on:
## 75 fps 20.6 -> 0.21 px, 144 fps 30.8 -> 0.13 px, 240 fps 25.2 -> 0.06 px;
## Utopia at ~140 fps 35.3 -> 0.19 px.

func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d


var _hitch_ms := 0.0
var _rng := RandomNumberGenerator.new()


func _process(_delta: float) -> void:
	# A busy CPU frame now and then, like a heavy moment in a race.
	if _hitch_ms > 0.0 and _rng.randf() < 0.25:
		var until := Time.get_ticks_usec() + int(_rng.randf() * _hitch_ms * 1000.0)
		while Time.get_ticks_usec() < until:
			pass


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var track_id := _env("JP_TRACK", "builder_lab")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(_env("JP_FPS", "144"))
	if _env("JP_INTERP", "1") == "0":
		get_tree().physics_interpolation = false   # A/B: the old behaviour
	match _env("JP_FX", ""):
		"low": FxSettings.active().quality = FxSettings.Quality.LOW
		"medium": FxSettings.active().quality = FxSettings.Quality.MEDIUM
		"high": FxSettings.active().quality = FxSettings.Quality.HIGH
	_hitch_ms = float(_env("JP_HITCH", "0"))
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
	var view: Camera3D = cam
	var cam_name := _env("JP_CAM", "")
	if cam_name != "":
		var rig := CinematicCameraRig.new()
		rig.name = "CinematicCameraRig"
		add_child(rig)
		rig.spline = ai.spline_helper
		rig.follow(ship)
		rig.select_index(CinematicCameraRig.CAMERA_NAMES.find(cam_name))
		view = rig.active_camera
	# Projects through where the view camera is DRAWN (its interpolated pose
	# when it is interpolated), whatever unproject_position() would use.
	var meter := Camera3D.new()
	meter.top_level = true
	meter.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(meter)
	var warm := float(_env("JP_WARMUP", "5"))
	var secs := float(_env("JP_SECONDS", "10"))
	var t0 := Time.get_ticks_msec()
	var pts := PackedVector2Array()
	# False where the ship is behind the camera or well off screen (planted
	# cameras): those frames say nothing about judder and are skipped.
	var seen: Array[bool] = []
	var vp := get_viewport().get_visible_rect().size
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
		meter.global_transform = view.get_global_transform_interpolated()
		meter.fov = view.fov
		meter.near = view.near
		meter.far = view.far
		var sp := meter.unproject_position(p)
		pts.append(sp)
		seen.append(not meter.is_position_behind(p) and Rect2(-vp * 0.25, vp * 1.5).has_point(sp))
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
	var skipped := 0
	var mags := PackedFloat32Array()
	for i in range(2, pts.size()):
		if not (seen[i] and seen[i - 1] and seen[i - 2]):
			skipped += 1
			continue
		var d2 := (pts[i] - pts[i - 1]) - (pts[i - 1] - pts[i - 2])
		acc += d2.length_squared()
		mags.append(d2.length())
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
	mags.sort()
	var pc := func(q: float) -> float: return mags[int(q * (mags.size() - 1))] if mags.size() > 0 else 0.0
	print("JUDDER   percentiles (px): p50 %.2f p90 %.2f p99 %.2f" % [pc.call(0.5), pc.call(0.9), pc.call(0.99)])
	print("JUDDER %s cam %s, fx %d, hitch %.0f ms, render %.0f fps, physics %d Hz, interpolation %s: judder RMS %.2f px, worst %.1f px; paced %.2f px; frame time sd %.2f ms (%d frames, %d skipped off screen)" % [
			track_id, cam_name if cam_name != "" else "chase", FxSettings.active().quality, _hitch_ms, fps, Engine.physics_ticks_per_second,
			"on" if ship.is_physics_interpolated_and_enabled() else "off", sqrt(acc / maxf(n, 1)), worst,
			sqrt(acc_t / maxf(n, 1)) * mean_dt, sqrt(dev / maxf(dts.size(), 1)) * 1000.0, frames, skipped])
	get_tree().quit(0)
