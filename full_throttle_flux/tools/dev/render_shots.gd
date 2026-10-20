extends SceneTree
## Renders race-camera (or free) shots of a track to PNG -- for judging
## environment / post-effect changes from the chase camera.
## usage: godot --path . -s res://tools/dev/render_shots.gd -- <shots.json> <outdir> [track_scene]
## shots.json: list of {name, d (track distance -> chase cam behind a ship on the
## trained racing line) | side_d+lat+h+ahead | pos+target, fov, preset, sky{}, far, settle}
## Env: SHOTS_NO_MSAA=1 (needed on lavapipe/software Vulkan: MSAA depth won't resolve).
var cfg := {}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var shots: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var outdir: String = args[1]
	DirAccess.make_dir_recursive_absolute(outdir)
	var track_path := "res://scenes/tracks/test_circuit_3_live.tscn"
	if args.size() > 2 and args[2] != "":
		track_path = args[2]
	var ps: PackedScene = load(track_path)
	if ps == null:
		push_error("cannot load " + track_path)
		quit(1)
		return
	var track: Node3D = ps.instantiate()
	root.add_child(track)
	var cam := Camera3D.new()
	cam.far = 4000.0   # Camera3D default, same as AGCamera2097
	cam.near = 0.3
	root.add_child(cam)
	cam.make_current()
	var ship: Node3D = null
	if FileAccess.file_exists("res://scenes/red_yellowmodel.tscn"):
		ship = load("res://scenes/red_yellowmodel.tscn").instantiate()
		root.add_child(ship)
	await process_frame
	var h := TrackSplineHelper.new(track)
	var kit := UtopiaKit.new(track)
	var rx := kit.road_xf
	var line_path: String = "res://resources/ai_data/%s_default_racer_trained_line.tres" % track_path.get_file().get_basename()
	var line: BakedRacingLine = load(line_path)
	var L := h.total_length
	var skyctl: Node = track.find_child("SkyController", true, false)
	if OS.has_environment("SHOTS_NO_MSAA"):
		root.msaa_3d = Viewport.MSAA_DISABLED
	for shot in shots:
		var name: String = shot.get("name", "shot")
		if shot.has("preset") and skyctl:
			skyctl.apply_preset(shot["preset"])
		if shot.has("rays"):
			var we: WorldEnvironment = track.find_child("WorldEnvironment", true, false)
			for e in we.compositor.compositor_effects:
				if e is UtopiaGodRays:
					for k in shot["rays"]:
						e.set(k, shot["rays"][k])
		if shot.has("sky") and skyctl:
			for k in shot["sky"]:
				skyctl.set(k, shot["sky"][k])
		if shot.has("side_d"):
			# trackside camera in the road frame: lat/h at d, looking at d+ahead
			var d0: float = shot["side_d"]
			var f0 := kit.frame(d0)
			var cp := kit.center(d0) + f0.x * float(shot.get("lat", 0.0)) + f0.y * float(shot.get("h", 4.0))
			var d1 := d0 + float(shot.get("ahead", 40.0))
			var f1 := kit.frame(d1)
			var tp := kit.center(d1) + f1.x * float(shot.get("tlat", 0.0)) + f1.y * float(shot.get("th", 3.0))
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = shot.get("fov", 60.0)
			cam.look_at_from_position(cp, tp, f0.y)
			if ship: ship.visible = false
		elif shot.has("d"):
			var d: float = fposmod(float(shot["d"]), L)
			var o := d / L
			var lat: float = shot.get("lat", line.get_lateral_at(o))
			var c := rx * h.spline_offset_to_world(o)
			var t := (rx.basis * h.get_tangent_at_offset(o)).normalized()
			var u := (rx.basis * h.get_up_at_offset(o, true)).normalized()
			var r := t.cross(u).normalized()
			# ship heading: blend toward a point a little ahead on the line (approx velocity dir)
			var o2 := fposmod(d + 6.0, L) / L
			var p2 := rx * (h.spline_offset_to_world(o2) + (h.get_tangent_at_offset(o2).cross(h.get_up_at_offset(o2, true)).normalized()) * line.get_lateral_at(o2))
			var p := c + r * lat
			var fwd := (p2 - p).normalized()
			var ship_pos := p + u * 4.2
			var ratio: float = shot.get("ratio", 0.85)
			var back: float = shot.get("back", 7.0 + 3.4 * ratio)
			var up_h: float = shot.get("height", 2.6 + 0.7 * ratio)
			var cam_pos := ship_pos - fwd * back + u * up_h
			var aim := ship_pos + fwd * 9.0 + u * 1.0
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = shot.get("fov", 74.0 + 10.0 * ratio)
			cam.look_at_from_position(cam_pos, aim, u)
			if ship:
				ship.visible = shot.get("ship", true)
				ship.scale = Vector3.ONE * 1.808
				ship.global_transform = Transform3D(Basis.looking_at(fwd, u), ship_pos)
				ship.scale = Vector3.ONE * 1.808
		else:
			if ship: ship.visible = false
			var pos := Vector3(shot["pos"][0], shot["pos"][1], shot["pos"][2])
			var tgt := Vector3(shot["target"][0], shot["target"][1], shot["target"][2])
			cam.fov = shot.get("fov", 60.0)
			if shot.get("ortho", false):
				cam.projection = Camera3D.PROJECTION_ORTHOGONAL
				cam.size = shot.get("size", 1600.0)
			else:
				cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.look_at_from_position(pos, tgt, Vector3(0, 0, -1) if shot.get("ortho", false) else Vector3.UP)
		cam.far = float(shot.get("far", 4000.0))
		for i in range(int(shot.get("settle", 4))):
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png(outdir.path_join(name + ".png"))
		print("saved ", name)
	quit()
