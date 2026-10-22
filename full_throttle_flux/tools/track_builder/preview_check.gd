extends Node
## Headless check of the Track Builder preview (v34 step 1): evaluates a
## builder scene with and without fairing, times the preview, and prints the
## report plus a curvature-smoothness measure.
##
##   TB_SCENE=res://scenes/tracks/builder_lab.tscn \
##     godot --headless --path . -s res://tools/track_builder/preview_check_boot.gd


func _ready() -> void:
	TrackBuilder.keep_at_runtime = true
	var path := OS.get_environment("TB_SCENE")
	if path.is_empty():
		path = "res://scenes/tracks/builder_lab.tscn"
	var scene := (load(path) as PackedScene).instantiate()
	add_child(scene)
	var tb := scene.find_child("TrackBuilder", true, false) as TrackBuilder
	if tb == null:
		push_error("no TrackBuilder in %s" % path)
		get_tree().quit(1)
		return
	for fair: float in [0.0, tb.fairing_m]:
		tb.fairing_m = fair
		tb.preview()
		print("---- fairing %.0f m ----" % fair)
		print(tb.report)
		print("curvature step: max |Δ lateral g| per metre %.3f, at %.0f m"
				% _jerk(tb))
	print("keys:")
	for k in tb.keys_of("BankKey") + tb.keys_of("WidthKey") + tb.all_keys_of("BoostPadKey"):
		print("  %s d=%.1f off=%.1f %s" % [k.name, k.distance, k.distance_to_track, k.label_text()])
	for p in tb.pad_placements():
		print("  pad %s #%d at %.1f m, %+.1f m sideways" % [p.key.name, p.i + 1, p.s, p.x])
	var prev := tb.get_node_or_null(TrackBuilder.PREVIEW_NAME)
	print("preview children: %d (owner %s)" % [prev.get_child_count() if prev else -1,
			str(prev.owner) if prev else "-"])
	get_tree().quit()


## Largest change in lateral g between neighbouring samples, per metre: the
## jolt hand-set handles cause at control points.
func _jerk(tb: TrackBuilder) -> Array:
	var s := tb.sampler
	var worst := 0.0
	var at := 0.0
	for i in range(1, s.size()):
		var j := absf(tb.lateral_g(i) - tb.lateral_g(i - 1)) / s.step()
		if j > worst:
			worst = j
			at = s.S[i]
	return [worst, at]
