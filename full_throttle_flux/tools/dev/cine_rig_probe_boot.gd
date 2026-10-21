extends SceneTree
## Bootstrap for cine_rig_probe.gd (typed script, loaded after autoloads exist).
func _initialize() -> void:
	await process_frame
	var d: Node = load("res://tools/dev/cine_rig_probe.gd").new()
	d.name = "CineRigProbe"
	root.add_child(d)
