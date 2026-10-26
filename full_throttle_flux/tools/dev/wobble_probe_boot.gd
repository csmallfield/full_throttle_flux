extends SceneTree
## Bootstrap for wobble_probe.gd (typed script, loaded after autoloads exist).
func _initialize() -> void:
	await process_frame
	var d: Node = load("res://tools/dev/wobble_probe.gd").new()
	d.name = "WobbleProbe"
	root.add_child(d)
