extends SceneTree
## Boot for judder_probe.gd (-s scripts compile before autoloads exist).
##   godot --path . -s res://tools/dev/judder_probe_boot.gd


func _initialize() -> void:
	var n := Node.new()
	n.set_script(load("res://tools/dev/judder_probe.gd"))
	root.add_child.call_deferred(n)
