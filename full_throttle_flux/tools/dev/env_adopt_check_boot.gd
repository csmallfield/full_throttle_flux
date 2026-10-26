extends SceneTree
## Boot for env_adopt_check.gd (-s scripts compile before autoloads exist).
##   godot --headless --path . -s res://tools/dev/env_adopt_check_boot.gd


func _initialize() -> void:
	var n := Node.new()
	n.set_script(load("res://tools/dev/env_adopt_check.gd"))
	root.add_child.call_deferred(n)
