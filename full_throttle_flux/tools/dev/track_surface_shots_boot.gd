extends SceneTree
## Boot for track_surface_shots.gd (-s scripts compile before autoloads exist).
##   godot --path . -s res://tools/dev/track_surface_shots_boot.gd


func _initialize() -> void:
	var n := Node.new()
	n.set_script(load("res://tools/dev/track_surface_shots.gd"))
	root.add_child.call_deferred(n)
