extends SceneTree
## Smoke test: launch an AI race, run 20 s, report frames. SMOKE_TRACK=<track_id> env
## e.g. SMOKE_TRACK=test_circuit_5_live godot --path . -s res://tools/dev/race_smoke.gd
func _initialize() -> void:
	await process_frame
	var gm = root.get_node("GameManager")
	gm.select_track_by_id(OS.get_environment("SMOKE_TRACK"))
	if "selected_mode" in gm:
		gm.selected_mode = "race"
	var launcher: Node = load("res://scenes/race_launcher.tscn").instantiate()
	root.add_child(launcher)
	var t0 := Time.get_ticks_msec()
	var frames := 0
	while Time.get_ticks_msec() - t0 < 20000:
		await process_frame
		frames += 1
	print("SMOKE frames=%d in 20s" % frames)
	quit()
