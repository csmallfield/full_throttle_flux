extends SceneTree
## Boot for preview_shots.gd (-s scripts compile before autoloads exist).


func _initialize() -> void:
	var n := Node.new()
	n.set_script(load("res://tools/track_builder/preview_shots.gd"))
	root.add_child.call_deferred(n)
