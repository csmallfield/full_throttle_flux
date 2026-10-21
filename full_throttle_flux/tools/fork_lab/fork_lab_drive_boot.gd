extends SceneTree
## Bootstrap for fork_lab_driver.gd (v31). A SceneTree script is compiled
## before autoloads exist, so the typed driver is loaded one frame later.
##   godot --headless --fixed-fps 60 --path . -s res://tools/fork_lab/fork_lab_drive_boot.gd
func _initialize() -> void:
	await process_frame
	var d: Node = load("res://tools/fork_lab/fork_lab_driver.gd").new()
	d.name = "ForkLabDriver"
	root.add_child(d)
