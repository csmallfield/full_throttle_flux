extends SceneTree
## Boot for env_selftest.gd (-s scripts compile before autoloads exist).
##   godot --headless --fixed-fps 60 --path . -s res://tools/env/env_selftest_boot.gd


func _initialize() -> void:
	var n := Node.new()
	n.set_script(load("res://tools/env/env_selftest.gd"))
	root.add_child.call_deferred(n)
