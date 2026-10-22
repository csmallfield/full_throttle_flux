extends SceneTree
## Boot for builder_tool.gd in build mode (-s scripts compile before autoloads).


func _initialize() -> void:
	var n := Node.new()
	n.set_script(load("res://tools/track_builder/builder_tool.gd"))
	n.set("mode", "build")
	root.add_child.call_deferred(n)
