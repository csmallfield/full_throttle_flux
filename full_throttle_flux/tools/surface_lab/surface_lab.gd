extends Node
## Surface Lab: tune the road surface and the greebles together, live on a real
## track, and save the result to the files the game loads. There's nothing to
## bake: the surface and greebles are built from those files when a track loads.
##
## Open tools/surface_lab/surface_lab.tscn and run it (F6), or:
##   godot --path full_throttle_flux res://tools/surface_lab/surface_lab.tscn
##
## Keys: C hold = show the saved look, H = hide the UI, Ctrl+Z / Ctrl+Y = undo /
## redo, Ctrl+S = save, Space = pause the glide. Fly camera: hold the right
## mouse button, WASD + Q/E, Shift for fast, the wheel for speed.
##
## Env: LAB_TRACK track scene name (builder_lab), LAB_SELFTEST 1 = run the self
## test (surface_lab_selftest.gd) and quit.
##
## FTF_SURFACE_LAB.md has the design and limits.

const Doc := preload("res://tools/surface_lab/lab_doc.gd")
const LabCamera := preload("res://tools/surface_lab/lab_camera.gd")
const Rows := preload("res://tools/surface_lab/lab_rows.gd")
const SectionView := preload("res://tools/surface_lab/lab_section_view.gd")
const RhythmView := preload("res://tools/surface_lab/lab_rhythm_view.gd")
const TimelineView := preload("res://tools/surface_lab/lab_timeline_view.gd")

const GB_DIR := "res://scenes/tracks/utopia/greebles"
const VIEW_NAMES := ["Debug: off", "s, t", "Bands", "Panels", "Filter level", "Zones", "Wear", "Mask"]
const MASK_TEX_DIR := "res://resources/track_surface/mask_textures"
const WEAR_TEX := "res://resources/track_surface/wear_detail.png"
const LAYERS := ["ground", "wall_face", "wall_top", "outside", "overhead"]
## Boost pads own this hue range (TrackSurfaceVariation's note).
const ORANGE_HUE := Vector2(20.0 / 360.0, 40.0 / 360.0)
const CHECK_QUIET := 0.7
const COLOR_WARN := Color(1.0, 0.72, 0.3)
const COLOR_OK := Color(0.55, 0.85, 0.75)

var doc: Doc
var track: Node
var spline: Path3D
var env: EnvironmentState
var cam: LabCamera
var gs: Node

var profile_name := "industrial"
var sel_band := 0
var style_name := "civic"
var sel_rule := 0
var follow_camera := true
var solo_rule := false
var neutral_road := false
var hidden_layers := 0

var ui: Control
var section: SectionView
var rhythm: RhythmView
var timeline: TimelineView
var tabs: TabContainer
var band_list: ItemList
var band_rows: Rows
var band_problems: Label
var profile_opt: OptionButton
var road_rows: Rows
var wall_rows: Rows
var mat_rows: Rows
var mask_rows: Rows
var mask_opt: OptionButton
var mask_note: Label
var mask_tex_names: Array = ["none"]
var mask_textures := {}
var variation_opt: OptionButton
var style_opt: OptionButton
var style_rows: Rows
var rule_list: ItemList
var rule_rows: Rows
var solo_btn: CheckButton
var cost_text: RichTextLabel
var checks: ItemList
var save_btn: Button
var undo_btn: Button
var redo_btn: Button
var status: Label
var gpu_label: Label
var compare_btn: Button
var save_dialog: ConfirmationDialog
var snap_btns := {}
var snaps := {}

var mesh_names: Array = ["none"]
var meshes := {}
var neutral_mat: StandardMaterial3D
var geometry: Array[MeshInstance3D] = []

var _compare_hold := {}
var _comparing := false
var _ui_dirty := false
var _views_wait := 0.0
var _cost_wait := 0.0
var _check_wait := -1.0
var _check_baseline := {}
var _check_items := {}       # style name or "" -> [{text, d}]
var _status_wait := 0.0
var follow_box: CheckBox
var _tri_cache := {}
var _gpu_samples := PackedFloat32Array()
var _last_zone_style := ""
var _last_zone_profile := ""


func _ready() -> void:
	get_tree().auto_accept_quit = false
	gs = get_node_or_null("/root/GraphicsSettings")
	var track_id := OS.get_environment("LAB_TRACK")
	if track_id == "":
		track_id = "builder_lab"
	track = (load("res://scenes/tracks/%s.tscn" % track_id) as PackedScene).instantiate()
	add_child(track)
	await get_tree().process_frame
	await get_tree().process_frame    # TrackSurface.apply() is deferred
	spline = track.find_child("MainSpline", true, false) as Path3D
	var profile_path := "res://resources/tracks/%s.tres" % track_id
	var profile: Resource = load(profile_path) if ResourceLoader.exists(profile_path) else null
	if gs and profile:
		gs.apply_track(track, profile.get("shadow_profile"))
	doc = Doc.new()
	doc.setup(track)
	doc.changed.connect(func(): _ui_dirty = true)
	env = EnvironmentState.install(self, track, profile as TrackProfile)
	cam = LabCamera.new()
	add_child(cam)
	cam.setup(track, spline)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_find_geometry()
	_load_meshes()
	_load_mask_textures()
	if doc.profiles.size() > 0 and not doc.profiles.has(profile_name):
		profile_name = doc.profiles.keys()[0]
	if doc.styles.size() > 0 and not doc.styles.has(style_name):
		style_name = doc.styles.keys()[0]
	_build_ui()
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	_select_profile(profile_name)
	_select_style(style_name)
	_rebuild_look_tabs()
	_run_checks(true)
	_refresh_all()
	if OS.get_environment("LAB_SELFTEST") == "1":
		var t: Node = load("res://tools/surface_lab/surface_lab_selftest.gd").new()
		t.lab = self
		add_child(t)
	elif OS.get_environment("LAB_TOUR") != "":
		var t: Node = load("res://tools/surface_lab/surface_lab_tour.gd").new()
		t.lab = self
		add_child(t)


func _find_geometry() -> void:
	for n in track.find_children("*", "TrackRoadSegment", true, false):
		var mi := (n as TrackRoadSegment).mesh_instance()
		if mi:
			geometry.append(mi)
	for n in track.find_children("*", "TrackJunction", true, false):
		for c in n.get_children(true):
			if c is MeshInstance3D:
				geometry.append(c)
	neutral_mat = StandardMaterial3D.new()
	neutral_mat.albedo_color = Color(0.35, 0.35, 0.35)
	neutral_mat.roughness = 0.8


func _load_mask_textures() -> void:
	var dir := DirAccess.open(MASK_TEX_DIR)
	if dir:
		var files := Array(dir.get_files())
		files.sort()
		for f: String in files:
			if f.ends_with(".png"):
				mask_textures[f.get_basename()] = load("%s/%s" % [MASK_TEX_DIR, f])
				mask_tex_names.append(f.get_basename())
	if ResourceLoader.exists(WEAR_TEX):
		mask_textures["wear_detail"] = load(WEAR_TEX)
		mask_tex_names.append("wear_detail")


func _load_meshes() -> void:
	var dir := DirAccess.open(GB_DIR)
	if dir == null:
		return
	var files := Array(dir.get_files())
	files.sort()
	for f: String in files:
		f = f.trim_suffix(".remap")
		if f.begins_with("gb_") and f.ends_with(".tres"):
			var name := f.trim_prefix("gb_").trim_suffix(".tres")
			meshes[name] = load("%s/%s" % [GB_DIR, f])
			mesh_names.append(name)


# =============================================================================
# EVERY FRAME
# =============================================================================

func _process(delta: float) -> void:
	if doc == null:
		return
	doc.tick(delta)
	# Working out what's unsaved reads every value: not on every slider tick.
	_status_wait -= delta
	if _ui_dirty and _status_wait <= 0.0:
		_ui_dirty = false
		_status_wait = 0.3
		_refresh_status()
		_check_wait = CHECK_QUIET
		_cost_wait = minf(_cost_wait, 0.15)
	if _check_wait > 0.0:
		_check_wait -= delta
		if _check_wait <= 0.0 and not _comparing:
			_run_checks()
	_views_wait -= delta
	if _views_wait <= 0.0:
		_views_wait = 0.1
		_update_views()
	var vp := get_viewport().get_viewport_rid()
	_gpu_samples.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	if _gpu_samples.size() > 60:
		_gpu_samples.remove_at(0)
	_cost_wait -= delta
	if _cost_wait <= 0.0:
		_cost_wait = 0.5
		_update_cost()


func _input(event: InputEvent) -> void:
	# While looking around the mouse belongs to the camera, whatever's under it.
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
	elif k.ctrl_pressed and k.physical_keycode == KEY_Z:
		if doc.undo():
			_after_restore()
	elif k.ctrl_pressed and k.physical_keycode == KEY_Y:
		if doc.redo():
			_after_restore()
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
	if gs:
		gs.set_surface_view(0)


# =============================================================================
# THE ZONE UNDER THE CAMERA
# =============================================================================

static func _zone_at(zones: Array, d: float, lap: float) -> Variant:
	for z in zones:
		var from: float = z.from_d
		var to: float = z.to_d
		if to <= from:
			to += lap
		if (d >= from and d < to) or (d + lap >= from and d + lap < to):
			return z
	return null


func _surface_zones() -> Array[TrackSurfaceZone]:
	return doc.surface.zones_of(0) if doc.surface else ([] as Array[TrackSurfaceZone])


func _greeble_zones() -> Array:
	var out := []
	if doc.greebles:
		for z in doc.greebles.zones:
			if z and z.path_index == 0:
				out.append(z)
	return out


func _update_views() -> void:
	var d := cam.d
	var lap := cam.length()
	var sz: TrackSurfaceZone = _zone_at(_surface_zones(), d, lap)
	var gz: TrackGreebleZone = _zone_at(_greeble_zones(), d, lap)
	# Not while editing: the panel would change under the slider.
	if follow_camera and doc.since_edit > 2.0:
		if sz and sz.profile and sz.profile.resource_path != _last_zone_profile:
			_last_zone_profile = sz.profile.resource_path
			var name := _name_of(doc.profiles, sz.profile)
			if name != "" and name != profile_name:
				_select_profile(name)
		var gs_path := gz.style.resource_path if gz and gz.style else ""
		if gs_path != _last_zone_style:
			_last_zone_style = gs_path
			if gz and gz.style:
				var name := _name_of(doc.styles, gz.style)
				if name != "" and name != style_name:
					_select_style(name)
	var seg := _road_segment(d)
	section.profile = doc.profiles.get(profile_name)
	section.style = doc.styles.get(style_name)
	section.greebles = doc.greebles
	section.mirror_zone = gz.mirror if gz else false
	section.selected_band = sel_band
	section.selected_rule = sel_rule
	if seg:
		section.half = seg.surface_half_widths_at(d)
		section.edge = seg.width_at(d)
	section.queue_redraw()
	rhythm.d = d
	rhythm.lap = lap
	rhythm.panel_len = _param_value(doc.road_base, "panel_len", 6.0)
	rhythm.wall_panel_len = _param_value(doc.wall_base, "wall_panel_len", 5.0)
	rhythm.seam_band = sel_band
	rhythm.seed_value = float(sz.seed) if sz else 0.0
	rhythm.zone = gz
	rhythm.selected_rule = sel_rule if gz and gz.style == doc.styles.get(style_name) else -1
	rhythm.queue_redraw()
	timeline.lap = lap
	timeline.d = d
	timeline.surface_zones = _surface_zones()
	timeline.greeble_zones = _greeble_zones()
	timeline.queue_redraw()


static func _param_value(m: ShaderMaterial, p: String, fallback: float) -> float:
	var v: Variant = m.get_shader_parameter(p)
	return float(v) if v != null else fallback


## The name of the greeble style in the zone under the camera, or the selected one.
func _style_at_camera() -> String:
	var gz: TrackGreebleZone = _zone_at(_greeble_zones(), cam.d, cam.length())
	var name := _name_of(doc.styles, gz.style) if gz and gz.style else ""
	return name if name != "" else style_name


func _road_segment(d: float) -> TrackRoadSegment:
	for seg in TrackSurface._road_segments(spline):
		var d1 := seg.end_distance if seg.end_distance >= 0.0 else INF
		if d >= seg.start_distance and d <= d1:
			return seg
	var all := TrackSurface._road_segments(spline)
	return all[0] if not all.is_empty() else null


static func _name_of(table: Dictionary, res: Resource) -> String:
	for k: String in table:
		if table[k] == res:
			return k
	return ""


# =============================================================================
# UI: FRAME
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


func _build_top_bar() -> void:
	var p := _panel()
	p.set_anchors_preset(Control.PRESET_TOP_WIDE)
	ui.add_child(p)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	p.add_child(bar)
	var title := Label.new()
	title.text = "Surface Lab"
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
	var names: Array = []
	var presets := env.weather_choices()
	for w in presets:
		names.append(w.display_name)
	var weather := _option(bar, names, maxi(presets.find(env.weather), 0))
	weather.item_selected.connect(func(i: int): env.apply_weather(presets[i], true))
	var view := _option(bar, VIEW_NAMES, 0)
	view.item_selected.connect(func(i: int):
		if gs:
			gs.set_surface_view(i))
	bar.add_child(VSeparator.new())
	var road := CheckButton.new()
	road.text = "Road"
	road.button_pressed = true
	road.tooltip_text = "Off: a plain grey road and walls, to judge the greebles alone."
	road.toggled.connect(_set_road_look)
	bar.add_child(road)
	var greebles := CheckButton.new()
	greebles.text = "Greebles"
	greebles.button_pressed = true
	greebles.toggled.connect(func(on: bool):
		if doc.greebles:
			doc.greebles.visible = on)
	bar.add_child(greebles)
	for i in LAYERS.size():
		var b := CheckBox.new()
		b.text = String(LAYERS[i]).replace("_", " ")
		b.button_pressed = true
		b.add_theme_font_size_override("font_size", 12)
		b.toggled.connect(func(on: bool): _set_layer(i, on))
		bar.add_child(b)
	bar.add_child(VSeparator.new())
	compare_btn = Button.new()
	compare_btn.text = "Hold C: saved"
	compare_btn.tooltip_text = "Hold to see the saved look of both layers."
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
			_after_restore())
	bar.add_child(undo_btn)
	redo_btn = Button.new()
	redo_btn.text = "Redo"
	redo_btn.pressed.connect(func():
		if doc.redo():
			_after_restore())
	bar.add_child(redo_btn)
	save_btn = Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(_ask_save)
	bar.add_child(save_btn)


func _option(parent: Control, names: Array, selected: int) -> OptionButton:
	var o := OptionButton.new()
	for n in names:
		o.add_item(str(n))
	o.select(selected)
	o.focus_mode = Control.FOCUS_NONE
	parent.add_child(o)
	return o


func _build_side_panel() -> void:
	var p := _panel()
	p.anchor_left = 1.0
	p.anchor_right = 1.0
	p.anchor_bottom = 1.0
	p.offset_left = -470.0
	p.offset_top = 46.0
	p.offset_bottom = -216.0
	ui.add_child(p)
	var col := VBoxContainer.new()
	p.add_child(col)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 13)
	col.add_child(tabs)
	_build_bands_tab()
	road_rows = _scroll_tab("Road", true)
	_build_mask_tab()
	wall_rows = _scroll_tab("Walls", false)
	_build_greebles_tab()
	mat_rows = _scroll_tab("Materials", false)
	_build_cost_tab()
	var head := Label.new()
	head.text = "Checks (double-click to go there)"
	head.add_theme_font_size_override("font_size", 12)
	col.add_child(head)
	checks = ItemList.new()
	checks.custom_minimum_size = Vector2(0, 92)
	checks.add_theme_font_size_override("font_size", 12)
	checks.item_activated.connect(func(i: int):
		var at: Variant = checks.get_item_metadata(i)
		if at != null and float(at) >= 0.0:
			cam.jump(float(at)))
	col.add_child(checks)


func _scroll_tab(title: String, with_variation: bool) -> Rows:
	var col := VBoxContainer.new()
	col.name = title
	tabs.add_child(col)
	if with_variation:
		var hb := HBoxContainer.new()
		col.add_child(hb)
		var l := Label.new()
		l.text = "Variation"
		hb.add_child(l)
		variation_opt = OptionButton.new()
		variation_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		variation_opt.clip_text = true
		variation_opt.item_selected.connect(_on_variation_selected)
		hb.add_child(variation_opt)
		var edit := LineEdit.new()
		edit.placeholder_text = "new name"
		edit.custom_minimum_size = Vector2(90, 0)
		hb.add_child(edit)
		var add := Button.new()
		add.text = "New"
		add.pressed.connect(func():
			if edit.text.strip_edges() != "":
				var f: String = doc.new_variation(edit.text.strip_edges())
				if f != "":
					edit.text = ""
					_fill_variation_opt()
					doc.set_v("var", f)
					_select_variation_item(f)
					_rebuild_look_tabs())
		hb.add_child(add)
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
	p.offset_top = -214.0
	ui.add_child(p)
	var col := VBoxContainer.new()
	p.add_child(col)
	var hb := HBoxContainer.new()
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(hb)
	section = SectionView.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.size_flags_stretch_ratio = 1.2
	section.band_selected.connect(_select_band)
	section.rule_selected.connect(func(i: int):
		_select_rule(i)
		tabs.current_tab = tabs.get_tab_idx_from_control(tabs.get_node("Greebles")))
	section.band_width_dragged.connect(func(i: int, w: float): _set_band_field(i, 1, w))
	section.pin_dragged.connect(func(ri: int, lateral: float):
		doc.set_v("style:%s/rule:%d/lateral" % [style_name, ri], lateral)
		rule_rows.refresh())
	hb.add_child(section)
	rhythm = RhythmView.new()
	rhythm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(rhythm)
	timeline = TimelineView.new()
	timeline.jump_requested.connect(func(d: float): cam.jump(d))
	col.add_child(timeline)


# =============================================================================
# UI: BANDS
# =============================================================================

func _build_bands_tab() -> void:
	var col := VBoxContainer.new()
	col.name = "Bands"
	tabs.add_child(col)
	var hb := HBoxContainer.new()
	col.add_child(hb)
	var names := doc.profiles.keys()
	profile_opt = _option(hb, names, 0)
	profile_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_opt.item_selected.connect(func(i: int): _pick_profile(names[i]))
	follow_box = CheckBox.new()
	follow_box.text = "Follow camera"
	follow_box.button_pressed = follow_camera
	follow_box.tooltip_text = "Show the profile and style of the zone under the camera."
	follow_box.toggled.connect(func(on: bool): follow_camera = on)
	hb.add_child(follow_box)
	var mirror := CheckBox.new()
	mirror.text = "Mirror"
	mirror.toggled.connect(func(on: bool):
		if on != bool(doc.get_v("prof:%s/mirror" % profile_name)):
			doc.set_v("prof:%s/mirror" % profile_name, on)
			_fill_band_list())
	mirror.name = "MirrorBox"
	hb.add_child(mirror)
	band_list = ItemList.new()
	band_list.custom_minimum_size = Vector2(0, 160)
	band_list.add_theme_font_size_override("font_size", 13)
	band_list.item_selected.connect(_select_band)
	col.add_child(band_list)
	var tools := HBoxContainer.new()
	col.add_child(tools)
	for spec: Array in [["Add", _band_add], ["Copy", _band_copy], ["Delete", _band_delete],
			["Up", func(): _band_move(-1)], ["Down", func(): _band_move(1)]]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(spec[1])
		tools.add_child(b)
	var note := Label.new()
	note.text = "Saved to the profile: every zone using it, on every track."
	note.add_theme_color_override("font_color", COLOR_WARN)
	note.add_theme_font_size_override("font_size", 12)
	col.add_child(note)
	band_rows = Rows.new()
	col.add_child(band_rows)
	band_problems = Label.new()
	band_problems.add_theme_color_override("font_color", COLOR_WARN)
	band_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(band_problems)


func _pick_profile(name: String) -> void:
	_stop_following()
	_select_profile(name)


func _stop_following() -> void:
	follow_camera = false
	follow_box.set_pressed_no_signal(false)


func _bands_data() -> Array:
	return (doc.get_v("prof:%s/bands" % profile_name) as Array).duplicate(true)


func _set_bands(data: Array) -> void:
	doc.set_v("prof:%s/bands" % profile_name, data)
	_fill_band_list()


func _set_band_field(i: int, field: int, value: Variant) -> void:
	var data := _bands_data()
	if i < 0 or i >= data.size():
		return
	(data[i] as Array)[field] = value
	_set_bands(data)
	band_rows.refresh()
	if field == 0 or field == 2:
		_build_band_rows()


func _band_add() -> void:
	var data := _bands_data()
	data.insert(mini(sel_band + 1, data.size()), [int(TrackSurfaceBand.Type.CHANNEL), 0.3, 0.0, 0, false, 1.0])
	_set_bands(data)
	_select_band(mini(sel_band + 1, data.size() - 1))


func _band_copy() -> void:
	var data := _bands_data()
	if data.is_empty():
		return
	data.insert(sel_band + 1, (data[sel_band] as Array).duplicate())
	_set_bands(data)
	_select_band(sel_band + 1)


func _band_delete() -> void:
	var data := _bands_data()
	if data.size() <= 1:
		return
	data.remove_at(sel_band)
	_set_bands(data)
	_select_band(clampi(sel_band, 0, data.size() - 1))


func _band_move(by: int) -> void:
	var data := _bands_data()
	var to := sel_band + by
	if to < 0 or to >= data.size():
		return
	var b: Variant = data[sel_band]
	data[sel_band] = data[to]
	data[to] = b
	_set_bands(data)
	_select_band(to)


func _select_profile(name: String) -> void:
	profile_name = name
	var keys := doc.profiles.keys()
	profile_opt.select(keys.find(name))
	sel_band = clampi(sel_band, 0, maxi((doc.get_v("prof:%s/bands" % name) as Array).size() - 1, 0))
	_fill_band_list()
	_build_band_rows()


func _select_band(i: int) -> void:
	sel_band = i
	if i < band_list.item_count:
		band_list.select(i)
	_build_band_rows()
	tabs.current_tab = tabs.get_tab_idx_from_control(tabs.get_node("Bands"))


func _fill_band_list() -> void:
	band_list.clear()
	var pr: TrackSurfaceProfile = doc.profiles[profile_name]
	var data: Array = doc.get_v("prof:%s/bands" % profile_name)
	for e: Array in data:
		var t: String = TrackSurfaceBand.Type.keys()[e[0]].to_lower()
		var w := "flex %.1f" % e[2] if e[2] > 0.0 else "%.2f m" % e[1]
		var extra := ""
		if e[0] == TrackSurfaceBand.Type.CHANNEL and e[3] > 0:
			extra = "  " + TrackSurfaceBand.Light.keys()[e[3]].to_lower().replace("_", " ")
		elif e[0] == TrackSurfaceBand.Type.PLATE and e[4]:
			extra = "  vents"
		band_list.add_item("%-8s %s%s" % [t, w, extra])
	if sel_band < band_list.item_count:
		band_list.select(sel_band)
	var mirror := tabs.get_node("Bands").find_child("MirrorBox", true, false) as CheckBox
	mirror.set_pressed_no_signal(pr.mirror)
	var probs := pr.problems()
	band_problems.text = "\n".join(probs)
	_check_wait = CHECK_QUIET


func _build_band_rows() -> void:
	band_rows.clear_rows()
	var data := _bands_data()
	if sel_band >= data.size():
		return
	var e: Array = data[sel_band]
	var i := sel_band
	var type_names := []
	for k in TrackSurfaceBand.Type.keys():
		type_names.append(k.to_lower())
	band_rows.add_row({name = "type", type = TYPE_INT, choices = type_names,
			get = func(): return _bands_data()[i][0],
			set = func(v: int): _set_band_field(i, 0, v)})
	if e[2] <= 0.0:
		band_rows.add_row({name = "width", type = TYPE_FLOAT, hint = PROPERTY_HINT_RANGE, hint_string = "0.05,40,0.05",
				get = func(): return _bands_data()[i][1],
				set = func(v: float): _set_band_field(i, 1, v)})
	band_rows.add_row({name = "flex", type = TYPE_FLOAT, hint = PROPERTY_HINT_RANGE, hint_string = "0,10,0.1",
			tooltip = "Above 0: this band shares what the fixed bands leave.",
			get = func(): return _bands_data()[i][2],
			set = func(v: float): _set_band_field(i, 2, v)})
	if e[0] == TrackSurfaceBand.Type.CHANNEL:
		var lights := []
		for k in TrackSurfaceBand.Light.keys():
			lights.append(k.to_lower())
		band_rows.add_row({name = "light", type = TYPE_INT, choices = lights,
				get = func(): return _bands_data()[i][3],
				set = func(v: int): _set_band_field(i, 3, v)})
	elif e[0] == TrackSurfaceBand.Type.PLATE:
		band_rows.add_row({name = "vents", type = TYPE_BOOL,
				get = func(): return _bands_data()[i][4],
				set = func(v: bool): _set_band_field(i, 4, v)})
	if e[0] != TrackSurfaceBand.Type.CHANNEL:
		band_rows.add_row({name = "mask_amount", type = TYPE_FLOAT, hint = PROPERTY_HINT_RANGE, hint_string = "0,1,0.01",
				tooltip = "How strongly the track's surface mask reaches this band.",
				get = func(): return _bands_data()[i][5],
				set = func(v: float): _set_band_field(i, 5, v)})


# =============================================================================
# UI: ROAD, WALLS, MATERIALS
# =============================================================================

func _fill_variation_opt() -> void:
	variation_opt.clear()
	variation_opt.add_item("None: style only")
	variation_opt.set_item_metadata(0, "")
	for f: String in doc.variations:
		variation_opt.add_item(f.trim_prefix("variation_").trim_suffix(".tres"))
		variation_opt.set_item_metadata(variation_opt.item_count - 1, f)
	_select_variation_item(doc.variation_file)


func _select_variation_item(file: String) -> void:
	for i in variation_opt.item_count:
		if variation_opt.get_item_metadata(i) == file:
			variation_opt.select(i)


func _on_variation_selected(i: int) -> void:
	doc.set_v("var", variation_opt.get_item_metadata(i))
	road_rows.refresh()
	wall_rows.refresh()
	_fill_mask_opt()
	_build_mask_rows()


func _rebuild_look_tabs() -> void:
	_fill_variation_opt()
	_fill_param_rows(road_rows, doc.road_params, "road", doc.road_base, true)
	_fill_param_rows(wall_rows, doc.wall_params, "wall", doc.wall_base, false)
	mat_rows.clear_rows()
	for m: String in doc.materials:
		mat_rows.add_group(m)
		for spec: Array in [["albedo_color", TYPE_COLOR, ""], ["roughness", TYPE_FLOAT, "0,1,0.01"],
				["metallic", TYPE_FLOAT, "0,1,0.01"], ["emission", TYPE_COLOR, ""],
				["emission_energy_multiplier", TYPE_FLOAT, "0,16,0.05"]]:
			var key := "mat:%s/%s" % [m, spec[0]]
			mat_rows.add_row({name = spec[0], type = spec[1], hint_string = spec[2],
					hint = PROPERTY_HINT_RANGE if spec[2] != "" else PROPERTY_HINT_NONE,
					badge = "all tracks", badge_warn = true,
					tooltip = "Shared by every greeble mesh using it, on every track and baked dressing.",
					get = func(): return doc.get_v(key),
					set = func(v: Variant): doc.set_v(key, v)})


func _fill_param_rows(rows: Rows, params: Array[Dictionary], prefix: String, base: ShaderMaterial,
		overridable: bool) -> void:
	rows.clear_rows()
	var group := ""
	var shader_rid := base.shader.get_rid()
	for p in params:
		if p.group != group:
			group = p.group
			rows.add_group(group, group == "materials")
		var name: String = p.name
		var spec: Dictionary = {name = name, type = p.type, hint = p.hint, hint_string = p.hint_string, badge = ""}
		var fallback: Variant = RenderingServer.shader_get_parameter_default(shader_rid, name)
		if overridable and name in TrackSurfaceVariation.PARAMS:
			spec.override = func(on: bool): _set_override(name, on, fallback)
			spec.is_override = func(): return doc.variation_override(name) != null
			spec.get = func() -> Variant:
				var o: Variant = doc.variation_override(name)
				if o != null:
					return o
				var v: Variant = base.get_shader_parameter(name)
				return v if v != null else fallback
			spec.set = func(v: Variant):
				if doc.variation_override(name) != null:
					doc.set_v("var:%s/%s" % [doc.variation_file, name], _to_variation(v))
				else:
					doc.set_v("%s/%s" % [prefix, name], v)
			spec.badge_fn = func() -> Array:
				return ["this track", false] if doc.variation_override(name) != null else ["all tracks", true]
		else:
			spec.get = func() -> Variant:
				var v: Variant = base.get_shader_parameter(name)
				return v if v != null else fallback
			spec.set = func(v: Variant): doc.set_v("%s/%s" % [prefix, name], v)
			spec.badge_fn = func() -> Array:
				return ["variation overrides", true] if doc.variation_override(name) != null else ["all tracks", true]
		spec.badge_warn = true
		rows.add_row(spec)


static func _to_variation(v: Variant) -> Variant:
	if v is Vector3:
		return Color((v as Vector3).x, (v as Vector3).y, (v as Vector3).z, 1.0)
	if v is Color:
		var c: Color = v
		c.a = 1.0
		return c
	return v


func _set_override(name: String, on: bool, fallback: Variant) -> void:
	if doc.variation_file == "":
		var keys := get_node_or_null("/root/DebugKeys")
		if keys:
			keys.toast("Pick or make a variation first")
		return
	var key := "var:%s/%s" % [doc.variation_file, name]
	if on:
		var v: Variant = doc.road_base.get_shader_parameter(name)
		doc.set_v(key, _to_variation(v if v != null else fallback))
	else:
		doc.set_v(key, Color(0, 0, 0, 0) if doc.get_v(key) is Color else -1.0)
	road_rows.refresh()


# =============================================================================
# UI: SURFACE MASK
# =============================================================================

func _build_mask_tab() -> void:
	var col := VBoxContainer.new()
	col.name = "Mask"
	tabs.add_child(col)
	var hb := HBoxContainer.new()
	col.add_child(hb)
	var l := Label.new()
	l.text = "Recipe"
	hb.add_child(l)
	mask_opt = OptionButton.new()
	mask_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mask_opt.clip_text = true
	mask_opt.focus_mode = Control.FOCUS_NONE
	mask_opt.item_selected.connect(func(i: int): _pick_mask(mask_opt.get_item_metadata(i)))
	hb.add_child(mask_opt)
	var edit := LineEdit.new()
	edit.placeholder_text = "new name"
	edit.custom_minimum_size = Vector2(90, 0)
	hb.add_child(edit)
	var add := Button.new()
	add.text = "New"
	add.pressed.connect(func():
		if edit.text.strip_edges() != "":
			var f: String = doc.new_mask(edit.text.strip_edges())
			if f != "":
				edit.text = ""
				var fresh: TrackSurfaceMask = doc.masks[f]
				if mask_tex_names.size() > 1:
					fresh.a_texture = mask_textures[mask_tex_names[1]]
				_pick_mask(f))
	hb.add_child(add)
	mask_note = Label.new()
	mask_note.add_theme_font_size_override("font_size", 12)
	mask_note.add_theme_color_override("font_color", COLOR_WARN)
	mask_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(mask_note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	mask_rows = Rows.new()
	mask_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(mask_rows)
	_fill_mask_opt()
	_build_mask_rows()


## Picks what's drawn. With a variation previewed, it's that variation's recipe
## (saved with it); otherwise only a preview.
func _pick_mask(file: String) -> void:
	if doc.variation_file != "":
		doc.set_v("var:%s/mask" % doc.variation_file, doc.masks.get(file))
	doc.set_v("mask", file)
	_fill_mask_opt()
	_build_mask_rows()


func _fill_mask_opt() -> void:
	mask_opt.clear()
	mask_opt.add_item("None")
	mask_opt.set_item_metadata(0, "")
	var cur: String = doc.effective_mask_file()
	if cur == "":
		mask_opt.select(0)
	var files: Array = doc.masks.keys()
	files.sort()
	for f: String in files:
		mask_opt.add_item(f.trim_prefix("mask_").trim_suffix(".tres"))
		mask_opt.set_item_metadata(mask_opt.item_count - 1, f)
		if f == cur:
			mask_opt.select(mask_opt.item_count - 1)
	if doc.variation_file != "":
		mask_note.text = "Choosing a recipe saves it to %s. Editing one reaches every variation using it." \
				% doc.variation_file.trim_prefix("variation_").trim_suffix(".tres")
	else:
		mask_note.text = "Preview only. To use a recipe in a race, pick a variation in the Road tab first, and give the track that variation."


func _build_mask_rows() -> void:
	mask_rows.clear_rows()
	var file: String = doc.effective_mask_file()
	if file == "":
		return
	var base := "mask:%s/" % file
	mask_rows.add_group("Combine", true)
	for p: Dictionary in TrackSurfaceMask.new().get_property_list():
		if p.usage & PROPERTY_USAGE_GROUP:
			if String(p.name) != "Resource":
				mask_rows.add_group(String(p.name), true)
			continue
		if not (p.usage & PROPERTY_USAGE_STORAGE and p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var prop: String = p.name
		var key: String = base + prop
		if p.type == TYPE_OBJECT:
			mask_rows.add_row({name = prop, type = TYPE_STRING, choices = mask_tex_names,
					get = func() -> String:
						var t: Texture2D = doc.get_v(key)
						return t.resource_path.get_file().get_basename() if t else "none",
					set = func(v: String): doc.set_v(key, mask_textures.get(v))})
			continue
		mask_rows.add_row({name = prop, type = p.type, hint = p.hint, hint_string = p.hint_string,
				get = func(): return doc.get_v(key),
				set = func(v: Variant): doc.set_v(key, v)})


# =============================================================================
# UI: GREEBLES
# =============================================================================

func _build_greebles_tab() -> void:
	var col := VBoxContainer.new()
	col.name = "Greebles"
	tabs.add_child(col)
	var names := doc.styles.keys()
	style_opt = _option(col, names, 0)
	style_opt.item_selected.connect(func(i: int):
		_stop_following()
		_select_style(names[i]))
	style_rows = Rows.new()
	col.add_child(style_rows)
	rule_list = ItemList.new()
	rule_list.custom_minimum_size = Vector2(0, 170)
	rule_list.add_theme_font_size_override("font_size", 13)
	rule_list.item_selected.connect(_select_rule)
	col.add_child(rule_list)
	var tools := HBoxContainer.new()
	col.add_child(tools)
	for spec: Array in [["Add", _rule_add], ["Copy", _rule_copy], ["Delete", _rule_delete]]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(spec[1])
		tools.add_child(b)
	solo_btn = CheckButton.new()
	solo_btn.text = "Solo rule"
	solo_btn.toggled.connect(func(on: bool):
		solo_rule = on
		_apply_greeble_display())
	tools.add_child(solo_btn)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	rule_rows = Rows.new()
	rule_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rule_rows)


func _select_style(name: String) -> void:
	style_name = name
	style_opt.select(doc.styles.keys().find(name))
	var st: UtopiaGreebleStyle = doc.styles[name]
	sel_rule = clampi(sel_rule, 0, maxi(st.rules.size() - 1, 0))
	style_rows.clear_rows()
	style_rows.add_row({name = "bay_length", type = TYPE_FLOAT, hint = PROPERTY_HINT_RANGE, hint_string = "4,80,0.5",
			badge = "all tracks", badge_warn = true,
			tooltip = "Every rule's rhythm, in metres along the road.",
			get = func(): return doc.get_v("style:%s/bay_length" % name),
			set = func(v: float): doc.set_v("style:%s/bay_length" % name, v)})
	_fill_rule_list()
	_build_rule_rows()
	_apply_greeble_display()


func _select_rule(i: int) -> void:
	sel_rule = i
	if i < rule_list.item_count:
		rule_list.select(i)
	_build_rule_rows()
	_apply_greeble_display()


func _rule_counts() -> Dictionary:
	var out := {}
	if doc.greebles == null:
		return out
	var st: UtopiaGreebleStyle = doc.styles[style_name]
	for g in doc.greebles.group_info():
		if doc.greebles.zones[g.zi].style == st:
			out[g.ri] = int(out.get(g.ri, 0)) + int(g.count)
	return out


func _fill_rule_list() -> void:
	rule_list.clear()
	var st: UtopiaGreebleStyle = doc.styles[style_name]
	var counts := _rule_counts()
	for i in st.rules.size():
		var r := st.rules[i]
		var mesh_name := r.mesh.resource_path.get_file().get_basename().trim_prefix("gb_") if r.mesh else "none"
		rule_list.add_item("%-9s %s  x%d%s" % [r.layer.replace("_", " "), mesh_name, int(counts.get(i, 0)),
				"" if r.enabled else "  (off)"])
	if sel_rule < rule_list.item_count:
		rule_list.select(sel_rule)


func _build_rule_rows() -> void:
	rule_rows.clear_rows()
	var st: UtopiaGreebleStyle = doc.styles[style_name]
	if sel_rule >= st.rules.size():
		return
	var i := sel_rule
	var base := "style:%s/rule:%d/" % [style_name, i]
	rule_rows.add_group("Rule", true)
	for p: Dictionary in UtopiaGreebleRule.new().get_property_list():
		if p.usage & PROPERTY_USAGE_GROUP:
			if String(p.name) != "Resource":
				rule_rows.add_group(String(p.name), true)
			continue
		if not (p.usage & PROPERTY_USAGE_STORAGE and p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var prop: String = p.name
		var key: String = base + prop
		if p.type == TYPE_OBJECT:
			rule_rows.add_row({name = prop, type = TYPE_STRING, choices = mesh_names,
					get = func() -> String:
						var m: Mesh = doc.get_v(key)
						return m.resource_path.get_file().get_basename().trim_prefix("gb_") if m else "none",
					set = func(v: String):
						doc.set_v(key, meshes.get(v))
						_fill_rule_list()})
			continue
		rule_rows.add_row({name = prop, type = p.type, hint = p.hint, hint_string = p.hint_string,
				get = func(): return doc.get_v(key),
				set = func(v: Variant):
					doc.set_v(key, v)
					if prop in ["layer", "enabled"]:
						_fill_rule_list()})


func _rule_add() -> void:
	var st: UtopiaGreebleStyle = doc.styles[style_name]
	var n := st.rules.size()
	doc.set_v("style:%s/n" % style_name, n + 1)
	if mesh_names.size() > 1:
		doc.set_v("style:%s/rule:%d/mesh" % [style_name, n], meshes[mesh_names[1]])
	_fill_rule_list()
	_select_rule(n)


func _rule_copy() -> void:
	var st: UtopiaGreebleStyle = doc.styles[style_name]
	var n := st.rules.size()
	if sel_rule >= n:
		return
	doc.set_v("style:%s/n" % style_name, n + 1)
	for prop in Doc.rule_props():
		doc.set_v("style:%s/rule:%d/%s" % [style_name, n, prop], st.rules[sel_rule].get(prop))
	_fill_rule_list()
	_select_rule(n)


func _rule_delete() -> void:
	var st: UtopiaGreebleStyle = doc.styles[style_name]
	var n := st.rules.size()
	if sel_rule >= n:
		return
	for i in range(sel_rule, n - 1):
		for prop in Doc.rule_props():
			doc.set_v("style:%s/rule:%d/%s" % [style_name, i, prop], st.rules[i + 1].get(prop))
	doc.set_v("style:%s/n" % style_name, n - 1)
	sel_rule = clampi(sel_rule, 0, maxi(n - 2, 0))
	_fill_rule_list()
	_build_rule_rows()


func _set_layer(i: int, on: bool) -> void:
	var bit: int = TrackGreebles.LAYER_BITS[LAYERS[i]]
	hidden_layers = (hidden_layers & ~bit) if on else (hidden_layers | bit)
	_apply_greeble_display()


func _apply_greeble_display() -> void:
	if doc.greebles == null:
		return
	if solo_rule:
		doc.greebles.set_display(hidden_layers, doc.styles[style_name], sel_rule)
	else:
		doc.greebles.set_display(hidden_layers)


func _set_road_look(full: bool) -> void:
	neutral_road = not full
	for mi in geometry:
		if is_instance_valid(mi):
			mi.material_override = null if full else neutral_mat


# =============================================================================
# UI: COST
# =============================================================================

func _build_cost_tab() -> void:
	cost_text = RichTextLabel.new()
	cost_text.name = "Cost"
	cost_text.bbcode_enabled = true
	cost_text.scroll_following = false
	cost_text.selection_enabled = true
	tabs.add_child(cost_text)


func _gpu_ms() -> float:
	if _gpu_samples.is_empty():
		return 0.0
	var s := _gpu_samples.duplicate()
	s.sort()
	return s[s.size() / 2]


func _tris(m: Mesh) -> int:
	if m == null:
		return 0
	if not _tri_cache.has(m):
		_tri_cache[m] = m.get_faces().size() / 3
	return _tri_cache[m]


func _update_cost() -> void:
	var gpu := _gpu_ms()
	var rs := RenderingServer
	gpu_label.text = "GPU %.1f ms" % gpu
	if tabs.current_tab != tabs.get_tab_idx_from_control(cost_text):
		return
	var lines := PackedStringArray()
	lines.append("[b]This frame[/b]  (GPU median of the last 60 frames)")
	lines.append("GPU %.2f ms   CPU render %.2f ms   %d fps" % [gpu,
			rs.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()), Engine.get_frames_per_second()])
	lines.append("Draw calls %d   objects %d   triangles %s" % [
			rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			_short(rs.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))])
	if doc.greebles:
		var by_layer := {}
		var by_rule := {}
		var total := 0
		var total_tris := 0
		var shadow_tris := 0
		var st: UtopiaGreebleStyle = doc.styles[style_name]
		for g in doc.greebles.group_info():
			var tris: int = _tris(g.mesh) * int(g.count)
			total += g.count
			total_tris += tris
			if g.shadows:
				shadow_tris += tris
			var l: Array = by_layer.get(g.layer, [0, 0])
			by_layer[g.layer] = [l[0] + g.count, l[1] + tris]
			if doc.greebles.zones[g.zi].style == st:
				var r: Array = by_rule.get(g.ri, [0, 0, g.shadows])
				by_rule[g.ri] = [r[0] + g.count, r[1] + tris, g.shadows]
		lines.append("")
		lines.append("[b]Greebles, whole lap[/b]")
		lines.append("%d instances, %s triangles, %s casting shadows" % [total, _short(total_tris), _short(shadow_tris)])
		lines.append("Last re-scatter %.1f ms" % doc.greebles.last_ms)
		lines.append("")
		for layer: String in LAYERS:
			if by_layer.has(layer):
				lines.append("%-10s %6d   %s tris" % [layer, by_layer[layer][0], _short(by_layer[layer][1])])
		lines.append("")
		lines.append("[b]%s, per rule[/b]" % style_name)
		for ri in st.rules.size():
			var r: Array = by_rule.get(ri, [0, 0, false])
			var mesh_name := st.rules[ri].mesh.resource_path.get_file().get_basename().trim_prefix("gb_") if st.rules[ri].mesh else "none"
			lines.append("%-14s %6d   %s tris%s" % [mesh_name, r[0], _short(r[1]), "   shadows" if r[2] else ""])
	cost_text.text = "\n".join(lines)


static func _short(n: int) -> String:
	if n >= 1000000:
		return "%.1fM" % (n / 1000000.0)
	if n >= 1000:
		return "%.0fk" % (n / 1000.0)
	return str(n)


# =============================================================================
# CHECKS
# =============================================================================

## Runs what's cheap always, and the greeble checks for styles that changed.
func _run_checks(all := false) -> void:
	var cur := doc.capture()
	var changed_styles := {}
	if all:
		for s: String in doc.styles:
			changed_styles[s] = true
	else:
		for k: String in cur:
			if k.begins_with("style:") and _check_baseline.get(k) != cur[k]:
				changed_styles[k.get_slice("/", 0).get_slice(":", 1)] = true
	_check_baseline = cur
	var general: Array = []
	var used := {}
	if doc.surface:
		for z in _surface_zones():
			if z.profile:
				used[z.profile] = true
	for pr: TrackSurfaceProfile in doc.profiles.values():
		if used.has(pr) or pr == doc.profiles.get(profile_name):
			for prob in pr.problems():
				general.append({text = "%s: %s" % [pr.profile_name, prob], d = -1.0})
	for w in _colour_warnings():
		general.append({text = w, d = -1.0})
	_check_items[""] = general
	for s: String in changed_styles:
		_check_items[s] = _style_checks(s)
	checks.clear()
	for k: String in _check_items:
		for item: Dictionary in _check_items[k]:
			var i := checks.add_item(item.text)
			checks.set_item_metadata(i, item.d)
	if checks.item_count == 0:
		checks.add_item("No problems found.")
		checks.set_item_metadata(0, -1.0)
	if not all:
		_fill_rule_list()


func _colour_warnings() -> PackedStringArray:
	var out := PackedStringArray()
	for p in doc.road_params:
		if p.type != TYPE_COLOR:
			continue
		var v: Variant = doc.variation_override(p.name)
		if v == null:
			v = doc.road_base.get_shader_parameter(p.name)
		if v == null:
			continue
		var c := Rows._to_color(v)
		if c.s > 0.5 and c.v > 0.3 and c.h >= ORANGE_HUE.x and c.h <= ORANGE_HUE.y:
			out.append("%s is close to the boost pads' orange" % p.name)
	return out


func _style_checks(name: String) -> Array:
	var out: Array = []
	if doc.greebles == null:
		return out
	var st: UtopiaGreebleStyle = doc.styles[name]
	var pl := doc.greebles.placements(st)
	if pl.is_empty():
		return out
	if doc.greebles.skipped_upright > 0:
		out.append({text = "%s: %d pieces left out by upright limits" % [name, doc.greebles.skipped_upright], d = -1.0})
	for f in doc.greebles.intrusions(pl):
		var r := st.rules[f.ri] if f.ri >= 0 else null
		var mesh_name := r.mesh.resource_path.get_file().get_basename().trim_prefix("gb_") if r and r.mesh else "threshold"
		out.append({text = "%s, %s: %s (x%d)" % [name, mesh_name, f.what, f.count], d = f.d if f.pi == 0 else -1.0})
	out.append_array(_decal_overlaps(name, st, pl))
	return out


## Ground pieces sitting on painted decals (they only keep off pads and the
## start line).
func _decal_overlaps(name: String, st: UtopiaGreebleStyle, pl: Array[Dictionary]) -> Array:
	var out: Array = []
	if doc.surface == null or doc.surface.decals.is_empty():
		return out
	var glyphs := load(TrackSurface.GLYPHS) as TrackSurfaceGlyphs
	if glyphs == null:
		return out
	var rects: Array[Rect2] = []    # (t, s)
	var segs := TrackSurface._road_segments(spline)
	for dc in doc.surface.decals:
		if dc == null or dc.path_index != 0:
			continue
		for n in dc.count:
			var sd: float = dc.distance + n * dc.spacing
			for rec: Dictionary in TrackSurface.layout(dc, sd, doc.surface._half_widths(segs, sd), n, glyphs):
				rects.append(Rect2(rec.t0, rec.s0, rec.wt, rec.hs))
	var hits := {}
	var info := {curve = spline.curve, xf = doc.greebles.global_transform.affine_inverse() * spline.global_transform}
	for p in pl:
		if p.layer != "ground" or p.pi != 0:
			continue
		var f := doc.greebles._frame(info, p.d)
		var xf: Transform3D = p.xf
		var aabb: AABB = (p.mesh as Mesh).get_aabb()
		var x: float = (xf.origin - f.origin).dot(f.basis.x)
		var box := Rect2(x - aabb.size.x * 0.5, float(p.d) - aabb.size.z * 0.5, aabb.size.x, aabb.size.z)
		for r in rects:
			if r.intersects(box):
				if not hits.has(p.ri):
					hits[p.ri] = [0, p.d]
				hits[p.ri][0] += 1
				break
	for ri: int in hits:
		var mesh_name := st.rules[ri].mesh.resource_path.get_file().get_basename().trim_prefix("gb_") if ri >= 0 else "threshold"
		var count: int = hits[ri][0]
		out.append({text = "%s, %s: %d %s on road decals" % [name, mesh_name, count, "piece" if count == 1 else "pieces"],
				d = hits[ri][1]})
	return out


# =============================================================================
# COMPARE, SNAPSHOTS, UNDO, SAVE
# =============================================================================

## Held: shows the saved look of both layers, then puts your edits back.
func _set_compare(on: bool) -> void:
	if on == _comparing:
		return
	_comparing = on
	if on:
		doc.commit()
		_compare_hold = doc.capture()
		doc.restore(doc.saved)
		status.text = "Showing saved"
	else:
		doc.restore(_compare_hold)
		_compare_hold = {}
	doc.flush()
	_refresh_all()


func _snapshot(s: String) -> void:
	if not snaps.has(s) or Input.is_key_pressed(KEY_CTRL):
		doc.commit()
		snaps[s] = doc.capture()
		(snap_btns[s] as Button).text = s + " stored"
		return
	doc.restore(snaps[s])
	doc.commit()
	_after_restore()


func _after_restore() -> void:
	doc.flush()
	_refresh_all()


func _refresh_all() -> void:
	# Rule counts may have changed under the selection.
	var st: UtopiaGreebleStyle = doc.styles[style_name]
	sel_rule = clampi(sel_rule, 0, maxi(st.rules.size() - 1, 0))
	sel_band = clampi(sel_band, 0, maxi((doc.get_v("prof:%s/bands" % profile_name) as Array).size() - 1, 0))
	_fill_band_list()
	_build_band_rows()
	_fill_rule_list()
	_build_rule_rows()
	style_rows.refresh()
	road_rows.refresh()
	wall_rows.refresh()
	mat_rows.refresh()
	_select_variation_item(doc.variation_file)
	_fill_mask_opt()
	_build_mask_rows()
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


func _ask_save() -> void:
	doc.commit()
	if not OS.has_feature("editor"):
		status.text = "Saving needs the Godot editor build"
		return
	var files := doc.dirty_files()
	if files.is_empty():
		status.text = "Nothing to save"
		return
	var shared := PackedStringArray()
	var own := PackedStringArray()
	for f: String in files:
		(own if f.begins_with(Doc.VARIATION_DIR) else shared).append("  %s  (%d)" % [f.trim_prefix("res://"), files[f]])
	var text := PackedStringArray()
	if not shared.is_empty():
		text.append("These reach every track using them:")
		text.append_array(shared)
	if not own.is_empty():
		text.append("One track's variation:")
		text.append_array(own)
	save_dialog.dialog_text = "\n".join(text)
	save_dialog.popup_centered()


func _do_save() -> void:
	var errors := doc.save()
	if errors.is_empty():
		_refresh_status()
	else:
		status.text = "Save failed"
		push_error("Surface Lab save: %s" % "; ".join(errors))
