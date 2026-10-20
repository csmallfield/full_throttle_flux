extends SceneTree
## Bootstrap for ai_race_probe.gd (typed script, loaded after autoloads exist).
func _initialize() -> void:
	await process_frame
	var d: Node = load("res://tools/dev/ai_race_probe.gd").new()
	d.name = "AIRaceProbe"
	root.add_child(d)
