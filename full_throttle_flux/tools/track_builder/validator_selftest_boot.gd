extends SceneTree
## Boot for validator_selftest.gd (-s scripts compile before autoloads exist).


func _initialize() -> void:
	var n := Node.new()
	n.set_script(load("res://tools/track_builder/validator_selftest.gd"))
	root.add_child.call_deferred(n)
