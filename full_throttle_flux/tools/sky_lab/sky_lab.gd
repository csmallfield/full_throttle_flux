extends Node
## Sky Lab: tune a track's sky, its post and fog, the weather presets and how
## rain, snow and grit look, live on the real track, then save to the files the
## game loads. Nothing to bake: a race reads these files when it starts.
##
## Open tools/sky_lab/sky_lab.tscn and run it (F6), or:
##   godot --path full_throttle_flux res://tools/sky_lab/sky_lab.tscn
##
## Keys: C hold = show the saved look, H = hide the UI, Ctrl+Z / Ctrl+Y = undo /
## redo, Ctrl+S = save, Space = pause the glide, [ / ] = previous / next
## weather. Fly camera: hold the right mouse button, WASD + Q/E, Shift for
## fast, the wheel for speed.
##
## Env: LAB_TRACK track scene name (test_circuit_3_live, Utopia), LAB_SELFTEST
## 1 = run the self test (sky_lab_selftest.gd) and quit, LAB_TOUR = take the
## tutorial's screenshots (sky_lab_tour.gd).
##
## FTF_SKY_LAB.md has the design and limits.

const Doc := preload("res://tools/sky_lab/sky_doc.gd")
const LabCamera := preload("res://tools/surface_lab/lab_camera.gd")
const Rows := preload("res://tools/surface_lab/lab_rows.gd")
const SunDial := preload("res://tools/sky_lab/sky_sun_dial.gd")
const ExposureView := preload("res://tools/sky_lab/sky_exposure_view.gd")

const DEFAULT_TRACK := "test_circuit_3_live"
const LOOK_NAMES := ["Look: road", "Look: toward sun", "Look: away from sun", "Look: up"]
const SIDE_W := 470.0
const BOTTOM_H := 196.0
const TOP_H := 46.0
const CHECK_QUIET := 0.6
## Distance fog this thick hides the road ahead sooner than this: worth a look.
const FOG_NEAR_M := 400.0
const COLOR_WARN := Color(1.0, 0.72, 0.3)
const COLOR_OK := Color(0.55, 0.85, 0.75)

enum Look { ROAD, TOWARD_SUN, AWAY, UP }

var doc: Doc
var track: Node
var track_id := ""
var spline: Path3D
var env: EnvironmentState
var cam: LabCamera
var gs: Node
var look := Look.ROAD
var weather_files: PackedStringArray = []

var ui: Control
var tabs: TabContainer
var sky_rows: Rows
var env_rows: Rows
var weather_rows: Rows
var look_rows: Rows
var te_rows: Rows
var weather_head: Label
var look_head: Label
var start_opt: OptionButton
var weather_opt: OptionButton
var look_opt: OptionButton
var sun_dial: SunDial
var exposure: ExposureView
var readout: RichTextLabel
var checks: ItemList
var status: Label
var gpu_label: Label
var undo_btn: Button
var redo_btn: Button
var save_btn: Button
var compare_btn: Button
var save_dialog: ConfirmationDialog
var snap_btns := {}
var snaps := {}

var _look_stem := "-"
var _compare_hold := {}
var _comparing := false
var _ui_dirty := false
var _status_wait := 0.0
var _check_wait := -1.0
var _views_wait := 0.0
var _expo_wait := 0.0
var _gpu_samples := PackedFloat32Array()


func _ready() -> void:
	get_tree().auto_accept_quit = false
	process_priority = 10    # after the lab camera, so Look can turn it
	gs = get_node_or_null("/root/GraphicsSettings")
	track_id = OS.get_environment("LAB_TRACK")
	if track_id == "":
		track_id = DEFAULT_TRACK
	track = (load("res://scenes/tracks/%s.tscn" % track_id) as PackedScene).instantiate()
	add_child(track)
	await get_tree().process_frame
	await get_tree().process_frame
	spline = track.find_child("MainSpline", true, false) as Path3D
	var profile_path := "res://resources/tracks/%s.tres" % track_id
	var profile := load(profile_path) as TrackProfile if ResourceLoader.exists(profile_path) else null
	if gs and profile:
		gs.apply_track(track, profile.get("shadow_profile"))
	doc = Doc.new()
	doc.setup(track, profile.environment if profile else null)
	env = EnvironmentState.install(self, track, profile)
	doc.attach(env)
	doc.changed.connect(func(): _ui_dirty = true)
	weather_files = PackedStringArray(doc.weathers.keys())
	weather_files.sort()
	cam = LabCamera.new()
	cam.road_xf = env.road_xf
	add_child(cam)
	cam.setup(track, spline)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_build_ui()
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	_build_all_rows()
	_refresh_all()
	_run_checks()
	if OS.get_environment("LAB_SELFTEST") == "1":
		var t: Node = load("res://tools/sky_lab/sky_lab_selftest.gd").new()
		t.lab = self
		add_child(t)
	elif OS.get_environment("LAB_TOUR") != "":
		var t: Node = load("res://tools/sky_lab/sky_lab_tour.gd").new()
		t.lab = self
		add_child(t)


# =============================================================================
# EVERY FRAME
# =============================================================================

func _process(delta: float) -> void:
	if doc == null:
		return
	doc.tick(delta)
	_status_wait -= delta
	if _ui_dirty and _status_wait <= 0.0:
		_ui_dirty = false
		_status_wait = 0.3
		_refresh_status()
		_check_wait = CHECK_QUIET
	if _check_wait > 0.0:
		_check_wait -= delta
		if _check_wait <= 0.0 and not _comparing:
			_run_checks()
	_aim_look()
	_views_wait -= delta
	if _views_wait <= 0.0:
		_views_wait = 0.1
		_update_views()
	_expo_wait -= delta
	if _expo_wait <= 0.0 and exposure.enabled:
		_expo_wait = 0.5
		_measure_exposure()
	var vp := get_viewport().get_viewport_rid()
	_gpu_samples.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	if _gpu_samples.size() > 60:
		_gpu_samples.remove_at(0)


func _input(event: InputEvent) -> void:
	if cam and cam.is_looking() and event is InputEventMouse:
		cam.view_input(event)
		get_viewport().set_input_as_handled()
		return
	var k := event as InputEventKey
	if k == null or k.echo:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if k.physical_keycode == KEY_C and not k.ctrl_pressed:
		_set_compare(k.pressed)
		get_viewport().set_input_as_handled()
		return
	if not k.pressed:
		return
	if k.physical_keycode == KEY_H:
		ui.visible = not ui.visible
	elif k.physical_keycode == KEY_SPACE:
		cam.glide_paused = not cam.glide_paused
	elif k.physical_keycode == KEY_BRACKETLEFT or k.physical_keycode == KEY_BRACKETRIGHT:
		var i := weather_files.find(doc.weather_file)
		_pick_weather(weather_files[posmod(i + (1 if k.physical_keycode == KEY_BRACKETRIGHT else -1), weather_files.size())])
	elif k.ctrl_pressed and k.physical_keycode == KEY_Z:
		if doc.undo():
			_refresh_all()
	elif k.ctrl_pressed and k.physical_keycode == KEY_Y:
		if doc.redo():
			_refresh_all()
	elif k.ctrl_pressed and k.physical_keycode == KEY_S:
		_ask_save()
	else:
		return
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if cam:
		cam.view_input(event)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if doc and not doc.dirty_files().is_empty():
			var d := ConfirmationDialog.new()
			d.dialog_text = "You have unsaved edits. Quit without saving them?"
			d.ok_button_text = "Quit"
			ui.add_child(d)
			d.confirmed.connect(func(): get_tree().quit())
			d.popup_centered()
		else:
			get_tree().quit()


func _on_focus_changed(c: Control) -> void:
	var keys := get_node_or_null("/root/DebugKeys")
	if keys:
		keys.suspended = c is LineEdit


func _exit_tree() -> void:
	var keys := get_node_or_null("/root/DebugKeys")
	if keys:
		keys.suspended = false


## Turns the glide camera toward or away from the sun, or up, after it's placed.
func _aim_look() -> void:
	if look == Look.ROAD or cam.mode != LabCamera.Mode.GLIDE:
		return
	var az := float(doc.sky_vals.get("sun_azimuth", 0.0))
	var el := float(doc.sky_vals.get("sun_elevation", 20.0))
	var yaw := az
	var pitch := clampf(el * 0.7 + 4.0, 2.0, 50.0)
	if look == Look.AWAY:
		yaw = az + 180.0
		pitch = 8.0
	elif look == Look.UP:
		yaw = _heading()
		pitch = 62.0
	var y := deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	var dir := Vector3(sin(y) * cos(p), sin(p), -cos(y) * cos(p))
	var c := cam.cam
	c.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), c.global_position)


## Compass heading of the 3D camera, degrees (sun_azimuth's convention).
func _heading() -> float:
	var c := get_viewport().get_camera_3d()
	if c == null:
		return 0.0
	var f := -c.global_transform.basis.z
	return fposmod(rad_to_deg(atan2(f.x, -f.z)), 360.0)


# =============================================================================
# UI
# =============================================================================

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	_build_top_bar()
	_build_side_panel()
	_build_bottom_panel()
	save_dialog = ConfirmationDialog.new()
	save_dialog.title = "Save edits"
	save_dialog.ok_button_text = "Save"
	save_dialog.confirmed.connect(_do_save)
	ui.add_child(save_dialog)


static func _panel(alpha := 0.9) -> PanelContainer:
	var p := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.1, 0.11, 0.13, alpha)
	box.set_content_margin_all(6.0)
	p.add_theme_stylebox_override("panel", box)
	return p


func _option(parent: Control, names: Array, selected: int) -> OptionButton:
	var o := OptionButton.new()
	for n in names:
		o.add_item(str(n))
	o.select(selected)
	o.focus_mode = Control.FOCUS_NONE
	parent.add_child(o)
	return o


func _build_top_bar() -> void:
	var p := _panel()
	p.set_anchors_preset(Control.PRESET_TOP_WIDE)
	ui.add_child(p)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	p.add_child(bar)
	var title := Label.new()
	title.text = "Sky Lab"
	bar.add_child(title)
	var cam_opt := _option(bar, ["Fly", "Glide", "Chase lap"], 1)
	cam_opt.item_selected.connect(func(i: int): cam.set_mode(i as LabCamera.Mode))
	cam_opt.tooltip_text = "Fly: hold the right mouse button, WASD + Q/E.\nGlide: the chase pose sliding round the lap (Space pauses).\nChase lap: a real AI ship with the game's camera."
	var speed := HSlider.new()
	speed.min_value = 0.0
	speed.max_value = 200.0
	speed.value = cam.glide_speed
	speed.custom_minimum_size = Vector2(90, 0)
	speed.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	speed.tooltip_text = "Glide speed"
	speed.focus_mode = Control.FOCUS_NONE
	speed.value_changed.connect(func(v: float): cam.glide_speed = v)
	bar.add_child(speed)
	look_opt = _option(bar, LOOK_NAMES, 0)
	look_opt.tooltip_text = "Turns the Glide camera toward the sun, away from it, or up at the sky."
	look_opt.item_selected.connect(func(i: int): look = i as Look)
	bar.add_child(VSeparator.new())
	var names: Array = []
	for f: String in weather_files:
		names.append(_weather_label(f))
	weather_opt = _option(bar, names, maxi(weather_files.find(doc.weather_file), 0))
	weather_opt.tooltip_text = "The weather on the track, and the preset the Weather tab edits. [ and ] step through them."
	weather_opt.item_selected.connect(func(i: int): _pick_weather(weather_files[i]))
	var play := Button.new()
	play.text = "Play change"
	play.tooltip_text = "Starts clear, then changes to this weather at race speed,\nas a mid-race change does."
	play.pressed.connect(func(): doc.play_change(doc.weathers.get("clear.tres")))
	bar.add_child(play)
	bar.add_child(VSeparator.new())
	compare_btn = Button.new()
	compare_btn.text = "Hold C: saved"
	compare_btn.tooltip_text = "Hold to see the saved look, in the same weather."
	compare_btn.button_down.connect(func(): _set_compare(true))
	compare_btn.button_up.connect(func(): _set_compare(false))
	bar.add_child(compare_btn)
	for s in ["A", "B"]:
		var b := Button.new()
		b.text = s + " -"
		b.tooltip_text = "Click: store the look here, then click to go back to it.\nCtrl+click: store again."
		b.pressed.connect(func(): _snapshot(s))
		bar.add_child(b)
		snap_btns[s] = b
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	gpu_label = Label.new()
	bar.add_child(gpu_label)
	status = Label.new()
	status.add_theme_color_override("font_color", COLOR_WARN)
	bar.add_child(status)
	undo_btn = Button.new()
	undo_btn.text = "Undo"
	undo_btn.pressed.connect(func():
		if doc.undo():
			_refresh_all())
	bar.add_child(undo_btn)
	redo_btn = Button.new()
	redo_btn.text = "Redo"
	redo_btn.pressed.connect(func():
		if doc.redo():
			_refresh_all())
	bar.add_child(redo_btn)
	save_btn = Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(_ask_save)
	bar.add_child(save_btn)


## "rain_light.tres" -> "Rain light": the file, since display names vary
## ("Blizzard", "Fog (dense)").
static func _weather_label(file: String) -> String:
	var t := file.trim_suffix(".tres").replace("_", " ")
	return t.substr(0, 1).to_upper() + t.substr(1)


func _build_side_panel() -> void:
	var p := _panel()
	p.anchor_left = 1.0
	p.anchor_right = 1.0
	p.anchor_bottom = 1.0
	p.offset_left = -SIDE_W
	p.offset_top = TOP_H
	p.offset_bottom = -BOTTOM_H - 2.0
	ui.add_child(p)
	var col := VBoxContainer.new()
	p.add_child(col)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 13)
	col.add_child(tabs)
	sky_rows = _scroll_tab("Sky", _sky_header())
	weather_head = _note("")
	weather_rows = _scroll_tab("Weather", weather_head)
	look_head = _note("")
	look_rows = _scroll_tab("Falling", look_head)
	env_rows = _scroll_tab("Post", _note("Saved to the track's lighting scene, with the sky. The sky owns fog colour and density, ambient light and exposure: they're on the Sky tab."))
	if not doc.te_props.is_empty():
		te_rows = _scroll_tab("Track", _note("Saved to %s: this track only." % doc.track_env.resource_path.get_file()))
	var head := Label.new()
	head.text = "Checks (double-click to see that weather)"
	head.add_theme_font_size_override("font_size", 12)
	col.add_child(head)
	checks = ItemList.new()
	checks.custom_minimum_size = Vector2(0, 92)
	checks.add_theme_font_size_override("font_size", 12)
	checks.item_activated.connect(func(i: int):
		var f: Variant = checks.get_item_metadata(i)
		if f is String and f != "":
			_pick_weather(f))
	col.add_child(checks)


func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", COLOR_WARN)
	return l


func _sky_header() -> Control:
	var col := VBoxContainer.new()
	if doc.sky == null:
		col.add_child(_note("This track has no sky controller (UtopiaSkyController), so there's no sky to edit and weather can't change it. Utopia, Swoopy and Hairpin Alley have one."))
		return col
	var hb := HBoxContainer.new()
	col.add_child(hb)
	var l := Label.new()
	l.text = "Start from"
	hb.add_child(l)
	var names: Array = UtopiaSkyController.PRESETS.keys()
	start_opt = _option(hb, names, maxi(names.find(doc.sky_vals.get("preset", "")), 0))
	start_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var go := Button.new()
	go.text = "Apply"
	go.tooltip_text = "Replaces every value the preset has with the preset's, as one edit."
	go.pressed.connect(func():
		doc.start_from_preset(start_opt.get_item_text(start_opt.selected))
		doc.commit()
		_refresh_all())
	hb.add_child(go)
	col.add_child(_note("Saved to %s: this track only. Values the current weather changes are marked." % doc.sky_file.get_file()))
	return col


func _scroll_tab(title: String, header: Control) -> Rows:
	var col := VBoxContainer.new()
	col.name = title
	tabs.add_child(col)
	if header:
		col.add_child(header)
	var search := LineEdit.new()
	search.placeholder_text = "Search settings"
	search.clear_button_enabled = true
	col.add_child(search)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var rows := Rows.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	search.text_changed.connect(func(t: String): rows.set_filter(t))
	return rows


func _build_bottom_panel() -> void:
	var p := _panel()
	p.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	p.offset_top = -BOTTOM_H
	ui.add_child(p)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	p.add_child(hb)
	sun_dial = SunDial.new()
	sun_dial.sun_dragged.connect(func(az: float, el: float):
		doc.set_v("sky/sun_azimuth", az)
		doc.set_v("sky/sun_elevation", el)
		sky_rows.refresh())
	hb.add_child(sun_dial)
	var ex_col := VBoxContainer.new()
	hb.add_child(ex_col)
	exposure = ExposureView.new()
	exposure.custom_minimum_size = Vector2(320, 150)
	ex_col.add_child(exposure)
	var ex_on := CheckBox.new()
	ex_on.text = "Measure exposure"
	ex_on.button_pressed = true
	ex_on.add_theme_font_size_override("font_size", 12)
	ex_on.tooltip_text = "Reads the frame back twice a second. Off while timing the GPU."
	ex_on.toggled.connect(func(on: bool):
		exposure.enabled = on
		exposure.queue_redraw())
	ex_col.add_child(ex_on)
	readout = RichTextLabel.new()
	readout.bbcode_enabled = true
	readout.fit_content = false
	readout.scroll_active = false
	readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	readout.add_theme_font_size_override("normal_font_size", 13)
	readout.add_theme_font_size_override("bold_font_size", 13)
	hb.add_child(readout)


# =============================================================================
# ROWS
# =============================================================================

func _build_all_rows() -> void:
	_fill_rows(sky_rows, doc.sky_props, "sky/", true)
	_fill_rows(env_rows, doc.env_props, "env/", true)
	if te_rows:
		_fill_rows(te_rows, doc.te_props, "te/", false)
	_build_weather_rows()
	_build_look_rows()


func _fill_rows(rows: Rows, props: Array[Dictionary], prefix: String, weather_badge: bool,
		badge := "this track") -> void:
	rows.clear_rows()
	var group := ""
	for p in props:
		if p.group != group:
			group = p.group
			rows.add_group(group, true)
		var key: String = prefix + p.name
		var spec := {name = p.name, type = p.type, hint = p.hint, hint_string = p.hint_string,
			get = func(): return doc.get_v(key),
			set = func(v: Variant): doc.set_v(key, v),
			badge = badge}
		if weather_badge:
			spec.badge_fn = func() -> Array:
				var e: Array = doc.weather_effect(key)
				return [badge, false] if e[0] == "" else [e[0], true]
		rows.add_row(spec)


func _build_weather_rows() -> void:
	var f := doc.weather_file
	var w := doc.weather()
	weather_head.text = "Editing %s (%s). Saved to resources/weather: every track using this weather." % [
			w.display_name if w else "-", f]
	weather_rows.clear_rows()
	var group := ""
	var sky_names: Array = ["(track's own)"] + UtopiaSkyController.PRESETS.keys()
	for p in doc.weather_props:
		if p.group != group:
			group = p.group
			weather_rows.add_group(group, true)
		var key: String = "w:%s/%s" % [f, p.name]
		var spec := {name = p.name, type = p.type, hint = p.hint, hint_string = p.hint_string,
			get = func(): return doc.get_v(key),
			set = func(v: Variant): doc.set_v(key, v),
			badge = "every track"}
		if p.name == "sky_preset":
			spec.choices = sky_names
			spec.get = func():
				var v := String(doc.get_v(key))
				return "(track's own)" if v == "" else v
			spec.set = func(v: Variant):
				doc.set_v(key, "" if v == "(track's own)" else String(v))
		elif p.name == "kind":
			spec.set = func(v: Variant):
				doc.set_v(key, v)
				_build_look_rows.call_deferred()
		elif p.name == "fog_tint":
			# Its alpha is how far the fog is pushed: a row of its own, since
			# the colour picker leaves alpha alone.
			spec.set = func(v: Variant):
				var a := (doc.get_v(key) as Color).a
				doc.set_v(key, Color((v as Color).r, (v as Color).g, (v as Color).b, a))
			weather_rows.add_row(spec)
			spec = {name = "fog_tint_amount", type = TYPE_FLOAT, hint = PROPERTY_HINT_RANGE,
				hint_string = "0,1,0.01", badge = "every track",
				tooltip = "fog_tint's alpha: how far the fog colour is pushed toward it.",
				get = func(): return (doc.get_v(key) as Color).a,
				set = func(v: Variant):
					var c: Color = doc.get_v(key)
					c.a = float(v)
					doc.set_v(key, c)}
		weather_rows.add_row(spec)


func _build_look_rows() -> void:
	var stem := doc.current_look_stem()
	_look_stem = stem
	look_rows.clear_rows()
	if stem == "":
		look_head.text = "Nothing falls in this weather. Pick rain, snow or a dust storm to edit how it looks."
		return
	look_head.text = "How %s looks, in every weather of that kind on every track (precip_%s.tres). The weather's precipitation sets how much falls." % [
			stem.replace("_", " "), stem]
	_fill_rows(look_rows, doc.look_props, "p:%s/" % stem, false, "every track")


# =============================================================================
# WEATHER, COMPARE, SNAPSHOTS
# =============================================================================

func _pick_weather(file: String) -> void:
	doc.set_v("weather", file, false)
	doc.apply()
	weather_opt.select(weather_files.find(file))
	_build_weather_rows()
	if doc.current_look_stem() != _look_stem:
		_build_look_rows()
	sky_rows.refresh()
	env_rows.refresh()
	_ui_dirty = true


## Held: shows the saved look in the current weather, then puts edits back.
func _set_compare(on: bool) -> void:
	if on == _comparing:
		return
	_comparing = on
	if on:
		doc.commit()
		_compare_hold = doc.capture()
		var target := doc.saved.duplicate()
		target["weather"] = doc.weather_file
		doc.restore(target)
		status.text = "Showing saved"
	else:
		doc.restore(_compare_hold)
		_compare_hold = {}
	_refresh_all()


func _snapshot(s: String) -> void:
	if not snaps.has(s) or Input.is_key_pressed(KEY_CTRL):
		doc.commit()
		snaps[s] = doc.capture()
		(snap_btns[s] as Button).text = s + " stored"
		return
	doc.restore(snaps[s])
	doc.commit()
	_refresh_all()


func _refresh_all() -> void:
	weather_opt.select(weather_files.find(doc.weather_file))
	if start_opt:
		var names: Array = UtopiaSkyController.PRESETS.keys()
		var i := names.find(doc.sky_vals.get("preset", ""))
		if i >= 0:
			start_opt.select(i)
	_build_weather_rows()
	if doc.current_look_stem() != _look_stem:
		_build_look_rows()
	for r: Rows in [sky_rows, env_rows, weather_rows, look_rows, te_rows]:
		if r:
			r.refresh()
	_refresh_status()


func _refresh_status() -> void:
	if _comparing:
		return
	var files := doc.dirty_files()
	var n := 0
	for f: String in files:
		n += files[f]
	status.text = "%d unsaved in %d %s" % [n, files.size(), "file" if files.size() == 1 else "files"] if n > 0 else "Saved"
	status.add_theme_color_override("font_color", COLOR_WARN if n > 0 else COLOR_OK)
	undo_btn.disabled = doc.history_i <= 0 and not doc._edited
	redo_btn.disabled = doc.history_i >= doc.history.size() - 1
	# Badges follow the weather and its edits.
	for r: Rows in [sky_rows, env_rows]:
		r.refresh()


# =============================================================================
# VIEWS
# =============================================================================

func _gpu_ms() -> float:
	if _gpu_samples.is_empty():
		return 0.0
	var s := _gpu_samples.duplicate()
	s.sort()
	return s[s.size() / 2]


## Metres of distance fog before the road is 90% gone (exponential fog).
static func fog_reach(density: float) -> float:
	return INF if density <= 0.0 else log(10.0) / density


func _update_views() -> void:
	gpu_label.text = "GPU %.1f ms" % _gpu_ms()
	var sun_col := Color(1.0, 0.85, 0.6)
	if doc.sky:
		sun_col = UtopiaSkyController.sun_color_for(float(doc.sky_vals.sun_elevation)) * (doc.sky_vals.sun_tint as Color)
		sun_dial.show_sun(float(doc.sky_vals.sun_azimuth), float(doc.sky_vals.sun_elevation), sun_col, _heading())
	var w := doc.weather()
	var t := PackedStringArray()
	t.append("[b]%s[/b]  %s, intensity %.2f" % [_weather_label(doc.weather_file),
			WeatherPreset.Kind.keys()[w.kind].to_lower().replace("_", " ") if w else "-", w.intensity if w else 0.0])
	t.append("Road now: wet %.2f   frost %.2f   dust %.2f   line glow %.2f" % [env.wetness, env.frost, env.dust, env.line_glow])
	var fx := WeatherFx.of(env)
	t.append("Falling: %.2f%s   humidity %.2f" % [env.precipitation,
			("   (%.0f%% shown)" % (fx.shown * 100.0)) if fx and fx.look else "", env.humidity])
	t.append("Wind: %.1f m/s toward %.0f°" % [env.wind_speed,
			fposmod(rad_to_deg(atan2(env.wind_direction.x, -env.wind_direction.y)), 360.0)])
	if doc.sky:
		var reach := fog_reach(doc.sky.fog_density)
		t.append("Distance fog: 90%% at %s   height fog %.3f" % [
				"never" if is_inf(reach) else "%d m" % roundi(reach), doc.environment.fog_height_density if doc.environment else 0.0])
		var s := doc.sky.get_node_or_null(doc.sky.sun) as DirectionalLight3D
		t.append("Sun: el %.1f°, light %.2f, cloud cover %.2f" % [doc.sky.sun_elevation,
				s.light_energy if s else 0.0, doc.sky.coverage])
	t.append("[color=#8aa]%s, %.0f m along the lap[/color]" % [track_id, cam.d])
	readout.text = "\n".join(t)


func _measure_exposure() -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return    # headless: there's no frame
	if not ui.visible:
		exposure.measure(img)
		return
	var area := Rect2i(0, int(TOP_H), img.get_width() - int(SIDE_W), img.get_height() - int(TOP_H + BOTTOM_H))
	if area.size.x > 16 and area.size.y > 16:
		exposure.measure(img.get_region(area))


# =============================================================================
# CHECKS
# =============================================================================

func _run_checks() -> void:
	checks.clear()
	var items := []    # [text, weather file or ""]
	var known: Array = UtopiaSkyController.PRESETS.keys()
	for f: String in weather_files:
		var w: WeatherPreset = doc.weathers[f]
		var name := _weather_label(f)
		if w.sky_preset != "" and w.sky_preset not in known:
			items.append(["%s: sky preset '%s' doesn't exist" % [name, w.sky_preset], f])
		if w.sky_preset == "" and w.sky_mood > 0.0:
			items.append(["%s: sky_mood does nothing without a sky preset" % name, f])
		var falls := w.kind in [WeatherPreset.Kind.RAIN, WeatherPreset.Kind.SNOW, WeatherPreset.Kind.DUST_STORM]
		if falls and w.precipitation <= 0.0:
			items.append(["%s: nothing falls (precipitation 0)" % name, f])
		if not falls and w.precipitation > 0.0:
			items.append(["%s: precipitation does nothing in %s" % [name, WeatherPreset.Kind.keys()[w.kind].to_lower()], f])
		if doc.sky:
			var dens: float = w.fog_density if w.fog_density >= 0.0 else float(doc.sky_vals.fog_density)
			var reach := fog_reach(dens)
			if reach < FOG_NEAR_M:
				items.append(["%s: distance fog 90%% at %d m" % [name, roundi(reach)], f])
	for stem: String in doc.looks:
		var l: PrecipLook = doc.looks[stem]
		if l.max_length < l.min_length:
			items.append(["%s look: max_length is under min_length" % stem.replace("_", " "), ""])
	if doc.sky:
		if bool(doc.sky_vals.volumetric_shafts):
			items.append(["Volumetric shafts are on: check the GPU time", ""])
		if String(doc.sky_vals.cloud_quality) == "ultra":
			items.append(["Cloud quality ultra: 64 steps, check the GPU time", ""])
		if float(doc.sky_vals.sun_elevation) < 0.0 and float(doc.sky_vals.star_intensity) <= 0.0:
			items.append(["The sun is below the horizon with no stars", ""])
	for it: Array in items:
		var i := checks.add_item(it[0])
		checks.set_item_metadata(i, it[1])
		checks.set_item_custom_fg_color(i, COLOR_WARN)
	if items.is_empty():
		checks.add_item("No problems found")


# =============================================================================
# SAVING
# =============================================================================

func _ask_save() -> void:
	doc.commit()
	if not OS.has_feature("editor"):
		status.text = "Saving needs the Godot editor build"
		return
	var files := doc.dirty_files()
	if files.is_empty():
		status.text = "Nothing to save"
		return
	var mine := PackedStringArray()
	var shared := PackedStringArray()
	for f: String in files:
		var line := "  %s  (%d)" % [f.trim_prefix("res://"), files[f]]
		(shared if f.begins_with(Doc.WEATHER_DIR) else mine).append(line)
	var text := PackedStringArray()
	if not mine.is_empty():
		text.append("This track only:")
		text.append_array(mine)
	if not shared.is_empty():
		text.append("Every track using them:")
		text.append_array(shared)
	save_dialog.dialog_text = "\n".join(text)
	save_dialog.popup_centered()


func _do_save() -> void:
	var errors := doc.save()
	if errors.is_empty():
		_refresh_status()
	else:
		status.text = "Save failed"
		push_error("Sky Lab save: %s" % "; ".join(errors))
