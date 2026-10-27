extends Node
## v38: checks the track-space data TrackRoadSegment writes for the track
## surface shader, on a real builder track:
##   UV2.x  = the ring's distance along the path
##   UV2.y  = the vertex's actual offset across the frame (after widening)
##   CUSTOM0 edge class: the surface verts are at y = 0, lips above
##   CUSTOM0 half widths = the outermost surface verts at that ring
##   TANGENT = the direction of travel (phase 2)
## and on each TrackJunction's two road meshes (Road in path A's frame,
## RoadBranch in path B's): the same, plus every RoadBranch vertex lies
## outside A's strip.
##
##   godot --headless --path . -s res://tools/dev/track_uv2_check_boot.gd
##
## Env: UC_TRACK (default builder_lab). Prints UV2CHECK lines, exits 1 on a
## failure.

var _fails := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var track_id := OS.get_environment("UC_TRACK")
	if track_id == "":
		track_id = "builder_lab"
	var ps := load("res://scenes/tracks/%s.tscn" % track_id) as PackedScene
	var track := ps.instantiate()
	add_child(track)
	await get_tree().process_frame
	var segs := 0
	for n in track.find_children("*", "TrackRoadSegment", true, false):
		var seg := n as TrackRoadSegment
		if seg.collision_layer & 4:
			continue   # walls
		_check_segment(seg)
		segs += 1
	var juncs := 0
	for n in track.find_children("*", "TrackJunction", true, false):
		var jn := n as TrackJunction
		var t0 := Time.get_ticks_usec()
		jn.build()
		print("UV2CHECK  %s rebuilt in %.1f ms" % [jn.name, (Time.get_ticks_usec() - t0) / 1000.0])
		for path_np: NodePath in [jn.path_a, jn.path_b]:
			_check_junction(jn, jn.get_node(path_np) as Path3D)
		juncs += 1
	print("UV2CHECK %s: %d road segments, %d junctions, %s" % [track_id, segs, juncs,
			"ok" if _fails == 0 else "%d FAILED" % _fails])
	get_tree().quit(1 if _fails > 0 or segs == 0 else 0)


func _check_segment(seg: TrackRoadSegment) -> void:
	var mi := seg.get_child(0, true) as MeshInstance3D
	var path := seg.get_node(seg.path_node) as Path3D
	var arr := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv2s: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var cust: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
	var tans: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
	var to_path := path.global_transform.affine_inverse() * seg.global_transform
	var length := path.curve.get_baked_length()
	var worst_t := 0.0
	var worst_y := 0.0
	var worst_w := 0.0
	var worst_tan := 1.0
	var counts := [0, 0, 0]
	var step := maxi(1, verts.size() / 4000)
	for i in range(0, verts.size(), step):
		var s := uv2s[i].x
		var fr := TrackRoadSegment.frame_at(path.curve, s)
		if seg.weld_lap_seam and s >= length - 0.001:
			fr = TrackRoadSegment.frame_at(path.curve, 0.0)
		var p := to_path * verts[i]
		var rel := p - fr.origin
		worst_t = maxf(worst_t, absf(rel.dot(fr.basis.x) - uv2s[i].y))
		var cls := int(cust[i * 4])
		counts[cls] += 1
		var h := rel.dot(fr.basis.y)
		if cls == TrackRoadSegment.EDGE_SURFACE:
			worst_y = maxf(worst_y, absf(h))
			var tan := to_path.basis * Vector3(tans[i * 4], tans[i * 4 + 1], tans[i * 4 + 2])
			worst_tan = minf(worst_tan, tan.normalized().dot(-fr.basis.z))
			var w := seg.width_at(s)
			var lim := seg.width_stretch_limit
			var want := Vector2(lim + w.x - seg.width_reference, lim + w.y - seg.width_reference) \
					if not seg.width_profile.is_empty() else Vector2(lim, lim)
			worst_w = maxf(worst_w, (Vector2(cust[i * 4 + 1], cust[i * 4 + 2]) - want).abs().length())
	print("UV2CHECK  %-28s %6d verts  t err %.4f m  surface y err %.4f m  half width err %.4f m  tangent dot %.5f  classes %s" % [
			seg.get_path(), verts.size(), worst_t, worst_y, worst_w, worst_tan, counts])
	if worst_t > 0.01 or worst_y > 0.01 or worst_w > 0.01 or worst_tan < 0.999 			or counts[0] == 0 or counts[1] == 0:
		_fails += 1


func _check_junction(jn: TrackJunction, path: Path3D) -> void:
	var mi := jn.road_mesh_for(path)
	if mi == null:
		print("UV2CHECK  %s: no road mesh for %s" % [jn.name, path.name])
		_fails += 1
		return
	var pa := jn.get_node(jn.path_a) as Path3D
	var branch := path != pa
	var arr := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv2s: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var cust: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
	var tans: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var to_path := path.global_transform.affine_inverse() * mi.global_transform
	var to_a := pa.global_transform.affine_inverse() * mi.global_transform
	var used := {}
	for i in idx:
		used[i] = true
	var worst_t := 0.0
	var worst_s := 0.0
	var worst_cls := 0
	var worst_w := 0.0
	var worst_tan := 1.0
	var inside_a := 0
	var deepest := 0.0
	var counts := [0, 0, 0, 0]
	for i: int in used:
		var s := uv2s[i].x
		var t := uv2s[i].y
		var fr := TrackRoadSegment.frame_at(path.curve, s)
		var rel := to_path * verts[i] - fr.origin
		# The junction is flat: compare in the horizontal plane.
		worst_t = maxf(worst_t, absf(rel.dot(fr.basis.x) - t))
		worst_s = maxf(worst_s, absf(rel.dot(-fr.basis.z)))
		var cls := int(cust[i * 4])
		counts[cls] += 1
		var want_cls := TrackRoadSegment.EDGE_SURFACE if absf(t) <= jn.surface_half_width + 0.001 				else TrackRoadSegment.EDGE_LIP
		# Shared columns at +-surface_half_width belong to either.
		if cls != want_cls and absf(absf(t) - jn.surface_half_width) > 0.001:
			worst_cls += 1
		worst_w = maxf(worst_w, absf(cust[i * 4 + 1] - jn.surface_half_width)
				+ absf(cust[i * 4 + 2] - jn.surface_half_width))
		var tan := to_path.basis * Vector3(tans[i * 4], tans[i * 4 + 1], tans[i * 4 + 2])
		worst_tan = minf(worst_tan, tan.normalized().dot(-fr.basis.z))
		if branch:
			# Strictly inside A's strip (a few mm of clipper rounding allowed)?
			var pa_local := to_a * verts[i]
			var off := _offset_from(pa.curve, pa_local, jn.a_start, jn.a_end)
			if off < jn.road_half_width - 0.005:
				inside_a += 1
				deepest = maxf(deepest, jn.road_half_width - off)
	print("UV2CHECK  %-28s %6d verts  t err %.4f m  s err %.4f m  class errs %d  half width err %.4f m  tangent dot %.5f  inside A %d (deepest %.4f m)  classes %s" % [
			"%s/%s" % [jn.name, mi.name], used.size(), worst_t, worst_s, worst_cls, worst_w, worst_tan,
			inside_a, deepest, counts])
	# s err: a vertex clipped inside a ring quad takes the quad's linear s, as
	# the GPU does between rings, which is off the curve's true s by up to
	# ~|t| / radius / 2 metres: reported, not gated.
	if worst_t > 0.01 or worst_cls > 0 or worst_w > 0.001 or worst_tan < 0.999 			or inside_a > 0 or counts[0] == 0:
		_fails += 1


## |lateral offset| of path-space point `p` from the curve between d0 and d1
## (nearest frame by a coarse-to-fine search).
static func _offset_from(curve: Curve3D, p: Vector3, d0: float, d1: float) -> float:
	var best := d0
	var best_d := INF
	var d := d0
	while d <= d1:
		var q := curve.sample_baked(d, true)
		var dd := Vector2(q.x - p.x, q.z - p.z).length_squared()
		if dd < best_d:
			best_d = dd
			best = d
		d += 2.0
	var lo := maxf(d0, best - 2.0)
	var hi := minf(d1, best + 2.0)
	for k in 40:
		var m1 := lerpf(lo, hi, 0.4)
		var m2 := lerpf(lo, hi, 0.6)
		var q1 := curve.sample_baked(m1, true)
		var q2 := curve.sample_baked(m2, true)
		if Vector2(q1.x - p.x, q1.z - p.z).length_squared() < Vector2(q2.x - p.x, q2.z - p.z).length_squared():
			hi = m2
		else:
			lo = m1
	var fr := TrackRoadSegment.frame_at(curve, (lo + hi) * 0.5)
	var rel := p - fr.origin
	return absf(rel.dot(fr.basis.x))
