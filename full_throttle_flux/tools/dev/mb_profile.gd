extends SceneTree
## Motion blur cost on REAL hardware (GPU timing is meaningless on lavapipe).
## Launches an AI race, follows an AI ship through the spectator so the camera
## is at race speed, then alternates the blur on/off in blocks and prints the
## averages: per-pass GPU ms from the effect's timestamps, and the viewport's
## whole-frame GPU ms with the blur on vs off (which also captures the cost of
## Forward+ writing the velocity buffer).
## usage: MB_TRACK=test_circuit_6_live godot --path . -s res://tools/dev/mb_profile.gd
##   optional: MB_SECONDS=40 (total), MB_BLOCK=4 (seconds per on/off block),
##             MB_MSAA=0|2|4 (override project MSAA), MB_SAMPLES=12
func _initialize() -> void:
	await process_frame
	var gm = root.get_node("GameManager")
	gm.select_track_by_id(OS.get_environment("MB_TRACK") if OS.has_environment("MB_TRACK") else "test_circuit_6_live")
	if "selected_mode" in gm:
		gm.selected_mode = "race"
	if OS.has_environment("MB_MSAA"):
		root.msaa_3d = {"0": Viewport.MSAA_DISABLED, "2": Viewport.MSAA_2X, "4": Viewport.MSAA_4X}.get(OS.get_environment("MB_MSAA"), root.msaa_3d)
	root.add_child(load("res://scenes/race_launcher.tscn").instantiate())
	var total := float(OS.get_environment("MB_SECONDS")) if OS.has_environment("MB_SECONDS") else 40.0
	var block := float(OS.get_environment("MB_BLOCK")) if OS.has_environment("MB_BLOCK") else 4.0
	# let the race start and the AI get up to speed
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:
		await process_frame
	var spec: Node = root.find_child("AISpectator", true, false)
	if spec:
		spec.call("_activate", true)
		spec.call("_step", 1)
	if OS.has_environment("MB_SAMPLES"):
		for e in _effects():
			e.samples = int(OS.get_environment("MB_SAMPLES"))
	var prof := MotionBlurProfiler.new()
	prof.print_every = 1e9   # we report ourselves
	root.add_child(prof)
	var sums := {true: {}, false: {}}
	var on := true
	var elapsed := 0.0
	while elapsed < total:
		MotionBlurEffect.set_user_settings(on)
		var b0 := Time.get_ticks_msec()
		# skip the first 0.5 s of a block (state change settles)
		while Time.get_ticks_msec() - b0 < 500:
			await process_frame
		prof.reset()
		while Time.get_ticks_msec() - b0 < int(block * 1000.0):
			await process_frame
		var r := prof.flush()
		for k in r:
			if r[k] is float:
				var s: Array = sums[on].get(k, [0.0, 0])
				s[0] += r[k]
				s[1] += 1
				sums[on][k] = s
		elapsed += block
		on = not on
	MotionBlurEffect.set_user_settings(true)
	for state in [true, false]:
		var line := {}
		for k in sums[state]:
			line[k] = snappedf(sums[state][k][0] / sums[state][k][1], 0.001)
		print("MB_PROFILE %s %s" % ["ON " if state else "OFF", JSON.stringify(line)])
	var on_gpu: float = sums[true].get("frame_gpu_ms", [0.0, 1])[0] / sums[true].get("frame_gpu_ms", [0.0, 1])[1]
	var off_gpu: float = sums[false].get("frame_gpu_ms", [0.0, 1])[0] / sums[false].get("frame_gpu_ms", [0.0, 1])[1]
	print("MB_PROFILE frame GPU delta (on - off): %.3f ms" % (on_gpu - off_gpu))
	quit()


func _effects() -> Array:
	var out := []
	for we in root.find_children("*", "WorldEnvironment", true, false):
		if we.compositor:
			for e in we.compositor.compositor_effects:
				if e is MotionBlurEffect:
					out.append(e)
	return out
