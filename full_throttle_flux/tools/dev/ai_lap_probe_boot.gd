extends SceneTree
## Bootstrap for ai_lap_probe.gd (typed script, loaded after autoloads exist).
func _initialize() -> void:
	await process_frame
	var d: Node = load("res://tools/dev/ai_lap_probe.gd").new()
	d.name = "AILapProbe"
	root.add_child(d)
