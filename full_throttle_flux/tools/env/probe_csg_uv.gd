extends SceneTree
## Dev probe (v35 Phase 4): how CSGPolygon3D path UVs map to distance along
## the spline and to the polygon outline, for the road and walls.

func _initialize() -> void:
	var track: Node3D = (load("res://scenes/tracks/test_circuit_3_live.tscn") as PackedScene).instantiate()
	root.add_child(track)
	await process_frame
	await process_frame
	var sp := track.find_child("MainSpline", true, false) as Path3D
	for gname in ["groundGeo", "wallLeftGeo", "wallRightGeo"]:
		var g := sp.get_node(gname) as CSGPolygon3D
		var meshes: Array = g.get_meshes()
		var xf: Transform3D = g.global_transform * (meshes[0] as Transform3D)
		var mesh := meshes[1] as ArrayMesh
		var arr := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var tracker := SplineTracker.new(sp, g.transform if gname == "groundGeo" else sp.get_node("groundGeo").transform)
		var vmin := {}
		var errs := []
		for i in range(0, verts.size(), maxi(1, verts.size() / 4000)):
			var wp: Vector3 = xf * verts[i]
			var key := snappedf(uvs[i].y, 0.0005)
			if not vmin.has(key):
				vmin[key] = [0, Vector3.ZERO, 0.0, 0.0]
			vmin[key][0] += 1
			vmin[key][1] += nrm[i]
			if i % 7 == 0:
				tracker.reset()
				tracker.update(wp)
				var fr := tracker.frame()
				var rel := wp - fr.origin
				vmin[key][2] += rel.dot(fr.basis.x)
				vmin[key][3] += rel.dot(fr.basis.y)
			if i % 97 == 0:
				tracker.reset()
				var d := tracker.update(wp)
				errs.append("%.4f->%.1f" % [uvs[i].x * g.path_u_distance, d])
		print("== %s verts %d  u_distance %.1f" % [gname, verts.size(), g.path_u_distance])
		var keys := vmin.keys()
		keys.sort()
		for k in keys:
			var n: Vector3 = (vmin[k][1] as Vector3).normalized()
			var c: float = maxf(1.0, vmin[k][0] / 7.0)
			print("  v %.4f  count %d  avg normal (%.2f, %.2f, %.2f)  ~lateral %.1f  height %.1f" % [k, vmin[k][0], n.x, n.y, n.z, vmin[k][2] / c, vmin[k][3] / c])
		print("  u samples (u, spline d):", errs.slice(0, 12))
	quit()
