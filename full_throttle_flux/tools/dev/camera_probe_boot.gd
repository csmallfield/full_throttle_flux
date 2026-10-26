extends SceneTree
## Bootstrap for camera_probe.gd (typed script, loaded after autoloads exist).
func _initialize() -> void:
	await process_frame
	var d: Node = load("res://tools/dev/camera_probe.gd").new()
	d.name = "CameraProbe"
	root.add_child(d)
