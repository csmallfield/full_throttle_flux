extends Node
## Surface Lab: takes the tutorial's screenshots (docs/surface-lab), so they can
## be retaken when the lab changes. Every edit is undone and nothing is saved.
##
##   LAB_TOUR=<absolute folder> godot --path full_throttle_flux res://tools/surface_lab/surface_lab.tscn
##
## Add LAB_TOUR_ONLY=<prefix> to retake only the shots whose names start with it.

const SCENE_W := 1280
const POSE := 850.0
## Metres behind the view point, above the road, and how far ahead it looks.
const POSE_BACK := 16.0
const POSE_UP := 7.5
const POSE_AHEAD := 70.0

var lab: Node
var doc: RefCounted
var out := ""
var only := ""


func _ready() -> void:
	out = OS.get_environment("LAB_TOUR")
	only = OS.get_environment("LAB_TOUR_ONLY")
	DirAccess.make_dir_recursive_absolute(out)
	doc = lab.doc
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Saves the frame, or `area` of it. UI crops stay full size; 3D views shrink.
func _shot(name: String, area := Rect2(), settle := 10) -> void:
	if only != "" and not name.begins_with(only):
		return
	await _frames(settle)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.has_mipmaps():
		img.clear_mipmaps()
	if area.size != Vector2.ZERO:
		img = img.get_region(Rect2i(area))
	elif not lab.ui.visible:
		img.resize(SCENE_W, SCENE_W * img.get_height() / img.get_width(), Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGB8)
	var err := img.save_jpg("%s/%s.jpg" % [out, name], 0.86)
	print("LABTOUR %s %s" % [name, error_string(err)])


## A raised view: more of the road's lanes than the chase pose shows.
func _pose(d: float = POSE) -> void:
	lab.cam.set_mode(0)
	lab.cam.jump(d)
	var sp: Path3D = lab.spline
	var L: float = sp.curve.get_baked_length()
	var at := func(x: float) -> Transform3D:
		return sp.global_transform * TrackRoadSegment.frame_at(sp.curve, fposmod(x, L))
	var here: Transform3D = at.call(d)
	var pos: Vector3 = (at.call(d - POSE_BACK) as Transform3D).origin + here.basis.y * POSE_UP
	var target: Vector3 = (at.call(d + POSE_AHEAD) as Transform3D).origin
	lab.cam.cam.global_transform = Transform3D(Basis.looking_at(target - pos, here.basis.y), pos)


func _tab(name: String) -> void:
	lab.tabs.current_tab = lab.tabs.get_tab_idx_from_control(lab.tabs.get_node(name))
	await _frames(3)


func _side_rect() -> Rect2:
	return lab.ui.get_child(1).get_global_rect()


func _reset() -> void:
	doc.restore(doc.saved)
	doc.commit()
	doc.flush()
	lab._refresh_all()


## Two pictures of the road: as saved, then with `edit` applied.
func _before_after(name: String, edit: Callable, setup := Callable()) -> void:
	lab.ui.visible = false
	if setup.is_valid():
		setup.call()
		doc.flush()
	await _shot(name + "_before")
	edit.call()
	doc.flush()
	await _shot(name + "_after")
	_reset()


func _open_group(rows: Control, title: String) -> void:
	for c in rows.get_children():
		if c is Button and String(c.text).ends_with(title):
			var next: Control = rows.get_child(c.get_index() + 1)
			if not next.visible:
				c.pressed.emit()
			c.grab_focus()
			c.release_focus()
			return


func _collapse_all(rows: Control) -> void:
	for c in rows.get_children():
		if c is Button:
			var next: Control = rows.get_child(c.get_index() + 1)
			if next.visible:
				c.pressed.emit()


func _run() -> void:
	lab.follow_camera = false
	lab.follow_box.set_pressed_no_signal(true)
	lab.follow_camera = true
	lab.cam.glide_paused = true
	_pose()
	await _frames(30)

	# The whole screen.
	await _select_grate()
	await _shot("overview")
	await _shot("topbar", lab.ui.get_child(0).get_global_rect())
	await _shot("section", lab.section.get_global_rect())
	await _shot("rhythm", lab.rhythm.get_global_rect())
	await _shot("timeline", lab.timeline.get_global_rect())
	await _section_at_widest()
	await _shot("checks", Rect2(_side_rect().position + Vector2(0, _side_rect().size.y - 130), Vector2(_side_rect().size.x, 130)))

	# Tabs.
	await _shot("tab_bands", _side_rect())
	await _tab("Road")
	_collapse_all(lab.road_rows)
	_open_group(lab.road_rows, "lights")
	await _shot("tab_road", _side_rect())
	_collapse_all(lab.road_rows)
	_open_group(lab.road_rows, "materials")
	await _tab("Walls")
	_collapse_all(lab.wall_rows)
	_open_group(lab.wall_rows, "wall")
	await _shot("tab_walls", _side_rect())
	await _tab("Greebles")
	await _shot("tab_greebles", _side_rect())
	await _tab("Materials")
	_open_group(lab.mat_rows, "glow")
	await _shot("tab_materials", _side_rect())
	await _tab("Mask")
	lab._pick_mask("mask_worn_patches.tres")
	await _shot("tab_mask", _side_rect())
	lab._pick_mask("")
	await _tab("Cost")
	await _frames(70)
	await _shot("tab_cost", _side_rect())
	await _tab("Bands")
	_reset()

	# Viewing.
	lab.ui.visible = false
	await _shot("view_clean")
	if lab.gs:
		for v in [[2, "bands"], [3, "panels"], [4, "filter"], [5, "zones"], [6, "wear"]]:
			lab.gs.set_surface_view(v[0])
			await _shot("view_debug_" + v[1])
		lab.gs.set_surface_view(0)
	for w: String in ["rain_heavy", "snow_medium", "fog_medium"]:
		lab.env.apply_weather(load("res://resources/weather/%s.tres" % w), true)
		await _shot("view_weather_" + w, Rect2(), 30)
	lab.env.apply_weather(load("res://resources/weather/clear.tres"), true)
	await _frames(20)
	lab._set_road_look(false)
	await _shot("view_neutral_road")
	lab._set_road_look(true)
	doc.greebles.visible = false
	await _shot("view_no_greebles")
	doc.greebles.visible = true
	lab._select_style(lab._style_at_camera())
	lab._select_rule(_rule_named(["wall_panel", "lamp_pole", "bollard"]))
	lab.solo_rule = true
	lab._apply_greeble_display()
	await _shot("view_solo_rule")
	lab.solo_rule = false
	lab._apply_greeble_display()
	lab.hidden_layers = TrackGreebles.LAYER_BITS["wall_face"] | TrackGreebles.LAYER_BITS["outside"] \
			| TrackGreebles.LAYER_BITS["wall_top"] | TrackGreebles.LAYER_BITS["overhead"]
	lab._apply_greeble_display()
	await _shot("view_ground_only")
	lab.hidden_layers = 0
	lab._apply_greeble_display()
	lab.cam.set_mode(2)
	await _frames(300)
	await _shot("view_chase")
	_pose()
	await _frames(10)

	# Worked examples: each one saved look, then an edit.
	await _before_after("ex_grate", func():
		var data: Array = (doc.get_v("prof:industrial/bands") as Array).duplicate(true)
		data[2][1] = 7.0
		doc.set_v("prof:industrial/bands", data))
	await _before_after("ex_plate", func():
		doc.set_v("road/plate_color", Color(0.38, 0.27, 0.16))
		doc.set_v("road/plate_roughness", 0.75))
	await _before_after("ex_lights", func():
		doc.set_v("road/light_blue", Color(1.0, 0.05, 0.75))
		doc.set_v("road/light_red", Color(0.1, 1.0, 0.5))
		doc.set_v("road/light_energy", 12.0)
		doc.set_v("road/led_energy", 10.0))
	await _before_after("ex_wear", func():
		doc.set_v("road/wear_age", 1.0)
		doc.set_v("road/grime_amount", 1.0)
		doc.set_v("road/scorch_amount", 1.0), func():
		doc.set_v("road/wear_age", 0.0))
	await _before_after("ex_walls", func():
		doc.set_v("wall/wall_color", Color(0.3, 0.05, 0.05))
		doc.set_v("road/hazard_yellow", Color(0.1, 0.6, 0.9)))
	var civic := func(key: String, value: Variant):
		var st: String = lab._style_at_camera()
		doc.set_v("style:%s/%s" % [st, key], value)
	await _before_after("ex_bay", func(): civic.call("bay_length", 10.0))
	await _before_after("ex_glow", func():
		for m: String in ["glow", "glow_cool"]:
			doc.set_v("mat:%s/emission" % m, Color(0.1, 1.0, 0.3))
			doc.set_v("mat:%s/albedo_color" % m, Color(0.3, 1.0, 0.4)))

	# Masks.
	lab.ui.visible = false
	lab._pick_mask("")
	await _shot("mask_none")
	for f: String in ["worn_patches", "soft_clouds", "long_streaks"]:
		lab._pick_mask("mask_%s.tres" % f)
		await _shot("mask_" + f)
	# One layer, then the second layer breaking it up.
	lab._pick_mask("mask_worn_patches.tres")
	doc.set_v("mask:mask_worn_patches.tres/mode", 1)
	await _shot("mask_layer_a")
	doc.set_v("mask:mask_worn_patches.tres/mode", 3)
	await _shot("mask_layer_ab")
	if lab.gs:
		lab.gs.set_surface_view(7)
		await _shot("mask_debug")
		lab.gs.set_surface_view(0)
	# A band left out of it.
	var bands: Array = (doc.get_v("prof:industrial/bands") as Array).duplicate(true)
	bands[bands.size() - 1][5] = 0.0
	doc.set_v("prof:industrial/bands", bands)
	doc.flush()
	await _shot("mask_band_off")
	lab._pick_mask("")
	_reset()

	# The save dialog, never confirmed.
	lab.ui.visible = true
	doc.set_v("road/plate_roughness", 0.5)
	doc.set_v("mask:mask_worn_patches.tres/contrast", 2.0)
	doc.commit()
	await _frames(40)
	lab._ask_save()
	await _frames(4)
	var dlg: Window = lab.save_dialog
	await _shot("save_dialog", Rect2(Vector2(dlg.position) - Vector2(8, 38), Vector2(dlg.size) + Vector2(16, 46)), 12)
	lab.save_dialog.hide()
	_reset()
	await _frames(5)
	if not doc.dirty_files().is_empty():
		push_error("LABTOUR left edits behind: %s" % str(doc.dirty_files()))
	print("LABTOUR done, dirty %s" % str(doc.dirty_files()))
	get_tree().quit(0)


## The section where a WidthKey makes the road widest: ground pins off their lanes.
func _section_at_widest() -> void:
	var best_d := POSE
	var best := 0.0
	var d := 0.0
	while d < lab.cam.length():
		var seg: TrackRoadSegment = lab._road_segment(d)
		if seg:
			var w: Vector2 = seg.width_at(d)
			if maxf(w.x, w.y) > best:
				best = maxf(w.x, w.y)
				best_d = d
		d += 10.0
	_pose(best_d)
	await _frames(20)
	print("LABTOUR widest road %.1f m at %.0f m" % [best, best_d])
	await _shot("section_wide", lab.section.get_global_rect())
	_pose()
	await _frames(20)


func _select_grate() -> void:
	await _frames(5)
	var data: Array = doc.get_v("prof:%s/bands" % lab.profile_name)
	for i in data.size():
		if data[i][0] == TrackSurfaceBand.Type.GRATE:
			lab._select_band(i)
			break
	await _frames(5)


## The first rule of the selected style using one of these meshes.
func _rule_named(names: Array) -> int:
	var st: UtopiaGreebleStyle = doc.styles[lab.style_name]
	for n: String in names:
		for i in st.rules.size():
			var m := st.rules[i].mesh
			if m and m.resource_path.get_file().get_basename() == "gb_" + n:
				return i
	return 0
