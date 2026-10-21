extends SceneTree
## Boot for preview_check.gd (-s scripts compile before autoloads exist).


func _initialize() -> void:
	var n := Node.new()
	n.set_script(load("res://tools/track_builder/preview_check.gd"))
	root.add_child.call_deferred(n)
