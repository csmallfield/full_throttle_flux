extends SceneTree
## Boot for render_dust.gd (needs a real renderer, see render_trails_boot.gd):
##   godot --path . --resolution 1280x720 --fixed-fps 60 -s res://tools/env/render_dust_boot.gd -- <outdir>


func _initialize() -> void:
	var n := Node.new()
	n.set_script(load("res://tools/env/render_dust.gd"))
	root.add_child.call_deferred(n)
