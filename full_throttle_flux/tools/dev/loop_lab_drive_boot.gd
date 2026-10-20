extends SceneTree
## Bootstrap for loop_lab_driver.gd (v30). A SceneTree script is compiled
## before autoloads exist, so the typed driver is loaded one frame later.
##   godot --headless --fixed-fps 60 --path . -s res://tools/dev/loop_lab_drive_boot.gd
func _initialize() -> void:
	await process_frame
	var d: Node = load("res://tools/dev/loop_lab_driver.gd").new()
	d.name = "LoopLabDriver"
	root.add_child(d)
