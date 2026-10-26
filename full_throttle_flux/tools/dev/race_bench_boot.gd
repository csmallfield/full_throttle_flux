extends SceneTree
## Boot for race_bench.gd (-s scripts compile before autoloads exist).
##   godot --path . -s res://tools/dev/race_bench_boot.gd


func _initialize() -> void:
	var n := Node.new()
	n.set_script(load("res://tools/dev/race_bench.gd"))
	root.add_child.call_deferred(n)
