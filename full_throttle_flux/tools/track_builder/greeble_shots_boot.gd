extends SceneTree
## Bootstrap for greeble_shots.gd (typed script, loaded after autoloads exist).
func _initialize() -> void:
	TrackBuilder.keep_at_runtime = false
	await process_frame
	var d: Node = load("res://tools/track_builder/greeble_shots.gd").new()
	d.name = "GreebleShots"
	root.add_child(d)
