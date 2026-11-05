extends Node
## Sky Lab: takes the tutorial's screenshots (docs/sky-lab), so they can be
## retaken when the lab changes. Every edit is undone and nothing is saved.
##
##   LAB_TOUR=<absolute folder> godot --path full_throttle_flux res://tools/sky_lab/sky_lab.tscn
##
## Add LAB_TOUR_ONLY=<prefix> to retake only the shots whose names start with it.

const SCENE_W := 1280
## Where on Utopia the shots are taken: metres along the lap.
const POSE := 1180.0

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


func _wants(name: String) -> bool:
	if only == "":
		return true
	for p in only.split(","):
		if name.begins_with(p):
			return true
	return false


## Saves the frame, or `area` of it. UI crops stay full size; 3D views shrink.
func _shot(name: String, area := Rect2(), settle := 4) -> void:
	if not _wants(name):
		return
	await _frames(settle)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if area.size != Vector2.ZERO:
		img = img.get_region(Rect2i(area))
	elif not lab.ui.visible:
		img.resize(SCENE_W, SCENE_W * img.get_height() / img.get_width(), Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGB8)
	var err := img.save_jpg("%s/%s.jpg" % [out, name], 0.86)
	print("SKYTOUR %s %s" % [name, error_string(err)])


func _side_rect() -> Rect2:
	return lab.ui.get_child(1).get_global_rect()


func _tab(name: String) -> void:
	lab.tabs.current_tab = lab.tabs.get_tab_idx_from_control(lab.tabs.get_node(name))
	await _frames(2)


func _reset() -> void:
	var w: String = doc.weather_file
	doc.restore(doc.saved)
	doc.commit()
	lab._pick_weather(w)
	lab._refresh_all()


func _weather(file: String) -> void:
	lab._pick_weather(file)
	await _frames(2)


## Two pictures: as saved, then with `edit` applied.
func _before_after(name: String, edit: Callable, setup := Callable()) -> void:
	if not _wants(name):
		return
	lab.ui.visible = false
	if setup.is_valid():
		await setup.call()
	doc.apply()
	await _shot(name + "_before")
	edit.call()
	doc.apply()
	await _shot(name + "_after")
	_reset()


func _collapse_all(rows: Control) -> void:
	for c in rows.get_children():
		if c is Button:
			var next: Control = rows.get_child(c.get_index() + 1)
			if next.visible:
				c.pressed.emit()


func _open_group(rows: Control, title: String) -> void:
	for c in rows.get_children():
		if c is Button and String(c.text).ends_with(title):
			var next: Control = rows.get_child(c.get_index() + 1)
			if not next.visible:
				c.pressed.emit()


func _run() -> void:
	lab.cam.glide_paused = true
	if only == "probe":
		# Candidate spots round the lap, to choose POSE.
		lab.ui.visible = false
		var d := 0.0
		while d < lab.cam.length():
			lab.cam.jump(d)
			await _shot("probe_%04d" % roundi(d), Rect2(), 3)
			d += 400.0
		get_tree().quit(0)
		return
	lab.cam.jump(POSE)
	lab.exposure.enabled = true
	await _frames(20)

	# The whole screen.
	lab._measure_exposure()
	await _shot("overview")
	await _shot("topbar", lab.ui.get_child(0).get_global_rect())
	await _shot("sun_dial", lab.sun_dial.get_global_rect())
	await _shot("exposure", lab.exposure.get_parent().get_global_rect())
	await _shot("readout", lab.readout.get_global_rect())
	await _shot("checks", Rect2(_side_rect().position + Vector2(0, _side_rect().size.y - 130), Vector2(_side_rect().size.x, 130)))

	# Tabs.
	_collapse_all(lab.sky_rows)
	_open_group(lab.sky_rows, "Sun")
	_open_group(lab.sky_rows, "Clouds")
	await _shot("tab_sky", _side_rect())
	_open_group(lab.sky_rows, "Atmosphere")
	await _weather("rain_medium.tres")
	await _tab("Weather")
	await _shot("tab_weather", _side_rect())
	await _tab("Falling")
	await _shot("tab_falling", _side_rect())
	await _tab("Sky")
	_collapse_all(lab.sky_rows)
	_open_group(lab.sky_rows, "Clouds")
	await _shot("tab_sky_badges", _side_rect())
	_open_group(lab.sky_rows, "Sun")
	await _weather("clear.tres")
	await _tab("Post")
	await _shot("tab_post", _side_rect())
	if lab.te_rows:
		await _tab("Track")
		await _shot("tab_track", _side_rect())
	await _tab("Sky")

	# Viewing.
	lab.ui.visible = false
	await _shot("view_clean")
	for l: int in [1, 2, 3]:
		lab.look = l
		await _frames(2)
		await _shot("view_look_" + ["road", "sun", "away", "up"][l])
	lab.look = 0

	# The sky presets, on this track.
	for p: String in UtopiaSkyController.PRESETS:
		if not _wants("preset_" + p):
			continue
		doc.start_from_preset(p)
		doc.apply()
		await _shot("preset_" + p)
		_reset()

	# The weathers.
	for w: String in ["clear", "rain_light", "rain_heavy", "snow_medium", "snow_heavy", "fog_medium",
			"fog_heavy", "dust_storm_medium"]:
		if not _wants("weather_" + w):
			continue
		await _weather(w + ".tres")
		await _shot("weather_" + w, Rect2(), 6)
	await _weather("clear.tres")

	# Worked examples.
	await _before_after("ex_sun", func():
		doc.set_v("sky/sun_elevation", 7.0)
		doc.set_v("sky/sun_azimuth", 250.0))
	await _before_after("ex_clouds", func():
		doc.set_v("sky/coverage", 0.78)
		doc.set_v("sky/billow_size", 1.8)
		doc.set_v("sky/cloud_shadow_color", Color(0.24, 0.26, 0.36)))
	await _before_after("ex_haze", func():
		doc.set_v("env/fog_height_density", 0.05)
		doc.set_v("env/fog_aerial_perspective", 0.5)
		doc.set_v("sky/fog_density", 0.0006))
	await _before_after("ex_grade", func():
		doc.set_v("env/adjustment_contrast", 1.25)
		doc.set_v("env/adjustment_saturation", 1.35)
		doc.set_v("env/glow_intensity", 1.2))
	await _before_after("ex_mood", func():
		doc.set_v("w:rain_medium.tres/sky_mood", 1.0)
		doc.set_v("w:rain_medium.tres/fog_tint", Color(0.35, 0.45, 0.6, 0.6)), func():
		await _weather("rain_medium.tres"))
	await _before_after("ex_rain", func():
		doc.set_v("p:rain/width", 0.03)
		doc.set_v("p:rain/opacity", 0.6)
		doc.set_v("p:rain/max_length", 6.0)
		doc.set_v("p:rain/min_length", 1.2), func():
		await _weather("rain_heavy.tres"))
	await _before_after("ex_snow", func():
		doc.set_v("p:snow/width", 0.08)
		doc.set_v("p:snow/sway", 2.0)
		doc.set_v("p:snow/tint_target", Color(1.0, 0.8, 0.9)), func():
		await _weather("snow_heavy.tres"))
	await _weather("clear.tres")

	# A change at race speed: clear to heavy rain, as a filmstrip.
	if _wants("change_"):
		lab.ui.visible = false
		await _weather("rain_heavy.tres")
		doc.play_change(doc.weathers["clear.tres"])
		var t0 := Time.get_ticks_msec()
		for at: float in [0.0, 3.0, 6.0, 20.0]:
			while (Time.get_ticks_msec() - t0) / 1000.0 < at:
				await get_tree().process_frame
			await _shot("change_%02d" % roundi(at), Rect2(), 1)
		await _weather("clear.tres")

	# The save dialog, never confirmed.
	lab.ui.visible = true
	doc.set_v("sky/sun_elevation", 12.0)
	doc.set_v("w:rain_medium.tres/wetness", 0.7)
	doc.commit()
	await _frames(20)
	lab._ask_save()
	await _frames(4)
	var dlg: Window = lab.save_dialog
	await _shot("save_dialog", Rect2(Vector2(dlg.position) - Vector2(8, 38), Vector2(dlg.size) + Vector2(16, 46)), 6)
	lab.save_dialog.hide()
	_reset()
	await _frames(5)
	if not doc.dirty_files().is_empty():
		push_error("SKYTOUR left edits behind: %s" % str(doc.dirty_files()))
	print("SKYTOUR done, dirty %s" % str(doc.dirty_files()))
	get_tree().quit(0)
