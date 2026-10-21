extends SceneTree
## Bootstrap for jump_sim.gd (v31): a SceneTree script compiles before the
## autoloads exist, so the typed simulator is loaded one frame later.
##   godot --headless --fixed-fps 60 --path . -s res://tools/fork_lab/jump_sim_boot.gd
func _initialize() -> void:
	await process_frame
	var d: Node = load("res://tools/fork_lab/jump_sim.gd").new()
	d.name = "JumpSim"
	root.add_child(d)
