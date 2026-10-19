extends SceneTree
## Dumps the track frame (centre, tangent, up) every 5 m via UtopiaKit to JSON.
## usage: godot --headless --path . -s res://tools/dev/analyze_track.gd -- <track scene> <out json>
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var track: Node3D = load(a[0]).instantiate()
	root.add_child(track)
	await process_frame
	var kit := UtopiaKit.new(track)
	var out := []
	var d := 0.0
	while d < kit.length:
		var c := kit.center(d)
		var f := kit.frame(d)
		var t := kit.tangent(d)
		out.append({"d": d, "c": [c.x, c.y, c.z], "t": [t.x, t.y, t.z], "u": [f.y.x, f.y.y, f.y.z]})
		d += 5.0
	var fa := FileAccess.open(a[1], FileAccess.WRITE)
	fa.store_string(JSON.stringify({"length": kit.length, "frames": out}))
	print("LENGTH ", kit.length)
	quit()
