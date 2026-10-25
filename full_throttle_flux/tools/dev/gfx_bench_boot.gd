extends SceneTree
## Bootstrap for gfx_bench.gd (typed script, loaded after autoloads exist).
func _initialize() -> void:
	await process_frame
	var d: Node = load("res://tools/dev/gfx_bench.gd").new()
	d.name = "GfxBench"
	root.add_child(d)
