extends Node
## Surface Lab self test (LAB_SELFTEST=1): drives the running lab through its
## edit paths on the real GPU and prints a LABTEST line per check, with
## screenshots in user://surface_lab. It never writes the project's files:
## saving goes to user://surface_lab/save.
##
##   LAB_SELFTEST=1 godot --path full_throttle_flux res://tools/surface_lab/surface_lab.tscn

const OUT := "user://surface_lab"

var lab: Node
var failed := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT + "/save")
	_run.call_deferred()


func _check(name: String, ok: bool, note := "") -> void:
	print("LABTEST %s %s %s" % ["ok  " if ok else "FAIL", name, note])
	if not ok:
		failed += 1


func _shot(name: String) -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT, name])


func _mouse_button(button: MouseButton, pressed: bool, at: Vector2) -> InputEventMouseButton:
	var b := InputEventMouseButton.new()
	b.button_index = button
	b.pressed = pressed
	b.position = at
	b.global_position = at
	return b


func _click(at: Vector2) -> void:
	Input.parse_input_event(_mouse_button(MOUSE_BUTTON_LEFT, true, at))
	await _frames(2)
	Input.parse_input_event(_mouse_button(MOUSE_BUTTON_LEFT, false, at))
	await _frames(2)


func _find_slider(n: Node) -> HSlider:
	for c in n.get_children():
		if c is HSlider:
			return c
		var f := _find_slider(c)
		if f:
			return f
	return null


func _ui_checks(doc: RefCounted) -> void:
	lab.follow_camera = false
	# A rule row's slider writes the rule, and the rule re-scatters.
	lab.tabs.current_tab = lab.tabs.get_tab_idx_from_control(lab.tabs.get_node("Greebles"))
	await _frames(2)
	lab._select_style("service")
	lab._select_rule(5)
	await _frames(2)
	var key := "style:service/rule:5/probability"
	var was: float = doc.get_v(key)
	var count0: int = lab._rule_counts().get(5, 0)
	var row: Dictionary = {}
	for r: Dictionary in lab.rule_rows.rows:
		if r.spec.name == "probability":
			row = r
	var slider := _find_slider(row.box)
	_check("probability has a slider", slider != null)
	slider.value = 0.25
	_check("slider wrote the rule", is_equal_approx(doc.get_v(key), 0.25), str(doc.get_v(key)))
	await get_tree().create_timer(0.2).timeout
	var count1: int = lab._rule_counts().get(5, 0)
	_check("slider thinned the rule", count1 < count0, "%d to %d" % [count0, count1])
	await get_tree().create_timer(0.6).timeout
	_check("edit went into the history", doc.history_i > 0)
	doc.undo()
	lab._after_restore()
	_check("undo put the slider back", is_equal_approx(_find_slider(lab.rule_rows.rows[_row_index("probability")].box).value, was))
	# Click a band in the section view.
	lab.cam.jump(850.0)
	await _frames(12)
	var sec: Control = lab.section
	var grate: Dictionary = {}
	for bd: Dictionary in sec._bands:
		if bd.type == TrackSurfaceBand.Type.GRATE:
			grate = bd
			break
	_check("section has a grate band", not grate.is_empty())
	var at: Vector2 = sec.global_position + Vector2((sec._x(grate.x0) + sec._x(grate.x1)) * 0.5, sec._road_y() + 13.0)
	await _click(at)
	_check("clicking a band selects it", lab.sel_band == grate.src, "%d vs %d" % [lab.sel_band, grate.src])
	await _shot("section_band_selected")
	# Click the timeline: the camera goes there.
	var tl: Control = lab.timeline
	await _click(tl.global_position + Vector2(tl._x(tl.lap * 0.5), 10.0))
	_check("timeline moved the camera", absf(lab.cam.d - tl.lap * 0.5) < 2.0, str(lab.cam.d))
	lab.cam.jump(850.0)
	lab.follow_camera = true


## Mean brightness of the road in the middle of the screen (UI hidden).
func _road_luma(band: Rect2) -> float:
	await _frames(6)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var sum := 0.0
	var n := 0
	for y in range(int(band.position.y), int(band.end.y), 3):
		for x in range(int(band.position.x), int(band.end.x), 3):
			sum += img.get_pixel(x, y).get_luminance()
			n += 1
	return sum / maxf(n, 1.0)


func _gpu_median() -> float:
	var vp := get_viewport().get_viewport_rid()
	await _frames(20)
	var s := PackedFloat32Array()
	for i in 180:
		await get_tree().process_frame
		s.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	s.sort()
	return s[90]


func _mask_checks(doc: RefCounted) -> void:
	lab.follow_camera = false
	lab.cam.set_mode(1)
	lab.cam.glide_paused = true
	lab.cam.jump(850.0)
	lab.tabs.current_tab = lab.tabs.get_tab_idx_from_control(lab.tabs.get_node("Mask"))
	await _shot("mask_tab_none")
	_check("starter recipes load", doc.masks.size() >= 3, str(doc.masks.keys()))
	_check("mask textures load", lab.mask_tex_names.size() >= 6, str(lab.mask_tex_names))
	var mat: ShaderMaterial = doc.surface.live_materials()[0]
	_check("no mask by default", int(mat.get_shader_parameter("mask_mode")) == 0)
	var files: Array = doc.masks.keys()
	files.sort()
	var r_file: String = files[0]
	var key := "mask:%s/" % r_file
	var r: TrackSurfaceMask = doc.masks[r_file]
	lab._pick_mask(r_file)
	_check("picking a recipe draws it", int(mat.get_shader_parameter("mask_mode")) == int(r.mode))
	_check("a measured mean", mat.get_shader_parameter("mask_a_mean") != null
			and absf(float(mat.get_shader_parameter("mask_a_mean")) - 0.5) < 0.45, str(mat.get_shader_parameter("mask_a_mean")))
	await _shot("mask_recipe_%s" % r_file.get_basename())
	if lab.gs:
		lab.gs.set_surface_view(7)
	await _shot("mask_debug_view")
	if lab.gs:
		lab.gs.set_surface_view(0)
	# Editing the recipe reaches the live material; undo takes it back.
	doc.commit()
	doc.set_v(key + "contrast", 3.0)
	_check("recipe edit is live", is_equal_approx(float(mat.get_shader_parameter("mask_contrast")), 3.0))
	_check("recipe edit is dirty", doc.dirty_files().has("%s/%s" % [doc.MASK_DIR, r_file]))
	doc.commit()
	doc.undo()
	_check("recipe undo", not is_equal_approx(float(mat.get_shader_parameter("mask_contrast")), 3.0))
	# A band's amount reaches the table, in the fraction, without changing its param.
	var data: Array = (doc.get_v("prof:industrial/bands") as Array).duplicate(true)
	var plate := data.size() - 1
	var vents_param := 1 if data[plate][4] else 0
	data[plate][5] = 0.25
	doc.set_v("prof:industrial/bands", data)
	doc.flush()
	var table: PackedVector4Array = mat.get_shader_parameter("surf_bands")
	var w: float = table[plate].w
	_check("band amount keeps its param", int(w) == vents_param, str(w))
	_check("band amount is in the fraction", is_equal_approx(1.0 - fposmod(w, 1.0) / 0.9, 0.25), str(w))
	doc.commit()
	doc.undo()
	doc.flush()
	# Saving: a recipe and a variation pointing at it, to the copy folder.
	var probe := TrackSurfaceVariation.new()
	probe.mask = r
	var fresh: ShaderMaterial = doc.road_base.duplicate()
	probe.apply(fresh)
	_check("a variation applies its recipe, as a race does", int(fresh.get_shader_parameter("mask_mode")) == int(r.mode)
			and fresh.get_shader_parameter("mask_a") == r.a_texture)
	var v_file: String = doc.variations.keys()[0]
	doc.set_v("var", v_file)
	var had: Variant = doc.get_v("var:%s/mask" % v_file)
	doc.set_v("var:%s/mask" % v_file, r)
	doc.set_v(key + "bias", 0.05)
	var errors: PackedStringArray = doc.save(OUT + "/save")
	_check("recipe saves", errors.is_empty(), str(errors))
	var rc: Resource = ResourceLoader.load("%s/save/%s" % [OUT, r_file], "", ResourceLoader.CACHE_MODE_IGNORE)
	_check("saved recipe reads back", rc != null and is_equal_approx(rc.bias, 0.05))
	var vtext := FileAccess.get_file_as_string("%s/save/%s" % [OUT, v_file])
	_check("saved variation names the recipe", vtext.contains(r_file))
	doc.set_v("var:%s/mask" % v_file, had)
	doc.set_v("var", "")
	doc.restore(doc.saved)
	doc.commit()
	doc.flush()
	_check("back to saved after recipe tests", doc.dirty_files().is_empty(), str(doc.dirty_files()))
	# Cost and neutrality, with the UI hidden, on a straight piece of road.
	lab.ui.visible = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	lab._pick_mask("")
	var near := Rect2(560, 620, 800, 300)
	var far := Rect2(800, 480, 320, 50)
	var luma_near0: float = await _road_luma(near)
	var luma_far0: float = await _road_luma(far)
	var gpu0: float = await _gpu_median()
	print("LABTEST mask off: GPU %.2f ms, luma near %.4f far %.4f" % [gpu0, luma_near0, luma_far0])
	var modes := {"A only": 1, "A x B": 2, "B masks A": 3}
	for m: String in modes:
		r.mode = modes[m]
		if r.b_texture == null:
			r.b_texture = lab.mask_textures[lab.mask_tex_names[1]]
		lab._pick_mask(r_file)
		doc.apply_mask()
		var ln: float = await _road_luma(near)
		var lf: float = await _road_luma(far)
		var g: float = await _gpu_median()
		print("LABTEST mask %-10s GPU %.2f ms (%+.2f), luma near %.4f (%+.1f%%) far %.4f (%+.1f%%)" % [m, g, g - gpu0, ln,
				(ln / luma_near0 - 1.0) * 100.0, lf, (lf / luma_far0 - 1.0) * 100.0])
	lab._pick_mask("")
	lab.ui.visible = true
	doc.restore(doc.saved)
	doc.commit()
	doc.flush()
	_check("clean after cost test", doc.dirty_files().is_empty(), str(doc.dirty_files()))
	lab.tabs.current_tab = 0


## Frame times while nothing's edited, and while a slider is dragged, vsync off.
func _timing(doc: RefCounted) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	lab.cam.set_mode(1)
	lab.cam.glide_paused = false
	await _frames(30)
	await _sample("idle, gliding", func(_i: int): pass)
	await _sample("dragging a road colour", func(i: int):
		doc.set_v("road/plate_color", Color(0.2 + fmod(i * 0.01, 0.2), 0.2, 0.2)))
	await _sample("dragging a band width", func(i: int):
		var data: Array = (doc.get_v("prof:industrial/bands") as Array).duplicate(true)
		data[0][1] = 1.0 + fmod(i * 0.02, 1.0)
		doc.set_v("prof:industrial/bands", data))
	await _sample("dragging the biggest rule", func(i: int):
		doc.set_v("style:service/rule:5/offset", Vector3(0.0, fmod(i * 0.01, 0.5), 0.0)))
	doc.restore(doc.saved)
	doc.commit()
	doc.flush()
	lab.tabs.current_tab = lab.tabs.get_tab_idx_from_control(lab.cost_text)
	await _sample("idle, cost tab open", func(_i: int): pass)
	lab.tabs.current_tab = 0
	_check("timing edits undone", doc.dirty_files().is_empty(), str(doc.dirty_files()))


func _sample(label: String, each_frame: Callable) -> void:
	var dt := PackedFloat32Array()
	for i in 180:
		each_frame.call(i)
		await get_tree().process_frame
		dt.append(get_process_delta_time() * 1000.0)
	dt.sort()
	print("LABTEST timing %-26s p50 %5.1f ms  p95 %5.1f ms  max %6.1f ms" % [label, dt[90], dt[171], dt[179]])


func _row_index(name: String) -> int:
	for i in lab.rule_rows.rows.size():
		if lab.rule_rows.rows[i].spec.name == name:
			return i
	return -1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	var doc = lab.doc
	lab.cam.glide_paused = true
	lab.cam.jump(850.0)
	await _frames(10)
	print("LABTEST %s, window %s" % [RenderingServer.get_video_adapter_name(), get_window().size])
	print("LABTEST road params %d, wall params %d, styles %d, profiles %d" % [doc.road_params.size(),
			doc.wall_params.size(), doc.styles.size(), doc.profiles.size()])
	_check("surface found", doc.surface != null)
	_check("greebles found", doc.greebles != null)
	_check("live materials", doc.surface.live_materials().size() > 0, str(doc.surface.live_materials().size()))
	_check("nothing dirty at start", doc.dirty_files().is_empty(), str(doc.dirty_files()))
	await _shot("start")

	# A full capture must be cheap: every edit gesture ends in one.
	var t := Time.get_ticks_usec()
	var base: Dictionary = doc.capture()
	print("LABTEST capture %d keys in %.2f ms" % [base.size(), (Time.get_ticks_usec() - t) / 1000.0])

	# Road parameter: reaches the live materials, shows as dirty.
	doc.set_v("road/plate_color", Color(0.7, 0.1, 0.1))
	var live: Variant = doc.surface.live_materials()[0].get_shader_parameter("plate_color")
	_check("road param is live", live == Color(0.7, 0.1, 0.1), str(live))
	_check("road param is dirty", doc.dirty_files().has(doc.ROAD_MATERIAL))
	await _shot("road_red")

	# Undo goes back and clears dirty.
	doc.commit()
	_check("undo", doc.undo())
	_check("undo cleared dirty", doc.dirty_files().is_empty(), str(doc.dirty_files()))
	var after: Variant = doc.surface.live_materials()[0].get_shader_parameter("plate_color")
	_check("undo reached the live material", doc.same(after, base["road/plate_color"]), str(after))
	_check("redo", doc.redo())
	doc.undo()

	# A band edit reaches the live band table.
	var mats: Array = doc.surface.live_materials()
	var before: PackedVector4Array = mats[0].get_shader_parameter("surf_bands")
	var data: Array = (doc.get_v("prof:industrial/bands") as Array).duplicate(true)
	data[0][1] = 3.0
	doc.set_v("prof:industrial/bands", data)
	doc.flush()
	var now: PackedVector4Array = mats[0].get_shader_parameter("surf_bands")
	_check("band table changed", now != before)
	await _shot("wide_edge_band")
	doc.commit()
	doc.undo()
	doc.flush()
	_check("band undo", mats[0].get_shader_parameter("surf_bands") == before)

	# One rule re-scatters alone, and leaves other rules' instances alone.
	var gr: TrackGreebles = doc.greebles
	var name: String = lab.style_name
	var st: UtopiaGreebleStyle = doc.styles[name]
	var total0: int = gr.instance_total
	t = Time.get_ticks_usec()
	gr.rebuild()
	print("LABTEST full rebuild %.1f ms, %d instances" % [(Time.get_ticks_usec() - t) / 1000.0, gr.instance_total])
	var ri := 0
	var best := 0
	var counts: Dictionary = lab._rule_counts()
	for k: int in counts:
		if counts[k] > best:
			best = counts[k]
			ri = k
	t = Time.get_ticks_usec()
	gr.rebuild_rule(st, ri)
	print("LABTEST rule rebuild %.1f ms (%s rule %d, %d instances)" % [(Time.get_ticks_usec() - t) / 1000.0, name, ri, best])
	_check("rule rebuild keeps the count", gr.instance_total == total0, "%d vs %d" % [gr.instance_total, total0])
	var key := "style:%s/rule:%d/enabled" % [name, ri]
	doc.set_v(key, false)
	doc.flush()
	_check("disabling a rule removes only it", gr.instance_total == total0 - best,
			"%d vs %d" % [gr.instance_total, total0 - best])
	doc.commit()
	doc.undo()
	doc.flush()
	_check("rule undo restores the count", gr.instance_total == total0)
	# Structure: add then undo.
	var n0: int = st.rules.size()
	doc.set_v("style:%s/n" % name, n0 + 1)
	doc.flush()
	doc.commit()
	doc.undo()
	doc.flush()
	_check("rule add undo", st.rules.size() == n0)

	# Greybox material.
	var glow: Color = doc.get_v("mat:glow/emission")
	doc.set_v("mat:glow/emission", Color(0, 1, 0))
	await _shot("green_glow")
	doc.commit()
	doc.undo()
	_check("material undo", doc.get_v("mat:glow/emission") == glow)

	# A variation previews, and overrides the style.
	var file: String = doc.variations.keys()[0]
	doc.set_v("var", file)
	await _shot("variation")
	var want: Variant = doc.variation_override("plate_color")
	_check("variation has a plate colour", want != null)
	_check("variation drawn", doc.same(doc.surface.live_materials()[0].get_shader_parameter("plate_color"), want))
	var wall_param := ""
	for p in doc.wall_params:
		if doc.variation_override(p.name) != null:
			wall_param = p.name
			break
	_check("variation reaches the walls' copy", wall_param != ""
			and doc.same(doc.wall_live.get_shader_parameter(wall_param), doc.variation_override(wall_param)), wall_param)
	_check("variation leaves the wall base alone", wall_param != ""
			and not doc.same(doc.wall_live.get_shader_parameter(wall_param), doc.wall_base.get_shader_parameter(wall_param)))
	doc.set_v("var", "")
	doc.commit()
	_check("variation preview isn't saved", doc.dirty_files().is_empty(), str(doc.dirty_files()))

	# Compare: edit, hold, the saved look shows, release, the edit's back.
	doc.set_v("road/plate_color", Color(0.1, 0.7, 0.1))
	doc.set_v(key, false)
	doc.flush()
	doc.commit()
	lab._set_compare(true)
	_check("compare shows saved", doc.dirty_files().is_empty(), str(doc.dirty_files()))
	_check("compare restores greebles", gr.instance_total == total0)
	lab._set_compare(false)
	_check("compare returns to the edit", doc.get_v("road/plate_color") == Color(0.1, 0.7, 0.1))
	_check("compare returns greebles", gr.instance_total == total0 - best)

	# Save a copy and read it back.
	var errors: PackedStringArray = doc.save(OUT + "/save")
	_check("save copies", errors.is_empty(), str(errors))
	var mat_copy: Resource = ResourceLoader.load(OUT + "/save/track_surface_material.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	_check("saved road material reads back", mat_copy != null and mat_copy.get_shader_parameter("plate_color") == Color(0.1, 0.7, 0.1))
	var original := FileAccess.get_file_as_string(doc.ROAD_MATERIAL).split("\n").size()
	var copy := FileAccess.get_file_as_string(OUT + "/save/track_surface_material.tres").split("\n").size()
	_check("material save adds no other lines", copy - original <= 1, "%d to %d lines" % [original, copy])
	var style_copy: Resource = ResourceLoader.load("%s/save/style_%s.tres" % [OUT, name], "", ResourceLoader.CACHE_MODE_IGNORE)
	_check("saved style reads back", style_copy != null and style_copy.rules[ri].enabled == false and style_copy.rules.size() == n0)
	var style_text := FileAccess.get_file_as_string("%s/save/style_%s.tres" % [OUT, name])
	_check("saved style keeps its uid", style_text.get_slice("\n", 0).contains('uid="'))
	_check("saved style keeps its script uid", style_text.contains('[ext_resource type="Script" uid="'))
	_check("a copy doesn't clear dirty", not doc.dirty_files().is_empty())
	doc.restore(doc.saved)
	doc.commit()
	doc.flush()
	_check("back to saved", doc.dirty_files().is_empty(), str(doc.dirty_files()))

	# The UI itself: rows, the views, real mouse clicks.
	await _ui_checks(doc)

	# Solo views and the chase camera.
	lab._set_road_look(false)
	await _shot("neutral_road")
	lab._set_road_look(true)
	lab._select_rule(ri)
	lab.solo_rule = true
	lab._apply_greeble_display()
	await _shot("solo_rule")
	lab.solo_rule = false
	lab._apply_greeble_display()
	lab.tabs.current_tab = lab.tabs.get_tab_idx_from_control(lab.tabs.get_node("Greebles"))
	await _shot("greebles_tab")
	lab.tabs.current_tab = lab.tabs.get_tab_idx_from_control(lab.tabs.get_node("Road"))
	await _shot("road_tab")
	lab.tabs.current_tab = lab.tabs.get_tab_idx_from_control(lab.cost_text)
	await _frames(40)
	await _shot("cost_tab")
	lab.tabs.current_tab = 0
	t = Time.get_ticks_usec()
	lab._run_checks(true)
	print("LABTEST checks %.1f ms, %d items" % [(Time.get_ticks_usec() - t) / 1000.0, lab.checks.item_count])
	for i in lab.checks.item_count:
		print("LABTEST   check: %s" % lab.checks.get_item_text(i))
	lab.cam.set_mode(1)
	lab.cam.glide_paused = false
	await _frames(60)
	lab.cam.set_mode(2)
	await _frames(240)
	await _shot("chase")
	lab.cam.set_mode(0)
	await _frames(10)
	_check("back from chase", lab.cam.cam.current)
	var view0: Basis = lab.cam.cam.global_transform.basis
	lab.cam.view_input(_mouse_button(MOUSE_BUTTON_RIGHT, true, Vector2(600, 400)))
	_check("fly starts looking", lab.cam.is_looking())
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(60, 20)
	lab.cam.view_input(motion)
	_check("fly turns the view", not lab.cam.cam.global_transform.basis.is_equal_approx(view0))
	lab.cam.view_input(_mouse_button(MOUSE_BUTTON_RIGHT, false, Vector2(600, 400)))
	_check("fly lets go of the mouse", Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	var gpu: float = lab._gpu_ms()
	print("LABTEST GPU %.2f ms" % gpu)
	await _mask_checks(doc)
	await _timing(doc)
	print("LABTEST done, %d failed" % failed)
	get_tree().quit(1 if failed > 0 else 0)
