extends SceneTree
## Geometry stats per top-level district of a city scene: nodes, draw items, triangles.
## usage: godot --path . -s res://tools/dev/scene_stats.gd -- res://scenes/tracks/swoopy/swoopy_city.tscn  (renderer needed for MultiMesh)
func _initialize() -> void:
	var city: Node = load(OS.get_cmdline_user_args()[0]).instantiate()
	root.add_child(city)
	var tot := [0, 0, 0]
	for dn in city.get_children():
		var s := [0, 0, 0]   # draw items (surfaces / mm), triangles, instances
		_walk(dn, s)
		print("%-28s draws %5d  tris %9d  inst %6d" % [dn.name, s[0], s[1], s[2]])
		for i in 3: tot[i] += s[i]
	print("TOTAL draws %d tris %d inst %d" % tot)
	quit()
func _tris(m: Mesh) -> int:
	var t := 0
	for i in m.get_surface_count():
		var a := m.surface_get_arrays(i)
		var idx = a[Mesh.ARRAY_INDEX]
		t += (idx.size() if idx != null else a[Mesh.ARRAY_VERTEX].size()) / 3
	return t
func _walk(n: Node, s: Array) -> void:
	if n is MeshInstance3D and n.mesh:
		s[0] += n.mesh.get_surface_count(); s[1] += _tris(n.mesh); s[2] += 1
	elif n is MultiMeshInstance3D and n.multimesh and n.multimesh.mesh:
		s[0] += n.multimesh.mesh.get_surface_count(); s[1] += _tris(n.multimesh.mesh) * n.multimesh.instance_count; s[2] += n.multimesh.instance_count
	for c in n.get_children():
		_walk(c, s)
