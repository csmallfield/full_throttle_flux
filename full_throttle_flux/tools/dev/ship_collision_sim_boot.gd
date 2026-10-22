extends SceneTree
## Bootstrap for ship_collision_sim.gd (typed script, loaded after autoloads exist).
func _initialize() -> void:
	await process_frame
	var scr = load("res://tools/dev/ship_collision_sim.gd")
	if scr == null or not scr.can_instantiate():
		push_error("ship_collision_sim.gd failed to load")
		quit(1)
		return
	var d: Node = scr.new()
	d.name = "ShipCollisionSim"
	root.add_child(d)
