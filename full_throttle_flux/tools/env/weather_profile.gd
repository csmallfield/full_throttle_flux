extends SceneTree
## v35 Phase 4: GPU cost of every weather on REAL hardware (GPU timing means
## nothing on the software renderer this was built on).
## Launches an AI race (8 ships), follows an AI ship through the spectator so
## the camera is at race speed, then runs each weather preset for a block and
## prints the viewport's average whole-frame GPU time, and the difference to
## clear (measured first and last, averaged, so drift along the lap evens out).
## Budget from the design: all environment FX within +2 ms in heavy weather.
##
## usage: godot --path . -s res://tools/env/weather_profile.gd
##   optional: WP_TRACK=test_circuit_3_live  WP_BLOCK=5 (seconds per preset)
##             WP_SETTLE=1.5  WP_ONLY="rain_heavy,fog_heavy"  WP_QUALITY=0|1|2

const PRESETS := ["clear", "rain_light", "rain_medium", "rain_heavy", "snow_light", "snow_medium",
	"snow_heavy", "fog_light", "fog_medium", "fog_heavy", "dust_storm_light", "dust_storm_medium",
	"dust_storm_heavy", "clear"]


func _initialize() -> void:
	await process_frame
	if OS.has_environment("WP_QUALITY"):
		FxSettings.active().quality = int(OS.get_environment("WP_QUALITY")) as FxSettings.Quality
	var gm = root.get_node("GameManager")
	gm.select_track_by_id(OS.get_environment("WP_TRACK") if OS.has_environment("WP_TRACK") else "test_circuit_3_live")
	if "selected_mode" in gm:
		gm.selected_mode = "race"
	root.add_child(load("res://scenes/race_launcher.tscn").instantiate())
	var block := float(OS.get_environment("WP_BLOCK")) if OS.has_environment("WP_BLOCK") else 5.0
	var settle := float(OS.get_environment("WP_SETTLE")) if OS.has_environment("WP_SETTLE") else 1.5
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	var spec: Node = root.find_child("AISpectator", true, false)
	if spec:
		spec.call("_activate", true)
		spec.call("_step", 1)
	var env := EnvironmentState.find(self)
	if env == null:
		push_error("weather_profile: no EnvironmentState in the race")
		quit(1)
		return
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var list: Array = PRESETS
	if OS.has_environment("WP_ONLY"):
		list = ["clear"] + Array(OS.get_environment("WP_ONLY").split(",")) + ["clear"]
	var results := {}
	for name in list:
		var preset := load("res://resources/weather/%s.tres" % name) as WeatherPreset
		env.apply_weather(preset, true)
		var s0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - s0 < settle * 1000.0:
			await process_frame
		var sum := 0.0
		var cpu := 0.0
		var frames := 0
		var b0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - b0 < block * 1000.0:
			await process_frame
			sum += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
			frames += 1
		var gpu := sum / maxi(frames, 1)
		if results.has(name):
			results[name] = (results[name] + gpu) * 0.5
		else:
			results[name] = gpu
		print("WEATHER %-18s gpu %6.2f ms  cpu %5.2f ms  (%d frames, %.0f fps)" % [name, gpu,
			cpu / maxi(frames, 1), frames, frames / block])
	var base: float = results.get("clear", 0.0)
	print("\nWEATHER summary vs clear (%.2f ms GPU), quality %s:" % [base, FxSettings.Quality.keys()[FxSettings.active().quality]])
	for name in results:
		if name == "clear":
			continue
		var d: float = results[name] - base
		print("  %-18s %+6.2f ms %s" % [name, d, "  OVER 2 ms BUDGET" if d > 2.0 else ""])
	quit()
