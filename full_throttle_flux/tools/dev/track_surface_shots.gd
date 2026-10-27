extends Node
## v38: screenshots and aliasing measurements of the track surface on a
## builder track, against the v37 grid. Run on the real GPU, windowed:
##
##   godot --path . -s res://tools/dev/track_surface_shots_boot.gd
##
## For each distance in TS_D and each pose (chase: 9 m behind, 3.2 m up,
## looking 25 m ahead; low: 1.3 m up looking 200 m ahead; top: 30 m up) it
## renders the road three ways:
##   grid     road segments on the v37 filtered grid (what v37 shipped)
##   surface  the v38 track surface
##   average  the surface with every pattern forced to its average
##            (aa_fade_px huge): the reference for "no brightening"
## and the surface's debug views (s/t, bands, panels, filter level) for the
## chase pose. EnvSurfaces.adopt() runs first, as in a race (clear weather).
##
## Measurements, per pose and look (TSMETRIC lines + track_surface.csv), on
## ROAD pixels only (where the grid and average renders differ):
##   flicker  mean |luma change| between frames while the camera creeps
##            forward TS_CREEP metres a frame (sub-pixel far away): a filtered
##            pattern changes smoothly, an aliased one flickers. All road
##            pixels, and the far road: the top fifth of the road's rows,
##            toward the horizon, in the centre half of the columns (at the
##            sides those rows hold the raised lips right beside the camera).
##   far / near  mean luma of the far road and the near road (bottom third);
##            compare surface with average: equal far luma = no brightening
##            from aliasing (what's left is real Fresnel).
##
## Env: TS_TRACK (builder_lab), TS_D distances (default "200,850,2400"),
##   TS_RES (1920x1080), TS_OUT (user://track_surface), TS_FRAMES (16),
##   TS_CREEP (0.012), TS_FOV (80), TS_POSES (default "chase,low,top"),
##   TS_PARAMS "name=value,..." surface material overrides (A/B a module,
##   e.g. "light_energy=0,led_energy=0"), TS_TIER 0|1 (default: as saved),
##   TS_FREEZE 1 (default) stops the living lights (phase 5) while measuring:
##   moving lights are real motion, which the flicker measure can't tell from
##   aliasing. 0 measures them moving.
##   TS_GLOBALS "name=value,..." global shader parameters, e.g. weather:
##   "env_wetness=0.8,env_precip=0.5" (there's no EnvironmentState here).
##   TS_PATH the path the poses follow (default MainSpline; e.g. BranchSpline
##   to drive a branch through its junctions), TS_DEBUG_POSES the poses that
##   also save the debug views (default "chase"). Pose "over": 70 m up, 50 m
##   behind, looking 60 m ahead (a whole junction in view).
## Junction roads (TrackJunction, v38) switch looks with the road segments.

const GRID_MATERIAL := "res://shaders/resources/grid_material.tres"
const LOOKS := ["grid", "surface", "average"]
const POSES := "chase,low,top"
const VIEW_NAMES := ["", "st", "bands", "panels", "filter", "zones", "wear"]

var out := ""
var cam: Camera3D
var path: Path3D
var csv := PackedStringArray(["track,d,pose,look,flicker_road,flicker_far,far_luma,near_luma"])
## Road mask for the current pose (1 = road pixel) and its far / near rows.
var mask := PackedByteArray()
var far_rows := Vector2i()
var near_rows := Vector2i()
var far_cols := Vector2i()
## Every road material (one per path with a TrackSurface).
var surf_mats: Array[ShaderMaterial] = []
## CSG node -> its v38 override (the circuits), to restore after "grid".
var csg_mats := {}


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d


func _ready() -> void:
	out = _env("TS_OUT", "user://track_surface")
	DirAccess.make_dir_recursive_absolute(out)
	var res := _env("TS_RES", "1920x1080").split("x")
	get_window().size = Vector2i(int(res[0]), int(res[1]))
	_run.call_deferred()


func _run() -> void:
	var track_id := _env("TS_TRACK", "builder_lab")
	var track := (load("res://scenes/tracks/%s.tscn" % track_id) as PackedScene).instantiate()
	add_child(track)
	path = track.find_child(_env("TS_PATH", "MainSpline"), true, false) as Path3D
	var main := track.find_child("MainSpline", true, false) as Path3D
	cam = Camera3D.new()
	cam.far = 4000.0
	cam.near = 0.3
	cam.fov = float(_env("TS_FOV", "80"))
	add_child(cam)
	cam.make_current()
	await get_tree().process_frame
	var gs := get_node_or_null("/root/GraphicsSettings")
	if gs:
		gs.set_surface_view(0)
	var segs: Array[GeometryInstance3D] = []
	var surface_mat: ShaderMaterial = null
	for n in track.find_children("*", "TrackRoadSegment", true, false):
		var seg := n as TrackRoadSegment
		var sm := seg.mesh_instance().mesh.surface_get_material(0) as ShaderMaterial
		if sm and (sm.shader.resource_path == EnvSurfaces.SURFACE_SHADER_PATH
				or sm.shader.resource_path == EnvSurfaces.WALL_SHADER_PATH):
			segs.append(seg.mesh_instance())
			if sm.shader.resource_path == EnvSurfaces.SURFACE_SHADER_PATH:
				surface_mat = sm
			# One material per path once TrackSurface has run (v38 phase 3).
			if not surf_mats.has(sm):
				surf_mats.append(sm)
	for n in track.find_children("*", "TrackJunction", true, false):
		for c in n.get_children(true):
			var mi := c as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var sm := mi.mesh.surface_get_material(0) as ShaderMaterial
			if sm and sm.shader.resource_path == EnvSurfaces.SURFACE_SHADER_PATH:
				segs.append(mi)
				if not surf_mats.has(sm):
					surf_mats.append(sm)
	# The circuits (phase 5b): CSG road and walls on v38 overrides.
	for n in track.find_children("*", "CSGPolygon3D", true, false):
		var ov := (n as GeometryInstance3D).material_override as ShaderMaterial
		if ov and ov.shader and (ov.shader.resource_path == EnvSurfaces.SURFACE_SHADER_PATH
				or ov.shader.resource_path == EnvSurfaces.WALL_SHADER_PATH):
			segs.append(n as GeometryInstance3D)
			csg_mats[n] = ov
			if not surf_mats.has(ov):
				surf_mats.append(ov)
			if ov.shader.resource_path == EnvSurfaces.SURFACE_SHADER_PATH:
				surface_mat = ov
	if surface_mat == null:
		print("TSMETRIC no track surface on %s" % track_id)
		get_tree().quit(1)
		return
	EnvSurfaces.adopt(track, main)
	if _env("TS_FREEZE", "1") == "1":
		_set_all("light_flow", 0.0)
		_set_all("light_pulse_speed", 0.0)
	for kv in _env("TS_PARAMS", "").split(",", false):
		var p := kv.split("=")
		_set_all(p[0].strip_edges(), float(p[1]))
	for kv in _env("TS_GLOBALS", "").split(",", false):
		var p := kv.split("=")
		RenderingServer.global_shader_parameter_set(p[0].strip_edges(), float(p[1]))
	if gs and _env("TS_TIER", "") != "":
		gs.set_surface_tier(int(_env("TS_TIER", "1")))
	var grid_mat := load(GRID_MATERIAL) as Material
	# Unset parameters read back as null: the shader's default.
	var fade_v = surface_mat.get_shader_parameter("aa_fade_px")
	var fade_px: float = fade_v if fade_v != null else 2.0
	print("TSMETRIC %s, %s, %s" % [RenderingServer.get_video_adapter_name(), track_id, get_window().size])
	for ds in _env("TS_D", "200,850,2400").split(",", false):
		var d := float(ds)
		for pose in _env("TS_POSES", POSES).split(",", false):
			await _build_mask(segs, grid_mat, surface_mat, d, pose)
			for look in LOOKS:
				_set_look(segs, grid_mat, surface_mat, look, fade_px)
				await _measure(track_id, d, pose, look)
			if pose in _env("TS_DEBUG_POSES", "chase").split(","):
				_set_all("aa_fade_px", fade_px)
				for v in range(1, VIEW_NAMES.size()):
					if gs:
						gs.set_surface_view(v)
					_place(d, pose, 0.0)
					var img := await _grab(4)
					img.save_png("%s/%s_%04d_%s_debug_%s.png" % [out, track_id, int(d), pose, VIEW_NAMES[v]])
				if gs:
					gs.set_surface_view(0)
	var f := FileAccess.open("%s/track_surface.csv" % out, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(csv) + "\n")
	print("TSMETRIC done -> %s" % ProjectSettings.globalize_path(out))
	get_tree().quit(0)


func _set_all(param: String, value: Variant) -> void:
	for m in surf_mats:
		m.set_shader_parameter(param, value)


func _set_look(segs: Array[GeometryInstance3D], grid_mat: Material, surface_mat: ShaderMaterial,
		look: String, fade_px: float) -> void:
	for gi in segs:
		if csg_mats.has(gi):
			# Circuits: "grid" = the CSG's own (weather-wrapped) grid material.
			gi.material_override = null if look == "grid" else csg_mats[gi]
		else:
			(gi as MeshInstance3D).set_surface_override_material(0, grid_mat if look == "grid" else null)
	_set_all("aa_fade_px", 1e6 if look == "average" else fade_px)


## Road pixels: where the grid and the averaged surface differ.
func _build_mask(segs: Array[GeometryInstance3D], grid_mat: Material, surface_mat: ShaderMaterial,
		d: float, pose: String) -> void:
	var fade_v = surface_mat.get_shader_parameter("aa_fade_px")
	var fade_px: float = fade_v if fade_v != null else 2.0
	_place(d, pose, 0.0)
	_set_look(segs, grid_mat, surface_mat, "grid", fade_px)
	var a := _luma(await _grab(4))
	_set_look(segs, grid_mat, surface_mat, "average", fade_px)
	var img := await _grab(4)
	var b := _luma(img)
	_set_look(segs, grid_mat, surface_mat, "surface", fade_px)
	var w := img.get_width()
	var h := img.get_height()
	mask.resize(a.size())
	var top := h
	var bottom := 0
	for i in a.size():
		var on := absf(a[i] - b[i]) > 0.01
		mask[i] = 1 if on else 0
		if on:
			top = mini(top, i / w)
			bottom = maxi(bottom, i / w)
	var span := maxi(bottom - top, 1)
	far_rows = Vector2i(top, top + maxi(span / 5, 1))
	near_rows = Vector2i(bottom - span / 3, bottom + 1)
	far_cols = Vector2i(w / 4, w * 3 / 4)


func _measure(track_id: String, d: float, pose: String, look: String) -> void:
	var frames := int(_env("TS_FRAMES", "16"))
	var creep := float(_env("TS_CREEP", "0.012"))
	var prev: PackedFloat32Array
	var sum_all := 0.0
	var sum_far := 0.0
	var far_l := 0.0
	var near_l := 0.0
	for i in frames:
		_place(d, pose, creep * i)
		var img := await _grab(4 if i == 0 else 1)
		if i == 0:
			img.save_png("%s/%s_%04d_%s_%s.png" % [out, track_id, int(d), pose, look])
		var l := _luma(img)
		var w := img.get_width()
		far_l += _band_mean(l, w, far_rows, far_cols)
		near_l += _band_mean(l, w, near_rows, Vector2i(0, w))
		if i > 0:
			sum_all += _diff(l, prev, w, Vector2i(0, img.get_height()), Vector2i(0, w))
			sum_far += _diff(l, prev, w, far_rows, far_cols)
		prev = l
	var row := [track_id, int(d), pose, look, sum_all / (frames - 1), sum_far / (frames - 1),
			far_l / frames, near_l / frames]
	csv.append(",".join(row.map(func(x): return str(x))))
	print("TSMETRIC %-12s d %5d  %-6s %-8s flicker %.5f (far %.5f)  luma far %.4f near %.4f" % row)


## Camera for `pose` at distance `d` along MainSpline, `creep` metres further on.
func _place(d: float, pose: String, creep: float) -> void:
	var curve := path.curve
	var at := func(x: float) -> Transform3D:
		return path.global_transform * TrackRoadSegment.frame_at(curve, fposmod(x, curve.get_baked_length()))
	var here: Transform3D = at.call(d + creep)
	var pos: Vector3
	var target: Vector3
	match pose:
		"chase":
			pos = (at.call(d + creep - 9.0) as Transform3D).origin + here.basis.y * 3.2
			target = (at.call(d + creep + 25.0) as Transform3D).origin + here.basis.y * 1.0
		"over":
			pos = here.origin + here.basis.y * 70.0 + here.basis.z * 50.0
			target = here.origin - here.basis.z * 60.0
		"low":
			pos = here.origin + here.basis.y * 1.3
			target = (at.call(d + creep + 200.0) as Transform3D).origin + here.basis.y * 1.3
		_:
			pos = here.origin + here.basis.y * 30.0 + here.basis.z * 10.0
			target = here.origin - here.basis.z * 10.0
	cam.look_at_from_position(pos, target, here.basis.y)


func _grab(settle: int) -> Image:
	for i in settle:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _luma(img: Image) -> PackedFloat32Array:
	img.convert(Image.FORMAT_RGB8)
	var data := img.get_data()
	var l := PackedFloat32Array()
	l.resize(data.size() / 3)
	for i in l.size():
		l[i] = (0.2126 * data[i * 3] + 0.7152 * data[i * 3 + 1] + 0.0722 * data[i * 3 + 2]) / 255.0
	return l


## Mean luma of the road pixels in rows [rows.x, rows.y), columns [cols.x, cols.y).
func _band_mean(l: PackedFloat32Array, w: int, rows: Vector2i, cols: Vector2i) -> float:
	var s := 0.0
	var n := 0
	for i in range(rows.x * w, mini(rows.y * w, l.size())):
		if mask[i] and i % w >= cols.x and i % w < cols.y:
			s += l[i]
			n += 1
	return s / maxf(n, 1)


## Mean |a - b| over the road pixels in rows [rows.x, rows.y), columns [cols.x, cols.y).
func _diff(a: PackedFloat32Array, b: PackedFloat32Array, w: int, rows: Vector2i, cols: Vector2i) -> float:
	var s := 0.0
	var n := 0
	for i in range(rows.x * w, mini(rows.y * w, a.size())):
		if mask[i] and i % w >= cols.x and i % w < cols.y:
			s += absf(a[i] - b[i])
			n += 1
	return s / maxf(n, 1)
