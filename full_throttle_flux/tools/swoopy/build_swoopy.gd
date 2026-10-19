extends SceneTree
## Regenerates the Swoopy sky-high greybox.
##   godot --headless --path . -s res://tools/swoopy/build_swoopy.gd [-- district ...]
## Writes scenes/tracks/swoopy/:
##   districts/swoopy_<id>.tscn, swoopy_city.tscn, swoopy_lighting.tscn
## WARNING: overwrites those files (see the Utopia readme for the
## replacements/<district>.tscn detail-swap convention -- it works here too).

const OUT := "res://scenes/tracks/swoopy"
const TRACK := "res://scenes/tracks/test_circuit_5_live.tscn"

func _initialize() -> void:
	var track: Node3D = load(TRACK).instantiate()
	for n in ["SwoopyCity", "SwoopyLighting"]:
		if track.has_node(n):
			track.get_node(n).free()
	root.add_child(track)
	await process_frame
	var kit := UtopiaKit.new(track)
	var layout := SwoopyLayout.new(kit)
	print("corners: ", layout.corners.size())
	var only := OS.get_cmdline_user_args()
	var ids: Array = layout.district_ids()
	for id in ids:
		if only.size() > 0 and not only.has(id):
			continue
		var t0 := Time.get_ticks_msec()
		kit.current_district = id
		_clear_generated(id)
		var droot := Node3D.new()
		droot.name = "Swoopy_" + id.to_pascal_case()
		layout.call("district_" + id, droot)
		_apply_replacement(droot, id)
		_own(droot, droot)
		var ps := PackedScene.new()
		ps.pack(droot)
		ResourceSaver.save(ps, "%s/districts/swoopy_%s.tscn" % [OUT, id])
		print("district %s: %d nodes, %d ms" % [id, _count(droot), Time.get_ticks_msec() - t0])
		droot.free()
	var city := Node3D.new()
	city.name = "SwoopyCity"
	for id in ids:
		var inst: Node3D = load("%s/districts/swoopy_%s.tscn" % [OUT, id]).instantiate()
		city.add_child(inst)
		inst.owner = city
	if ResourceLoader.exists(OUT + "/swoopy_track_dressing.tscn"):
		var dr: Node3D = load(OUT + "/swoopy_track_dressing.tscn").instantiate()
		city.add_child(dr)
		dr.owner = city
	var cps := PackedScene.new()
	cps.pack(city)
	ResourceSaver.save(cps, OUT + "/swoopy_city.tscn")
	city.free()
	preload("res://tools/utopia/utopia_lighting_builder.gd").build(OUT + "/swoopy_lighting.tscn", layout.lighting_params())
	print("BUILD OK")
	quit()

func _apply_replacement(droot: Node3D, id: String) -> void:
	var path := "%s/replacements/%s.tscn" % [OUT, id]
	if not ResourceLoader.exists(path):
		return
	var det: Node = load(path).instantiate()
	for c in det.get_children():
		var g := droot.find_child(c.name, true, false)
		if g:
			g.get_parent().remove_child(g)
			g.free()
	det.name = "Detail"
	droot.add_child(det)

func _own(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		if c.scene_file_path == "":
			_own(c, owner_node)

func _count(n: Node) -> int:
	var k := 1
	for c in n.get_children():
		k += _count(c)
	return k

func _clear_generated(id: String) -> void:
	var dir := DirAccess.open(OUT + "/meshes")
	if dir == null:
		return
	for f in dir.get_files():
		if f.begins_with("gen_%s_" % id):
			dir.remove(f)
