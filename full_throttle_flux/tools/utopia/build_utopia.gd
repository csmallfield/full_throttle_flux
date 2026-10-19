extends SceneTree
## Regenerates the Utopia greybox city.
##   godot --headless --path . -s res://tools/utopia/build_utopia.gd [-- district_id ...]
## Writes:
##   scenes/tracks/utopia/districts/utopia_<id>.tscn   (one per district)
##   scenes/tracks/utopia/utopia_city.tscn            (instances all districts)
##   scenes/tracks/utopia/utopia_lighting.tscn
## WARNING: overwrites those files. Hand edits belong in new scenes, or
## move the district out of the build list in utopia_layout.gd first.

const OUT := "res://scenes/tracks/utopia"

func _initialize() -> void:
	var track: Node3D = load("res://scenes/tracks/test_circuit_3_live.tscn").instantiate()
	for n in ["UtopiaCity", "UtopiaLighting"]:
		if track.has_node(n):
			track.get_node(n).free()
	root.add_child(track)
	await process_frame
	var kit := UtopiaKit.new(track)
	var layout := UtopiaLayout.new(kit)
	var only := OS.get_cmdline_user_args()
	var ids: Array = layout.district_ids()
	for id in ids:
		if only.size() > 0 and not only.has(id):
			continue
		var t0 := Time.get_ticks_msec()
		kit.current_district = id
		_clear_generated(id)
		var droot := Node3D.new()
		droot.name = "Utopia_" + id.to_pascal_case()
		layout.call("district_" + id, droot)
		_apply_replacement(droot, id)
		_own(droot, droot)
		var ps := PackedScene.new()
		ps.pack(droot)
		ResourceSaver.save(ps, "%s/districts/utopia_%s.tscn" % [OUT, id])
		print("district %s: %d nodes, %d ms" % [id, _count(droot), Time.get_ticks_msec() - t0])
		droot.free()
	# city scene
	var city := Node3D.new()
	city.name = "UtopiaCity"
	for id in ids:
		var inst: Node3D = load("%s/districts/utopia_%s.tscn" % [OUT, id]).instantiate()
		city.add_child(inst)
		inst.owner = city
	# track dressing (greebles on the surveyed rails) -- built separately by
	# build_dressing.gd, only instanced here
	if ResourceLoader.exists(OUT + "/utopia_track_dressing.tscn"):
		var dr: Node3D = load(OUT + "/utopia_track_dressing.tscn").instantiate()
		city.add_child(dr)
		dr.owner = city
	var cps := PackedScene.new()
	cps.pack(city)
	ResourceSaver.save(cps, OUT + "/utopia_city.tscn")
	city.free()
	preload("res://tools/utopia/utopia_lighting_builder.gd").build(OUT + "/utopia_lighting.tscn", layout.lighting_params())
	print("BUILD OK")
	quit()

## Detail swap: if scenes/tracks/utopia/replacements/<id>.tscn exists it is
## instanced into the district as "Detail", and every greybox node whose name
## matches a DIRECT child of that scene's root is removed. Model in world space
## on top of the greybox (the district groups have identity transforms), name
## your top-level pieces after the greybox groups they replace, and rebuilds
## keep your work.
func _apply_replacement(droot: Node3D, id: String) -> void:
	var path := "%s/replacements/%s.tscn" % [OUT, id]
	if not ResourceLoader.exists(path):
		return
	var det: Node = load(path).instantiate()
	var removed := 0
	for c in det.get_children():
		var g := droot.find_child(c.name, true, false)
		if g:
			g.get_parent().remove_child(g)
			g.free()
			removed += 1
		else:
			print("  replacement %s: no greybox node named %s" % [id, c.name])
	det.name = "Detail"
	droot.add_child(det)
	print("  replacement %s: swapped %d greybox groups" % [id, removed])

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
