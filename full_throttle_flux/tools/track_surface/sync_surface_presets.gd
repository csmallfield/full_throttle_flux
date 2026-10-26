extends SceneTree
## Boot for sync_surface_presets_run.gd (-s scripts compile before autoloads
## exist). What it does is in that file.
##   godot --headless --path . -s res://tools/track_surface/sync_surface_presets.gd


func _initialize() -> void:
	var n := Node.new()
	n.set_script(load("res://tools/track_surface/sync_surface_presets_run.gd"))
	root.add_child.call_deferred(n)
