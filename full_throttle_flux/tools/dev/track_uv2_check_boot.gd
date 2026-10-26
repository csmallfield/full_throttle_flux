extends SceneTree
## Boot for track_uv2_check.gd (-s scripts compile before autoloads exist).
##   godot --headless --path . -s res://tools/dev/track_uv2_check_boot.gd


func _initialize() -> void:
	var n := Node.new()
	n.set_script(load("res://tools/dev/track_uv2_check.gd"))
	root.add_child.call_deferred(n)
