extends SceneTree
## Renders MOVING race-camera shots, for judging motion blur (a static frame
## has zero velocity, so render_shots.gd can't show it).
## Each shot flies the chase camera and the ship along the trained racing line
## for `frames` frames before capturing, so the velocity buffer holds real
## camera + object motion.
##
## usage (lavapipe; not --headless, it has no renderer):
##   SHOTS_NO_MSAA=1 xvfb-run -a -s "-screen 0 1920x1080x24" \
##     godot --path . -s res://tools/dev/render_motion_shots.gd -- <shots.json> <outdir> [track_scene]
## shots.json: list of
##   {name, d, speed=120 (units/s), frames=4, dt=1/60, ratio=0.85 (camera speed pose),
##    variants=["off","on"] ("on", "off", "noship" = off with every ship hidden,
##      "mask" = ships only, flat white on black, for mb_metrics.py),
##    mb={MotionBlurEffect overrides}, speed_ratio=1.0 (drives the speed fade),
##    ai=[{lat, ahead, speed_delta}] AI ships (ahead/lat relative to the player),
##    render_hz / physics_hz: ship moves only on physics ticks, camera every
##      frame (shows what the effect does to the ship above 60 Hz without
##      physics interpolation),
##    strafe=[right, up] (units/frame): camera slides sideways instead, ship hidden,
##      prints measured vs expected velocity at the screen centre,
##    sequence=N: save all N frames (ending at d) as <name>_<variant>/NNNN.png,
##    ship_shadow=true, rays={god-ray overrides}, fov, far}
## Output: <outdir>/<name>_<variant>.png, and one "MBSTATS {...}" line per "on"
## render with the effect's read-back stats.
## Env: SHOTS_NO_MSAA=1 (lavapipe can't resolve MSAA depth), SHOTS_SCALE=0.5 for
## a quicker half-res pass.

var track: Node3D
var cam: Camera3D
var ship: Node3D
var ai_ships: Array[Node3D] = []
var h: TrackSplineHelper
var rx: Transform3D
var line: BakedRacingLine
var L := 1.0
var mb: MotionBlurEffect
var rays: CompositorEffect


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var shots: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var outdir: String = args[1]
	DirAccess.make_dir_recursive_absolute(outdir)
	var track_path := "res://scenes/tracks/test_circuit_3_live.tscn"
	if args.size() > 2 and args[2] != "":
		track_path = args[2]
	if OS.has_environment("SHOTS_NO_MSAA"):
		root.msaa_3d = Viewport.MSAA_DISABLED
	if OS.has_environment("SHOTS_SCALE"):
		root.scaling_3d_scale = float(OS.get_environment("SHOTS_SCALE"))
	track = (load(track_path) as PackedScene).instantiate()
	root.add_child(track)
	cam = Camera3D.new()
	cam.near = 0.3
	cam.far = 4000.0
	root.add_child(cam)
	cam.make_current()
	ship = _make_ship()
	await process_frame
	h = TrackSplineHelper.new(track)
	rx = UtopiaKit.new(track).road_xf
	line = load("res://resources/ai_data/%s_default_racer_trained_line.tres" % track_path.get_file().get_basename())
	L = h.total_length
	var we: WorldEnvironment = track.find_child("WorldEnvironment", true, false)
	if we and we.compositor:
		for e in we.compositor.compositor_effects:
			if e is MotionBlurEffect:
				mb = e
			elif e is UtopiaGodRays:
				rays = e
	if mb == null:
		push_error("no MotionBlurEffect on this track's compositor")
		quit(1)
		return
	print("MB effects order: ", we.compositor.compositor_effects.map(func(e): return e.get_script().get_global_name()))
	var defaults := {}
	for p in mb.get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			defaults[p["name"]] = mb.get(p["name"])
	for shot in shots:
		for variant in shot.get("variants", ["off", "on"]):
			for k in defaults:
				mb.set(k, defaults[k])
			for k in shot.get("mb", {}):
				mb.set(k, shot["mb"][k])
			mb.blur_enabled = variant == "on"
			if shot.has("rays") and rays:
				for k in shot["rays"]:
					rays.set(k, shot["rays"][k])
			await _render(shot, variant, outdir)
	quit()


const MASK_LAYER := 1 << 19
var _mm: StandardMaterial3D
var _me: Environment

func _mask_mat() -> StandardMaterial3D:
	if _mm == null:
		_mm = StandardMaterial3D.new()
		_mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mm.albedo_color = Color.WHITE
	return _mm

func _mask_env() -> Environment:
	if _me == null:
		_me = Environment.new()
		_me.background_mode = Environment.BG_COLOR
		_me.background_color = Color.BLACK
		_me.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	return _me


func _make_ship() -> Node3D:
	var s: Node3D = load("res://scenes/red_yellowmodel.tscn").instantiate()
	root.add_child(s)
	return s


## Position/orientation on the trained line at track distance d.
func _line_pose(d: float, lat_extra: float = 0.0) -> Dictionary:
	d = fposmod(d, L)
	var o := d / L
	var lat := line.get_lateral_at(o) + lat_extra
	var c := rx * h.spline_offset_to_world(o)
	var t := (rx.basis * h.get_tangent_at_offset(o)).normalized()
	var u := (rx.basis * h.get_up_at_offset(o, true)).normalized()
	var r := t.cross(u).normalized()
	var o2 := fposmod(d + 6.0, L) / L
	var p2 := rx * (h.spline_offset_to_world(o2) + (h.get_tangent_at_offset(o2).cross(h.get_up_at_offset(o2, true)).normalized()) * (line.get_lateral_at(o2) + lat_extra))
	var p := c + r * lat
	return {"pos": p + u * 4.2, "fwd": (p2 - p).normalized(), "up": u}


func _place(n: Node3D, pose: Dictionary) -> void:
	n.global_transform = Transform3D(Basis.looking_at(pose["fwd"], pose["up"]), pose["pos"])
	n.scale = Vector3.ONE * 1.808


func _render(shot: Dictionary, variant: String, outdir: String) -> void:
	var name: String = shot.get("name", "shot")
	var frames: int = int(shot.get("frames", 4))
	# sequence=N: fly N frames ending at d and save every one of them (after 3
	# warm-up frames) to <outdir>/<name>_<variant>/NNNN.png, for a video
	var seq: int = int(shot.get("sequence", 0))
	var seq_dir := ""
	if seq > 0:
		frames = seq + 3
		seq_dir = outdir.path_join("%s_%s" % [shot.get("name", "shot"), variant])
		DirAccess.make_dir_recursive_absolute(seq_dir)
	var render_hz: float = float(shot.get("render_hz", 60.0))
	var physics_hz: float = float(shot.get("physics_hz", render_hz))
	var dt: float = float(shot.get("dt", 1.0 / render_hz))
	var speed: float = float(shot.get("speed", 120.0))
	var d_end: float = float(shot.get("d", 0.0))
	var ratio: float = float(shot.get("ratio", 0.85))
	var back: float = float(shot.get("back", 7.0 + 3.4 * ratio))
	var up_h: float = float(shot.get("height", 2.6 + 0.7 * ratio))
	var strafe: Array = shot.get("strafe", [])
	MotionBlurEffect.speed_ratio = float(shot.get("speed_ratio", 1.0))
	mb.debug_frame_dt = dt
	cam.fov = float(shot.get("fov", 74.0 + 10.0 * ratio))
	cam.far = float(shot.get("far", 4000.0))
	# AI ships
	var ai_cfg: Array = shot.get("ai", [])
	while ai_ships.size() < ai_cfg.size():
		ai_ships.append(_make_ship())
	for i in range(ai_ships.size()):
		ai_ships[i].visible = i < ai_cfg.size() and variant != "noship"
	ship.visible = strafe.is_empty() and variant != "noship" and bool(shot.get("ship", true))
	# ship_shadow=false keeps ship shadows off the track, so mb_metrics.py's
	# ship mask is the hulls only
	for s in [ship] + ai_ships:
		for g in s.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shot.get("ship_shadow", true) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# "mask": only the ships, flat white on black -> exact hull silhouettes for
	# tools/dev/mb_metrics.py
	var is_mask := variant == "mask"
	for s in [ship] + ai_ships:
		for g in s.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).layers = MASK_LAYER if is_mask else 1
			(g as GeometryInstance3D).material_override = _mask_mat() if is_mask else null
	cam.cull_mask = MASK_LAYER if is_mask else 0xFFFFF
	cam.environment = _mask_env() if is_mask else null

	var t_end := float(frames - 1) * dt
	var base_pose := _line_pose(d_end)
	for i in range(frames):
		var t := float(i) * dt
		var rel := t - t_end   # <= 0, seconds before the captured frame
		if strafe.is_empty():
			# camera follows the continuous ship position; the ship itself only
			# advances on physics ticks
			var cont := _line_pose(d_end + rel * speed)
			var tick_t: float = floorf(t * physics_hz + 1e-4) / physics_hz
			var sp := _line_pose(d_end + (tick_t - t_end) * speed)
			_place(ship, sp)
			var cam_pos: Vector3 = cont["pos"] - cont["fwd"] * back + cont["up"] * up_h
			cam.look_at_from_position(cam_pos, cont["pos"] + cont["fwd"] * 9.0 + cont["up"] * 1.0, cont["up"])
			for a in range(ai_cfg.size()):
				var c: Dictionary = ai_cfg[a]
				var ai_speed := speed * (1.0 + float(c.get("speed_delta", 0.0)))
				var ap := _line_pose(d_end + float(c.get("ahead", 15.0)) + (tick_t - t_end) * ai_speed, float(c.get("lat", 4.0)))
				_place(ai_ships[a], ap)
		else:
			var cam_pos: Vector3 = base_pose["pos"] - base_pose["fwd"] * back + base_pose["up"] * up_h
			cam.look_at_from_position(cam_pos, base_pose["pos"] + base_pose["fwd"] * 9.0 + base_pose["up"] * 1.0, base_pose["up"])
			var steps := float(i - (frames - 1))
			cam.global_position += cam.global_basis.x * float(strafe[0]) * steps + cam.global_basis.y * float(strafe[1]) * steps
		mb.debug_stats = variant == "on" and i == frames - 1 and seq == 0
		await RenderingServer.frame_post_draw
		if seq > 0 and i >= 3:
			root.get_texture().get_image().save_png(seq_dir.path_join("%04d.png" % (i - 3)))
			if (i - 3) % 30 == 0:
				print("seq %s_%s %d/%d" % [name, variant, i - 3, seq])
	if seq > 0:
		return
	var img := root.get_texture().get_image()
	img.save_png(outdir.path_join("%s_%s.png" % [name, variant]))
	print("saved %s_%s" % [name, variant])
	if variant == "on":
		var f0 := Engine.get_frames_drawn()
		var guard := 0
		while (MotionBlurEffect.last_stats.get("frame", -1) as int) < f0 - 1 and guard < 20:
			await RenderingServer.frame_post_draw
			guard += 1
		mb.debug_stats = false
		var s := MotionBlurEffect.last_stats.duplicate()
		s["shot"] = name
		s["hit_distance"] = _center_hit_distance()
		if not strafe.is_empty():
			var z: float = s.get("hit_distance", -1.0)
			var proj := cam.get_camera_projection()
			if z > 0.0:
				# camera slides right by a: the centre point moves left, v = prev - cur > 0
				# camera slides up by b: it moves down on screen (texture y down), v < 0
				s["expected_velocity_uv"] = Vector2(proj[0][0] * float(strafe[0]) / (2.0 * z), -proj[1][1] * float(strafe[1]) / (2.0 * z))
		print("MBSTATS ", JSON.stringify(s))


## Distance along the view axis to whatever the screen centre sees (physics).
func _center_hit_distance() -> float:
	var space := cam.get_world_3d().direct_space_state
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * cam.far)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return -1.0
	return (hit["position"] - from).dot(dir)
