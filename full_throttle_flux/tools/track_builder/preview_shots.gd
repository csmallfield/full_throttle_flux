extends Node
## Renders preview overlays of a Track Builder scene to PNGs (v34, for notes
## and review). Needs a display (xvfb-run) and the OpenGL renderer:
##
##   TB_SCENE=res://scenes/tracks/builder_lab.tscn TB_OUT=/tmp/shots \
##     xvfb-run -s "-screen 0 1600x1000x24" godot --rendering-driver opengl3 \
##     --path . -s res://tools/track_builder/preview_shots_boot.gd

const SIZE := Vector2i(1600, 1000)

var _tb: TrackBuilder
var _cam: Camera3D
var _out := ""


func _ready() -> void:
	TrackBuilder.keep_at_runtime = true
	_out = OS.get_environment("TB_OUT")
	if _out.is_empty():
		_out = "user://track_builder_shots"
	DirAccess.make_dir_recursive_absolute(_out)
	var path := OS.get_environment("TB_SCENE")
	if path.is_empty():
		path = "res://scenes/tracks/builder_lab.tscn"
	get_window().size = SIZE
	var scene := (load(path) as PackedScene).instantiate()
	add_child(scene)
	_tb = scene.find_child("TrackBuilder", true, false) as TrackBuilder
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.09, 0.11)
	add_child(env)
	_cam = Camera3D.new()
	_cam.far = 20000.0
	add_child(_cam)
	_cam.make_current()
	_run.call_deferred()


func _run() -> void:
	_tb.ribbon = true
	_tb.preview()
	var bounds := _bounds()
	var centre := bounds.get_center()
	# Top-down views of the whole track, one per overlay.
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = maxf(bounds.size.x * SIZE.y / float(SIZE.x), bounds.size.z) * 1.12
	_cam.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD),
			centre + Vector3.UP * 3000.0)
	for o: int in [TrackBuilder.Overlay.BANK, TrackBuilder.Overlay.LATERAL_G,
			TrackBuilder.Overlay.WIDTH, TrackBuilder.Overlay.FAIRING]:
		_tb.overlay = o
		_tb.preview()
		await _shot("top_%s" % TrackBuilder.Overlay.keys()[o].to_lower())
	# Oblique close-up on a bank key and the widened stretch.
	_tb.overlay = TrackBuilder.Overlay.BANK
	_tb.preview()
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 55.0
	var f := _tb.sampler.frame_at(1650.0)
	var eye := f.origin - f.basis.z * -260.0 + f.basis.x * -180.0 + Vector3.UP * 140.0
	_cam.global_transform = Transform3D(Basis.looking_at(f.origin + (-f.basis.z) * 150.0 - eye, Vector3.UP), eye)
	await _shot("oblique_keys")
	# The built road (if the scene has been built), ribbon off: a chase-height
	# view into the widened corner and one into the narrow chicane.
	if get_tree().root.find_child("MainSpline", true, false):
		_tb.ribbon = false
		_tb.label_every = 0.0
		_tb.preview()
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, 210, 0)
		sun.shadow_enabled = true
		add_child(sun)
		var we := get_tree().root.find_child("WorldEnvironment", true, false) as WorldEnvironment
		if we:
			we.compositor = null    # motion blur needs Forward+; this is OpenGL
		for at: Array in [[1640.0, "road_widened"], [3420.0, "road_narrow"], [2520.0, "road_banked"]]:
			var fr := _tb.sampler.frame_at(at[0])
			var ahead := _tb.sampler.frame_at(at[0] + 160.0)
			var cam_pos := fr.origin + fr.basis.y * 14.0
			_cam.global_transform = Transform3D(Basis.looking_at(ahead.origin + ahead.basis.y * 2.0 - cam_pos, fr.basis.y), cam_pos)
			await _shot(at[1])
	print("shots written to %s" % ProjectSettings.globalize_path(_out))
	get_tree().quit()


func _shot(name: String) -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out.path_join(name + ".png"))


func _bounds() -> AABB:
	var s := _tb.sampler
	var b := AABB(s.P[0], Vector3.ZERO)
	for p in s.P:
		b = b.expand(p)
	return b
