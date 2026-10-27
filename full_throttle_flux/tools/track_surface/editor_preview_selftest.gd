@tool
extends RefCounted
## TS_EDITOR_SELFTEST=1 with a circuit open in the editor: checks the
## TrackSurface editor preview (render-instance overrides, never saved).
## It edits the first zone and decal, waits for the preview to rebuild,
## puts them back, saves the scene through the editor and quits. Without
## --headless it also saves the 3D viewport to TS_SHOT (if set) before and
## after the edits.
##
##   Godot --editor --path . [--headless] res://scenes/tracks/test_circuit_3_live.tscn
##   (with TS_EDITOR_SELFTEST=1)


static func run(ts: TrackSurface) -> void:
	var tree := ts.get_tree()
	var wait := TrackSurface.PREVIEW_POLL + 0.3
	await tree.create_timer(1.5).timeout
	# The editor may also restore other scene tabs: test the open one only.
	if not is_instance_valid(ts) or ts.owner != EditorInterface.get_edited_scene_root():
		return
	var fails := 0
	print("TS_SELFTEST preview: %d CSGs" % ts._preview_csgs.size())
	if ts._preview_csgs.is_empty():
		fails += 1
		print("TS_SELFTEST FAIL no CSG previewed")
	fails += _check_unsaved(ts, "after open")
	await _shot(ts, "before")
	var road_mat: ShaderMaterial = ts._preview_mats[0] if not ts._preview_mats.is_empty() else null

	if not ts.zones.is_empty():
		var z := ts.zones[0]
		var old := z.wear
		z.wear = old + 1.0
		await tree.create_timer(wait).timeout
		fails += _check_rebuilt(ts, road_mat, "zone wear")
		road_mat = ts._preview_mats[0]
		z.wear = old
		await tree.create_timer(wait).timeout
		road_mat = ts._preview_mats[0]
	if not ts.decals.is_empty():
		var d := ts.decals[0]
		var old := d.text
		d.text = "PREVIEW"
		await tree.create_timer(wait).timeout
		fails += _check_rebuilt(ts, road_mat, "decal text")
		await _shot(ts, "decal")
		d.text = old
		await tree.create_timer(wait).timeout

	EditorInterface.save_scene()
	await tree.process_frame
	fails += _check_unsaved(ts, "after save")
	print("TS_SELFTEST done: %d failures" % fails)
	tree.quit(1 if fails else 0)


## Nothing of the preview would be saved: the scene packed as the editor
## saves it has no material_override or instance parameter on any node.
static func _check_unsaved(ts: TrackSurface, when: String) -> int:
	var fails := 0
	var ps := PackedScene.new()
	ps.pack(EditorInterface.get_edited_scene_root())
	var st := ps.get_state()
	for i in st.get_node_count():
		for k in st.get_node_property_count(i):
			var prop := String(st.get_node_property_name(i, k))
			if prop == "material_override" or prop.begins_with("instance_shader_parameters/"):
				fails += 1
				print("TS_SELFTEST FAIL %s: %s saves %s" % [when, st.get_node_name(i), prop])
	if fails == 0:
		print("TS_SELFTEST %s: nothing of the preview in the packed scene" % when)
	return fails


static func _check_rebuilt(ts: TrackSurface, before: ShaderMaterial, what: String) -> int:
	var now: ShaderMaterial = ts._preview_mats[0] if not ts._preview_mats.is_empty() else null
	if now == null or now == before:
		print("TS_SELFTEST FAIL %s: preview not rebuilt" % what)
		return 1
	print("TS_SELFTEST %s: rebuilt (%d CSGs)" % [what, ts._preview_csgs.size()])
	return 0


static func _shot(ts: TrackSurface, tag: String) -> void:
	var dir := OS.get_environment("TS_SHOT")
	if dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	var vp := EditorInterface.get_editor_viewport_3d(0)
	var cam := vp.get_camera_3d()
	var path := ts.get_node_or_null(ts.paths[0]) as Path3D
	if cam and path:
		# Above the start line, looking down the track.
		var c := path.curve
		var p := path.to_global(c.sample_baked(10.0))
		var ahead := path.to_global(c.sample_baked(60.0))
		cam.global_position = p + Vector3.UP * 12.0 - (ahead - p).normalized() * 10.0
		cam.look_at(ahead, Vector3.UP)
	for i in 10:
		await ts.get_tree().process_frame
	vp.get_texture().get_image().save_png(dir.path_join("editor_preview_%s.png" % tag))
	print("TS_SELFTEST shot %s" % tag)
