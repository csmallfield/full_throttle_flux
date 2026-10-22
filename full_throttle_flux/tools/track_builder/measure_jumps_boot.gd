extends SceneTree
## Boot for measure_jumps.gd (-s scripts compile before autoloads exist).


func _initialize() -> void:
	var n := Node.new()
	n.set_script(load("res://tools/track_builder/measure_jumps.gd"))
	root.add_child.call_deferred(n)
