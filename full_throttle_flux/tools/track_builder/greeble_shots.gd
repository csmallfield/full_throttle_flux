extends Node
## Renders a Track Builder track's greebles from a chase-camera viewpoint at
## each zone (and any extra distances) to PNGs, and prints the scatter stats
## (v36). Needs a display (xvfb-run) and the OpenGL renderer:
##
##   TB_SCENE=res://scenes/tracks/builder_lab.tscn TB_OUT=/tmp/shots \
##     xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 \
##     --path . -s res://tools/track_builder/greeble_shots_boot.gd
##
## Env: TB_AT="d,d,..." extra MainSpline distances; TB_BRANCH="d,..." branch
## distances (first branch); TB_BACK (m behind, default 14), TB_UP (default 5).

const SIZE := Vector2i(1600, 900)

var _cam: Camera3D
var _out := ""
var _scene: Node


func _ready() -> void:
	_out = OS.get_environment("TB_OUT")
	if _out.is_empty():
		_out = "user://greeble_shots"
	DirAccess.make_dir_recursive_absolute(_out)
	var path := OS.get_environment("TB_SCENE")
	if path.is_empty():
		path = "res://scenes/tracks/builder_lab.tscn"
	get_window().size = SIZE
	_scene = (load(path) as PackedScene).instantiate()
	add_child(_scene)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.72)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.52, 0.56)
	if _scene.find_child("WorldEnvironment", true, false) == null:
		add_child(env)
	if _scene.find_child("*Sun*", true, false) == null:
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, 30, 0)
		sun.shadow_enabled = true
		add_child(sun)
	_cam = Camera3D.new()
	_cam.far = 4000.0
	_cam.fov = 70.0
	add_child(_cam)
	_cam.make_current()
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	var g := _scene.get_node_or_null("TrackGreebles") as TrackGreebles
	if g == null:
		print("SHOTS no TrackGreebles in the scene")
		get_tree().quit(1)
		return
	var t0 := Time.get_ticks_usec()
	g.rebuild()
	print("SHOTS rebuild %.1f ms, %d instances, %d zones" % [(Time.get_ticks_usec() - t0) / 1000.0,
			g.instance_total, g.zones.size()])
	var per := {}
	for p in g.placements():
		var k := "%s/%s" % [g.zones[p.zi].label, p.layer]
		per[k] = per.get(k, 0) + 1
	var ks := per.keys()
	ks.sort()
	for k in ks:
		print("SHOTS   %-34s %5d" % [k, per[k]])
	var t1 := Time.get_ticks_usec()
	var bad := g.intrusions()
	print("SHOTS intrusions check %.1f ms: %d" % [(Time.get_ticks_usec() - t1) / 1000.0, bad.size()])
	for b in bad:
		var z: TrackGreebleZone = g.zones[b.zi]
		var rn := "threshold" if b.ri < 0 else z.style.rules[b.ri].mesh.resource_path.get_file()
		print("SHOTS   %s %s ×%d @ %.0f m: %s" % [z.label, rn, b.count, b.d, b.what])
	var back := float(OS.get_environment("TB_BACK")) if OS.get_environment("TB_BACK") != "" else 14.0
	var up := float(OS.get_environment("TB_UP")) if OS.get_environment("TB_UP") != "" else 5.0
	var main := _scene.get_node("MainSpline") as Path3D
	var stops: Array = []
	for z in g.zones:
		if z.path_index == 0:
			stops.append([0, z.from_d + 60.0, z.label])
	for s in OS.get_environment("TB_AT").split(",", false):
		stops.append([0, float(s), "at_%s" % s])
	for s in OS.get_environment("TB_BRANCH").split(",", false):
		stops.append([1, float(s), "branch_%s" % s])
	for st in stops:
		var p: Path3D = main if st[0] == 0 else _scene.get_node(String(g.paths[st[0]]).trim_prefix("../")) as Path3D
		var L := p.curve.get_baked_length()
		var d: float = fposmod(st[1], L) if st[0] == 0 else clampf(st[1], 0.0, L)
		var f := p.global_transform * TrackRoadSegment.frame_at(p.curve, d)
		var fb := p.global_transform * TrackRoadSegment.frame_at(p.curve, fposmod(d - back, L) if st[0] == 0 else maxf(d - back, 0.0))
		var fa := p.global_transform * TrackRoadSegment.frame_at(p.curve, fposmod(d + 40.0, L) if st[0] == 0 else minf(d + 40.0, L))
		var pos := fb.origin + fb.basis.y * up
		var aim := fa.origin + fa.basis.y * 2.0
		_cam.global_transform = Transform3D(Basis.looking_at(aim - pos, fb.basis.y), pos)
		await _shot("%02d_%s_%.0f" % [stops.find(st), String(st[2]).to_snake_case(), d])
	print("SHOTS done -> %s" % ProjectSettings.globalize_path(_out))
	get_tree().quit(0)


func _shot(nm: String) -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, nm])
