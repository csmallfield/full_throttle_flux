extends SceneTree
## Boot for measure_circuits.gd (-s scripts compile before autoloads exist).


func _initialize() -> void:
	var n := Node.new()
	n.set_script(load("res://tools/track_builder/measure_circuits.gd"))
	root.add_child.call_deferred(n)
