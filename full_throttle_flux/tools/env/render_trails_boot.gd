extends SceneTree
## Boot for render_trails.gd. Needs a real renderer (not --headless):
##   godot --path . --resolution 1280x720 --fixed-fps 60 -s res://tools/env/render_trails_boot.gd -- <outdir>
## On software Vulkan (lavapipe) under xvfb-run it works too, slowly.


func _initialize() -> void:
	var n := Node.new()
	n.set_script(load("res://tools/env/render_trails.gd"))
	root.add_child.call_deferred(n)
